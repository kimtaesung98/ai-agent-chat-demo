package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/account"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/usage"
)

// 계정·로그인·관리 API와 AI 경로 보호 (SPEC.md F-026·F-029·F-030, API-010~022, ADR-029·032·033).
//
//	요청 ─▶ withAccounts ─┬─ /api/auth/* · /api/me · /api/admin/* ─▶ 이 파일의 핸들러
//	                      ├─ AI 경로(/api/chat · /api/summary · /api/consolidate · /api/voice/session)
//	                      │     세션 확인(실제 모드) → 사용량 상한 → 원래 핸들러
//	                      └─ 그 밖 ─▶ 원래 핸들러
//
// 세션 토큰·로그인 코드·이름·이메일은 로그에 남기지 않는다.

// SessionCookie는 세션 쿠키 이름이다.
const SessionCookie = "sid"

// AuthOptions는 계정 기능 설정이다.
type AuthOptions struct {
	GuestMode      bool   // 게스트 체험 (F-030)
	RequireSession bool   // 세션 없는 AI 경로를 닫는다 — 실제 모드. 모의 모드는 열어 둔다
	ClientIPHeader string // 프록시가 넣는 진짜 IP 헤더 (비면 연결 주소)
	CareSetting    string // 배포 유형 (ADR-035) — 앱에 알림
}

// 게스트 글 채팅 제한 (F-030 상세 동작 1·2).
const (
	GuestMaxMessage = 500
	GuestMaxTurns   = 6
)

// 사용자에게 보이는 문장.
const (
	msgBadCode      = "코드를 다시 확인해 주세요."
	msgRateLimited  = "잠시 뒤에 다시 시도해 주세요."
	msgLoginNeeded  = "다시 로그인해 주세요."
	msgNotInvited   = "등록되지 않은 Google 계정이에요. 담당 기관에 로그인 코드를 받아 주세요."
	msgForbidden    = "이 작업을 할 권한이 없어요."
	msgGuestQuota   = "체험은 여기까지예요. 계속하려면 담당 기관에서 로그인 코드를 받아 주세요."
	msgQuota        = "오늘 사용할 수 있는 양을 다 썼어요. 내일 다시 이야기해요."
	msgGuestTooLong = "체험에서는 한 번에 500자까지 보낼 수 있어요."
	msgNeedJSON     = "Content-Type은 application/json이어야 해요."
	msgBadOrigin    = "허용되지 않은 출처의 요청이에요."
)

// WithAccounts는 계정 기능을 켠다.
func WithAccounts(acc *account.Service, lim *usage.Limiter, o AuthOptions) Option {
	return func(s *server) { s.accounts, s.limiter, s.authOpts, s.store = acc, lim, o, acc.Store() }
}

type principalKey struct{}

// PrincipalFrom은 요청한 사람을 꺼낸다 (세션이 없으면 false).
func PrincipalFrom(ctx context.Context) (account.Principal, bool) {
	p, ok := ctx.Value(principalKey{}).(account.Principal)
	return p, ok
}

// aiPaths는 AI 제공자를 부르는 경로다. 게스트는 /api/chat만.
var aiPaths = map[string]bool{"/api/chat": true, "/api/summary": true, "/api/consolidate": true, "/api/voice/session": true}

