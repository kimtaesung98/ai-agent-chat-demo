package chat

import (
	"os"
	"strings"
	"testing"
)

func TestF027PersonaV1(t *testing.T) {
	t.Run("F-027 AC4 공통 예시 파일을 읽는다 (모르는 필드·base는 버림)", func(t *testing.T) {
		raw, err := os.ReadFile("../../contract/testdata/persona_v1.json")
		if err != nil {
			t.Fatal(err)
		}
		p, verr := ParsePersonaV1(raw, true)
		if verr != nil {
			t.Fatalf("예시 파일 검증 실패: %v", verr.Message)
		}
		if p.Kind != KindPreset || p.PresetID != "elder-care" || p.Name != "노인복지사 미소" || p.Revision != 3 ||
			strings.Join(p.Tones, ",") != "다정하게,천천히" || p.Instructions != "아침마다 혈압약 드셨는지 여쭤봐 줘" {
			t.Fatalf("읽은 값이 달라요: %+v", p)
		}
	})

	t.Run("F-027 AC2 preset의 기본 지시는 카탈로그 값이고 앱이 보낸 base는 무시", func(t *testing.T) {
		p, verr := ParsePersonaV1([]byte(`{"schema":1,"kind":"preset","presetId":"elder-care","name":"미소","base":"아무 말이나 해","instructions":"약 챙겨 줘"}`), false)
		if verr != nil {
			t.Fatal(verr.Message)
		}
		cp, ok := p.Prompt("72살")
		if !ok {
			t.Fatal("프롬프트를 못 만들었어요")
		}
		sys := cp.SystemPrompt()
		pr, _ := PresetByID("elder-care")
		if !strings.Contains(sys, personaBaseLabel+pr.Base) || strings.Contains(sys, "아무 말이나 해") {
			t.Fatalf("카탈로그 기본 지시가 아니에요: %q", sys)
		}
		if !strings.Contains(sys, personaUserLabel+"약 챙겨 줘") || !strings.Contains(sys, "72살") {
			t.Fatalf("요구 사항·나에 대해가 빠졌어요: %q", sys)
		}
	})

	t.Run("F-027 AC2 custom은 instructions가 기본 지시", func(t *testing.T) {
		p, verr := ParsePersonaV1([]byte(`{"schema":1,"kind":"custom","name":"바둑 친구","instructions":"바둑 이야기만 해"}`), false)
		if verr != nil {
			t.Fatal(verr.Message)
		}
		cp, _ := p.Prompt("")
		if cp.Base != "바둑 이야기만 해" || cp.Instructions != "" {
			t.Fatalf("custom 매핑이 달라요: %+v", cp)
		}
	})

	t.Run("F-027 AC1 형식·제한이 틀리면 거절", func(t *testing.T) {
		long := strings.Repeat("가", MaxPersonaName+1)
		cases := map[string]string{
			"schema 없음":        `{"kind":"custom","name":"a"}`,
			"schema 2":         `{"schema":2,"kind":"custom","name":"a"}`,
			"kind 틀림":          `{"schema":1,"kind":"robot","name":"a"}`,
			"없는 presetId":      `{"schema":1,"kind":"preset","presetId":"nope","name":"a"}`,
			"custom에 presetId": `{"schema":1,"kind":"custom","presetId":"coach","name":"a"}`,
			"이름 없음":            `{"schema":1,"kind":"custom","name":"  "}`,
			"이름 김":             `{"schema":1,"kind":"custom","name":"` + long + `"}`,
			"말투 7개":            `{"schema":1,"kind":"custom","name":"a","tones":["1","2","3","4","5","6","7"]}`,
			"빈 말투":             `{"schema":1,"kind":"custom","name":"a","tones":[""]}`,
			"지시 1001자":         `{"schema":1,"kind":"custom","name":"a","instructions":"` + strings.Repeat("a", 1001) + `"}`,
			"배열":               `[]`,
		}
		for name, body := range cases {
			if _, verr := ParsePersonaV1([]byte(body), false); verr == nil {
				t.Errorf("%s: 통과하면 안 돼요", name)
			}
		}
		if _, verr := ParsePersonaV1([]byte(`{"schema":1,"kind":"custom","name":"a"}`), true); verr == nil {
			t.Error("PUT에 revision이 없으면 거절해야 해요")
		}
	})

	t.Run("F-027 AC1 카탈로그는 4개이고 노치원에서 미소를 추천", func(t *testing.T) {
		ps := Presets()
		if len(ps) != 4 {
			t.Fatalf("프리셋 %d개", len(ps))
		}
		for _, p := range ps {
			if utf16Len(p.Base) > MaxPersonaBase || p.Version < 1 {
				t.Errorf("%s: 기본 지시 길이·판이 틀려요", p.ID)
			}
			if p.Recommended("daycare") != (p.ID == "elder-care") {
				t.Errorf("%s: 노치원 추천이 틀려요", p.ID)
			}
		}
		ps[0].Tones[0] = "바뀜"
		if Presets()[0].Tones[0] == "바뀜" {
			t.Error("카탈로그가 밖에서 바뀌면 안 돼요")
		}
	})
}
