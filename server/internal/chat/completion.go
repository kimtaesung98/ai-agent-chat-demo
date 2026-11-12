package chat

import (
	"encoding/json"
	"strings"
)

// 실시간 음성 대화(F-022, ARCHITECTURE.md ADR-025): ElevenLabs Agents가 우리 서버를 Custom LLM으로 부른다.
// 요청은 OpenAI Chat Completions 형식이고, 앱이 대화를 시작할 때 넘긴 값은 `elevenlabs_extra_body`로 온다.
// 여기서는 그것을 API-001 본문(messages · persona · memory · longTerm, mode는 항상 voice)으로 바꿔
// ParseRequest로 같은 검증을 거친다 — 시스템 프롬프트 틀은 여전히 서버가 만든다 (ADR-016).

// MaxAgentHistory는 extra body `history`(이전 연결에서 나눈 말, 다시 연결할 때 맥락 유지)의 최대 메시지 수다.
const MaxAgentHistory = 2 * MaxTurns

// CompletionRequest는 검증된 POST /v1/chat/completions 본문이다.
type CompletionRequest struct {
	Request
	Stream bool
}

// ParseCompletionRequest는 OpenAI 형식 본문을 검증해 Request로 바꾼다.
//   - system 메시지는 버린다 — ElevenLabs 에이전트 설정의 프롬프트가 아니라 서버가 만든 프롬프트를 쓴다.
//   - 내용이 빈 메시지(도구 호출 등)는 버린다. content가 조각 배열이면 text 조각만 이어 붙인다.
//   - extra body `history`(앱 대화 내역)를 ElevenLabs 대화 앞에 붙인다.
//   - 앞쪽 에이전트 인사(첫 사용자 말 전)는 TrimToRecentTurns가 떼어 낸다.
func ParseCompletionRequest(body []byte) (CompletionRequest, *ValidationError) {
	if !json.Valid(body) {
		return CompletionRequest{}, invalid("INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
	}
	var in struct {
		Messages []struct {
			Role    string          `json:"role"`
			Content json.RawMessage `json:"content"`
		} `json:"messages"`
		Stream bool                       `json:"stream"`
		Extra  map[string]json.RawMessage `json:"elevenlabs_extra_body"`
	}
	if json.Unmarshal(body, &in) != nil || in.Messages == nil {
		return CompletionRequest{}, invalid("INVALID_INPUT", "요청 형식이 올바르지 않아요. messages 배열이 필요해요.")
	}

	var msgs []Message
	if raw, ok := in.Extra["history"]; ok {
		var h []Message
		if json.Unmarshal(raw, &h) != nil {
			return CompletionRequest{}, invalid("INVALID_INPUT", "요청 형식이 올바르지 않아요. history 형식을 확인해 주세요.")
		}
		if len(h) > MaxAgentHistory {
			h = h[len(h)-MaxAgentHistory:]
		}
		msgs = append(msgs, h...)
	}
	for _, m := range in.Messages {
		role := Role(m.Role)
		if role != RoleUser && role != RoleAssistant {
			continue // system · tool
		}
		if text := contentText(m.Content); strings.TrimSpace(text) != "" {
			msgs = append(msgs, Message{Role: role, Content: cutUTF16(text, MaxContentLength)})
		}
	}
	msgs = TrimToRecentTurns(msgs, MaxTurns)
	if len(msgs) == 0 || msgs[0].Role != RoleUser {
		return CompletionRequest{}, invalid("EMPTY_MESSAGE", "메시지를 입력해 주세요.")
	}

	// API-001 본문으로 바꿔 같은 검증을 거친다
	api := map[string]any{"messages": msgs, "mode": ModeVoice}
	for _, k := range []string{"persona", "memory", "longTerm"} {
		if raw, ok := in.Extra[k]; ok && string(raw) != "null" {
			api[k] = raw
		}
	}
	b, _ := json.Marshal(api)
	req, verr := ParseRequest(b)
	if verr != nil {
		return CompletionRequest{}, verr
	}
	return CompletionRequest{Request: req, Stream: in.Stream}, nil
}

// contentText는 OpenAI content(문자열 또는 [{type:"text", text}] 배열)에서 글만 꺼낸다.
func contentText(raw json.RawMessage) string {
	var s string
	if json.Unmarshal(raw, &s) == nil {
		return s
	}
	var parts []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	}
	if json.Unmarshal(raw, &parts) != nil {
		return ""
	}
	var b strings.Builder
	for _, p := range parts {
		if p.Type == "text" {
			b.WriteString(p.Text)
		}
	}
	return b.String()
}
