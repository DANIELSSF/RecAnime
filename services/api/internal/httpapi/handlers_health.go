package httpapi

import (
	"context"
	"net/http"
	"time"
)

type healthBody struct {
	Status  string `json:"status"`
	Version string `json:"version"`
}

// handleHealthz answers liveness without touching the database.
func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, healthBody{Status: "ok", Version: s.deps.Version})
}

// handleReadyz answers readiness with a cheap database round trip. The keep-alive cron hits
// this endpoint so the Supabase free project keeps seeing database activity.
func (s *Server) handleReadyz(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	var one int
	if err := s.deps.Pool.QueryRow(ctx, "SELECT 1").Scan(&one); err != nil {
		s.deps.Logger.WarnContext(ctx, "readiness probe failed", "error", err)
		writeJSON(w, http.StatusServiceUnavailable, healthBody{Status: "database unavailable", Version: s.deps.Version})
		return
	}
	writeJSON(w, http.StatusOK, healthBody{Status: "ok", Version: s.deps.Version})
}
