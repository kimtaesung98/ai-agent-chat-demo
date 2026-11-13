package account

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store/sqlite"
)

var ctx = context.Background()

type clock struct{ t time.Time }

func (c *clock) now() time.Time { return c.t }

func newService(t *testing.T, opts ...Option) (*Service, *clock, store.Store) {
	t.Helper()
	db, err := sqlite.Open("")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	c := &clock{t: time.Date(2026, 11, 13, 9, 0, 0, 0, time.UTC)}
	return New(db, append([]Option{WithClock(c.now)}, opts...)...), c, db
}

// login은 코드로 들어가 Principal을 돌려준다.
func login(t *testing.T, s *Service, code string) Principal {
	t.Helper()
	tok, _, err := s.LoginWithCode(ctx, code)
	if err != nil {
		t.Fatalf("로그인 실패: %v", err)
	}
	p, err := s.Authenticate(ctx, tok)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func mustCreate(t *testing.T, s *Service, actor User, n NewUser) (User, string) {
	t.Helper()
	u, code, _, err := s.Create(ctx, actor, n)
	if err != nil {
		t.Fatalf("%s가 %s 만들기 실패: %v", actor.Role, n.Role, err)
	}
	return u, code
}

func TestF029AC1GrantTable(t *testing.T) {
	// 역할 × 줄 역할 전부 (F-029 AC1)
	want := map[Role][]Role{
		store.RoleSuperAdmin: {store.RoleSuperAdmin, store.RoleCaregiver, store.RoleElder, store.RoleGuardian},
		store.RoleCaregiver:  {store.RoleElder, store.RoleGuardian},
		store.RoleElder:      nil,
		store.RoleGuardian:   nil,
	}
	for actor, roles := range want {
		for _, r := range store.Roles {
			exp := false
			for _, w := range roles {
				exp = exp || w == r
			}
			if got := CanGrant(actor, r); got != exp {
				t.Errorf("F-029 AC1 CanGrant(%s, %s) = %v, want %v", actor, r, got, exp)
			}
		}
	}
	if CanGrant(store.RoleSuperAdmin, "owner") {
		t.Error("모르는 역할을 줄 수 있음")
	}
	a := User{ID: "a", Role: store.RoleSuperAdmin}
	if CanManage(a, a) {
		t.Error("F-029 AC4 자기 자신을 관리할 수 있음")
	}
	if !CanManage(a, User{ID: "b", Role: store.RoleSuperAdmin}) {
		t.Error("최고 관리자가 다른 최고 관리자를 관리할 수 없음")
	}
	if CanManage(User{ID: "c", Role: store.RoleCaregiver}, User{ID: "d", Role: store.RoleCaregiver}) {
		t.Error("요양사가 같은 등급 요양사를 관리함")
	}
}

func TestF026Login(t *testing.T) {
	s, c, db := newService(t)
	admin, code, err := s.Bootstrap(ctx, "원장", "")
	if err != nil {
		t.Fatal(err)
	}
	t.Run("F-026 AC7 bootstrap은 최고 관리자가 없을 때만", func(t *testing.T) {
		if _, _, err := s.Bootstrap(ctx, "또", ""); !errors.Is(err, ErrExists) {
			t.Fatalf("두 번째 bootstrap: %v", err)
		}
	})
	t.Run("F-026 AC1 코드로 로그인하면 세션, 코드는 한 번만", func(t *testing.T) {
		p := login(t, s, strings.ToLower(code)) // 소문자·하이픈 섞여도 됨
		if p.User.ID != admin.ID || p.User.Role != store.RoleSuperAdmin {
			t.Fatalf("got %+v", p.User)
		}
		if _, _, err := s.LoginWithCode(ctx, code); !errors.Is(err, ErrBadCode) {
			t.Fatalf("두 번째 사용: %v", err)
		}
	})
	t.Run("F-026 AC1 DB에 코드·토큰 원문이 없다", func(t *testing.T) {
		_, c2, _, _ := s.Create(ctx, admin, NewUser{Name: "어르신", Role: store.RoleElder})
		tok, _, _ := s.LoginWithCode(ctx, c2)
		all, _ := db.ListUsers(ctx)
		_ = all
		if _, err := db.GetSession(ctx, tok); !errors.Is(err, store.ErrNotFound) {
			t.Fatal("세션 토큰 원문으로 찾아짐")
		}
		if _, err := db.UseLoginCode(ctx, NormalizeCode(c2), c.t); !errors.Is(err, store.ErrNotFound) {
			t.Fatal("코드 원문으로 찾아짐")
		}
	})
	t.Run("F-026 AC1 만료·재발급 전 코드는 거절", func(t *testing.T) {
		u, old := mustCreate(t, s, admin, NewUser{Name: "보호자", Role: store.RoleGuardian})
		if _, _, err := s.ReissueCode(ctx, admin, u.ID); err != nil {
			t.Fatal(err)
		}
		if _, _, err := s.LoginWithCode(ctx, old); !errors.Is(err, ErrBadCode) {
			t.Fatalf("재발급 전 코드: %v", err)
		}
		_, c3 := mustCreate(t, s, admin, NewUser{Name: "늦음", Role: store.RoleElder})
		c.t = c.t.Add(CodeTTL + time.Minute)
		if _, _, err := s.LoginWithCode(ctx, c3); !errors.Is(err, ErrBadCode) {
			t.Fatalf("만료 코드: %v", err)
		}
		c.t = c.t.Add(-CodeTTL - time.Minute)
	})
	t.Run("F-026 AC4 끝난 세션·로그아웃·정지는 401", func(t *testing.T) {
		u, c4 := mustCreate(t, s, admin, NewUser{Name: "철수", Role: store.RoleElder})
		tok, _, _ := s.LoginWithCode(ctx, c4)
		p, _ := s.Authenticate(ctx, tok)
		s.Logout(ctx, p)
		if _, err := s.Authenticate(ctx, tok); !errors.Is(err, ErrUnauthenticated) {
			t.Fatalf("로그아웃 뒤: %v", err)
		}
		c5, _, _ := s.ReissueCode(ctx, admin, u.ID)
		tok, _, _ = s.LoginWithCode(ctx, c5)
		if _, err := s.Update(ctx, admin, u.ID, Change{Status: store.StatusSuspended}); err != nil {
			t.Fatal(err)
		}
		if _, err := s.Authenticate(ctx, tok); !errors.Is(err, ErrUnauthenticated) {
			t.Fatalf("정지 뒤: %v", err)
		}
		s.Update(ctx, admin, u.ID, Change{Status: store.StatusActive})
		c6, _, _ := s.ReissueCode(ctx, admin, u.ID)
		tok, _, _ = s.LoginWithCode(ctx, c6)
		c.t = c.t.Add(MemberSession + time.Hour)
		if _, err := s.Authenticate(ctx, tok); !errors.Is(err, ErrUnauthenticated) {
			t.Fatalf("90일 뒤: %v", err)
		}
	})
}

func TestF029Hierarchy(t *testing.T) {
	s, _, _ := newService(t)
	_, code, _ := s.Bootstrap(ctx, "원장", "")
	admin := login(t, s, code).User
	cg1, c1 := mustCreate(t, s, admin, NewUser{Name: "요양사1", Role: store.RoleCaregiver})
	cg2, c2 := mustCreate(t, s, admin, NewUser{Name: "요양사2", Role: store.RoleCaregiver})
	care1, care2 := login(t, s, c1).User, login(t, s, c2).User
	_ = cg1
	_ = cg2
	elderA, ca := mustCreate(t, s, care1, NewUser{Name: "어르신A", Role: store.RoleElder})
	elderB, _ := mustCreate(t, s, care2, NewUser{Name: "어르신B", Role: store.RoleElder})
	guardA, cgA := mustCreate(t, s, care1, NewUser{Name: "보호자A", Role: store.RoleGuardian, ElderIDs: []string{elderA.ID}})

	t.Run("F-029 AC1 요양사는 요양사·최고 관리자를 만들 수 없다", func(t *testing.T) {
		for _, r := range []Role{store.RoleCaregiver, store.RoleSuperAdmin} {
			if _, _, _, err := s.Create(ctx, care1, NewUser{Name: "x", Role: r}); !errors.Is(err, ErrForbidden) {
				t.Errorf("%s 만들기: %v", r, err)
			}
		}
		if _, err := s.Update(ctx, care1, elderA.ID, Change{Role: store.RoleCaregiver}); !errors.Is(err, ErrForbidden) {
			t.Errorf("어르신을 요양사로 올리기: %v", err)
		}
	})
	t.Run("F-029 AC1 어르신·보호자는 관리 API를 쓸 수 없다", func(t *testing.T) {
		elder := login(t, s, ca).User
		if _, _, _, err := s.Create(ctx, elder, NewUser{Name: "x", Role: store.RoleElder}); !errors.Is(err, ErrForbidden) {
			t.Errorf("어르신이 만들기: %v", err)
		}
		g := login(t, s, cgA).User
		if _, err := s.Visible(ctx, g); !errors.Is(err, ErrForbidden) {
			t.Errorf("보호자 목록: %v", err)
		}
	})
	t.Run("F-029 AC2 요양사는 맡지 않은 어르신을 못 보고 id로 요청하면 404", func(t *testing.T) {
		list, _ := s.Visible(ctx, care1)
		for _, u := range list {
			if u.ID == elderB.ID || u.ID == care2.ID {
				t.Errorf("보이면 안 되는 계정: %s", u.Name)
			}
		}
		if len(list) != 3 { // 자기·어르신A·보호자A
			t.Errorf("보이는 계정 %d개", len(list))
		}
		if _, _, err := s.ReissueCode(ctx, care1, elderB.ID); !errors.Is(err, ErrNotFound) {
			t.Errorf("남의 어르신 코드: %v", err)
		}
		if err := s.Delete(ctx, care1, elderB.ID); !errors.Is(err, ErrNotFound) {
			t.Errorf("남의 어르신 지우기: %v", err)
		}
		if _, _, _, err := s.Create(ctx, care1, NewUser{Name: "보호자B", Role: store.RoleGuardian, ElderIDs: []string{elderB.ID}}); !errors.Is(err, ErrNotFound) {
			t.Errorf("남의 어르신에 보호자 연결: %v", err)
		}
	})
	t.Run("F-029 상세 동작 3 최고 관리자는 담당을 바꾼다", func(t *testing.T) {
		if err := s.AssignCare(ctx, care1, care1.ID, elderB.ID, false); !errors.Is(err, ErrForbidden) {
			t.Errorf("요양사가 담당 바꾸기: %v", err)
		}
		if err := s.AssignCare(ctx, admin, care1.ID, elderB.ID, false); err != nil {
			t.Fatal(err)
		}
		if _, err := s.visible(ctx, care1, elderB.ID); err != nil {
			t.Errorf("맡긴 뒤에도 안 보임: %v", err)
		}
		s.AssignCare(ctx, admin, care1.ID, elderB.ID, true)
		if _, err := s.visible(ctx, care1, elderB.ID); !errors.Is(err, ErrNotFound) {
			t.Errorf("뺀 뒤에도 보임: %v", err)
		}
	})
	t.Run("F-029 AC4 자기 자신·마지막 최고 관리자는 보호", func(t *testing.T) {
		if _, err := s.Update(ctx, admin, admin.ID, Change{Role: store.RoleCaregiver}); !errors.Is(err, ErrForbidden) {
			t.Errorf("자기 강등: %v", err)
		}
		if err := s.Delete(ctx, admin, admin.ID); !errors.Is(err, ErrForbidden) {
			t.Errorf("자기 삭제: %v", err)
		}
		dev, dc := mustCreate(t, s, admin, NewUser{Name: "개발자", Role: store.RoleSuperAdmin})
		devP := login(t, s, dc).User
		if _, err := s.Update(ctx, devP, admin.ID, Change{Status: store.StatusSuspended}); err != nil {
			t.Fatalf("다른 최고 관리자 정지: %v", err)
		}
		// 이제 활성 최고 관리자는 개발자 하나 — 원장이 정지돼 있으니 개발자 자신은 못 건드리고, 원장 복구는 가능
		if _, err := s.Update(ctx, devP, admin.ID, Change{Status: store.StatusActive}); err != nil {
			t.Fatal(err)
		}
		_ = dev
	})
	t.Run("F-029 AC5 역할을 바꾸면 그 계정 세션이 끝난다", func(t *testing.T) {
		code, _, _ := s.ReissueCode(ctx, care1, guardA.ID)
		tok, _, _ := s.LoginWithCode(ctx, code)
		if _, err := s.Update(ctx, care1, guardA.ID, Change{Role: store.RoleElder}); err != nil {
			t.Fatal(err)
		}
		if _, err := s.Authenticate(ctx, tok); !errors.Is(err, ErrUnauthenticated) {
			t.Fatalf("역할 바꾼 뒤 세션: %v", err)
		}
	})
	t.Run("F-029 AC6 권한 동작마다 감사 기록, 최고 관리자만 본다", func(t *testing.T) {
		if _, err := s.Audit(ctx, care1, 10); !errors.Is(err, ErrForbidden) {
			t.Errorf("요양사가 감사 기록: %v", err)
		}
		log, _ := s.Audit(ctx, admin, 100)
		if len(log) < 8 {
			t.Errorf("감사 기록 %d개", len(log))
		}
		for _, e := range log {
			if strings.Contains(e.Action, "-") && strings.Count(e.Action, "-") > 1 {
				t.Errorf("기록에 코드처럼 보이는 값: %q", e.Action)
			}
		}
	})
}

// --- Google (가짜 JWKS) ---

type fakeGoogle struct {
	key *rsa.PrivateKey
	srv *httptest.Server
}

func newFakeGoogle(t *testing.T) *fakeGoogle {
	k, _ := rsa.GenerateKey(rand.Reader, 2048)
	f := &fakeGoogle{key: k}
	f.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]string{{
			"kid": "k1", "kty": "RSA",
			"n": base64.RawURLEncoding.EncodeToString(k.N.Bytes()),
			"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(k.E)).Bytes()),
		}}})
	}))
	t.Cleanup(f.srv.Close)
	return f
}

