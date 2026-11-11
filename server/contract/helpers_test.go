package contract

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

var baseURL = flag.String("base-url", os.Getenv("CONTRACT_BASE_URL"), "계약 테스트를 실행할 서버 주소 (예: http://127.0.0.1:3000)")

var client = &http.Client{Timeout: 15 * time.Second}

func TestMain(m *testing.M) {
	flag.Parse()
	*baseURL = strings.TrimRight(*baseURL, "/")
	os.Exit(run(m))
}

func run(m *testing.M) int {
	if *baseURL == "" {
		// -base-url이 없으면 chatd를 빌드해 모의 모드로 직접 띄운다 (F-013 AC2)
		url, stop, err := startChatd()
		if err != nil {
			fmt.Fprintln(os.Stderr, "contract:", err)
			return 1
		}
		defer stop()
		*baseURL = url
		fmt.Println("contract: 모의 모드 chatd를 띄웠어요", url)
	}
	// F-009 AC3: 모의 모드가 아니면 채팅 요청을 보내기 전에 멈춘다 (실제 Claude 호출 방지)
	if err := requireMockMode(); err != nil {
		fmt.Fprintln(os.Stderr, "contract:", err)
		return 1
	}
	return m.Run()
}

// startChatd는 cmd/chatd를 임시 폴더에 빌드해 빈 포트에서 띄운다.
// ANTHROPIC_API_KEY는 넘기지 않아 항상 모의 모드다 (실제 Claude 호출 금지).
// 정적 파일은 index.html 하나만 있는 임시 폴더를 쓴다 (S-001 시나리오용).
func startChatd() (string, func(), error) {
	tmp, err := os.MkdirTemp("", "chatd-contract-")
	if err != nil {
		return "", nil, err
	}
	cleanup := func() { os.RemoveAll(tmp) }
	static := filepath.Join(tmp, "web")
	if err := os.Mkdir(static, 0o755); err != nil {
		cleanup()
		return "", nil, err
	}
	if err := os.WriteFile(filepath.Join(static, "index.html"), []byte("<!doctype html><title>contract</title>"), 0o644); err != nil {
		cleanup()
		return "", nil, err
	}
	bin := filepath.Join(tmp, "chatd")
	build := exec.Command("go", "build", "-o", bin, "./cmd/chatd")
	build.Dir = ".." // server/
	build.Env = append(os.Environ(), "CGO_ENABLED=0")
	build.Stdout, build.Stderr = os.Stderr, os.Stderr
	if err := build.Run(); err != nil {
		cleanup()
		return "", nil, fmt.Errorf("chatd 빌드 실패: %w", err)
	}

	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		cleanup()
		return "", nil, err
	}
	port := l.Addr().(*net.TCPAddr).Port
	l.Close()

	var env []string
	for _, kv := range os.Environ() {
		if k, _, _ := strings.Cut(kv, "="); k == "ANTHROPIC_API_KEY" || k == "PORT" || k == "STATIC_DIR" {
			continue
		}
		env = append(env, kv)
	}
	cmd := exec.Command(bin)
	cmd.Env = append(env, fmt.Sprintf("PORT=%d", port), "STATIC_DIR="+static)
	cmd.Stderr = os.Stderr // 요청 로그(stdout)는 버린다
	if err := cmd.Start(); err != nil {
		cleanup()
		return "", nil, err
	}
	stop := func() {
		cmd.Process.Kill()
		cmd.Wait()
		cleanup()
	}
	url := fmt.Sprintf("http://127.0.0.1:%d", port)
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if res, err := client.Get(url + "/api/config"); err == nil {
			res.Body.Close()
			if res.StatusCode == http.StatusOK {
				return url, stop, nil
			}
		}
		time.Sleep(100 * time.Millisecond)
	}
	stop()
	return "", nil, fmt.Errorf("chatd가 10초 안에 뜨지 않았어요")
}

func requireMockMode() error {
	res, err := client.Get(*baseURL + "/api/config")
	if err != nil {
		return fmt.Errorf("서버에 연결할 수 없어요: %w", err)
	}
	defer res.Body.Close()
	var cfg struct {
		Provider string `json:"provider"`
	}
	if err := json.NewDecoder(res.Body).Decode(&cfg); err != nil {
		return fmt.Errorf("/api/config 응답을 읽을 수 없어요: %w", err)
	}
	if cfg.Provider != "mock" {
		return fmt.Errorf("서버가 모의 모드가 아니에요 (provider=%q). ANTHROPIC_API_KEY 없이 서버를 띄워 주세요", cfg.Provider)
	}
	return nil
}

type message struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

// sseEvent는 SSE 이벤트 하나와 도착 시각이다.
type sseEvent struct {
	Name string
	Data map[string]any
	At   time.Time
}

func postChat(t *testing.T, body any) *http.Response {
	t.Helper()
	return postJSON(t, "/api/chat", body)
}

