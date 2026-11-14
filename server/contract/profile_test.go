package contract

import "testing"

// F-026 프로필(API-013)·기기 데이터 옮기기(API-014) 계약 테스트.
func TestF026ProfileImport(t *testing.T) {
	a := admin(t)
	elder, _ := create(t, a, "어르신", "elder", nil)
	other, _ := create(t, a, "다른 어르신", "elder", nil)

	t.Run("F-026 프로필 읽기·고치기, 세션 없으면 401", func(t *testing.T) {
		st, m := elder.do(t, "PUT", "/api/me/profile", map[string]any{"about": "72살이에요", "settings": map[string]any{"textSize": "large"}})
		if st != 200 || m["about"] != "72살이에요" {
			t.Fatalf("%d %v", st, m)
		}
		if _, m := other.do(t, "GET", "/api/me/profile", nil); m["about"] != "" {
			t.Fatalf("남의 프로필이 보여요: %v", m)
		}
		if st, _ := newSess().do(t, "GET", "/api/me/profile", nil); st != 401 {
			t.Fatalf("%d", st)
		}
	})

	t.Run("F-026 AC8 두 번 옮겨도 늘지 않는다", func(t *testing.T) {
		body := map[string]any{
			"personas":  []map[string]any{{"schema": 1, "kind": "custom", "name": "바둑 친구", "clientId": "dev-custom-1"}},
			"summaries": []map[string]any{{"clientId": "dev-s1", "personaClientId": "dev-custom-1", "summary": "바둑 이야기", "endedAt": "2026-11-10T09:00:00Z"}},
		}
		var pid string
		for range 2 {
			st, m := elder.do(t, "POST", "/api/import", body)
			if st != 200 {
				t.Fatalf("%d %v", st, m)
			}
			pid, _ = m["personaIds"].(map[string]any)["dev-custom-1"].(string)
		}
		if n := len(personaList(t, elder, "")); n != 5 {
			t.Fatalf("페르소나 %d개", n)
		}
		if _, mem := elder.do(t, "GET", "/api/personas/"+pid+"/memory", nil); len(mem["summaries"].([]any)) != 1 {
			t.Fatalf("요약 %v", mem)
		}
	})
}
