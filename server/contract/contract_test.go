package contract

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"
)

// F-001 실시간 스트리밍 채팅 · API-001
func TestF001(t *testing.T) {
	t.Run("F-001 AC1 done 전에 delta가 2개 이상 오고 이어 붙이면 응답이 된다", func(t *testing.T) {
		res := postChat(t, chatBody(message{"user", "안녕하세요"}))
		events, text := requireStream(t, res)
		deltas := 0
		for _, ev := range events {
			if ev.Name == "delta" {
				deltas++
			}
		}
		if deltas < 2 {
			t.Fatalf("delta %d개, 2개 이상이어야 해요", deltas)
		}
		if !strings.Contains(text, "안녕하세요") {
			t.Fatalf("모의 응답에 받은 메시지가 들어 있어야 해요: %q", text)
		}
	})

	t.Run("F-001 AC1 첫 delta는 응답이 끝나기 전에 도착한다 (실제 스트리밍)", func(t *testing.T) {
		res := postChat(t, chatBody(message{"user", "스트리밍 확인"}))
		events, _ := requireStream(t, res)
		first, done := events[0].At, events[len(events)-1].At
		if gap := done.Sub(first); gap < 20*time.Millisecond {
			t.Fatalf("첫 delta와 done 사이가 %v — 한 번에 몰아 보낸 것 같아요", gap)
		}
	})

	t.Run("F-001 AC3 빈 메시지와 공백만 있는 메시지는 400", func(t *testing.T) {
		for _, content := range []string{"", "   ", "\n\t "} {
			requireErrorJSON(t, postChat(t, chatBody(message{"user", content})), http.StatusBadRequest)
		}
		requireErrorJSON(t, postChat(t, chatBody()), http.StatusBadRequest)
	})

	t.Run("F-001 AC4 /api/config는 모의 모드와 모델 이름을 알려 준다", func(t *testing.T) {
		res, err := client.Get(*baseURL + "/api/config")
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		if res.StatusCode != http.StatusOK {
			t.Fatalf("상태 코드 = %d", res.StatusCode)
		}
		var cfg struct {
			Provider string `json:"provider"`
			Model    string `json:"model"`
		}
		if err := json.NewDecoder(res.Body).Decode(&cfg); err != nil {
			t.Fatal(err)
		}
		if cfg.Provider != "mock" || cfg.Model == "" {
			t.Fatalf("config = %+v, provider=mock이고 model이 있어야 해요", cfg)
		}
	})

	t.Run("F-001 AC5 4,000자는 통과하고 4,001자는 400", func(t *testing.T) {
		requireStream(t, postChat(t, chatBody(message{"user", strings.Repeat("가", 4000)})))
		requireErrorJSON(t, postChat(t, chatBody(message{"user", strings.Repeat("가", 4001)})), http.StatusBadRequest)
	})

	t.Run("F-001 예외 잘못된 JSON과 형식이 틀린 messages는 400", func(t *testing.T) {
		cases := map[string]any{
			"JSON 아님":            `{"messages": [`,
			"messages 없음":        map[string]any{},
			"messages가 배열 아님":    map[string]any{"messages": "안녕"},
			"알 수 없는 role":        chatBody(message{"system", "안녕"}),
			"content가 문자열 아님":    map[string]any{"messages": []map[string]any{{"role": "user", "content": 1}}},
			"마지막이 assistant 메시지": chatBody(message{"user", "안녕"}, message{"assistant", "네"}),
		}
		for name, body := range cases {
			t.Run(name, func(t *testing.T) {
				requireErrorJSON(t, postChat(t, body), http.StatusBadRequest)
			})
		}
	})
}

// F-002 대화 맥락 유지 — 모의 제공자는 받은 사용자 메시지 수를 "이 대화의 N번째 질문"으로 알려 준다 (SPEC F-009 참고)
func TestF002(t *testing.T) {
	t.Run("F-002 AC1 이전 대화 내역이 제공자에 전달된다", func(t *testing.T) {
		_, text := requireStream(t, postChat(t, chatBody(conversation(3)...)))
		if !strings.Contains(text, "3번째 질문") || !strings.Contains(text, "질문 3") {
			t.Fatalf("3턴 대화와 마지막 질문이 전달돼야 해요: %q", text)
		}
	})

	t.Run("F-002 AC2 20턴을 넘으면 최근 20턴만 전달된다", func(t *testing.T) {
		for _, turns := range []int{20, 21, 25} {
			_, text := requireStream(t, postChat(t, chatBody(conversation(turns)...)))
			if !strings.Contains(text, "20번째 질문") {
				t.Fatalf("%d턴 대화 → 20턴만 전달돼야 해요: %q", turns, text)
			}
		}
	})
}

