// Package usage는 AI 사용량 상한을 제공자를 부르기 전에 확인·증가한다 (SPEC.md F-030, ARCHITECTURE.md ADR-033).
// 상한은 게스트 세션·IP별 게스트 만들기·역할별 사용자·서버 전체 네 겹이다. store 인터페이스만 안다.
package usage

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
)

// ErrQuota는 상한을 넘었다는 뜻이다 (429 QUOTA_EXCEEDED).
var ErrQuota = errors.New("usage: quota exceeded")

// ErrRateLimited는 로그인 시도가 너무 많다는 뜻이다 (429 RATE_LIMITED).
var ErrRateLimited = errors.New("usage: rate limited")

// Limits는 상한이다. 0이면 상한 없음.
type Limits struct {
	GuestTurns       int // 게스트 세션 하나의 글 질문
	GuestPerIPHourly int // IP마다 시간당 게스트 세션 만들기
	GuestDailyTotal  int // 서버 전체 게스트 질문 하루
	UserDailyTurns   int // 어르신·보호자 하루 글 질문
	AdminDailyTurns  int // 요양사 이상 하루 글 질문
	VoiceDailyMin    int // 사람마다 하루 음성 분
	DailyGlobal      int // 서버 전체 하루 AI 호출 (글·음성·요약 모두)
	CodeTriesPer10m  int // IP마다 10분에 코드 로그인 시도
}

// Defaults는 SPEC F-030 상세 동작 2·3의 기본값이다.
var Defaults = Limits{
	GuestTurns: 10, GuestPerIPHourly: 3, GuestDailyTotal: 300,
	UserDailyTurns: 300, AdminDailyTurns: 500, VoiceDailyMin: 60, DailyGlobal: 5000,
	CodeTriesPer10m: 10,
}

// VoiceSessionMinutes는 음성 세션 하나를 몇 분으로 셀지다 (임시 키로는 세션 길이를 강제할 수 없어 미리 센다).
const VoiceSessionMinutes = 10

// seoul은 하루를 나누는 시간대다 (서울 0시에 풀림, tzdata 없이).
var seoul = time.FixedZone("KST", 9*3600)

// Limiter는 사용량 상한이다.
type Limiter struct {
	store  store.Store
	limits Limits
	now    func() time.Time
}

// New는 Limiter를 만든다. now가 nil이면 time.Now.
func New(st store.Store, l Limits, now func() time.Time) *Limiter {
	if now == nil {
		now = time.Now
	}
	return &Limiter{store: st, limits: l, now: now}
}

// Limits는 지금 상한이다.
func (l *Limiter) Limits() Limits { return l.limits }

func (l *Limiter) day() string { return l.now().In(seoul).Format("2006-01-02") }

func (l *Limiter) hour() string { return l.now().In(seoul).Format("2006-01-02T15") }

func (l *Limiter) tenMin() string {
	t := l.now().In(seoul)
	return t.Format("2006-01-02T15:") + string(rune('0'+t.Minute()/10))
}

// ipKey는 IP를 그대로 저장하지 않으려고 해시한다.
func ipKey(ip string) string {
	h := sha256.Sum256([]byte("ip|" + ip))
	return "ip:" + hex.EncodeToString(h[:8])
}

func (l *Limiter) add(ctx context.Context, d []store.UsageDelta, quotaErr error) error {
	err := l.store.AddUsage(ctx, d)
	if errors.Is(err, store.ErrQuota) {
		return quotaErr
	}
	return err
}

// Who는 사용량 주체다.
type Who struct {
	Subject string // 사용자 id 또는 "guest:…"
	Guest   bool
	Admin   bool      // 요양사 이상
	Since   time.Time // 게스트 세션을 연 시각
}

func (l *Limiter) turnLimit(w Who) int {
	switch {
	case w.Guest:
		return l.limits.GuestTurns
	case w.Admin:
		return l.limits.AdminDailyTurns
	}
	return l.limits.UserDailyTurns
}

// ChatTurn은 글 질문 하나를 센다. 게스트는 세션 전체(24시간) 상한, 사용자는 하루 상한.
func (l *Limiter) ChatTurn(ctx context.Context, w Who) error {
	day := l.day()
	bucket := day
	if w.Guest {
		// 게스트는 세션 전체(24시간)로 센다: 자정을 넘겨도 다시 10번이 생기지 않게 세션을 연 날로 묶는다
		bucket = w.Since.In(seoul).Format("2006-01-02")
	}
	d := []store.UsageDelta{
		{Subject: "turns:" + w.Subject, Bucket: bucket, Amount: 1, Limit: l.turnLimit(w)},
		{Subject: "global", Bucket: day, Amount: 1, Limit: l.limits.DailyGlobal},
	}
	if w.Guest {
		d = append(d, store.UsageDelta{Subject: "guest-total", Bucket: day, Amount: 1, Limit: l.limits.GuestDailyTotal})
	}
	return l.add(ctx, d, ErrQuota)
}

// Background는 요약·장기 기억처럼 사용자 상한에는 세지 않고 전체 상한에만 세는 호출이다.
func (l *Limiter) Background(ctx context.Context) error {
	return l.add(ctx, []store.UsageDelta{{Subject: "global", Bucket: l.day(), Amount: 1, Limit: l.limits.DailyGlobal}}, ErrQuota)
}

// VoiceSession은 음성 세션 하나(VoiceSessionMinutes분)를 센다. 게스트는 음성을 쓸 수 없다(호출자가 막음).
func (l *Limiter) VoiceSession(ctx context.Context, w Who) error {
	day := l.day()
	return l.add(ctx, []store.UsageDelta{
		{Subject: "voice-min:" + w.Subject, Bucket: day, Amount: VoiceSessionMinutes, Limit: l.limits.VoiceDailyMin},
		{Subject: "global", Bucket: day, Amount: 1, Limit: l.limits.DailyGlobal},
	}, ErrQuota)
}

// GuestStart는 IP마다 시간당 게스트 세션 만들기를 센다.
func (l *Limiter) GuestStart(ctx context.Context, ip string) error {
	return l.add(ctx, []store.UsageDelta{{Subject: "guest-start:" + ipKey(ip), Bucket: l.hour(), Amount: 1, Limit: l.limits.GuestPerIPHourly}}, ErrQuota)
}

// CodeAttempt는 IP마다 10분 단위로 코드 로그인 시도를 센다 (F-026 상세 동작 5).
func (l *Limiter) CodeAttempt(ctx context.Context, ip string) error {
	return l.add(ctx, []store.UsageDelta{{Subject: "code-try:" + ipKey(ip), Bucket: l.tenMin(), Amount: 1, Limit: l.limits.CodeTriesPer10m}}, ErrRateLimited)
}

// Sweep은 이틀 지난 버킷을 지운다 (게스트 행 포함 — F-030 AC6).
func (l *Limiter) Sweep(ctx context.Context) (int, error) {
	before := l.now().In(seoul).AddDate(0, 0, -1).Format("2006-01-02")
	return l.store.DeleteUsageBefore(ctx, before)
}
