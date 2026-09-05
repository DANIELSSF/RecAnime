package store_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/danielssf/recanime/services/api/internal/store"
	"github.com/danielssf/recanime/services/api/internal/testutil"
)

// TestAdjustEpisodesSemantics exercises the single-statement SQL in store.AdjustEpisodes: it must
// match the read-modify-write rules the API used to apply in Go (see the removed
// GetLibraryEntry-then-Upsert round trips), but atomically.
func TestAdjustEpisodesSemantics(t *testing.T) {
	pool := testutil.TestPool(t)
	st := store.New(pool)
	ctx := context.Background()

	ptr := func(n int) *int { return &n }

	// newFixture provisions a fresh user + anime pair (unique per subtest) so cases cannot
	// interfere with each other; malID doubles as a stable seed for both ids.
	newFixture := func(t *testing.T, seed int, episodes *int) (userID string, malID int) {
		t.Helper()
		userID = fmt.Sprintf("aaaaaaaa-aaaa-4aaa-8aaa-%012d", seed)
		malID = 900000 + seed
		if err := st.UpsertUser(ctx, userID, fmt.Sprintf("adjust-%d@example.com", seed), "", ""); err != nil {
			t.Fatalf("upsert user: %v", err)
		}
		row := animeFixtureRow(malID, fmt.Sprintf("Adjust Fixture %d", seed))
		row.Episodes = episodes
		if err := st.UpsertAnimeFull(ctx, row, nil); err != nil {
			t.Fatalf("upsert anime: %v", err)
		}
		return userID, malID
	}

	t.Run("new row with set becomes watching", func(t *testing.T) {
		user, mal := newFixture(t, 1, ptr(24))
		e, err := st.AdjustEpisodes(ctx, user, mal, ptr(5), nil, ptr(24))
		if err != nil {
			t.Fatalf("adjust: %v", err)
		}
		if e.EpisodesWatched != 5 || e.Status != store.StatusWatching {
			t.Fatalf("unexpected entry: %+v", e)
		}
	})

	t.Run("new row with delta only becomes watching and clamps to the total", func(t *testing.T) {
		user, mal := newFixture(t, 2, ptr(10))
		e, err := st.AdjustEpisodes(ctx, user, mal, nil, ptr(50), ptr(10))
		if err != nil {
			t.Fatalf("adjust: %v", err)
		}
		if e.EpisodesWatched != 10 || e.Status != store.StatusWatching {
			t.Fatalf("a delta on a brand new row must clamp to the total and start watching: %+v", e)
		}
	})

	t.Run("pending row with positive delta becomes watching", func(t *testing.T) {
		user, mal := newFixture(t, 3, ptr(24))
		pending := store.StatusPending
		if _, err := st.UpsertLibraryEntry(ctx, user, mal, store.LibraryPatch{Status: &pending}); err != nil {
			t.Fatalf("seed pending entry: %v", err)
		}
		e, err := st.AdjustEpisodes(ctx, user, mal, nil, ptr(2), ptr(24))
		if err != nil {
			t.Fatalf("adjust: %v", err)
		}
		if e.Status != store.StatusWatching || e.EpisodesWatched != 2 {
			t.Fatalf("pending + positive progress must switch to watching: %+v", e)
		}
	})

	t.Run("watched row with set stays watched", func(t *testing.T) {
		user, mal := newFixture(t, 4, ptr(24))
		watched := store.StatusWatched
		total := 24
		if _, err := st.UpsertLibraryEntry(ctx, user, mal, store.LibraryPatch{Status: &watched, EpisodesWatched: &total}); err != nil {
			t.Fatalf("seed watched entry: %v", err)
		}
		e, err := st.AdjustEpisodes(ctx, user, mal, ptr(10), nil, ptr(24))
		if err != nil {
			t.Fatalf("adjust: %v", err)
		}
		if e.Status != store.StatusWatched {
			t.Fatalf("a watched entry must stay watched even when progress moves back: %+v", e)
		}
		if e.EpisodesWatched != 10 {
			t.Fatalf("set must still apply the new progress: %+v", e)
		}
	})

	t.Run("set wins when both set and delta are given", func(t *testing.T) {
		user, mal := newFixture(t, 5, ptr(24))
		if _, err := st.AdjustEpisodes(ctx, user, mal, nil, ptr(3), ptr(24)); err != nil {
			t.Fatalf("seed: %v", err)
		}
		e, err := st.AdjustEpisodes(ctx, user, mal, ptr(9), ptr(100), ptr(24))
		if err != nil {
			t.Fatalf("adjust: %v", err)
		}
		if e.EpisodesWatched != 9 {
			t.Fatalf("set must win over a simultaneous delta, got %+v", e)
		}
	})

	t.Run("negative result clamps to zero", func(t *testing.T) {
		user, mal := newFixture(t, 6, ptr(24))
		if _, err := st.AdjustEpisodes(ctx, user, mal, ptr(2), nil, ptr(24)); err != nil {
			t.Fatalf("seed: %v", err)
		}
		e, err := st.AdjustEpisodes(ctx, user, mal, nil, ptr(-99), ptr(24))
		if err != nil {
			t.Fatalf("adjust: %v", err)
		}
		if e.EpisodesWatched != 0 {
			t.Fatalf("progress must not go negative: %+v", e)
		}
	})

	t.Run("nil total does not clamp", func(t *testing.T) {
		// A nil total is how the library layer marks "unknown episode count" (still airing);
		// the store must let the progress through uncapped.
		user, mal := newFixture(t, 7, nil)
		e, err := st.AdjustEpisodes(ctx, user, mal, ptr(500), nil, nil)
		if err != nil {
			t.Fatalf("adjust: %v", err)
		}
		if e.EpisodesWatched != 500 {
			t.Fatalf("an unknown (nil) total must not clamp the progress: %+v", e)
		}
	})

	t.Run("total 12 clamps to 12", func(t *testing.T) {
		user, mal := newFixture(t, 8, ptr(12))
		e, err := st.AdjustEpisodes(ctx, user, mal, ptr(999), nil, ptr(12))
		if err != nil {
			t.Fatalf("adjust: %v", err)
		}
		if e.EpisodesWatched != 12 {
			t.Fatalf("progress must clamp to a known total: %+v", e)
		}
	})

	t.Run("another user's row is untouched", func(t *testing.T) {
		userA, mal := newFixture(t, 9, ptr(24))
		userB := fmt.Sprintf("aaaaaaaa-aaaa-4aaa-8aaa-%012d", 90009)
		if err := st.UpsertUser(ctx, userB, "adjust-90009@example.com", "", ""); err != nil {
			t.Fatalf("upsert second user: %v", err)
		}
		if _, err := st.AdjustEpisodes(ctx, userA, mal, ptr(5), nil, ptr(24)); err != nil {
			t.Fatalf("adjust A: %v", err)
		}
		if _, err := st.AdjustEpisodes(ctx, userB, mal, ptr(20), nil, ptr(24)); err != nil {
			t.Fatalf("adjust B: %v", err)
		}
		a, err := st.GetLibraryEntry(ctx, userA, mal)
		if err != nil {
			t.Fatalf("get A: %v", err)
		}
		if a.EpisodesWatched != 5 {
			t.Fatalf("user B's adjustment must not affect user A's row: %+v", a)
		}
	})
}
