package httpapi

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/account"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store/sqlite"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/usage"
	"iter"
)

// realProvider는 실제 모드처럼 이름이 mock이 아닌 가짜 제공자다. 불린 횟수를 센다.
type realProvider struct{ calls atomic.Int32 }

func (p *realProvider) Name() string  { return "anthropic" }
func (p *realProvider) Model() string { return "fake" }
func (p *realProvider) Stream(context.Context, string, []chat.Message) iter.Seq2[provider.Chunk, error] {
	p.calls.Add(1)
	return func(yield func(provider.Chunk, error) bool) {
		yield(provider.Chunk{Text: `{"summary":"요약"}`}, nil)
		yield(provider.Chunk{Done: true, StopReason: "end_turn"}, nil)
	}
}

func startAccounts(t *testing.T, p provider.Provider, log *bytes.Buffer, l usage.Limits) (*httptest.Server, string) {
	t.Helper()
	db, err := sqlite.Open("")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	acc := account.New(db)
	_, code, err := acc.Bootstrap(context.Background(), "원장", "")
	if err != nil {
		t.Fatal(err)
	}
	h := New(p, t.TempDir(), slog.New(slog.NewTextHandler(log, nil)),
		WithAccounts(acc, usage.New(db, l, nil), AuthOptions{RequireSession: p.Name() != "mock"}))
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	return srv, code
}

func postJSON(t *testing.T, url, body, cookie string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest("POST", url, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if cookie != "" {
		req.Header.Set("Cookie", cookie)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, res.Body)
	res.Body.Close()
	return res
}

const chatBody = `{"messages":[{"role":"user","content":"안녕하세요"}]}`

func TestF030AC5RealModeClosesSessionlessAI(t *testing.T) {
	p := &realProvider{}
	var log bytes.Buffer
	srv, code := startAccounts(t, p, &log, usage.Limits{UserDailyTurns: 1, AdminDailyTurns: 1})
	for _, path := range []string{"/api/chat", "/api/summary", "/api/consolidate", "/api/voice/session"} {
		if res := postJSON(t, srv.URL+path, chatBody, ""); res.StatusCode != http.StatusUnauthorized {
			t.Errorf("F-030 AC5 세션 없는 %s: %d", path, res.StatusCode)
		}
	}
	if n := p.calls.Load(); n != 0 {
		t.Fatalf("세션 없이 제공자를 %d번 불렀어요", n)
	}

	res := postJSON(t, srv.URL+"/api/auth/code", `{"code":"`+code+`"}`, "")
	cookie := strings.Split(res.Header.Get("Set-Cookie"), ";")[0]
	if res := postJSON(t, srv.URL+"/api/chat", chatBody, cookie); res.StatusCode != 200 {
		t.Fatalf("로그인 뒤 채팅: %d", res.StatusCode)
	}
	if res := postJSON(t, srv.URL+"/api/chat", chatBody, cookie); res.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("F-030 AC4 하루 상한 뒤: %d", res.StatusCode)
	}
	if n := p.calls.Load(); n != 1 {
		t.Fatalf("F-030 AC2 상한을 넘은 요청에 제공자를 불렀어요 (%d번)", n)
	}
	t.Run("F-026 AC9 로그에 코드·토큰이 없다", func(t *testing.T) {
		tok := strings.TrimPrefix(cookie, SessionCookie+"=")
		if strings.Contains(log.String(), code) || strings.Contains(log.String(), tok) {
			t.Fatal("로그에 코드나 세션 토큰이 남았어요")
		}
	})
}

func TestF030MockModeStaysOpen(t *testing.T) {
	var log bytes.Buffer
	srv, _ := startAccounts(t, &fakeProvider{stream: chunks([]provider.Chunk{{Text: "안녕"}, {Done: true}}, nil)}, &log, usage.Defaults)
	if res := postJSON(t, srv.URL+"/api/chat", chatBody, ""); res.StatusCode != 200 {
		t.Fatalf("모의 모드 세션 없는 채팅: %d", res.StatusCode)
	}
}
