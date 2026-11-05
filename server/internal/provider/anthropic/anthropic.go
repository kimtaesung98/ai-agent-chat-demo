// Package anthropic은 Claude 제공자 어댑터다. 공식 Go SDK는 이 패키지에서만 import한다
// (ARCHITECTURE.md ADR-008). 업스트림 오류는 여기서 사용자용 문장으로 바꾸고,
// 업스트림 원문·API 키는 밖으로 내보내지 않는다.
package anthropic

import (
	"context"
	"errors"
	"iter"

	sdk "github.com/anthropics/anthropic-sdk-go/v2"
	"github.com/anthropics/anthropic-sdk-go/v2/option"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
)

// DefaultMaxTokens는 응답 최대 토큰 수다 (Node와 같음).
const DefaultMaxTokens = 1024

// Options는 Claude 제공자 설정이다.
type Options struct {
	APIKey    string
	Model     string
	MaxTokens int64
	// BaseURL과 MaxRetries는 테스트에서 가짜 업스트림을 쓸 때 바꾼다.
	BaseURL    string
	MaxRetries *int
}

// Provider는 Claude 제공자다.
type Provider struct {
	client    sdk.Client
	model     string
	maxTokens int64
}

// New는 Claude 제공자를 만든다. APIKey는 필수다.
func New(o Options) (*Provider, error) {
	if o.APIKey == "" {
		return nil, errors.New("anthropic: APIKey가 필요해요")
	}
	opts := []option.RequestOption{option.WithAPIKey(o.APIKey)}
	if o.BaseURL != "" {
		opts = append(opts, option.WithBaseURL(o.BaseURL))
	}
	if o.MaxRetries != nil {
		opts = append(opts, option.WithMaxRetries(*o.MaxRetries))
	}
	if o.MaxTokens == 0 {
		o.MaxTokens = DefaultMaxTokens
	}
	return &Provider{client: sdk.NewClient(opts...), model: o.Model, maxTokens: o.MaxTokens}, nil
}

func (p *Provider) Name() string  { return "anthropic" }
func (p *Provider) Model() string { return p.model }

func (p *Provider) Stream(ctx context.Context, msgs []chat.Message) iter.Seq2[provider.Chunk, error] {
	return func(yield func(provider.Chunk, error) bool) {
		params := sdk.MessageNewParams{
			Model:     p.model,
			MaxTokens: p.maxTokens,
			Messages:  toParams(msgs),
		}
		stream := p.client.Messages.NewStreaming(ctx, params)
		defer stream.Close()

		stopReason := "end_turn"
		for stream.Next() {
			ev := stream.Current()
			switch ev.Type {
			case "content_block_delta":
				if ev.Delta.Type == "text_delta" && ev.Delta.Text != "" {
					if !yield(provider.Chunk{Text: ev.Delta.Text}, nil) {
						return
					}
				}
			case "message_delta":
				if ev.Delta.StopReason != "" {
					stopReason = string(ev.Delta.StopReason)
				}
			case "message_stop":
				yield(provider.Chunk{Done: true, StopReason: stopReason}, nil)
				return
			}
			// message_start, content_block_start/stop, 알 수 없는 이벤트 → 무시
		}
		if ctx.Err() != nil {
			return // 클라이언트가 끊음: 오류를 내보내지 않는다
		}
		if err := stream.Err(); err != nil {
			yield(provider.Chunk{}, toError(err))
			return
		}
		// message_stop 없이 끝난 스트림
		yield(provider.Chunk{}, &provider.Error{UserMessage: provider.GenericMessage, Code: "stream_error"})
	}
}

func toParams(msgs []chat.Message) []sdk.MessageParam {
	out := make([]sdk.MessageParam, 0, len(msgs))
	for _, m := range msgs {
		block := sdk.NewTextBlock(m.Content)
		if m.Role == chat.RoleAssistant {
			out = append(out, sdk.NewAssistantMessage(block))
		} else {
			out = append(out, sdk.NewUserMessage(block))
		}
	}
	return out
}

// toError는 SDK 오류를 사용자용 오류로 바꾼다. 원문(err.Error())은 URL과 응답 본문을 담으므로 쓰지 않는다.
func toError(err error) *provider.Error {
	var apiErr *sdk.Error
	if errors.As(err, &apiErr) {
		typ := string(apiErr.Type())
		code := typ
		if code == "" {
			code = "api_error"
		}
		return &provider.Error{UserMessage: provider.UserMessage(apiErr.StatusCode, typ), Status: apiErr.StatusCode, Code: code}
	}
	return &provider.Error{UserMessage: provider.GenericMessage, Code: "network_error"}
}
