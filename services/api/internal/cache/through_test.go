package cache

import (
	"context"
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

var errUpstream = errors.New("upstream down")

type mem struct {
	mu        sync.Mutex
	value     string
	fetchedAt time.Time
	found     bool
	writes    int
}

func (m *mem) read(context.Context) (string, time.Time, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.value, m.fetchedAt, m.found, nil
}

func (m *mem) write(_ context.Context, v string, at time.Time) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.value, m.fetchedAt, m.found, m.writes = v, at, true, m.writes+1
	return nil
}

func newCoord() (*Coordinator, *time.Time) {
	now := time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)
	c := NewCoordinator(func(err error) bool { return errors.Is(err, errUpstream) })
	c.now = func() time.Time { return now }
	return c, &now
}

func TestMissThenHitThenExpiry(t *testing.T) {
	c, now := newCoord()
	m := &mem{}
	var fetches atomic.Int32
	fetch := func(context.Context) (string, error) { fetches.Add(1); return "v1", nil }
	ctx := context.Background()

	r, err := Through(ctx, c, "k", 12*time.Hour, m.read, fetch, m.write)
	if err != nil || r.Status != Miss || r.Value != "v1" || fetches.Load() != 1 {
		t.Fatalf("first call: %+v err=%v fetches=%d", r, err, fetches.Load())
	}
	r, err = Through(ctx, c, "k", 12*time.Hour, m.read, fetch, m.write)
	if err != nil || r.Status != Hit || fetches.Load() != 1 {
		t.Fatalf("second call must be HIT without fetch: %+v err=%v fetches=%d", r, err, fetches.Load())
	}
	*now = now.Add(13 * time.Hour)
	r, err = Through(ctx, c, "k", 12*time.Hour, m.read, fetch, m.write)
	if err != nil || r.Status != Miss || fetches.Load() != 2 || m.writes != 2 {
		t.Fatalf("after expiry must refetch: %+v err=%v fetches=%d writes=%d", r, err, fetches.Load(), m.writes)
	}
}

func TestStaleOnUpstreamError(t *testing.T) {
	c, now := newCoord()
	m := &mem{value: "old", fetchedAt: now.Add(-20 * time.Hour), found: true}
	fetch := func(context.Context) (string, error) { return "", errUpstream }
	r, err := Through(context.Background(), c, "k", 12*time.Hour, m.read, fetch, m.write)
	if err != nil || r.Status != Stale || r.Value != "old" || !errors.Is(r.UpstreamErr, errUpstream) {
		t.Fatalf("expected STALE with old value, got %+v err=%v", r, err)
	}
}

func TestErrorWithoutStaleCopy(t *testing.T) {
	c, _ := newCoord()
	m := &mem{}
	fetch := func(context.Context) (string, error) { return "", errUpstream }
	if _, err := Through(context.Background(), c, "k", 12*time.Hour, m.read, fetch, m.write); !errors.Is(err, errUpstream) {
		t.Fatalf("expected upstream error, got %v", err)
	}
}

func TestNonStaleableErrorIsReturned(t *testing.T) {
	c, now := newCoord()
	m := &mem{value: "old", fetchedAt: now.Add(-20 * time.Hour), found: true}
	notFound := errors.New("not found")
	fetch := func(context.Context) (string, error) { return "", notFound }
	if _, err := Through(context.Background(), c, "k", 12*time.Hour, m.read, fetch, m.write); !errors.Is(err, notFound) {
		t.Fatalf("expected not found error, got %v", err)
	}
}

func TestConcurrentMissesShareOneFetch(t *testing.T) {
	c, _ := newCoord()
	m := &mem{}
	var fetches atomic.Int32
	release := make(chan struct{})
	fetch := func(context.Context) (string, error) {
		fetches.Add(1)
		<-release
		return "v", nil
	}
	var wg sync.WaitGroup
	results := make([]Status, 50)
	for i := range 50 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r, err := Through(context.Background(), c, "same", time.Hour, m.read, fetch, m.write)
			if err != nil {
				t.Error(err)
				return
			}
			results[i] = r.Status
		}()
	}
	time.Sleep(50 * time.Millisecond)
	close(release)
	wg.Wait()
	if fetches.Load() != 1 {
		t.Fatalf("expected exactly one upstream fetch, got %d", fetches.Load())
	}
	for _, s := range results {
		if s != Miss {
			t.Fatalf("shared flight must report MISS, got %q", s)
		}
	}
}

func TestClientCancelDoesNotKillSharedFlight(t *testing.T) {
	c, _ := newCoord()
	m := &mem{}
	fetch := func(ctx context.Context) (string, error) {
		select {
		case <-ctx.Done():
			return "", ctx.Err()
		case <-time.After(30 * time.Millisecond):
			return "v", nil
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel() // already cancelled client
	r, err := Through(ctx, c, "k", time.Hour, m.read, fetch, m.write)
	if err != nil || r.Status != Miss {
		t.Fatalf("flight must run detached from the client context: %+v err=%v", r, err)
	}
}
