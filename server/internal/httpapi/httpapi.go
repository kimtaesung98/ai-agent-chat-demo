// Package httpapi는 HTTP 라우팅, 요청 파싱, SSE 쓰기, 정적 파일 제공을 맡는다.
// provider 인터페이스만 알고 구현(mock · anthropic)은 import하지 않는다 (ARCHITECTURE.md §3.3).
// 계약은 SPEC.md §9 API-001 · API-002이며 server/contract 테스트로 검증한다.
package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path"
	"strings"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/account"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/usage"
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
	provider  provider.Provider
	static    *os.Root // nil이면 정적 파일 없음
	log       *slog.Logger
	tokens    TokenSource      // nil이면 실시간 음성 대화 없음 (F-022)
	llmSecret string           // 비면 /v1/chat/completions 꺼짐 (F-022)
	realtime  RealtimeSessions // nil이면 OpenAI 실시간 음성 없음 (F-024)

	// 계정 기능 (F-026·F-029·F-030, auth.go). accounts가 nil이면 꺼짐
	accounts *account.Service
	limiter  *usage.Limiter
	authOpts AuthOptions
}

// RealtimeSecret은 브라우저가 OpenAI Realtime에 WebRTC로 붙을 때 쓰는 임시 키다 (F-024, API-007).
type RealtimeSecret struct {
	Value     string
	ExpiresAt int64
	Model     string
}

// RealtimeSessions는 지시문을 담은 임시 키를 발급한다 (F-024, ADR-026). 구현은 internal/openai (조립은 cmd/chatd).
type RealtimeSessions interface {
	ClientSecret(ctx context.Context, instructions string) (RealtimeSecret, error)
}

// WithRealtime은 POST /api/voice/session을 켜고 API-002 voiceAgent를 "openai"로 알린다.
func WithRealtime(rs RealtimeSessions) Option { return func(s *server) { s.realtime = rs } }

// TokenSource는 실시간 음성 대화(ElevenLabs Agents) 토큰을 발급한다 (F-022, ADR-025). 구현은 internal/elevenlabs.
type TokenSource interface {
	ConversationToken(ctx context.Context) (string, error)
}

// Option은 선택 기능을 켠다.
type Option func(*server)

// WithVoiceAgent는 POST /api/voice/token을 켜고 API-002에 voiceAgent를 알린다.
func WithVoiceAgent(ts TokenSource) Option { return func(s *server) { s.tokens = ts } }

// WithLLMSecret은 ElevenLabs가 부르는 Custom LLM 엔드포인트(POST /v1/chat/completions)를 켠다.
// 요청은 `Authorization: Bearer <secret>`이어야 한다.
func WithLLMSecret(secret string) Option { return func(s *server) { s.llmSecret = secret } }

// New는 HTTP 핸들러를 만든다. staticDir를 열 수 없으면 경고를 남기고 정적 파일 요청에 404를 준다.
func New(p provider.Provider, staticDir string, log *slog.Logger, opts ...Option) http.Handler {
	s := &server{provider: p, log: log}
	for _, o := range opts {
		o(s)
	}
	if root, err := os.OpenRoot(staticDir); err == nil {
		s.static = root
	} else {
		log.Warn("정적 파일 폴더를 열 수 없어요", "static_dir", staticDir)
	}

	// 메서드가 틀린 요청도 오류 JSON으로 답하려고 메서드는 핸들러에서 확인한다
	mux := http.NewServeMux()
	mux.HandleFunc("/api/chat", only(http.MethodPost, "POST만 지원해요.", s.handleChat))
	mux.HandleFunc("/api/summary", only(http.MethodPost, "POST만 지원해요.", s.handleSummary))
	mux.HandleFunc("/api/consolidate", only(http.MethodPost, "POST만 지원해요.", s.handleConsolidate))
	mux.HandleFunc("/api/config", only(http.MethodGet, "GET만 지원해요.", s.handleConfig))
	mux.HandleFunc("/api/voice/session", only(http.MethodPost, "POST만 지원해요.", s.handleVoiceSession))
	mux.HandleFunc("/api/voice/token", only(http.MethodPost, "POST만 지원해요.", s.handleVoiceToken))
	mux.HandleFunc("/v1/chat/completions", only(http.MethodPost, "POST만 지원해요.", s.handleCompletions))
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			notFound(w, r)
			return
		}
		s.handleStatic(w, r)
	})
	var h http.Handler = mux
	if s.accounts != nil {
		h = s.withAccounts(mux)
	}
	return withLogging(log, withRecover(log, h))
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
	voice := "none"
	switch {
	case s.realtime != nil:
		voice = "openai"
	case s.tokens != nil:
		voice = "elevenlabs"
	}
	writeJSON(w, http.StatusOK, map[string]string{"provider": s.provider.Name(), "model": s.provider.Model(), "voiceAgent": voice})
}

