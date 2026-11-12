// Package config는 시작할 때 환경변수를 한 번 읽고 검증한다 (ARCHITECTURE.md §6.3, §7).
package config

import (
	"fmt"
	"strconv"
	"strings"
)

// DefaultModel은 ANTHROPIC_MODEL이 없을 때 쓰는 모델이다.
const DefaultModel = "claude-sonnet-5-5"

// Config는 서버 설정이다. APIKey는 비밀값이라 로그·응답에 쓰지 않는다.
type Config struct {
	Port      int
	APIKey    string
	Model     string
	StaticDir string

	// ElevenLabs Agents 실시간 음성 대화 (F-022, ADR-025). 모두 비밀값이라 로그·응답에 쓰지 않는다.
	ElevenLabsAPIKey  string // 대화 토큰 발급용
	ElevenLabsAgentID string
	ElevenLabsBaseURL string // 비면 https://api.elevenlabs.io (테스트는 가짜 서버)
	LLMSecret         string // ElevenLabs가 Custom LLM(/v1/chat/completions)을 부를 때 보내는 Bearer 값
}

// MinLLMSecret은 ELEVENLABS_LLM_SECRET 최소 길이다.
const MinLLMSecret = 16

// VoiceAgent는 실시간 음성 대화 토큰을 발급할 수 있는지 알려 준다.
func (c Config) VoiceAgent() bool { return c.ElevenLabsAPIKey != "" && c.ElevenLabsAgentID != "" }

// MockMode는 API 키가 없어 모의 제공자를 쓰는지 알려 준다.
func (c Config) MockMode() bool { return c.APIKey == "" }

// Load는 getenv로 설정을 읽는다. 값이 잘못되면 오류를 돌려주고, 호출자는 기동을 멈춘다.
func Load(getenv func(string) string) (Config, error) {
	c := Config{
		Port:      3000,
		APIKey:    strings.TrimSpace(getenv("ANTHROPIC_API_KEY")),
		Model:     strings.TrimSpace(getenv("ANTHROPIC_MODEL")),
		StaticDir: strings.TrimSpace(getenv("STATIC_DIR")),

		ElevenLabsAPIKey:  strings.TrimSpace(getenv("ELEVENLABS_API_KEY")),
		ElevenLabsAgentID: strings.TrimSpace(getenv("ELEVENLABS_AGENT_ID")),
		ElevenLabsBaseURL: strings.TrimSpace(getenv("ELEVENLABS_API_BASE")),
		LLMSecret:         strings.TrimSpace(getenv("ELEVENLABS_LLM_SECRET")),
	}
	if (c.ElevenLabsAPIKey == "") != (c.ElevenLabsAgentID == "") {
		return Config{}, fmt.Errorf("ELEVENLABS_API_KEY와 ELEVENLABS_AGENT_ID는 함께 설정해야 해요")
	}
	if c.LLMSecret != "" && len(c.LLMSecret) < MinLLMSecret {
		return Config{}, fmt.Errorf("ELEVENLABS_LLM_SECRET은 %d자 이상이어야 해요", MinLLMSecret)
	}
	if c.Model == "" {
		c.Model = DefaultModel
	}
	if c.StaticDir == "" {
		c.StaticDir = "./web"
	}
	if p := strings.TrimSpace(getenv("PORT")); p != "" {
		n, err := strconv.Atoi(p)
		if err != nil || n < 1 || n > 65535 {
			return Config{}, fmt.Errorf("PORT는 1~65535 사이 숫자여야 해요 (받은 값: %q)", p)
		}
		c.Port = n
	}
	return c, nil
}
