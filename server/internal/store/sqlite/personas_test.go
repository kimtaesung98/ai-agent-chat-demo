package sqlite

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
)

func TestF027PersonaStore(t *testing.T) {
	ctx := context.Background()
	d, err := Open("")
	if err != nil {
		t.Fatal(err)
	}
	defer d.Close()
	now := time.Now()
	for _, id := range []string{"usr_a", "usr_b"} {
		if err := d.CreateUser(ctx, store.User{ID: id, Name: id, Role: store.RoleElder, Status: store.StatusActive, CreatedAt: now}); err != nil {
			t.Fatal(err)
		}
	}
	mk := func(id, user string) store.Persona {
		return store.Persona{ID: id, UserID: user, Kind: "custom", Name: "바둑 친구", Tones: []string{"짧게"}, Revision: 1, CreatedAt: now, UpdatedAt: now}
	}

	t.Run("F-027 AC1 만들기·읽기·최대 개수", func(t *testing.T) {
		if err := d.CreatePersona(ctx, mk("per_1", "usr_a"), 2); err != nil {
			t.Fatal(err)
		}
		if err := d.CreatePersona(ctx, mk("per_2", "usr_a"), 2); err != nil {
			t.Fatal(err)
		}
		if err := d.CreatePersona(ctx, mk("per_3", "usr_a"), 2); !errors.Is(err, store.ErrQuota) {
			t.Fatalf("세 번째는 ErrQuota여야 해요: %v", err)
		}
		got, err := d.GetPersona(ctx, "usr_a", "per_1")
		if err != nil || got.Name != "바둑 친구" || len(got.Tones) != 1 || got.Revision != 1 {
			t.Fatalf("%+v %v", got, err)
		}
	})

	t.Run("F-026 AC5 남의 페르소나는 없는 것과 같다", func(t *testing.T) {
		if _, err := d.GetPersona(ctx, "usr_b", "per_1"); !errors.Is(err, store.ErrNotFound) {
			t.Fatal(err)
		}
		p := mk("per_1", "usr_b")
		p.Revision = 2
		if err := d.UpdatePersona(ctx, p); !errors.Is(err, store.ErrNotFound) {
			t.Fatal(err)
		}
		if err := d.DeletePersona(ctx, "usr_b", "per_1"); !errors.Is(err, store.ErrNotFound) {
			t.Fatal(err)
		}
	})

	t.Run("F-027 AC3 옛 revision은 ErrConflict이고 값은 그대로", func(t *testing.T) {
		p := mk("per_1", "usr_a")
		p.Name, p.Revision = "새 이름", 2
		if err := d.UpdatePersona(ctx, p); err != nil {
			t.Fatal(err)
		}
		p.Name = "늦은 기기"
		if err := d.UpdatePersona(ctx, p); !errors.Is(err, store.ErrConflict) {
			t.Fatalf("같은 revision을 두 번 쓰면 ErrConflict: %v", err)
		}
		got, _ := d.GetPersona(ctx, "usr_a", "per_1")
		if got.Name != "새 이름" || got.Revision != 2 {
			t.Fatalf("%+v", got)
		}
	})

	t.Run("F-027 AC1 탑재 페르소나는 한 번만 넣는다", func(t *testing.T) {
		var seed []store.Persona
		for i := range 4 {
			seed = append(seed, store.Persona{ID: fmt.Sprintf("per_s%d", i), UserID: "usr_b", Kind: "preset", PresetID: "coach", Name: "코치", Revision: 1, CreatedAt: now, UpdatedAt: now})
		}
		if ok, err := d.SeedPersonas(ctx, "usr_b", seed); !ok || err != nil {
			t.Fatal(ok, err)
		}
		if ok, err := d.SeedPersonas(ctx, "usr_b", seed); ok || err != nil {
			t.Fatal("두 번째는 넣지 않아야 해요", ok, err)
		}
		list, _ := d.ListPersonas(ctx, "usr_b")
		if len(list) != 4 {
			t.Fatalf("%d개", len(list))
		}
	})

	t.Run("같은 clientId는 ErrConflict, 계정을 지우면 같이 지워진다", func(t *testing.T) {
		p := mk("per_c1", "usr_b")
		p.ClientID = "dev-1"
		if err := d.CreatePersona(ctx, p, 20); err != nil {
			t.Fatal(err)
		}
		p.ID = "per_c2"
		if err := d.CreatePersona(ctx, p, 20); !errors.Is(err, store.ErrConflict) {
			t.Fatal(err)
		}
		if err := d.DeleteUser(ctx, "usr_b"); err != nil {
			t.Fatal(err)
		}
		if list, _ := d.ListPersonas(ctx, "usr_b"); len(list) != 0 {
			t.Fatalf("%d개 남음", len(list))
		}
	})
}
