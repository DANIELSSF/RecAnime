package store_test

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/danielssf/recanime/services/api/internal/store"
	"github.com/danielssf/recanime/services/api/internal/testutil"
)

// animeFixtureRow is the minimum an anime row needs to satisfy the library FK.
func animeFixtureRow(malID int, title string) store.AnimeRow {
	return store.AnimeRow{
		MalID:     malID,
		Title:     title,
		Genres:    []string{},
		Studios:   []string{},
		Raw:       json.RawMessage(`{"mal_id":` + strconv.Itoa(malID) + `}`),
		FetchedAt: time.Now().UTC(),
	}
}

// TestUpsertUserRekeysByEmail covers a recreated Supabase project: the same person comes back
// with a new `sub`, which used to break the unique index on lower(email) forever.
func TestUpsertUserRekeysByEmail(t *testing.T) {
	pool := testutil.TestPool(t)
	st := store.New(pool)
	ctx := context.Background()

	const (
		oldID = "11111111-1111-4111-8111-111111111111"
		newID = "22222222-2222-4222-8222-222222222222"
		email = "rekey@example.com"
	)
	if err := st.UpsertUser(ctx, oldID, email, "Old Name", ""); err != nil {
		t.Fatalf("first upsert: %v", err)
	}
	if err := st.UpsertAnimeFull(ctx, animeFixtureRow(52991, "Sousou no Frieren"), nil); err != nil {
		t.Fatalf("upsert anime: %v", err)
	}
	watching := store.StatusWatching
	if _, err := st.UpsertLibraryEntry(ctx, oldID, 52991, store.LibraryPatch{Status: &watching}); err != nil {
		t.Fatalf("library entry: %v", err)
	}

	// Same email, different id, different capitalisation: reported as a re-key exactly once.
	rekeyed, err := st.RecordUser(ctx, newID, "ReKey@Example.COM", "New Name", "https://cdn.example/a.png")
	if err != nil {
		t.Fatalf("rekey upsert: %v", err)
	}
	if !rekeyed {
		t.Fatal("RecordUser must report the re-key")
	}
	if again, err := st.RecordUser(ctx, newID, email, "", ""); err != nil || again {
		t.Fatalf("a repeat upsert must not report a re-key: rekeyed=%v err=%v", again, err)
	}

	u, err := st.GetUser(ctx, newID)
	if err != nil {
		t.Fatalf("get rekeyed user: %v", err)
	}
	if !strings.EqualFold(u.Email, email) || u.DisplayName != "New Name" {
		t.Fatalf("unexpected user after rekey: %+v", u)
	}
	if _, err := st.GetUser(ctx, oldID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("old id must be gone, got %v", err)
	}
	items, err := st.ListLibrary(ctx, newID, nil, nil)
	if err != nil {
		t.Fatalf("list library: %v", err)
	}
	if len(items) != 1 || items[0].Entry.MalID != 52991 || items[0].Entry.Status != store.StatusWatching {
		t.Fatalf("library must follow the new id: %+v", items)
	}
}
