package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/chat"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store"
)

// 프로필 (SPEC.md F-026 상세 동작 8, §7.2 Profile, API-013).
// 이름은 계정(users.name), 나머지는 profiles. "나에 대해"(about)는 대화 프롬프트에 실린다 (F-028 AC1).

var textSizes = map[string]bool{"normal": true, "large": true, "xlarge": true}

// profileOf는 프로필을 읽는다. 아직 없으면 기본값.
func (s *server) profileOf(ctx context.Context, userID string) (store.Profile, error) {
	p, err := s.store.GetProfile(ctx, userID)
	if errors.Is(err, store.ErrNotFound) {
		return store.Profile{UserID: userID, TextSize: "normal"}, nil
	}
	return p, err
}

func profileJSON(u store.User, p store.Profile) map[string]any {
	m := map[string]any{
		"displayName": u.Name, "about": p.About,
		"settings":      map[string]any{"textSize": p.TextSize, "voiceOnStart": p.VoiceOnStart},
		"lastPersonaId": p.LastPersonaID,
	}
	if !p.UpdatedAt.IsZero() {
		m["updatedAt"] = p.UpdatedAt.UTC().Format(time.RFC3339)
	}
	return m
}

func (s *server) handleGetProfile(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	p, err := s.profileOf(r.Context(), user.ID)
	if err != nil {
		s.storeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, profileJSON(user, p))
}

const msgProfileInvalid = "프로필 형식이 올바르지 않아요. 이름은 1~20자, 나에 대해는 1,000자까지예요."

// profilePatch는 PUT 본문이다. 보낸 필드만 바꾼다. 모르는 필드·설정 키는 버린다.
type profilePatch struct {
	DisplayName   *string
	About         *string
	TextSize      *string
	VoiceOnStart  *bool
	LastPersonaID *string
}

func parseProfilePatch(body []byte) (profilePatch, bool) {
	var root map[string]json.RawMessage
	if !bytes.HasPrefix(bytes.TrimSpace(body), []byte("{")) || json.Unmarshal(body, &root) != nil {
		return profilePatch{}, false
	}
	var p profilePatch
	str := func(key string, max int) (*string, bool) {
		raw, has := root[key]
		if !has {
			return nil, true
		}
		var v string
		if json.Unmarshal(raw, &v) != nil {
			return nil, false
		}
		v = strings.TrimSpace(v)
		if utf16Len(v) > max {
			return nil, false
		}
		return &v, true
	}
	var ok bool
	if p.DisplayName, ok = str("displayName", 40); !ok {
		return p, false
	}
	if p.About, ok = str("about", chat.MaxPersonaAbout); !ok {
		return p, false
	}
	if p.LastPersonaID, ok = str("lastPersonaId", 64); !ok {
		return p, false
	}
	if raw, has := root["settings"]; has {
		var set map[string]json.RawMessage
		if json.Unmarshal(raw, &set) != nil || set == nil {
			return p, false
		}
		if v, has := set["textSize"]; has {
			var t string
			if json.Unmarshal(v, &t) != nil || !textSizes[t] {
				return p, false
			}
			p.TextSize = &t
		}
		if v, has := set["voiceOnStart"]; has {
			var b bool
			if json.Unmarshal(v, &b) != nil {
				return p, false
			}
			p.VoiceOnStart = &b
		}
	}
	return p, true
}

func utf16Len(s string) int {
	n := 0
	for _, r := range s {
		if r >= 0x10000 {
			n += 2
		} else {
			n++
		}
	}
	return n
}

func (s *server) handlePutProfile(w http.ResponseWriter, r *http.Request) {
	user, ok := requireUser(w, r)
	if !ok {
		return
	}
	body, ok := readBody(w, r)
	if !ok {
		return
	}
	patch, ok := parseProfilePatch(body)
	if !ok {
		writeError(w, http.StatusBadRequest, "INVALID_INPUT", msgProfileInvalid)
		return
	}
	ctx := r.Context()
	if patch.LastPersonaID != nil && *patch.LastPersonaID != "" {
		if _, err := s.store.GetPersona(ctx, user.ID, *patch.LastPersonaID); err != nil {
			s.storeError(w, err) // 남의 페르소나·없는 id는 404
			return
		}
	}
	if patch.DisplayName != nil {
		u, err := s.accounts.Rename(ctx, user, *patch.DisplayName)
		if err != nil {
			s.accountError(w, err)
			return
		}
		user = u
	}
	p, err := s.profileOf(ctx, user.ID)
	if err != nil {
		s.storeError(w, err)
		return
	}
	if patch.About != nil {
		p.About = *patch.About
	}
	if patch.TextSize != nil {
		p.TextSize = *patch.TextSize
	}
	if patch.VoiceOnStart != nil {
		p.VoiceOnStart = *patch.VoiceOnStart
	}
	if patch.LastPersonaID != nil {
		p.LastPersonaID = *patch.LastPersonaID
	}
	p.UpdatedAt = time.Now()
	if err := s.store.PutProfile(ctx, p); err != nil {
		s.storeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, profileJSON(user, p))
}
