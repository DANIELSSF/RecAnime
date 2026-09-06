package anime

import (
	"io"
	"log/slog"
	"testing"
	"time"
)

// newNegativeCacheService builds a Service exercising only the negative cache, which touches
// neither the store, nor Jikan, nor the cache coordinator.
func newNegativeCacheService(now *time.Time) *Service {
	s := NewService(nil, nil, nil, time.Hour, 0, slog.New(slog.NewTextHandler(io.Discard, nil)))
	s.SetNow(func() time.Time { return *now })
	return s
}

// TestNegativeCacheExpires pins the 404 memory to negativeTTL.
func TestNegativeCacheExpires(t *testing.T) {
	tests := []struct {
		name    string
		elapsed time.Duration
		want    bool
	}{
		{name: "immediately", elapsed: 0, want: true},
		{name: "just before the ttl", elapsed: negativeTTL - time.Second, want: true},
		{name: "at the ttl", elapsed: negativeTTL, want: true},
		{name: "after the ttl", elapsed: negativeTTL + time.Second, want: false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			now := time.Unix(0, 0).UTC()
			s := newNegativeCacheService(&now)
			s.rememberMissing(42)
			now = now.Add(tc.elapsed)
			if got := s.isNegativelyCached(42); got != tc.want {
				t.Fatalf("isNegativelyCached after %v = %v, want %v", tc.elapsed, got, tc.want)
			}
		})
	}
}

// TestNegativeCacheStaysBounded covers the growth guard: a client can ask for unlimited unknown
// ids, so the map must stay capped while still remembering what was just asked for.
func TestNegativeCacheStaysBounded(t *testing.T) {
	const (
		inserted   = maxNegativeEntries + 1
		wantRecent = 400 // the most recent ids that must survive the prune
	)
	tests := []struct {
		name string
		step time.Duration // clock advance between two unknown ids
	}{
		// A burst: nothing has expired yet, so the older half is dropped.
		{name: "burst", step: time.Millisecond},
		// A slow trickle: the entries inserted first have expired and are reclaimed.
		{name: "trickle", step: time.Second},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			now := time.Unix(0, 0).UTC()
			s := newNegativeCacheService(&now)
			for id := range inserted {
				s.rememberMissing(id)
				now = now.Add(tc.step)
			}
			if got := len(s.neg); got > maxNegativeEntries {
				t.Fatalf("negative cache holds %d entries after %d misses, want at most %d", got, inserted, maxNegativeEntries)
			}
			for id := inserted - wantRecent; id < inserted; id++ {
				if !s.isNegativelyCached(id) {
					t.Fatalf("recently missing id %d is no longer negatively cached", id)
				}
			}
			if s.isNegativelyCached(0) {
				t.Fatal("the oldest id survived the prune")
			}
		})
	}
}
