// Package mock은 API 키 없이 시연·테스트하기 위한 모의 제공자다 (ARCHITECTURE.md ADR-003).
// 답 문구는 Node src/agent/mock.js와 같다. 계약 테스트가 "이 대화의 N번째 질문"으로
// 전달된 턴 수를 확인하므로 문구를 바꾸면 안 된다 (SPEC.md F-009 참고).
package mock

import (
	"context"
	"fmt"
	"iter"
	"strings"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
)

const chunkSize = 4 // 글자 수

// Provider는 모의 제공자다.
type Provider struct {
	ChunkDelay time.Duration
}

// New는 조각 사이 지연이 30ms인 모의 제공자를 만든다.
func New() *Provider { return &Provider{ChunkDelay: 30 * time.Millisecond} }

func (p *Provider) Name() string  { return "mock" }
func (p *Provider) Model() string { return "mock-echo" }

func (p *Provider) Stream(ctx context.Context, msgs []chat.Message) iter.Seq2[provider.Chunk, error] {
	return func(yield func(provider.Chunk, error) bool) {
		reply := []rune(buildReply(msgs))
		for i := 0; i < len(reply); i += chunkSize {
			if !sleep(ctx, p.ChunkDelay) {
				return
			}
			end := min(i+chunkSize, len(reply))
			if !yield(provider.Chunk{Text: string(reply[i:end])}, nil) {
				return
			}
		}
		yield(provider.Chunk{Done: true, StopReason: "end_turn"}, nil)
	}
}

func buildReply(msgs []chat.Message) string {
	var last string
	turns := 0
	for _, m := range msgs {
		if m.Role == chat.RoleUser {
			turns++
			last = m.Content
		}
	}
	return strings.Join([]string{
		fmt.Sprintf("모의 모드 응답이에요. 받은 메시지: \"%s\"", truncate(strings.TrimSpace(last), 60)),
		fmt.Sprintf("지금은 이 대화의 %d번째 질문이에요.", turns),
		"ANTHROPIC_API_KEY를 설정하고 서버를 다시 시작하면 실제 Claude가 답해요.",
	}, "\n")
}

func truncate(s string, max int) string {
	r := []rune(s)
	if len(r) > max {
		return string(r[:max]) + "…"
	}
	return s
}

// sleep은 d만큼 기다린다. ctx가 먼저 취소되면 false.
func sleep(ctx context.Context, d time.Duration) bool {
	if ctx.Err() != nil {
		return false
	}
	if d <= 0 {
		return true
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-t.C:
		return true
	case <-ctx.Done():
		return false
	}
}
