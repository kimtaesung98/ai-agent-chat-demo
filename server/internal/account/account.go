// Package account는 계정·로그인 코드·Google 로그인·세션과 역할 계층 권한 검사를 맡는다
// (SPEC.md F-026·F-029, ARCHITECTURE.md ADR-029·032). store 인터페이스만 안다.
package account

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/hex"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
)

// 바깥으로 쓰는 타입은 store 것을 그대로 쓴다.
type (
	User = store.User
	Role = store.Role
)

// 오류. httpapi가 상태 코드로 바꾼다.
var (
	ErrUnauthenticated = errors.New("account: unauthenticated") // 401
	ErrBadCode         = errors.New("account: bad code")        // 401 — 이유를 가리지 않는다
	ErrNotInvited      = errors.New("account: not invited")     // 403 — 연결 안 된 Google 계정
	ErrForbidden       = errors.New("account: forbidden")       // 403 — 볼 수는 있지만 등급이 모자람
	ErrNotFound        = errors.New("account: not found")       // 404 — 볼 수 없거나 없음
	ErrInvalid         = errors.New("account: invalid")         // 400
	ErrExists          = errors.New("account: exists")          // 409
)

// 기본값 (F-026 상세 동작 2·4).
const (
	CodeTTL         = 72 * time.Hour
	MemberSession   = 90 * 24 * time.Hour // 어르신·보호자
	AdminSession    = 14 * 24 * time.Hour // 요양사 이상
	GuestSessionTTL = 24 * time.Hour      // F-030
	touchEvery      = time.Hour           // 이보다 자주 쓰면 연장을 DB에 쓰지 않는다
	MaxName         = 20
)

// Service는 계정 기능이다.
type Service struct {
	store  store.Store
	now    func() time.Time
	google GoogleVerifier // nil이면 Google 로그인 꺼짐
}

// Option은 Service 선택 기능이다.
type Option func(*Service)

// WithClock은 시계를 바꾼다 (테스트).
func WithClock(now func() time.Time) Option { return func(s *Service) { s.now = now } }

// WithGoogle은 Google ID 토큰 로그인을 켠다.
func WithGoogle(v GoogleVerifier) Option { return func(s *Service) { s.google = v } }

// New는 Service를 만든다.
func New(st store.Store, opts ...Option) *Service {
	s := &Service{store: st, now: time.Now}
	for _, o := range opts {
		o(s)
	}
	return s
}

// GoogleEnabled는 Google 로그인을 쓸 수 있는지 알려 준다.
func (s *Service) GoogleEnabled() bool { return s.google != nil }

// Principal은 요청한 사람이다. Guest면 User는 비어 있다.
type Principal struct {
	User      User
	Guest     bool
	TokenHash string
}

// Subject는 사용량을 셀 때 쓰는 이름이다 (F-030).
func (p Principal) Subject() string {
	if p.Guest {
		return "guest:" + p.TokenHash[:16]
	}
	return p.User.ID
}

// --- 무작위 값·해시 ---

// codeAlphabet은 헷갈리는 0·O·1·I를 뺀 32글자다.
const codeAlphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

func randomBytes(n int) []byte {
	b := make([]byte, n)
	rand.Read(b) // 실패하면 Go 런타임이 멈춘다
	return b
}

func newID(prefix string) string {
	return prefix + strings.ToLower(base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(randomBytes(16)))
}

// NewCode는 10자리 로그인 코드를 만든다 (예 K7QM-4XPH-2R).
func NewCode() string {
	b := randomBytes(10)
	var sb strings.Builder
	for i, c := range b {
		if i == 4 || i == 8 {
			sb.WriteByte('-')
		}
		sb.WriteByte(codeAlphabet[int(c)%len(codeAlphabet)]) // 256은 32의 배수라 치우침 없음
	}
	return sb.String()
}

// NormalizeCode는 입력 코드에서 글자만 남기고 대문자로 바꾼다. 형식이 아니면 빈 값.
func NormalizeCode(code string) string {
	var sb strings.Builder
	for _, r := range strings.ToUpper(code) {
		switch {
		case r == '-' || r == ' ':
		case strings.ContainsRune(codeAlphabet, r):
			sb.WriteRune(r)
		default:
			return ""
		}
	}
	if sb.Len() != 10 {
		return ""
	}
	return sb.String()
}

