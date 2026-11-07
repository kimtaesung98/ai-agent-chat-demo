package chat

import (
	"fmt"
	"strings"
	"testing"
)

func TestParseRequest(t *testing.T) {
	parse := func(t *testing.T, body string) Request {
		t.Helper()
		req, err := ParseRequest([]byte(body))
		if err != nil {
			t.Fatalf("ParseRequest(%s) 오류 %v", body, err)
		}
		return req
	}
	ok := func(t *testing.T, body string) []Message { t.Helper(); return parse(t, body).Messages }
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
	t.Run("F-012 AC6 mode가 없거나 text면 텍스트, voice면 음성", func(t *testing.T) {
		const msgs = `"messages":[{"role":"user","content":"안녕"}]`
		for body, want := range map[string]Mode{
			`{` + msgs + `}`:                ModeText,
			`{` + msgs + `,"mode":"text"}`:  ModeText,
			`{` + msgs + `,"mode":"voice"}`: ModeVoice,
		} {
			if got := parse(t, body).Mode; got != want {
				t.Fatalf("%s → mode %q, %q이어야 해요", body, got, want)
			}
		}
	})
	t.Run("F-012 AC6 mode가 text·voice가 아니면 INVALID_INPUT", func(t *testing.T) {
		const msgs = `"messages":[{"role":"user","content":"안녕"}]`
		for _, mode := range []string{`"VOICE"`, `"audio"`, `""`, `1`, `null`, `true`, `["voice"]`} {
			fail(t, `{`+msgs+`,"mode":`+mode+`}`, "INVALID_INPUT")
		}
	})
	t.Run("F-012 AC6 voice만 말하기용 시스템 프롬프트가 있다", func(t *testing.T) {
		if ModeText.SystemPrompt() != "" {
			t.Fatal("텍스트 모드에는 시스템 프롬프트가 없어야 해요")
		}
		p := ModeVoice.SystemPrompt()
		for _, want := range []string{"음성 대화", "구어체", "마크다운"} {
			if !strings.Contains(p, want) {
				t.Fatalf("음성 프롬프트에 %q가 없어요: %s", want, p)
			}
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
