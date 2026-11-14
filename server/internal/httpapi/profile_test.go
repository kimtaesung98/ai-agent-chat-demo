package httpapi

import (
	"strings"
	"testing"
)

func TestF026Profile(t *testing.T) {
	t.Run("F-026 프로필: 보낸 필드만 바뀌고, 이름은 계정에, 모르는 설정은 버린다", func(t *testing.T) {
		e := startConv(t, &recProvider{})
		st, m := e.call(t, "GET", "/api/me/profile", "")
		if st != 200 || m["displayName"] != "원장" || m["about"] != "" {
			t.Fatalf("기본값 %d %v", st, m)
		}
		st, m = e.call(t, "PUT", "/api/me/profile", `{"displayName":"김영희","about":"72살, 무릎이 안 좋아요","settings":{"textSize":"large","voiceOnStart":true,"unknown":1}}`)
		set, _ := m["settings"].(map[string]any)
		if st != 200 || m["displayName"] != "김영희" || set["textSize"] != "large" || set["voiceOnStart"] != true || set["unknown"] != nil {
			t.Fatalf("고치기 %d %v", st, m)
		}
		_, m = e.call(t, "PUT", "/api/me/profile", `{"settings":{"textSize":"xlarge"}}`)
		if m["about"] != "72살, 무릎이 안 좋아요" || m["displayName"] != "김영희" {
			t.Fatalf("보내지 않은 필드가 바뀌었어요: %v", m)
		}
		if _, me := e.call(t, "GET", "/api/me", ""); me["user"].(map[string]any)["name"] != "김영희" {
			t.Fatalf("계정 이름 %v", me)
		}
	})

	t.Run("F-026 프로필: 형식·길이가 틀리면 400, 남의 페르소나 id는 404", func(t *testing.T) {
		e := startConv(t, &recProvider{})
		for _, body := range []string{
			`{"displayName":""}`, `{"displayName":"` + strings.Repeat("가", 21) + `"}`,
			`{"about":"` + strings.Repeat("a", 1001) + `"}`, `{"settings":{"textSize":"huge"}}`, `[]`,
		} {
			if st, _ := e.call(t, "PUT", "/api/me/profile", body); st != 400 {
				t.Errorf("%s → %d", body, st)
			}
		}
		if st, _ := e.call(t, "PUT", "/api/me/profile", `{"lastPersonaId":"per_nope"}`); st != 404 {
			t.Errorf("없는 페르소나 %d", st)
		}
	})

	t.Run("F-028 AC1 conversationId 프롬프트에 프로필의 나에 대해가 실린다", func(t *testing.T) {
		p := &recProvider{}
		e := startConv(t, p)
		e.call(t, "PUT", "/api/me/profile", `{"about":"손주가 둘이에요"}`)
		_, convID := e.openWith(t, "elder-care")
		res := postJSON(t, e.srv.URL+"/api/chat", `{"conversationId":"`+convID+`","messages":[{"role":"user","content":"안녕"}],"persona":{"name":"x","about":"앱이 보낸 정보"}}`, e.cookie)
		if res.StatusCode != 200 {
			t.Fatal(res.StatusCode)
		}
		sys := p.last()
		if !strings.Contains(sys, "손주가 둘이에요") || strings.Contains(sys, "앱이 보낸 정보") {
			t.Fatalf("나에 대해가 DB 값이 아니에요: %q", sys)
		}
	})
}

