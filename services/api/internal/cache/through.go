// Package cache implements the read-through policy every Jikan-backed endpoint uses:
// serve from the database while fresh, otherwise fetch once (single-flight), rate limited,
// persist, and fall back to stale data when the upstream fails.
package cache

import (
	"context"
	"errors"
	"time"

	"golang.org/x/sync/singleflight"
)

// Status tells the client how the value was obtained.
type Status string

const (
	Hit   Status = "HIT"   // fresh copy from the database, no upstream call
	Miss  Status = "MISS"  // fetched from Jikan and stored
	Stale Status = "STALE" // upstream failed; an expired copy was served
	Live  Status = "LIVE"  // never cached (recommendations feed)
)

// Result carries the value with its provenance.
type Result[T any] struct {
	Value       T
	FetchedAt   time.Time
	Status      Status
	UpstreamErr error // set when Status == Stale
}

// ReadFn loads the cached value; found=false means nothing is cached.
type ReadFn[T any] func(ctx context.Context) (value T, fetchedAt time.Time, found bool, err error)

// FetchFn calls the upstream API.
type FetchFn[T any] func(ctx context.Context) (T, error)

// WriteFn persists a freshly fetched value.
type WriteFn[T any] func(ctx context.Context, value T, fetchedAt time.Time) error

// Coordinator shares the single-flight group and limiter across all cached endpoints.
type Coordinator struct {
	flights      singleflight.Group
	fetchTimeout time.Duration
	now          func() time.Time
	// ServeStaleOn decides whether an upstream error may be masked by stale data.
	ServeStaleOn func(error) bool
}

// NewCoordinator creates a coordinator; serveStaleOn may be nil (never serve stale).
// Rate limiting happens inside the fetch function (the Jikan client), so retries are covered too.
func NewCoordinator(serveStaleOn func(error) bool) *Coordinator {
	if serveStaleOn == nil {
		serveStaleOn = func(error) bool { return false }
	}
	return &Coordinator{
		fetchTimeout: 20 * time.Second,
		now:          time.Now,
		ServeStaleOn: serveStaleOn,
	}
}

// SetNow overrides the clock (tests).
func (c *Coordinator) SetNow(now func() time.Time) { c.now = now }

// Through applies the policy for key with the given TTL.
func Through[T any](ctx context.Context, c *Coordinator, key string, ttl time.Duration,
	read ReadFn[T], fetch FetchFn[T], write WriteFn[T]) (Result[T], error) {
	value, fetchedAt, found, err := read(ctx)
	if err != nil {
		return Result[T]{}, err
	}
	if found && c.now().Sub(fetchedAt) < ttl {
		return Result[T]{Value: value, FetchedAt: fetchedAt, Status: Hit}, nil
	}

	// A client cancelling must not kill a flight other requests share.
	v, err, _ := c.flights.Do(key, func() (any, error) {
		fctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), c.fetchTimeout)
		defer cancel()

		// Another flight may have refreshed the row while we waited for the group.
		if v2, t2, f2, err := read(fctx); err == nil && f2 && c.now().Sub(t2) < ttl {
			return Result[T]{Value: v2, FetchedAt: t2, Status: Hit}, nil
		}
		fresh, ferr := fetch(fctx)
		if ferr != nil {
			return nil, ferr
		}
		now := c.now()
		if err := write(fctx, fresh, now); err != nil {
			return nil, err
		}
		return Result[T]{Value: fresh, FetchedAt: now, Status: Miss}, nil
	})
	if err == nil {
		return v.(Result[T]), nil
	}
	if found && c.ServeStaleOn(err) {
		return Result[T]{Value: value, FetchedAt: fetchedAt, Status: Stale, UpstreamErr: err}, nil
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return Result[T]{}, errors.Join(ErrUpstreamTimeout, err)
	}
	return Result[T]{}, err
}

// ErrUpstreamTimeout marks a fetch that exceeded the flight timeout.
var ErrUpstreamTimeout = errors.New("cache: upstream fetch timed out")
