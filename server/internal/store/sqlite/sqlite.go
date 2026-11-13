// Package sqlite는 store.Store의 SQLite 구현이다 (ARCHITECTURE.md ADR-028).
// 드라이버 modernc.org/sqlite(순수 Go)는 이 패키지에서만 import한다 — cgo 없음 (ADR-007).
package sqlite

import (
	"context"
	"database/sql"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"net/url"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"

	_ "modernc.org/sqlite"
)

//go:embed migrations/*.sql
var migrations embed.FS

// DB는 SQLite 파일(또는 메모리) DB다.
type DB struct{ db *sql.DB }

var _ store.Store = (*DB)(nil)

// Open은 dir/chatd.db를 연다. dir이 비면 메모리 DB(프로세스가 끝나면 사라짐)다.
// 연결은 하나만 쓴다: 쓰기가 한 번에 하나라 AddUsage의 확인·증가가 겹치지 않는다.
func Open(dir string) (*DB, error) {
	pragmas := "_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)"
	dsn := "file::memory:?" + pragmas
	if dir != "" {
		p, err := filepath.Abs(filepath.Join(dir, "chatd.db"))
		if err != nil {
			return nil, err
		}
		dsn = "file:" + (&url.URL{Path: p}).EscapedPath() + "?" + pragmas + "&_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)"
	}
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	db.SetConnMaxLifetime(0)
	db.SetConnMaxIdleTime(0)
	d := &DB{db: db}
	if err := d.migrate(context.Background()); err != nil {
		db.Close()
		return nil, err
	}
	return d, nil
}

// Close는 DB를 닫는다.
func (d *DB) Close() error { return d.db.Close() }

// migrate는 migrations/NNN_*.sql을 번호 순서로 한 번씩 적용한다 (F-026 AC6).
func (d *DB) migrate(ctx context.Context) error {
	if _, err := d.db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)`); err != nil {
		return err
	}
	names, err := fs.Glob(migrations, "migrations/*.sql")
	if err != nil {
		return err
	}
	sort.Strings(names)
	for _, name := range names {
		base := filepath.Base(name)
		num, _, ok := strings.Cut(base, "_")
		v, err := strconv.Atoi(num)
		if !ok || err != nil {
			return fmt.Errorf("마이그레이션 이름이 NNN_이름.sql이 아니에요: %s", base)
		}
		var n int
		if err := d.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM schema_migrations WHERE version = ?`, v).Scan(&n); err != nil {
			return err
		}
		if n > 0 {
			continue
		}
		body, err := migrations.ReadFile(name)
		if err != nil {
			return err
		}
		tx, err := d.db.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, string(body)); err != nil {
			tx.Rollback()
			return fmt.Errorf("마이그레이션 %s 실패: %w", base, err)
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)`, v, ts(time.Now())); err != nil {
			tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
	}
	return nil
}

// 시각은 UTC RFC 3339(나노초)로 저장한다 — 문자열 비교가 시간 순서와 같다.
func ts(t time.Time) string { return t.UTC().Format("2006-01-02T15:04:05.000000000Z") }

func parseTS(s string) time.Time {
	t, _ := time.Parse(time.RFC3339Nano, s)
	return t
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func isUnique(err error) bool {
	return err != nil && strings.Contains(err.Error(), "UNIQUE constraint failed")
}

const userCols = `id, name, role, status, created_by, created_at, COALESCE(google_sub, ''), COALESCE(invite_email, '')`

type scanner interface{ Scan(dest ...any) error }

func scanUser(row scanner) (store.User, error) {
	var u store.User
	var role, status, created string
	err := row.Scan(&u.ID, &u.Name, &role, &status, &u.CreatedBy, &created, &u.GoogleSub, &u.InviteEmail)
	if errors.Is(err, sql.ErrNoRows) {
		return store.User{}, store.ErrNotFound
	}
	u.Role, u.Status, u.CreatedAt = store.Role(role), store.Status(status), parseTS(created)
	return u, err
}

func (d *DB) CreateUser(ctx context.Context, u store.User) error {
	_, err := d.db.ExecContext(ctx, `INSERT INTO users (id, name, role, status, created_by, created_at, google_sub, invite_email) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
		u.ID, u.Name, string(u.Role), string(u.Status), u.CreatedBy, ts(u.CreatedAt), nullable(u.GoogleSub), nullable(u.InviteEmail))
	if isUnique(err) {
		return store.ErrConflict
	}
	return err
}

