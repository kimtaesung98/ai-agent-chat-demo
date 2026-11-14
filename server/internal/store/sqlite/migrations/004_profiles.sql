-- F-026 프로필 (SPEC.md §7.2 Profile, API-013). 이름은 users.name에 둔다.
CREATE TABLE profiles (
    user_id         TEXT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    about           TEXT NOT NULL DEFAULT '',
    text_size       TEXT NOT NULL DEFAULT 'normal' CHECK (text_size IN ('normal', 'large', 'xlarge')),
    voice_on_start  INTEGER NOT NULL DEFAULT 0,
    last_persona_id TEXT NOT NULL DEFAULT '',
    updated_at      TEXT NOT NULL
);
