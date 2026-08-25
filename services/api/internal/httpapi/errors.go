package httpapi

import (
	"context"
	"errors"
	"net/http"

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
	switch {
	case errors.Is(err, errValidation), errors.Is(err, catalog.ErrValidation), errors.Is(err, library.ErrValidation), errors.Is(err, jikan.ErrBadRequest):
		writeError(w, r, http.StatusBadRequest, "validation_error", err.Error())
	case errors.Is(err, anime.ErrNotFound), errors.Is(err, store.ErrNotFound), errors.Is(err, jikan.ErrNotFound):
		writeError(w, r, http.StatusNotFound, "not_found", "resource not found")
	case errors.Is(err, jikan.ErrRateLimited):
		w.Header().Set("Retry-After", "2")
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
