// Package httpapi는 HTTP 라우팅, 요청 파싱, SSE 쓰기, 정적 파일 제공을 맡는다.
// provider 인터페이스만 알고 구현(mock · anthropic)은 import하지 않는다 (ARCHITECTURE.md §3.3).
// 계약은 SPEC.md §9 API-001 · API-002이며 server/contract 테스트로 검증한다.
package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path"
	"strings"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
)

// MaxBodyBytes는 POST /api/chat 본문 한도다.
const MaxBodyBytes = 1 << 20

// mimeTypes는 제공하는 정적 파일 종류다. 여기 없는 확장자(문서·소스맵 등)는 404.
// 아래쪽은 Flutter 웹 빌드(ADR-011)에 필요한 파일이다.
var mimeTypes = map[string]string{
	".html": "text/html; charset=utf-8",
	".js":   "text/javascript; charset=utf-8",
	".mjs":  "text/javascript; charset=utf-8",
	".css":  "text/css; charset=utf-8",
	".svg":  "image/svg+xml",
	".json": "application/json; charset=utf-8",
	".wasm": "application/wasm",
	".png":  "image/png",
	".ico":  "image/x-icon",
	".ttf":  "font/ttf",
	".otf":  "font/otf",
	".bin":  "application/octet-stream",
	".frag": "application/octet-stream",
}

type server struct {
	provider provider.Provider
	static   *os.Root // nil이면 정적 파일 없음
	log      *slog.Logger
}

// New는 HTTP 핸들러를 만든다. staticDir를 열 수 없으면 경고를 남기고 정적 파일 요청에 404를 준다.
func New(p provider.Provider, staticDir string, log *slog.Logger) http.Handler {
	s := &server{provider: p, log: log}
	if root, err := os.OpenRoot(staticDir); err == nil {
		s.static = root
	} else {
		log.Warn("정적 파일 폴더를 열 수 없어요", "static_dir", staticDir)
	}

	// 메서드가 틀린 요청도 오류 JSON으로 답하려고 메서드는 핸들러에서 확인한다
	mux := http.NewServeMux()
	mux.HandleFunc("/api/chat", only(http.MethodPost, "POST만 지원해요.", s.handleChat))
	mux.HandleFunc("/api/config", only(http.MethodGet, "GET만 지원해요.", s.handleConfig))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			notFound(w, r)
			return
		}
		s.handleStatic(w, r)
	})
	return withLogging(log, withRecover(log, mux))
}

func only(method, msg string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != method {
			writeError(w, http.StatusMethodNotAllowed, "METHOD_NOT_ALLOWED", msg)
			return
		}
		h(w, r)
	}
}

func (s *server) handleConfig(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"provider": s.provider.Name(), "model": s.provider.Model()})
}

func (s *server) handleChat(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxBodyBytes))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			writeError(w, http.StatusRequestEntityTooLarge, "TOO_LARGE", "요청이 너무 커요.")
			return
		}
		writeError(w, http.StatusBadRequest, "INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
		return
	}
	req, verr := chat.ParseRequest(body)
	if verr != nil {
		writeError(w, http.StatusBadRequest, verr.Code, verr.Message)
		return
	}
	msgs := chat.TrimToRecentTurns(req.Messages, chat.MaxTurns) // F-002 AC2

	h := w.Header()
	h.Set("Content-Type", "text/event-stream; charset=utf-8")
	h.Set("Cache-Control", "no-cache, no-transform")
	h.Set("Connection", "keep-alive")
	h.Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	rc := http.NewResponseController(w)
	rc.Flush()

	// 클라이언트가 끊으면 r.Context()가 취소되고 제공자 호출도 멈춘다 (F-010 AC4)
	ctx := r.Context()
	send := func(event string, data any) bool {
		if ctx.Err() != nil {
			return false
		}
		b, _ := json.Marshal(data)
		if _, err := fmt.Fprintf(w, "event: %s\ndata: %s\n\n", event, b); err != nil {
			return false
		}
		return rc.Flush() == nil
	}

	for c, err := range s.provider.Stream(ctx, req.SystemPrompt(), msgs) {
		if err != nil {
			msg := provider.GenericMessage
			var pe *provider.Error
			if errors.As(err, &pe) {
				msg = pe.UserMessage
				s.log.Warn("provider error", "code", pe.Code, "status", pe.Status)
			}
			send("error", map[string]string{"message": msg})
			return
		}
		var ok bool
		if c.Done {
			ok = send("done", map[string]string{"stopReason": c.StopReason})
		} else {
			ok = send("delta", map[string]string{"text": c.Text})
		}
		if !ok {
			return
		}
	}
}

func (s *server) handleStatic(w http.ResponseWriter, r *http.Request) {
	rel := strings.TrimPrefix(path.Clean("/"+r.URL.Path), "/")
	if rel == "" {
		rel = "index.html"
	}
	mime, ok := mimeTypes[path.Ext(rel)]
	if s.static == nil || !ok {
		notFound(w, r)
		return
	}
	f, err := s.static.Open(rel) // os.Root: 폴더 바깥으로 나가는 경로는 열리지 않음
	if err != nil {
		notFound(w, r)
		return
	}
	defer f.Close()
	content, err := io.ReadAll(f)
	if err != nil {
		notFound(w, r)
		return
	}
	w.Header().Set("Content-Type", mime)
	w.Header().Set("Cache-Control", "no-cache")
	w.WriteHeader(http.StatusOK)
	if r.Method != http.MethodHead {
		w.Write(content)
	}
}

func notFound(w http.ResponseWriter, r *http.Request) {
	writeError(w, http.StatusNotFound, "NOT_FOUND", "찾을 수 없어요.")
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": message}})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	b, _ := json.Marshal(v)
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	w.Write(b)
}
