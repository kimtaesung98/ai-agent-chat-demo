package provider

import "testing"

func TestUserMessage(t *testing.T) {
	t.Run("F-004 AC1 상태 코드와 오류 타입을 사용자용 문장으로 바꾼다", func(t *testing.T) {
		cases := []struct {
			status int
			typ    string
			want   string
		}{
			{401, "", "AI 서비스 인증에 실패했어요. 운영자에게 API 키 설정을 확인해 달라고 알려 주세요."},
			{0, "authentication_error", "AI 서비스 인증에 실패했어요. 운영자에게 API 키 설정을 확인해 달라고 알려 주세요."},
			{429, "", "요청이 너무 많아요. 잠시 후 다시 시도해 주세요."},
			{529, "", "AI 서비스에 일시적인 문제가 있어요. 잠시 후 다시 시도해 주세요."},
			{0, "overloaded_error", "AI 서비스에 일시적인 문제가 있어요. 잠시 후 다시 시도해 주세요."},
			{400, "", "요청을 처리할 수 없어요. 메시지를 줄이거나 새 대화로 시도해 주세요."},
			{500, "api_error", GenericMessage},
			{0, "", GenericMessage},
		}
		for _, c := range cases {
			if got := UserMessage(c.status, c.typ); got != c.want {
				t.Errorf("UserMessage(%d, %q) = %q", c.status, c.typ, got)
			}
		}
	})
}
