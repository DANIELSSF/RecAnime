package anime

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/danielssf/recanime/services/api/internal/cache"
	"github.com/danielssf/recanime/services/api/internal/jikan"
	"github.com/danielssf/recanime/services/api/internal/model"
	"github.com/danielssf/recanime/services/api/internal/store"
)

// ErrNotFound is returned for MAL ids Jikan does not know.
var ErrNotFound = errors.New("anime: not found")

// Service caches anime rows with the 12 h read-through policy.
type Service struct {
	store  *store.Store
	jikan  *jikan.Client
	coord  *cache.Coordinator
	ttl    time.Duration
	logger *slog.Logger
	budget int // default franchise fetch budget

	negMu sync.Mutex
	neg   map[int]time.Time // negative cache for 404s
	now   func() time.Time
}

// NewService wires the dependencies.
func NewService(st *store.Store, jk *jikan.Client, coord *cache.Coordinator, ttl time.Duration, franchiseBudget int, logger *slog.Logger) *Service {
	return &Service{store: st, jikan: jk, coord: coord, ttl: ttl, logger: logger, budget: franchiseBudget, neg: map[int]time.Time{}, now: time.Now}
}

// SetNow overrides the clock (tests).
func (s *Service) SetNow(now func() time.Time) { s.now = now }

// Get returns the cached row, refreshing it from Jikan when older than the TTL.
func (s *Service) Get(ctx context.Context, malID int) (cache.Result[store.AnimeRow], error) {
	if s.isNegativelyCached(malID) {
		return cache.Result[store.AnimeRow]{}, ErrNotFound
	}
	res, err := cache.Through(ctx, s.coord, fmt.Sprintf("anime:%d", malID), s.ttl,
		func(ctx context.Context) (store.AnimeRow, time.Time, bool, error) {
			row, found, err := s.store.GetAnime(ctx, malID)
			return row, row.FetchedAt, found, err
		},
		func(ctx context.Context) (store.AnimeRow, error) {
			return s.fetch(ctx, malID)
		},
		func(ctx context.Context, row store.AnimeRow, _ time.Time) error {
			return s.persist(ctx, row)
		},
	)
	if err != nil {
		if errors.Is(err, jikan.ErrNotFound) {
			s.rememberMissing(malID)
			return cache.Result[store.AnimeRow]{}, ErrNotFound
		}
		return cache.Result[store.AnimeRow]{}, err
	}
	return res, nil
}

// Ensure returns any cached row regardless of age, fetching it only when absent.
// Used before creating library entries (the FK requires the anime row).
func (s *Service) Ensure(ctx context.Context, malID int) (store.AnimeRow, error) {
	row, found, err := s.store.GetAnime(ctx, malID)
	if err != nil {
		return store.AnimeRow{}, err
	}
	if found {
		return row, nil
	}
	res, err := s.Get(ctx, malID)
	if err != nil {
		return store.AnimeRow{}, err
	}
	return res.Value, nil
}

// fetch downloads /anime/{id}/full and converts it; relations ride along in the row's raw payload.
func (s *Service) fetch(ctx context.Context, malID int) (store.AnimeRow, error) {
	res, err := s.jikan.AnimeFull(ctx, malID)
	if err != nil {
		return store.AnimeRow{}, err
	}
	row, _ := RowFromJikan(res.Data, res.Raw, s.now())
	return row, nil
}

// persist stores the row and its relations (re-derived from the raw payload).
func (s *Service) persist(ctx context.Context, row store.AnimeRow) error {
	var a jikan.Anime
	if err := jsonUnmarshal(row.Raw, &a); err != nil {
		return err
	}
	return s.store.UpsertAnimeFull(ctx, row, RelationsFromJikan(row.MalID, a.Relations))
}

// Detail builds the anime page for userID, including a zero-budget franchise chain.
func (s *Service) Detail(ctx context.Context, userID string, malID int) (model.AnimeDetail, cache.Result[store.AnimeRow], error) {
	res, err := s.Get(ctx, malID)
	if err != nil {
		return model.AnimeDetail{}, res, err
	}
	d, err := DetailFromRow(res.Value)
	if err != nil {
		return model.AnimeDetail{}, res, fmt.Errorf("decode cached anime %d: %w", malID, err)
	}
	entries, err := s.store.LibraryEntriesFor(ctx, userID, []int{malID})
	if err != nil {
		return model.AnimeDetail{}, res, err
	}
	if e, ok := entries[malID]; ok {
		d.Library = OverlayFromEntry(e)
	}
	fr, err := s.Franchise(ctx, userID, malID, 0)
	if err != nil {
		// The chain is a nice-to-have on the detail page; log and continue.
		s.logger.WarnContext(ctx, "franchise chain unavailable", "malId", malID, "error", err)
	} else {
		d.Franchise = &fr
	}
	return d, res, nil
}

func (s *Service) isNegativelyCached(malID int) bool {
	s.negMu.Lock()
	defer s.negMu.Unlock()
	until, ok := s.neg[malID]
	if !ok {
		return false
	}
	if s.now().After(until) {
		delete(s.neg, malID)
		return false
	}
	return true
}

func (s *Service) rememberMissing(malID int) {
	s.negMu.Lock()
	defer s.negMu.Unlock()
	s.neg[malID] = s.now().Add(10 * time.Minute)
}
