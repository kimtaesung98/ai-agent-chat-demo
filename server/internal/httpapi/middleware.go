package httpapi

import (
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net/http"
	"time"
)

// withLogging은 요청마다 한 줄을 남긴다: 메서드, 경로, 상태, 소요 시간, 요청 ID.
// 메시지 본문과 비밀값은 기록하지 않는다 (ARCHITECTURE.md §7).
func withLogging(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		log.Info("request",
			"request_id", requestID(),
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
			"client_closed", r.Context().Err() != nil,
		)
	})
}

// withRecover는 처리 중 panic을 500 JSON으로 바꾼다 (이미 응답을 시작했으면 연결만 끝낸다).
func withRecover(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec, _ := w.(*statusRecorder)
		defer func() {
			if v := recover(); v != nil {
				if v == http.ErrAbortHandler {
					panic(v)
				}
				log.Error("unhandled panic", "path", r.URL.Path)
				if rec == nil || !rec.wrote {
					writeError(w, http.StatusInternalServerError, "INTERNAL", "서버 오류가 발생했어요.")
				}
			}
		}()
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
	wrote  bool
}

func (r *statusRecorder) WriteHeader(code int) {
	if !r.wrote {
		r.status, r.wrote = code, true
	}
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	r.wrote = true
	return r.ResponseWriter.Write(b)
}

// Unwrap은 http.ResponseController가 Flush를 원래 ResponseWriter까지 전달하게 한다.
func (r *statusRecorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }

func requestID() string {
	b := make([]byte, 8)
	rand.Read(b)
	return hex.EncodeToString(b)
}
