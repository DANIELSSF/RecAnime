package httpapi

import (
	"context"
	"errors"
	"math"
	"net/http"
	"strconv"

	"github.com/danielssf/recanime/services/api/internal/anime"
	"github.com/danielssf/recanime/services/api/internal/cache"
	"github.com/danielssf/recanime/services/api/internal/catalog"
	"github.com/danielssf/recanime/services/api/internal/jikan"
	"github.com/danielssf/recanime/services/api/internal/library"
	"github.com/danielssf/recanime/services/api/internal/store"
)

// errValidation marks request parsing problems raised by handlers.
var errValidation = errors.New("validation")

// writeServiceError maps domain errors to HTTP responses; anything unknown is a 500.
func (s *Server) writeServiceError(w http.ResponseWriter, r *http.Request, err error) {
	// The request's own deadline (middleware.Timeout) fired: a gateway timeout, not a bug.
	if errors.Is(r.Context().Err(), context.DeadlineExceeded) {
		s.deps.Logger.WarnContext(r.Context(), "request timed out", "path", r.URL.Path, "error", err)
		writeError(w, r, http.StatusGatewayTimeout, "timeout", "request timed out")
		return
	}
	switch {
	case errors.Is(err, errValidation), errors.Is(err, catalog.ErrValidation), errors.Is(err, library.ErrValidation), errors.Is(err, jikan.ErrBadRequest):
		writeError(w, r, http.StatusBadRequest, "validation_error", err.Error())
	case errors.Is(err, anime.ErrNotFound), errors.Is(err, store.ErrNotFound), errors.Is(err, jikan.ErrNotFound):
		writeError(w, r, http.StatusNotFound, "not_found", "resource not found")
	case errors.Is(err, jikan.ErrRateLimited):
		w.Header().Set("Retry-After", strconv.Itoa(retryAfterSeconds(err)))
		writeError(w, r, http.StatusServiceUnavailable, "upstream_rate_limited", "MyAnimeList is rate limiting requests, try again shortly")
	case errors.Is(err, jikan.ErrUpstream), errors.Is(err, cache.ErrUpstreamTimeout):
		writeError(w, r, http.StatusBadGateway, "upstream_unavailable", "MyAnimeList data is temporarily unavailable")
	case errors.Is(err, context.Canceled):
		// Client went away; nothing useful to write.
		writeError(w, r, 499, "client_closed", "request cancelled")
	default:
		s.deps.Logger.ErrorContext(r.Context(), "internal error", "error", err, "path", r.URL.Path)
		writeError(w, r, http.StatusInternalServerError, "internal", "internal error")
	}
}

// Retry-After bounds: the limiter's own cooldown never exceeds 30 s.
const (
	retryAfterDefault = 2
	retryAfterMin     = 1
	retryAfterMax     = 30
)

// retryAfterSeconds mirrors upstream's Retry-After when Jikan sent one.
func retryAfterSeconds(err error) int {
	var je *jikan.Error
	if !errors.As(err, &je) || je.RetryAfter <= 0 {
		return retryAfterDefault
	}
	secs := int(math.Ceil(je.RetryAfter.Seconds()))
	return min(max(secs, retryAfterMin), retryAfterMax)
}

// upstreamErrorToken classifies an upstream failure for meta.upstreamError. Raw error strings
// leak internals (URLs, driver messages), so clients get a stable token instead.
func upstreamErrorToken(err error) string {
	switch {
	case err == nil:
		return ""
	case errors.Is(err, jikan.ErrRateLimited):
		return "rate_limited"
	case errors.Is(err, cache.ErrUpstreamTimeout), errors.Is(err, context.DeadlineExceeded):
		return "timeout"
	case errors.Is(err, jikan.ErrUpstream):
		return "upstream_unavailable"
	case errors.Is(err, jikan.ErrNotFound), errors.Is(err, anime.ErrNotFound), errors.Is(err, store.ErrNotFound):
		return "not_found"
	default:
		return "error"
	}
}
