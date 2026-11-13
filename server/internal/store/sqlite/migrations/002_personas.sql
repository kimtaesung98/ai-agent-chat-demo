-- F-027 사용자 페르소나 (SPEC.md §7.2 Persona v1). 프리셋 카탈로그는 DB가 아니라 chat 패키지에 있다.
CREATE TABLE personas (
    id           TEXT PRIMARY KEY,
    user_id      TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind         TEXT NOT NULL CHECK (kind IN ('preset', 'custom')),
    preset_id    TEXT NOT NULL DEFAULT '',
    name         TEXT NOT NULL,
    role         TEXT NOT NULL DEFAULT '',
    tones        TEXT NOT NULL DEFAULT '[]',
    instructions TEXT NOT NULL DEFAULT '',
    revision     INTEGER NOT NULL,
    client_id    TEXT,
    created_at   TEXT NOT NULL,
    updated_at   TEXT NOT NULL
);
CREATE INDEX personas_user ON personas (user_id, created_at);
CREATE UNIQUE INDEX personas_client ON personas (user_id, client_id) WHERE client_id IS NOT NULL;

-- 처음 계정에 탑재 페르소나를 한 번만 넣었는지 (지운 뒤 다시 생기지 않게)
ALTER TABLE users ADD COLUMN personas_seeded INTEGER NOT NULL DEFAULT 0;
