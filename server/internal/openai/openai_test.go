package openai

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

const fakeKey = "sk-test-fake-openai-key"

// fakeOpenAI는 임시 키 발급만 흉내 낸다. 받은 본문을 got에 남긴다.
func fakeOpenAI(t *testing.T, status int, reply string, got *map[string]any) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/v1/realtime/client_secrets" || r.Header.Get("Authorization") != "Bearer "+fakeKey {
			w.WriteHeader(http.StatusUnauthorized)
			return
		}
		b, _ := io.ReadAll(r.Body)
		if got != nil {
			json.Unmarshal(b, got)
		}
		w.WriteHeader(status)
		io.WriteString(w, reply)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func TestClientSecret(t *testing.T) {
	t.Run("F-024 AC2 지시문·모델·목소리·전사를 세션에 담고 임시 키만 돌려준다", func(t *testing.T) {
		var got map[string]any
		srv := fakeOpenAI(t, 200, `{"value":"ek_test","expires_at":1763030000,"session":{"model":"gpt-realtime"}}`, &got)
		s, err := New(fakeKey, "", "", "", srv.URL).ClientSecret(context.Background(), "당신은 미소예요")
		if err != nil {
			t.Fatal(err)
		}
		if s.Value != "ek_test" || s.ExpiresAt != 1763030000 || s.Model != "gpt-realtime" {
			t.Fatalf("%+v", s)
		}
		sess := got["session"].(map[string]any)
		audio := sess["audio"].(map[string]any)
		if sess["type"] != "realtime" || sess["model"] != DefaultModel || sess["instructions"] != "당신은 미소예요" ||
			audio["output"].(map[string]any)["voice"] != DefaultVoice ||
			audio["input"].(map[string]any)["transcription"].(map[string]any)["language"] != "ko" {
			t.Fatalf("%v", got)
		}
		if got["expires_after"].(map[string]any)["seconds"].(float64) != SecretTTL {
			t.Fatalf("%v", got["expires_after"])
		}
	})

	t.Run("F-024 AC2 업스트림 오류는 상태만 담고 키를 오류에 넣지 않는다", func(t *testing.T) {
		for _, c := range []struct {
			status int
			reply  string
		}{{500, `{"error":"x"}`}, {200, `{"value":""}`}, {200, `nope`}} {
			srv := fakeOpenAI(t, c.status, c.reply, nil)
			_, err := New(fakeKey, "", "", "", srv.URL).ClientSecret(context.Background(), "x")
			if err == nil || strings.Contains(err.Error(), fakeKey) {
				t.Fatalf("%d %s → %v", c.status, c.reply, err)
			}
		}
		_, err := New(fakeKey, "", "", "", "http://127.0.0.1:1").ClientSecret(context.Background(), "x")
		if err == nil || strings.Contains(err.Error(), fakeKey) || strings.Contains(err.Error(), "127.0.0.1") {
			t.Fatal(err)
		}
	})
}
