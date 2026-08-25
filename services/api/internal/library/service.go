// Package library manages the per-user lists (pending / watching / watched, favorites, progress).
package library

import (
	"context"
	"errors"
	"fmt"

	"github.com/danielssf/recanime/services/api/internal/anime"
	"github.com/danielssf/recanime/services/api/internal/model"
	"github.com/danielssf/recanime/services/api/internal/store"
)

// ErrValidation reports an invalid patch.
var ErrValidation = errors.New("library: invalid input")

// Service applies the library rules on top of the store.
type Service struct {
	store *store.Store
	anime *anime.Service
}

// NewService wires the dependencies.
func NewService(st *store.Store, an *anime.Service) *Service {
	return &Service{store: st, anime: an}
}

// Patch is a partial update; nil fields are left untouched.
type Patch struct {
	Status          *string
	Favorite        *bool
	EpisodesWatched *int
}

// Upsert creates or updates the entry, making sure the anime is cached first.
func (s *Service) Upsert(ctx context.Context, userID string, malID int, p Patch) (model.LibraryItem, error) {
	if p.Status != nil {
		switch *p.Status {
		case model.StatusPending, model.StatusWatching, model.StatusWatched:
		default:
			return model.LibraryItem{}, fmt.Errorf("%w: status must be pending|watching|watched", ErrValidation)
		}
	}
	if p.EpisodesWatched != nil && *p.EpisodesWatched < 0 {
		return model.LibraryItem{}, fmt.Errorf("%w: episodesWatched must be >= 0", ErrValidation)
	}
	row, err := s.anime.Ensure(ctx, malID)
	if err != nil {
		return model.LibraryItem{}, err
	}
	// Marking a season as watched completes its progress when the episode count is known.
	if p.Status != nil && *p.Status == model.StatusWatched && row.Episodes != nil && p.EpisodesWatched == nil {
		total := *row.Episodes
		p.EpisodesWatched = &total
	}
	if p.EpisodesWatched != nil {
		clamped := clamp(*p.EpisodesWatched, row.Episodes)
		p.EpisodesWatched = &clamped
	}
	e, err := s.store.UpsertLibraryEntry(ctx, userID, malID, store.LibraryPatch{Status: p.Status, Favorite: p.Favorite, EpisodesWatched: p.EpisodesWatched})
	if err != nil {
		return model.LibraryItem{}, err
	}
	return itemFrom(store.LibraryItem{Entry: e, Anime: row}), nil
}

// AdjustEpisodes sets the progress absolutely (set) or relatively (delta); exactly one must be given.
func (s *Service) AdjustEpisodes(ctx context.Context, userID string, malID int, set *int, delta *int) (model.LibraryItem, error) {
	if (set == nil) == (delta == nil) {
		return model.LibraryItem{}, fmt.Errorf("%w: provide either episodesWatched or delta", ErrValidation)
	}
	row, err := s.anime.Ensure(ctx, malID)
	if err != nil {
		return model.LibraryItem{}, err
	}
	target := 0
	if set != nil {
		target = *set
	} else {
		current, err := s.store.GetLibraryEntry(ctx, userID, malID)
		if err != nil && !errors.Is(err, store.ErrNotFound) {
			return model.LibraryItem{}, err
		}
		target = current.EpisodesWatched + *delta
	}
	target = clamp(target, row.Episodes)
	patch := store.LibraryPatch{EpisodesWatched: &target}
	// Progress on a pending entry means the user started watching.
	if existing, err := s.store.GetLibraryEntry(ctx, userID, malID); errors.Is(err, store.ErrNotFound) || (err == nil && existing.Status == model.StatusPending && target > 0) {
		st := model.StatusWatching
		patch.Status = &st
	}
	e, err := s.store.UpsertLibraryEntry(ctx, userID, malID, patch)
	if err != nil {
		return model.LibraryItem{}, err
	}
	return itemFrom(store.LibraryItem{Entry: e, Anime: row}), nil
}

// Get returns one item.
func (s *Service) Get(ctx context.Context, userID string, malID int) (model.LibraryItem, error) {
	e, err := s.store.GetLibraryEntry(ctx, userID, malID)
	if err != nil {
		return model.LibraryItem{}, err
	}
	row, found, err := s.store.GetAnime(ctx, malID)
	if err != nil {
		return model.LibraryItem{}, err
	}
	if !found {
		return model.LibraryItem{}, store.ErrNotFound
	}
	return itemFrom(store.LibraryItem{Entry: e, Anime: row}), nil
}

// Delete removes the entry.
func (s *Service) Delete(ctx context.Context, userID string, malID int) error {
	return s.store.DeleteLibraryEntry(ctx, userID, malID)
}

// List returns a flat, optionally filtered list.
func (s *Service) List(ctx context.Context, userID string, status *string, favorite *bool) ([]model.LibraryItem, error) {
	if status != nil {
		switch *status {
		case model.StatusPending, model.StatusWatching, model.StatusWatched:
		default:
			return nil, fmt.Errorf("%w: status must be pending|watching|watched", ErrValidation)
		}
	}
	rows, err := s.store.ListLibrary(ctx, userID, status, favorite)
	if err != nil {
		return nil, err
	}
	return itemsFrom(rows), nil
}

// Grouped returns the "Mi lista" buckets in one call.
func (s *Service) Grouped(ctx context.Context, userID string) (model.LibraryGroups, error) {
	rows, err := s.store.ListLibrary(ctx, userID, nil, nil)
	if err != nil {
		return model.LibraryGroups{}, err
	}
	g := model.LibraryGroups{Watching: []model.LibraryItem{}, Pending: []model.LibraryItem{}, Watched: []model.LibraryItem{}, Favorites: []model.LibraryItem{}}
	for _, r := range rows {
		it := itemFrom(r)
		switch r.Entry.Status {
		case model.StatusWatching:
			g.Watching = append(g.Watching, it)
		case model.StatusPending:
			g.Pending = append(g.Pending, it)
		case model.StatusWatched:
			g.Watched = append(g.Watched, it)
		}
		if r.Entry.Favorite {
			g.Favorites = append(g.Favorites, it)
		}
	}
	return g, nil
}

func clamp(v int, total *int) int {
	if v < 0 {
		return 0
	}
	if total != nil && *total > 0 && v > *total {
		return *total
	}
	return v
}

func itemsFrom(rows []store.LibraryItem) []model.LibraryItem {
	out := make([]model.LibraryItem, 0, len(rows))
	for _, r := range rows {
		out = append(out, itemFrom(r))
	}
	return out
}

func itemFrom(r store.LibraryItem) model.LibraryItem {
	sum := anime.SummaryFromRow(r.Anime)
	sum.Library = anime.OverlayFromEntry(r.Entry)
	it := model.LibraryItem{
		Anime:    sum,
		Entry:    model.LibraryEntry{Status: r.Entry.Status, Favorite: r.Entry.Favorite, EpisodesWatched: r.Entry.EpisodesWatched, CreatedAt: r.Entry.CreatedAt, UpdatedAt: r.Entry.UpdatedAt},
		Progress: model.Progress{EpisodesTotal: r.Anime.Episodes},
	}
	if r.Anime.Episodes != nil {
		rem := *r.Anime.Episodes - r.Entry.EpisodesWatched
		if rem < 0 {
			rem = 0
		}
		it.Progress.Remaining = &rem
	}
	return it
}
