package httpapi

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"io"
	"iter"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
)

// fakeProvider는 테스트용 제공자다. stream이 응답을 정한다.
type fakeProvider struct {
	stream func(ctx context.Context, msgs []chat.Message) iter.Seq2[provider.Chunk, error]
	system string // 마지막 요청의 시스템 프롬프트
}

func (f *fakeProvider) Name() string  { return "mock" }
func (f *fakeProvider) Model() string { return "fake" }
func (f *fakeProvider) Stream(ctx context.Context, system string, msgs []chat.Message) iter.Seq2[provider.Chunk, error] {
	f.system = system
	return f.stream(ctx, msgs)
}

func chunks(cs []provider.Chunk, err error) func(context.Context, []chat.Message) iter.Seq2[provider.Chunk, error] {
	return func(context.Context, []chat.Message) iter.Seq2[provider.Chunk, error] {
		return func(yield func(provider.Chunk, error) bool) {
			for _, c := range cs {
				if !yield(c, nil) {
					return
				}
			}
			if err != nil {
				yield(provider.Chunk{}, err)
			}
		}
	}
}

func start(t *testing.T, p provider.Provider, log *bytes.Buffer) string {
	t.Helper()
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "index.html"), []byte("<!doctype html><title>chat</title>"), 0o644)
	os.WriteFile(filepath.Join(dir, "app.js"), []byte("console.log(1)"), 0o644)
	os.WriteFile(filepath.Join(dir, "README.md"), []byte("# doc"), 0o644)
	for _, f := range []string{"main.dart.js", "main.dart.js.map", "canvaskit/canvaskit.wasm", "manifest.json", "assets/fonts/MaterialIcons-Regular.otf"} {
		os.MkdirAll(filepath.Join(dir, filepath.Dir(f)), 0o755)
		os.WriteFile(filepath.Join(dir, f), []byte("x"), 0o644)
	}
	os.WriteFile(filepath.Join(filepath.Dir(dir), "secret.js"), []byte("secret"), 0o644)
	if log == nil {
		log = &bytes.Buffer{}
	}
	srv := httptest.NewServer(New(p, dir, slog.New(slog.NewJSONHandler(log, nil))))
	t.Cleanup(srv.Close)
	return srv.URL
}

func post(t *testing.T, url, body string) *http.Response {
	t.Helper()
	res, err := http.Post(url+"/api/chat", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { res.Body.Close() })
	return res
}

const hi = `{"messages":[{"role":"user","content":"비밀-본문-안녕"}]}`

