package chat

import (
	"strings"
	"testing"
)

func TestPersona(t *testing.T) {
	t.Run("F-005 AC4 페르소나 프롬프트는 이름·역할·말투·지시·사용자 정보를 담는다", func(t *testing.T) {
		req, err := ParseRequest([]byte(`{"messages":[{"role":"user","content":"q"}],"persona":{"name":" 지은 ","role":"기획 파트너","tones":["차분하게"," 존댓말 "],"instructions":"질문으로 정리","about":"32살 기획자"}}`))
		if err != nil {
			t.Fatal(err)
		}
		got := req.SystemPrompt()
		want := "당신은 사용자와 대화하는 에이전트 \"지은\"예요. 아래 설정에 맞는 인물로서 답하세요.\n" +
			"역할: 기획 파트너\n말투: 차분하게, 존댓말\n사용자가 정한 추가 지시: 질문으로 정리\n" +
			"사용자에 대해 (사용자가 직접 알려 준 정보예요. 대화 맥락으로 참고하되, 묻지 않으면 그대로 되풀이하지 마세요): 32살 기획자"
		if got != want {
			t.Fatalf("got\n%s\nwant\n%s", got, want)
		}
	})

	t.Run("F-005 AC4 빈 필드는 줄을 만들지 않는다", func(t *testing.T) {
		p := &Persona{Name: "친구"}
		if got := p.SystemPrompt(); strings.Contains(got, "\n") || !strings.Contains(got, "\"친구\"") {
			t.Fatalf("got %q", got)
		}
	})

	t.Run("F-005 AC4 voice면 페르소나 뒤에 말하기 지시를 붙이고, 페르소나가 없으면 지금과 같다", func(t *testing.T) {
		p := &Persona{Name: "친구"}
		if got := (Request{Mode: ModeVoice, Persona: p}).SystemPrompt(); got != p.SystemPrompt()+"\n\n"+VoiceSystemPrompt {
			t.Fatalf("got %q", got)
		}
		if got := (Request{Mode: ModeVoice}).SystemPrompt(); got != VoiceSystemPrompt {
			t.Fatalf("got %q", got)
		}
		if got := (Request{Mode: ModeText}).SystemPrompt(); got != "" {
			t.Fatalf("got %q", got)
		}
	})

	t.Run("F-005 AC5 형식이 틀리면 INVALID_INPUT", func(t *testing.T) {
		for _, p := range []string{`null`, `"x"`, `[]`, `{}`, `{"name":""}`, `{"name":null}`, `{"name":"a","tones":null}`,
			`{"name":"a","tones":[null]}`, `{"name":"a","role":null}`, `{"name":"` + strings.Repeat("가", 41) + `"}`,
			`{"name":"a","tones":["1","2","3","4","5","6","7"]}`} {
			_, err := ParseRequest([]byte(`{"messages":[{"role":"user","content":"q"}],"persona":` + p + `}`))
			if err == nil || err.Code != "INVALID_INPUT" {
				t.Fatalf("persona=%s → %v", p, err)
			}
		}
	})
}
