package account

import (
	"context"
	"errors"
	"slices"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
)

// 역할 계층 (F-029, ADR-032): super_admin(3) > caregiver(2) > elder·guardian(1).
// 보는 범위: super_admin은 모두, caregiver는 자기·맡은 어르신·그 보호자, 나머지는 자기만.
// 관리(만들기·역할·정지·삭제·코드)는 보이는 계정 중 낮은 등급에게만 — super_admin은 super_admin도.

// CanGrant는 actor가 role을 가진 계정을 만들거나 그 역할을 줄 수 있는지 알려 준다.
func CanGrant(actor, role Role) bool {
	if !role.Valid() {
		return false
	}
	if actor == store.RoleSuperAdmin {
		return true
	}
	return actor.Level() >= 2 && role.Level() < actor.Level()
}

// CanManage는 actor가 (보이는) target을 관리할 수 있는지 알려 준다. 자기 자신은 관리하지 않는다.
func CanManage(actor, target User) bool {
	if actor.ID == target.ID {
		return false
	}
	if actor.Role == store.RoleSuperAdmin {
		return true
	}
	return actor.Role.Level() >= 2 && target.Role.Level() < actor.Role.Level()
}

// GrantableRoles는 화면에 보여 줄, actor가 줄 수 있는 역할이다 (F-029 AC7).
func GrantableRoles(actor Role) []Role {
	var out []Role
	for _, r := range store.Roles {
		if CanGrant(actor, r) {
			out = append(out, r)
		}
	}
	return out
}

// scope는 actor가 볼 수 있는 계정 id 집합이다. nil이면 전부.
func (s *Service) scope(ctx context.Context, actor User) (map[string]bool, error) {
	if actor.Role == store.RoleSuperAdmin {
		return nil, nil
	}
	ids := map[string]bool{actor.ID: true}
	if actor.Role != store.RoleCaregiver {
		return ids, nil
	}
	elders, err := s.store.EldersOfCaregiver(ctx, actor.ID)
	if err != nil {
		return nil, err
	}
	for _, e := range elders {
		ids[e] = true
		gs, err := s.store.GuardiansOfElder(ctx, e)
		if err != nil {
			return nil, err
		}
		for _, g := range gs {
			ids[g] = true
		}
	}
	return ids, nil
}

// visible은 actor가 볼 수 있는 계정이면 돌려주고, 아니면 ErrNotFound (있는지도 알리지 않음).
func (s *Service) visible(ctx context.Context, actor User, id string) (User, error) {
	sc, err := s.scope(ctx, actor)
	if err != nil {
		return User{}, err
	}
	if sc != nil && !sc[id] {
		return User{}, ErrNotFound
	}
	u, err := s.store.GetUser(ctx, id)
	if errors.Is(err, store.ErrNotFound) {
		return User{}, ErrNotFound
	}
	return u, err
}

// manageable은 보이고 관리할 수 있는 계정을 돌려준다.
func (s *Service) manageable(ctx context.Context, actor User, id string) (User, error) {
	t, err := s.visible(ctx, actor, id)
	if err != nil {
		return User{}, err
	}
	if !CanManage(actor, t) {
		return User{}, ErrForbidden
	}
	return t, nil
}

// requireAdmin은 관리 API를 쓸 수 있는 등급(요양사 이상)인지 본다. 아니면 ErrForbidden.
func requireAdmin(actor User) error {
	if actor.Role.Level() < 2 {
		return ErrForbidden
	}
	return nil
}

// Visible은 actor가 볼 수 있는 계정 목록이다 (관리 화면).
func (s *Service) Visible(ctx context.Context, actor User) ([]User, error) {
	if err := requireAdmin(actor); err != nil {
		return nil, err
	}
	sc, err := s.scope(ctx, actor)
	if err != nil {
		return nil, err
	}
	all, err := s.store.ListUsers(ctx)
	if err != nil {
		return nil, err
	}
	var out []User
	for _, u := range all {
		if sc == nil || sc[u.ID] {
			out = append(out, u)
		}
	}
	return out, nil
}

// NewUser는 만들 계정이다.
type NewUser struct {
	Name        string
	Role        Role
	InviteEmail string   // 처음 Google 로그인 때 연결 (선택)
	ElderIDs    []string // 보호자: 연결할 어르신, 요양사가 만드는 어르신에는 쓰지 않음
}

