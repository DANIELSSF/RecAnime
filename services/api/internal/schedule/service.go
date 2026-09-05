package schedule

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/danielssf/recanime/services/api/internal/anime"
	"github.com/danielssf/recanime/services/api/internal/cache"
	"github.com/danielssf/recanime/services/api/internal/catalog"
	"github.com/danielssf/recanime/services/api/internal/model"
	"github.com/danielssf/recanime/services/api/internal/store"
)

// Service builds the personal airing schedule.
type Service struct {
	store   *store.Store
	anime   *anime.Service
	catalog *catalog.Service
	logger  *slog.Logger
	now     func() time.Time
	// episodeBudget caps the upstream episode fetches one includeEpisodes request may spend.
	episodeBudget int
}

// NewService wires the dependencies. episodeBudget bounds the upstream episode calls per request.
func NewService(st *store.Store, an *anime.Service, cat *catalog.Service, episodeBudget int, logger *slog.Logger) *Service {
	if episodeBudget < 0 {
		episodeBudget = 0
	}
	return &Service{store: st, anime: an, catalog: cat, logger: logger, now: time.Now, episodeBudget: episodeBudget}
}

// SetNow overrides the clock (tests).
func (s *Service) SetNow(now func() time.Time) { s.now = now }

// SetEpisodeBudget overrides the per-request episode budget (tests).
func (s *Service) SetEpisodeBudget(n int) { s.episodeBudget = n }

// Result is the schedule plus whether any anime row could not be refreshed.
type Result struct {
	Items []model.ScheduleItem
	Stale bool
}

// ForUser lists the user's currently-watched, airing anime with their next airing time.
// includeEpisodes spends up to two Jikan calls per anime to get the exact latest episode,
// bounded by the per-request episode budget: cache hits are free, upstream fetches are not.
// Once the budget runs out the remaining anime fall back to the weekly estimate and the
// result is marked stale.
func (s *Service) ForUser(ctx context.Context, userID string, includeEpisodes bool) (Result, error) {
	rows, err := s.store.WatchingAiring(ctx, userID)
	if err != nil {
		return Result{}, err
	}
	now := s.now()
	budget := s.episodeBudget
	out := Result{Items: make([]model.ScheduleItem, 0, len(rows))}
	for _, r := range rows {
		row := r.Anime
		// Refresh rows past the cache TTL so broadcast/status/episodes are current.
		if res, err := s.anime.Get(ctx, row.MalID); err == nil {
			row = res.Value
			if res.Status == cache.Stale {
				out.Stale = true
			}
		} else if !errors.Is(err, anime.ErrNotFound) {
			out.Stale = true
			s.logger.WarnContext(ctx, "schedule: refresh failed, using cached row", "malId", row.MalID, "error", err)
		}
		if !row.Airing && (row.Status == nil || *row.Status != "Not yet aired") {
			continue // finished since the library entry was created
		}
		item, exhausted := s.item(ctx, row, r.Entry, now, includeEpisodes, &budget)
		if exhausted {
			out.Stale = true
		}
		out.Items = append(out.Items, item)
	}
	return out, nil
}

// item builds one schedule row; exhausted reports that the episode budget ran out for it.
func (s *Service) item(ctx context.Context, row store.AnimeRow, e store.LibraryEntry, now time.Time, includeEpisodes bool, budget *int) (model.ScheduleItem, bool) {
	it := model.ScheduleItem{
		MalID:           row.MalID,
		Title:           row.Title,
		EpisodesTotal:   row.Episodes,
		EpisodesWatched: e.EpisodesWatched,
		Status:          row.Status,
		Airing:          row.Airing,
	}
	if row.ImageURL != nil {
		it.ImageURL = *row.ImageURL
	}
	if row.Episodes != nil {
		rem := max(*row.Episodes-e.EpisodesWatched, 0)
		it.Remaining = &rem
	}
	if row.BroadcastDay != nil || row.BroadcastTime != nil || row.BroadcastString != nil {
		it.Broadcast = &model.BroadcastInfo{Day: row.BroadcastDay, Time: row.BroadcastTime, Timezone: row.BroadcastTimezone, String: row.BroadcastString}
	}
	if row.BroadcastDay != nil && row.BroadcastTime != nil {
		tz := ""
		if row.BroadcastTimezone != nil {
			tz = *row.BroadcastTimezone
		}
		if next, err := NextAiring(*row.BroadcastDay, *row.BroadcastTime, tz, now, row.AiredFrom); err == nil {
			it.NextAiringAt = &next
		} else {
			it.Reason = "unknown_broadcast"
		}
	} else {
		it.Reason = "unknown_broadcast"
	}

	var exhausted bool
	it.LatestEpisode, exhausted = s.latestEpisode(ctx, row, now, includeEpisodes, budget)
	if it.LatestEpisode != nil {
		next := it.LatestEpisode.Number + 1
		if row.Episodes == nil || next <= *row.Episodes {
			it.NextEpisodeNumber = &next
		}
	}
	return it, exhausted
}

// latestEpisode uses Jikan's episode list when asked (or already cached) and estimates a weekly
// cadence otherwise. exhausted reports that the budget denied an upstream episode fetch.
func (s *Service) latestEpisode(ctx context.Context, row store.AnimeRow, now time.Time, includeEpisodes bool, budget *int) (*model.LatestEpisode, bool) {
	var exhausted bool
	if includeEpisodes {
		le, spent := s.exactLatest(ctx, row.MalID, now, budget)
		exhausted = spent
		if le != nil {
			return le, exhausted
		}
	}
	if row.AiredFrom == nil || row.AiredFrom.After(now) {
		return nil, exhausted
	}
	weeks := int(now.Sub(*row.AiredFrom).Hours()/(24*7)) + 1
	if row.Episodes != nil && *row.Episodes > 0 && weeks > *row.Episodes {
		weeks = *row.Episodes
	}
	aired := row.AiredFrom.AddDate(0, 0, 7*(weeks-1))
	return &model.LatestEpisode{Number: weeks, AiredAt: &aired, Source: "estimate"}, exhausted
}

// exactLatest reads the episode list (page 1, then the last page). Every call that actually
// reaches Jikan costs one unit of budget; cache hits are free. exhausted reports that the budget
// was empty, so the caller falls back to the estimate and flags the response as stale.
func (s *Service) exactLatest(ctx context.Context, malID int, now time.Time, budget *int) (*model.LatestEpisode, bool) {
	episodes := func(pg int) ([]model.Episode, model.Pagination, bool, error) {
		if *budget <= 0 {
			return nil, model.Pagination{}, true, nil
		}
		eps, pagination, res, err := s.catalog.Episodes(ctx, malID, pg)
		if res.Status != cache.Hit {
			*budget--
		}
		return eps, pagination, false, err
	}
	eps, pg, exhausted, err := episodes(1)
	if exhausted || err != nil {
		return nil, exhausted
	}
	if pg.LastVisiblePage > 1 {
		last, _, lastExhausted, err := episodes(pg.LastVisiblePage)
		if lastExhausted {
			// The first page is still usable; the exact latest may just be older than the truth.
			exhausted = true
		} else if err == nil && len(last) > 0 {
			eps = last
		}
	}
	var latest *model.Episode
	for i := range eps {
		ep := &eps[i]
		if ep.Aired != nil && ep.Aired.After(now) {
			continue
		}
		if latest == nil || ep.Number > latest.Number {
			latest = ep
		}
	}
	if latest == nil {
		return nil, exhausted
	}
	return &model.LatestEpisode{Number: latest.Number, AiredAt: latest.Aired, Source: "jikan"}, exhausted
}