func (s *server) withAccounts(next http.Handler) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/auth/options", s.handleAuthOptions)
	mux.HandleFunc("POST /api/auth/code", s.handleLoginCode)
	mux.HandleFunc("POST /api/auth/google", s.handleLoginGoogle)
	mux.HandleFunc("POST /api/auth/guest", s.handleGuest)
	mux.HandleFunc("POST /api/auth/logout", s.handleLogout)
	mux.HandleFunc("GET /api/me", s.handleMe)
	mux.HandleFunc("POST /api/me/google", s.handleLinkGoogle)
	mux.HandleFunc("GET /api/admin/users", s.handleListUsers)
	mux.HandleFunc("POST /api/admin/users", s.handleCreateUser)
	mux.HandleFunc("PATCH /api/admin/users/{id}", s.handleUpdateUser)
	mux.HandleFunc("DELETE /api/admin/users/{id}", s.handleDeleteUser)
	mux.HandleFunc("POST /api/admin/users/{id}/code", s.handleReissue)
	mux.HandleFunc("POST /api/admin/care", s.handleCare)
	mux.HandleFunc("POST /api/admin/guardians", s.handleGuardians)
	mux.HandleFunc("GET /api/admin/audit", s.handleAudit)
	mux.HandleFunc("GET /api/presets", s.handlePresets)
	mux.HandleFunc("GET /api/personas", s.handleListPersonas)
	mux.HandleFunc("POST /api/personas", s.handleCreatePersona)
	mux.HandleFunc("POST /api/personas/presets", s.handleRestorePresets)
	mux.HandleFunc("GET /api/personas/{id}", s.handleGetPersona)
	mux.HandleFunc("PUT /api/personas/{id}", s.handleUpdatePersona)
	mux.HandleFunc("DELETE /api/personas/{id}", s.handleDeletePersona)
	mux.HandleFunc("GET /api/personas/{id}/memory", s.handlePersonaMemory)
	mux.HandleFunc("DELETE /api/personas/{id}/memory", s.handleDeletePersonaMemory)
	mux.HandleFunc("DELETE /api/summaries/{id}", s.handleDeleteSummary)
	mux.HandleFunc("POST /api/conversations", s.handleOpenConversation)
	mux.HandleFunc("POST /api/conversations/{id}/end", s.handleEndConversation)

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := r.URL.Path
		if !strings.HasPrefix(p, "/api/") {
			next.ServeHTTP(w, r)
			return
		}
		if r.Method != http.MethodGet && r.Method != http.MethodHead && !sameOrigin(r) {
			writeError(w, http.StatusForbidden, "BAD_ORIGIN", msgBadOrigin) // F-026 AC9 (CSRF)
			return
		}
		ctx := r.Context()
		if c, err := r.Cookie(SessionCookie); err == nil {
			if pr, err := s.accounts.Authenticate(ctx, c.Value); err == nil {
				ctx = context.WithValue(ctx, principalKey{}, pr)
			} else if !errors.Is(err, account.ErrUnauthenticated) {
				s.log.Error("session lookup failed")
				writeError(w, http.StatusInternalServerError, "INTERNAL", "서버 오류가 발생했어요.")
				return
			}
		}
		r = r.WithContext(ctx)
		switch {
		case accountRoute(p):
			if r.Method == http.MethodPost || r.Method == http.MethodPatch || r.Method == http.MethodPut {
				if ct := r.Header.Get("Content-Type"); ct != "" && !strings.HasPrefix(ct, "application/json") {
					writeError(w, http.StatusUnsupportedMediaType, "INVALID_INPUT", msgNeedJSON)
					return
				}
			}
			mux.ServeHTTP(w, r)
		case aiPaths[p] && r.Method == http.MethodPost:
			if s.guardAI(w, r) {
				next.ServeHTTP(w, r)
			}
		default:
			next.ServeHTTP(w, r)
		}
	})
}

// accountRoute는 계정·개인 데이터 API 경로다 (이 미들웨어의 mux가 처리).
func accountRoute(p string) bool {
	if p == "/api/me" || p == "/api/presets" || p == "/api/personas" || p == "/api/conversations" {
		return true
	}
	for _, pre := range []string{"/api/auth/", "/api/me/", "/api/admin/", "/api/personas/", "/api/conversations/", "/api/summaries/"} {
		if strings.HasPrefix(p, pre) {
			return true
		}
	}
	return false
}

// sameOrigin은 Origin 헤더가 있으면 이 서버 주소와 같은지 본다 (없으면 같은 출처 요청으로 본다 — 브라우저는 교차 출처 POST에 Origin을 붙인다).
func sameOrigin(r *http.Request) bool {
	o := r.Header.Get("Origin")
	if o == "" {
		return true
	}
	u, err := url.Parse(o)
	return err == nil && u.Host == r.Host
}

