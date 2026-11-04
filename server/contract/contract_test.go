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
