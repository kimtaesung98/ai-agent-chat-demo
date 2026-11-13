package contract

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

// F-026·F-029·F-030 계약 테스트. chatd를 직접 띄울 때 아래 환경으로 첫 최고 관리자와 게스트 체험을 켠다.
// -base-url로 띄운 서버는 CONTRACT_ADMIN_CODE(그 서버의 BOOTSTRAP_ADMIN_CODE)가 있어야 돌고, 없으면 건너뛴다.
const contractAdminCode = "CTRT-7ADM-N2"

var accountEnv = []string{
	"BOOTSTRAP_ADMIN_CODE=" + contractAdminCode, "BOOTSTRAP_ADMIN_NAME=원장",
	"GUEST_MODE=on", "CLIENT_IP_HEADER=X-Test-IP",
}

// localChatd는 테스트가 chatd를 직접 띄웠는지다 (그때만 contractAdminCode를 안다).
var localChatd bool

// ipSeq는 테스트마다 다른 IP를 써서 IP별 상한이 서로 겹치지 않게 한다.
var ipSeq atomic.Int32

type sess struct {
	c  *http.Client
	ip string
}

func newSess() *sess {
	jar, _ := cookiejar.New(nil)
	return &sess{c: &http.Client{Jar: jar, Timeout: client.Timeout}, ip: fmt.Sprintf("10.0.%d.%d", ipSeq.Add(1)/250, ipSeq.Load()%250)}
}

func (s *sess) do(t *testing.T, method, path string, body any, hdr ...string) (int, map[string]any) {
	t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, *baseURL+path, rd)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	req.Header.Set("X-Test-IP", s.ip)
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	res, err := s.c.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	var m map[string]any
	json.Unmarshal(raw, &m)
	return res.StatusCode, m
}

func errCode(m map[string]any) string {
	e, _ := m["error"].(map[string]any)
	c, _ := e["code"].(string)
	return c
}

var (
	adminOnce sync.Once
	adminSess *sess
	adminErr  string
)

// admin은 첫 최고 관리자로 로그인한 세션이다 (코드는 한 번만 쓰이므로 한 번만 로그인).
func admin(t *testing.T) *sess {
	t.Helper()
	code := os.Getenv("CONTRACT_ADMIN_CODE")
	if code == "" && localChatd {
		code = contractAdminCode
	}
	if code == "" {
		t.Skip("CONTRACT_ADMIN_CODE가 없어 계정 계약 테스트를 건너뛰어요")
	}
	adminOnce.Do(func() {
		s := newSess()
		if st, m := s.do(t, "POST", "/api/auth/code", map[string]string{"code": code}); st != 200 {
			adminErr = fmt.Sprintf("최고 관리자 로그인 %d %v", st, m)
			return
		}
		adminSess = s
	})
	if adminSess == nil {
		t.Fatal(adminErr)
	}
	return adminSess
}

// create는 actor가 계정을 만들고, 그 코드로 로그인한 세션과 id를 돌려준다.
func create(t *testing.T, actor *sess, name, role string, extra map[string]any) (*sess, string) {
	t.Helper()
	body := map[string]any{"name": name, "role": role}
	for k, v := range extra {
		body[k] = v
	}
	st, m := actor.do(t, "POST", "/api/admin/users", body)
	if st != 201 {
		t.Fatalf("%s(%s) 만들기: %d %v", name, role, st, m)
	}
	code, _ := m["code"].(string)
	id, _ := m["user"].(map[string]any)["id"].(string)
	s := newSess()
	if st, m := s.do(t, "POST", "/api/auth/code", map[string]string{"code": code}); st != 200 {
		t.Fatalf("%s 로그인: %d %v", name, st, m)
	}
	return s, id
}