// guardAI는 AI 경로의 세션·사용량을 확인한다. 막으면 응답을 쓰고 false (F-030 상세 동작 3·4).
func (s *server) guardAI(w http.ResponseWriter, r *http.Request) bool {
	pr, ok := PrincipalFrom(r.Context())
	if !ok {
		if s.authOpts.RequireSession {
			writeError(w, http.StatusUnauthorized, "UNAUTHENTICATED", msgLoginNeeded)
			return false
		}
		return true // 모의 모드: 세션 없이도 지금처럼 (테스트·시연)
	}
	ctx := r.Context()
	who := usage.Who{Subject: pr.Subject(), Guest: pr.Guest, Admin: pr.User.Role.Level() >= 2, Since: pr.Since}
	var err error
	switch {
	case pr.Guest && r.URL.Path != "/api/chat":
		writeError(w, http.StatusUnauthorized, "UNAUTHENTICATED", msgGuestQuota)
		return false
	case pr.Guest:
		if !s.limitGuestBody(w, r) {
			return false
		}
		err = s.limiter.ChatTurn(ctx, who)
	case r.URL.Path == "/api/chat":
		err = s.limiter.ChatTurn(ctx, who)
	case r.URL.Path == "/api/voice/session":
		err = s.limiter.VoiceSession(ctx, who)
	default: // 요약·장기 기억
		err = s.limiter.Background(ctx)
	}
	if errors.Is(err, usage.ErrQuota) {
		msg := msgQuota
		if pr.Guest {
			msg = msgGuestQuota
		}
		writeError(w, http.StatusTooManyRequests, "QUOTA_EXCEEDED", msg)
		return false
	} else if err != nil {
		s.log.Error("usage check failed")
		writeError(w, http.StatusInternalServerError, "INTERNAL", "서버 오류가 발생했어요.")
		return false
	}
	return true
}

// limitGuestBody는 게스트 요청을 줄인다: 마지막 질문 500자, 최근 6턴, 기억·내 정보·요구 사항은 뺀다.
func (s *server) limitGuestBody(w http.ResponseWriter, r *http.Request) bool {
	body, ok := readBody(w, r)
	if !ok {
		return false
	}
	var req map[string]json.RawMessage
	if json.Unmarshal(body, &req) != nil {
		writeError(w, http.StatusBadRequest, "INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
		return false
	}
	var msgs []struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	}
	if json.Unmarshal(req["messages"], &msgs) == nil && len(msgs) > 0 {
		if last := msgs[len(msgs)-1]; len([]rune(last.Content)) > GuestMaxMessage {
			writeError(w, http.StatusBadRequest, "INVALID_INPUT", msgGuestTooLong)
			return false
		}
		if max := 2*GuestMaxTurns - 1; len(msgs) > max {
			msgs = msgs[len(msgs)-max:]
		}
		req["messages"], _ = json.Marshal(msgs)
	}
	delete(req, "memory")
	delete(req, "longTerm")
	if raw, ok := req["persona"]; ok {
		var persona map[string]json.RawMessage
		if json.Unmarshal(raw, &persona) == nil {
			delete(persona, "instructions")
			delete(persona, "about")
			req["persona"], _ = json.Marshal(persona)
		}
	}
	nb, _ := json.Marshal(req)
	r.Body = ioNopCloser{bytes.NewReader(nb)}
	r.ContentLength = int64(len(nb))
	return true
}

type ioNopCloser struct{ *bytes.Reader }

func (ioNopCloser) Close() error { return nil }