// Create는 계정을 만들고 로그인 코드를 돌려준다 (F-026 상세 동작 1·2, F-029 상세 동작 2~4).
// 요양사가 만든 어르신은 그 요양사가 담당. 보호자는 보이는 어르신에만 연결한다.
func (s *Service) Create(ctx context.Context, actor User, n NewUser) (User, string, time.Time, error) {
	if err := requireAdmin(actor); err != nil {
		return User{}, "", time.Time{}, err
	}
	name, ok := cleanName(n.Name)
	email, ok2 := cleanEmail(n.InviteEmail)
	if !ok || !ok2 || !n.Role.Valid() || len(n.ElderIDs) > 10 || (n.Role != store.RoleGuardian && len(n.ElderIDs) > 0) {
		return User{}, "", time.Time{}, ErrInvalid
	}
	if !CanGrant(actor.Role, n.Role) {
		return User{}, "", time.Time{}, ErrForbidden
	}
	for _, id := range n.ElderIDs {
		e, err := s.visible(ctx, actor, id)
		if err != nil {
			return User{}, "", time.Time{}, err
		}
		if e.Role != store.RoleElder {
			return User{}, "", time.Time{}, ErrInvalid
		}
	}
	u := User{ID: newID("usr_"), Name: name, Role: n.Role, Status: store.StatusActive, CreatedBy: actor.ID, CreatedAt: s.now(), InviteEmail: email}
	if err := s.store.CreateUser(ctx, u); errors.Is(err, store.ErrConflict) {
		return User{}, "", time.Time{}, ErrExists
	} else if err != nil {
		return User{}, "", time.Time{}, err
	}
	if n.Role == store.RoleElder && actor.Role == store.RoleCaregiver {
		if err := s.store.AddCare(ctx, actor.ID, u.ID); err != nil {
			return User{}, "", time.Time{}, err
		}
	}
	for _, id := range n.ElderIDs {
		if err := s.store.AddGuardianLink(ctx, u.ID, id); err != nil {
			return User{}, "", time.Time{}, err
		}
	}
	s.audit(ctx, actor.ID, "user_create:"+string(n.Role), u.ID)
	code, exp, err := s.issue(ctx, actor, u)
	return u, code, exp, err
}

func (s *Service) issue(ctx context.Context, actor, u User) (string, time.Time, error) {
	code := NewCode()
	exp := s.now().Add(CodeTTL)
	err := s.store.SetLoginCode(ctx, store.LoginCode{UserID: u.ID, CodeHash: hash(NormalizeCode(code)), IssuedBy: actor.ID, ExpiresAt: exp})
	if errors.Is(err, store.ErrConflict) { // 같은 코드가 이미 있음 (거의 없음) — 한 번 더
		code = NewCode()
		err = s.store.SetLoginCode(ctx, store.LoginCode{UserID: u.ID, CodeHash: hash(NormalizeCode(code)), IssuedBy: actor.ID, ExpiresAt: exp})
	}
	return code, exp, err
}

// ReissueCode는 로그인 코드를 다시 만든다 (이전 코드 무효).
func (s *Service) ReissueCode(ctx context.Context, actor User, id string) (string, time.Time, error) {
	if err := requireAdmin(actor); err != nil {
		return "", time.Time{}, err
	}
	t, err := s.manageable(ctx, actor, id)
	if err != nil {
		return "", time.Time{}, err
	}
	code, exp, err := s.issue(ctx, actor, t)
	if err == nil {
		s.audit(ctx, actor.ID, "code_reissue", t.ID)
	}
	return code, exp, err
}

// lastSuperAdmin은 t가 마지막 남은 활성 최고 관리자인지 알려 준다.
func (s *Service) lastSuperAdmin(ctx context.Context, t User) (bool, error) {
	if t.Role != store.RoleSuperAdmin || t.Status != store.StatusActive {
		return false, nil
	}
	n, err := s.store.CountActiveRole(ctx, store.RoleSuperAdmin)
	return n <= 1, err
}

// Change는 역할·상태 바꾸기다. 빈 값은 그대로.
type Change struct {
	Role   Role
	Status store.Status
	Name   string
}

// Update는 역할·상태·이름을 바꾼다. 정지하면 그 계정 세션을 모두 지운다 (F-026 상세 동작 4, F-029 AC4·5).
func (s *Service) Update(ctx context.Context, actor User, id string, c Change) (User, error) {
	if err := requireAdmin(actor); err != nil {
		return User{}, err
	}
	t, err := s.manageable(ctx, actor, id)
	if err != nil {
		return User{}, err
	}
	next := t
	if c.Name != "" {
		n, ok := cleanName(c.Name)
		if !ok {
			return User{}, ErrInvalid
		}
		next.Name = n
	}
	if c.Role != "" {
		if !c.Role.Valid() {
			return User{}, ErrInvalid
		}
		if !CanGrant(actor.Role, c.Role) {
			return User{}, ErrForbidden
		}
		next.Role = c.Role
	}
	if c.Status != "" {
		if c.Status != store.StatusActive && c.Status != store.StatusSuspended {
			return User{}, ErrInvalid
		}
		next.Status = c.Status
	}
	if (next.Role != store.RoleSuperAdmin || next.Status != store.StatusActive) && t.Role == store.RoleSuperAdmin {
		if last, err := s.lastSuperAdmin(ctx, t); err != nil {
			return User{}, err
		} else if last {
			return User{}, ErrForbidden
		}
	}
	if err := s.store.UpdateUser(ctx, next); err != nil {
		return User{}, err
	}
	if next.Status == store.StatusSuspended || next.Role != t.Role {
		if err := s.store.DeleteUserSessions(ctx, t.ID); err != nil {
			return User{}, err
		}
	}
	if next.Role != t.Role {
		s.audit(ctx, actor.ID, "role:"+string(t.Role)+"->"+string(next.Role), t.ID)
	}
	if next.Status != t.Status {
		s.audit(ctx, actor.ID, "status:"+string(next.Status), t.ID)
	}
	return next, nil
}