func (f *fakeGoogle) token(claims map[string]any, key *rsa.PrivateKey) string {
	enc := func(v any) string { b, _ := json.Marshal(v); return base64.RawURLEncoding.EncodeToString(b) }
	head := enc(map[string]string{"alg": "RS256", "kid": "k1", "typ": "JWT"})
	body := enc(claims)
	d := sha256.Sum256([]byte(head + "." + body))
	sig, _ := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, d[:])
	return head + "." + body + "." + base64.RawURLEncoding.EncodeToString(sig)
}

func TestF026AC3Google(t *testing.T) {
	g := newFakeGoogle(t)
	now := time.Date(2026, 11, 13, 9, 0, 0, 0, time.UTC)
	v := &JWKSVerifier{ClientID: "client-1", CertsURL: g.srv.URL, Now: func() time.Time { return now }}
	s, _, _ := newService(t, WithGoogle(v))
	_, code, _ := s.Bootstrap(ctx, "원장", "")
	admin := login(t, s, code).User
	guard, _ := mustCreate(t, s, admin, NewUser{Name: "보호자", Role: store.RoleGuardian, InviteEmail: "Son@Example.com"})
	good := map[string]any{"iss": "https://accounts.google.com", "aud": "client-1", "sub": "g-1", "exp": now.Add(time.Hour).Unix(), "email": "son@example.com", "email_verified": true}

	t.Run("F-026 AC3 초대 이메일이 맞으면 처음 로그인 때 연결, 다음부터 sub로", func(t *testing.T) {
		_, u, err := s.LoginWithGoogle(ctx, g.token(good, g.key))
		if err != nil || u.ID != guard.ID {
			t.Fatalf("got %+v %v", u, err)
		}
		other := map[string]any{}
		for k, v := range good {
			other[k] = v
		}
		other["email"] = "changed@example.com"
		if _, u, err := s.LoginWithGoogle(ctx, g.token(other, g.key)); err != nil || u.ID != guard.ID {
			t.Fatalf("sub로 다시 로그인: %+v %v", u, err)
		}
	})
	t.Run("F-026 AC3 서명·발급자·대상·만료가 틀리면 401", func(t *testing.T) {
		bad := func(k string, v any) map[string]any {
			m := map[string]any{}
			for kk, vv := range good {
				m[kk] = vv
			}
			m[k] = v
			return m
		}
		other, _ := rsa.GenerateKey(rand.Reader, 2048)
		cases := map[string]string{
			"서명":  g.token(good, other),
			"발급자": g.token(bad("iss", "evil.com"), g.key),
			"대상":  g.token(bad("aud", "client-2"), g.key),
			"만료":  g.token(bad("exp", now.Add(-time.Second).Unix()), g.key),
			"모양":  "abc.def",
		}
		for name, tok := range cases {
			if _, _, err := s.LoginWithGoogle(ctx, tok); !errors.Is(err, ErrUnauthenticated) {
				t.Errorf("%s: %v", name, err)
			}
		}
	})
	t.Run("F-026 AC3 연결 안 된 Google 계정은 NOT_INVITED", func(t *testing.T) {
		m := map[string]any{}
		for k, v := range good {
			m[k] = v
		}
		m["sub"], m["email"] = "g-2", "stranger@example.com"
		if _, _, err := s.LoginWithGoogle(ctx, g.token(m, g.key)); !errors.Is(err, ErrNotInvited) {
			t.Fatalf("got %v", err)
		}
	})
}
