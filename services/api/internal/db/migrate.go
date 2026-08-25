package db

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/pressly/goose/v3/database"
	"github.com/pressly/goose/v3/lock"

	"github.com/danielssf/recanime/services/api/internal/migrations"
)

// Schema is the dedicated PostgreSQL schema that holds every RecAnime table.
const Schema = "recanime"

// versionTable keeps goose's bookkeeping out of `public` (not exposed by PostgREST either).
const versionTable = Schema + ".goose_db_version"

// MigrationStatus describes one migration as reported by `migrate status`.
type MigrationStatus struct {
	Version int64
	Source  string
	Applied bool
}

// Migrate applies all pending embedded migrations. sessionLock serializes concurrent
// starters with a PostgreSQL advisory lock (requires a session-mode connection).
func Migrate(ctx context.Context, databaseURL string, sessionLock bool, logger *slog.Logger) error {
	provider, closeFn, err := newProvider(ctx, databaseURL, sessionLock)
	if err != nil {
		return err
	}
	defer closeFn()

	results, err := provider.Up(ctx)
	if err != nil {
		return fmt.Errorf("apply migrations: %w", err)
	}
	for _, r := range results {
		logger.InfoContext(ctx, "migration applied", "version", r.Source.Version, "source", r.Source.Path, "duration", r.Duration.String())
	}
	if len(results) == 0 {
		logger.DebugContext(ctx, "migrations up to date")
	}
	return nil
}

// Status lists every embedded migration and whether it has been applied.
func Status(ctx context.Context, databaseURL string) ([]MigrationStatus, error) {
	provider, closeFn, err := newProvider(ctx, databaseURL, false)
	if err != nil {
		return nil, err
	}
	defer closeFn()

	statuses, err := provider.Status(ctx)
	if err != nil {
		return nil, fmt.Errorf("migration status: %w", err)
	}
	out := make([]MigrationStatus, 0, len(statuses))
	for _, s := range statuses {
		out = append(out, MigrationStatus{
			Version: s.Source.Version,
			Source:  s.Source.Path,
			Applied: s.State == goose.StateApplied,
		})
	}
	return out, nil
}

func newProvider(ctx context.Context, databaseURL string, sessionLock bool) (*goose.Provider, func(), error) {
	connCfg, err := pgx.ParseConfig(databaseURL)
	if err != nil {
		return nil, nil, fmt.Errorf("parse DATABASE_URL: %w", err)
	}
	sqlDB := stdlib.OpenDB(*connCfg)
	sqlDB.SetMaxOpenConns(1)
	closeFn := func() { _ = sqlDB.Close() }

	// The schema must exist before goose creates its version table inside it.
	if _, err := sqlDB.ExecContext(ctx, "CREATE SCHEMA IF NOT EXISTS "+Schema); err != nil {
		closeFn()
		return nil, nil, fmt.Errorf("create schema: %w", err)
	}

	store, err := database.NewStore(database.DialectPostgres, versionTable)
	if err != nil {
		closeFn()
		return nil, nil, fmt.Errorf("goose store: %w", err)
	}
	opts := []goose.ProviderOption{goose.WithStore(store)}
	if sessionLock {
		locker, err := lock.NewPostgresSessionLocker()
		if err != nil {
			closeFn()
			return nil, nil, fmt.Errorf("goose session locker: %w", err)
		}
		opts = append(opts, goose.WithSessionLocker(locker))
	}
	provider, err := goose.NewProvider("", sqlDB, migrations.FS, opts...)
	if err != nil {
		closeFn()
		return nil, nil, fmt.Errorf("goose provider: %w", err)
	}
	return provider, closeFn, nil
}
