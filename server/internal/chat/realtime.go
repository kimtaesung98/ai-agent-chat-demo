package chat

import (
	"encoding/json"
	"strings"
)

// 실시간 음성 대화(F-024, ARCHITECTURE.md ADR-026): 브라우저가 OpenAI Realtime과 WebRTC로 직접 이야기한다.
// 서버는 연결 전에 앱이 보낸 페르소나·기억·대화 내역으로 지시문(instructions)을 만들어 임시 키 발급 요청에 넣는다.
// 지시문 틀은 서버에만 있다 (ADR-016) — 앱은 임시 키만 받는다 (API-007).

// MaxSessionHistory는 API-007 `history`(이전 연결에서 나눈 말)의 최대 메시지 수다. 더 많으면 앞쪽을 버린다.
const MaxSessionHistory = 2 * MaxTurns

// RealtimeVoicePrompt는 실시간 음성 대화에서 말투 지시 뒤에 붙인다.
const RealtimeVoicePrompt = "사용자는 보통 한국어로 말해요. 처음 연결되면 페르소나답게 짧게 인사하세요. " +
	"사용자가 말하는 도중에는 끼어들지 말고, 말을 끊으면 바로 멈추고 들으세요."

// historyIntro는 지시문 끝에 붙는 지금까지의 대화 머리말이다.
const historyIntro = "지금까지의 대화 (연결이 끊기기 전이나 글 채팅에서 나눈 말이에요. 인사는 다시 하지 말고 이어서 대화하세요):"

// VoiceSession은 검증된 POST /api/voice/session 본문이다 (API-007).
type VoiceSession struct {
	Persona  *Persona
	Memory   []MemoryEntry
	LongTerm *LongTerm
	History  []Message // 오래된 것부터, 비어 있을 수 있음
}

// ParseVoiceSession은 API-007 본문을 검증한다. persona·memory·longTerm은 API-001과 같은 규칙이다.
// 빈 본문 `{}`도 받는다 (페르소나 없이 대화).
func ParseVoiceSession(body []byte) (VoiceSession, *ValidationError) {
	if !json.Valid(body) {
		return VoiceSession{}, invalid("INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
	}
	var root map[string]json.RawMessage
	if json.Unmarshal(body, &root) != nil || root == nil {
		return VoiceSession{}, invalid("INVALID_INPUT", "요청 형식이 올바르지 않아요.")
	}
	var history []Message
	if raw, ok := root["history"]; ok && string(raw) != "null" {
		var list []json.RawMessage
		if json.Unmarshal(raw, &list) != nil {
			return VoiceSession{}, invalid("INVALID_INPUT", "요청 형식이 올바르지 않아요. history 형식을 확인해 주세요.")
		}
		if len(list) > 0 {
			msgs, verr := parseMessages(list)
			if verr != nil {
				return VoiceSession{}, verr
			}
			if len(msgs) > MaxSessionHistory {
				msgs = msgs[len(msgs)-MaxSessionHistory:]
			}
			history = TrimToRecentTurns(msgs, MaxTurns)
			if len(history) > 0 && history[0].Role != RoleUser {
				history = nil // 사용자 말이 없으면(인사뿐) 맥락으로 쓰지 않는다
			}
		}
	}
	// persona·memory·longTerm은 API-001 검증을 그대로 쓴다
	api := map[string]any{"messages": []Message{{Role: RoleUser, Content: "."}}}
	for _, k := range []string{"persona", "memory", "longTerm"} {
		if raw, ok := root[k]; ok && string(raw) != "null" {
			api[k] = raw
		}
	}
	b, _ := json.Marshal(api)
	req, verr := ParseRequest(b)
	if verr != nil {
		return VoiceSession{}, verr
	}
	return VoiceSession{Persona: req.Persona, Memory: req.Memory, LongTerm: req.LongTerm, History: history}, nil
}

// Instructions는 실시간 모델에 넣을 지시문이다: 페르소나 → 지난 대화 기억 → 음성 말투 → 지금까지의 대화.
func (v VoiceSession) Instructions() string {
	base := Request{Mode: ModeVoice, Persona: v.Persona, Memory: v.Memory, LongTerm: v.LongTerm}.SystemPrompt()
	parts := []string{base, RealtimeVoicePrompt}
	if len(v.History) > 0 {
		lines := []string{historyIntro}
		for _, m := range v.History {
			who := "사용자: "
			if m.Role == RoleAssistant {
				who = "당신: "
			}
			lines = append(lines, who+strings.ReplaceAll(m.Content, "\n", " "))
		}
		parts = append(parts, strings.Join(lines, "\n"))
	}
	return strings.Join(parts, "\n\n")
}