func TestChat(t *testing.T) {
	t.Run("F-001 AC1 조각을 SSE delta로, 끝을 done으로 보낸다", func(t *testing.T) {
		url := start(t, &fakeProvider{stream: chunks([]provider.Chunk{{Text: "안"}, {Text: "녕"}, {Done: true, StopReason: "end_turn"}}, nil)}, nil)
		res := post(t, url, hi)
		b, _ := io.ReadAll(res.Body)
		want := "event: delta\ndata: {\"text\":\"안\"}\n\nevent: delta\ndata: {\"text\":\"녕\"}\n\nevent: done\ndata: {\"stopReason\":\"end_turn\"}\n\n"
		if res.StatusCode != 200 || string(b) != want {
			t.Fatalf("status=%d body=%q", res.StatusCode, b)
		}
		if res.Header.Get("Content-Type") != "text/event-stream; charset=utf-8" || res.Header.Get("X-Accel-Buffering") != "no" {
			t.Fatalf("headers = %v", res.Header)
		}
	})

	t.Run("F-012 AC6 mode가 voice면 말하기용 시스템 프롬프트를 제공자에 넘긴다", func(t *testing.T) {
		for body, want := range map[string]string{
			hi: "",
			`{"messages":[{"role":"user","content":"안녕"}],"mode":"text"}`:  "",
			`{"messages":[{"role":"user","content":"안녕"}],"mode":"voice"}`: chat.VoiceSystemPrompt,
		} {
			fp := &fakeProvider{stream: chunks([]provider.Chunk{{Done: true, StopReason: "end_turn"}}, nil)}
			url := start(t, fp, nil)
			res := post(t, url, body)
			io.ReadAll(res.Body)
			if res.StatusCode != 200 || fp.system != want {
				t.Fatalf("%s → status %d, system %q", body, res.StatusCode, fp.system)
			}
		}
	})

	t.Run("F-005 AC4 persona가 있으면 페르소나 프롬프트를, voice면 그 뒤에 말하기 지시를 넘긴다", func(t *testing.T) {
		persona := `"persona":{"name":"지은","role":"기획 파트너","tones":["차분하게"],"about":"기획자"}`
		p := &chat.Persona{Name: "지은", Role: "기획 파트너", Tones: []string{"차분하게"}, About: "기획자"}
		for body, want := range map[string]string{
			`{"messages":[{"role":"user","content":"안녕"}],` + persona + `}`:                p.SystemPrompt(),
			`{"messages":[{"role":"user","content":"안녕"}],"mode":"voice",` + persona + `}`: p.SystemPrompt() + "\n\n" + chat.VoiceSystemPrompt,
		} {
			fp := &fakeProvider{stream: chunks([]provider.Chunk{{Done: true, StopReason: "end_turn"}}, nil)}
			url := start(t, fp, nil)
			res := post(t, url, body)
			io.ReadAll(res.Body)
			if res.StatusCode != 200 || fp.system != want {
				t.Fatalf("%s → status %d, system %q", body, res.StatusCode, fp.system)
			}
		}
	})

	t.Run("F-005 AC6 persona 내용은 로그에 남지 않는다", func(t *testing.T) {
		var log bytes.Buffer
		url := start(t, &fakeProvider{stream: chunks([]provider.Chunk{{Done: true, StopReason: "end_turn"}}, nil)}, &log)
		io.ReadAll(post(t, url, `{"messages":[{"role":"user","content":"q"}],"persona":{"name":"비밀-이름","about":"비밀-소개"}}`).Body)
		time.Sleep(50 * time.Millisecond)
		if out := log.String(); strings.Contains(out, "비밀-") {
			t.Fatalf("persona가 로그에 남았어요: %s", out)
		}
	})

	t.Run("F-002 AC2 20턴을 넘으면 최근 20턴만 제공자에 넘긴다", func(t *testing.T) {
		var got []chat.Message
		p := &fakeProvider{stream: func(ctx context.Context, msgs []chat.Message) iter.Seq2[provider.Chunk, error] {
			got = msgs
			return chunks([]provider.Chunk{{Done: true, StopReason: "end_turn"}}, nil)(ctx, msgs)
		}}
		url := start(t, p, nil)
		var b strings.Builder
		b.WriteString(`{"messages":[`)
		for i := 0; i < 25; i++ {
			if i > 0 {
				b.WriteString(`,{"role":"assistant","content":"a"},`)
			}
			b.WriteString(`{"role":"user","content":"q"}`)
		}
		b.WriteString(`]}`)
		io.ReadAll(post(t, url, b.String()).Body)
		if len(got) != 39 || got[0].Role != chat.RoleUser {
			t.Fatalf("제공자가 받은 메시지 %d개", len(got))
		}
	})

	t.Run("F-010 AC5·F-004 AC1 제공자 오류는 사용자용 문장의 error 이벤트로 보내고 서버는 계속 동작한다", func(t *testing.T) {
		pe := &provider.Error{UserMessage: "요청이 너무 많아요. 잠시 후 다시 시도해 주세요.", Status: 429, Code: "rate_limit_error"}
		var log bytes.Buffer
		url := start(t, &fakeProvider{stream: chunks([]provider.Chunk{{Text: "앞"}}, pe)}, &log)
		b, _ := io.ReadAll(post(t, url, hi).Body)
		if !strings.HasSuffix(string(b), "event: error\ndata: {\"message\":\"요청이 너무 많아요. 잠시 후 다시 시도해 주세요.\"}\n\n") {
			t.Fatalf("body = %q", b)
		}
		if res := post(t, url, `{}`); res.StatusCode != 400 {
			t.Fatalf("오류 뒤 서버가 응답하지 않아요: %d", res.StatusCode)
		}
		if !strings.Contains(log.String(), "rate_limit_error") {
			t.Fatalf("오류 코드는 로그에 남아야 해요: %s", log.String())
		}
	})

	t.Run("F-010 AC5·F-004 AC3 알 수 없는 오류는 일반 문장으로 감춘다", func(t *testing.T) {
		url := start(t, &fakeProvider{stream: chunks(nil, errors.New("upstream raw secret-detail"))}, nil)
		b, _ := io.ReadAll(post(t, url, hi).Body)
		if strings.Contains(string(b), "secret-detail") || !strings.Contains(string(b), provider.GenericMessage) {
			t.Fatalf("body = %q", b)
		}
	})

	t.Run("F-010 AC4 클라이언트가 끊으면 제공자 ctx가 취소되고 더 쓰지 않는다", func(t *testing.T) {
		canceled := make(chan struct{})
		p := &fakeProvider{stream: func(ctx context.Context, _ []chat.Message) iter.Seq2[provider.Chunk, error] {
			return func(yield func(provider.Chunk, error) bool) {
				if !yield(provider.Chunk{Text: "첫"}, nil) {
					return
				}
				<-ctx.Done()
				close(canceled)
			}
		}}
		var log bytes.Buffer
		url := start(t, p, &log)
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		req, _ := http.NewRequestWithContext(ctx, http.MethodPost, url+"/api/chat", strings.NewReader(hi))
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		line, _ := bufio.NewReader(res.Body).ReadString('\n')
		if line != "event: delta\n" {
			t.Fatalf("첫 줄 = %q", line)
		}
		cancel()
		res.Body.Close()
		select {
		case <-canceled:
		case <-time.After(3 * time.Second):
			t.Fatal("제공자 ctx가 취소되지 않았어요")
		}
	})

	t.Run("F-001 AC3·AC5 입력 오류는 400 오류 JSON, 너무 큰 본문은 413", func(t *testing.T) {
		url := start(t, &fakeProvider{stream: chunks(nil, nil)}, nil)
		for body, code := range map[string]string{
			`{"messages":[{"role":"user","content":"  "}]}`: "EMPTY_MESSAGE",
			`not json`: "INVALID_JSON",
			`{}`:       "INVALID_INPUT",
			`{"messages":[{"role":"user","content":"` + strings.Repeat("a", 4001) + `"}]}`: "TOO_LONG",
		} {
			res := post(t, url, body)
			b, _ := io.ReadAll(res.Body)
			if res.StatusCode != 400 || !strings.Contains(string(b), `"code":"`+code+`"`) {
				t.Fatalf("%s → %d %s", code, res.StatusCode, b)
			}
		}
		res := post(t, url, `{"messages":"`+strings.Repeat("a", MaxBodyBytes)+`"}`)
		if res.StatusCode != http.StatusRequestEntityTooLarge {
			t.Fatalf("큰 본문 → %d", res.StatusCode)
		}
	})

	t.Run("F-010 요청 로그에는 메서드·경로·상태가 남고 메시지 본문은 남지 않는다", func(t *testing.T) {
		var log bytes.Buffer
		url := start(t, &fakeProvider{stream: chunks([]provider.Chunk{{Done: true, StopReason: "end_turn"}}, nil)}, &log)
		io.ReadAll(post(t, url, hi).Body)
		time.Sleep(50 * time.Millisecond) // 핸들러가 로그를 쓰는 시간
		out := log.String()
		if strings.Contains(out, "비밀-본문") {
			t.Fatalf("본문이 로그에 남았어요: %s", out)
		}
		for _, want := range []string{`"method":"POST"`, `"path":"/api/chat"`, `"status":200`, `"request_id":`, `"duration_ms":`} {
			if !strings.Contains(out, want) {
				t.Fatalf("로그에 %s가 없어요: %s", want, out)
			}
		}
	})
}

