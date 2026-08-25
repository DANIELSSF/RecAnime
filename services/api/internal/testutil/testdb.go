package testutil

import (
	"context"
	"log/slog"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/danielssf/recanime/services/api/internal/db"
)

// TestPool connects to TEST_DATABASE_URL, applies migrations and truncates every table.
// Tests calling it are skipped when the variable is unset.
func TestPool(t testing.TB) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping integration test")
	}
	ctx := context.Background()
	if err := db.Migrate(ctx, url, false, slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn}))); err != nil {
		t.Fatalf("migrate test database: %v", err)
	}
	pool, err := db.Open(ctx, url, 4)
	if err != nil {
		t.Fatalf("open test database: %v", err)
	}
	t.Cleanup(pool.Close)
	_, err = pool.Exec(ctx, `TRUNCATE recanime.library_entry, recanime.user_settings, recanime.app_user,
		recanime.anime_relation, recanime.anime, recanime.list_cache`)
	if err != nil {
		t.Fatalf("truncate: %v", err)
	}
	return pool
}
