package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/account"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/usage"
)

// 대화·요약·기억의 서버 처리 (SPEC.md F-028, API-017·018, ARCHITECTURE.md ADR-031).
//
//	앱 ── POST /api/conversations {personaId} ──▶ 대화 열기
//	앱 ── POST /api/chat {conversationId, messages} ──▶ 서버가 DB의 페르소나·최근 요약 5개·장기 기억을 붙인다
//	앱 ── POST /api/conversations/{id}/end {messages} ──▶ 요약 저장, 묶이지 않은 요약이 5개를 넘으면 장기 기억 묶기
//
// 원문(messages)은 처리만 하고 저장·로그하지 않는다 (Q-009 — 기기에 계속 보관).

const (
	// RecentSummaries는 프롬프트에 싣는 최근 요약 수다 (API-001 memory 상한과 같다).
	RecentSummaries = chat.MaxMemoryEntries
	// MaxSummariesPerPersona는 페르소나마다 남기는 요약 수다. 넘으면 묶인 것부터 지운다.
	MaxSummariesPerPersona = 20
	maxConversationID      = 64
)

var seoul = time.FixedZone("KST", 9*60*60)

func conversationJSON(c store.Conversation) map[string]any {
	m := map[string]any{"id": c.ID, "personaId": c.PersonaID, "channel": c.Channel, "status": c.Status, "startedAt": c.StartedAt.UTC().Format(time.RFC3339), "turns": c.Turns}
	if !c.EndedAt.IsZero() {
		m["endedAt"] = c.EndedAt.UTC().Format(time.RFC3339)
	}
	return m
}

func summaryJSON(s store.Summary) map[string]any {
	return map[string]any{"id": s.ID, "conversationId": s.ConversationID, "personaId": s.PersonaID, "endedAt": s.EndedAt.UTC().Format(time.RFC3339),
		"summary": s.Summary, "facts": nonNil(s.Facts), "followUps": nonNil(s.FollowUps), "turns": s.Turns, "folded": s.Folded}
}

func longTermJSON(lt store.LongTermMemory) map[string]any {
	return map[string]any{"summary": lt.Summary, "facts": nonNil(lt.Facts), "coversUntil": lt.CoversUntil.UTC().Format(time.RFC3339), "updatedAt": lt.UpdatedAt.UTC().Format(time.RFC3339)}
}

func memoryEntry(s store.Summary) chat.MemoryEntry {
	return chat.MemoryEntry{Date: s.EndedAt.In(seoul).Format("2006-01-02"), Summary: s.Summary, Facts: s.Facts, FollowUps: s.FollowUps}
}

// memoryOf는 그 페르소나의 장기 기억(없으면 nil)과 묶이지 않은 최근 요약 n개(오래된 것부터)다.
func (s *server) memoryOf(ctx context.Context, userID, personaID string, n int) (*chat.LongTerm, []store.Summary, error) {
	var lt *chat.LongTerm
	switch got, err := s.store.GetLongTerm(ctx, userID, personaID); {
	case err == nil:
		lt = &chat.LongTerm{Summary: got.Summary, Facts: got.Facts}
	case !errors.Is(err, store.ErrNotFound):
		return nil, nil, err
	}
	all, err := s.store.ListSummaries(ctx, userID, personaID)
	if err != nil {
		return nil, nil, err
	}
	var open []store.Summary
	for _, sm := range all {
		if !sm.Folded {
			open = append(open, sm)
		}
	}
	if len(open) > n {
		open = open[len(open)-n:]
	}
	return lt, open, nil
}

// conversationID는 API-001·007 본문의 선택 필드 conversationId다. 없으면 "", 모양이 틀리면 false.
func conversationID(body []byte) (string, bool) {
	var root map[string]json.RawMessage
	if json.Unmarshal(body, &root) != nil {
		return "", true // 본문 검증은 chat이 한다
	}
	raw, has := root["conversationId"]
	if !has || string(raw) == "null" {
		return "", true
	}
	var id string
	if json.Unmarshal(raw, &id) != nil || id == "" || len(id) > maxConversationID {
		return "", false
	}
	return id, true
}

