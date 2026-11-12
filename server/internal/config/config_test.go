package config

import (
	"strings"
	"testing"
)

func env(m map[string]string) func(string) string { return func(k string) string { return m[k] } }

func TestLoad(t *testing.T) {
	t.Run("F-001 AC4 키가 없으면 모의 모드, 기본값 사용", func(t *testing.T) {
		c, err := Load(env(nil))
		if err != nil {
			t.Fatal(err)
		}
		if !c.MockMode() || c.Port != 3000 || c.Model != DefaultModel || c.StaticDir != "./web" {
			t.Fatalf("c = %+v", c)
		}
	})
	t.Run("F-010 환경변수를 읽고 공백을 다듬는다", func(t *testing.T) {
		c, err := Load(env(map[string]string{"ANTHROPIC_API_KEY": " k ", "ANTHROPIC_MODEL": "m", "PORT": "8080", "STATIC_DIR": "../public"}))
		if err != nil {
			t.Fatal(err)
		}
		if c.MockMode() || c.APIKey != "k" || c.Model != "m" || c.Port != 8080 || c.StaticDir != "../public" {
			t.Fatalf("c = %+v", c)
		}
	})
	t.Run("F-010 공백뿐인 키는 모의 모드", func(t *testing.T) {
		c, _ := Load(env(map[string]string{"ANTHROPIC_API_KEY": "  "}))
		if !c.MockMode() {
			t.Fatal("모의 모드여야 해요")
		}
	})
	t.Run("F-010 잘못된 PORT는 기동을 멈추고 키를 오류에 넣지 않는다", func(t *testing.T) {
		for _, p := range []string{"abc", "0", "70000"} {
			_, err := Load(env(map[string]string{"PORT": p, "ANTHROPIC_API_KEY": "secret-value"}))
			if err == nil || strings.Contains(err.Error(), "secret-value") {
				t.Fatalf("PORT=%q err=%v", p, err)
			}
		}
	})
	t.Run("F-022 AC1 ElevenLabs 설정을 읽고, 키와 에이전트 ID가 둘 다 있어야 음성 에이전트를 켠다", func(t *testing.T) {
		c, err := Load(env(map[string]string{"ELEVENLABS_API_KEY": " xi ", "ELEVENLABS_AGENT_ID": "agent_1", "ELEVENLABS_LLM_SECRET": "0123456789abcdef"}))
		if err != nil || !c.VoiceAgent() || c.ElevenLabsAPIKey != "xi" || c.LLMSecret != "0123456789abcdef" {
			t.Fatalf("c=%+v err=%v", c, err)
		}
		if c, _ := Load(env(nil)); c.VoiceAgent() {
			t.Fatal("설정이 없으면 꺼져 있어야 해요")
		}
	})
	t.Run("F-022 AC1 키·에이전트 ID 한쪽만 있거나 짧은 비밀값은 기동을 멈추고 값을 오류에 넣지 않는다", func(t *testing.T) {
		for _, m := range []map[string]string{
			{"ELEVENLABS_API_KEY": "xi-secret"},
			{"ELEVENLABS_AGENT_ID": "agent_1"},
			{"ELEVENLABS_LLM_SECRET": "short-secret"},
		} {
			_, err := Load(env(m))
			if err == nil || strings.Contains(err.Error(), "xi-secret") || strings.Contains(err.Error(), "short-secret") {
				t.Fatalf("%v err=%v", m, err)
			}
		}
	})
}
