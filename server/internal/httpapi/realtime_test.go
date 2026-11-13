package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"
)

type fakeRealtime struct {
	got *string // 받은 지시문
	err error
}

func (f fakeRealtime) ClientSecret(_ context.Context, instructions string) (RealtimeSecret, error) {
	if f.got != nil {
		*f.got = instructions
	}
	if f.err != nil {
		return RealtimeSecret{}, f.err
	}
	return RealtimeSecret{Value: "ek_비밀", ExpiresAt: 1763030000, Model: "gpt-realtime"}, nil
}

const sessionBody = `{"persona":{"name":"미소","role":"노인복지사","about":"비밀-소개"},
	"memory":[{"summary":"비밀-요약","facts":[],"followUps":[]}],
	"history":[{"role":"user","content":"비밀-본문"},{"role":"assistant","content":"네"}]}`

func TestVoiceSession(t *testing.T) {
	t.Run("F-024 AC2 설정이 없으면 503 VOICE_AGENT_OFF", func(t *testing.T) {
		res, body := do(t, "POST", startWith(t, done(), nil)+"/api/voice/session", "", sessionBody)
		if res.StatusCode != 503 || !strings.Contains(body, "VOICE_AGENT_OFF") || !strings.Contains(body, RealtimeUnavailable) {
			t.Fatalf("%d %s", res.StatusCode, body)
		}
	})

	t.Run("F-024 AC2 켜져 있으면 지시문을 담아 임시 키만 주고, API-002 voiceAgent는 openai", func(t *testing.T) {
		var log bytes.Buffer
		var got string
		url := startWith(t, done(), &log, WithRealtime(fakeRealtime{got: &got}), WithVoiceAgent(fakeTokens{tok: "t"}))
		res, body := do(t, "POST", url+"/api/voice/session", "", sessionBody)
		var out map[string]any
		json.Unmarshal([]byte(body), &out)
		if res.StatusCode != 200 || out["clientSecret"] != "ek_비밀" || out["expiresAt"].(float64) != 1763030000 || out["model"] != "gpt-realtime" ||
			len(out) != 3 || res.Header.Get("Cache-Control") != "no-store" {
			t.Fatalf("%d %s", res.StatusCode, body)
		}
		for _, s := range []string{"미소", "노인복지사", "비밀-요약", "비밀-본문", "음성 대화"} {
			if !strings.Contains(got, s) {
				t.Fatalf("지시문에 %q가 없어요: %s", s, got)
			}
		}
		_, cfg := do(t, "GET", url+"/api/config", "", "")
		if !strings.Contains(cfg, `"voiceAgent":"openai"`) {
			t.Fatalf("config = %s", cfg)
		}
		time.Sleep(30 * time.Millisecond)
		for _, s := range []string{"ek_비밀", "비밀-소개", "비밀-요약", "비밀-본문"} {
			if strings.Contains(log.String(), s) {
				t.Fatalf("%q가 로그에 남았어요", s)
			}
		}
		if res, _ := do(t, "GET", url+"/api/voice/session", "", ""); res.StatusCode != 405 {
			t.Fatalf("GET → %d", res.StatusCode)
		}
	})

	t.Run("F-024 AC3 형식 오류는 API-001과 같은 400", func(t *testing.T) {
		url := startWith(t, done(), nil, WithRealtime(fakeRealtime{}))
		for body, code := range map[string]string{`nope`: "INVALID_JSON", `{"history":[{"role":"x","content":"a"}]}`: "INVALID_INPUT", `{"persona":{"name":""}}`: "INVALID_INPUT"} {
			if res, b := do(t, "POST", url+"/api/voice/session", "", body); res.StatusCode != 400 || !strings.Contains(b, code) {
				t.Fatalf("%s → %d %s", body, res.StatusCode, b)
			}
		}
	})

	t.Run("F-024 AC2 업스트림 실패는 502와 사용자용 문장, 원문은 숨긴다", func(t *testing.T) {
		url := startWith(t, done(), nil, WithRealtime(fakeRealtime{err: errors.New("sk-원문")}))
		res, body := do(t, "POST", url+"/api/voice/session", "", `{}`)
		if res.StatusCode != 502 || strings.Contains(body, "sk-") || !strings.Contains(body, "VOICE_AGENT_ERROR") {
			t.Fatalf("%d %s", res.StatusCode, body)
		}
	})
}
