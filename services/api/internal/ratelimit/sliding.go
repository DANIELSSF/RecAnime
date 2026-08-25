// Package ratelimit implements the process-wide Jikan request budget.
//
// Jikan allows 3 requests per second AND 60 per minute. A token bucket would let bursts
// overshoot a window after refills, so this is a sliding-window log: it remembers the
// timestamps of the last N calls per window and never lets more than N through any
// 1 s / 60 s span. A cooldown (Penalize) is applied after upstream 429 responses.
package ratelimit

import (
	"context"
	"sync"
	"time"
)

// SlidingWindow enforces both per-second and per-minute limits for one process.
type SlidingWindow struct {
	mu            sync.Mutex
	perSecond     int
	perMinute     int
	second        []time.Time
	minute        []time.Time
	cooldownUntil time.Time

	// injectable for tests
	now   func() time.Time
	sleep func(ctx context.Context, d time.Duration) error
}

// New creates a limiter allowing perSecond calls per second and perMinute calls per minute.
func New(perSecond, perMinute int) *SlidingWindow {
	if perSecond < 1 {
		perSecond = 1
	}
	if perMinute < 1 {
		perMinute = 1
	}
	return &SlidingWindow{
		perSecond: perSecond,
		perMinute: perMinute,
		now:       time.Now,
		sleep:     sleepCtx,
	}
}

func sleepCtx(ctx context.Context, d time.Duration) error {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-t.C:
		return nil
	}
}

// Wait blocks until a request may be sent, then records it. It returns early only when ctx ends.
func (l *SlidingWindow) Wait(ctx context.Context) error {
	for {
		l.mu.Lock()
		now := l.now()
		l.trim(now)
		earliest := now
		if len(l.second) >= l.perSecond {
			if e := l.second[0].Add(time.Second); e.After(earliest) {
				earliest = e
			}
		}
		if len(l.minute) >= l.perMinute {
			if e := l.minute[0].Add(time.Minute); e.After(earliest) {
				earliest = e
			}
		}
		if l.cooldownUntil.After(earliest) {
			earliest = l.cooldownUntil
		}
		if !earliest.After(now) {
			l.second = append(l.second, now)
			l.minute = append(l.minute, now)
			l.mu.Unlock()
			return nil
		}
		wait := earliest.Sub(now)
		l.mu.Unlock()
		if err := l.sleep(ctx, wait); err != nil {
			return err
		}
	}
}

// Penalize blocks all callers for d (bounded to 30 s) after an upstream 429.
func (l *SlidingWindow) Penalize(d time.Duration) {
	if d <= 0 {
		d = 2 * time.Second
	}
	if d > 30*time.Second {
		d = 30 * time.Second
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	until := l.now().Add(d)
	if until.After(l.cooldownUntil) {
		l.cooldownUntil = until
	}
}

// trim drops timestamps that left their windows. Caller holds the lock.
func (l *SlidingWindow) trim(now time.Time) {
	cut := now.Add(-time.Second)
	i := 0
	for i < len(l.second) && !l.second[i].After(cut) {
		i++
	}
	l.second = l.second[i:]
	cut = now.Add(-time.Minute)
	i = 0
	for i < len(l.minute) && !l.minute[i].After(cut) {
		i++
	}
	l.minute = l.minute[i:]
}
