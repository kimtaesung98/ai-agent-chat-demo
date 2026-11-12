package httpapi

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
)

// 실시간 음성 대화 (F-022, ARCHITECTURE.md ADR-025).
//
//	앱 ── POST /api/voice/token ──▶ chatd ── xi-api-key ──▶ ElevenLabs   (토큰만 앱으로)
//	앱 ◀══ WebRTC 음성 ══▶ ElevenLabs ── POST /v1/chat/completions (Bearer) ──▶ chatd ──▶ Claude

// VoiceUnavailable은 실시간 음성 대화를 쓸 수 없을 때 앱에 보이는 문장이다. 앱은 기기 음성(F-012)으로 돌아간다.
const VoiceUnavailable = "실시간 음성 대화를 시작할 수 없어요. 기기 음성으로 대화할게요."

// handleVoiceToken은 ElevenLabs WebRTC 대화 토큰을 발급해 준다 (API-005). 토큰은 로그에 남기지 않는다.
func (s *server) handleVoiceToken(w http.ResponseWriter, r *http.Request) {
	if s.tokens == nil {
		writeError(w, http.StatusServiceUnavailable, "VOICE_AGENT_OFF", VoiceUnavailable)
		return
	}
	tok, err := s.tokens.ConversationToken(r.Context())
	if err != nil {
		s.log.Warn("voice agent token error") // 원문에 키·주소가 섞일 수 있어 남기지 않는다
		writeError(w, http.StatusBadGateway, "VOICE_AGENT_ERROR", VoiceUnavailable)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, map[string]string{"conversationToken": tok})
}

// authorized는 Bearer 값을 상수 시간으로 비교한다.
func (s *server) authorized(r *http.Request) bool {
	got, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	return ok && subtle.ConstantTimeCompare([]byte(strings.TrimSpace(got)), []byte(s.llmSecret)) == 1
}

// handleCompletions는 ElevenLabs가 부르는 OpenAI 호환 Custom LLM 엔드포인트다 (API-006).
// 앱이 넘긴 페르소나·기억으로 서버가 시스템 프롬프트를 만들고(ADR-016·024), 음성 말투로 Claude 답을 스트리밍한다.
func (s *server) handleCompletions(w http.ResponseWriter, r *http.Request) {
	if s.llmSecret == "" {
		notFound(w, r)
		return
	}
	if !s.authorized(r) {
		writeError(w, http.StatusUnauthorized, "UNAUTHORIZED", "인증이 필요해요.")
		return
	}
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	req, verr := chat.ParseCompletionRequest(body)
	if verr != nil {
		writeError(w, http.StatusBadRequest, verr.Code, verr.Message)
		return
	}
	id := fmt.Sprintf("chatcmpl-%d", time.Now().UnixNano())
	created := time.Now().Unix()
	model := s.provider.Model()
	ctx := r.Context()

	if !req.Stream {
		var text strings.Builder
		for c, err := range s.provider.Stream(ctx, req.SystemPrompt(), req.Messages) {
			if err != nil {
				text.Reset()
				text.WriteString(userMessage(s, err))
				break
			}
			text.WriteString(c.Text)
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"id": id, "object": "chat.completion", "created": created, "model": model,
			"choices": []any{map[string]any{"index": 0, "finish_reason": "stop",
				"message": map[string]string{"role": "assistant", "content": text.String()}}},
		})
		return
	}

	h := w.Header()
	h.Set("Content-Type", "text/event-stream; charset=utf-8")
	h.Set("Cache-Control", "no-cache, no-transform")
	h.Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	rc := http.NewResponseController(w)
	send := func(delta map[string]string, finish any) bool {
		if ctx.Err() != nil {
			return false
		}
		b, _ := json.Marshal(map[string]any{
			"id": id, "object": "chat.completion.chunk", "created": created, "model": model,
			"choices": []any{map[string]any{"index": 0, "delta": delta, "finish_reason": finish}},
		})
		if _, err := fmt.Fprintf(w, "data: %s\n\n", b); err != nil {
			return false
		}
		return rc.Flush() == nil
	}
	if !send(map[string]string{"role": "assistant"}, nil) {
		return
	}
	for c, err := range s.provider.Stream(ctx, req.SystemPrompt(), req.Messages) {
		if err != nil {
			// 음성이라 사용자용 오류 문장을 그대로 읽어 준다 (F-004)
			send(map[string]string{"content": userMessage(s, err)}, nil)
			break
		}
		if c.Done {
			break
		}
		if c.Text != "" && !send(map[string]string{"content": c.Text}, nil) {
			return
		}
	}
	if send(map[string]string{}, "stop") {
		fmt.Fprint(w, "data: [DONE]\n\n")
		rc.Flush()
	}
}

func userMessage(s *server, err error) string {
	var pe *provider.Error
	if errors.As(err, &pe) {
		s.log.Warn("provider error", "code", pe.Code, "status", pe.Status, "route", "completions")
		return pe.UserMessage
	}
	return provider.GenericMessage
}