func TestRoutes(t *testing.T) {
	url := start(t, &fakeProvider{stream: chunks(nil, nil)}, nil)
	get := func(method, path string) (*http.Response, string) {
		req, _ := http.NewRequest(method, url+path, nil)
		res, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		b, _ := io.ReadAll(res.Body)
		return res, string(b)
	}

	t.Run("F-001 AC4 /api/config는 제공자 이름과 모델을 준다", func(t *testing.T) {
		res, b := get("GET", "/api/config")
		if res.StatusCode != 200 || b != `{"model":"fake","provider":"mock"}` {
			t.Fatalf("%d %s", res.StatusCode, b)
		}
	})
	t.Run("F-001 잘못된 메서드는 405, 없는 경로는 404 오류 JSON", func(t *testing.T) {
		for _, c := range []struct {
			method, path string
			status       int
		}{
			{"GET", "/api/chat", 405}, {"PUT", "/api/chat", 405}, {"POST", "/api/config", 405},
			{"GET", "/nope.js", 404}, {"DELETE", "/", 404}, {"GET", "/api/other", 404},
		} {
			res, b := get(c.method, c.path)
			if res.StatusCode != c.status || !strings.HasPrefix(res.Header.Get("Content-Type"), "application/json") || !strings.Contains(b, `"error":{"code":`) {
				t.Errorf("%s %s → %d %s", c.method, c.path, res.StatusCode, b)
			}
		}
	})
	t.Run("F-011 Flutter 웹 빌드 파일을 알맞은 형식으로 준다", func(t *testing.T) {
		for p, ct := range map[string]string{
			"/main.dart.js":                           "text/javascript; charset=utf-8",
			"/canvaskit/canvaskit.wasm":               "application/wasm",
			"/manifest.json":                          "application/json; charset=utf-8",
			"/assets/fonts/MaterialIcons-Regular.otf": "font/otf",
		} {
			if res, _ := get("GET", p); res.StatusCode != 200 || res.Header.Get("Content-Type") != ct {
				t.Errorf("%s → %d %q", p, res.StatusCode, res.Header.Get("Content-Type"))
			}
		}
		if res, _ := get("GET", "/main.dart.js.map"); res.StatusCode != 404 {
			t.Errorf("소스맵은 404여야 해요: %d", res.StatusCode)
		}
	})
	t.Run("F-010 AC3 화면 파일을 주고, 문서 파일과 폴더 바깥은 막는다", func(t *testing.T) {
		if res, b := get("GET", "/"); res.StatusCode != 200 || !strings.HasPrefix(res.Header.Get("Content-Type"), "text/html") || !strings.Contains(b, "chat") {
			t.Fatalf("/ → %d %s", res.StatusCode, b)
		}
		if res, _ := get("GET", "/app.js"); res.StatusCode != 200 || res.Header.Get("Content-Type") != "text/javascript; charset=utf-8" {
			t.Fatalf("/app.js → %d", res.StatusCode)
		}
		for _, p := range []string{"/README.md", "/../secret.js", "/%2e%2e/secret.js", "/..%2fsecret.js"} {
			if res, b := get("GET", p); res.StatusCode != 404 || strings.Contains(b, "secret") {
				t.Errorf("%s → %d %s", p, res.StatusCode, b)
			}
		}
	})
}

