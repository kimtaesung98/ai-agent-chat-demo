package chat

import (
	"encoding/json"
	"strings"
)

// 장기 기억 제한 (SPEC.md API-001 longTerm · API-004, F-020). UTF-16 코드 단위로 센다.
const (
	MaxLongTermSummary     = 1000
	MaxLongTermFacts       = 10
	MaxConsolidateSessions = 20
)

// LongTerm은 오래된 대화 세션 요약을 묶은 장기 기억이다 (F-020, ADR-024).
// 앱이 기기에 저장하고, 최근 요약(memory)과 함께 다음 대화에 싣는다.
type LongTerm struct {
	Summary string   `json:"summary"`
	Facts   []string `json:"facts"`
}

const (
	longTermLabel      = "장기 기억 (오래된 대화를 묶은 것): "
	longTermFactsLabel = "사용자에 대해 알고 있는 것: "
	longTermInvalid    = "요청 형식이 올바르지 않아요. longTerm 형식을 확인해 주세요."
)

// ConsolidateSystemPrompt는 장기 기억을 만들 때 쓰는 시스템 프롬프트다 (F-020).
// 모의 제공자는 이 값으로 장기 기억 요청인지 알아본다.
const ConsolidateSystemPrompt = "당신은 사용자와 에이전트의 대화 기억을 정리하는 도우미예요. 이전 장기 기억과 오래된 대화 요약들을 " +
	"하나의 장기 기억으로 합치세요. 다른 말 없이 JSON 객체 하나만 답하세요: " +
	`{"summary": "지금까지 함께 나눈 이야기의 흐름과 이어지는 관심사, 5문장 이내", "facts": ["사용자에 대해 오래 기억할 만한 사실이나 선호, 최대 10개"]}. ` +
	"겹치는 내용은 하나로 합치고, 나중 요약이 앞 요약과 다르면 나중 것을 따르세요. 지어내지 마세요. 사용자를 3인칭(사용자)으로 쓰세요. " +
	"비밀번호, 주민등록번호, 카드·계좌 번호, 전화번호, 주소 같은 민감한 정보는 적지 마세요. 요약과 같은 언어로 쓰세요."

// ConsolidateTranscriptItem은 기록에서 대화 요약 한 줄의 머리다. 모의 제공자가 요약 수를 셀 때 쓴다.
const ConsolidateTranscriptItem = "- "

// ConsolidateRequest는 검증된 POST /api/consolidate 본문이다 (API-004).
type ConsolidateRequest struct {
	Persona  *Persona
	LongTerm *LongTerm     // 이전 장기 기억. 없으면 nil
	Sessions []MemoryEntry // 묶을 요약, 오래된 것부터 1~20개
}

// ParseConsolidateRequest는 POST /api/consolidate 본문을 검증한다.
func ParseConsolidateRequest(body []byte) (ConsolidateRequest, *ValidationError) {
	if !json.Valid(body) {
		return ConsolidateRequest{}, invalid("INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
	}
	var root map[string]json.RawMessage
	if json.Unmarshal(body, &root) != nil || root == nil {
		return ConsolidateRequest{}, invalid("INVALID_INPUT", "요청 형식이 올바르지 않아요. sessions 배열이 필요해요.")
	}
	var r ConsolidateRequest
	if raw, ok := root["persona"]; ok {
		p, err := parsePersona(raw)
		if err != nil {
			return ConsolidateRequest{}, err
		}
		r.Persona = p
	}
	if raw, ok := root["longTerm"]; ok {
		lt, err := parseLongTerm(raw)
		if err != nil {
			return ConsolidateRequest{}, err
		}
		r.LongTerm = lt
	}
	raw, ok := root["sessions"]
	if !ok {
		return ConsolidateRequest{}, invalid("INVALID_INPUT", "요청 형식이 올바르지 않아요. sessions 배열이 필요해요.")
	}
	sessions, err := parseMemoryList(raw, MaxConsolidateSessions)
	if err != nil {
		return ConsolidateRequest{}, err
	}
	if len(sessions) == 0 {
		return ConsolidateRequest{}, invalid("INVALID_INPUT", "묶을 대화 요약이 없어요.")
	}
	r.Sessions = sessions
	return r, nil
}

// Transcript는 이전 장기 기억과 요약들을 사용자 메시지 하나로 만든다.
func (r ConsolidateRequest) Transcript() []Message {
	var b strings.Builder
	b.WriteString("아래는 사용자와 에이전트")
	if r.Persona != nil {
		b.WriteString(" \"" + r.Persona.Name + "\"")
	}
	b.WriteString("의 이전 장기 기억과 오래된 대화 요약이에요.\n\n")
	if r.LongTerm != nil {
		b.WriteString("이전 장기 기억: " + r.LongTerm.Summary + "\n")
		if len(r.LongTerm.Facts) > 0 {
			b.WriteString("알고 있는 것: " + strings.Join(r.LongTerm.Facts, "; ") + "\n")
		}
		b.WriteString("\n")
	}
	b.WriteString("대화 요약 (오래된 것부터):\n")
	for _, e := range r.Sessions {
		b.WriteString(ConsolidateTranscriptItem + strings.TrimPrefix(memoryLine(e), "- ") + "\n")
	}
	b.WriteString("\n위 내용을 하나의 장기 기억으로 정해진 JSON 형식에 맞춰 합쳐 주세요.")
	return []Message{{Role: RoleUser, Content: b.String()}}
}

// ParseLongTerm은 모델 답에서 장기 기억을 꺼낸다. 길이는 longTerm 제한으로 자른다. 요약이 비면 false.
func ParseLongTerm(text string) (LongTerm, bool) {
	raw := readModelJSON(text)
	lt := LongTerm{
		Summary: cutUTF16(strings.Join(strings.Fields(raw.Summary), " "), MaxLongTermSummary),
		Facts:   cleanList(raw.Facts, MaxLongTermFacts),
	}
	return lt, lt.Summary != ""
}

// longTermPrompt는 장기 기억 줄이다. 없으면 빈 문자열.
func longTermPrompt(lt *LongTerm) string {
	if lt == nil {
		return ""
	}
	line := longTermLabel + lt.Summary
	if len(lt.Facts) > 0 {
		line += "\n" + longTermFactsLabel + strings.Join(lt.Facts, "; ")
	}
	return line
}

// parseLongTerm은 longTerm 값을 검증한다: summary 1~1,000자, facts 0~10개(각 1~100자).
func parseLongTerm(raw json.RawMessage) (*LongTerm, *ValidationError) {
	bad := invalid("INVALID_INPUT", longTermInvalid)
	var obj map[string]json.RawMessage
	if !strings.HasPrefix(strings.TrimSpace(string(raw)), "{") || json.Unmarshal(raw, &obj) != nil {
		return nil, bad
	}
	var lt LongTerm
	var ok bool
	if lt.Summary, ok = strField(obj, "summary", MaxLongTermSummary, true); !ok {
		return nil, bad
	}
	if lt.Facts, ok = strList(obj, "facts", MaxLongTermFacts, MaxMemoryItem); !ok {
		return nil, bad
	}
	return &lt, nil
}
