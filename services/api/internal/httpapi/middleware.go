package httpapi

import (
	"fmt"
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"

	"github.com/go-chi/chi/v5/middleware"
)

// requestLogger emits one structured access-log line per request and echoes the request id,
// so a user can quote it from a failing response.
func requestLogger(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			if id := middleware.GetReqID(r.Context()); id != "" {
				w.Header().Set("X-Request-Id", id)
			}
			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
			next.ServeHTTP(ww, r)
			attrs := []any{
				"method", r.Method,
				"path", r.URL.Path,
				"status", ww.Status(),
				"bytes", ww.BytesWritten(),
				"durationMs", time.Since(start).Milliseconds(),
				"requestId", middleware.GetReqID(r.Context()),
			}
			if cache := ww.Header().Get("X-Cache"); cache != "" {
				attrs = append(attrs, "cache", cache)
			}
			if p := principalFromContext(r.Context()); p != nil {
				attrs = append(attrs, "userId", p.UserID)
			}
			level := slog.LevelInfo
			if ww.Status() >= 500 {
				level = slog.LevelError
			}
			logger.Log(r.Context(), level, "request", attrs...)
		})
	}
}

// recoverPanics replaces chi's Recoverer: it logs one structured line (Cloud Logging cannot
// parse chi's ANSI stack dump) and answers with the JSON error envelope when the handler
// wrote nothing yet.
func recoverPanics(logger *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
			defer func() {
				rec := recover()
				if rec == nil {
					return
				}
				if err, ok := rec.(error); ok && err == http.ErrAbortHandler { //nolint:errorlint // sentinel is compared by identity, as net/http does
					panic(rec)
				}
				logger.ErrorContext(r.Context(), "panic",
					"error", fmt.Sprint(rec),
					"stack", string(debug.Stack()),
					"method", r.Method,
					"path", r.URL.Path,
					"requestId", middleware.GetReqID(r.Context()))
				if ww.Status() == 0 {
					writeError(ww, r, http.StatusInternalServerError, "internal", "internal error")
				}
			}()
			next.ServeHTTP(ww, r)
		})
	}
}

// maxBodyBytes caps request bodies; the API only receives tiny JSON documents.
func maxBodyBytes(limit int64) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.Body != nil {
				r.Body = http.MaxBytesReader(w, r.Body, limit)
			}
			next.ServeHTTP(w, r)
		})
	}
}