// F-012 음성 대화 — API-001 mode 필드. 모의 제공자는 시스템 프롬프트를 쓰지 않으므로 받아들이는지만 본다.
func TestF012(t *testing.T) {
	withMode := func(mode any) map[string]any {
		b := chatBody(message{"user", "음성으로 물어봐요"})
		b["mode"] = mode
		return b
	}

	t.Run("F-012 AC6 mode가 voice나 text면 지금과 같이 스트리밍한다", func(t *testing.T) {
		for _, mode := range []string{"voice", "text"} {
			_, text := requireStream(t, postChat(t, withMode(mode)))
			if !strings.Contains(text, "음성으로 물어봐요") {
				t.Fatalf("mode=%s 응답 = %q", mode, text)
			}
		}
	})

	t.Run("F-012 AC6 mode가 text·voice가 아니면 400", func(t *testing.T) {
		for _, mode := range []any{"VOICE", "audio", "", 1, nil, true} {
			requireErrorJSON(t, postChat(t, withMode(mode)), http.StatusBadRequest)
		}
	})
}

// F-005 페르소나 — API-001 persona 필드. 모의 제공자는 시스템 프롬프트를 쓰지 않으므로 받아들이는지만 본다.
func TestF005(t *testing.T) {
	withPersona := func(persona any) map[string]any {
		b := chatBody(message{"user", "페르소나로 물어봐요"})
		b["persona"] = persona
		return b
	}
	long := func(n int) string { return strings.Repeat("가", n) }
	full := map[string]any{"name": "기획 파트너 지은", "role": "기획 파트너", "tones": []string{"차분하게", "존댓말"}, "instructions": "질문으로 정리해 줘", "about": "32살 기획자예요"}

	t.Run("F-005 AC5 올바른 persona는 지금과 같이 스트리밍한다", func(t *testing.T) {
		for _, p := range []any{
			full,
			map[string]any{"name": "친구"},
			map[string]any{"name": "친구", "tones": []string{}, "role": "", "unknown": 1},
			map[string]any{"name": long(40), "role": long(40), "tones": []string{long(20), "a", "b", "c", "d", "e"}, "instructions": long(1000), "about": long(1000)},
		} {
			_, text := requireStream(t, postChat(t, withPersona(p)))
			if !strings.Contains(text, "페르소나로 물어봐요") {
				t.Fatalf("persona=%v 응답 = %q", p, text)
			}
		}
		b := withPersona(full)
		b["mode"] = "voice"
		requireStream(t, postChat(t, b))
	})

	t.Run("F-005 AC5 persona 형식이 틀리면 400", func(t *testing.T) {
		for _, p := range []any{
			nil, "지은", 1, []any{}, true,
			map[string]any{},
			map[string]any{"name": ""},
			map[string]any{"name": "   "},
			map[string]any{"name": 1},
			map[string]any{"name": nil},
			map[string]any{"name": long(41)},
			map[string]any{"name": "a", "role": long(41)},
			map[string]any{"name": "a", "role": 3},
			map[string]any{"name": "a", "tones": "차분하게"},
			map[string]any{"name": "a", "tones": []any{"a", 1}},
			map[string]any{"name": "a", "tones": []string{""}},
			map[string]any{"name": "a", "tones": []string{long(21)}},
			map[string]any{"name": "a", "tones": []string{"1", "2", "3", "4", "5", "6", "7"}},
			map[string]any{"name": "a", "instructions": long(1001)},
			map[string]any{"name": "a", "about": long(1001)},
			map[string]any{"name": "a", "about": false},
		} {
			requireErrorJSON(t, postChat(t, withPersona(p)), http.StatusBadRequest)
		}
	})
}

