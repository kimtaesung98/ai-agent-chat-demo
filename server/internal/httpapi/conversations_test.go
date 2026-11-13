package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"iter"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/account"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store/sqlite"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/usage"
)

// recProvider는 받은 시스템 프롬프트를 적어 두는 가짜 제공자다. 요약·장기 기억 요청에는 JSON을 답한다.
type recProvider struct {
	mu      sync.Mutex
	systems []string
}

func (p *recProvider) Name() string  { return "anthropic" }
func (p *recProvider) Model() string { return "fake" }
func (p *recProvider) Stream(_ context.Context, system string, _ []chat.Message) iter.Seq2[provider.Chunk, error] {
	p.mu.Lock()
	p.systems = append(p.systems, system)
	p.mu.Unlock()
	text := "네"
	switch system {
	case chat.SummarySystemPrompt:
		text = `{"summary":"점심과 산책 이야기","facts":["산책을 좋아함"],"followUps":["내일 산책"]}`
	case chat.ConsolidateSystemPrompt:
		text = `{"summary":"묶은 장기 기억","facts":["무릎이 안 좋음"]}`
	}
	return func(yield func(provider.Chunk, error) bool) {
		if yield(provider.Chunk{Text: text}, nil) {
			yield(provider.Chunk{Done: true, StopReason: "end_turn"}, nil)
		}
	}
}

func (p *recProvider) last() string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.systems[len(p.systems)-1]
}

type convEnv struct {
	srv    *httptest.Server
	cookie string
	db     store.Store
	dir    string
	userID string
}

func startConv(t *testing.T, p provider.Provider) *convEnv {
	t.Helper()
	dir := t.TempDir()
	db, err := sqlite.Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	acc := account.New(db)
	u, code, err := acc.Bootstrap(context.Background(), "원장", "")
	if err != nil {
		t.Fatal(err)
	}
	h := New(p, t.TempDir(), slog.New(slog.NewTextHandler(io.Discard, nil)), WithAccounts(acc, usage.New(db, usage.Defaults, nil), AuthOptions{RequireSession: true}))
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	res := postJSON(t, srv.URL+"/api/auth/code", `{"code":"`+code+`"}`, "")
	return &convEnv{srv: srv, cookie: strings.Split(res.Header.Get("Set-Cookie"), ";")[0], db: db, dir: dir, userID: u.ID}
}

