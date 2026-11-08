package anthropic

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
)

// 가짜 업스트림만 쓴다. 실제 Claude API는 호출하지 않는다 (CLAUDE.md).
const fakeKey = "test-key-not-real"

func sse(w http.ResponseWriter, event string, data string) {
	fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event, data)
	w.(http.Flusher).Flush()
}

func newProvider(t *testing.T, h http.HandlerFunc) *Provider {
	t.Helper()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	zero := 0
	p, err := New(Options{APIKey: fakeKey, Model: "claude-test", BaseURL: srv.URL, MaxRetries: &zero})
	if err != nil {
		t.Fatal(err)
	}
	return p
}

type result struct {
	text   string
	deltas int
	done   *provider.Chunk
	err    error
}

func collect(ctx context.Context, p *Provider, msgs []chat.Message) result {
	var r result
	var b strings.Builder
	for c, err := range p.Stream(ctx, "", msgs) {
		if err != nil {
			r.err = err
			break
		}
		if c.Done {
			r.done = &c
			continue
		}
		r.deltas++
		b.WriteString(c.Text)
	}
	r.text = b.String()
	return r
}

var hello = []chat.Message{{Role: chat.RoleUser, Content: "안녕"}, {Role: chat.RoleAssistant, Content: "네"}, {Role: chat.RoleUser, Content: "또 안녕"}}

