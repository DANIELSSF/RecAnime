package db

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestPingWithRetry(t *testing.T) {
	boom := errors.New("connection refused")
	delays := []time.Duration{time.Millisecond, time.Millisecond, time.Millisecond}

	t.Run("succeeds after transient failures", func(t *testing.T) {
		calls := 0
		err := pingWithRetry(context.Background(), func(context.Context) error {
			calls++
			if calls < 3 {
				return boom
			}
			return nil
		}, delays)
		if err != nil || calls != 3 {
			t.Fatalf("expected success on the third attempt, got err=%v calls=%d", err, calls)
		}
	})

	t.Run("gives up after the last delay", func(t *testing.T) {
		calls := 0
		err := pingWithRetry(context.Background(), func(context.Context) error {
			calls++
			return boom
		}, delays)
		if !errors.Is(err, boom) || calls != len(delays)+1 {
			t.Fatalf("expected the last error after %d attempts, got err=%v calls=%d", len(delays)+1, err, calls)
		}
	})

	t.Run("stops when the context ends", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		calls := 0
		err := pingWithRetry(ctx, func(context.Context) error {
			calls++
			cancel()
			return boom
		}, delays)
		if !errors.Is(err, context.Canceled) || calls != 1 {
			t.Fatalf("expected an immediate stop, got err=%v calls=%d", err, calls)
		}
	})
}

// TestOpenReturnsPoolWhenUnreachable proves a cold start survives a database outage: the pool is
// usable (pgxpool reconnects on its own) and the caller only learns about it through ErrUnreachable.
func TestOpenReturnsPoolWhenUnreachable(t *testing.T) {
	original := pingDelays
	pingDelays = []time.Duration{time.Millisecond, time.Millisecond}
	t.Cleanup(func() { pingDelays = original })

	// Port 1 refuses connections on every platform the API runs on.
	pool, err := Open(context.Background(), "postgres://user:pass@127.0.0.1:1/recanime?sslmode=disable&connect_timeout=1", 2)
	if pool == nil {
		t.Fatal("Open must return the pool so the process can keep serving")
	}
	defer pool.Close()
	if !errors.Is(err, ErrUnreachable) {
		t.Fatalf("expected ErrUnreachable, got %v", err)
	}
}
