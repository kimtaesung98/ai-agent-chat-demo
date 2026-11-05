package chat

import (
	"fmt"
	"strings"
	"testing"
)

func TestParseRequest(t *testing.T) {
	ok := func(t *testing.T, body string) []Message {
		t.Helper()
		msgs, err := ParseRequest([]byte(body))
		if err != nil {
			t.Fatalf("ParseRequest(%s) 오류 %v", body, err)
		}
		return msgs
	}
	fail := func(t *testing.T, body, code string) {
		t.Helper()
		_, err := ParseRequest([]byte(body))
		if err == nil || err.Code != code {
			t.Fatalf("ParseRequest(%s) = %v, %s이어야 해요", body, err, code)
		}
		if err.Message == "" {
			t.Fatal("오류 문장이 비어 있어요")
		}
	}

	t.Run("F-001 정상 요청은 메시지 목록을 돌려준다", func(t *testing.T) {
		msgs := ok(t, `{"messages":[{"role":"user","content":"안녕"},{"role":"assistant","content":"네"},{"role":"user","content":"또"}]}`)
		if len(msgs) != 3 || msgs[2].Content != "또" || msgs[1].Role != RoleAssistant {
			t.Fatalf("msgs = %+v", msgs)
		}
	})
	t.Run("F-001 AC3 빈 메시지와 공백 메시지는 EMPTY_MESSAGE", func(t *testing.T) {
		fail(t, `{"messages":[{"role":"user","content":""}]}`, "EMPTY_MESSAGE")
		fail(t, `{"messages":[{"role":"user","content":" \n\t"}]}`, "EMPTY_MESSAGE")
		fail(t, `{"messages":[]}`, "EMPTY_MESSAGE")
	})
	t.Run("F-001 AC5 4,000자까지 허용하고 넘으면 TOO_LONG (UTF-16 기준)", func(t *testing.T) {
		ok(t, fmt.Sprintf(`{"messages":[{"role":"user","content":%q}]}`, strings.Repeat("가", 4000)))
		fail(t, fmt.Sprintf(`{"messages":[{"role":"user","content":%q}]}`, strings.Repeat("가", 4001)), "TOO_LONG")
		// 이모지는 UTF-16 2단위 → 2,001개면 4,002단위
		fail(t, fmt.Sprintf(`{"messages":[{"role":"user","content":%q}]}`, strings.Repeat("😀", 2001)), "TOO_LONG")
	})
	t.Run("F-001 잘못된 JSON은 INVALID_JSON", func(t *testing.T) {
		fail(t, `{"messages": [`, "INVALID_JSON")
	})
	t.Run("F-001 형식이 틀린 요청은 INVALID_INPUT", func(t *testing.T) {
		for _, body := range []string{
			`null`, `"안녕"`, `[]`, `{}`, `{"messages":"안녕"}`, `{"messages":null}`,
			`{"messages":[null]}`, `{"messages":[{"role":"system","content":"x"}]}`,
			`{"messages":[{"role":"user","content":1}]}`, `{"messages":[{"role":"user"}]}`,
			`{"messages":[{"role":"user","content":"a"},{"role":"assistant","content":"b"}]}`,
		} {
			fail(t, body, "INVALID_INPUT")
		}
	})
}

func conversation(turns int) []Message {
	var msgs []Message
	for i := 1; i <= turns; i++ {
		msgs = append(msgs, Message{RoleUser, fmt.Sprintf("q%d", i)})
		if i < turns {
			msgs = append(msgs, Message{RoleAssistant, fmt.Sprintf("a%d", i)})
		}
	}
	return msgs
}

func TestTrimToRecentTurns(t *testing.T) {
	t.Run("F-002 AC1 한도 이하면 그대로 순서대로 전달", func(t *testing.T) {
		got := TrimToRecentTurns(conversation(3), MaxTurns)
		if len(got) != 5 || got[0].Content != "q1" || got[4].Content != "q3" {
			t.Fatalf("got = %+v", got)
		}
	})
	t.Run("F-002 AC2 20턴을 넘으면 오래된 턴부터 잘라 최근 20턴만", func(t *testing.T) {
		got := TrimToRecentTurns(conversation(25), MaxTurns)
		if len(got) != 39 || got[0].Content != "q6" || got[0].Role != RoleUser || got[len(got)-1].Content != "q25" {
			t.Fatalf("len=%d first=%+v", len(got), got[0])
		}
	})
	t.Run("F-002 AC2 앞쪽 assistant 메시지는 뗀다", func(t *testing.T) {
		got := TrimToRecentTurns([]Message{{RoleAssistant, "x"}, {RoleUser, "q"}}, MaxTurns)
		if len(got) != 1 || got[0].Content != "q" {
			t.Fatalf("got = %+v", got)
		}
	})
}
