package chat

import (
	"bytes"
	"encoding/json"
	"strings"
)

// 페르소나 필드 길이 제한 (SPEC.md API-001 persona, F-005). UTF-16 코드 단위로 센다.
const (
	MaxPersonaName         = 40
	MaxPersonaRole         = 40
	MaxPersonaTones        = 6
	MaxPersonaTone         = 20
	MaxPersonaInstructions = 1000
	MaxPersonaAbout        = 1000
)

// Persona는 사용자가 화면에서 고른 대화 상대와 사용자 정보다 (F-005, ARCHITECTURE.md ADR-016).
// 시스템 프롬프트 틀은 서버가 정하고, 클라이언트는 필드 값만 보낸다.
type Persona struct {
	Name         string
	Role         string
	Tones        []string
	Instructions string
	About        string
}

// 페르소나 시스템 프롬프트 문구.
const (
	personaIntro       = "당신은 사용자와 대화하는 에이전트 \"%s\"예요. 아래 설정에 맞는 인물로서 답하세요."
	personaRoleLabel   = "역할: "
	personaTonesLabel  = "말투: "
	personaInstrLabel  = "사용자가 정한 추가 지시: "
	personaAboutLabel  = "사용자에 대해 (사용자가 직접 알려 준 정보예요. 대화 맥락으로 참고하되, 묻지 않으면 그대로 되풀이하지 마세요): "
	personaInvalidText = "요청 형식이 올바르지 않아요. persona 형식을 확인해 주세요."
)

// SystemPrompt는 페르소나를 시스템 프롬프트로 바꾼다. 빈 필드는 줄을 만들지 않는다.
func (p *Persona) SystemPrompt() string {
	if p == nil {
		return ""
	}
	lines := []string{strings.Replace(personaIntro, "%s", p.Name, 1)}
	if p.Role != "" {
		lines = append(lines, personaRoleLabel+p.Role)
	}
	if len(p.Tones) > 0 {
		lines = append(lines, personaTonesLabel+strings.Join(p.Tones, ", "))
	}
	if p.Instructions != "" {
		lines = append(lines, personaInstrLabel+p.Instructions)
	}
	if p.About != "" {
		lines = append(lines, personaAboutLabel+p.About)
	}
	return strings.Join(lines, "\n")
}

// parsePersona는 API-001 persona 값을 검증한다. 모르는 필드는 무시한다.
func parsePersona(raw json.RawMessage) (*Persona, *ValidationError) {
	bad := invalid("INVALID_INPUT", personaInvalidText)
	if !bytes.HasPrefix(bytes.TrimSpace(raw), []byte("{")) {
		return nil, bad
	}
	var obj map[string]json.RawMessage
	if json.Unmarshal(raw, &obj) != nil {
		return nil, bad
	}
	str := func(key string, max int, required bool) (string, bool) {
		v, ok := obj[key]
		if !ok {
			return "", !required
		}
		var s string
		if json.Unmarshal(v, &s) != nil || bytes.Equal(bytes.TrimSpace(v), []byte("null")) {
			return "", false
		}
		s = strings.TrimSpace(s)
		if utf16Len(s) > max || (required && s == "") {
			return "", false
		}
		return s, true
	}
	var p Persona
	var ok bool
	if p.Name, ok = str("name", MaxPersonaName, true); !ok {
		return nil, bad
	}
	if p.Role, ok = str("role", MaxPersonaRole, false); !ok {
		return nil, bad
	}
	if p.Instructions, ok = str("instructions", MaxPersonaInstructions, false); !ok {
		return nil, bad
	}
	if p.About, ok = str("about", MaxPersonaAbout, false); !ok {
		return nil, bad
	}
	if v, has := obj["tones"]; has {
		var tones []json.RawMessage
		if json.Unmarshal(v, &tones) != nil || tones == nil || len(tones) > MaxPersonaTones {
			return nil, bad
		}
		for _, t := range tones {
			var s string
			if json.Unmarshal(t, &s) != nil || bytes.Equal(bytes.TrimSpace(t), []byte("null")) {
				return nil, bad
			}
			s = strings.TrimSpace(s)
			if s == "" || utf16Len(s) > MaxPersonaTone {
				return nil, bad
			}
			p.Tones = append(p.Tones, s)
		}
	}
	return &p, nil
}