func (d *DB) GetUser(ctx context.Context, id string) (store.User, error) {
	return scanUser(d.db.QueryRowContext(ctx, `SELECT `+userCols+` FROM users WHERE id = ?`, id))
}

func (d *DB) UserByGoogleSub(ctx context.Context, sub string) (store.User, error) {
	if sub == "" {
		return store.User{}, store.ErrNotFound
	}
	return scanUser(d.db.QueryRowContext(ctx, `SELECT `+userCols+` FROM users WHERE google_sub = ?`, sub))
}

func (d *DB) UserByInviteEmail(ctx context.Context, email string) (store.User, error) {
	if email == "" {
		return store.User{}, store.ErrNotFound
	}
	return scanUser(d.db.QueryRowContext(ctx, `SELECT `+userCols+` FROM users WHERE invite_email = ?`, email))
}

func (d *DB) UpdateUser(ctx context.Context, u store.User) error {
	res, err := d.db.ExecContext(ctx, `UPDATE users SET name = ?, role = ?, status = ?, google_sub = ?, invite_email = ? WHERE id = ?`,
		u.Name, string(u.Role), string(u.Status), nullable(u.GoogleSub), nullable(u.InviteEmail), u.ID)
	if isUnique(err) {
		return store.ErrConflict
	}
	return affected(res, err)
}

func affected(res sql.Result, err error) error {
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return store.ErrNotFound
	}
	return nil
}

func (d *DB) DeleteUser(ctx context.Context, id string) error {
	return affected(d.db.ExecContext(ctx, `DELETE FROM users WHERE id = ?`, id))
}

func (d *DB) ListUsers(ctx context.Context) ([]store.User, error) {
	rows, err := d.db.QueryContext(ctx, `SELECT `+userCols+` FROM users ORDER BY created_at, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []store.User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

func (d *DB) CountActiveRole(ctx context.Context, r store.Role) (int, error) {
	var n int
	err := d.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM users WHERE role = ? AND status = 'active'`, string(r)).Scan(&n)
	return n, err
}

func (d *DB) SetLoginCode(ctx context.Context, c store.LoginCode) error {
	_, err := d.db.ExecContext(ctx, `INSERT INTO login_codes (user_id, code_hash, issued_by, expires_at) VALUES (?, ?, ?, ?)
		ON CONFLICT (user_id) DO UPDATE SET code_hash = excluded.code_hash, issued_by = excluded.issued_by, expires_at = excluded.expires_at`,
		c.UserID, c.CodeHash, c.IssuedBy, ts(c.ExpiresAt))
	if isUnique(err) {
		return store.ErrConflict
	}
	return err
}

func (d *DB) UseLoginCode(ctx context.Context, codeHash string, now time.Time) (string, error) {
	var id string
	err := d.db.QueryRowContext(ctx, `DELETE FROM login_codes WHERE code_hash = ? AND expires_at > ? RETURNING user_id`, codeHash, ts(now)).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return "", store.ErrNotFound
	}
	return id, err
}

func (d *DB) CreateSession(ctx context.Context, s store.Session) error {
	_, err := d.db.ExecContext(ctx, `INSERT INTO sessions (token_hash, user_id, kind, created_at, last_seen_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)`,
		s.TokenHash, nullable(s.UserID), string(s.Kind), ts(s.CreatedAt), ts(s.LastSeenAt), ts(s.ExpiresAt))
	return err
}

func (d *DB) GetSession(ctx context.Context, tokenHash string) (store.Session, error) {
	var s store.Session
	var kind, created, seen, expires string
	err := d.db.QueryRowContext(ctx, `SELECT token_hash, COALESCE(user_id, ''), kind, created_at, last_seen_at, expires_at FROM sessions WHERE token_hash = ?`, tokenHash).
		Scan(&s.TokenHash, &s.UserID, &kind, &created, &seen, &expires)
	if errors.Is(err, sql.ErrNoRows) {
		return store.Session{}, store.ErrNotFound
	}
	s.Kind, s.CreatedAt, s.LastSeenAt, s.ExpiresAt = store.SessionKind(kind), parseTS(created), parseTS(seen), parseTS(expires)
	return s, err
}

func (d *DB) TouchSession(ctx context.Context, tokenHash string, lastSeen, expires time.Time) error {
	return affected(d.db.ExecContext(ctx, `UPDATE sessions SET last_seen_at = ?, expires_at = ? WHERE token_hash = ?`, ts(lastSeen), ts(expires), tokenHash))
}

func (d *DB) DeleteSession(ctx context.Context, tokenHash string) error {
	_, err := d.db.ExecContext(ctx, `DELETE FROM sessions WHERE token_hash = ?`, tokenHash)
	return err
}