// readBody는 본문을 MaxBodyBytes까지 읽는다. 실패하면 오류 응답을 쓰고 false.
func readBody(w http.ResponseWriter, r *http.Request) ([]byte, bool) {
	body, err := io.ReadAll(http.MaxBytesReader(w, r.Body, MaxBodyBytes))
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			writeError(w, http.StatusRequestEntityTooLarge, "TOO_LARGE", "요청이 너무 커요.")
			return nil, false
		}
		writeError(w, http.StatusBadRequest, "INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
		return nil, false
	}
	return body, true
}

// handleSummary는 끝난 대화 세션을 요약해 JSON으로 답한다 (API-003, F-019). 스트리밍하지 않는다.
// 요약은 저장하지 않고 로그에도 남기지 않는다 — 앱이 기기에 저장한다 (ADR-024).
func (s *server) handleSummary(w http.ResponseWriter, r *http.Request) {
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	req, verr := chat.ParseSummaryRequest(body)
	if verr != nil {
		writeError(w, http.StatusBadRequest, verr.Code, verr.Message)
		return
	}
	text, ok := s.collect(w, r, "summary", chat.SummarySystemPrompt, req.Transcript())
	if !ok {
		return
	}
	sum, ok := chat.ParseSummary(text)
	if !ok {
		writeError(w, http.StatusBadGateway, "PROVIDER_ERROR", chat.SummaryUnavailable)
		return
	}
	writeJSON(w, http.StatusOK, sum)
}

// handleConsolidate는 이전 장기 기억과 오래된 요약을 장기 기억 하나로 묶는다 (API-004, F-020). 저장·로그 없음.
func (s *server) handleConsolidate(w http.ResponseWriter, r *http.Request) {
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	req, verr := chat.ParseConsolidateRequest(body)
	if verr != nil {
		writeError(w, http.StatusBadRequest, verr.Code, verr.Message)
		return
	}
	text, ok := s.collect(w, r, "consolidate", chat.ConsolidateSystemPrompt, req.Transcript())
	if !ok {
		return
	}
	lt, ok := chat.ParseLongTerm(text)
	if !ok {
		writeError(w, http.StatusBadGateway, "PROVIDER_ERROR", chat.SummaryUnavailable)
		return
	}
	writeJSON(w, http.StatusOK, lt)
}

// collect는 제공자 답을 끝까지 모은다. 제공자 오류면 502를 쓰고, 클라이언트가 끊으면 아무것도 쓰지 않고 false.
func (s *server) collect(w http.ResponseWriter, r *http.Request, route, system string, msgs []chat.Message) (string, bool) {
	ctx := r.Context()
	var text strings.Builder
	for c, err := range s.provider.Stream(ctx, system, msgs) {
		if err != nil {
			msg := provider.GenericMessage
			var pe *provider.Error
			if errors.As(err, &pe) {
				msg = pe.UserMessage
				s.log.Warn("provider error", "code", pe.Code, "status", pe.Status, "route", route)
			}
			writeError(w, http.StatusBadGateway, "PROVIDER_ERROR", msg)
			return "", false
		}
		text.WriteString(c.Text)
	}
	if ctx.Err() != nil {
		return "", false // 클라이언트가 끊음
	}
	return text.String(), true
}

func (s *server) handleChat(w http.ResponseWriter, r *http.Request) {
	body, ok := readBody(w, r)
	if !ok {
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