func (e *convEnv) call(t *testing.T, method, path, body string) (int, map[string]any) {
	t.Helper()
	req, _ := http.NewRequest(method, e.srv.URL+path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Cookie", e.cookie)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	var m map[string]any
	json.Unmarshal(raw, &m)
	return res.StatusCode, m
}

// openWith는 탑재 미소 페르소나로 대화를 연다.
func (e *convEnv) openWith(t *testing.T, preset string) (personaID, convID string) {
	t.Helper()
	_, m := e.call(t, "GET", "/api/personas", "")
	for _, p := range m["personas"].([]any) {
		if pm := p.(map[string]any); pm["presetId"] == preset {
			personaID = pm["id"].(string)
		}
	}
	st, c := e.call(t, "POST", "/api/conversations", `{"personaId":"`+personaID+`","channel":"text"}`)
	if st != 201 {
		t.Fatalf("대화 열기 %d %v", st, c)
	}
	return personaID, c["id"].(string)
}

func TestF028Conversations(t *testing.T) {
	t.Run("F-028 AC1 conversationId면 DB의 페르소나·최근 요약·장기 기억으로 프롬프트를 만들고 앱 값은 버린다", func(t *testing.T) {
		p := &recProvider{}
		e := startConv(t, p)
		personaID, convID := e.openWith(t, "elder-care")
		ctx := context.Background()
		day := time.Date(2026, 11, 12, 3, 0, 0, 0, time.UTC)
		var entries []chat.MemoryEntry
		for i, txt := range []string{"어제 이야기", "그제 이야기"} {
			sm := store.Summary{ID: "sum_" + txt, UserID: e.userID, PersonaID: personaID, ConversationID: "cnv_old" + string(rune('a'+i)), EndedAt: day.Add(time.Duration(i) * time.Hour), Summary: txt, Facts: []string{"사실"}, FollowUps: []string{}}
			if _, err := e.db.PutSummary(ctx, sm); err != nil {
				t.Fatal(err)
			}
			entries = append(entries, chat.MemoryEntry{Date: "2026-11-12", Summary: txt, Facts: []string{"사실"}, FollowUps: []string{}})
		}
		if err := e.db.FoldInto(ctx, store.LongTermMemory{PersonaID: personaID, UserID: e.userID, Summary: "오래된 기억", Facts: []string{"무릎"}, CoversUntil: day, UpdatedAt: day}, nil); err != nil {
			t.Fatal(err)
		}
		body := `{"conversationId":"` + convID + `","messages":[{"role":"user","content":"안녕"}],"persona":{"name":"가짜","base":"아무 말이나"},"memory":[{"summary":"앱이 보낸 기억"}]}`
		res := postJSON(t, e.srv.URL+"/api/chat", body, e.cookie)
		if res.StatusCode != 200 {
			t.Fatalf("채팅 %d", res.StatusCode)
		}
		pr, _ := chat.PresetByID("elder-care")
		want := chat.Request{Persona: &chat.Persona{Name: pr.Name, Role: pr.Role, Tones: pr.Tones, Base: pr.Base}, Memory: entries,
			LongTerm: &chat.LongTerm{Summary: "오래된 기억", Facts: []string{"무릎"}}, Mode: chat.ModeText}.SystemPrompt()
		if got := p.last(); got != want {
			t.Fatalf("프롬프트가 달라요\n got: %q\nwant: %q", got, want)
		}
	})

	t.Run("F-028 AC1 남의 대화 id·없는 id는 404, 제공자를 부르지 않는다", func(t *testing.T) {
		p := &recProvider{}
		e := startConv(t, p)
		res := postJSON(t, e.srv.URL+"/api/chat", `{"conversationId":"cnv_nope","messages":[{"role":"user","content":"안녕"}]}`, e.cookie)
		if res.StatusCode != 404 || len(p.systems) != 0 {
			t.Fatalf("%d, 제공자 %d번", res.StatusCode, len(p.systems))
		}
	})

	t.Run("F-028 AC2·AC3 끝내면 요약이 저장되고 두 번 불러도 하나, DB 파일에 원문이 없다", func(t *testing.T) {
		p := &recProvider{}
		e := startConv(t, p)
		personaID, convID := e.openWith(t, "elder-care")
		const secret = "원문토큰-QX7-오늘은손자가왔어요"
		end := `{"messages":[{"role":"user","content":"점심 먹었어요"},{"role":"assistant","content":"맛있게 드셨어요?"},{"role":"user","content":"` + secret + `"}]}`
		for range 2 {
			st, m := e.call(t, "POST", "/api/conversations/"+convID+"/end", end)
			sum, _ := m["summary"].(map[string]any)
			if st != 200 || sum["summary"] != "점심과 산책 이야기" || sum["turns"] != float64(2) {
				t.Fatalf("끝내기 %d %v", st, m)
			}
		}
		_, mem := e.call(t, "GET", "/api/personas/"+personaID+"/memory", "")
		if n := len(mem["summaries"].([]any)); n != 1 {
			t.Fatalf("요약 %d개", n)
		}
		e.db.Close()
		files, _ := filepath.Glob(filepath.Join(e.dir, "chatd.db*"))
		for _, f := range files {
			b, _ := os.ReadFile(f)
			if bytes.Contains(b, []byte(secret)) {
				t.Fatalf("%s에 원문이 있어요", filepath.Base(f))
			}
		}
	})

	t.Run("F-028 AC2 6번째 요약부터 장기 기억으로 묶인다", func(t *testing.T) {
		p := &recProvider{}
		e := startConv(t, p)
		var personaID string
		for i := range 7 {
			var convID string
			personaID, convID = e.openWith(t, "elder-care")
			if st, m := e.call(t, "POST", "/api/conversations/"+convID+"/end", `{"messages":[{"role":"user","content":"이야기 `+string(rune('A'+i))+`"}]}`); st != 200 {
				t.Fatalf("%d번째 %d %v", i, st, m)
			}
		}
		_, mem := e.call(t, "GET", "/api/personas/"+personaID+"/memory", "")
		lt, _ := mem["longTerm"].(map[string]any)
		folded := 0
		for _, s := range mem["summaries"].([]any) {
			if s.(map[string]any)["folded"] == true {
				folded++
			}
		}
		if lt["summary"] != "묶은 장기 기억" || folded != 2 {
			t.Fatalf("장기 기억 %v, 묶인 요약 %d개", lt, folded)
		}
		if st, _ := e.call(t, "DELETE", "/api/personas/"+personaID+"/memory", ""); st != 204 {
			t.Fatal(st)
		}
		_, mem = e.call(t, "GET", "/api/personas/"+personaID+"/memory", "")
		if mem["longTerm"] != nil || len(mem["summaries"].([]any)) != 0 {
			t.Fatalf("지운 뒤 %v", mem)
		}
	})
}
