package schedule_test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/danielssf/recanime/services/api/internal/anime"
	"github.com/danielssf/recanime/services/api/internal/cache"
	"github.com/danielssf/recanime/services/api/internal/catalog"
	"github.com/danielssf/recanime/services/api/internal/schedule"
	"github.com/danielssf/recanime/services/api/internal/store"
	"github.com/danielssf/recanime/services/api/internal/testutil"
)

// TestForUserFallsBackToEstimateWhenBudgetExhausted proves the episode budget exhaustion path
// without going through HTTP: with the anime row already fresh in the cache (so the refresh in
// ForUser is a hit and never touches Jikan), a budget of 0 must still deny the exact-episode
// lookup, mark the response stale and fall back to the weekly estimate.
func TestForUserFallsBackToEstimateWhenBudgetExhausted(t *testing.T) {
	pool := testutil.TestPool(t)
	st := store.New(pool)
	ctx := context.Background()
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))

	const userID = "bbbbbbbb-bbbb-4bbb-8bbb-000000000001"
	if err := st.UpsertUser(ctx, userID, "budget-exhausted@example.com", "", ""); err != nil {
		t.Fatalf("upsert user: %v", err)
	}

	now := time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)
	airedFrom := now.AddDate(0, 0, -7*3) // aired three weeks ago
	episodes := 24
	day, hhmm := "Sunday", "12:00"
	row := store.AnimeRow{
		MalID:        90101,
		Title:        "Budget Exhaustion Fixture",
		Episodes:     &episodes,
		Airing:       true,
		AiredFrom:    &airedFrom,
		BroadcastDay: &day, BroadcastTime: &hhmm,
		Genres: []string{}, Studios: []string{},
		Raw:       json.RawMessage(`{"mal_id":90101}`),
		FetchedAt: now, // fresh: ForUser's refresh will be a cache hit, no Jikan client needed
	}
	if err := st.UpsertAnimeFull(ctx, row, nil); err != nil {
		t.Fatalf("upsert anime: %v", err)
	}
	watching := store.StatusWatching
	if _, err := st.UpsertLibraryEntry(ctx, userID, row.MalID, store.LibraryPatch{Status: &watching}); err != nil {
		t.Fatalf("library entry: %v", err)
	}

	clock := func() time.Time { return now }
	coord := cache.NewCoordinator(nil)
	coord.SetNow(clock)
	// Neither service ever needs to reach Jikan here (the anime row is fresh and the budget is
	// exhausted before any episode fetch), so a nil client is enough.
	animeSvc := anime.NewService(st, nil, coord, 12*time.Hour, 4, logger)
	animeSvc.SetNow(clock)
	catalogSvc := catalog.NewService(st, nil, coord, 12*time.Hour, 12*time.Hour, 30*time.Second, logger)
	catalogSvc.SetNow(clock)

	sched := schedule.NewService(st, animeSvc, catalogSvc, 0, logger) // budget: 0
	sched.SetNow(clock)

	res, err := sched.ForUser(ctx, userID, true)
	if err != nil {
		t.Fatalf("for user: %v", err)
	}
	if !res.Stale {
		t.Fatalf("an exhausted episode budget must mark the schedule stale: %+v", res)
	}
	if len(res.Items) != 1 {
		t.Fatalf("expected exactly one scheduled item, got %d: %+v", len(res.Items), res.Items)
	}
	item := res.Items[0]
	if item.LatestEpisode == nil || item.LatestEpisode.Source != "estimate" {
		t.Fatalf("with no budget left the latest episode must fall back to the weekly estimate, got %+v", item.LatestEpisode)
	}
}
