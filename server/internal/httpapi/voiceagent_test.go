package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
)

type fakeTokens struct {
	tok string
	err error
}

func (f fakeTokens) ConversationToken(context.Context) (string, error) { return f.tok, f.err }

const testSecret = "test-llm-secret-0123456789"

func startWith(t *testing.T, p provider.Provider, log *bytes.Buffer, opts ...Option) string {
	t.Helper()
	if log == nil {
		log = &bytes.Buffer{}
	}
	srv := httptest.NewServer(New(p, t.TempDir(), slog.New(slog.NewJSONHandler(log, nil)), opts...))
	t.Cleanup(srv.Close)
	return srv.URL
}

func do(t *testing.T, method, url, auth, body string) (*http.Response, string) {
	t.Helper()
	req, _ := http.NewRequest(method, url, strings.NewReader(body))
	if auth != "" {
		req.Header.Set("Authorization", auth)
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	return res, string(b)
}

func done() *fakeProvider {
	return &fakeProvider{stream: chunks([]provider.Chunk{{Text: "네, "}, {Text: "좋아요."}, {Done: true, StopReason: "end_turn"}}, nil)}
}

func TestVoiceToken(t *testing.T) {
	t.Run("F-022 AC2 설정이 없으면 503, API-002 voiceAgent는 none", func(t *testing.T) {
		url := startWith(t, done(), nil)
		res, body := do(t, "POST", url+"/api/voice/token", "", "")
		if res.StatusCode != 503 || !strings.Contains(body, "VOICE_AGENT_OFF") {
			t.Fatalf("%d %s", res.StatusCode, body)
		}
		_, cfg := do(t, "GET", url+"/api/config", "", "")
		if !strings.Contains(cfg, `"voiceAgent":"none"`) {
			t.Fatalf("config = %s", cfg)
		}
	})

	t.Run("F-022 AC2 켜져 있으면 토큰만 주고, API-002 voiceAgent는 elevenlabs", func(t *testing.T) {
		var log bytes.Buffer
		url := startWith(t, done(), &log, WithVoiceAgent(fakeTokens{tok: "tok-비밀"}))
		res, body := do(t, "POST", url+"/api/voice/token", "", "")
		var out map[string]string
		json.Unmarshal([]byte(body), &out)
		if res.StatusCode != 200 || out["conversationToken"] != "tok-비밀" || len(out) != 1 || res.Header.Get("Cache-Control") != "no-store" {
			t.Fatalf("%d %s", res.StatusCode, body)
		}
		_, cfg := do(t, "GET", url+"/api/config", "", "")
		if !strings.Contains(cfg, `"voiceAgent":"elevenlabs"`) {
			t.Fatalf("config = %s", cfg)
		}
		time.Sleep(30 * time.Millisecond)
		if strings.Contains(log.String(), "tok-비밀") {
			t.Fatal("토큰이 로그에 남았어요")
		}
		if res, _ := do(t, "GET", url+"/api/voice/token", "", ""); res.StatusCode != 405 {
			t.Fatalf("GET → %d", res.StatusCode)
		}
	})

	t.Run("F-022 AC2 업스트림 실패는 502와 사용자용 문장", func(t *testing.T) {
		url := startWith(t, done(), nil, WithVoiceAgent(fakeTokens{err: errors.New("xi-key-원문")}))
		res, body := do(t, "POST", url+"/api/voice/token", "", "")
		if res.StatusCode != 502 || strings.Contains(body, "xi-key") || !strings.Contains(body, VoiceUnavailable) {
			t.Fatalf("%d %s", res.StatusCode, body)
		}
	})
}

const completion = `{"model":"x","stream":true,"messages":[{"role":"system","content":"대시보드"},{"role":"user","content":"비밀-본문"}],
	"elevenlabs_extra_body":{"persona":{"name":"미소","about":"비밀-소개"}}}`

func TestCompletions(t *testing.T) {
	t.Run("F-022 AC4 비밀값이 없으면 엔드포인트가 없다(404), 틀린 Bearer는 401", func(t *testing.T) {
		if res, _ := do(t, "POST", startWith(t, done(), nil)+"/v1/chat/completions", "Bearer "+testSecret, completion); res.StatusCode != 404 {
			t.Fatalf("%d", res.StatusCode)
		}
		url := startWith(t, done(), nil, WithLLMSecret(testSecret))
		for _, auth := range []string{"", "Bearer wrong", testSecret, "Bearer " + testSecret + "x"} {
			if res, _ := do(t, "POST", url+"/v1/chat/completions", auth, completion); res.StatusCode != 401 {
				t.Fatalf("auth=%q → %d", auth, res.StatusCode)
			}
		}
	})

	t.Run("F-022 AC3 OpenAI 형식 조각으로 스트리밍하고 [DONE]으로 끝낸다", func(t *testing.T) {
		fp := done()
		url := startWith(t, fp, nil, WithLLMSecret(testSecret))
		res, body := do(t, "POST", url+"/v1/chat/completions", "Bearer "+testSecret, completion)
		if res.StatusCode != 200 || res.Header.Get("Content-Type") != "text/event-stream; charset=utf-8" {
			t.Fatalf("%d %v", res.StatusCode, res.Header)
		}
		var text strings.Builder
		var finish []any
		lines := strings.Split(strings.TrimSpace(body), "\n\n")
		if lines[len(lines)-1] != "data: [DONE]" {
			t.Fatalf("끝이 [DONE]이 아니에요: %q", body)
		}
		for _, l := range lines[:len(lines)-1] {
			var c struct {
				Object  string `json:"object"`
				Choices []struct {
					Delta        map[string]string `json:"delta"`
					FinishReason any               `json:"finish_reason"`
				} `json:"choices"`
			}
			if err := json.Unmarshal([]byte(strings.TrimPrefix(l, "data: ")), &c); err != nil || c.Object != "chat.completion.chunk" {
				t.Fatalf("조각 %q: %v", l, err)
			}
			text.WriteString(c.Choices[0].Delta["content"])
			finish = append(finish, c.Choices[0].FinishReason)
		}
		if text.String() != "네, 좋아요." || finish[len(finish)-1] != "stop" || finish[0] != nil {
			t.Fatalf("text=%q finish=%v", text.String(), finish)
		}
		if !strings.Contains(fp.system, "미소") || strings.Contains(fp.system, "대시보드") || !strings.Contains(fp.system, chat.VoiceSystemPrompt) {
			t.Fatalf("system = %q", fp.system)
		}
	})

	t.Run("F-022 AC3 stream이 false면 chat.completion 하나로 답한다", func(t *testing.T) {
		url := startWith(t, done(), nil, WithLLMSecret(testSecret))
		res, body := do(t, "POST", url+"/v1/chat/completions", "Bearer "+testSecret, `{"messages":[{"role":"user","content":"q"}]}`)
		if res.StatusCode != 200 || !strings.Contains(body, `"content":"네, 좋아요."`) || !strings.Contains(body, `"object":"chat.completion"`) {
			t.Fatalf("%d %s", res.StatusCode, body)
		}
	})

	t.Run("F-022 AC5 제공자 오류는 사용자용 문장을 읽어 주고 원문은 숨긴다", func(t *testing.T) {
		fp := &fakeProvider{stream: chunks(nil, &provider.Error{UserMessage: "요청이 너무 많아요.", Status: 429, Code: "rate_limit-원문"})}
		url := startWith(t, fp, nil, WithLLMSecret(testSecret))
		_, body := do(t, "POST", url+"/v1/chat/completions", "Bearer "+testSecret, completion)
		if !strings.Contains(body, "요청이 너무 많아요.") || strings.Contains(body, "원문") || !strings.HasSuffix(strings.TrimSpace(body), "data: [DONE]") {
			t.Fatalf("body = %s", body)
		}
	})

	t.Run("F-022 AC4 대화 본문·페르소나·비밀값은 로그에 남지 않고, 형식 오류는 400", func(t *testing.T) {
		var log bytes.Buffer
		url := startWith(t, done(), &log, WithLLMSecret(testSecret))
		do(t, "POST", url+"/v1/chat/completions", "Bearer "+testSecret, completion)
		res, _ := do(t, "POST", url+"/v1/chat/completions", "Bearer "+testSecret, `{"messages":[{"role":"system","content":"x"}]}`)
		if res.StatusCode != 400 {
			t.Fatalf("%d", res.StatusCode)
		}
		time.Sleep(30 * time.Millisecond)
		if out := log.String(); strings.Contains(out, "비밀-") || strings.Contains(out, testSecret) {
			t.Fatalf("로그에 남았어요: %s", out)
		}
	})
}
