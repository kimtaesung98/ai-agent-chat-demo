package chat

import (
	"strings"
	"testing"
)

func TestF020(t *testing.T) {
	t.Run("F-020 AC3 longTerm은 지난 대화 기억 머리에 최근 요약보다 먼저 실린다", func(t *testing.T) {
		req, err := ParseRequest([]byte(`{"messages":[{"role":"user","content":"q"}],
			"longTerm":{"summary":"산책과 손주 이야기를 자주 해요","facts":["무릎이 약함"]},"memory":[{"summary":"어제 이야기"}]}`))
		if err != nil {
			t.Fatal(err)
		}
		want := memoryIntro + "\n" + longTermLabel + "산책과 손주 이야기를 자주 해요\n" + longTermFactsLabel + "무릎이 약함\n- 어제 이야기"
		if got := req.SystemPrompt(); got != want {
			t.Fatalf("got\n%s\nwant\n%s", got, want)
		}
		only, _ := ParseRequest([]byte(`{"messages":[{"role":"user","content":"q"}],"longTerm":{"summary":"장기"}}`))
		if got := only.SystemPrompt(); got != memoryIntro+"\n"+longTermLabel+"장기" {
			t.Fatalf("got %q", got)
		}
	})

	t.Run("F-020 AC3 longTerm 형식이 틀리면 INVALID_INPUT", func(t *testing.T) {
		long := strings.Repeat("가", 1001)
		for _, lt := range []string{`null`, `"x"`, `[]`, `{}`, `{"summary":""}`, `{"summary":"` + long + `"}`,
			`{"summary":"a","facts":"x"}`, `{"summary":"a","facts":["1","2","3","4","5","6","7","8","9","10","11"]}`} {
			if _, err := ParseRequest([]byte(`{"messages":[{"role":"user","content":"q"}],"longTerm":` + lt + `}`)); err == nil || err.Code != "INVALID_INPUT" {
				t.Fatalf("longTerm=%s → %v", lt, err)
			}
		}
	})

	t.Run("F-020 AC1 장기 기억 요청은 이전 장기 기억과 요약을 기록 한 덩어리로 넘긴다", func(t *testing.T) {
		req, err := ParseConsolidateRequest([]byte(`{"persona":{"name":"미소"},"longTerm":{"summary":"예전 이야기","facts":["a"]},
			"sessions":[{"date":"2026-11-01","summary":"첫째"},{"summary":"둘째","followUps":["병원"]}]}`))
		if err != nil {
			t.Fatal(err)
		}
		tr := req.Transcript()
		if len(tr) != 1 || tr[0].Role != RoleUser {
			t.Fatalf("%v", tr)
		}
		for _, s := range []string{`"미소"`, "이전 장기 기억: 예전 이야기\n알고 있는 것: a\n", "\n- 2026-11-01: 첫째\n", "\n- 둘째 / 다음에 이어 갈 것: 병원\n"} {
			if !strings.Contains(tr[0].Content, s) {
				t.Fatalf("%q 없음:\n%s", s, tr[0].Content)
			}
		}
	})

	t.Run("F-020 AC1 장기 기억 요청 형식 오류", func(t *testing.T) {
		many := strings.Repeat(`{"summary":"a"},`, 20) + `{"summary":"a"}`
		for _, b := range []string{`x`, `{}`, `{"sessions":[]}`, `{"sessions":"x"}`, `{"sessions":[` + many + `]}`,
			`{"sessions":[{"summary":"a"}],"longTerm":{}}`, `{"sessions":[{"summary":"a"}],"persona":{}}`} {
			if _, err := ParseConsolidateRequest([]byte(b)); err == nil {
				t.Fatalf("%s 통과", b)
			}
		}
	})

	t.Run("F-020 AC1 모델 답에서 장기 기억을 꺼내고 제한으로 자른다", func(t *testing.T) {
		facts := `"1","2","3","4","5","6","7","8","9","10","11"`
		lt, ok := ParseLongTerm("```json\n{\"summary\":\"" + strings.Repeat("다", 1200) + "\",\"facts\":[" + facts + "]}\n```")
		if !ok || utf16Len(lt.Summary) != MaxLongTermSummary || len(lt.Facts) != MaxLongTermFacts {
			t.Fatalf("%+v", lt)
		}
		if _, ok := ParseLongTerm(`{"summary":""}`); ok {
			t.Fatal("빈 장기 기억은 실패")
		}
	})
}
