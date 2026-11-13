package chat

import (
	"bytes"
	"encoding/json"
	"strings"
)

// 페르소나 형식 v1 (SPEC.md F-027 §7.2 Persona, ARCHITECTURE.md ADR-030) — 앱·서버·DB 공통 계약.
// 서버가 진실 원천이다: kind "preset"의 기본 지시는 카탈로그에서 찾고, 요청의 base는 버린다.

// PersonaSchema는 지금 형식 판이다. 다른 값이면 400.
const PersonaSchema = 1

// 페르소나 종류.
const (
	KindPreset = "preset"
	KindCustom = "custom"
)

// MaxPersonaClientID는 기기 데이터 옮기기용 clientId 길이 상한이다 (F-026 상세 동작 9).
const MaxPersonaClientID = 64

// PersonaV1은 요청으로 받은, 검증된 페르소나 값이다 (id·revision·시각은 저장소가 가진다).
type PersonaV1 struct {
	Kind         string
	PresetID     string
	Name         string
	Role         string
	Tones        []string
	Instructions string
	ClientID     string
	// Revision은 PUT에서 받은 값이다 (POST는 0).
	Revision int
}

const personaV1InvalidText = "페르소나 형식이 올바르지 않아요. schema·kind·이름·길이를 확인해 주세요."

// ParsePersonaV1은 §7.2 형식을 검증한다. needRevision이면 revision(1 이상)이 있어야 한다.
// 모르는 필드와 id·base·createdAt 같은 응답 전용 필드는 버린다.
func ParsePersonaV1(raw []byte, needRevision bool) (PersonaV1, *ValidationError) {
	bad := invalid("INVALID_INPUT", personaV1InvalidText)
	var obj map[string]json.RawMessage
	if !bytes.HasPrefix(bytes.TrimSpace(raw), []byte("{")) || json.Unmarshal(raw, &obj) != nil {
		return PersonaV1{}, bad
	}
	var schema int
	if v, ok := obj["schema"]; !ok || json.Unmarshal(v, &schema) != nil || schema != PersonaSchema {
		return PersonaV1{}, bad
	}
	str := func(key string, max int, required bool) (string, bool) {
		v, ok := obj[key]
		if !ok || bytes.Equal(bytes.TrimSpace(v), []byte("null")) {
			return "", !required
		}
		var s string
		if json.Unmarshal(v, &s) != nil {
			return "", false
		}
		s = strings.TrimSpace(s)
		if utf16Len(s) > max || (required && s == "") {
			return "", false
		}
		return s, true
	}
	var p PersonaV1
	var ok bool
	if p.Kind, ok = str("kind", 10, true); !ok || (p.Kind != KindPreset && p.Kind != KindCustom) {
		return PersonaV1{}, bad
	}
	if p.PresetID, ok = str("presetId", 40, false); !ok {
		return PersonaV1{}, bad
	}
	if p.Kind == KindPreset {
		if _, found := PresetByID(p.PresetID); !found {
			return PersonaV1{}, bad
		}
	} else if p.PresetID != "" {
		return PersonaV1{}, bad
	}
	if p.Name, ok = str("name", MaxPersonaName, true); !ok {
		return PersonaV1{}, bad
	}
	if p.Role, ok = str("role", MaxPersonaRole, false); !ok {
		return PersonaV1{}, bad
	}
	if p.Instructions, ok = str("instructions", MaxPersonaInstructions, false); !ok {
		return PersonaV1{}, bad
	}
	if p.ClientID, ok = str("clientId", MaxPersonaClientID, false); !ok {
		return PersonaV1{}, bad
	}
	if v, has := obj["tones"]; has && !bytes.Equal(bytes.TrimSpace(v), []byte("null")) {
		var tones []json.RawMessage
		if json.Unmarshal(v, &tones) != nil || len(tones) > MaxPersonaTones {
			return PersonaV1{}, bad
		}
		for _, t := range tones {
			var s string
			if json.Unmarshal(t, &s) != nil {
				return PersonaV1{}, bad
			}
			s = strings.TrimSpace(s)
			if s == "" || utf16Len(s) > MaxPersonaTone {
				return PersonaV1{}, bad
			}
			p.Tones = append(p.Tones, s)
		}
	}
	if needRevision {
		if v, has := obj["revision"]; !has || json.Unmarshal(v, &p.Revision) != nil || p.Revision < 1 {
			return PersonaV1{}, bad
		}
	}
	return p, nil
}

// FromPreset은 프리셋을 그대로 가리키는 사용자 페르소나 값이다 (처음 계정에 넣는 4개).
func FromPreset(pr Preset) PersonaV1 {
	return PersonaV1{Kind: KindPreset, PresetID: pr.ID, Name: pr.Name, Role: pr.Role, Tones: append([]string(nil), pr.Tones...)}
}

// Prompt는 v1 페르소나를 시스템 프롬프트용 Persona로 바꾼다 (§7.2 프롬프트 매핑, F-027 AC2).
// preset → Base = 카탈로그 base, Instructions = 내 요구 사항 / custom → Base = instructions, Instructions = 비움.
// 카탈로그에 없는 presetId면 false.
func (p PersonaV1) Prompt(about string) (*Persona, bool) {
	out := &Persona{Name: p.Name, Role: p.Role, Tones: append([]string(nil), p.Tones...), About: about}
	switch p.Kind {
	case KindPreset:
		pr, ok := PresetByID(p.PresetID)
		if !ok {
			return nil, false
		}
		out.Base, out.Instructions = pr.Base, p.Instructions
	case KindCustom:
		out.Base = p.Instructions
	default:
		return nil, false
	}
	return out, true
}
