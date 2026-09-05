package httpapi

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/danielssf/recanime/services/api/internal/anime"
	"github.com/danielssf/recanime/services/api/internal/cache"
	"github.com/danielssf/recanime/services/api/internal/jikan"
	"github.com/danielssf/recanime/services/api/internal/store"
)

// TestMetaForUpstreamErrorTokens covers the class tokens meta.upstreamError may carry: raw error
// strings leak internals (URLs, driver messages), so clients only ever see one of these.
func TestMetaForUpstreamErrorTokens(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want string
	}{
		{"rate limited", jikan.ErrRateLimited, "rate_limited"},
		{"upstream unavailable", jikan.ErrUpstream, "upstream_unavailable"},
		{"cache fetch timeout", cache.ErrUpstreamTimeout, "timeout"},
		{"request deadline exceeded", context.DeadlineExceeded, "timeout"},
		{"jikan not found", jikan.ErrNotFound, "not_found"},
		{"anime not found", anime.ErrNotFound, "not_found"},
		{"store not found", store.ErrNotFound, "not_found"},
		{"anything else", errors.New("boom"), "error"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := metaFor(cache.Stale, time.Time{}, tc.err)
			if m.UpstreamError == nil || *m.UpstreamError != tc.want {
				got := "<nil>"
				if m.UpstreamError != nil {
					got = *m.UpstreamError
				}
				t.Fatalf("upstreamError = %s, want %s", got, tc.want)
			}
		})
	}

	// No error at all: meta must carry no upstreamError token.
	if m := metaFor(cache.Hit, time.Time{}, nil); m.UpstreamError != nil {
		t.Fatalf("a successful result must not carry an upstreamError token, got %v", *m.UpstreamError)
	}
}

// TestRetryAfterSecondsClamping covers the Retry-After bounds: unknown defaults to 2, a short
// cooldown is echoed as-is, a long one clamps to 30, and a sub-second one rounds up to 1.
func TestRetryAfterSecondsClamping(t *testing.T) {
	cases := []struct {
		name       string
		retryAfter time.Duration
		want       int
	}{
		{"unknown defaults to 2", 0, 2},
		{"seven seconds is echoed", 7 * time.Second, 7},
		{"ninety seconds clamps to 30", 90 * time.Second, 30},
		{"four hundred milliseconds rounds up to 1", 400 * time.Millisecond, 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := &jikan.Error{Status: http.StatusTooManyRequests, RetryAfter: tc.retryAfter}
			if got := retryAfterSeconds(err); got != tc.want {
				t.Fatalf("retryAfterSeconds(%v) = %d, want %d", tc.retryAfter, got, tc.want)
			}
		})
	}

	// No *jikan.Error in the chain at all: same default as an unknown RetryAfter.
	if got := retryAfterSeconds(errors.New("plain")); got != 2 {
		t.Fatalf("retryAfterSeconds with no jikan.Error = %d, want 2", got)
	}
}

// TestWriteServiceErrorRetryAfterHeader drives writeServiceError itself (not just the helper) for
// the rate-limited branch, using errors.Join so the error both `errors.Is`-matches
// jikan.ErrRateLimited (the switch's dispatch key) and `errors.As`-extracts the *jikan.Error the
// header clamp reads (jikan.Error.kind is unexported, so it cannot be built from this package).
func TestWriteServiceErrorRetryAfterHeader(t *testing.T) {
	cases := []struct {
		name       string
		retryAfter time.Duration
		want       string
	}{
		{"unknown defaults to 2", 0, "2"},
		{"seven seconds is echoed", 7 * time.Second, "7"},
		{"ninety seconds clamps to 30", 90 * time.Second, "30"},
		{"four hundred milliseconds rounds up to 1", 400 * time.Millisecond, "1"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := testServer()
			je := &jikan.Error{Status: http.StatusTooManyRequests, RetryAfter: tc.retryAfter}
			err := errors.Join(jikan.ErrRateLimited, je)

			w := httptest.NewRecorder()
			req, reqErr := http.NewRequestWithContext(context.Background(), http.MethodGet, "http://example.com/x", nil)
			if reqErr != nil {
				t.Fatal(reqErr)
			}
			s.writeServiceError(w, req, err)

			if w.Code != http.StatusServiceUnavailable {
				t.Fatalf("status = %d, want 503", w.Code)
			}
			if got := w.Header().Get("Retry-After"); got != tc.want {
				t.Fatalf("Retry-After = %q, want %q", got, tc.want)
			}
		})
	}
}

// TestRecoverPanicsRepanicsAbortHandler: http.ErrAbortHandler tells net/http to close the
// connection silently (used to abandon a hijacked or half-written response); recoverPanics must
// let it keep unwinding instead of turning it into a 500.
func TestRecoverPanicsRepanicsAbortHandler(t *testing.T) {
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	h := recoverPanics(logger)(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		panic(http.ErrAbortHandler)
	}))

	rec := httptest.NewRecorder()
	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, "http://example.com/boom", nil)
	if err != nil {
		t.Fatal(err)
	}

	func() {
		defer func() {
			r := recover()
			if r == nil {
				t.Fatal("expected recoverPanics to re-panic, but it did not panic at all")
			}
			if r != http.ErrAbortHandler { //nolint:errorlint // identity match, like net/http itself
				t.Fatalf("expected a re-panic with http.ErrAbortHandler, got %v", r)
			}
		}()
		h.ServeHTTP(rec, req)
	}()

	if rec.Code != 200 {
		t.Fatalf("nothing should have been written to the response, got status %d", rec.Code)
	}
}
