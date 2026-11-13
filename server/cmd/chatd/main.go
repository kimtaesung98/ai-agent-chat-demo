// chatd는 AI Agent Chat Go 서버의 진입점이다: 설정 → 제공자 → HTTP 조립 (ARCHITECTURE.md §3.2).
//
//	STATIC_DIR=../app/build/web go run ./cmd/chatd   # 키가 없으면 모의 모드
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/config"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/elevenlabs"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/httpapi"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/openai"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider/anthropic"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/provider/mock"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(log); err != nil {
		log.Error("서버를 시작할 수 없어요", "error", err.Error())
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	cfg, err := config.Load(os.Getenv)
	if err != nil {
		return err
	}
	p, err := newProvider(cfg)
	if err != nil {
		return err
	}

	srv := &http.Server{
		Addr:              fmt.Sprintf(":%d", cfg.Port),
		Handler:           httpapi.New(p, cfg.StaticDir, log, voiceOptions(cfg)...),
		ReadHeaderTimeout: 10 * time.Second,
		// WriteTimeout은 두지 않는다: SSE 응답이 길어질 수 있음
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	errc := make(chan error, 1)
	go func() { errc <- srv.ListenAndServe() }()

	log.Info(describeMode(p), "provider", p.Name(), "model", p.Model()) // 키는 기록하지 않음
	log.Info(describeVoice(cfg))                                        // 키·비밀값은 기록하지 않음
	log.Info(fmt.Sprintf("AI Agent Chat → http://localhost:%d", cfg.Port), "static_dir", cfg.StaticDir)

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdown); err != nil && !errors.Is(err, context.DeadlineExceeded) {
		return err
	}
	return nil
}

func newProvider(cfg config.Config) (provider.Provider, error) {
	if cfg.MockMode() {
		return mock.New(), nil
	}
	return anthropic.New(anthropic.Options{APIKey: cfg.APIKey, Model: cfg.Model})
}

// describeMode는 시작 로그 문구다 (SPEC.md F-001 AC4).
func describeMode(p provider.Provider) string {
	if p.Name() == "mock" {
		return "모드: 모의(mock) — ANTHROPIC_API_KEY가 없어 모의 응답을 사용합니다"
	}
	return "모드: Claude — 모델 " + p.Model()
}

// voiceOptions는 ElevenLabs 실시간 음성 대화를 켠다 (F-022, ADR-025).
func voiceOptions(cfg config.Config) []httpapi.Option {
	var opts []httpapi.Option
	if cfg.VoiceAgent() {
		opts = append(opts, httpapi.WithVoiceAgent(elevenlabs.New(cfg.ElevenLabsAPIKey, cfg.ElevenLabsAgentID, cfg.ElevenLabsBaseURL)))
	}
	if cfg.LLMSecret != "" {
		opts = append(opts, httpapi.WithLLMSecret(cfg.LLMSecret))
	}
	if cfg.Realtime() {
		c := openai.New(cfg.OpenAIAPIKey, cfg.OpenAIRealtimeModel, cfg.OpenAIRealtimeVoice, cfg.OpenAITranscribeModel, cfg.OpenAIBaseURL)
		opts = append(opts, httpapi.WithRealtime(realtimeAdapter{c}))
	}
	return opts
}

// realtimeAdapter는 internal/openai를 httpapi.RealtimeSessions에 맞춘다 (두 패키지는 서로 모른다).
type realtimeAdapter struct{ c *openai.Client }

func (a realtimeAdapter) ClientSecret(ctx context.Context, instructions string) (httpapi.RealtimeSecret, error) {
	s, err := a.c.ClientSecret(ctx, instructions)
	return httpapi.RealtimeSecret{Value: s.Value, ExpiresAt: s.ExpiresAt, Model: s.Model}, err
}

func describeVoice(cfg config.Config) string {
	switch {
	case cfg.Realtime():
		return "실시간 음성: OpenAI Realtime 켜짐 (POST /api/voice/session 임시 키 발급, 모델 " + orDefault(cfg.OpenAIRealtimeModel, openai.DefaultModel) + ")"
	case cfg.VoiceAgent() && cfg.LLMSecret != "":
		return "실시간 음성: ElevenLabs Agents 켜짐 (토큰 발급 + Custom LLM /v1/chat/completions)"
	case cfg.VoiceAgent():
		return "실시간 음성: ElevenLabs 토큰 발급만 켜짐 — ELEVENLABS_LLM_SECRET이 없어 Custom LLM 엔드포인트는 꺼져 있어요"
	case cfg.LLMSecret != "":
		return "실시간 음성: Custom LLM 엔드포인트만 켜짐 — ELEVENLABS_API_KEY·ELEVENLABS_AGENT_ID가 없어 앱은 기기 음성을 써요"
	}
	return "실시간 음성: 꺼짐 — 앱은 기기 음성(STT·TTS)을 써요"
}

func orDefault(v, d string) string {
	if v == "" {
		return d
	}
	return v
}
