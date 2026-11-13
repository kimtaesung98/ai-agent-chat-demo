package contract

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"
)

// F-027 페르소나 형식 v1 계약 테스트 (API-015·016). 같은 예시 파일을 앱 테스트도 읽는다 (F-027 AC4).

func personaList(t *testing.T, s *sess, query string) []map[string]any {
	t.Helper()
	st, m := s.do(t, "GET", "/api/personas"+query, nil)
	if st != 200 {
		t.Fatalf("목록 %d %v", st, m)
	}
	var out []map[string]any
	for _, p := range m["personas"].([]any) {
		out = append(out, p.(map[string]any))
	}
	return out
}

func TestF027Personas(t *testing.T) {
	a := admin(t)
	cg, _ := create(t, a, "요양사", "caregiver", nil)
	elder, elderID := create(t, cg, "어르신", "elder", nil)
	other, otherID := create(t, a, "다른 어르신", "elder", nil)
	guardian, _ := create(t, cg, "보호자", "guardian", map[string]any{"elderIds": []string{elderID}})

	t.Run("F-027 AC1 카탈로그와 처음 계정의 탑재 페르소나 4개", func(t *testing.T) {
		st, m := newSess().do(t, "GET", "/api/presets", nil)
		ps, _ := m["presets"].([]any)
		if st != 200 || len(ps) != 4 {
			t.Fatalf("%d %v", st, m)
		}
		var recommended string
		for _, p := range ps {
			pm := p.(map[string]any)
			if pm["base"] == "" || pm["id"] == "" {
				t.Fatalf("프리셋 모양 %v", pm)
			}
			if pm["recommended"] == true {
				recommended, _ = pm["id"].(string)
			}
		}
		if m["careSetting"] != "daycare" || recommended != "elder-care" {
			t.Fatalf("노치원 추천이 미소가 아니에요: %v", m)
		}
		list := personaList(t, elder, "")
		if len(list) != 4 || list[0]["schema"] != float64(1) || list[3]["presetId"] != "elder-care" || list[3]["base"] == nil {
			t.Fatalf("탑재 4개가 아니에요: %v", list)
		}
		if again := personaList(t, elder, ""); len(again) != 4 {
			t.Fatalf("다시 읽으면 늘어나면 안 돼요: %d", len(again))
		}
	})

	var created map[string]any
	t.Run("F-027 AC1 공통 예시 파일로 만들기 — 앱이 보낸 base는 무시", func(t *testing.T) {
		raw, err := os.ReadFile("testdata/persona_v1.json")
		if err != nil {
			t.Fatal(err)
		}
		var body map[string]any
		json.Unmarshal(raw, &body)
		st, m := elder.do(t, "POST", "/api/personas", body)
		if st != 201 || m["revision"] != float64(1) || m["kind"] != "preset" || m["id"] == body["id"] {
			t.Fatalf("%d %v", st, m)
		}
		if m["base"] == body["base"] || m["unknownField"] != nil {
			t.Fatalf("앱이 보낸 base·모르는 필드가 남았어요: %v", m)
		}
		created = m
	})

	t.Run("F-027 AC1 형식이 틀리면 400", func(t *testing.T) {
		for name, body := range map[string]any{
			"schema 2": map[string]any{"schema": 2, "kind": "custom", "name": "a"},
			"없는 프리셋":   map[string]any{"schema": 1, "kind": "preset", "presetId": "nope", "name": "a"},
			"이름 없음":    map[string]any{"schema": 1, "kind": "custom", "name": ""},
			"말투 7개":    map[string]any{"schema": 1, "kind": "custom", "name": "a", "tones": []string{"1", "2", "3", "4", "5", "6", "7"}},
		} {
			if st, m := elder.do(t, "POST", "/api/personas", body); st != 400 || errCode(m) != "INVALID_INPUT" {
				t.Errorf("%s: %d %v", name, st, m)
			}
		}
	})

	t.Run("F-027 AC3 옛 revision의 PUT은 409이고 저장 값은 그대로", func(t *testing.T) {
		id := created["id"].(string)
		upd := map[string]any{"schema": 1, "kind": "custom", "name": "바둑 친구", "instructions": "바둑 이야기", "revision": 1}
		st, m := elder.do(t, "PUT", "/api/personas/"+id, upd)
		if st != 200 || m["revision"] != float64(2) || m["kind"] != "custom" || m["presetId"] != nil {
			t.Fatalf("고치기 %d %v", st, m)
		}
		upd["name"] = "늦은 기기"
		st, m = elder.do(t, "PUT", "/api/personas/"+id, upd)
		latest, _ := m["persona"].(map[string]any)
		if st != 409 || errCode(m) != "CONFLICT" || latest["name"] != "바둑 친구" {
			t.Fatalf("409가 아니에요: %d %v", st, m)
		}
		if _, m := elder.do(t, "GET", "/api/personas/"+id, nil); m["name"] != "바둑 친구" || m["revision"] != float64(2) {
			t.Fatalf("저장 값이 바뀌었어요: %v", m)
		}
	})

	t.Run("F-026 AC5 남의 페르소나는 읽기·고치기·지우기 모두 404", func(t *testing.T) {
		id := created["id"].(string)
		upd := map[string]any{"schema": 1, "kind": "custom", "name": "x", "revision": 2}
		for _, c := range []struct {
			method string
			body   any
		}{{"GET", nil}, {"PUT", upd}, {"DELETE", nil}} {
			if st, _ := other.do(t, c.method, "/api/personas/"+id, c.body); st != 404 {
				t.Errorf("%s %d", c.method, st)
			}
		}
		if st, _ := other.do(t, "GET", "/api/personas?userId="+elderID, nil); st != 404 {
			t.Errorf("남의 목록 %d", st)
		}
	})

	t.Run("F-029 AC3 요양사는 맡은 어르신 페르소나를 정하고, 보호자는 보기만", func(t *testing.T) {
		body := map[string]any{"schema": 1, "kind": "preset", "presetId": "elder-care", "name": "미소", "instructions": "점심 뒤 산책 여쭤봐 줘"}
		if st, m := cg.do(t, "POST", "/api/personas?userId="+elderID, body); st != 201 {
			t.Fatalf("요양사 만들기 %d %v", st, m)
		}
		if n := len(personaList(t, elder, "")); n != 6 {
			t.Fatalf("어르신 쪽에 %d개", n)
		}
		if n := len(personaList(t, guardian, "?userId="+elderID)); n != 6 {
			t.Fatalf("보호자 보기 %d개", n)
		}
		if st, m := guardian.do(t, "POST", "/api/personas?userId="+elderID, body); st != 403 || errCode(m) != "FORBIDDEN" {
			t.Fatalf("보호자 고치기 %d %v", st, m)
		}
		if st, _ := cg.do(t, "GET", "/api/personas?userId="+otherID, nil); st != 404 {
			t.Fatalf("맡지 않은 어르신 %d", st)
		}
	})

	t.Run("F-027 AC1 사람마다 20개까지, 지운 탑재 페르소나는 다시 넣기로 복구", func(t *testing.T) {
		list := personaList(t, other, "")
		for i := len(list); i < 20; i++ {
			if st, m := other.do(t, "POST", "/api/personas", map[string]any{"schema": 1, "kind": "custom", "name": fmt.Sprintf("상대 %d", i)}); st != 201 {
				t.Fatalf("%d번째 %d %v", i, st, m)
			}
		}
		if st, m := other.do(t, "POST", "/api/personas", map[string]any{"schema": 1, "kind": "custom", "name": "21번째"}); st != 400 {
			t.Fatalf("21번째 %d %v", st, m)
		}
		for _, p := range personaList(t, other, "") {
			if p["presetId"] == "elder-care" {
				if st, _ := other.do(t, "DELETE", "/api/personas/"+p["id"].(string), nil); st != 204 {
					t.Fatalf("지우기 %d", st)
				}
			}
		}
		st, m := other.do(t, "POST", "/api/personas/presets", map[string]any{})
		var found bool
		for _, p := range m["personas"].([]any) {
			found = found || p.(map[string]any)["presetId"] == "elder-care"
		}
		if st != 200 || !found {
			t.Fatalf("다시 넣기 %d %v", st, m)
		}
	})

	t.Run("F-026 AC4 세션 없으면 401", func(t *testing.T) {
		if st, m := newSess().do(t, "GET", "/api/personas", nil); st != 401 || errCode(m) != "UNAUTHENTICATED" {
			t.Fatalf("%d %v", st, m)
		}
	})
}
