package httpapi

import (
	"errors"
	"net/http"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/account"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
)

// 페르소나 형식 v1 API (SPEC.md F-027, API-015·016, ARCHITECTURE.md ADR-030).
// 남의 페르소나는 ?userId=로 — 원장은 모두, 요양사는 맡은 어르신, 보호자는 연결된 어르신 보기만 (account.PersonaOwner).

// MaxPersonas는 사람마다 가질 수 있는 페르소나 수다 (F-027 상세 동작 5).
const MaxPersonas = 20

const (
	msgPersonaLimit    = "대화 상대는 20개까지 만들 수 있어요. 안 쓰는 대화 상대를 지운 뒤 다시 해 주세요."
	msgPersonaConflict = "다른 기기에서 먼저 고쳤어요. 최신 내용을 다시 불러왔어요."
)

func (s *server) handlePresets(w http.ResponseWriter, r *http.Request) {
	ps := chat.Presets()
	out := make([]map[string]any, 0, len(ps))
	for _, p := range ps {
		out = append(out, map[string]any{"id": p.ID, "version": p.Version, "name": p.Name, "role": p.Role, "tones": nonNil(p.Tones), "base": p.Base, "recommended": p.Recommended(s.authOpts.CareSetting)})
	}
	writeJSON(w, http.StatusOK, map[string]any{"presets": out, "careSetting": s.authOpts.CareSetting})
}

// personaJSON은 §7.2 형식의 응답이다. preset이면 카탈로그 base를 읽기용으로 붙인다.
func personaJSON(p store.Persona) map[string]any {
	m := map[string]any{
		"schema": chat.PersonaSchema, "id": p.ID, "kind": p.Kind, "name": p.Name, "role": p.Role, "tones": nonNil(p.Tones),
		"instructions": p.Instructions, "revision": p.Revision,
		"createdAt": p.CreatedAt.UTC().Format(time.RFC3339), "updatedAt": p.UpdatedAt.UTC().Format(time.RFC3339),
	}
	if p.Kind == chat.KindPreset {
		m["presetId"] = p.PresetID
		if pr, ok := chat.PresetByID(p.PresetID); ok {
			m["base"] = pr.Base
		}
	}
	if p.ClientID != "" {
		m["clientId"] = p.ClientID
	}
	return m
}

// PersonaPrompt는 저장된 페르소나를 시스템 프롬프트용으로 바꾼다 (F-027 AC2 — base는 카탈로그). F-028에서 쓴다.
func PersonaPrompt(p store.Persona, about string) (*chat.Persona, bool) {
	return chat.PersonaV1{Kind: p.Kind, PresetID: p.PresetID, Name: p.Name, Role: p.Role, Tones: p.Tones, Instructions: p.Instructions}.Prompt(about)
}

// personaOwner는 요청한 사람과 ?userId= 대상을 확인한다. 실패하면 응답을 쓰고 false.
func (s *server) personaOwner(w http.ResponseWriter, r *http.Request, write bool) (store.User, bool) {
	actor, ok := requireUser(w, r)
	if !ok {
		return store.User{}, false
	}
	owner, err := s.accounts.PersonaOwner(r.Context(), actor, r.URL.Query().Get("userId"), write)
	if err != nil {
		s.accountError(w, err)
		return store.User{}, false
	}
	return owner, true
}

func (s *server) storeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "NOT_FOUND", "찾을 수 없어요.")
	case errors.Is(err, store.ErrQuota):
		writeError(w, http.StatusBadRequest, "INVALID_INPUT", msgPersonaLimit)
	case errors.Is(err, store.ErrConflict):
		writeError(w, http.StatusConflict, "CONFLICT", "이미 있는 값이에요.")
	default:
		s.log.Error("store error")
		writeError(w, http.StatusInternalServerError, "INTERNAL", "서버 오류가 발생했어요.")
	}
}

func fromV1(v chat.PersonaV1, id, userID string, now time.Time) store.Persona {
	return store.Persona{ID: id, UserID: userID, Kind: v.Kind, PresetID: v.PresetID, Name: v.Name, Role: v.Role, Tones: v.Tones,
		Instructions: v.Instructions, ClientID: v.ClientID, Revision: 1, CreatedAt: now, UpdatedAt: now}
}

// seedPersonas는 처음 보는 계정에 탑재 페르소나 4개를 넣는다 (F-027 상세 동작 5). 한 번만.
func (s *server) seedPersonas(r *http.Request, userID string) error {
	now := time.Now()
	var ps []store.Persona
	for i, pr := range chat.Presets() {
		at := now.Add(time.Duration(i) * time.Microsecond) // 카탈로그 순서대로 보이게
		ps = append(ps, fromV1(chat.FromPreset(pr), account.NewID("per_"), userID, at))
	}
	_, err := s.store.SeedPersonas(r.Context(), userID, ps)
	return err
}

