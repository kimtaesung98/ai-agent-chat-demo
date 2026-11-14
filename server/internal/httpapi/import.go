package httpapi

import (
	"bytes"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/account"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
)

// 기기 데이터 옮기기 (SPEC.md F-026 상세 동작 9, AC8, API-014).
// 앱이 처음 로그인한 뒤 기기의 페르소나·요약·장기 기억·"나에 대해"를 한 번 올린다.
// clientId로 같은 것을 알아보므로 두 번 올려도 늘지 않는다. 서버에 이미 있는 값은 덮어쓰지 않는다.

const (
	maxImportSummaries = 200
	maxImportClientID  = 64
)

type importSummary struct {
	ClientID        string          `json:"clientId"`
	PersonaClientID string          `json:"personaClientId"`
	EndedAt         string          `json:"endedAt"`
	Summary         string          `json:"summary"`
	Facts           json.RawMessage `json:"facts"`
	FollowUps       json.RawMessage `json:"followUps"`
	Turns           int             `json:"turns"`
}

type importLongTerm struct {
	PersonaClientID string          `json:"personaClientId"`
	Summary         string          `json:"summary"`
	Facts           json.RawMessage `json:"facts"`
	CoversUntil     string          `json:"coversUntil"`
}

type importBody struct {
	Profile *struct {
		About *string `json:"about"`
	} `json:"profile"`
	Personas  []json.RawMessage `json:"personas"`
	Summaries []importSummary   `json:"summaries"`
	LongTerm  []importLongTerm  `json:"longTerm"`
}

const msgImportInvalid = "옮길 데이터 형식이 올바르지 않아요."

// cleanItems는 문자열 배열을 자르고 빈 값을 버린다 (모양이 틀리면 빈 배열).
func cleanItems(raw json.RawMessage, maxItems, maxLen int) []string {
	var list []string
	if len(raw) == 0 || json.Unmarshal(raw, &list) != nil {
		return []string{}
	}
	out := []string{}
	for _, v := range list {
		v = strings.Join(strings.Fields(v), " ")
		if v == "" {
			continue
		}
		v = cutUTF16(v, maxLen)
		out = append(out, v)
		if len(out) == maxItems {
			break
		}
	}
	return out
}

