package httpapi

import (
	"strconv"
	"testing"
	"time"
)

// TestUserEnsurerDue pins the throttle: the user row is refreshed at most once per ensureInterval,
// and a failed refresh (forget) makes the next request try again.
func TestUserEnsurerDue(t *testing.T) {
	base := time.Unix(0, 0).UTC()
	tests := []struct {
		name    string
		elapsed time.Duration
		forget  bool
		want    bool
	}{
		{name: "immediate repeat", elapsed: 0, want: false},
		{name: "inside the interval", elapsed: ensureInterval - time.Second, want: false},
		{name: "at the interval", elapsed: ensureInterval, want: true},
		{name: "after the interval", elapsed: 2 * ensureInterval, want: true},
		{name: "forgotten after a failure", elapsed: 0, forget: true, want: true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			u := &userEnsurer{seen: map[string]time.Time{}}
			if !u.due("user-1", base) {
				t.Fatal("the first call must be due")
			}
			if tc.forget {
				u.forget("user-1")
			}
			if got := u.due("user-1", base.Add(tc.elapsed)); got != tc.want {
				t.Fatalf("due after %v = %v, want %v", tc.elapsed, got, tc.want)
			}
		})
	}
}

// TestUserEnsurerPrunes covers the growth guard: entries older than ensureInterval suppress
// nothing, so they are dropped once the map reaches its cap.
func TestUserEnsurerPrunes(t *testing.T) {
	base := time.Unix(0, 0).UTC()
	tests := []struct {
		name    string
		elapsed time.Duration // age of the pre-existing entries when a new user arrives
		wantLen int
	}{
		// Stale entries are reclaimed, so the map stays small.
		{name: "stale entries pruned", elapsed: ensureInterval, wantLen: 1},
		// Users active inside the interval are kept: the map is bounded by real concurrent users.
		{name: "active entries kept", elapsed: time.Minute, wantLen: maxTrackedUsers + 1},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			u := &userEnsurer{seen: map[string]time.Time{}}
			for i := range maxTrackedUsers {
				u.due("user-"+strconv.Itoa(i), base)
			}
			if got := len(u.seen); got != maxTrackedUsers {
				t.Fatalf("seen holds %d entries, want %d", got, maxTrackedUsers)
			}
			now := base.Add(tc.elapsed)
			if !u.due("newcomer", now) {
				t.Fatal("an unseen user must be due")
			}
			if got := len(u.seen); got != tc.wantLen {
				t.Fatalf("seen holds %d entries after the prune, want %d", got, tc.wantLen)
			}
			if _, ok := u.seen["newcomer"]; !ok {
				t.Fatal("the newcomer was not recorded")
			}
		})
	}
}
