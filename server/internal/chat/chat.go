// Package chat은 서버 도메인이다: 메시지, 입력 검증, 최근 턴 정리.
// 순수 함수만 두고 다른 모듈을 import하지 않는다 (ARCHITECTURE.md §3.3).
package chat

import (
	"encoding/json"
	"strings"
	"unicode/utf16"
)

// Role은 메시지 작성자다.
type Role string

const (
	RoleUser      Role = "user"
	RoleAssistant Role = "assistant"
)

// Message는 대화 메시지 하나다 (SPEC.md §7.2 ChatMessage).
type Message struct {
	Role    Role   `json:"role"`
	Content string `json:"content"`
}

// MaxContentLength는 메시지 하나의 최대 길이다. Node 서버와 같게 UTF-16 코드 단위로 센다.
const MaxContentLength = 4000

// MaxTurns는 제공자에 넘기는 최근 턴 수다 (SPEC.md F-002 AC2).
const MaxTurns = 20

// ValidationError는 400 응답으로 바뀌는 입력 오류다. Message는 화면에 그대로 보여도 된다.
type ValidationError struct {
	Code    string
	Message string
}

func (e *ValidationError) Error() string { return e.Code + ": " + e.Message }

func invalid(code, msg string) *ValidationError { return &ValidationError{Code: code, Message: msg} }

// Mode는 답 말투다 (SPEC.md API-001 mode, F-012).
type Mode string

const (
	ModeText  Mode = "text"
	ModeVoice Mode = "voice"
)

// VoiceSystemPrompt는 음성 대화일 때 붙이는 말하기용 답 지시다 (ARCHITECTURE.md ADR-015).
// Node src/server/voice.js와 같은 문장이다.
const VoiceSystemPrompt = "지금은 음성 대화예요. 답은 소리 내어 읽혀요. " +
	"사람과 마주 보고 이야기하듯 자연스러운 구어체로, 보통 한두 문장, 길어도 세 문장 안으로 짧게 답하세요. " +
	"마크다운, 목록, 표, 코드, 이모지, URL은 쓰지 마세요. 숫자와 단위는 소리 내어 읽기 쉽게 쓰세요. " +
	"설명이 길어질 것 같으면 핵심부터 말하고 더 들을지 물어보세요. 사용자가 다른 언어로 말하면 그 언어로 답하세요."

// SystemPrompt는 말투에 맞는 시스템 프롬프트다. 텍스트는 없음.
func (m Mode) SystemPrompt() string {
	if m == ModeVoice {
		return VoiceSystemPrompt
	}
	return ""
}

// Request는 검증된 POST /api/chat 본문이다.
type Request struct {
	Messages []Message
	Mode     Mode
}

// ParseRequest는 POST /api/chat 본문을 검증한다.
// JSON이 아니면 INVALID_JSON, 형식이 틀리면 INVALID_INPUT · EMPTY_MESSAGE · TOO_LONG.
func ParseRequest(body []byte) (Request, *ValidationError) {
	if !json.Valid(body) {
		return Request{}, invalid("INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
	}
	var root map[string]json.RawMessage
	var list []json.RawMessage
	if json.Unmarshal(body, &root) != nil || root == nil || json.Unmarshal(root["messages"], &list) != nil || list == nil {
		return Request{}, invalid("INVALID_INPUT", "요청 형식이 올바르지 않아요. messages 배열이 필요해요.")
	}
	mode := ModeText
	if raw, ok := root["mode"]; ok {
		var s string
		if json.Unmarshal(raw, &s) != nil || (Mode(s) != ModeText && Mode(s) != ModeVoice) {
			return Request{}, invalid("INVALID_INPUT", "요청 형식이 올바르지 않아요. mode는 text 또는 voice여야 해요.")
		}
		mode = Mode(s)
	}
	if len(list) == 0 {
		return Request{}, invalid("EMPTY_MESSAGE", "메시지를 입력해 주세요.")
	}

	msgs := make([]Message, 0, len(list))
	for _, raw := range list {
		var m struct {
			Role    *string `json:"role"`
			Content *string `json:"content"`
		}
		if json.Unmarshal(raw, &m) != nil || m.Role == nil || m.Content == nil {
			return Request{}, invalid("INVALID_INPUT", "메시지 형식이 올바르지 않아요.")
		}
		role := Role(*m.Role)
		if role != RoleUser && role != RoleAssistant {
			return Request{}, invalid("INVALID_INPUT", "메시지 형식이 올바르지 않아요.")
		}
		if strings.TrimSpace(*m.Content) == "" {
			return Request{}, invalid("EMPTY_MESSAGE", "메시지를 입력해 주세요.")
		}
		if utf16Len(*m.Content) > MaxContentLength {
			return Request{}, invalid("TOO_LONG", "메시지는 4,000자까지 보낼 수 있어요.")
		}
		msgs = append(msgs, Message{Role: role, Content: *m.Content})
	}
	if msgs[len(msgs)-1].Role != RoleUser {
		return Request{}, invalid("INVALID_INPUT", "마지막 메시지는 사용자 메시지여야 해요.")
	}
	return Request{Messages: msgs, Mode: mode}, nil
}

// TrimToRecentTurns는 최근 maxTurns개 턴만 남긴다. 턴 = 사용자 메시지 + 그 뒤의 응답.
// 결과는 항상 사용자 메시지로 시작한다 (Node src/server/context.js와 같은 규칙).
func TrimToRecentTurns(msgs []Message, maxTurns int) []Message {
	turns := 0
	for i := len(msgs) - 1; i >= 0; i-- {
		if msgs[i].Role == RoleUser {
			turns++
			if turns == maxTurns {
				return msgs[i:]
			}
		}
	}
	for i, m := range msgs {
		if m.Role == RoleUser {
			return msgs[i:]
		}
	}
	return msgs
}

func utf16Len(s string) int {
	n := 0
	for _, r := range s {
		n += utf16.RuneLen(r)
	}
	return n
}
