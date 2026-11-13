package sqlite

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
)

func open(t *testing.T, dir string) *DB {
	t.Helper()
	d, err := Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { d.Close() })
	return d
}

var ctx = context.Background()

func TestF026AC6Persistence(t *testing.T) {
	t.Run("F-026 AC6 DATA_DIR가 있으면 다시 열어도 남고 마이그레이션은 한 번만 적용된다", func(t *testing.T) {
		dir := t.TempDir()
		d, err := Open(dir)
		if err != nil {
			t.Fatal(err)
		}
		u := store.User{ID: "usr_a", Name: "원장", Role: store.RoleSuperAdmin, Status: store.StatusActive, CreatedAt: time.Now()}
		if err := d.CreateUser(ctx, u); err != nil {
			t.Fatal(err)
		}
		d.Close()
		d2 := open(t, dir)
		got, err := d2.GetUser(ctx, "usr_a")
		if err != nil || got.Name != "원장" || got.Role != store.RoleSuperAdmin {
			t.Fatalf("다시 연 DB: %+v, %v", got, err)
		}
		var n int
		d2.db.QueryRow(`SELECT COUNT(*) FROM schema_migrations`).Scan(&n)
		if n != 1 {
			t.Fatalf("마이그레이션 행 %d개", n)
		}
	})
	t.Run("F-026 AC6 DATA_DIR가 없으면 메모리 DB", func(t *testing.T) {
		d := open(t, "")
		if _, err := d.GetUser(ctx, "x"); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("없는 계정: %v", err)
		}
	})
}

func TestStoreBasics(t *testing.T) {
	d := open(t, "")
	now := time.Now()
	for _, u := range []store.User{
		{ID: "a", Name: "원장", Role: store.RoleSuperAdmin, Status: store.StatusActive, CreatedAt: now},
		{ID: "e", Name: "어르신", Role: store.RoleElder, Status: store.StatusActive, CreatedAt: now, InviteEmail: "e@example.com"},
	} {
		if err := d.CreateUser(ctx, u); err != nil {
			t.Fatal(err)
		}
	}
	t.Run("초대 이메일은 유일하다", func(t *testing.T) {
		err := d.CreateUser(ctx, store.User{ID: "x", Name: "x", Role: store.RoleElder, Status: store.StatusActive, CreatedAt: now, InviteEmail: "e@example.com"})
		if !errors.Is(err, store.ErrConflict) {
			t.Fatalf("got %v", err)
		}
	})
	t.Run("F-026 AC1 로그인 코드는 한 번만, 만료 전만, 재발급하면 이전 것 무효", func(t *testing.T) {
		d.SetLoginCode(ctx, store.LoginCode{UserID: "e", CodeHash: "h1", ExpiresAt: now.Add(time.Hour)})
		d.SetLoginCode(ctx, store.LoginCode{UserID: "e", CodeHash: "h2", ExpiresAt: now.Add(time.Hour)})
		if _, err := d.UseLoginCode(ctx, "h1", now); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("이전 코드: %v", err)
		}
		if id, err := d.UseLoginCode(ctx, "h2", now); err != nil || id != "e" {
			t.Fatalf("새 코드: %q %v", id, err)
		}
		if _, err := d.UseLoginCode(ctx, "h2", now); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("두 번째 사용: %v", err)
		}
		d.SetLoginCode(ctx, store.LoginCode{UserID: "e", CodeHash: "h3", ExpiresAt: now.Add(time.Hour)})
		if _, err := d.UseLoginCode(ctx, "h3", now.Add(2*time.Hour)); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("만료 코드: %v", err)
		}
	})
	t.Run("F-026 AC6 계정을 지우면 세션·관계도 지워진다", func(t *testing.T) {
		d.CreateSession(ctx, store.Session{TokenHash: "t", UserID: "e", Kind: store.SessionUser, CreatedAt: now, LastSeenAt: now, ExpiresAt: now.Add(time.Hour)})
		d.AddCare(ctx, "a", "e")
		if err := d.DeleteUser(ctx, "e"); err != nil {
			t.Fatal(err)
		}
		if _, err := d.GetSession(ctx, "t"); !errors.Is(err, store.ErrNotFound) {
			t.Fatalf("세션이 남음: %v", err)
		}
		if ids, _ := d.EldersOfCaregiver(ctx, "a"); len(ids) != 0 {
			t.Fatalf("담당이 남음: %v", ids)
		}
	})
}

func TestF030AC3UsageIsAtomic(t *testing.T) {
	d := open(t, t.TempDir())
	var wg sync.WaitGroup
	var mu sync.Mutex
	ok := 0
	for range 20 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			err := d.AddUsage(ctx, []store.UsageDelta{{Subject: "u", Bucket: "2026-11-13", Amount: 1, Limit: 10}, {Subject: "global", Bucket: "2026-11-13", Amount: 1, Limit: 100}})
			if err == nil {
				mu.Lock()
				ok++
				mu.Unlock()
			} else if !errors.Is(err, store.ErrQuota) {
				t.Error(err)
			}
		}()
	}
	wg.Wait()
	if ok != 10 {
		t.Fatalf("F-030 AC3 동시 20개 중 %d개 통과 (10이어야 함)", ok)
	}
	var global int
	d.db.QueryRow(`SELECT amount FROM usage WHERE subject = 'global'`).Scan(&global)
	if global != 10 {
		t.Fatalf("막힌 요청이 전체 사용량을 늘림: %d", global)
	}
	if n, _ := d.DeleteUsageBefore(ctx, "2026-11-14"); n != 2 {
		t.Fatalf("지운 행 %d", n)
	}
}
