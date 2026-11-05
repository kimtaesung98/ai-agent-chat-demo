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

// ParseRequest는 POST /api/chat 본문을 검증해 메시지 목록을 돌려준다.
// JSON이 아니면 INVALID_JSON, 형식이 틀리면 INVALID_INPUT · EMPTY_MESSAGE · TOO_LONG.
func ParseRequest(body []byte) ([]Message, *ValidationError) {
	if !json.Valid(body) {
		return nil, invalid("INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
	}
	var root map[string]json.RawMessage
	var list []json.RawMessage
	if json.Unmarshal(body, &root) != nil || root == nil || json.Unmarshal(root["messages"], &list) != nil || list == nil {
		return nil, invalid("INVALID_INPUT", "요청 형식이 올바르지 않아요. messages 배열이 필요해요.")
	}
	if len(list) == 0 {
		return nil, invalid("EMPTY_MESSAGE", "메시지를 입력해 주세요.")
	}

	msgs := make([]Message, 0, len(list))
	for _, raw := range list {
		var m struct {
			Role    *string `json:"role"`
			Content *string `json:"content"`
		}
		if json.Unmarshal(raw, &m) != nil || m.Role == nil || m.Content == nil {
			return nil, invalid("INVALID_INPUT", "메시지 형식이 올바르지 않아요.")
		}
		role := Role(*m.Role)
		if role != RoleUser && role != RoleAssistant {
			return nil, invalid("INVALID_INPUT", "메시지 형식이 올바르지 않아요.")
		}
		if strings.TrimSpace(*m.Content) == "" {
			return nil, invalid("EMPTY_MESSAGE", "메시지를 입력해 주세요.")
		}
		if utf16Len(*m.Content) > MaxContentLength {
			return nil, invalid("TOO_LONG", "메시지는 4,000자까지 보낼 수 있어요.")
		}
		msgs = append(msgs, Message{Role: role, Content: *m.Content})
	}
	if msgs[len(msgs)-1].Role != RoleUser {
		return nil, invalid("INVALID_INPUT", "마지막 메시지는 사용자 메시지여야 해요.")
	}
	return msgs, nil
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
