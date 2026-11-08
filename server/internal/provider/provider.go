// Package provider는 AI 제공자 인터페이스와 사용자용 오류를 정의한다 (ARCHITECTURE.md §4.2).
// httpapi는 이 인터페이스만 알고, 구현(mock · anthropic)은 cmd/chatd가 조립한다.
package provider

import (
	"context"
	"iter"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
)

// Provider는 응답 조각을 순서대로 내보낸다. ctx가 취소되면 오류 없이 즉시 끝난다.
// 실패하면 *Error를 마지막 값으로 내보낸다. system이 비어 있지 않으면 시스템 프롬프트로 쓴다 (F-012).
type Provider interface {
	Name() string  // "mock" | "anthropic"
	Model() string // 표시용 모델 이름
	Stream(ctx context.Context, system string, msgs []chat.Message) iter.Seq2[Chunk, error]
}

// Chunk는 응답 조각 하나다. Done이면 마지막 조각이다.
type Chunk struct {
	Text       string
	Done       bool
	StopReason string
}

// Error는 제공자 오류다. UserMessage는 화면에 그대로 보여도 안전한 문장이어야 하며
// 업스트림 원문이나 API 키를 넣지 않는다.
type Error struct {
	UserMessage string
	Status      int
	Code        string
}

func (e *Error) Error() string { return "provider: " + e.Code }

// UserMessage는 HTTP 상태 코드나 업스트림 오류 타입을 사용자용 문장으로 바꾼다.
// Node src/agent/errors.js toUserMessage와 같은 문장을 쓴다.
func UserMessage(status int, errType string) string {
	switch {
	case status == 401 || errType == "authentication_error":
		return "AI 서비스 인증에 실패했어요. 운영자에게 API 키 설정을 확인해 달라고 알려 주세요."
	case status == 429 || errType == "rate_limit_error":
		return "요청이 너무 많아요. 잠시 후 다시 시도해 주세요."
	case status == 529 || errType == "overloaded_error":
		return "AI 서비스에 일시적인 문제가 있어요. 잠시 후 다시 시도해 주세요."
	case status == 400 || errType == "invalid_request_error":
		return "요청을 처리할 수 없어요. 메시지를 줄이거나 새 대화로 시도해 주세요."
	}
	return GenericMessage
}

// GenericMessage는 원인을 알 수 없는 실패에 쓰는 문장이다.
const GenericMessage = "AI 응답을 받지 못했어요. 잠시 후 다시 시도해 주세요."
