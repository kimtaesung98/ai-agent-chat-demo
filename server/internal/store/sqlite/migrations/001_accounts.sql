-- F-026·F-029·F-030 계정·세션·로그인 코드·역할 관계·감사·사용량 (SPEC.md §7)
CREATE TABLE users (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    role         TEXT NOT NULL CHECK (role IN ('super_admin', 'caregiver', 'elder', 'guardian')),
    status       TEXT NOT NULL CHECK (status IN ('active', 'suspended')),
    created_by   TEXT NOT NULL DEFAULT '',
    created_at   TEXT NOT NULL,
    google_sub   TEXT,
    invite_email TEXT
);
CREATE UNIQUE INDEX users_google_sub ON users (google_sub) WHERE google_sub IS NOT NULL;
CREATE UNIQUE INDEX users_invite_email ON users (invite_email) WHERE invite_email IS NOT NULL;

CREATE TABLE login_codes (
    user_id    TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    code_hash  TEXT NOT NULL UNIQUE,
    issued_by  TEXT NOT NULL DEFAULT '',
    expires_at TEXT NOT NULL
);

CREATE TABLE sessions (
    token_hash   TEXT PRIMARY KEY,
    user_id      TEXT REFERENCES users (id) ON DELETE CASCADE,
    kind         TEXT NOT NULL CHECK (kind IN ('user', 'guest')),
    created_at   TEXT NOT NULL,
    last_seen_at TEXT NOT NULL,
    expires_at   TEXT NOT NULL
);
CREATE INDEX sessions_user ON sessions (user_id);

CREATE TABLE care_assignments (
    caregiver_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    elder_id     TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    PRIMARY KEY (caregiver_id, elder_id)
);
CREATE INDEX care_elder ON care_assignments (elder_id);

CREATE TABLE guardian_links (
    guardian_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    elder_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    PRIMARY KEY (guardian_id, elder_id)
);
CREATE INDEX guardian_elder ON guardian_links (elder_id);

-- 계정을 지워도 기록은 남긴다 (id만, 내용 없음)
CREATE TABLE audit_log (
    id        INTEGER PRIMARY KEY AUTOINCREMENT,
    actor_id  TEXT NOT NULL,
    action    TEXT NOT NULL,
    target_id TEXT NOT NULL DEFAULT '',
    at        TEXT NOT NULL
);

CREATE TABLE usage (
    subject TEXT NOT NULL,
    bucket  TEXT NOT NULL,
    amount  INTEGER NOT NULL,
    PRIMARY KEY (subject, bucket)
);
CREATE INDEX usage_bucket ON usage (bucket);