// Delete는 계정과 그 데이터를 지운다 (F-026 상세 동작 10).
func (s *Service) Delete(ctx context.Context, actor User, id string) error {
	if err := requireAdmin(actor); err != nil {
		return err
	}
	t, err := s.manageable(ctx, actor, id)
	if err != nil {
		return err
	}
	if last, err := s.lastSuperAdmin(ctx, t); err != nil {
		return err
	} else if last {
		return ErrForbidden
	}
	if err := s.store.DeleteUser(ctx, t.ID); err != nil {
		return err
	}
	s.audit(ctx, actor.ID, "user_delete:"+string(t.Role), t.ID)
	return nil
}

// AssignCare는 요양사에게 어르신을 맡긴다 (최고 관리자만, F-029 상세 동작 3). remove면 뺀다.
func (s *Service) AssignCare(ctx context.Context, actor User, caregiverID, elderID string, remove bool) error {
	if actor.Role != store.RoleSuperAdmin {
		return ErrForbidden
	}
	c, err := s.visible(ctx, actor, caregiverID)
	if err != nil {
		return err
	}
	e, err := s.visible(ctx, actor, elderID)
	if err != nil {
		return err
	}
	if c.Role != store.RoleCaregiver || e.Role != store.RoleElder {
		return ErrInvalid
	}
	if remove {
		err = s.store.RemoveCare(ctx, c.ID, e.ID)
		if errors.Is(err, store.ErrNotFound) {
			return ErrNotFound
		}
	} else {
		err = s.store.AddCare(ctx, c.ID, e.ID)
	}
	if err == nil {
		s.audit(ctx, actor.ID, map[bool]string{false: "care_add", true: "care_remove"}[remove]+":"+c.ID, e.ID)
	}
	return err
}

// LinkGuardian은 보호자를 어르신에 연결한다 (요양사 이상, 둘 다 보이고 관리할 수 있어야 함). remove면 끊는다.
func (s *Service) LinkGuardian(ctx context.Context, actor User, guardianID, elderID string, remove bool) error {
	if err := requireAdmin(actor); err != nil {
		return err
	}
	e, err := s.manageable(ctx, actor, elderID)
	if err != nil {
		return err
	}
	g, err := s.store.GetUser(ctx, guardianID)
	if errors.Is(err, store.ErrNotFound) {
		return ErrNotFound
	} else if err != nil {
		return err
	}
	if actor.Role != store.RoleSuperAdmin && g.CreatedBy != actor.ID {
		// 요양사는 자기가 만들었거나 이미 보이는 보호자만 연결한다
		if _, err := s.visible(ctx, actor, guardianID); err != nil {
			return err
		}
	}
	if g.Role != store.RoleGuardian || e.Role != store.RoleElder {
		return ErrInvalid
	}
	if remove {
		err = s.store.RemoveGuardianLink(ctx, g.ID, e.ID)
		if errors.Is(err, store.ErrNotFound) {
			return ErrNotFound
		}
	} else {
		err = s.store.AddGuardianLink(ctx, g.ID, e.ID)
	}
	if err == nil {
		s.audit(ctx, actor.ID, map[bool]string{false: "guardian_link:", true: "guardian_unlink:"}[remove]+g.ID, e.ID)
	}
	return err
}

// Relations는 관리 화면에 보여 줄 관계다.
type Relations struct {
	Caregivers []string // 어르신: 담당 요양사 — 최고 관리자에게만
	Elders     []string // 요양사: 맡은 어르신, 보호자: 연결된 어르신
	Guardians  []string // 어르신: 연결된 보호자
}

// RelationsOf는 actor가 볼 수 있는 범위에서 target의 관계를 돌려준다.
func (s *Service) RelationsOf(ctx context.Context, actor User, t User) (Relations, error) {
	var r Relations
	var err error
	switch t.Role {
	case store.RoleCaregiver:
		r.Elders, err = s.store.EldersOfCaregiver(ctx, t.ID)
	case store.RoleGuardian:
		r.Elders, err = s.store.EldersOfGuardian(ctx, t.ID)
	case store.RoleElder:
		r.Guardians, err = s.store.GuardiansOfElder(ctx, t.ID)
	}
	if err != nil || actor.Role == store.RoleSuperAdmin {
		return r, err
	}
	sc, err := s.scope(ctx, actor)
	if err != nil {
		return r, err
	}
	keep := func(ids []string) []string {
		return slices.DeleteFunc(ids, func(id string) bool { return !sc[id] })
	}
	r.Elders, r.Guardians = keep(r.Elders), keep(r.Guardians)
	return r, nil
}

// Audit은 감사 기록이다 (최고 관리자만).
func (s *Service) Audit(ctx context.Context, actor User, limit int) ([]store.AuditEntry, error) {
	if actor.Role != store.RoleSuperAdmin {
		return nil, ErrForbidden
	}
	return s.store.ListAudit(ctx, limit)
}