func TestF026Accounts(t *testing.T) {
	a := admin(t)

	t.Run("F-026 AC1 코드로 로그인하면 쿠키(HttpOnly)를 받고 /api/me가 이름·역할을 준다", func(t *testing.T) {
		st, m := a.do(t, "GET", "/api/me", nil)
		u, _ := m["user"].(map[string]any)
		if st != 200 || u["role"] != "super_admin" || u["name"] != "원장" {
			t.Fatalf("got %d %v", st, m)
		}
		st, m = a.do(t, "POST", "/api/admin/users", map[string]any{"name": "어르신", "role": "elder"})
		code, _ := m["code"].(string)
		if st != 201 || len(code) != 12 {
			t.Fatalf("계정 만들기 %d %v", st, m)
		}
		b, _ := json.Marshal(map[string]string{"code": code})
		req, _ := http.NewRequest("POST", *baseURL+"/api/auth/code", bytes.NewReader(b))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("X-Test-IP", newSess().ip)
		res, err := client.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		res.Body.Close()
		ck := res.Header.Get("Set-Cookie")
		if res.StatusCode != 200 || !strings.Contains(ck, "sid=") || !strings.Contains(ck, "HttpOnly") || !strings.Contains(ck, "SameSite=Lax") {
			t.Fatalf("쿠키: %d %q", res.StatusCode, ck)
		}
		if st, m := newSess().do(t, "POST", "/api/auth/code", map[string]string{"code": code}); st != 401 || errCode(m) != "BAD_CODE" {
			t.Fatalf("같은 코드 두 번째: %d %v", st, m)
		}
	})
	t.Run("F-026 AC2 같은 IP 틀린 코드 10번 뒤에는 429", func(t *testing.T) {
		s := newSess()
		for i := range 10 {
			if st, _ := s.do(t, "POST", "/api/auth/code", map[string]string{"code": "AAAA-AAAA-AA"}); st != 401 {
				t.Fatalf("%d번째: %d", i+1, st)
			}
		}
		if st, m := s.do(t, "POST", "/api/auth/code", map[string]string{"code": "AAAA-AAAA-AA"}); st != 429 || errCode(m) != "RATE_LIMITED" {
			t.Fatalf("11번째: %d %v", st, m)
		}
	})
	t.Run("F-026 AC4 쿠키 없음·로그아웃 뒤는 401", func(t *testing.T) {
		if st, m := newSess().do(t, "GET", "/api/me", nil); st != 401 || errCode(m) != "UNAUTHENTICATED" {
			t.Fatalf("쿠키 없음: %d %v", st, m)
		}
		s, _ := create(t, a, "로그아웃", "guardian", nil)
		if st, _ := s.do(t, "POST", "/api/auth/logout", nil); st != 204 {
			t.Fatalf("로그아웃: %d", st)
		}
		if st, _ := s.do(t, "GET", "/api/me", nil); st != 401 {
			t.Fatalf("로그아웃 뒤: %d", st)
		}
	})
	t.Run("F-026 AC9 다른 Origin의 상태 변경은 403", func(t *testing.T) {
		if st, m := a.do(t, "POST", "/api/admin/users", map[string]any{"name": "x", "role": "elder"}, "Origin", "https://evil.example"); st != 403 || errCode(m) != "BAD_ORIGIN" {
			t.Fatalf("got %d %v", st, m)
		}
	})
}

