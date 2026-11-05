// chatd는 AI Agent Chat Go 서버의 진입점이다: 설정 → 제공자 → HTTP 조립 (ARCHITECTURE.md §3.2).
//
//	STATIC_DIR=../public go run ./cmd/chatd   # 키가 없으면 모의 모드
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
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/httpapi"
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
		Handler:           httpapi.New(p, cfg.StaticDir, log),
		ReadHeaderTimeout: 10 * time.Second,
		// WriteTimeout은 두지 않는다: SSE 응답이 길어질 수 있음
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	errc := make(chan error, 1)
	go func() { errc <- srv.ListenAndServe() }()

	log.Info(describeMode(p), "provider", p.Name(), "model", p.Model()) // 키는 기록하지 않음
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

// describeMode는 시작 로그 문구다 (SPEC.md F-001 AC4, Node src/server/mode.js와 같음).
func describeMode(p provider.Provider) string {
	if p.Name() == "mock" {
		return "모드: 모의(mock) — ANTHROPIC_API_KEY가 없어 모의 응답을 사용합니다"
	}
	return "모드: Claude — 모델 " + p.Model()
}
