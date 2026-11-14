package account

import (
	"context"
	"errors"
	"slices"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
)

// NewID는 밖으로 내는 무작위 id다 (접두어 + 16바이트 base32, SPEC.md §7.1).
func NewID(prefix string) string { return newID(prefix) }

// PersonaOwner는 actor가 ownerID의 페르소나를 읽거나(write=false) 고칠 수 있는지 보고 그 계정을 돌려준다
// (SPEC.md F-027 상세 동작 5, F-029 보는 범위 표).
//   - 자기 것: 읽기·고치기 (ownerID가 비어도 자기 것)
//   - super_admin: 모든 계정
//   - caregiver: 맡은 어르신
//   - guardian: 연결된 어르신 — 보기만 (고치려 하면 ErrForbidden)
//
// 그 밖에는 ErrNotFound (있는지도 알리지 않음).
func (s *Service) PersonaOwner(ctx context.Context, actor User, ownerID string, write bool) (User, error) {
	if ownerID == "" || ownerID == actor.ID {
		return actor, nil
	}
	var allowed bool
	switch actor.Role {
	case store.RoleSuperAdmin:
		allowed = true
	case store.RoleCaregiver:
		elders, err := s.store.EldersOfCaregiver(ctx, actor.ID)
		if err != nil {
			return User{}, err
		}
		allowed = slices.Contains(elders, ownerID)
	case store.RoleGuardian:
		elders, err := s.store.EldersOfGuardian(ctx, actor.ID)
		if err != nil {
			return User{}, err
		}
		if slices.Contains(elders, ownerID) {
			if write {
				return User{}, ErrForbidden
			}
			allowed = true
		}
	}
	if !allowed {
		return User{}, ErrNotFound
	}
	u, err := s.store.GetUser(ctx, ownerID)
	if errors.Is(err, store.ErrNotFound) {
		return User{}, ErrNotFound
	}
	return u, err
}

// Store는 계정과 같은 저장소다 — 페르소나·대화 같은 개인 데이터 API가 쓴다 (권한 확인은 이 Service로).
func (s *Service) Store() store.Store { return s.store }

// Rename은 자기 이름을 바꾼다 (프로필 displayName, API-013). 1~20자.
func (s *Service) Rename(ctx context.Context, actor User, name string) (User, error) {
	n, ok := cleanName(name)
	if !ok {
		return User{}, ErrInvalid
	}
	u, err := s.store.GetUser(ctx, actor.ID)
	if err != nil {
		return User{}, err
	}
	if u.Name == n {
		return u, nil
	}
	u.Name = n
	return u, s.store.UpdateUser(ctx, u)
}
