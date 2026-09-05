// Command api runs the RecAnime HTTP API (default: serve) or applies migrations (migrate up|status).
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata" // broadcast schedules convert JST; the distroless image has no zoneinfo

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/danielssf/recanime/services/api/internal/anime"
	"github.com/danielssf/recanime/services/api/internal/auth"
	"github.com/danielssf/recanime/services/api/internal/cache"
	"github.com/danielssf/recanime/services/api/internal/catalog"
	"github.com/danielssf/recanime/services/api/internal/config"
	"github.com/danielssf/recanime/services/api/internal/db"
	"github.com/danielssf/recanime/services/api/internal/httpapi"
	"github.com/danielssf/recanime/services/api/internal/jikan"
	"github.com/danielssf/recanime/services/api/internal/library"
	"github.com/danielssf/recanime/services/api/internal/platform"
	"github.com/danielssf/recanime/services/api/internal/ratelimit"
	"github.com/danielssf/recanime/services/api/internal/schedule"
	"github.com/danielssf/recanime/services/api/internal/store"
)

// version is stamped at build time with -ldflags "-X main.version=<git sha>".
var version = "dev"

func main() {
	// Serialize every timestamp in UTC regardless of the host time zone (Cloud Run is UTC anyway).
	time.Local = time.UTC
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	cmd := "serve"
	if len(args) > 0 {
		cmd = args[0]
	}
	cfg, err := config.Load(os.Getenv)
	if err != nil {
		return err
	}
	logger := platform.NewLogger(os.Stdout, cfg.IsProduction(), cfg.LogLevel)
	slog.SetDefault(logger)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	switch cmd {
	case "serve":
		return serve(ctx, cfg, logger)
	case "migrate":
		sub := "up"
		if len(args) > 1 {
			sub = args[1]
		}
		return migrate(ctx, cfg, logger, sub)
	default:
		return fmt.Errorf("unknown command %q (expected: serve | migrate up | migrate status)", cmd)
	}
}

func migrate(ctx context.Context, cfg config.Config, logger *slog.Logger, sub string) error {
	switch sub {
	case "up":
		return db.Migrate(ctx, cfg.DatabaseURL, cfg.DBSessionLock, logger)
	case "status":
		statuses, err := db.Status(ctx, cfg.DatabaseURL)
		if err != nil {
			return err
		}
		for _, s := range statuses {
			state := "pending"
			if s.Applied {
				state = "applied"
			}
			fmt.Printf("%-8s %05d %s\n", state, s.Version, s.Source)
		}
		return nil
	default:
		return fmt.Errorf("unknown migrate subcommand %q (expected: up | status)", sub)
	}
}