// clientIP는 사용량 상한에 쓰는 IP다.
func (s *server) clientIP(r *http.Request) string {
	if h := s.authOpts.ClientIPHeader; h != "" {
		if v := strings.TrimSpace(strings.Split(r.Header.Get(h), ",")[0]); v != "" {
			return v
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func secureRequest(r *http.Request) bool {
	return r.TLS != nil || strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
}

func (s *server) setSession(w http.ResponseWriter, r *http.Request, token string, ttl time.Duration) {
	http.SetCookie(w, &http.Cookie{Name: SessionCookie, Value: token, Path: "/", MaxAge: int(ttl.Seconds()), HttpOnly: true, Secure: secureRequest(r), SameSite: http.SameSiteLaxMode})
}

func clearSession(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, &http.Cookie{Name: SessionCookie, Value: "", Path: "/", MaxAge: -1, HttpOnly: true, Secure: secureRequest(r), SameSite: http.SameSiteLaxMode})
}

func ttlFor(r store.Role) time.Duration {
	if r.Level() >= 2 {
		return account.AdminSession
	}
	return account.MemberSession
}

// accountError는 account 오류를 응답으로 바꾼다.
func (s *server) accountError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, account.ErrUnauthenticated):
		writeError(w, http.StatusUnauthorized, "UNAUTHENTICATED", msgLoginNeeded)
	case errors.Is(err, account.ErrBadCode):
		writeError(w, http.StatusUnauthorized, "BAD_CODE", msgBadCode)
	case errors.Is(err, account.ErrNotInvited):
		writeError(w, http.StatusForbidden, "NOT_INVITED", msgNotInvited)
	case errors.Is(err, account.ErrForbidden):
		writeError(w, http.StatusForbidden, "FORBIDDEN", msgForbidden)
	case errors.Is(err, account.ErrNotFound):
		writeError(w, http.StatusNotFound, "NOT_FOUND", "찾을 수 없어요.")
	case errors.Is(err, account.ErrInvalid):
		writeError(w, http.StatusBadRequest, "INVALID_INPUT", "입력 값을 확인해 주세요.")
	case errors.Is(err, account.ErrExists):
		writeError(w, http.StatusConflict, "CONFLICT", "이미 쓰이고 있어요.")
	default:
		s.log.Error("account error")
		writeError(w, http.StatusInternalServerError, "INTERNAL", "서버 오류가 발생했어요.")
	}
}

// decode는 본문 JSON을 읽는다. 실패하면 응답을 쓰고 false.
func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	body, ok := readBody(w, r)
	if !ok {
		return false
	}
	if len(bytes.TrimSpace(body)) == 0 {
		body = []byte("{}")
	}
	if json.Unmarshal(body, v) != nil {
		writeError(w, http.StatusBadRequest, "INVALID_JSON", "요청 본문이 올바른 JSON이 아니에요.")
		return false
	}
	return true
}

// userJSON은 화면에 주는 계정 모양이다 (이메일은 관리 화면에만).
func userJSON(u store.User, admin bool) map[string]any {
	m := map[string]any{"id": u.ID, "name": u.Name, "role": u.Role, "status": u.Status, "createdAt": u.CreatedAt.UTC().Format(time.RFC3339), "google": u.GoogleSub != ""}
	if admin && u.InviteEmail != "" {
		m["inviteEmail"] = u.InviteEmail
	}
	return m
}

// --- 로그인 ---

func (s *server) handleAuthOptions(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"code": true, "google": s.accounts.GoogleEnabled(), "guest": s.authOpts.GuestMode, "careSetting": s.authOpts.CareSetting})
}

func (s *server) handleLoginCode(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Code string `json:"code"`
	}
	if !decode(w, r, &req) {
		return
	}
	if err := s.limiter.CodeAttempt(r.Context(), s.clientIP(r)); errors.Is(err, usage.ErrRateLimited) {
		writeError(w, http.StatusTooManyRequests, "RATE_LIMITED", msgRateLimited)
		return
	} else if err != nil {
		s.accountError(w, err)
		return
	}
	token, u, err := s.accounts.LoginWithCode(r.Context(), req.Code)
	if err != nil {
		s.accountError(w, err)
		return
	}
	s.setSession(w, r, token, ttlFor(u.Role))
	writeJSON(w, http.StatusOK, map[string]any{"user": userJSON(u, false)})
}

