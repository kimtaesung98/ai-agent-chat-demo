package chat

import (
	"strings"
	"testing"
)

func TestF019(t *testing.T) {
	t.Run("F-019 AC1 기본 지시와 사용자 요구 사항이 따로 실리고, 기본 지시가 먼저다", func(t *testing.T) {
		req, err := ParseRequest([]byte(`{"messages":[{"role":"user","content":"q"}],"persona":{"name":"미소","base":" 어르신을 존중해요 ","instructions":"아침마다 혈압약을 챙겨 줘"}}`))
		if err != nil {
			t.Fatal(err)
		}
		got := req.SystemPrompt()
		base := strings.Index(got, personaBaseLabel+"어르신을 존중해요")
		user := strings.Index(got, personaUserLabel+"아침마다 혈압약을 챙겨 줘")
		if base < 0 || user < 0 || base > user {
			t.Fatalf("got\n%s", got)
		}
	})

	t.Run("F-019 AC1 기본 지시가 없으면 추가 지시는 예전 문구 그대로다", func(t *testing.T) {
		p := &Persona{Name: "친구", Instructions: "짧게"}
		if got := p.SystemPrompt(); !strings.Contains(got, "\n"+personaInstrLabel+"짧게") || strings.Contains(got, personaBaseLabel) {
			t.Fatalf("got %q", got)
		}
	})

	t.Run("F-019 AC1 base 형식이 틀리면 INVALID_INPUT", func(t *testing.T) {
		for _, p := range []string{`{"name":"a","base":1}`, `{"name":"a","base":null}`, `{"name":"a","base":"` + strings.Repeat("가", 1001) + `"}`} {
			if _, err := ParseRequest([]byte(`{"messages":[{"role":"user","content":"q"}],"persona":` + p + `}`)); err == nil || err.Code != "INVALID_INPUT" {
				t.Fatalf("persona=%s → %v", p, err)
			}
		}
	})

	t.Run("F-019 AC4 memory는 페르소나 뒤, 말하기 지시 앞에 오래된 것부터 실린다", func(t *testing.T) {
		req, err := ParseRequest([]byte(`{"messages":[{"role":"user","content":"q"}],"mode":"voice","persona":{"name":"미소"},
			"memory":[{"date":"2026-11-09","summary":"산책 이야기","facts":["무릎이 아프심"],"followUps":["병원 다녀오셨는지"]},{"summary":"손주 이야기","unknown":1}]}`))
		if err != nil {
			t.Fatal(err)
		}
		got := req.SystemPrompt()
		want := req.Persona.SystemPrompt() + "\n\n" + memoryIntro +
			"\n- 2026-11-09: 산책 이야기 / 알게 된 점: 무릎이 아프심 / 다음에 이어 갈 것: 병원 다녀오셨는지\n- 손주 이야기\n\n" + VoiceSystemPrompt
		if got != want {
			t.Fatalf("got\n%s\nwant\n%s", got, want)
		}
		if MemoryPrompt(nil) != "" {
			t.Fatal("기억이 없으면 빈 문자열")
		}
	})

	t.Run("F-019 AC4 memory 형식이 틀리면 INVALID_INPUT, 빈 배열은 없는 것과 같다", func(t *testing.T) {
		long := func(n int) string { return strings.Repeat("가", n) }
		six := strings.Repeat(`{"summary":"a"},`, 5) + `{"summary":"a"}`
		for _, m := range []string{`null`, `{}`, `"x"`, `[1]`, `[null]`, `[{}]`, `[{"summary":""}]`, `[{"summary":"` + long(601) + `"}]`,
			`[` + six + `]`, `[{"summary":"a","date":"` + long(21) + `"}]`, `[{"summary":"a","facts":"x"}]`, `[{"summary":"a","facts":[""]}]`,
			`[{"summary":"a","facts":["1","2","3","4","5","6"]}]`, `[{"summary":"a","followUps":["1","2","3","4"]}]`,
			`[{"summary":"a","followUps":["` + long(101) + `"]}]`} {
			if _, err := ParseRequest([]byte(`{"messages":[{"role":"user","content":"q"}],"memory":` + m + `}`)); err == nil || err.Code != "INVALID_INPUT" {
				t.Fatalf("memory=%s → %v", m, err)
			}
		}
		req, err := ParseRequest([]byte(`{"messages":[{"role":"user","content":"q"}],"memory":[]}`))
		if err != nil || req.Memory != nil || req.SystemPrompt() != "" {
			t.Fatalf("%v %v", req.Memory, err)
		}
	})

	t.Run("F-019 AC3 요약 요청은 마지막이 응답이어도 되고 기록 한 덩어리로 넘긴다", func(t *testing.T) {
		req, err := ParseSummaryRequest([]byte(`{"messages":[{"role":"user","content":"안녕\n하세요"},{"role":"assistant","content":"네 어르신"}],"persona":{"name":"미소","role":"노인복지사"}}`))
		if err != nil {
			t.Fatal(err)
		}
		tr := req.Transcript()
		if len(tr) != 1 || tr[0].Role != RoleUser {
			t.Fatalf("%v", tr)
		}
		for _, s := range []string{`"미소"(노인복지사)`, "\n" + TranscriptUser + "안녕 하세요\n", "\n" + TranscriptAgent + "네 어르신\n"} {
			if !strings.Contains(tr[0].Content, s) {
				t.Fatalf("%q 없음:\n%s", s, tr[0].Content)
			}
		}
	})

	t.Run("F-019 AC3 요약 요청 형식 오류", func(t *testing.T) {
		for _, b := range []string{`x`, `{}`, `{"messages":[]}`, `{"messages":[{"role":"assistant","content":"a"}]}`,
			`{"messages":[{"role":"user","content":""}]}`, `{"messages":[{"role":"user","content":"a"}],"persona":{}}`} {
			if _, err := ParseSummaryRequest([]byte(b)); err == nil {
				t.Fatalf("%s 통과", b)
			}
		}
	})

	t.Run("F-019 AC3 모델 답에서 요약을 꺼내고 memory 제한으로 자른다", func(t *testing.T) {
		s, ok := ParseSummary("정리했어요.\n```json\n{\"summary\":\" 산책  이야기 \",\"facts\":[\"a\",1,\"\",\"b\",\"c\",\"d\",\"e\",\"f\"],\"followUps\":[\"" + strings.Repeat("나", 150) + "\"]}\n```")
		if !ok || s.Summary != "산책 이야기" || len(s.Facts) != MaxMemoryFacts || s.Facts[0] != "a" || utf16Len(s.FollowUps[0]) != MaxMemoryItem {
			t.Fatalf("%+v", s)
		}
		s, ok = ParseSummary("JSON이 아닌 답 " + strings.Repeat("다", 700))
		if !ok || utf16Len(s.Summary) != MaxMemorySummary || s.Facts == nil || s.FollowUps == nil {
			t.Fatalf("%+v", s)
		}
		if _, ok := ParseSummary(`{"summary":"  "}`); ok {
			t.Fatal("빈 요약은 실패")
		}
	})
}
