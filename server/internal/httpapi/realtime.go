package httpapi

import (
	"net/http"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
)

// 실시간 음성 대화 (F-024, ARCHITECTURE.md ADR-026).
//
//	앱 ── POST /api/voice/session (페르소나·기억·내역) ──▶ chatd ── 지시문 + OPENAI_API_KEY ──▶ OpenAI   (임시 키만 앱으로)
//	브라우저 ◀══ WebRTC 음성 (임시 키) ══▶ OpenAI Realtime

// handleVoiceSession은 지시문을 담은 OpenAI Realtime 임시 키를 발급한다 (API-007).
// 지시문·임시 키·대화 본문은 로그에 남기지 않는다.
func (s *server) handleVoiceSession(w http.ResponseWriter, r *http.Request) {
	if s.realtime == nil {
		writeError(w, http.StatusServiceUnavailable, "VOICE_AGENT_OFF", RealtimeUnavailable)
		return
	}
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	v, verr := chat.ParseVoiceSession(body)
	if verr != nil {
		writeError(w, http.StatusBadRequest, verr.Code, verr.Message)
		return
	}
	sec, err := s.realtime.ClientSecret(r.Context(), v.Instructions())
	if err != nil {
		s.log.Warn("realtime session error") // 원문에 키·주소가 섞일 수 있어 남기지 않는다
		writeError(w, http.StatusBadGateway, "VOICE_AGENT_ERROR", RealtimeUnavailable)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, map[string]any{"clientSecret": sec.Value, "expiresAt": sec.ExpiresAt, "model": sec.Model})
}

// RealtimeUnavailable은 실시간 음성 대화를 쓸 수 없을 때 앱에 보이는 문장이다. 앱은 글 채팅으로 계속한다 (F-024 7).
const RealtimeUnavailable = "지금은 음성 대화를 할 수 없어요. 글로 이야기해 주세요."