func (s *server) handleLoginGoogle(w http.ResponseWriter, r *http.Request) {
	if !s.accounts.GoogleEnabled() {
		notFound(w, r)
		return
	}
	var req struct {
		IDToken string `json:"idToken"`
	}
	if !decode(w, r, &req) {
		return
	}
	if err := s.limiter.CodeAttempt(r.Context(), s.clientIP(r)); errors.Is(err, usage.ErrRateLimited) {
		writeError(w, http.StatusTooManyRequests, "RATE_LIMITED", msgRateLimited)
		return
	}
	token, u, err := s.accounts.LoginWithGoogle(r.Context(), req.IDToken)
	if err != nil {
		s.accountError(w, err)
		return
	}
	s.setSession(w, r, token, ttlFor(u.Role))
	writeJSON(w, http.StatusOK, map[string]any{"user": userJSON(u, false)})
}

func (s *server) handleGuest(w http.ResponseWriter, r *http.Request) {
	if !s.authOpts.GuestMode {
		notFound(w, r) // F-030 AC1
		return
	}
	if err := s.limiter.GuestStart(r.Context(), s.clientIP(r)); errors.Is(err, usage.ErrQuota) {
		writeError(w, http.StatusTooManyRequests, "QUOTA_EXCEEDED", msgGuestQuota)
		return
	} else if err != nil {
		s.accountError(w, err)
		return
	}
	token, _, err := s.accounts.StartGuest(r.Context())
	if err != nil {
		s.accountError(w, err)
		return
	}
	s.setSession(w, r, token, account.GuestSessionTTL)
	writeJSON(w, http.StatusOK, map[string]any{"guest": true, "turns": s.limiter.Limits().GuestTurns})
}

func (s *server) handleLogout(w http.ResponseWriter, r *http.Request) {
	if pr, ok := PrincipalFrom(r.Context()); ok {
		s.accounts.Logout(r.Context(), pr)
	}
	clearSession(w, r)
	w.WriteHeader(http.StatusNoContent)
}

// requireUser는 로그인한 계정(게스트 아님)을 돌려준다. 없으면 401을 쓰고 false.
func requireUser(w http.ResponseWriter, r *http.Request) (store.User, bool) {
	pr, ok := PrincipalFrom(r.Context())
	if !ok || pr.Guest {
		writeError(w, http.StatusUnauthorized, "UNAUTHENTICATED", msgLoginNeeded)
		return store.User{}, false
	}
	return pr.User, true
}

func (s *server) handleMe(w http.ResponseWriter, r *http.Request) {
	pr, ok := PrincipalFrom(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHENTICATED", msgLoginNeeded)
		return
	}
	if pr.Guest {
		writeJSON(w, http.StatusOK, map[string]any{"guest": true})
		return
	}
	m := userJSON(pr.User, false)
	m["grantableRoles"] = account.GrantableRoles(pr.User.Role)
	writeJSON(w, http.StatusOK, map[string]any{"user": m})
}

func (s *server) handleLinkGoogle(w http.ResponseWriter, r *http.Request) {
	pr, ok := PrincipalFrom(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, "UNAUTHENTICATED", msgLoginNeeded)
		return
	}
	var req struct {
		IDToken string `json:"idToken"`
	}
	if !decode(w, r, &req) {
		return
	}
	u, err := s.accounts.LinkGoogle(r.Context(), pr, req.IDToken)
	if err != nil {
		s.accountError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": userJSON(u, false)})
}

// --- 관리 (F-029, API-019~022) ---

