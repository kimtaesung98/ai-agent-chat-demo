package contract

import (
	"strings"
	"testing"
)

// F-028 대화·요약·기억 서버 처리 계약 테스트 (API-017·018). 모의 제공자 요약을 쓴다.

func elderCarePersona(t *testing.T, s *sess) string {
	t.Helper()
	for _, p := range personaList(t, s, "") {
		if p["presetId"] == "elder-care" {
			return p["id"].(string)
		}
	}
	t.Fatal("미소 페르소나가 없어요")
	return ""
}

func TestF028Conversations(t *testing.T) {
	a := admin(t)
	cg, _ := create(t, a, "요양사", "caregiver", nil)
	elder, elderID := create(t, cg, "어르신", "elder", nil)
	other, _ := create(t, a, "다른 어르신", "elder", nil)
	guardian, _ := create(t, cg, "보호자", "guardian", map[string]any{"elderIds": []string{elderID}})
	personaID := elderCarePersona(t, elder)

	st, c := elder.do(t, "POST", "/api/conversations", map[string]any{"personaId": personaID, "channel": "voice"})
	if st != 201 || c["status"] != "open" {
		t.Fatalf("대화 열기 %d %v", st, c)
	}
	convID := c["id"].(string)

	t.Run("F-028 AC1 conversationId로 채팅, 남의 대화 id는 404", func(t *testing.T) {
		msgs := []map[string]string{{"role": "user", "content": "안녕하세요"}}
		if st, _ := elder.do(t, "POST", "/api/chat", map[string]any{"conversationId": convID, "messages": msgs}); st != 200 {
			t.Fatalf("채팅 %d", st)
		}
		if st, _ := other.do(t, "POST", "/api/chat", map[string]any{"conversationId": convID, "messages": msgs}); st != 404 {
			t.Fatalf("남의 대화 %d", st)
		}
		if st, _ := other.do(t, "POST", "/api/conversations", map[string]any{"personaId": personaID}); st != 404 {
			t.Fatalf("남의 페르소나로 대화 열기 %d", st)
		}
	})

	t.Run("F-028 AC2 끝내면 요약이 하나 저장된다 (두 번 불러도)", func(t *testing.T) {
		body := map[string]any{"messages": []map[string]string{
			{"role": "user", "content": "점심에 국수 먹었어요"}, {"role": "assistant", "content": "맛있게 드셨어요?"}, {"role": "user", "content": "네"},
		}}
		for range 2 {
			st, m := elder.do(t, "POST", "/api/conversations/"+convID+"/end", body)
			sum, _ := m["summary"].(map[string]any)
			txt, _ := sum["summary"].(string)
			if st != 200 || !strings.Contains(txt, "사용자 말 2개") {
				t.Fatalf("끝내기 %d %v", st, m)
			}
		}
		_, mem := elder.do(t, "GET", "/api/personas/"+personaID+"/memory", nil)
		if n := len(mem["summaries"].([]any)); n != 1 {
			t.Fatalf("요약 %d개", n)
		}
		if st, _ := other.do(t, "POST", "/api/conversations/"+convID+"/end", body); st != 404 {
			t.Fatalf("남이 끝내기 %d", st)
		}
	})

	t.Run("F-029 AC3 보호자는 연결된 어르신의 요약을 보고 지우지 못한다", func(t *testing.T) {
		st, mem := guardian.do(t, "GET", "/api/personas/"+personaID+"/memory?userId="+elderID, nil)
		if st != 200 || len(mem["summaries"].([]any)) != 1 {
			t.Fatalf("보호자 보기 %d %v", st, mem)
		}
		if st, _ := guardian.do(t, "DELETE", "/api/personas/"+personaID+"/memory?userId="+elderID, nil); st != 403 {
			t.Fatalf("보호자 지우기 %d", st)
		}
		if st, _ := other.do(t, "GET", "/api/personas/"+personaID+"/memory?userId="+elderID, nil); st != 404 {
			t.Fatalf("다른 어르신 보기 %d", st)
		}
		if st, _ := cg.do(t, "GET", "/api/personas/"+personaID+"/memory?userId="+elderID, nil); st != 200 {
			t.Fatalf("요양사 보기 %d", st)
		}
	})

	t.Run("F-028 AC3 요약 하나 지우기", func(t *testing.T) {
		_, mem := elder.do(t, "GET", "/api/personas/"+personaID+"/memory", nil)
		id := mem["summaries"].([]any)[0].(map[string]any)["id"].(string)
		if st, _ := other.do(t, "DELETE", "/api/summaries/"+id, nil); st != 404 {
			t.Fatalf("남이 지우기 %d", st)
		}
		if st, _ := elder.do(t, "DELETE", "/api/summaries/"+id, nil); st != 204 {
			t.Fatalf("지우기 %d", st)
		}
	})

	t.Run("F-026 AC4 세션 없으면 401", func(t *testing.T) {
		if st, _ := newSess().do(t, "POST", "/api/conversations", map[string]any{"personaId": personaID}); st != 401 {
			t.Fatalf("%d", st)
		}
	})
}
