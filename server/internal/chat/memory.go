package chat

import (
	"bytes"
	"encoding/json"
	"strings"
)

// 지난 대화 기억 제한 (SPEC.md API-001 memory · API-003, F-019). UTF-16 코드 단위로 센다.
// API-003 요약 응답도 같은 제한으로 자르므로, 앱은 받은 요약을 그대로 다시 보낼 수 있다.
const (
	MaxMemoryEntries   = 5
	MaxMemoryDate      = 20
	MaxMemorySummary   = 600
	MaxMemoryFacts     = 5
	MaxMemoryFollowUps = 3
	MaxMemoryItem      = 100
)

// MemoryEntry는 끝난 대화 세션 하나의 요약이다 (F-019, ARCHITECTURE.md ADR-024).
// 앱이 기기에 저장해 두고 다음 대화 요청에 싣는다 — 서버는 저장하지 않는다 (ADR-004 무상태).
type MemoryEntry struct {
	Date      string   `json:"date,omitempty"`
	Summary   string   `json:"summary"`
	Facts     []string `json:"facts"`
	FollowUps []string `json:"followUps"`
}

const (
	memoryIntro = "지난 대화 기억 (사용자 기기에 저장된 이전 대화 세션 요약이에요. 오래된 것부터 적었어요. " +
		"이 맥락을 바탕으로 대화를 자연스럽게 이어 가되, 사용자가 묻지 않으면 요약을 그대로 읽어 주지 마세요. " +
		"지금 대화에서 사용자가 다르게 말하면 지금 말을 따르세요):"
	memoryFactsLabel     = "알게 된 점: "
	memoryFollowUpsLabel = "다음에 이어 갈 것: "
	memoryInvalidText    = "요청 형식이 올바르지 않아요. memory 형식을 확인해 주세요."
)

// MemoryPrompt는 지난 대화 기억(장기 기억 + 최근 요약)을 시스템 프롬프트 한 덩어리로 바꾼다. 둘 다 없으면 빈 문자열.
func MemoryPrompt(longTerm *LongTerm, entries []MemoryEntry) string {
	if longTerm == nil && len(entries) == 0 {
		return ""
	}
	lines := []string{memoryIntro}
	if lt := longTermPrompt(longTerm); lt != "" {
		lines = append(lines, lt)
	}
	for _, e := range entries {
		lines = append(lines, memoryLine(e))
	}
	return strings.Join(lines, "\n")
}

// memoryLine은 요약 하나를 "- 날짜: 요약 / 알게 된 점: … / 다음에 이어 갈 것: …" 한 줄로 만든다.
func memoryLine(e MemoryEntry) string {
	line := "- "
	if e.Date != "" {
		line += e.Date + ": "
	}
	line += e.Summary
	if len(e.Facts) > 0 {
		line += " / " + memoryFactsLabel + strings.Join(e.Facts, "; ")
	}
	if len(e.FollowUps) > 0 {
		line += " / " + memoryFollowUpsLabel + strings.Join(e.FollowUps, "; ")
	}
	return line
}

// parseMemory는 API-001 memory 값을 검증한다: 0~5개, 각 요약 1~600자. 모르는 필드는 무시한다.
func parseMemory(raw json.RawMessage) ([]MemoryEntry, *ValidationError) {
	return parseMemoryList(raw, MaxMemoryEntries)
}

// parseMemoryList는 요약 배열을 검증한다: 0~max개. 빈 배열은 nil.
func parseMemoryList(raw json.RawMessage, max int) ([]MemoryEntry, *ValidationError) {
	bad := invalid("INVALID_INPUT", memoryInvalidText)
	var list []json.RawMessage
	if !bytes.HasPrefix(bytes.TrimSpace(raw), []byte("[")) || json.Unmarshal(raw, &list) != nil || len(list) > max {
		return nil, bad
	}
	out := make([]MemoryEntry, 0, len(list))
	for _, item := range list {
		var obj map[string]json.RawMessage
		if !bytes.HasPrefix(bytes.TrimSpace(item), []byte("{")) || json.Unmarshal(item, &obj) != nil {
			return nil, bad
		}
		var e MemoryEntry
		var ok bool
		if e.Summary, ok = strField(obj, "summary", MaxMemorySummary, true); !ok {
			return nil, bad
		}
		if e.Date, ok = strField(obj, "date", MaxMemoryDate, false); !ok {
			return nil, bad
		}
		if e.Facts, ok = strList(obj, "facts", MaxMemoryFacts, MaxMemoryItem); !ok {
			return nil, bad
		}
		if e.FollowUps, ok = strList(obj, "followUps", MaxMemoryFollowUps, MaxMemoryItem); !ok {
			return nil, bad
		}
		out = append(out, e)
	}
	if len(out) == 0 {
		return nil, nil
	}
	return out, nil
}

// strField는 obj[key] 문자열을 앞뒤 공백을 빼고 읽는다. 없으면 required가 아닐 때만 통과.
func strField(obj map[string]json.RawMessage, key string, max int, required bool) (string, bool) {
	v, has := obj[key]
	if !has {
		return "", !required
	}
	var s string
	if bytes.Equal(bytes.TrimSpace(v), []byte("null")) || json.Unmarshal(v, &s) != nil {
		return "", false
	}
	s = strings.TrimSpace(s)
	if utf16Len(s) > max || (required && s == "") {
		return "", false
	}
	return s, true
}

// strList는 obj[key] 문자열 배열을 읽는다. 없으면 nil. 항목은 1~maxItem자.
func strList(obj map[string]json.RawMessage, key string, maxLen, maxItem int) ([]string, bool) {
	v, has := obj[key]
	if !has {
		return nil, true
	}
	var items []json.RawMessage
	if json.Unmarshal(v, &items) != nil || items == nil || len(items) > maxLen {
		return nil, false
	}
	var out []string
	for _, it := range items {
		var s string
		if bytes.Equal(bytes.TrimSpace(it), []byte("null")) || json.Unmarshal(it, &s) != nil {
			return nil, false
		}
		s = strings.TrimSpace(s)
		if s == "" || utf16Len(s) > maxItem {
			return nil, false
		}
		out = append(out, s)
	}
	return out, true
}
