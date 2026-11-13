// Package openai는 OpenAI Realtime API 어댑터다 (F-024, ARCHITECTURE.md ADR-026).
// 지금은 브라우저가 WebRTC로 붙을 때 쓰는 임시 키(ephemeral client secret) 발급만 한다. 표준 라이브러리만 쓴다.
// API 키는 이 패키지 밖으로 나가지 않고 로그·오류에도 쓰지 않는다 — 앱은 짧게 쓰는 임시 키만 받는다.
package openai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// 기본값. 환경변수로 바꿀 수 있다 (ARCHITECTURE.md §6.3).
const (
	DefaultBaseURL         = "https://api.openai.com"
	DefaultModel           = "gpt-realtime"
	DefaultVoice           = "marin"
	DefaultTranscribeModel = "gpt-4o-transcribe"
	// SecretTTL은 임시 키 유효 시간(초)이다. 키로 연결을 연 뒤에는 대화가 이어져도 된다.
	SecretTTL = 600
)

// Client는 임시 키를 발급받는다.
type Client struct {
	APIKey          string
	Model           string
	Voice           string
	TranscribeModel string
	BaseURL         string
	HTTP            *http.Client
}

// New는 Client를 만든다. 빈 값은 기본값.
func New(apiKey, model, voice, transcribeModel, baseURL string) *Client {
	or := func(v, d string) string {
		if v == "" {
			return d
		}
		return v
	}
	return &Client{
		APIKey:          apiKey,
		Model:           or(model, DefaultModel),
		Voice:           or(voice, DefaultVoice),
		TranscribeModel: or(transcribeModel, DefaultTranscribeModel),
		BaseURL:         strings.TrimRight(or(baseURL, DefaultBaseURL), "/"),
		HTTP:            &http.Client{Timeout: 10 * time.Second},
	}
}

// Secret은 브라우저에 넘길 임시 키다.
type Secret struct {
	Value     string
	ExpiresAt int64 // Unix 초
	Model     string
}

// ErrUpstream은 OpenAI가 임시 키를 주지 않은 경우다. Status는 업스트림 HTTP 상태(연결 실패면 0).
type ErrUpstream struct{ Status int }

func (e *ErrUpstream) Error() string { return fmt.Sprintf("openai: upstream status %d", e.Status) }

// sessionBody는 POST /v1/realtime/client_secrets 본문이다.
// 지시문·목소리·말 끝 판단·입력 전사를 세션에 고정해 브라우저가 바꿀 필요가 없게 한다.
func (c *Client) sessionBody(instructions string) map[string]any {
	return map[string]any{
		"expires_after": map[string]any{"anchor": "created_at", "seconds": SecretTTL},
		"session": map[string]any{
			"type":         "realtime",
			"model":        c.Model,
			"instructions": instructions,
			"audio": map[string]any{
				"input": map[string]any{
					"transcription":   map[string]any{"model": c.TranscribeModel, "language": "ko"},
					"noise_reduction": map[string]any{"type": "near_field"},
					// 어르신은 말 사이에 쉬는 일이 많아 말 끝을 서두르지 않는다
					"turn_detection": map[string]any{"type": "semantic_vad", "eagerness": "low", "interrupt_response": true, "create_response": true},
				},
				"output": map[string]any{"voice": c.Voice},
			},
		},
	}
}

// ClientSecret은 지시문을 담은 Realtime 세션용 임시 키를 받는다.
func (c *Client) ClientSecret(ctx context.Context, instructions string) (Secret, error) {
	b, _ := json.Marshal(c.sessionBody(instructions))
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL+"/v1/realtime/client_secrets", bytes.NewReader(b))
	if err != nil {
		return Secret{}, &ErrUpstream{}
	}
	req.Header.Set("Authorization", "Bearer "+c.APIKey)
	req.Header.Set("Content-Type", "application/json")
	res, err := c.HTTP.Do(req)
	if err != nil {
		return Secret{}, &ErrUpstream{} // 원문(주소·키)이 섞일 수 있어 감싸지 않는다
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 256<<10))
	if res.StatusCode != http.StatusOK {
		return Secret{}, &ErrUpstream{Status: res.StatusCode}
	}
	var out struct {
		Value     string `json:"value"`
		ExpiresAt int64  `json:"expires_at"`
		Session   struct {
			Model string `json:"model"`
		} `json:"session"`
	}
	if json.Unmarshal(body, &out) != nil || out.Value == "" {
		return Secret{}, &ErrUpstream{Status: res.StatusCode}
	}
	model := out.Session.Model
	if model == "" {
		model = c.Model
	}
	return Secret{Value: out.Value, ExpiresAt: out.ExpiresAt, Model: model}, nil
}
