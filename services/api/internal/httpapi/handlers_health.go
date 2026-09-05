package httpapi

import (
	"context"
	"net/http"
	"sync"
	"time"
)

type healthBody struct {
	Status  string `json:"status"`
	Version string `json:"version"`
}

// readyWindow bounds how often /readyz touches the database: the keep-alive cron and Cloud Run
// probes hit it continuously, and one connection per request starves the small pool.
const readyWindow = time.Second

// readyState caches the last readiness answer for readyWindow.
type readyState struct {
	mu      sync.Mutex
	checked time.Time
	ok      bool
	queries int // database round trips actually made; asserted in tests
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
	if !s.databaseReady(ctx, time.Now()) {
		writeJSON(w, http.StatusServiceUnavailable, healthBody{Status: "database unavailable", Version: s.deps.Version})
		return
	}
	writeJSON(w, http.StatusOK, healthBody{Status: "ok", Version: s.deps.Version})
}

// databaseReady runs at most one SELECT 1 per readyWindow and shares the answer.
func (s *Server) databaseReady(ctx context.Context, now time.Time) bool {
	st := s.ready
	st.mu.Lock()
	defer st.mu.Unlock()
	if !st.checked.IsZero() && now.Sub(st.checked) < readyWindow {
		return st.ok
	}
	var one int
	err := s.deps.Pool.QueryRow(ctx, "SELECT 1").Scan(&one)
	st.queries++
	st.checked = now
	st.ok = err == nil
	if err != nil {
		s.deps.Logger.WarnContext(ctx, "readiness probe failed", "error", err)
	}
	return st.ok
}