func hash(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}

// --- 계정 만들기 ---

func cleanName(name string) (string, bool) {
	name = strings.TrimSpace(name)
	return name, name != "" && utf8.RuneCountInString(name) <= MaxName
}

func cleanEmail(email string) (string, bool) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" {
		return "", true
	}
	at := strings.IndexByte(email, '@')
	return email, at > 0 && at < len(email)-1 && len(email) <= 254 && !strings.ContainsAny(email, " \t")
}

// Bootstrap은 최고 관리자가 없을 때만 첫 최고 관리자를 만든다 (F-026 AC7).
// code가 비면 새로 만들고, 있으면 그 값(BOOTSTRAP_ADMIN_CODE)을 쓴다. 이미 있으면 ErrExists.
func (s *Service) Bootstrap(ctx context.Context, name, code string) (User, string, error) {
	n, ok := cleanName(name)
	if !ok {
		return User{}, "", ErrInvalid
	}
	if code == "" {
		code = NewCode()
	}
	norm := NormalizeCode(code)
	if norm == "" {
		return User{}, "", ErrInvalid
	}
	all, err := s.store.ListUsers(ctx)
	if err != nil {
		return User{}, "", err
	}
	for _, u := range all {
		if u.Role == store.RoleSuperAdmin {
			return User{}, "", ErrExists
		}
	}
	u := User{ID: newID("usr_"), Name: n, Role: store.RoleSuperAdmin, Status: store.StatusActive, CreatedAt: s.now()}
	if err := s.store.CreateUser(ctx, u); err != nil {
		return User{}, "", err
	}
	if err := s.store.SetLoginCode(ctx, store.LoginCode{UserID: u.ID, CodeHash: hash(norm), ExpiresAt: s.now().Add(CodeTTL)}); err != nil {
		return User{}, "", err
	}
	s.audit(ctx, "", "bootstrap", u.ID)
	return u, code, nil
}

func (s *Service) audit(ctx context.Context, actor, action, target string) {
	s.store.AddAudit(ctx, store.AuditEntry{ActorID: actor, Action: action, TargetID: target, At: s.now()})
}

// --- 로그인·세션 ---

func sessionTTL(r Role) time.Duration {
	if r.Level() >= 2 {
		return AdminSession
	}
	return MemberSession
}

func (s *Service) newSession(ctx context.Context, userID string, kind store.SessionKind, ttl time.Duration) (string, store.Session, error) {
	token := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(randomBytes(32))
	now := s.now()
	sess := store.Session{TokenHash: hash(token), UserID: userID, Kind: kind, CreatedAt: now, LastSeenAt: now, ExpiresAt: now.Add(ttl)}
	return token, sess, s.store.CreateSession(ctx, sess)
}

// LoginWithCode는 로그인 코드를 한 번 쓰고 세션 토큰을 돌려준다. 틀리거나 끝난 코드, 정지된 계정은 모두 ErrBadCode.
func (s *Service) LoginWithCode(ctx context.Context, code string) (string, User, error) {
	norm := NormalizeCode(code)
	if norm == "" {
		return "", User{}, ErrBadCode
	}
	id, err := s.store.UseLoginCode(ctx, hash(norm), s.now())
	if errors.Is(err, store.ErrNotFound) {
		return "", User{}, ErrBadCode
	} else if err != nil {
		return "", User{}, err
	}
	u, err := s.store.GetUser(ctx, id)
	if err != nil || u.Status != store.StatusActive {
		return "", User{}, ErrBadCode
	}
	token, _, err := s.newSession(ctx, u.ID, store.SessionUser, sessionTTL(u.Role))
	return token, u, err
}