func TestF029Roles(t *testing.T) {
	a := admin(t)
	c1, _ := create(t, a, "요양사1", "caregiver", nil)
	c2, _ := create(t, a, "요양사2", "caregiver", nil)
	_, elderA := create(t, c1, "어르신A", "elder", nil)
	g, _ := create(t, c1, "보호자A", "guardian", map[string]any{"elderIds": []string{elderA}})

	t.Run("F-029 AC1 요양사는 요양사·최고 관리자를 만들 수 없다", func(t *testing.T) {
		for _, r := range []string{"caregiver", "super_admin"} {
			if st, m := c1.do(t, "POST", "/api/admin/users", map[string]any{"name": "x", "role": r}); st != 403 || errCode(m) != "FORBIDDEN" {
				t.Errorf("%s: %d %v", r, st, m)
			}
		}
		if st, _ := g.do(t, "GET", "/api/admin/users", nil); st != 403 {
			t.Errorf("보호자 목록: %d", st)
		}
	})
	t.Run("F-029 AC2 F-026 AC5 다른 요양사의 어르신은 목록에 없고 id로 요청하면 404", func(t *testing.T) {
		st, m := c2.do(t, "GET", "/api/admin/users", nil)
		if st != 200 || strings.Contains(fmt.Sprint(m["users"]), elderA) {
			t.Fatalf("목록: %d %v", st, m)
		}
		for _, call := range [][2]string{{"PATCH", "/api/admin/users/" + elderA}, {"DELETE", "/api/admin/users/" + elderA}, {"POST", "/api/admin/users/" + elderA + "/code"}} {
			if st, m := c2.do(t, call[0], call[1], map[string]any{"status": "suspended"}); st != 404 {
				t.Errorf("%s %s: %d %v", call[0], call[1], st, m)
			}
		}
		st, m = c1.do(t, "GET", "/api/admin/users", nil)
		if st != 200 || !strings.Contains(fmt.Sprint(m["users"]), elderA) {
			t.Fatalf("맡은 요양사 목록: %d %v", st, m)
		}
	})
	t.Run("F-029 AC5 정지하면 그 계정의 다음 요청부터 401", func(t *testing.T) {
		e, id := create(t, c1, "정지", "elder", nil)
		if st, _ := c1.do(t, "PATCH", "/api/admin/users/"+id, map[string]any{"status": "suspended"}); st != 200 {
			t.Fatalf("정지: %d", st)
		}
		if st, _ := e.do(t, "GET", "/api/me", nil); st != 401 {
			t.Fatalf("정지 뒤: %d", st)
		}
	})
}

func TestF030Guest(t *testing.T) {
	admin(t) // 계정 계약 테스트를 돌릴 수 있는 서버인지 확인
	chat := map[string]any{"messages": []map[string]string{{"role": "user", "content": "안녕하세요"}}}

	t.Run("F-030 AC1 게스트는 글 채팅만, 요약·음성은 401", func(t *testing.T) {
		g := newSess()
		if st, m := g.do(t, "POST", "/api/auth/guest", nil); st != 200 || m["guest"] != true {
			t.Fatalf("게스트 시작: %d %v", st, m)
		}
		if st, _ := g.do(t, "POST", "/api/chat", chat); st != 200 {
			t.Fatalf("게스트 채팅: %d", st)
		}
		for _, p := range []string{"/api/summary", "/api/voice/session", "/api/consolidate"} {
			if st, _ := g.do(t, "POST", p, chat); st != 401 {
				t.Errorf("%s: %d", p, st)
			}
		}
	})
	t.Run("F-030 AC2 게스트 11번째 질문·같은 IP 4번째 게스트 세션은 429", func(t *testing.T) {
		g := newSess()
		g.do(t, "POST", "/api/auth/guest", nil)
		for i := range 10 {
			if st, _ := g.do(t, "POST", "/api/chat", chat); st != 200 {
				t.Fatalf("%d번째: %d", i+1, st)
			}
		}
		if st, m := g.do(t, "POST", "/api/chat", chat); st != 429 || errCode(m) != "QUOTA_EXCEEDED" {
			t.Fatalf("11번째: %d %v", st, m)
		}
		ip := newSess().ip
		for i := range 3 {
			s := newSess()
			s.ip = ip
			if st, _ := s.do(t, "POST", "/api/auth/guest", nil); st != 200 {
				t.Fatalf("%d번째 게스트 세션: %d", i+1, st)
			}
		}
		s := newSess()
		s.ip = ip
		if st, m := s.do(t, "POST", "/api/auth/guest", nil); st != 429 || errCode(m) != "QUOTA_EXCEEDED" {
			t.Fatalf("4번째 게스트 세션: %d %v", st, m)
		}
	})
	t.Run("F-030 게스트 질문은 500자까지", func(t *testing.T) {
		g := newSess()
		g.do(t, "POST", "/api/auth/guest", nil)
		long := map[string]any{"messages": []map[string]string{{"role": "user", "content": strings.Repeat("가", 501)}}}
		if st, _ := g.do(t, "POST", "/api/chat", long); st != 400 {
			t.Fatalf("501자: %d", st)
		}
	})
}
