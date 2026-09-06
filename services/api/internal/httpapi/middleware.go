package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log/slog"
	"net/http"
	"regexp"
	"runtime/debug"
	"time"

	"github.com/go-chi/chi/v5/middleware"
)

// requestIDPattern is the shape a client-supplied X-Request-Id must have to be trusted. The id is
// reflected into the response header, the JSON error envelope and every log line, so anything with
// control characters, quotes or an unbounded length is discarded in favour of a generated one.
var requestIDPattern = regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`)

// requestID replaces chi's middleware.RequestID, which trusts the incoming header verbatim. It
// stores the id under chi's own context key so middleware.GetReqID keeps working downstream.
func requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-Id")
		if !requestIDPattern.MatchString(id) {
			id = newRequestID()
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), middleware.RequestIDKey, id)))
	})
}

// newRequestID returns 32 hex characters; crypto/rand.Read never fails.
func newRequestID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

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