func (d *DB) DeleteUserSessions(ctx context.Context, userID string) error {
	_, err := d.db.ExecContext(ctx, `DELETE FROM sessions WHERE user_id = ?`, userID)
	return err
}

func (d *DB) DeleteExpiredSessions(ctx context.Context, now time.Time) (int, error) {
	res, err := d.db.ExecContext(ctx, `DELETE FROM sessions WHERE expires_at <= ?`, ts(now))
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return int(n), nil
}

func (d *DB) ids(ctx context.Context, q string, arg string) ([]string, error) {
	rows, err := d.db.QueryContext(ctx, q, arg)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, rows.Err()
}

func (d *DB) AddCare(ctx context.Context, caregiverID, elderID string) error {
	_, err := d.db.ExecContext(ctx, `INSERT OR IGNORE INTO care_assignments (caregiver_id, elder_id) VALUES (?, ?)`, caregiverID, elderID)
	return err
}

func (d *DB) RemoveCare(ctx context.Context, caregiverID, elderID string) error {
	return affected(d.db.ExecContext(ctx, `DELETE FROM care_assignments WHERE caregiver_id = ? AND elder_id = ?`, caregiverID, elderID))
}

func (d *DB) EldersOfCaregiver(ctx context.Context, caregiverID string) ([]string, error) {
	return d.ids(ctx, `SELECT elder_id FROM care_assignments WHERE caregiver_id = ? ORDER BY elder_id`, caregiverID)
}

func (d *DB) AddGuardianLink(ctx context.Context, guardianID, elderID string) error {
	_, err := d.db.ExecContext(ctx, `INSERT OR IGNORE INTO guardian_links (guardian_id, elder_id) VALUES (?, ?)`, guardianID, elderID)
	return err
}

func (d *DB) RemoveGuardianLink(ctx context.Context, guardianID, elderID string) error {
	return affected(d.db.ExecContext(ctx, `DELETE FROM guardian_links WHERE guardian_id = ? AND elder_id = ?`, guardianID, elderID))
}

func (d *DB) EldersOfGuardian(ctx context.Context, guardianID string) ([]string, error) {
	return d.ids(ctx, `SELECT elder_id FROM guardian_links WHERE guardian_id = ? ORDER BY elder_id`, guardianID)
}

func (d *DB) GuardiansOfElder(ctx context.Context, elderID string) ([]string, error) {
	return d.ids(ctx, `SELECT guardian_id FROM guardian_links WHERE elder_id = ? ORDER BY guardian_id`, elderID)
}

func (d *DB) AddAudit(ctx context.Context, e store.AuditEntry) error {
	_, err := d.db.ExecContext(ctx, `INSERT INTO audit_log (actor_id, action, target_id, at) VALUES (?, ?, ?, ?)`, e.ActorID, e.Action, e.TargetID, ts(e.At))
	return err
}

func (d *DB) ListAudit(ctx context.Context, limit int) ([]store.AuditEntry, error) {
	if limit <= 0 || limit > 500 {
		limit = 500
	}
	rows, err := d.db.QueryContext(ctx, `SELECT id, actor_id, action, target_id, at FROM audit_log ORDER BY id DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []store.AuditEntry
	for rows.Next() {
		var e store.AuditEntry
		var at string
		if err := rows.Scan(&e.ID, &e.ActorID, &e.Action, &e.TargetID, &at); err != nil {
			return nil, err
		}
		e.At = parseTS(at)
		out = append(out, e)
	}
	return out, rows.Err()
}

func (d *DB) AddUsage(ctx context.Context, deltas []store.UsageDelta) error {
	tx, err := d.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, u := range deltas {
		if u.Limit > 0 {
			var cur int
			err := tx.QueryRowContext(ctx, `SELECT amount FROM usage WHERE subject = ? AND bucket = ?`, u.Subject, u.Bucket).Scan(&cur)
			if err != nil && !errors.Is(err, sql.ErrNoRows) {
				return err
			}
			if cur+u.Amount > u.Limit {
				return store.ErrQuota
			}
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO usage (subject, bucket, amount) VALUES (?, ?, ?)
			ON CONFLICT (subject, bucket) DO UPDATE SET amount = amount + excluded.amount`, u.Subject, u.Bucket, u.Amount); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (d *DB) DeleteUsageBefore(ctx context.Context, before string) (int, error) {
	res, err := d.db.ExecContext(ctx, `DELETE FROM usage WHERE bucket < ?`, before)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return int(n), nil
}