func TestF019(t *testing.T) {
	persona := map[string]any{"name": "노인복지사 미소", "base": "어르신을 존중해요", "instructions": "혈압약을 챙겨 줘"}

	t.Run("F-019 AC1·AC4 base와 memory가 있는 요청은 지금과 같이 스트리밍한다", func(t *testing.T) {
		b := chatBody(message{"user", "기억하고 계세요?"})
		b["persona"] = persona
		b["memory"] = []map[string]any{{"date": "2026-11-10", "summary": "산책 이야기를 했어요", "facts": []string{"무릎이 아프심"}, "followUps": []string{}}}
		b["mode"] = "voice"
		if _, text := requireStream(t, postChat(t, b)); !strings.Contains(text, "기억하고 계세요?") {
			t.Fatalf("응답 = %q", text)
		}
	})

	t.Run("F-019 AC4 memory 형식이 틀리면 400", func(t *testing.T) {
		for _, m := range []any{"x", map[string]any{}, []any{1}, []any{map[string]any{"summary": ""}}, []any{map[string]any{"summary": strings.Repeat("가", 601)}}} {
			b := chatBody(message{"user", "q"})
			b["memory"] = m
			requireErrorJSON(t, postChat(t, b), http.StatusBadRequest)
		}
	})

	t.Run("F-019 AC3 POST /api/summary는 끝난 대화를 요약 JSON으로 답한다", func(t *testing.T) {
		res := postJSON(t, "/api/summary", map[string]any{"persona": persona, "messages": []message{
			{"user", "오늘 산책 다녀왔어요"}, {"assistant", "잘하셨어요"}, {"user", "무릎이 좀 아파요"}, {"assistant", "쉬세요"},
		}})
		if res.StatusCode != http.StatusOK || !strings.HasPrefix(res.Header.Get("Content-Type"), "application/json") {
			t.Fatalf("상태 %d, %q", res.StatusCode, res.Header.Get("Content-Type"))
		}
		var got struct {
			Summary   string   `json:"summary"`
			Facts     []string `json:"facts"`
			FollowUps []string `json:"followUps"`
		}
		if err := json.NewDecoder(res.Body).Decode(&got); err != nil {
			t.Fatal(err)
		}
		if got.Summary != `모의 모드 요약이에요. 사용자 말 2개를 나눴어요. 처음 말: "오늘 산책 다녀왔어요"` || got.Facts == nil || got.FollowUps == nil {
			t.Fatalf("%+v", got)
		}
	})

	t.Run("F-019 AC3 /api/summary 형식 오류는 400, GET은 405", func(t *testing.T) {
		for _, b := range []any{"x", map[string]any{"messages": []message{}}, map[string]any{"messages": []message{{"assistant", "a"}}}} {
			requireErrorJSON(t, postJSON(t, "/api/summary", b), http.StatusBadRequest)
		}
		res, err := client.Get(*baseURL + "/api/summary")
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		requireErrorJSON(t, res, http.StatusMethodNotAllowed)
	})
}

// API-001·API-002 공통 계약: 메서드·경로 오류, 정적 화면
func TestAPI(t *testing.T) {
	do := func(t *testing.T, method, path string) *http.Response {
		t.Helper()
		req, err := http.NewRequest(method, *baseURL+path, nil)
		if err != nil {
			t.Fatal(err)
		}
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { res.Body.Close() })
		return res
	}

	t.Run("API-001 GET /api/chat은 405", func(t *testing.T) {
		requireErrorJSON(t, do(t, http.MethodGet, "/api/chat"), http.StatusMethodNotAllowed)
	})
	t.Run("API-002 POST /api/config는 405", func(t *testing.T) {
		requireErrorJSON(t, do(t, http.MethodPost, "/api/config"), http.StatusMethodNotAllowed)
	})
	t.Run("API 없는 경로는 404", func(t *testing.T) {
		requireErrorJSON(t, do(t, http.MethodGet, "/no-such-file.js"), http.StatusNotFound)
		requireErrorJSON(t, do(t, http.MethodGet, "/README.md"), http.StatusNotFound)
	})
	t.Run("S-001 GET /는 채팅 화면 HTML을 준다", func(t *testing.T) {
		res := do(t, http.MethodGet, "/")
		if res.StatusCode != http.StatusOK {
			t.Fatalf("상태 코드 = %d", res.StatusCode)
		}
		if ct := res.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
			t.Fatalf("Content-Type = %q", ct)
		}
	})
}
