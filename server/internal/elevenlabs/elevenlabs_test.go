package elevenlabs

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestConversationToken(t *testing.T) {
	t.Run("F-022 AC2 agent_id와 xi-api-key로 토큰을 받는다", func(t *testing.T) {
		var gotKey, gotAgent, gotPath string
		up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			gotKey, gotAgent, gotPath = r.Header.Get("xi-api-key"), r.URL.Query().Get("agent_id"), r.URL.Path
			w.Write([]byte(`{"token":"tok-123","conversation_id":"c1"}`))
		}))
		defer up.Close()
		tok, err := New("test-key", "agent_1", up.URL).ConversationToken(context.Background())
		if err != nil || tok != "tok-123" {
			t.Fatalf("tok=%q err=%v", tok, err)
		}
		if gotKey != "test-key" || gotAgent != "agent_1" || gotPath != "/v1/convai/conversation/token" {
			t.Fatalf("key=%q agent=%q path=%q", gotKey, gotAgent, gotPath)
		}
	})

	t.Run("F-022 AC2 업스트림 오류는 상태만 담고 키를 오류 문장에 넣지 않는다", func(t *testing.T) {
		up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, `{"detail":"invalid key test-key"}`, http.StatusUnauthorized)
		}))
		defer up.Close()
		_, err := New("test-key", "agent_1", up.URL).ConversationToken(context.Background())
		if !IsUpstream(err) || strings.Contains(err.Error(), "test-key") {
			t.Fatalf("err=%v", err)
		}
	})

	t.Run("F-022 AC2 연결 실패도 ErrUpstream", func(t *testing.T) {
		_, err := New("k", "a", "http://127.0.0.1:1").ConversationToken(context.Background())
		if !IsUpstream(err) {
			t.Fatalf("err=%v", err)
		}
	})
}
