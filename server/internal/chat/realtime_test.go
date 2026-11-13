package chat

import (
	"fmt"
	"strings"
	"testing"
)

func TestVoiceSession(t *testing.T) {
	t.Run("F-024 AC2 지시문은 페르소나 → 기억 → 음성 말투 → 대화 내역 순이다", func(t *testing.T) {
		v, err := ParseVoiceSession([]byte(`{"persona":{"name":"미소","role":"노인복지사","base":"천천히 말해요"},
			"memory":[{"summary":"손주 이야기를 했어요","facts":[],"followUps":[]}],
			"history":[{"role":"assistant","content":"안녕하세요"},{"role":"user","content":"오늘 덥네"},{"role":"assistant","content":"물 드세요"}]}`))
		if err != nil {
			t.Fatal(err)
		}
		ins := v.Instructions()
		order := []string{"미소", "천천히 말해요", "손주 이야기", VoiceSystemPrompt, RealtimeVoicePrompt, historyIntro, "사용자: 오늘 덥네", "당신: 물 드세요"}
		last := -1
		for _, s := range order {
			i := strings.Index(ins, s)
			if i < 0 || i < last {
				t.Fatalf("%q 위치가 틀려요 (%d, 앞 %d)\n%s", s, i, last, ins)
			}
			last = i
		}
		if strings.Contains(ins, "안녕하세요") {
			t.Fatal("첫 사용자 말 앞의 인사는 빼야 해요")
		}
	})

	t.Run("F-024 AC3 빈 본문도 받고, 대화 내역이 없으면 내역 머리말을 붙이지 않는다", func(t *testing.T) {
		v, err := ParseVoiceSession([]byte(`{}`))
		if err != nil {
			t.Fatal(err)
		}
		if ins := v.Instructions(); strings.Contains(ins, historyIntro) || !strings.Contains(ins, VoiceSystemPrompt) {
			t.Fatal(ins)
		}
	})

	t.Run("F-024 AC3 형식 오류는 API-001과 같은 코드", func(t *testing.T) {
		cases := map[string]string{
			`nope`:            "INVALID_JSON",
			`[]`:              "INVALID_INPUT",
			`{"history":"x"}`: "INVALID_INPUT",
			`{"history":[{"role":"system","content":"x"}]}`: "INVALID_INPUT",
			`{"history":[{"role":"user","content":" "}]}`:   "EMPTY_MESSAGE",
			`{"persona":{"name":""}}`:                       "INVALID_INPUT",
			`{"memory":"x"}`:                                "INVALID_INPUT",
		}
		for body, code := range cases {
			if _, err := ParseVoiceSession([]byte(body)); err == nil || err.Code != code {
				t.Errorf("%s → %v, want %s", body, err, code)
			}
		}
	})

	t.Run("F-024 AC2 대화 내역은 최근 20턴만 싣는다", func(t *testing.T) {
		var b strings.Builder
		b.WriteString(`{"history":[`)
		for i := range 30 {
			if i > 0 {
				b.WriteString(",")
			}
			fmt.Fprintf(&b, `{"role":"user","content":"질문%d"},{"role":"assistant","content":"답%d"}`, i, i)
		}
		b.WriteString(`]}`)
		v, err := ParseVoiceSession([]byte(b.String()))
		if err != nil {
			t.Fatal(err)
		}
		if len(v.History) != 2*MaxTurns || v.History[0].Content != "질문10" {
			t.Fatalf("%d %v", len(v.History), v.History[0])
		}
	})
}
