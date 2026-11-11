// Package mock은 API 키 없이 시연·테스트하기 위한 모의 제공자다 (ARCHITECTURE.md ADR-003).
// 계약 테스트가 "이 대화의 N번째 질문"으로
// 전달된 턴 수를 확인하므로 문구를 바꾸면 안 된다 (SPEC.md F-009 참고).
package mock

import (
	"context"
	"encoding/json"
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

// Stream은 system을 쓰지 않는다 — 계약 테스트가 보는 답 문구가 모드와 상관없이 같아야 한다.
// 예외: 요약 요청(chat.SummarySystemPrompt)·장기 기억 요청(chat.ConsolidateSystemPrompt)이면 정해진 모양의 JSON을 답한다 (F-019·F-020).
func (p *Provider) Stream(ctx context.Context, system string, msgs []chat.Message) iter.Seq2[provider.Chunk, error] {
	return func(yield func(provider.Chunk, error) bool) {
		text := buildReply(msgs)
		switch system {
		case chat.SummarySystemPrompt:
			text = buildSummary(msgs)
		case chat.ConsolidateSystemPrompt:
			text = buildLongTerm(msgs)
		}
		reply := []rune(text)
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

// buildSummary는 대화 기록(chat.SummaryRequest.Transcript)에서 사용자 말 수와 첫 말을 세어 요약 JSON을 만든다.
// 계약 테스트가 "사용자 말 N개"로 넘긴 기록을 확인하므로 문구를 바꾸면 안 된다.
func buildSummary(msgs []chat.Message) string {
	var first string
	n := 0
	if len(msgs) > 0 {
		for _, line := range strings.Split(msgs[len(msgs)-1].Content, "\n") {
			if rest, ok := strings.CutPrefix(line, chat.TranscriptUser); ok {
				if n == 0 {
					first = rest
				}
				n++
			}
		}
	}
	b, _ := json.Marshal(map[string]any{
		"summary":   fmt.Sprintf("모의 모드 요약이에요. 사용자 말 %d개를 나눴어요. 처음 말: \"%s\"", n, truncate(first, 40)),
		"facts":     []string{"모의 모드에서 나눈 대화예요."},
		"followUps": []string{},
	})
	return string(b)
}

// buildLongTerm은 장기 기억 기록(chat.ConsolidateRequest.Transcript)에서 묶은 요약 수를 세어 장기 기억 JSON을 만든다.
// 계약 테스트가 "대화 요약 N개"로 확인하므로 문구를 바꾸면 안 된다.
func buildLongTerm(msgs []chat.Message) string {
	n, carried := 0, false
	if len(msgs) > 0 {
		for _, line := range strings.Split(msgs[len(msgs)-1].Content, "\n") {
			if strings.HasPrefix(line, chat.ConsolidateTranscriptItem) {
				n++
			}
			carried = carried || strings.HasPrefix(line, "이전 장기 기억: ")
		}
	}
	summary := fmt.Sprintf("모의 모드 장기 기억이에요. 대화 요약 %d개를 묶었어요.", n)
	if carried {
		summary += " 이전 장기 기억도 이어 받았어요."
	}
	b, _ := json.Marshal(map[string]any{"summary": summary, "facts": []string{"모의 모드에서 나눈 대화예요."}})
	return string(b)
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
