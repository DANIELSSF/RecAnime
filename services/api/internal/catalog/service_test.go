package catalog

import (
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/danielssf/recanime/services/api/internal/jikan"
)

// TestLiveCacheEviction covers the only unbounded map in the process: `page` is client-controlled,
// so the live-feed micro-cache must drop what the debounce can no longer serve.
func TestLiveCacheEviction(t *testing.T) {
	const debounce = 30 * time.Second
	s := NewService(nil, nil, nil, time.Hour, time.Hour, debounce, slog.New(slog.NewTextHandler(io.Discard, nil)))
	now := time.Date(2026, 9, 5, 12, 0, 0, 0, time.UTC)
	s.SetNow(func() time.Time { return now })
	res := &jikan.Response[[]jikan.Recommendation]{}

	t.Run("drops entries older than ten debounce windows", func(t *testing.T) {
		s.rememberLive(1, res)
		now = now.Add(11 * debounce)
		s.rememberLive(2, res)
		if len(s.live) != 1 {
			t.Fatalf("expected only the fresh page, got %d entries", len(s.live))
		}
		if _, ok := s.live[2]; !ok {
			t.Fatal("the page just stored must be kept")
		}
	})

	t.Run("caps the map size", func(t *testing.T) {
		for pg := range liveCacheMax * 2 {
			now = now.Add(time.Second) // every page stays inside the eviction window
			s.rememberLive(pg+10, res)
		}
		if len(s.live) > liveCacheMax {
			t.Fatalf("live cache must stay at %d entries, got %d", liveCacheMax, len(s.live))
		}
		if _, ok := s.live[liveCacheMax*2+9]; !ok {
			t.Fatal("the newest page must survive the eviction")
		}
	})
}
