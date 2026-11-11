package mock

import (
	"context"
	"strings"
	"testing"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
)

func TestMock(t *testing.T) {
	msgs := []chat.Message{{Role: chat.RoleUser, Content: "첫 질문"}, {Role: chat.RoleAssistant, Content: "답"}, {Role: chat.RoleUser, Content: " 안녕하세요 "}}

	t.Run("F-001 AC1 여러 조각으로 나눠 보내고 done으로 끝난다", func(t *testing.T) {
		p := &Provider{}
		var text strings.Builder
		deltas, done := 0, false
		for c, err := range p.Stream(context.Background(), "", msgs) {
			if err != nil {
				t.Fatal(err)
			}
			if done {
				t.Fatal("done 뒤에 조각이 더 왔어요")
			}
			if c.Done {
				done = c.StopReason == "end_turn"
				continue
			}
			deltas++
			text.WriteString(c.Text)
		}
		if deltas < 2 || !done {
			t.Fatalf("deltas=%d done=%v", deltas, done)
		}
		want := "모의 모드 응답이에요. 받은 메시지: \"안녕하세요\"\n지금은 이 대화의 2번째 질문이에요.\nANTHROPIC_API_KEY를 설정하고 서버를 다시 시작하면 실제 Claude가 답해요."
		if text.String() != want {
			t.Fatalf("text = %q", text.String())
		}
	})

	t.Run("F-003 AC2 ctx가 취소되면 오류 없이 바로 멈춘다", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		n := 0
		for c, err := range New().Stream(ctx, "", msgs) {
			if err != nil || c.Done {
				t.Fatalf("취소 뒤에 err=%v done=%v", err, c.Done)
			}
			n++
			cancel()
		}
		if n != 1 {
			t.Fatalf("취소 뒤 조각 %d개", n)
		}
	})

	t.Run("F-001 긴 메시지는 60자로 자르고 말줄임표를 붙인다", func(t *testing.T) {
		got := buildReply([]chat.Message{{Role: chat.RoleUser, Content: strings.Repeat("가", 61)}})
		if !strings.Contains(got, strings.Repeat("가", 60)+"…\"") {
			t.Fatalf("got = %q", got)
		}
	})
}

func TestF019Summary(t *testing.T) {
	t.Run("F-019 AC3 요약 요청이면 사용자 말 수와 첫 말을 담은 요약 JSON을 답한다", func(t *testing.T) {
		req, _ := chat.ParseSummaryRequest([]byte(`{"messages":[{"role":"user","content":"산책 다녀왔어"},{"role":"assistant","content":"좋네요"},{"role":"user","content":"응"}]}`))
		var b strings.Builder
		for c, err := range (&Provider{}).Stream(context.Background(), chat.SummarySystemPrompt, req.Transcript()) {
			if err != nil {
				t.Fatal(err)
			}
			b.WriteString(c.Text)
		}
		s, ok := chat.ParseSummary(b.String())
		if !ok || s.Summary != `모의 모드 요약이에요. 사용자 말 2개를 나눴어요. 처음 말: "산책 다녀왔어"` || len(s.Facts) != 1 {
			t.Fatalf("%q", b.String())
		}
	})
}

func TestF020LongTerm(t *testing.T) {
	t.Run("F-020 AC1 장기 기억 요청이면 묶은 요약 수를 담은 JSON을 답한다", func(t *testing.T) {
		req, _ := chat.ParseConsolidateRequest([]byte(`{"longTerm":{"summary":"예전"},"sessions":[{"summary":"a"},{"summary":"b"},{"summary":"c"}]}`))
		var b strings.Builder
		for c, err := range (&Provider{}).Stream(context.Background(), chat.ConsolidateSystemPrompt, req.Transcript()) {
			if err != nil {
				t.Fatal(err)
			}
			b.WriteString(c.Text)
		}
		lt, ok := chat.ParseLongTerm(b.String())
		if !ok || lt.Summary != "모의 모드 장기 기억이에요. 대화 요약 3개를 묶었어요. 이전 장기 기억도 이어 받았어요." {
			t.Fatalf("%q", b.String())
		}
	})
}
