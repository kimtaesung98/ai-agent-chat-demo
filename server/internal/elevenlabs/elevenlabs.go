// Package elevenlabs는 ElevenLabs Agents API 어댑터다 (F-022, ARCHITECTURE.md ADR-025).
// 지금은 실시간 음성 대화(WebRTC)용 대화 토큰 발급만 한다. 표준 라이브러리만 쓴다.
// API 키는 이 패키지 밖으로 나가지 않고 로그·오류에도 쓰지 않는다 — 앱은 짧게 쓰는 토큰만 받는다.
package elevenlabs

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// DefaultBaseURL은 ElevenLabs API 주소다. 테스트는 가짜 서버 주소를 넣는다.
const DefaultBaseURL = "https://api.elevenlabs.io"

// Client는 대화 토큰을 발급받는다.
type Client struct {
	APIKey  string
	AgentID string
	BaseURL string
	HTTP    *http.Client
}

// New는 Client를 만든다. baseURL이 비면 DefaultBaseURL.
func New(apiKey, agentID, baseURL string) *Client {
	if baseURL == "" {
		baseURL = DefaultBaseURL
	}
	return &Client{
		APIKey:  apiKey,
		AgentID: agentID,
		BaseURL: strings.TrimRight(baseURL, "/"),
		HTTP:    &http.Client{Timeout: 10 * time.Second},
	}
}

// ErrUpstream은 ElevenLabs가 토큰을 주지 않은 경우다. Status는 업스트림 HTTP 상태(연결 실패면 0).
type ErrUpstream struct{ Status int }

func (e *ErrUpstream) Error() string { return fmt.Sprintf("elevenlabs: upstream status %d", e.Status) }

// ConversationToken은 GET /v1/convai/conversation/token?agent_id=… 으로 WebRTC 대화 토큰을 받는다.
func (c *Client) ConversationToken(ctx context.Context) (string, error) {
	u := c.BaseURL + "/v1/convai/conversation/token?agent_id=" + url.QueryEscape(c.AgentID)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return "", &ErrUpstream{}
	}
	req.Header.Set("xi-api-key", c.APIKey)
	res, err := c.HTTP.Do(req)
	if err != nil {
		return "", &ErrUpstream{} // 원문(주소·키)이 섞일 수 있어 감싸지 않는다
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 64<<10))
	if res.StatusCode != http.StatusOK {
		return "", &ErrUpstream{Status: res.StatusCode}
	}
	var out struct {
		Token string `json:"token"`
	}
	if json.Unmarshal(body, &out) != nil || out.Token == "" {
		return "", &ErrUpstream{Status: res.StatusCode}
	}
	return out.Token, nil
}

// IsUpstream은 err가 ErrUpstream인지 알려 준다.
func IsUpstream(err error) bool {
	var e *ErrUpstream
	return errors.As(err, &e)
}
