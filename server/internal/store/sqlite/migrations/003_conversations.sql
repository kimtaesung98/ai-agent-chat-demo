-- F-028 대화·요약·장기 기억 (SPEC.md §7.2). 대화 원문은 서버에 두지 않는다 (Q-009 — 기기 보관).
CREATE TABLE conversations (
    id         TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    persona_id TEXT NOT NULL REFERENCES personas (id) ON DELETE CASCADE,
    channel    TEXT NOT NULL CHECK (channel IN ('text', 'voice')),
    status     TEXT NOT NULL CHECK (status IN ('open', 'ended', 'summarized')),
    started_at TEXT NOT NULL,
    ended_at   TEXT NOT NULL DEFAULT '',
    turns      INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX conversations_user ON conversations (user_id, started_at);

CREATE TABLE summaries (
    id              TEXT PRIMARY KEY,
    user_id         TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    persona_id      TEXT NOT NULL REFERENCES personas (id) ON DELETE CASCADE,
    conversation_id TEXT NOT NULL UNIQUE,
    ended_at        TEXT NOT NULL,
    summary         TEXT NOT NULL,
    facts           TEXT NOT NULL DEFAULT '[]',
    follow_ups      TEXT NOT NULL DEFAULT '[]',
    turns           INTEGER NOT NULL DEFAULT 0,
    folded          INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX summaries_persona ON summaries (user_id, persona_id, ended_at);

CREATE TABLE long_term_memory (
    persona_id   TEXT PRIMARY KEY REFERENCES personas (id) ON DELETE CASCADE,
    user_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    summary      TEXT NOT NULL,
    facts        TEXT NOT NULL DEFAULT '[]',
    covers_until TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);
