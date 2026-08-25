package ratelimit

import (
	"context"
	"errors"
	"testing"
	"time"
)

// fakeClock advances virtual time whenever the limiter sleeps.
type fakeClock struct {
	now    time.Time
	sleeps []time.Duration
}

func newTestLimiter(perSecond, perMinute int) (*SlidingWindow, *fakeClock) {
	c := &fakeClock{now: time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)}
	l := New(perSecond, perMinute)
	l.now = func() time.Time { return c.now }
	l.sleep = func(ctx context.Context, d time.Duration) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		c.sleeps = append(c.sleeps, d)
		c.now = c.now.Add(d)
		return nil
	}
	return l, c
}

func TestPerSecondWindow(t *testing.T) {
	l, c := newTestLimiter(3, 60)
	ctx := context.Background()
	for range 3 {
		if err := l.Wait(ctx); err != nil {
			t.Fatal(err)
		}
	}
	if len(c.sleeps) != 0 {
		t.Fatalf("first 3 calls must not sleep, got %v", c.sleeps)
	}
	if err := l.Wait(ctx); err != nil {
		t.Fatal(err)
	}
	if len(c.sleeps) != 1 || c.sleeps[0] != time.Second {
		t.Fatalf("4th call must wait exactly 1s, got %v", c.sleeps)
	}
}

func TestPerMinuteWindow(t *testing.T) {
	l, c := newTestLimiter(3, 60)
	ctx := context.Background()
	start := c.now
	for range 60 {
		if err := l.Wait(ctx); err != nil {
			t.Fatal(err)
		}
	}
	// 60 calls at 3 rps take ~19.67 s of virtual time.
	if err := l.Wait(ctx); err != nil {
		t.Fatal(err)
	}
	if got := c.now.Sub(start); got < time.Minute {
		t.Fatalf("61st call must be delayed to t+60s, got t+%v", got)
	}
}

func TestPenalizeCooldown(t *testing.T) {
	l, c := newTestLimiter(3, 60)
	ctx := context.Background()
	l.Penalize(5 * time.Second)
	if err := l.Wait(ctx); err != nil {
		t.Fatal(err)
	}
	if len(c.sleeps) != 1 || c.sleeps[0] != 5*time.Second {
		t.Fatalf("expected a 5s cooldown sleep, got %v", c.sleeps)
	}
	l.Penalize(10 * time.Minute)
	if err := l.Wait(ctx); err != nil {
		t.Fatal(err)
	}
	if last := c.sleeps[len(c.sleeps)-1]; last != 30*time.Second {
		t.Fatalf("cooldown must be capped at 30s, got %v", last)
	}
}

func TestWaitHonorsContext(t *testing.T) {
	l, _ := newTestLimiter(1, 60)
	ctx, cancel := context.WithCancel(context.Background())
	if err := l.Wait(ctx); err != nil {
		t.Fatal(err)
	}
	cancel()
	if err := l.Wait(ctx); !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context.Canceled, got %v", err)
	}
}

func TestConcurrentWaitersNeverExceedLimit(t *testing.T) {
	l := New(3, 60) // real clock
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	stamps := make(chan time.Time, 9)
	for range 9 {
		go func() {
			if err := l.Wait(ctx); err == nil {
				stamps <- time.Now()
			}
		}()
	}
	var got []time.Time
	for range 9 {
		select {
		case s := <-stamps:
			got = append(got, s)
		case <-ctx.Done():
			t.Fatal("timed out waiting for limiter")
		}
	}
	// Any 1 s window must contain at most 3 stamps.
	for i := range got {
		count := 0
		for j := range got {
			d := got[j].Sub(got[i])
			if d >= 0 && d < time.Second-5*time.Millisecond {
				count++
			}
		}
		if count > 3 {
			t.Fatalf("found %d calls within one second", count)
		}
	}
}