func (s *server) handleImport(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	var req importBody
	if !bytes.HasPrefix(bytes.TrimSpace(body), []byte("{")) || json.Unmarshal(body, &req) != nil ||
		len(req.Personas) > MaxPersonas || len(req.Summaries) > maxImportSummaries || len(req.LongTerm) > MaxPersonas {
		writeError(w, http.StatusBadRequest, "INVALID_INPUT", msgImportInvalid)
		return
	}
	// 먼저 모두 검증한다 — 하나라도 틀리면 아무것도 바꾸지 않는다
	var personas []chat.PersonaV1
	for _, raw := range req.Personas {
		v, verr := chat.ParsePersonaV1(raw, false)
		if verr != nil || v.ClientID == "" {
			writeError(w, http.StatusBadRequest, "INVALID_INPUT", msgImportInvalid)
			return
		}
		personas = append(personas, v)
	}
	ctx := r.Context()
	if err := s.seedPersonas(r, user.ID); err != nil {
		s.storeError(w, err)
		return
	}
	existing, err := s.store.ListPersonas(ctx, user.ID)
	if err != nil {
		s.storeError(w, err)
		return
	}
	byClient := map[string]store.Persona{}
	for _, p := range existing {
		if p.ClientID != "" {
			byClient[p.ClientID] = p
		}
	}
	// 20개를 넘기게 되면 아무것도 바꾸지 않고 400
	free := map[string]int{}
	for _, e := range existing {
		if e.Kind == chat.KindPreset && e.ClientID == "" {
			free[e.PresetID]++
		}
	}
	need, seen := 0, map[string]bool{}
	for _, v := range personas {
		if _, done := byClient[v.ClientID]; done || seen[v.ClientID] {
			continue
		}
		seen[v.ClientID] = true
		if v.Kind == chat.KindPreset && free[v.PresetID] > 0 {
			free[v.PresetID]--
			continue
		}
		need++
	}
	if len(existing)+need > MaxPersonas {
		writeError(w, http.StatusBadRequest, "INVALID_INPUT", msgPersonaLimit)
		return
	}
	created, merged := 0, 0
	for _, v := range personas {
		if _, done := byClient[v.ClientID]; done {
			continue // 두 번째 옮기기
		}
		now := time.Now()
		// 탑재 페르소나는 처음 넣어 둔 것(clientId 없음)에 기기 값을 얹는다
		var target *store.Persona
		if v.Kind == chat.KindPreset {
			for i := range existing {
				if e := existing[i]; e.Kind == chat.KindPreset && e.PresetID == v.PresetID && e.ClientID == "" {
					target = &existing[i]
					break
				}
			}
		}
		if target != nil {
			next := fromV1(v, target.ID, user.ID, now)
			next.CreatedAt, next.Revision = target.CreatedAt, target.Revision+1
			if err := s.store.UpdatePersona(ctx, next); err != nil {
				s.storeError(w, err)
				return
			}
			target.ClientID = v.ClientID
			byClient[v.ClientID] = next
			merged++
			continue
		}
		p := fromV1(v, account.NewID("per_"), user.ID, now)
		if err := s.store.CreatePersona(ctx, p, MaxPersonas); err != nil {
			s.storeError(w, err)
			return
		}
		byClient[v.ClientID] = p
		created++
	}

	summaries := 0
	touched := map[string]bool{}
	for _, sm := range req.Summaries {
		p, ok := byClient[sm.PersonaClientID]
		text := cutUTF16(strings.Join(strings.Fields(sm.Summary), " "), chat.MaxMemorySummary)
		if !ok || text == "" || sm.ClientID == "" || len(sm.ClientID) > maxImportClientID {
			continue // 대상 페르소나가 없거나 빈 요약은 건너뛴다
		}
		ended, err := time.Parse(time.RFC3339, sm.EndedAt)
		if err != nil {
			ended = time.Now()
		}
		_, err = s.store.PutSummary(ctx, store.Summary{
			ID: account.NewID("sum_"), UserID: user.ID, PersonaID: p.ID,
			ConversationID: "imp_" + user.ID + "_" + sm.ClientID, // 사람마다 유일 — 다시 올리면 같은 행
			EndedAt:        ended, Summary: text, Turns: max(sm.Turns, 0),
			Facts:     cleanItems(sm.Facts, chat.MaxMemoryFacts, chat.MaxMemoryItem),
			FollowUps: cleanItems(sm.FollowUps, chat.MaxMemoryFollowUps, chat.MaxMemoryItem),
		})
		if err != nil {
			s.storeError(w, err)
			return
		}
		touched[p.ID] = true
		summaries++
	}

	longTerm := 0
	for _, lt := range req.LongTerm {
		p, ok := byClient[lt.PersonaClientID]
		text := cutUTF16(strings.Join(strings.Fields(lt.Summary), " "), chat.MaxLongTermSummary)
		if !ok || text == "" {
			continue
		}
		if _, err := s.store.GetLongTerm(ctx, user.ID, p.ID); err == nil {
			continue // 서버 값이 있으면 그대로
		} else if !errors.Is(err, store.ErrNotFound) {
			s.storeError(w, err)
			return
		}
		covers, err := time.Parse(time.RFC3339, lt.CoversUntil)
		if err != nil {
			covers = time.Now()
		}
		mem := store.LongTermMemory{PersonaID: p.ID, UserID: user.ID, Summary: text, Facts: cleanItems(lt.Facts, chat.MaxLongTermFacts, chat.MaxMemoryItem), CoversUntil: covers, UpdatedAt: time.Now()}
		if err := s.store.FoldInto(ctx, mem, nil); err != nil {
			s.storeError(w, err)
			return
		}
		longTerm++
	}

	// 페르소나마다 요약은 MaxSummariesPerPersona개까지 — 오래된 것부터 지운다
	for pid := range touched {
		all, err := s.store.ListSummaries(ctx, user.ID, pid)
		if err != nil {
			s.storeError(w, err)
			return
		}
		if extra := len(all) - MaxSummariesPerPersona; extra > 0 {
			var ids []string
			for _, sm := range all[:extra] {
				ids = append(ids, sm.ID)
			}
			if err := s.store.DeleteSummaries(ctx, user.ID, ids); err != nil {
				s.storeError(w, err)
				return
			}
		}
	}

	aboutSet := false
	if req.Profile != nil && req.Profile.About != nil {
		about := cutUTF16(strings.TrimSpace(*req.Profile.About), chat.MaxPersonaAbout)
		prof, err := s.profileOf(ctx, user.ID)
		if err != nil {
			s.storeError(w, err)
			return
		}
		if prof.About == "" && about != "" { // 서버 값이 있으면 그대로
			prof.About, prof.UpdatedAt = about, time.Now()
			if err := s.store.PutProfile(ctx, prof); err != nil {
				s.storeError(w, err)
				return
			}
			aboutSet = true
		}
	}

	ids := map[string]string{}
	for c, p := range byClient {
		ids[c] = p.ID
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"personasCreated": created, "personasMerged": merged, "summaries": summaries, "longTerm": longTerm, "about": aboutSet,
		"personaIds": ids, // 기기 id(clientId) → 서버 id
	})
}

// cutUTF16은 UTF-16 코드 단위 max까지 자른다.
func cutUTF16(s string, max int) string {
	n := 0
	for i, r := range s {
		w := 1
		if r >= 0x10000 {
			w = 2
		}
		if n+w > max {
			return s[:i]
		}
		n += w
	}
	return s
}
