package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// ListCacheGet returns the cached payload for key.
func (s *Store) ListCacheGet(ctx context.Context, key string) (payload json.RawMessage, fetchedAt time.Time, found bool, err error) {
	err = s.pool.QueryRow(ctx, `SELECT payload, fetched_at FROM recanime.list_cache WHERE cache_key = $1`, key).
		Scan(&payload, &fetchedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, time.Time{}, false, nil
		}
		return nil, time.Time{}, false, fmt.Errorf("list cache get: %w", err)
	}
	return payload, fetchedAt, true, nil
}

// ListCacheSweep deletes cached list rows fetched longer ago than olderThan and returns how
// many were removed. Nothing reads a row that old (the TTL is 12 h), but every distinct
// page/search key would otherwise stay forever.
func (s *Store) ListCacheSweep(ctx context.Context, olderThan time.Duration) (int64, error) {
	if olderThan <= 0 {
		return 0, nil
	}
	tag, err := s.pool.Exec(ctx, `DELETE FROM recanime.list_cache WHERE fetched_at < $1`, time.Now().Add(-olderThan))
	if err != nil {
		return 0, fmt.Errorf("list cache sweep: %w", err)
	}
	return tag.RowsAffected(), nil
}

// ListCachePut stores or refreshes a cached list payload.
func (s *Store) ListCachePut(ctx context.Context, key, kind string, payload json.RawMessage, fetchedAt time.Time, upstreamExpires *time.Time) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO recanime.list_cache (cache_key, kind, payload, fetched_at, upstream_expires_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (cache_key) DO UPDATE SET
			kind = EXCLUDED.kind, payload = EXCLUDED.payload, fetched_at = EXCLUDED.fetched_at,
			upstream_expires_at = EXCLUDED.upstream_expires_at`, key, kind, payload, fetchedAt, upstreamExpires)
	if err != nil {
		return fmt.Errorf("list cache put: %w", err)
	}
	return nil
}