func TestStream(t *testing.T) {
	t.Run("F-001 AC1 text_delta를 조각으로 바꾸고 stop_reason을 done에 담는다", func(t *testing.T) {
		var got struct {
			Model     string `json:"model"`
			MaxTokens int    `json:"max_tokens"`
			Stream    bool   `json:"stream"`
			Messages  []struct {
				Role string `json:"role"`
			} `json:"messages"`
		}
		var key string
		p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
			key = r.Header.Get("Authorization")
			if r.URL.Path != "/v1/messages" {
				http.NotFound(w, r)
				return
			}
			body, _ := io.ReadAll(r.Body)
			json.Unmarshal(body, &got)
			w.Header().Set("Content-Type", "text/event-stream")
			sse(w, "message_start", `{"type":"message_start","message":{"id":"m","type":"message","role":"assistant","content":[],"model":"claude-test"}}`)
			sse(w, "content_block_start", `{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}`)
			sse(w, "ping", `{"type":"ping"}`)
			sse(w, "content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"안녕"}}`)
			sse(w, "content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"하세요"}}`)
			sse(w, "content_block_stop", `{"type":"content_block_stop","index":0}`)
			sse(w, "message_delta", `{"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":2}}`)
			sse(w, "message_stop", `{"type":"message_stop"}`)
		})
		r := collect(context.Background(), p, hello)
		if r.err != nil || r.text != "안녕하세요" || r.deltas != 2 || r.done == nil || r.done.StopReason != "max_tokens" {
			t.Fatalf("result = %+v", r)
		}
		if key != "Bearer "+fakeKey || got.Model != "claude-test" || got.MaxTokens != DefaultMaxTokens || !got.Stream {
			t.Fatalf("업스트림 요청 = key:%q %+v", key, got)
		}
		if len(got.Messages) != 3 || got.Messages[0].Role != "user" || got.Messages[1].Role != "assistant" {
			t.Fatalf("F-002 AC1 대화 내역이 순서대로 가야 해요: %+v", got.Messages)
		}
	})

	t.Run("F-012 AC6 system이 있으면 업스트림 요청에 시스템 프롬프트로 보내고, 없으면 보내지 않는다", func(t *testing.T) {
		for _, system := range []string{"", chat.VoiceSystemPrompt} {
			var raw map[string]json.RawMessage
			p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
				body, _ := io.ReadAll(r.Body)
				json.Unmarshal(body, &raw)
				w.Header().Set("Content-Type", "text/event-stream")
				sse(w, "message_start", `{"type":"message_start","message":{"id":"m","type":"message","role":"assistant","content":[],"model":"claude-test"}}`)
				sse(w, "message_stop", `{"type":"message_stop"}`)
			})
			for range p.Stream(context.Background(), system, hello) {
			}
			var blocks []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			}
			sys, has := raw["system"]
			if system == "" {
				if has {
					t.Fatalf("텍스트 모드에 system이 가면 안 돼요: %s", sys)
				}
				continue
			}
			if json.Unmarshal(sys, &blocks) != nil || len(blocks) != 1 || blocks[0].Text != system {
				t.Fatalf("system = %s", sys)
			}
		}
	})

	errCases := []struct {
		name   string
		status int
		body   string
		want   string
	}{
		{"인증 실패 401", 401, `{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key secret-detail"}}`, "AI 서비스 인증에 실패했어요. 운영자에게 API 키 설정을 확인해 달라고 알려 주세요."},
		{"과부하 529", 529, `{"type":"error","error":{"type":"overloaded_error","message":"Overloaded secret-detail"}}`, "AI 서비스에 일시적인 문제가 있어요. 잠시 후 다시 시도해 주세요."},
		{"요청 한도 429", 429, `{"type":"error","error":{"type":"rate_limit_error","message":"secret-detail"}}`, "요청이 너무 많아요. 잠시 후 다시 시도해 주세요."},
		{"서버 오류 500", 500, `{"type":"error","error":{"type":"api_error","message":"secret-detail"}}`, provider.GenericMessage},
	}
	for _, c := range errCases {
		t.Run("F-010 AC5 업스트림 "+c.name+"는 사용자용 문장으로 바뀌고 원문은 숨긴다", func(t *testing.T) {
			p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(c.status)
				io.WriteString(w, c.body)
			})
			r := collect(context.Background(), p, hello)
			var pe *provider.Error
			if !errors.As(r.err, &pe) || pe.UserMessage != c.want || pe.Status != c.status {
				t.Fatalf("err = %#v", r.err)
			}
			for _, s := range []string{pe.UserMessage, pe.Error(), pe.Code} {
				if strings.Contains(s, "secret-detail") || strings.Contains(s, fakeKey) {
					t.Fatalf("업스트림 원문이나 키가 새어 나왔어요: %q", s)
				}
			}
		})
	}

	t.Run("F-010 AC5 스트림 중 error 이벤트는 사용자용 오류가 된다", func(t *testing.T) {
		p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "text/event-stream")
			sse(w, "content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"앞부분"}}`)
			sse(w, "error", `{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}`)
		})
		r := collect(context.Background(), p, hello)
		var pe *provider.Error
		if r.text != "앞부분" || !errors.As(r.err, &pe) || pe.UserMessage != provider.UserMessage(0, "overloaded_error") {
			t.Fatalf("result = %+v", r)
		}
	})

	t.Run("F-010 message_stop 없이 끊긴 스트림은 일반 오류", func(t *testing.T) {
		p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "text/event-stream")
			sse(w, "content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"앞"}}`)
		})
		r := collect(context.Background(), p, hello)
		var pe *provider.Error
		if !errors.As(r.err, &pe) || pe.UserMessage != provider.GenericMessage {
			t.Fatalf("result = %+v", r)
		}
	})

	t.Run("F-010 AC4 ctx가 취소되면 업스트림 요청도 끊기고 오류 없이 끝난다", func(t *testing.T) {
		upstreamDone := make(chan struct{})
		p := newProvider(t, func(w http.ResponseWriter, r *http.Request) {
			defer close(upstreamDone)
			w.Header().Set("Content-Type", "text/event-stream")
			sse(w, "content_block_delta", `{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"첫"}}`)
			<-r.Context().Done() // 클라이언트가 끊을 때까지 대기
		})
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		n := 0
		for c, err := range p.Stream(ctx, "", hello) {
			if err != nil || c.Done {
				t.Fatalf("취소 뒤 err=%v done=%v", err, c.Done)
			}
			n++
			cancel()
		}
		select {
		case <-upstreamDone:
		case <-time.After(3 * time.Second):
			t.Fatal("업스트림 요청이 취소되지 않았어요")
		}
		if n != 1 {
			t.Fatalf("조각 %d개", n)
		}
	})

	t.Run("F-010 연결할 수 없으면 일반 오류", func(t *testing.T) {
		zero := 0
		p, _ := New(Options{APIKey: fakeKey, Model: "m", BaseURL: "http://127.0.0.1:1", MaxRetries: &zero})
		r := collect(context.Background(), p, hello)
		var pe *provider.Error
		if !errors.As(r.err, &pe) || pe.UserMessage != provider.GenericMessage || pe.Code != "network_error" {
			t.Fatalf("result = %+v", r)
		}
	})

	t.Run("F-010 API 키가 없으면 만들 수 없다", func(t *testing.T) {
		if _, err := New(Options{Model: "m"}); err == nil {
			t.Fatal("오류여야 해요")
		}
	})
}
