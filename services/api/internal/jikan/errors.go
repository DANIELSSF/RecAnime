package jikan

import (
	"errors"
	"fmt"
	"time"
)

// Sentinel errors callers branch on.
var (
	ErrNotFound    = errors.New("jikan: resource not found")
	ErrBadRequest  = errors.New("jikan: bad request")
	ErrRateLimited = errors.New("jikan: rate limited")
	ErrUpstream    = errors.New("jikan: upstream unavailable")
)

// Error carries the HTTP status and Jikan's error body.
type Error struct {
	Status  int
	Type    string
	Message string
	// RetryAfter is the parsed Retry-After header (0 when absent); only 429 responses carry one.
	RetryAfter time.Duration
	kind       error
}

func (e *Error) Error() string {
	return fmt.Sprintf("jikan: HTTP %d %s: %s", e.Status, e.Type, e.Message)
}

// Unwrap exposes the sentinel so errors.Is works.
func (e *Error) Unwrap() error { return e.kind }

// IsTransient reports whether an error is worth masking with stale cache data:
// rate limiting, upstream failures, network problems and timeouts.
func IsTransient(err error) bool {
	return errors.Is(err, ErrRateLimited) || errors.Is(err, ErrUpstream)
}
