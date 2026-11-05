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
}

// MockMode는 API 키가 없어 모의 제공자를 쓰는지 알려 준다.
func (c Config) MockMode() bool { return c.APIKey == "" }

// Load는 getenv로 설정을 읽는다. 값이 잘못되면 오류를 돌려주고, 호출자는 기동을 멈춘다.
func Load(getenv func(string) string) (Config, error) {
	c := Config{
		Port:      3000,
		APIKey:    strings.TrimSpace(getenv("ANTHROPIC_API_KEY")),
		Model:     strings.TrimSpace(getenv("ANTHROPIC_MODEL")),
		StaticDir: strings.TrimSpace(getenv("STATIC_DIR")),
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