func (s *server) listPersonas(w http.ResponseWriter, r *http.Request, userID string) {
	list, err := s.store.ListPersonas(r.Context(), userID)
	if err != nil {
		s.storeError(w, err)
		return
	}
	out := make([]map[string]any, 0, len(list))
	for _, p := range list {
		out = append(out, personaJSON(p))
	}
	writeJSON(w, http.StatusOK, map[string]any{"personas": out, "max": MaxPersonas})
}

func (s *server) handleListPersonas(w http.ResponseWriter, r *http.Request) {
	owner, ok := s.personaOwner(w, r, false)
	if !ok {
		return
	}
	if err := s.seedPersonas(r, owner.ID); err != nil {
		s.storeError(w, err)
		return
	}
	s.listPersonas(w, r, owner.ID)
}

func (s *server) handleCreatePersona(w http.ResponseWriter, r *http.Request) {
	owner, ok := s.personaOwner(w, r, true)
	if !ok {
		return
	}
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	v, verr := chat.ParsePersonaV1(body, false)
	if verr != nil {
		writeError(w, http.StatusBadRequest, verr.Code, verr.Message)
		return
	}
	if err := s.seedPersonas(r, owner.ID); err != nil { // 처음 만들기 전에 탑재 4개를 먼저 — 나중에 다시 생기지 않게
		s.storeError(w, err)
		return
	}
	p := fromV1(v, account.NewID("per_"), owner.ID, time.Now())
	if err := s.store.CreatePersona(r.Context(), p, MaxPersonas); err != nil {
		s.storeError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, personaJSON(p))
}

func (s *server) handleGetPersona(w http.ResponseWriter, r *http.Request) {
	owner, ok := s.personaOwner(w, r, false)
	if !ok {
		return
	}
	p, err := s.store.GetPersona(r.Context(), owner.ID, r.PathValue("id"))
	if err != nil {
		s.storeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, personaJSON(p))
}

func (s *server) handleUpdatePersona(w http.ResponseWriter, r *http.Request) {
	owner, ok := s.personaOwner(w, r, true)
	if !ok {
		return
	}
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	v, verr := chat.ParsePersonaV1(body, true)
	if verr != nil {
		writeError(w, http.StatusBadRequest, verr.Code, verr.Message)
		return
	}
	cur, err := s.store.GetPersona(r.Context(), owner.ID, r.PathValue("id"))
	if err != nil {
		s.storeError(w, err)
		return
	}
	next := fromV1(v, cur.ID, owner.ID, time.Now())
	next.CreatedAt, next.ClientID, next.Revision = cur.CreatedAt, cur.ClientID, v.Revision+1
	err = s.store.UpdatePersona(r.Context(), next)
	if errors.Is(err, store.ErrConflict) {
		// F-027 AC3: 저장 값은 그대로, 앱이 다시 보여 줄 수 있게 서버 값을 같이 준다
		if latest, gerr := s.store.GetPersona(r.Context(), owner.ID, cur.ID); gerr == nil {
			writeJSON(w, http.StatusConflict, map[string]any{"error": map[string]string{"code": "CONFLICT", "message": msgPersonaConflict}, "persona": personaJSON(latest)})
			return
		}
	}
	if err != nil {
		s.storeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, personaJSON(next))
}

func (s *server) handleDeletePersona(w http.ResponseWriter, r *http.Request) {
	owner, ok := s.personaOwner(w, r, true)
	if !ok {
		return
	}
	if err := s.store.DeletePersona(r.Context(), owner.ID, r.PathValue("id")); err != nil {
		s.storeError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleRestorePresets는 지운 탑재 페르소나를 다시 넣는다 ("탑재 페르소나 다시 넣기", F-027 상세 동작 5).
func (s *server) handleRestorePresets(w http.ResponseWriter, r *http.Request) {
	owner, ok := s.personaOwner(w, r, true)
	if !ok {
		return
	}
	if err := s.seedPersonas(r, owner.ID); err != nil {
		s.storeError(w, err)
		return
	}
	list, err := s.store.ListPersonas(r.Context(), owner.ID)
	if err != nil {
		s.storeError(w, err)
		return
	}
	have := map[string]bool{}
	for _, p := range list {
		if p.Kind == chat.KindPreset {
			have[p.PresetID] = true
		}
	}
	for _, pr := range chat.Presets() {
		if have[pr.ID] {
			continue
		}
		err := s.store.CreatePersona(r.Context(), fromV1(chat.FromPreset(pr), account.NewID("per_"), owner.ID, time.Now()), MaxPersonas)
		if err != nil {
			s.storeError(w, err)
			return
		}
	}
	s.listPersonas(w, r, owner.ID)
}
