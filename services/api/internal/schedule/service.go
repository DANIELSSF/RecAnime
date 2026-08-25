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
}

// NewService wires the dependencies.
func NewService(st *store.Store, an *anime.Service, cat *catalog.Service, logger *slog.Logger) *Service {
	return &Service{store: st, anime: an, catalog: cat, logger: logger, now: time.Now}
}

// SetNow overrides the clock (tests).
func (s *Service) SetNow(now func() time.Time) { s.now = now }

// Result is the schedule plus whether any anime row could not be refreshed.
type Result struct {
	Items []model.ScheduleItem
	Stale bool
}

// ForUser lists the user's currently-watched, airing anime with their next airing time.
// includeEpisodes spends up to two Jikan calls per anime to get the exact latest episode.
func (s *Service) ForUser(ctx context.Context, userID string, includeEpisodes bool) (Result, error) {
	rows, err := s.store.WatchingAiring(ctx, userID)
	if err != nil {
		return Result{}, err
	}
	now := s.now()
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
		out.Items = append(out.Items, s.item(ctx, row, r.Entry, now, includeEpisodes))
	}
	return out, nil
}

func (s *Service) item(ctx context.Context, row store.AnimeRow, e store.LibraryEntry, now time.Time, includeEpisodes bool) model.ScheduleItem {
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

	it.LatestEpisode = s.latestEpisode(ctx, row, now, includeEpisodes)
	if it.LatestEpisode != nil {
		next := it.LatestEpisode.Number + 1
		if row.Episodes == nil || next <= *row.Episodes {
			it.NextEpisodeNumber = &next
		}
	}
	return it
}

// latestEpisode uses Jikan's episode list when asked (or already cached) and estimates a weekly
// cadence otherwise.
func (s *Service) latestEpisode(ctx context.Context, row store.AnimeRow, now time.Time, includeEpisodes bool) *model.LatestEpisode {
	if includeEpisodes {
		if le := s.exactLatest(ctx, row.MalID, now); le != nil {
			return le
		}
	}
	if row.AiredFrom == nil || row.AiredFrom.After(now) {
		return nil
	}
	weeks := int(now.Sub(*row.AiredFrom).Hours()/(24*7)) + 1
	if row.Episodes != nil && *row.Episodes > 0 && weeks > *row.Episodes {
		weeks = *row.Episodes
	}
	aired := row.AiredFrom.AddDate(0, 0, 7*(weeks-1))
	return &model.LatestEpisode{Number: weeks, AiredAt: &aired, Source: "estimate"}
}

func (s *Service) exactLatest(ctx context.Context, malID int, now time.Time) *model.LatestEpisode {
	eps, pg, _, err := s.catalog.Episodes(ctx, malID, 1)
	if err != nil {
		return nil
	}
	if pg.LastVisiblePage > 1 {
		if last, _, _, err := s.catalog.Episodes(ctx, malID, pg.LastVisiblePage); err == nil && len(last) > 0 {
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
		return nil
	}
	return &model.LatestEpisode{Number: latest.Number, AiredAt: latest.Aired, Source: "jikan"}
}
