package chat

import (
	"encoding/json"
	"strings"
)

// MaxSummaryTurns는 요약할 때 넘기는 최근 턴 수다 (F-019). 대화 요청(MaxTurns)보다 길게 본다.
const MaxSummaryTurns = 40

// 대화 기록 줄 머리 (F-019). 모의 제공자가 사용자 말을 셀 때도 쓴다.
const (
	TranscriptUser  = "사용자: "
	TranscriptAgent = "에이전트: "
)

// SummarySystemPrompt는 대화 세션 요약을 만들 때 쓰는 시스템 프롬프트다 (F-019, ADR-024).
// 모의 제공자는 이 값으로 요약 요청인지 알아본다 — 바꾸면 mock 테스트도 함께 본다.
const SummarySystemPrompt = "당신은 대화 기록을 정리하는 도우미예요. 사용자가 다음 대화에서 에이전트와 이어서 이야기할 수 있도록, " +
	"주어진 대화 세션을 기억으로 정리하세요. 다른 말 없이 JSON 객체 하나만 답하세요: " +
	`{"summary": "무엇을 이야기했고 어떻게 끝났는지 2~4문장", "facts": ["사용자에 대해 새로 알게 된 사실이나 선호, 최대 5개"], "followUps": ["다음 대화에서 이어 가거나 챙길 것, 최대 3개"]}. ` +
	"없으면 빈 배열로 두세요. 대화에 없는 내용은 지어내지 마세요. 사용자를 3인칭(사용자)으로 쓰세요. " +
	"비밀번호, 주민등록번호, 카드·계좌 번호, 전화번호, 주소 같은 민감한 정보는 적지 마세요. 대화와 같은 언어로 쓰세요."

// SummaryUnavailable은 요약을 만들지 못했을 때 화면에 보여도 되는 문장이다.
const SummaryUnavailable = "대화를 정리하지 못했어요. 잠시 후 다시 시도해 주세요."

// SummaryRequest는 검증된 POST /api/summary 본문이다 (API-003).
type SummaryRequest struct {
	Messages []Message
	Persona  *Persona // 대화한 페르소나 이름·역할을 기록 머리에 쓴다. 없으면 nil
}

// ParseSummaryRequest는 POST /api/summary 본문을 검증한다. 메시지 규칙은 API-001과 같고,
// 마지막이 응답이어도 된다. 사용자 메시지가 하나도 없으면 INVALID_INPUT.
func ParseSummaryRequest(body []byte) (SummaryRequest, *ValidationError) {
	if !json.Valid(body) {
		return SummaryRequest{}, invalid("INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
	}
	var root map[string]json.RawMessage
	var list []json.RawMessage
	if json.Unmarshal(body, &root) != nil || root == nil || json.Unmarshal(root["messages"], &list) != nil || list == nil {
		return SummaryRequest{}, invalid("INVALID_INPUT", "요청 형식이 올바르지 않아요. messages 배열이 필요해요.")
	}
	var persona *Persona
	if raw, ok := root["persona"]; ok {
		p, err := parsePersona(raw)
		if err != nil {
			return SummaryRequest{}, err
		}
		persona = p
	}
	msgs, verr := parseMessages(list)
	if verr != nil {
		return SummaryRequest{}, verr
	}
	hasUser := false
	for _, m := range msgs {
		hasUser = hasUser || m.Role == RoleUser
	}
	if !hasUser {
		return SummaryRequest{}, invalid("INVALID_INPUT", "요약할 사용자 메시지가 없어요.")
	}
	return SummaryRequest{Messages: TrimToRecentTurns(msgs, MaxSummaryTurns), Persona: persona}, nil
}

// Transcript는 대화를 사용자 메시지 하나로 만든 기록이다. 여러 턴으로 넘기면 모델이 요약 대신 대화를 이어 갈 수 있어서다.
// 메시지 안의 줄바꿈은 공백으로 바꿔 한 줄에 하나씩 둔다.
func (r SummaryRequest) Transcript() []Message {
	var b strings.Builder
	b.WriteString("아래는 사용자와 에이전트")
	if r.Persona != nil {
		b.WriteString(" \"" + r.Persona.Name + "\"")
		if r.Persona.Role != "" {
			b.WriteString("(" + r.Persona.Role + ")")
		}
	}
	b.WriteString("의 대화 기록이에요.\n\n")
	for _, m := range r.Messages {
		head := TranscriptUser
		if m.Role == RoleAssistant {
			head = TranscriptAgent
		}
		b.WriteString(head + strings.Join(strings.Fields(m.Content), " ") + "\n")
	}
	b.WriteString("\n위 대화를 정해진 JSON 형식으로 정리해 주세요.")
	return []Message{{Role: RoleUser, Content: b.String()}}
}

// Summary는 API-003 응답이다. 길이는 API-001 memory 제한과 같다.
type Summary struct {
	Summary   string   `json:"summary"`
	Facts     []string `json:"facts"`
	FollowUps []string `json:"followUps"`
}

// ParseSummary는 모델 답에서 요약을 꺼낸다. JSON 객체를 찾아 읽고, 못 읽으면 답 전체를 요약 문장으로 쓴다.
// 길이는 memory 제한으로 자른다. 요약이 비면 false.
func ParseSummary(text string) (Summary, bool) {
	var raw struct {
		Summary   any `json:"summary"`
		Facts     any `json:"facts"`
		FollowUps any `json:"followUps"`
	}
	s := Summary{Facts: []string{}, FollowUps: []string{}}
	start, end := strings.Index(text, "{"), strings.LastIndex(text, "}")
	if start >= 0 && end > start && json.Unmarshal([]byte(text[start:end+1]), &raw) == nil {
		if v, ok := raw.Summary.(string); ok {
			s.Summary = v
		}
		s.Facts = cleanList(raw.Facts, MaxMemoryFacts)
		s.FollowUps = cleanList(raw.FollowUps, MaxMemoryFollowUps)
	} else {
		s.Summary = text
	}
	s.Summary = cutUTF16(strings.Join(strings.Fields(s.Summary), " "), MaxMemorySummary)
	return s, s.Summary != ""
}

func cleanList(v any, max int) []string {
	out := []string{}
	items, _ := v.([]any)
	for _, it := range items {
		s, ok := it.(string)
		if !ok {
			continue
		}
		s = cutUTF16(strings.Join(strings.Fields(s), " "), MaxMemoryItem)
		if s != "" && len(out) < max {
			out = append(out, s)
		}
	}
	return out
}
