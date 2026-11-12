package chat

import (
	"strings"
	"testing"
)

func TestParseCompletionRequest(t *testing.T) {
	t.Run("F-022 AC3 system 메시지는 버리고, 앞쪽 에이전트 인사를 떼고, 음성 말투로 바꾼다", func(t *testing.T) {
		req, err := ParseCompletionRequest([]byte(`{"model":"claude","stream":true,"messages":[
			{"role":"system","content":"엘레븐랩스 대시보드 프롬프트"},
			{"role":"assistant","content":"안녕하세요, 미소예요."},
			{"role":"user","content":"오늘 날씨 어때?"}]}`))
		if err != nil {
			t.Fatal(err)
		}
		if !req.Stream || req.Mode != ModeVoice || len(req.Messages) != 1 || req.Messages[0].Content != "오늘 날씨 어때?" {
			t.Fatalf("req = %+v", req)
		}
		if strings.Contains(req.SystemPrompt(), "대시보드") || !strings.Contains(req.SystemPrompt(), VoiceSystemPrompt) {
			t.Fatalf("system = %q", req.SystemPrompt())
		}
	})

	t.Run("F-022 AC3 extra body의 persona·memory·longTerm·history로 서버가 프롬프트를 만든다", func(t *testing.T) {
		req, err := ParseCompletionRequest([]byte(`{"messages":[{"role":"user","content":[{"type":"text","text":"또 "},{"type":"text","text":"왔어"}]}],
			"elevenlabs_extra_body":{
				"persona":{"name":"미소","role":"노인복지사","base":"천천히 말해요"},
				"memory":[{"summary":"무릎이 아프다고 함","facts":[],"followUps":[]}],
				"longTerm":null,
				"history":[{"role":"user","content":"안녕"},{"role":"assistant","content":"네 안녕하세요"}]}}`))
		if err != nil {
			t.Fatal(err)
		}
		if len(req.Messages) != 3 || req.Messages[2].Content != "또 왔어" || req.Messages[0].Content != "안녕" {
			t.Fatalf("msgs = %+v", req.Messages)
		}
		sys := req.SystemPrompt()
		for _, want := range []string{"미소", "천천히 말해요", "무릎이 아프다고 함", VoiceSystemPrompt} {
			if !strings.Contains(sys, want) {
				t.Fatalf("system에 %q가 없어요: %q", want, sys)
			}
		}
	})

	t.Run("F-022 AC3 형식이 틀리면 API-001과 같은 오류 코드", func(t *testing.T) {
		for body, code := range map[string]string{
			`{"messages":[`: "INVALID_JSON",
			`{}`:            "INVALID_INPUT",
			`{"messages":[{"role":"system","content":"x"}]}`:                                               "EMPTY_MESSAGE",
			`{"messages":[{"role":"user","content":"q"}],"elevenlabs_extra_body":{"persona":{"name":""}}}`: "INVALID_INPUT",
			`{"messages":[{"role":"user","content":"q"}],"elevenlabs_extra_body":{"history":"x"}}`:         "INVALID_INPUT",
		} {
			if _, err := ParseCompletionRequest([]byte(body)); err == nil || err.Code != code {
				t.Fatalf("%s → %v, %s이어야 해요", body, err, code)
			}
		}
	})

	t.Run("F-022 AC3 긴 history는 최근 20턴만 남는다", func(t *testing.T) {
		var b strings.Builder
		b.WriteString(`{"messages":[{"role":"user","content":"마지막"}],"elevenlabs_extra_body":{"history":[`)
		for i := range 30 {
			if i > 0 {
				b.WriteString(",")
			}
			b.WriteString(`{"role":"user","content":"q"},{"role":"assistant","content":"a"}`)
		}
		b.WriteString(`]}}`)
		req, err := ParseCompletionRequest([]byte(b.String()))
		if err != nil {
			t.Fatal(err)
		}
		users := 0
		for _, m := range req.Messages {
			if m.Role == RoleUser {
				users++
			}
		}
		if users != MaxTurns || req.Messages[len(req.Messages)-1].Content != "마지막" {
			t.Fatalf("users=%d", users)
		}
	})
}