// conversationPrompt는 conversationId가 있는 요청에 DB의 페르소나·기억을 붙인다 (F-028 AC1).
// 앱이 보낸 persona·memory·longTerm은 버린다. 처리했으면 true, 응답을 썼으면 false.
func (s *server) conversationPrompt(w http.ResponseWriter, r *http.Request, body []byte, persona **chat.Persona, memory *[]chat.MemoryEntry, longTerm **chat.LongTerm) bool {
	id, ok := conversationID(body)
	if !ok {
		writeError(w, http.StatusBadRequest, "INVALID_INPUT", "conversationId 형식이 올바르지 않아요.")
		return false
	}
	if id == "" || s.store == nil {
		return true
	}
	user, ok := requireUser(w, r)
	if !ok {
		return false
	}
	ctx := r.Context()
	c, err := s.store.GetConversation(ctx, user.ID, id)
	if err != nil {
		s.storeError(w, err) // 남의 대화면 404
		return false
	}
	p, err := s.store.GetPersona(ctx, user.ID, c.PersonaID)
	if err != nil {
		s.storeError(w, err)
		return false
	}
	prof, err := s.profileOf(ctx, user.ID)
	if err != nil {
		s.storeError(w, err)
		return false
	}
	cp, ok := PersonaPrompt(p, prof.About) // F-028 AC1: 프로필의 "나에 대해"
	if !ok {
		writeError(w, http.StatusBadRequest, "INVALID_INPUT", "대화 상대를 찾을 수 없어요.")
		return false
	}
	lt, recent, err := s.memoryOf(ctx, user.ID, p.ID, RecentSummaries)
	if err != nil {
		s.storeError(w, err)
		return false
	}
	var entries []chat.MemoryEntry
	for _, sm := range recent {
		entries = append(entries, memoryEntry(sm))
	}
	*persona, *memory, *longTerm = cp, entries, lt
	if err := s.store.AddConversationTurn(ctx, user.ID, c.ID); err != nil {
		s.log.Warn("conversation turn count failed")
	}
	return true
}

func (s *server) handleOpenConversation(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	var req struct {
		PersonaID string `json:"personaId"`
		Channel   string `json:"channel"`
	}
	if !decode(w, r, &req) {
		return
	}
	if req.Channel == "" {
		req.Channel = "text"
	}
	if req.Channel != "text" && req.Channel != "voice" {
		writeError(w, http.StatusBadRequest, "INVALID_INPUT", "channel은 text 또는 voice여야 해요.")
		return
	}
	if _, err := s.store.GetPersona(r.Context(), user.ID, req.PersonaID); err != nil {
		s.storeError(w, err)
		return
	}
	c := store.Conversation{ID: account.NewID("cnv_"), UserID: user.ID, PersonaID: req.PersonaID, Channel: req.Channel, Status: "open", StartedAt: time.Now()}
	if err := s.store.CreateConversation(r.Context(), c); err != nil {
		s.storeError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, conversationJSON(c))
}

// complete는 제공자 답을 끝까지 모은다 (응답을 쓰지 않는다).
func (s *server) complete(ctx context.Context, route, system string, msgs []chat.Message) (string, error) {
	var text strings.Builder
	for c, err := range s.provider.Stream(ctx, system, msgs) {
		if err != nil {
			var pe *provider.Error
			if errors.As(err, &pe) {
				s.log.Warn("provider error", "code", pe.Code, "status", pe.Status, "route", route)
			}
			return "", err
		}
		text.WriteString(c.Text)
	}
	return text.String(), ctx.Err()
}