// postJSON은 body(문자열이면 그대로, 아니면 JSON)를 path로 보낸다.
func postJSON(t *testing.T, path string, body any) *http.Response {
	t.Helper()
	var raw []byte
	switch b := body.(type) {
	case string:
		raw = []byte(b)
	default:
		var err error
		if raw, err = json.Marshal(b); err != nil {
			t.Fatal(err)
		}
	}
	res, err := client.Post(*baseURL+path, "application/json", bytes.NewReader(raw))
	if err != nil {
		t.Fatalf("POST %s: %v", path, err)
	}
	t.Cleanup(func() { res.Body.Close() })
	return res
}

func chatBody(msgs ...message) map[string]any {
	return map[string]any{"messages": msgs}
}

// conversation은 user·assistant가 번갈아 오는 turns턴짜리 대화를 만든다 (마지막은 user).
func conversation(turns int) []message {
	var msgs []message
	for i := 1; i <= turns; i++ {
		msgs = append(msgs, message{Role: "user", Content: fmt.Sprintf("질문 %d", i)})
		if i < turns {
			msgs = append(msgs, message{Role: "assistant", Content: fmt.Sprintf("답 %d", i)})
		}
	}
	return msgs
}

// readSSE는 스트림을 끝까지 읽어 이벤트를 도착 순서대로 돌려준다.
func readSSE(t *testing.T, res *http.Response) []sseEvent {
	t.Helper()
	var events []sseEvent
	var name, data string
	r := bufio.NewReader(res.Body)
	for {
		line, err := r.ReadString('\n')
		line = strings.TrimRight(line, "\r\n")
		switch {
		case strings.HasPrefix(line, "event:"):
			name = strings.TrimSpace(strings.TrimPrefix(line, "event:"))
		case strings.HasPrefix(line, "data:"):
			data = strings.TrimSpace(strings.TrimPrefix(line, "data:"))
		case line == "" && (name != "" || data != ""):
			ev := sseEvent{Name: name, At: time.Now()}
			if err := json.Unmarshal([]byte(data), &ev.Data); err != nil {
				t.Fatalf("SSE data가 JSON이 아니에요: %q", data)
			}
			events = append(events, ev)
			name, data = "", ""
		}
		if err == io.EOF {
			return events
		}
		if err != nil {
			t.Fatalf("SSE 읽기 실패: %v", err)
		}
	}
}

// requireStream은 200 SSE 응답을 읽고, 계약(delta 0개 이상 → done 1개로 끝)을 확인한 뒤
// 이벤트와 이어 붙인 응답 문자열을 돌려준다.
func requireStream(t *testing.T, res *http.Response) ([]sseEvent, string) {
	t.Helper()
	if res.StatusCode != http.StatusOK {
		b, _ := io.ReadAll(res.Body)
		t.Fatalf("상태 코드 = %d, 200이어야 해요. 본문: %s", res.StatusCode, b)
	}
	if ct := res.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
		t.Fatalf("Content-Type = %q, text/event-stream이어야 해요", ct)
	}
	events := readSSE(t, res)
	if len(events) == 0 {
		t.Fatal("SSE 이벤트가 없어요")
	}
	var text strings.Builder
	for i, ev := range events {
		last := i == len(events)-1
		switch ev.Name {
		case "delta":
			if last {
				t.Fatal("스트림이 done 없이 delta로 끝났어요")
			}
			s, ok := ev.Data["text"].(string)
			if !ok {
				t.Fatalf("delta data에 text 문자열이 없어요: %v", ev.Data)
			}
			text.WriteString(s)
		case "done":
			if !last {
				t.Fatalf("done 뒤에 이벤트가 더 있어요 (%d번째)", i)
			}
			if s, ok := ev.Data["stopReason"].(string); !ok || s == "" {
				t.Fatalf("done data에 stopReason 문자열이 없어요: %v", ev.Data)
			}
		case "error":
			t.Fatalf("모의 모드에서 error 이벤트가 왔어요: %v", ev.Data)
		default:
			t.Fatalf("알 수 없는 SSE 이벤트 %q", ev.Name)
		}
	}
	return events, text.String()
}

// requireErrorJSON은 오류 응답이 SPEC §9.1 형식 {"error":{"code","message"}}인지 확인한다.
func requireErrorJSON(t *testing.T, res *http.Response, status int) {
	t.Helper()
	b, _ := io.ReadAll(res.Body)
	if res.StatusCode != status {
		t.Fatalf("상태 코드 = %d, %d이어야 해요. 본문: %s", res.StatusCode, status, b)
	}
	if ct := res.Header.Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
		t.Fatalf("Content-Type = %q, application/json이어야 해요", ct)
	}
	var body struct {
		Error *struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal(b, &body); err != nil || body.Error == nil {
		t.Fatalf("오류 JSON 형식이 아니에요: %s", b)
	}
	if body.Error.Code == "" || body.Error.Message == "" {
		t.Fatalf("error.code와 error.message가 비어 있으면 안 돼요: %s", b)
	}
}
