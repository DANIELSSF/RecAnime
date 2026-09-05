package httpapi

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/danielssf/recanime/services/api/internal/testutil"
)

// TestReadyzThrottlesDatabaseChecks: the keep-alive cron and the Cloud Run probe hit /readyz
// continuously; one SELECT per request would eat the (tiny) pool.
func TestReadyzThrottlesDatabaseChecks(t *testing.T) {
	pool := testutil.TestPool(t)
	s := New(Deps{Logger: slog.New(slog.NewTextHandler(io.Discard, nil)), Pool: pool, Version: "test"})
	srv := httptest.NewServer(s)
	t.Cleanup(srv.Close)

	for range 3 {
		req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, srv.URL+"/readyz", nil)
		if err != nil {
			t.Fatal(err)
		}
		res, err := srv.Client().Do(req)
		if err != nil {
			t.Fatal(err)
		}
		_, _ = io.Copy(io.Discard, res.Body)
		_ = res.Body.Close()
		if res.StatusCode != http.StatusOK {
			t.Fatalf("readyz = %d, want 200", res.StatusCode)
		}
	}
	s.ready.mu.Lock()
	defer s.ready.mu.Unlock()
	if s.ready.queries != 1 {
		t.Fatalf("three immediate probes must share one database round trip, got %d", s.ready.queries)
	}
}

// TestReadyzProbesAgainAfterWindow proves the cache actually expires: calls inside readyWindow
// share one probe, and a call after the window runs a new one. databaseReady takes the "now" it
// judges freshness against as a parameter, so the window can be exercised deterministically
// without an actual sleep.
func TestReadyzProbesAgainAfterWindow(t *testing.T) {
	pool := testutil.TestPool(t)
	s := New(Deps{Logger: slog.New(slog.NewTextHandler(io.Discard, nil)), Pool: pool, Version: "test"})
	ctx := context.Background()
	base := time.Now()

	if !s.databaseReady(ctx, base) {
		t.Fatal("expected the database to be ready")
	}
	if !s.databaseReady(ctx, base.Add(500*time.Millisecond)) {
		t.Fatal("expected the database to be ready")
	}
	s.ready.mu.Lock()
	queries := s.ready.queries
	s.ready.mu.Unlock()
	if queries != 1 {
		t.Fatalf("two calls inside the window must share one probe, got %d", queries)
	}

	if !s.databaseReady(ctx, base.Add(1100*time.Millisecond)) {
		t.Fatal("expected the database to be ready")
	}
	s.ready.mu.Lock()
	queries = s.ready.queries
	s.ready.mu.Unlock()
	if queries != 2 {
		t.Fatalf("a call past the window must run a new probe, got %d", queries)
	}
}