func TestF026Import(t *testing.T) {
	body := `{
	  "profile": {"about": "기기의 나에 대해"},
	  "personas": [
	    {"schema":1,"kind":"preset","presetId":"elder-care","name":"노인복지사 미소","instructions":"혈압약 챙겨 줘","clientId":"elder-care"},
	    {"schema":1,"kind":"custom","name":"바둑 친구","instructions":"바둑 이야기","clientId":"custom-1"}
	  ],
	  "summaries": [
	    {"clientId":"s1","personaClientId":"elder-care","endedAt":"2026-11-10T09:00:00Z","summary":"점심 이야기","facts":["국수 좋아함"],"followUps":[],"turns":3},
	    {"clientId":"s2","personaClientId":"custom-1","endedAt":"2026-11-11T09:00:00Z","summary":"바둑 이야기","turns":2},
	    {"clientId":"s3","personaClientId":"없는-페르소나","summary":"버려짐"}
	  ],
	  "longTerm": [{"personaClientId":"elder-care","summary":"오래된 기억","facts":["무릎"],"coversUntil":"2026-11-01T00:00:00Z"}]
	}`
	t.Run("F-026 AC8 기기 데이터를 옮기면 같은 페르소나·요약·장기 기억이 생기고 두 번 올려도 늘지 않는다", func(t *testing.T) {
		e := startConv(t, &recProvider{})
		var ids map[string]any
		for i := range 2 {
			st, m := e.call(t, "POST", "/api/import", body)
			if st != 200 {
				t.Fatalf("%d번째 %d %v", i, st, m)
			}
			if i == 0 && (m["personasMerged"] != float64(1) || m["personasCreated"] != float64(1) || m["summaries"] != float64(2) || m["longTerm"] != float64(1) || m["about"] != true) {
				t.Fatalf("첫 옮기기 %v", m)
			}
			if i == 1 && (m["personasCreated"] != float64(0) || m["personasMerged"] != float64(0) || m["longTerm"] != float64(0) || m["about"] != false) {
				t.Fatalf("두 번째 옮기기 %v", m)
			}
			ids = m["personaIds"].(map[string]any)
		}
		_, list := e.call(t, "GET", "/api/personas", "")
		if n := len(list["personas"].([]any)); n != 5 { // 탑재 4개(미소에 기기 값을 얹음) + 바둑 친구
			t.Fatalf("페르소나 %d개", n)
		}
		miso := ids["elder-care"].(string)
		_, p := e.call(t, "GET", "/api/personas/"+miso, "")
		if p["instructions"] != "혈압약 챙겨 줘" || p["clientId"] != "elder-care" {
			t.Fatalf("미소에 기기 값이 없어요: %v", p)
		}
		_, mem := e.call(t, "GET", "/api/personas/"+miso+"/memory", "")
		lt, _ := mem["longTerm"].(map[string]any)
		if len(mem["summaries"].([]any)) != 1 || lt["summary"] != "오래된 기억" {
			t.Fatalf("미소 기억 %v", mem)
		}
		_, prof := e.call(t, "GET", "/api/me/profile", "")
		if prof["about"] != "기기의 나에 대해" {
			t.Fatalf("나에 대해 %v", prof)
		}
	})

	t.Run("F-026 AC8 서버에 이미 있는 나에 대해는 덮어쓰지 않고, 형식이 틀리면 아무것도 바꾸지 않는다", func(t *testing.T) {
		e := startConv(t, &recProvider{})
		e.call(t, "PUT", "/api/me/profile", `{"about":"서버 값"}`)
		if st, _ := e.call(t, "POST", "/api/import", `{"profile":{"about":"기기 값"}}`); st != 200 {
			t.Fatal(st)
		}
		if _, prof := e.call(t, "GET", "/api/me/profile", ""); prof["about"] != "서버 값" {
			t.Fatalf("덮어씀 %v", prof)
		}
		bad := `{"personas":[{"schema":1,"kind":"custom","name":"a","clientId":"c1"},{"schema":2,"kind":"custom","name":"b","clientId":"c2"}]}`
		if st, _ := e.call(t, "POST", "/api/import", bad); st != 400 {
			t.Fatalf("틀린 형식 %d", st)
		}
		if _, list := e.call(t, "GET", "/api/personas", ""); len(list["personas"].([]any)) != 4 {
			t.Fatalf("틀린 요청이 일부 반영됐어요: %v", list)
		}
		noClient := `{"personas":[{"schema":1,"kind":"custom","name":"a"}]}`
		if st, _ := e.call(t, "POST", "/api/import", noClient); st != 400 {
			t.Fatalf("clientId 없음 %d", st)
		}
	})
}
