// Package db opens the PostgreSQL connection pool and runs the embedded migrations.
package db

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrUnreachable reports that the pool was created but the database did not answer.
// Open returns it wrapped together with a usable pool: the process may keep serving
// (/healthz, cached-free routes fail per request) and pgxpool reconnects on its own.
var ErrUnreachable = errors.New("db: database unreachable")

// pingDelays is the boot backoff: four retries, ~15 s of waiting in total.
var pingDelays = []time.Duration{time.Second, 2 * time.Second, 4 * time.Second, 8 * time.Second}

// Open creates a pgx pool sized for a small Cloud Run instance and verifies connectivity.
// A pool is always returned when it could be built, even when the ping never succeeds.
func Open(ctx context.Context, databaseURL string, maxConns int32) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("parse DATABASE_URL: %w", err)
	}
	cfg.MaxConns = maxConns
	cfg.MinConns = 0
	cfg.MaxConnIdleTime = 5 * time.Minute
	cfg.MaxConnLifetime = 30 * time.Minute
	cfg.HealthCheckPeriod = 30 * time.Second

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("create pool: %w", err)
	}
	ping := func(ctx context.Context) error {
		pingCtx, cancel := context.WithTimeout(ctx, 3*time.Second)
		defer cancel()
		return pool.Ping(pingCtx)
	}
	if err := pingWithRetry(ctx, ping, pingDelays); err != nil {
		return pool, fmt.Errorf("%w: %w", ErrUnreachable, err)
	}
	return pool, nil
}

// pingWithRetry calls ping once and retries after each delay, honouring ctx. It returns the
// last error when every attempt failed.
func pingWithRetry(ctx context.Context, ping func(context.Context) error, delays []time.Duration) error {
	var lastErr error
	for attempt := 0; attempt <= len(delays); attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return errors.Join(ctx.Err(), lastErr)
			case <-time.After(delays[attempt-1]):
			}
		}
		if err := ping(ctx); err != nil {
			lastErr = err
			continue
		}
		return nil
	}
	return lastErr
}