func serve(ctx context.Context, cfg config.Config, logger *slog.Logger) error {
	if cfg.DevBypassAuth {
		logger.Warn("DEV_BYPASS_AUTH is enabled: requests are NOT authenticated", "email", cfg.DevBypassEmail)
	}

	// A database that is down (Supabase paused, cold start during a blip) must not kill the
	// revision: the pool is kept, /healthz stays green, /readyz answers 503 and pgxpool reconnects.
	pool, err := db.Open(ctx, cfg.DatabaseURL, cfg.DBMaxConns)
	if err != nil && (pool == nil || !errors.Is(err, db.ErrUnreachable)) {
		return err
	}
	defer pool.Close()
	dbReady := make(chan struct{})
	if err != nil {
		logger.Error("database unreachable at startup, serving anyway", "error", err)
		go waitForDatabase(ctx, cfg, pool, logger, dbReady)
	} else {
		if cfg.DBMigrateOnStart {
			if err := db.Migrate(ctx, cfg.DatabaseURL, cfg.DBSessionLock, logger); err != nil {
				return err
			}
		}
		close(dbReady)
	}

	limiter := ratelimit.New(cfg.JikanRPS, cfg.JikanRPM)
	jk := jikan.New(cfg.JikanBaseURL, &http.Client{Timeout: 15 * time.Second}, limiter, "RecAnime/"+version+" (+https://github.com/danielssf/recanime)")
	coord := cache.NewCoordinator(jikan.IsTransient)
	st := store.New(pool)
	animeSvc := anime.NewService(st, jk, coord, cfg.CacheTTL, cfg.FranchiseFetchBudget, logger)
	catalogSvc := catalog.NewService(st, jk, coord, cfg.CacheTTL, cfg.SearchTTL, cfg.LiveDebounce, logger)
	librarySvc := library.NewService(st, animeSvc)
	scheduleSvc := schedule.NewService(st, animeSvc, catalogSvc, cfg.ScheduleEpisodeBudget, logger)

	go sweepListCache(ctx, st, cfg.ListCacheRetention, logger, dbReady)

	authCfg := httpapi.AuthConfig{
		Allowlist:      auth.NewAllowlist(cfg.AllowedEmails),
		DevBypass:      cfg.DevBypassAuth,
		DevBypassEmail: cfg.DevBypassEmail,
	}
	if !cfg.DevBypassAuth {
		keys := auth.NewKeySet(cfg.JWKSURL(), &http.Client{Timeout: 10 * time.Second})
		prefetchCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		if err := keys.Prefetch(prefetchCtx); err != nil {
			// Not fatal: the set is fetched lazily on the first request.
			logger.Warn("jwks prefetch failed", "url", cfg.JWKSURL(), "error", err)
		}
		cancel()
		authCfg.Verifier = auth.NewVerifier(keys, cfg.Issuer())
	}

	handler := httpapi.New(httpapi.Deps{
		Logger:          logger,
		Pool:            pool,
		Version:         version,
		Store:           st,
		Anime:           animeSvc,
		Catalog:         catalogSvc,
		Library:         librarySvc,
		Schedule:        scheduleSvc,
		Auth:            authCfg,
		FranchiseBudget: cfg.FranchiseFetchBudget,
	})

	srv := &http.Server{
		Addr:              net.JoinHostPort(cfg.Host, cfg.Port),
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		logger.Info("api listening", "addr", srv.Addr, "env", cfg.AppEnv, "version", version)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
	}

	// Cloud Run grants ~10 s after SIGTERM; drain in-flight requests within 8 s.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	logger.Info("shutting down")
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}
	return nil
}

// waitForDatabase runs the pending migrations once the database answers again, retrying every
// 30 s, and closes ready when the database is usable.
func waitForDatabase(ctx context.Context, cfg config.Config, pool *pgxpool.Pool, logger *slog.Logger, ready chan<- struct{}) {
	const retry = 30 * time.Second
	for {
		var err error
		if cfg.DBMigrateOnStart {
			err = db.Migrate(ctx, cfg.DatabaseURL, cfg.DBSessionLock, logger)
		} else {
			err = pool.Ping(ctx)
		}
		if err == nil {
			logger.Info("database reachable")
			close(ready)
			return
		}
		logger.Warn("database still unreachable", "error", err, "retryIn", retry.String())
		select {
		case <-ctx.Done():
			return
		case <-time.After(retry):
		}
	}
}

// sweepListCache deletes list_cache rows nothing can read any more: once the database is
// reachable and then every 6 h. Without it every distinct page/search key stays forever.
func sweepListCache(ctx context.Context, st *store.Store, retention time.Duration, logger *slog.Logger, ready <-chan struct{}) {
	if retention <= 0 {
		return
	}
	select {
	case <-ready:
	case <-ctx.Done():
		return
	}
	const interval = 6 * time.Hour
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		deleted, err := st.ListCacheSweep(ctx, retention)
		if err != nil {
			logger.WarnContext(ctx, "list cache sweep failed", "error", err)
		} else {
			logger.InfoContext(ctx, "list cache swept", "deleted", deleted, "retention", retention.String())
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
