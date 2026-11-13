package usage

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store/sqlite"
)

var ctx = context.Background()

func newLimiter(t *testing.T, l Limits) (*Limiter, *time.Time) {
	t.Helper()
	db, err := sqlite.Open("")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	now := time.Date(2026, 11, 13, 14, 0, 0, 0, time.UTC) // 서울 23시
	return New(db, l, func() time.Time { return now }), &now
}

func TestF030Limits(t *testing.T) {
	t.Run("F-030 AC2 게스트 11번째 질문은 막힌다, 자정을 넘겨도 다시 생기지 않는다", func(t *testing.T) {
		l, now := newLimiter(t, Defaults)
		g := Who{Subject: "guest:abc", Guest: true, Since: *now}
		for i := range 10 {
			if err := l.ChatTurn(ctx, g); err != nil {
				t.Fatalf("%d번째: %v", i+1, err)
			}
			if i == 4 {
				*now = now.Add(2 * time.Hour) // 서울 자정 넘김
			}
		}
		if err := l.ChatTurn(ctx, g); !errors.Is(err, ErrQuota) {
			t.Fatalf("11번째: %v", err)
		}
	})
	t.Run("F-030 AC2 같은 IP 4번째 게스트 세션과 전체 게스트 상한", func(t *testing.T) {
		l, now := newLimiter(t, Limits{GuestPerIPHourly: 3, GuestTurns: 10, GuestDailyTotal: 5})
		for range 3 {
			if err := l.GuestStart(ctx, "1.2.3.4"); err != nil {
				t.Fatal(err)
			}
		}
		if err := l.GuestStart(ctx, "1.2.3.4"); !errors.Is(err, ErrQuota) {
			t.Fatalf("4번째: %v", err)
		}
		if err := l.GuestStart(ctx, "5.6.7.8"); err != nil {
			t.Fatalf("다른 IP: %v", err)
		}
		*now = now.Add(time.Hour)
		if err := l.GuestStart(ctx, "1.2.3.4"); err != nil {
			t.Fatalf("한 시간 뒤: %v", err)
		}
		for i := range 5 {
			if err := l.ChatTurn(ctx, Who{Subject: "guest:" + string(rune('a'+i)), Guest: true, Since: *now}); err != nil {
				t.Fatal(err)
			}
		}
		if err := l.ChatTurn(ctx, Who{Subject: "guest:z", Guest: true, Since: *now}); !errors.Is(err, ErrQuota) {
			t.Fatalf("전체 게스트 상한: %v", err)
		}
	})
	t.Run("F-030 AC4 사용자·음성·전체 상한, 서울 0시에 풀린다", func(t *testing.T) {
		l, now := newLimiter(t, Limits{UserDailyTurns: 2, AdminDailyTurns: 3, VoiceDailyMin: 20, DailyGlobal: 100})
		u := Who{Subject: "usr_1"}
		l.ChatTurn(ctx, u)
		l.ChatTurn(ctx, u)
		if err := l.ChatTurn(ctx, u); !errors.Is(err, ErrQuota) {
			t.Fatalf("사용자 3번째: %v", err)
		}
		a := Who{Subject: "usr_2", Admin: true}
		for range 3 {
			if err := l.ChatTurn(ctx, a); err != nil {
				t.Fatal(err)
			}
		}
		l.VoiceSession(ctx, u)
		l.VoiceSession(ctx, u)
		if err := l.VoiceSession(ctx, u); !errors.Is(err, ErrQuota) {
			t.Fatalf("음성 30분째: %v", err)
		}
		*now = now.Add(time.Hour) // 서울 0시
		if err := l.ChatTurn(ctx, u); err != nil {
			t.Fatalf("다음 날: %v", err)
		}
		g, _ := newLimiter(t, Limits{DailyGlobal: 2})
		g.ChatTurn(ctx, Who{Subject: "a"})
		g.Background(ctx)
		if err := g.ChatTurn(ctx, Who{Subject: "b"}); !errors.Is(err, ErrQuota) {
			t.Fatalf("전체 상한: %v", err)
		}
	})
	t.Run("F-026 AC2 코드 시도는 IP마다 10분에 10번", func(t *testing.T) {
		l, now := newLimiter(t, Defaults)
		for range 10 {
			if err := l.CodeAttempt(ctx, "9.9.9.9"); err != nil {
				t.Fatal(err)
			}
		}
		if err := l.CodeAttempt(ctx, "9.9.9.9"); !errors.Is(err, ErrRateLimited) {
			t.Fatalf("11번째: %v", err)
		}
		*now = now.Add(10 * time.Minute)
		if err := l.CodeAttempt(ctx, "9.9.9.9"); err != nil {
			t.Fatalf("10분 뒤: %v", err)
		}
	})
	t.Run("F-030 AC6 이틀 지난 사용량(게스트 포함)은 지워진다", func(t *testing.T) {
		l, now := newLimiter(t, Defaults)
		l.ChatTurn(ctx, Who{Subject: "guest:x", Guest: true, Since: *now})
		*now = now.Add(49 * time.Hour)
		if n, _ := l.Sweep(ctx); n != 3 {
			t.Fatalf("지운 행 %d (게스트·전체·게스트 합계 3이어야 함)", n)
		}
	})
}
