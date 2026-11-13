// Package store는 서버 DB의 도메인 행 타입과 저장소 인터페이스를 정의한다 (SPEC.md §7, ARCHITECTURE.md ADR-028).
// 구현은 store/sqlite에만 있고, 다른 모듈은 이 인터페이스만 안다.
package store

import (
	"context"
	"errors"
	"time"
)

// 오류. 구현은 이 값을 감싸지 않고 그대로 돌려준다.
var (
	ErrNotFound = errors.New("store: not found")
	ErrConflict = errors.New("store: conflict") // 유일 값이 겹침 (예: 같은 Google 계정)
	ErrQuota    = errors.New("store: quota exceeded")
)

// Role은 이용 개체의 역할이다 (F-029, ADR-032).
type Role string

const (
	RoleSuperAdmin Role = "super_admin" // 최고 관리자 — 개발자·원장 (등급 3)
	RoleCaregiver  Role = "caregiver"   // 인가된 관리자 — 요양사 (등급 2)
	RoleElder      Role = "elder"       // 사용자 — 어르신 (등급 1)
	RoleGuardian   Role = "guardian"    // 보호자 (등급 1)
)

// Roles는 알려진 역할 전부다.
var Roles = []Role{RoleSuperAdmin, RoleCaregiver, RoleElder, RoleGuardian}

// Level은 등급이다. 모르는 역할은 0.
func (r Role) Level() int {
	switch r {
	case RoleSuperAdmin:
		return 3
	case RoleCaregiver:
		return 2
	case RoleElder, RoleGuardian:
		return 1
	}
	return 0
}

// Valid는 알려진 역할인지 알려 준다.
func (r Role) Valid() bool { return r.Level() > 0 }

// Status는 계정 상태다.
type Status string

const (
	StatusActive    Status = "active"
	StatusSuspended Status = "suspended"
)

// User는 계정이다. 이름은 화면 표시용.
type User struct {
	ID          string
	Name        string
	Role        Role
	Status      Status
	CreatedBy   string // 만든 관리자 id (bootstrap이면 빈 값)
	CreatedAt   time.Time
	GoogleSub   string // 연결된 Google 계정 (`sub`), 없으면 빈 값
	InviteEmail string // 관리자가 적어 둔 초대 이메일 — 처음 Google 로그인 때 연결 (소문자)
}

// SessionKind는 세션 종류다.
type SessionKind string

const (
	SessionUser  SessionKind = "user"
	SessionGuest SessionKind = "guest" // DB 계정 없음 (F-030)
)

// Session은 로그인 세션이다. 토큰 원문은 저장하지 않는다.
type Session struct {
	TokenHash  string
	UserID     string // 게스트는 빈 값
	Kind       SessionKind
	CreatedAt  time.Time
	LastSeenAt time.Time
	ExpiresAt  time.Time
}

// LoginCode는 관리자가 발급한 로그인 코드다 (해시만).
type LoginCode struct {
	UserID    string
	CodeHash  string
	IssuedBy  string
	ExpiresAt time.Time
}

// AuditEntry는 권한 동작 기록이다 (F-029 상세 동작 7). 내용·코드는 담지 않는다.
type AuditEntry struct {
	ID       int64
	ActorID  string
	Action   string
	TargetID string
	At       time.Time
}

// UsageDelta는 사용량 버킷 하나에 더할 양과 상한이다 (F-030, ADR-033).
// Limit이 0 이하면 상한 없이 더하기만 한다.
type UsageDelta struct {
	Subject string // 사용자 id · "guest:<세션 해시>" · "ip:<해시>" · "global" …
	Bucket  string // 서울 날짜(2026-11-13) 또는 시간·10분 단위 버킷
	Amount  int
	Limit   int
}

// Store는 서버 DB다. 모든 메서드는 동시에 불러도 안전하다.
type Store interface {
	Close() error

	CreateUser(ctx context.Context, u User) error
	GetUser(ctx context.Context, id string) (User, error)
	UserByGoogleSub(ctx context.Context, sub string) (User, error)
	UserByInviteEmail(ctx context.Context, email string) (User, error)
	UpdateUser(ctx context.Context, u User) error // 이름·역할·상태·Google·초대 이메일
	DeleteUser(ctx context.Context, id string) error
	ListUsers(ctx context.Context) ([]User, error)
	CountActiveRole(ctx context.Context, r Role) (int, error)

	// SetLoginCode는 그 계정의 코드를 바꾼다 (이전 코드는 무효).
	SetLoginCode(ctx context.Context, c LoginCode) error
	// UseLoginCode는 만료 전·안 쓴 코드면 지우고 계정 id를 돌려준다. 아니면 ErrNotFound.
	UseLoginCode(ctx context.Context, codeHash string, now time.Time) (string, error)

	CreateSession(ctx context.Context, s Session) error
	GetSession(ctx context.Context, tokenHash string) (Session, error)
	TouchSession(ctx context.Context, tokenHash string, lastSeen, expires time.Time) error
	DeleteSession(ctx context.Context, tokenHash string) error
	DeleteUserSessions(ctx context.Context, userID string) error
	DeleteExpiredSessions(ctx context.Context, now time.Time) (int, error)

	AddCare(ctx context.Context, caregiverID, elderID string) error
	RemoveCare(ctx context.Context, caregiverID, elderID string) error
	EldersOfCaregiver(ctx context.Context, caregiverID string) ([]string, error)
	AddGuardianLink(ctx context.Context, guardianID, elderID string) error
	RemoveGuardianLink(ctx context.Context, guardianID, elderID string) error
	EldersOfGuardian(ctx context.Context, guardianID string) ([]string, error)
	GuardiansOfElder(ctx context.Context, elderID string) ([]string, error)

	AddAudit(ctx context.Context, e AuditEntry) error
	ListAudit(ctx context.Context, limit int) ([]AuditEntry, error)

	// AddUsage는 모든 버킷이 상한 안일 때만 한 트랜잭션으로 더한다. 하나라도 넘으면 아무것도 더하지 않고 ErrQuota.
	AddUsage(ctx context.Context, deltas []UsageDelta) error
	// DeleteUsageBefore는 bucket < before인 행을 지운다 (버킷 문자열은 사전 순 = 시간 순).
	DeleteUsageBefore(ctx context.Context, before string) (int, error)
}
