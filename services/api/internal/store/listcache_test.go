package store_test

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/danielssf/recanime/services/api/internal/store"
	"github.com/danielssf/recanime/services/api/internal/testutil"
)

// TestListCacheSweep proves the retention sweep only removes rows nothing can read any more.
func TestListCacheSweep(t *testing.T) {
	pool := testutil.TestPool(t)
	st := store.New(pool)
	ctx := context.Background()
	payload := json.RawMessage(`{"data":[],"pagination":null}`)

	if err := st.ListCachePut(ctx, "top:-:-:-:p9", "top", payload, time.Now().Add(-200*time.Hour), nil); err != nil {
		t.Fatalf("put old: %v", err)
	}
	if err := st.ListCachePut(ctx, "top:-:-:-:p1", "top", payload, time.Now(), nil); err != nil {
		t.Fatalf("put fresh: %v", err)
	}

	if n, err := st.ListCacheSweep(ctx, 0); err != nil || n != 0 {
		t.Fatalf("retention 0 must disable the sweep, got n=%d err=%v", n, err)
	}
	n, err := st.ListCacheSweep(ctx, 168*time.Hour)
	if err != nil || n != 1 {
		t.Fatalf("sweep: n=%d err=%v", n, err)
	}
	if _, _, found, err := st.ListCacheGet(ctx, "top:-:-:-:p9"); err != nil || found {
		t.Fatalf("old row must be gone (found=%v err=%v)", found, err)
	}
	if _, _, found, err := st.ListCacheGet(ctx, "top:-:-:-:p1"); err != nil || !found {
		t.Fatalf("fresh row must survive (found=%v err=%v)", found, err)
	}
}
