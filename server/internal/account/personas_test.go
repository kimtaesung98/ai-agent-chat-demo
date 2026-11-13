package account

import (
	"errors"
	"testing"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
)

func TestF027PersonaOwner(t *testing.T) {
	s, _, _ := newService(t)
	admin, _, err := s.Bootstrap(ctx, "원장", "")
	if err != nil {
		t.Fatal(err)
	}
	cg, _ := mustCreate(t, s, admin, NewUser{Name: "요양사", Role: store.RoleCaregiver})
	elder, _ := mustCreate(t, s, cg, NewUser{Name: "어르신", Role: store.RoleElder})
	other, _ := mustCreate(t, s, admin, NewUser{Name: "다른 어르신", Role: store.RoleElder})
	guardian, _ := mustCreate(t, s, cg, NewUser{Name: "보호자", Role: store.RoleGuardian, ElderIDs: []string{elder.ID}})

	type c struct {
		name   string
		actor  User
		owner  string
		write  bool
		expect error
	}
	for _, tc := range []c{
		{"자기 것", elder, "", true, nil},
		{"원장은 아무 어르신", admin, other.ID, true, nil},
		{"요양사는 맡은 어르신을 고친다", cg, elder.ID, true, nil},
		{"요양사는 맡지 않은 어르신 404", cg, other.ID, false, ErrNotFound},
		{"보호자는 연결된 어르신을 본다", guardian, elder.ID, false, nil},
		{"보호자는 고치지 못한다", guardian, elder.ID, true, ErrForbidden},
		{"보호자는 다른 어르신 404", guardian, other.ID, false, ErrNotFound},
		{"어르신은 남의 것 404", other, elder.ID, false, ErrNotFound},
	} {
		t.Run("F-029 AC3 "+tc.name, func(t *testing.T) {
			u, err := s.PersonaOwner(ctx, tc.actor, tc.owner, tc.write)
			if !errors.Is(err, tc.expect) && !(err == nil && tc.expect == nil) {
				t.Fatalf("오류 %v, 기대 %v", err, tc.expect)
			}
			if err == nil && tc.owner != "" && u.ID != tc.owner {
				t.Fatalf("계정 %s", u.ID)
			}
		})
	}
}