// LoginWithGoogle은 연결된 Google 계정만 들인다 (F-026 상세 동작 3). 관리자가 적어 둔 초대 이메일과
// Google이 확인한 이메일이 같으면 처음 로그인 때 연결한다.
func (s *Service) LoginWithGoogle(ctx context.Context, idToken string) (string, User, error) {
	if s.google == nil {
		return "", User{}, ErrNotFound
	}
	id, err := s.google.Verify(ctx, idToken)
	if err != nil {
		return "", User{}, ErrUnauthenticated
	}
	u, err := s.store.UserByGoogleSub(ctx, id.Subject)
	if errors.Is(err, store.ErrNotFound) && id.EmailVerified && id.Email != "" {
		u, err = s.store.UserByInviteEmail(ctx, strings.ToLower(id.Email))
		if err == nil && u.GoogleSub == "" {
			u.GoogleSub, u.InviteEmail = id.Subject, ""
			if err = s.store.UpdateUser(ctx, u); err == nil {
				s.audit(ctx, u.ID, "google_link", u.ID)
			}
		} else if err == nil {
			err = store.ErrNotFound // 다른 Google 계정이 이미 연결됨
		}
	}
	if errors.Is(err, store.ErrNotFound) {
		return "", User{}, ErrNotInvited
	} else if err != nil {
		return "", User{}, err
	}
	if u.Status != store.StatusActive {
		return "", User{}, ErrNotInvited
	}
	token, _, err := s.newSession(ctx, u.ID, store.SessionUser, sessionTTL(u.Role))
	return token, u, err
}

// LinkGoogle은 로그인한 계정에 Google 계정을 붙인다. 다른 계정에 이미 붙어 있으면 ErrExists.
func (s *Service) LinkGoogle(ctx context.Context, p Principal, idToken string) (User, error) {
	if s.google == nil {
		return User{}, ErrNotFound
	}
	if p.Guest {
		return User{}, ErrForbidden
	}
	id, err := s.google.Verify(ctx, idToken)
	if err != nil {
		return User{}, ErrUnauthenticated
	}
	u := p.User
	u.GoogleSub, u.InviteEmail = id.Subject, ""
	if err := s.store.UpdateUser(ctx, u); errors.Is(err, store.ErrConflict) {
		return User{}, ErrExists
	} else if err != nil {
		return User{}, err
	}
	s.audit(ctx, u.ID, "google_link", u.ID)
	return u, nil
}

// StartGuest는 게스트 세션을 만든다 (F-030). 사용량 확인은 호출자(usage)가 먼저 한다.
func (s *Service) StartGuest(ctx context.Context) (string, Principal, error) {
	token, sess, err := s.newSession(ctx, "", store.SessionGuest, GuestSessionTTL)
	return token, Principal{Guest: true, TokenHash: sess.TokenHash}, err
}

// Authenticate는 세션 토큰을 확인한다. 끝난 세션·정지된 계정이면 ErrUnauthenticated.
// 역할은 세션에 담지 않고 매번 DB에서 읽는다 (ADR-032 — 강등·정지가 바로 반영).
func (s *Service) Authenticate(ctx context.Context, token string) (Principal, error) {
	if token == "" || len(token) > 128 {
		return Principal{}, ErrUnauthenticated
	}
	h := hash(token)
	sess, err := s.store.GetSession(ctx, h)
	if errors.Is(err, store.ErrNotFound) {
		return Principal{}, ErrUnauthenticated
	} else if err != nil {
		return Principal{}, err
	}
	now := s.now()
	if !now.Before(sess.ExpiresAt) {
		s.store.DeleteSession(ctx, h)
		return Principal{}, ErrUnauthenticated
	}
	if sess.Kind == store.SessionGuest {
		return Principal{Guest: true, TokenHash: h}, nil // 게스트는 연장하지 않는다
	}
	u, err := s.store.GetUser(ctx, sess.UserID)
	if errors.Is(err, store.ErrNotFound) || (err == nil && u.Status != store.StatusActive) {
		return Principal{}, ErrUnauthenticated
	} else if err != nil {
		return Principal{}, err
	}
	if now.Sub(sess.LastSeenAt) >= touchEvery {
		s.store.TouchSession(ctx, h, now, now.Add(sessionTTL(u.Role)))
	}
	return Principal{User: u, TokenHash: h}, nil
}

// Logout은 그 세션만 지운다.
func (s *Service) Logout(ctx context.Context, p Principal) error {
	return s.store.DeleteSession(ctx, p.TokenHash)
}

// Sweep은 끝난 세션을 지운다 (서버가 주기적으로 부름).
func (s *Service) Sweep(ctx context.Context) (int, error) {
	return s.store.DeleteExpiredSessions(ctx, s.now())
}