func TestSummary(t *testing.T) {
	postSummary := func(t *testing.T, url, body string) (*http.Response, string) {
		t.Helper()
		res, err := http.Post(url+"/api/summary", "application/json", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		b, _ := io.ReadAll(res.Body)
		return res, string(b)
	}
	const conv = `{"messages":[{"role":"user","content":"비밀-본문-산책"},{"role":"assistant","content":"좋아요"}],"persona":{"name":"미소"}}`

	t.Run("F-019 AC3 요약 시스템 프롬프트로 부르고 JSON으로 답하며 본문은 로그에 없다", func(t *testing.T) {
		var log bytes.Buffer
		f := &fakeProvider{stream: chunks([]provider.Chunk{{Text: `{"summary":"산책`}, {Text: ` 이야기","facts":["걷기 좋아함"]}`}, {Done: true}}, nil)}
		res, b := postSummary(t, start(t, f, &log), conv)
		if res.StatusCode != 200 || !strings.HasPrefix(res.Header.Get("Content-Type"), "application/json") ||
			b != `{"summary":"산책 이야기","facts":["걷기 좋아함"],"followUps":[]}` {
			t.Fatalf("%d %s", res.StatusCode, b)
		}
		if f.system != chat.SummarySystemPrompt {
			t.Fatalf("system = %q", f.system)
		}
		if strings.Contains(log.String(), "비밀-본문") || strings.Contains(log.String(), "산책") {
			t.Fatalf("로그에 본문: %s", log.String())
		}
	})

	t.Run("F-019 AC3 제공자 오류는 502 오류 JSON, 형식 오류는 400, GET은 405", func(t *testing.T) {
		f := &fakeProvider{stream: chunks(nil, &provider.Error{UserMessage: "잠시 후 다시", Code: "overloaded_error"})}
		url := start(t, f, nil)
		if res, b := postSummary(t, url, conv); res.StatusCode != 502 || b != `{"error":{"code":"PROVIDER_ERROR","message":"잠시 후 다시"}}` {
			t.Fatalf("%d %s", res.StatusCode, b)
		}
		empty := start(t, &fakeProvider{stream: chunks([]provider.Chunk{{Text: "  "}, {Done: true}}, nil)}, nil)
		if res, b := postSummary(t, empty, conv); res.StatusCode != 502 || !strings.Contains(b, chat.SummaryUnavailable) {
			t.Fatalf("%d %s", res.StatusCode, b)
		}
		if res, _ := postSummary(t, url, `{"messages":[]}`); res.StatusCode != 400 {
			t.Fatalf("%d", res.StatusCode)
		}
		res, err := http.Get(url + "/api/summary")
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		if res.StatusCode != 405 {
			t.Fatalf("%d", res.StatusCode)
		}
	})
}

func TestConsolidate(t *testing.T) {
	post := func(t *testing.T, url, body string) (int, string) {
		t.Helper()
		res, err := http.Post(url+"/api/consolidate", "application/json", strings.NewReader(body))
		if err != nil {
			t.Fatal(err)
		}
		defer res.Body.Close()
		b, _ := io.ReadAll(res.Body)
		return res.StatusCode, string(b)
	}
	const body = `{"sessions":[{"summary":"비밀-요약-산책"}]}`

	t.Run("F-020 AC1 장기 기억 시스템 프롬프트로 부르고 JSON으로 답하며 내용은 로그에 없다", func(t *testing.T) {
		var log bytes.Buffer
		f := &fakeProvider{stream: chunks([]provider.Chunk{{Text: `{"summary":"산책 이야기","facts":["걷기"]}`}, {Done: true}}, nil)}
		status, b := post(t, start(t, f, &log), body)
		if status != 200 || b != `{"summary":"산책 이야기","facts":["걷기"]}` || f.system != chat.ConsolidateSystemPrompt {
			t.Fatalf("%d %s %q", status, b, f.system)
		}
		if strings.Contains(log.String(), "비밀-요약") {
			t.Fatalf("로그에 내용: %s", log.String())
		}
	})

	t.Run("F-020 AC1 제공자 오류는 502, 형식 오류는 400", func(t *testing.T) {
		url := start(t, &fakeProvider{stream: chunks(nil, &provider.Error{UserMessage: "잠시 후", Code: "x"})}, nil)
		if status, b := post(t, url, body); status != 502 || !strings.Contains(b, "PROVIDER_ERROR") {
			t.Fatalf("%d %s", status, b)
		}
		if status, _ := post(t, url, `{"sessions":[]}`); status != 400 {
			t.Fatalf("%d", status)
		}
	})
}