func (s *server) handleListUsers(w http.ResponseWriter, r *http.Request) {
	actor, ok := requireUser(w, r)
	if !ok {
		return
	}
	users, err := s.accounts.Visible(r.Context(), actor)
	if err != nil {
		s.accountError(w, err)
		return
	}
	out := make([]map[string]any, 0, len(users))
	for _, u := range users {
		m := userJSON(u, true)
		if rel, err := s.accounts.RelationsOf(r.Context(), actor, u); err == nil {
			m["elders"], m["guardians"] = nonNil(rel.Elders), nonNil(rel.Guardians)
		}
		out = append(out, m)
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": out, "grantableRoles": account.GrantableRoles(actor.Role)})
}

func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

func (s *server) handleCreateUser(w http.ResponseWriter, r *http.Request) {
	actor, ok := requireUser(w, r)
	if !ok {
		return
	}
	var req struct {
		Name        string   `json:"name"`
		Role        string   `json:"role"`
		InviteEmail string   `json:"inviteEmail"`
		ElderIDs    []string `json:"elderIds"`
	}
	if !decode(w, r, &req) {
		return
	}
	u, code, exp, err := s.accounts.Create(r.Context(), actor, account.NewUser{Name: req.Name, Role: store.Role(req.Role), InviteEmail: req.InviteEmail, ElderIDs: req.ElderIDs})
	if err != nil {
		s.accountError(w, err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusCreated, map[string]any{"user": userJSON(u, true), "code": code, "codeExpiresAt": exp.UTC().Format(time.RFC3339)})
}

func (s *server) handleUpdateUser(w http.ResponseWriter, r *http.Request) {
	actor, ok := requireUser(w, r)
	if !ok {
		return
	}
	var req struct {
		Name   string `json:"name"`
		Role   string `json:"role"`
		Status string `json:"status"`
	}
	if !decode(w, r, &req) {
		return
	}
	u, err := s.accounts.Update(r.Context(), actor, r.PathValue("id"), account.Change{Name: req.Name, Role: store.Role(req.Role), Status: store.Status(req.Status)})
	if err != nil {
		s.accountError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": userJSON(u, true)})
}

func (s *server) handleDeleteUser(w http.ResponseWriter, r *http.Request) {
	actor, ok := requireUser(w, r)
	if !ok {
		return
	}
	if err := s.accounts.Delete(r.Context(), actor, r.PathValue("id")); err != nil {
		s.accountError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) handleReissue(w http.ResponseWriter, r *http.Request) {
	actor, ok := requireUser(w, r)
	if !ok {
		return
	}
	code, exp, err := s.accounts.ReissueCode(r.Context(), actor, r.PathValue("id"))
	if err != nil {
		s.accountError(w, err)
		return
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, map[string]any{"code": code, "expiresAt": exp.UTC().Format(time.RFC3339)})
}

func (s *server) handleCare(w http.ResponseWriter, r *http.Request) {
	actor, ok := requireUser(w, r)
	if !ok {
		return
	}
	var req struct {
		CaregiverID string `json:"caregiverId"`
		ElderID     string `json:"elderId"`
		Remove      bool   `json:"remove"`
	}
	if !decode(w, r, &req) {
		return
	}
	if err := s.accounts.AssignCare(r.Context(), actor, req.CaregiverID, req.ElderID, req.Remove); err != nil {
		s.accountError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) handleGuardians(w http.ResponseWriter, r *http.Request) {
	actor, ok := requireUser(w, r)
	if !ok {
		return
	}
	var req struct {
		GuardianID string `json:"guardianId"`
		ElderID    string `json:"elderId"`
		Remove     bool   `json:"remove"`
	}
	if !decode(w, r, &req) {
		return
	}
	if err := s.accounts.LinkGuardian(r.Context(), actor, req.GuardianID, req.ElderID, req.Remove); err != nil {
		s.accountError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) handleAudit(w http.ResponseWriter, r *http.Request) {
	actor, ok := requireUser(w, r)
	if !ok {
		return
	}
	entries, err := s.accounts.Audit(r.Context(), actor, 200)
	if err != nil {
		s.accountError(w, err)
		return
	}
	out := make([]map[string]any, 0, len(entries))
	for _, e := range entries {
		out = append(out, map[string]any{"actorId": e.ActorID, "action": e.Action, "targetId": e.TargetID, "at": e.At.UTC().Format(time.RFC3339)})
	}
	writeJSON(w, http.StatusOK, map[string]any{"entries": out})
}