// handleEndConversation은 대화를 끝내고 요약·장기 기억을 만든다 (F-028 상세 동작 4, AC2).
// 원문 messages는 요약에만 쓰고 저장하지 않는다. 다시 부르면 그 대화의 요약을 바꾼다.
func (s *server) handleEndConversation(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	ctx := r.Context()
	c, err := s.store.GetConversation(ctx, user.ID, r.PathValue("id"))
	if err != nil {
		s.storeError(w, err)
		return
	}
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	var root struct {
		Messages []json.RawMessage `json:"messages"`
	}
	if len(strings.TrimSpace(string(body))) > 0 && json.Unmarshal(body, &root) != nil {
		writeError(w, http.StatusBadRequest, "INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
		return
	}
	now := time.Now()
	if c.EndedAt.IsZero() {
		c.EndedAt = now
	}
	if c.Status == "open" {
		c.Status = "ended"
	}
	if err := s.store.UpdateConversation(ctx, c); err != nil {
		s.storeError(w, err)
		return
	}
	if len(root.Messages) == 0 { // 주고받은 말이 없으면 요약 없이 끝낸다
		writeJSON(w, http.StatusOK, map[string]any{"conversation": conversationJSON(c), "summary": nil})
		return
	}
	req, verr := chat.ParseSummaryRequest(body)
	if verr != nil {
		writeError(w, http.StatusBadRequest, verr.Code, verr.Message)
		return
	}
	p, err := s.store.GetPersona(ctx, user.ID, c.PersonaID)
	if err != nil {
		s.storeError(w, err)
		return
	}
	cp, _ := PersonaPrompt(p, "")
	req.Persona = cp
	if !s.background(w, ctx) {
		return
	}
	text, err := s.complete(ctx, "end", chat.SummarySystemPrompt, req.Transcript())
	if ctx.Err() != nil {
		return
	}
	sum, ok := chat.ParseSummary(text)
	if err != nil || !ok {
		// 대화는 ended로 남는다 — 앱이 기기 원문으로 /end를 다시 부르면 그때 만든다
		writeError(w, http.StatusBadGateway, "PROVIDER_ERROR", chat.SummaryUnavailable)
		return
	}
	turns := 0
	for _, m := range req.Messages {
		if m.Role == chat.RoleUser {
			turns++
		}
	}
	saved, err := s.store.PutSummary(ctx, store.Summary{ID: account.NewID("sum_"), UserID: user.ID, PersonaID: p.ID, ConversationID: c.ID,
		EndedAt: c.EndedAt, Summary: sum.Summary, Facts: sum.Facts, FollowUps: sum.FollowUps, Turns: turns})
	if err != nil {
		s.storeError(w, err)
		return
	}
	c.Status, c.Turns = "summarized", max(c.Turns, turns)
	if err := s.store.UpdateConversation(ctx, c); err != nil {
		s.storeError(w, err)
		return
	}
	s.fold(ctx, user.ID, p, cp)
	writeJSON(w, http.StatusOK, map[string]any{"conversation": conversationJSON(c), "summary": summaryJSON(saved)})
}

// background는 요약·장기 기억 호출을 사용량에 센다. 막으면 응답을 쓰고 false.
func (s *server) background(w http.ResponseWriter, ctx context.Context) bool {
	if s.limiter == nil {
		return true
	}
	err := s.limiter.Background(ctx)
	if errors.Is(err, usage.ErrQuota) {
		writeError(w, http.StatusTooManyRequests, "QUOTA_EXCEEDED", msgQuota)
		return false
	} else if err != nil {
		s.log.Error("usage check failed")
		writeError(w, http.StatusInternalServerError, "INTERNAL", "서버 오류가 발생했어요.")
		return false
	}
	return true
}

// fold는 묶이지 않은 요약이 RecentSummaries개를 넘으면 오래된 것을 장기 기억에 묶는다 (F-020 규칙).
// 실패해도 요약은 남고, 다음 끝내기에서 다시 묶는다. 페르소나마다 요약은 MaxSummariesPerPersona개까지.
func (s *server) fold(ctx context.Context, userID string, p store.Persona, cp *chat.Persona) {
	all, err := s.store.ListSummaries(ctx, userID, p.ID)
	if err != nil {
		s.log.Warn("fold: list failed")
		return
	}
	var open, folded []store.Summary
	for _, sm := range all {
		if sm.Folded {
			folded = append(folded, sm)
		} else {
			open = append(open, sm)
		}
	}
	if n := len(open) - RecentSummaries; n > 0 {
		batch := open[:min(n, chat.MaxConsolidateSessions)]
		req := chat.ConsolidateRequest{Persona: cp}
		if lt, err := s.store.GetLongTerm(ctx, userID, p.ID); err == nil {
			req.LongTerm = &chat.LongTerm{Summary: lt.Summary, Facts: lt.Facts}
		}
		for _, sm := range batch {
			req.Sessions = append(req.Sessions, memoryEntry(sm))
		}
		if s.limiter != nil && s.limiter.Background(ctx) != nil {
			return
		}
		text, err := s.complete(ctx, "fold", chat.ConsolidateSystemPrompt, req.Transcript())
		lt, ok := chat.ParseLongTerm(text)
		if err != nil || !ok {
			s.log.Warn("fold: consolidate failed")
			return
		}
		var ids []string
		for _, sm := range batch {
			ids = append(ids, sm.ID)
		}
		mem := store.LongTermMemory{PersonaID: p.ID, UserID: userID, Summary: lt.Summary, Facts: lt.Facts, CoversUntil: batch[len(batch)-1].EndedAt, UpdatedAt: time.Now()}
		if err := s.store.FoldInto(ctx, mem, ids); err != nil {
			s.log.Warn("fold: save failed")
			return
		}
		folded = append(folded, batch...)
	}
	if extra := len(all) - MaxSummariesPerPersona; extra > 0 && len(folded) > 0 {
		var ids []string
		for _, sm := range folded[:min(extra, len(folded))] {
			ids = append(ids, sm.ID)
		}
		if err := s.store.DeleteSummaries(ctx, userID, ids); err != nil {
			s.log.Warn("fold: prune failed")
		}
	}
}

// --- 기억 보기·지우기 (API-018, F-029 보는 범위) ---

func (s *server) handlePersonaMemory(w http.ResponseWriter, r *http.Request) {
	owner, ok := s.personaOwner(w, r, false)
	if !ok {
		return
	}
	ctx := r.Context()
	p, err := s.store.GetPersona(ctx, owner.ID, r.PathValue("id"))
	if err != nil {
		s.storeError(w, err)
		return
	}
	all, err := s.store.ListSummaries(ctx, owner.ID, p.ID)
	if err != nil {
		s.storeError(w, err)
		return
	}
	out := map[string]any{"personaId": p.ID, "longTerm": nil, "summaries": []map[string]any{}}
	sums := make([]map[string]any, 0, len(all))
	for _, sm := range all {
		sums = append(sums, summaryJSON(sm))
	}
	out["summaries"] = sums
	switch lt, err := s.store.GetLongTerm(ctx, owner.ID, p.ID); {
	case err == nil:
		out["longTerm"] = longTermJSON(lt)
	case !errors.Is(err, store.ErrNotFound):
		s.storeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *server) handleDeletePersonaMemory(w http.ResponseWriter, r *http.Request) {
	owner, ok := s.personaOwner(w, r, true)
	if !ok {
		return
	}
	ctx := r.Context()
	if _, err := s.store.GetPersona(ctx, owner.ID, r.PathValue("id")); err != nil {
		s.storeError(w, err)
		return
	}
	if err := s.store.DeletePersonaMemory(ctx, owner.ID, r.PathValue("id")); err != nil {
		s.storeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) handleDeleteSummary(w http.ResponseWriter, r *http.Request) {
	owner, ok := s.personaOwner(w, r, true)
	if !ok {
		return
	}
	if err := s.store.DeleteSummary(r.Context(), owner.ID, r.PathValue("id")); err != nil {
		s.storeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
