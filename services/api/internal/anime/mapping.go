// Package anime caches MyAnimeList entries (via Jikan) and builds detail/franchise views.
package anime

import (
	"encoding/json"
	"strings"
	"time"

	"github.com/danielssf/recanime/services/api/internal/jikan"
	"github.com/danielssf/recanime/services/api/internal/model"
	"github.com/danielssf/recanime/services/api/internal/store"
)

// AiringStatus normalizes MAL's status text.
func AiringStatus(status *string, airing bool) string {
	if status != nil {
		switch strings.ToLower(*status) {
		case "currently airing":
			return model.AiringNow
		case "finished airing":
			return model.AiringFinished
		case "not yet aired":
			return model.AiringUpcoming
		}
	}
	if airing {
		return model.AiringNow
	}
	return model.AiringUnknown
}

// IsAdult flags hentai (Rx rating) or explicit genres.
func IsAdult(rating *string, explicit []jikan.Named) bool {
	if len(explicit) > 0 {
		return true
	}
	return rating != nil && strings.HasPrefix(*rating, "Rx")
}

// RowFromJikan converts a full Jikan anime into the cached row and its relations.
func RowFromJikan(a jikan.Anime, raw json.RawMessage, fetchedAt time.Time) (store.AnimeRow, []store.RelationRow) {
	row := store.AnimeRow{
		MalID:             a.MalID,
		Title:             a.Title,
		TitleEnglish:      a.TitleEnglish,
		TitleJapanese:     a.TitleJapanese,
		Type:              a.Type,
		Source:            a.Source,
		Episodes:          a.Episodes,
		Status:            a.Status,
		Airing:            a.Airing,
		AiredFrom:         a.Aired.From,
		AiredTo:           a.Aired.To,
		Duration:          a.Duration,
		Rating:            a.Rating,
		Score:             a.Score,
		ScoredBy:          a.ScoredBy,
		Rank:              a.Rank,
		Popularity:        a.Popularity,
		Members:           a.Members,
		Favorites:         a.Favorites,
		Season:            a.Season,
		Year:              a.Year,
		BroadcastDay:      a.Broadcast.Day,
		BroadcastTime:     a.Broadcast.Time,
		BroadcastTimezone: a.Broadcast.Timezone,
		BroadcastString:   a.Broadcast.String,
		ImageURL:          optional(a.Images.JPG.ImageURL),
		ImageLargeURL:     optional(a.Images.JPG.LargeImageURL),
		Genres:            names(a.Genres),
		Studios:           names(a.Studios),
		IsAdult:           IsAdult(a.Rating, a.ExplicitGenres),
		Raw:               raw,
		FetchedAt:         fetchedAt,
	}
	if row.Genres == nil {
		row.Genres = []string{}
	}
	if row.Studios == nil {
		row.Studios = []string{}
	}
	return row, RelationsFromJikan(a.MalID, a.Relations)
}

// RelationsFromJikan flattens Jikan relation groups into rows.
func RelationsFromJikan(fromID int, groups []jikan.RelationGroup) []store.RelationRow {
	var out []store.RelationRow
	for _, g := range groups {
		for _, e := range g.Entry {
			out = append(out, store.RelationRow{FromMalID: fromID, Relation: g.Relation, ToType: e.Type, ToMalID: e.MalID, ToName: e.Name})
		}
	}
	return out
}

// SummaryFromRow builds the card representation from the cached row.
func SummaryFromRow(r store.AnimeRow) model.AnimeSummary {
	return model.AnimeSummary{
		MalID:         r.MalID,
		Title:         r.Title,
		TitleEnglish:  r.TitleEnglish,
		ImageURL:      deref(r.ImageURL),
		ImageLargeURL: deref(r.ImageLargeURL),
		Type:          r.Type,
		Episodes:      r.Episodes,
		Status:        r.Status,
		AiringStatus:  AiringStatus(r.Status, r.Airing),
		Airing:        r.Airing,
		Score:         r.Score,
		Rank:          r.Rank,
		Popularity:    r.Popularity,
		Members:       r.Members,
		Year:          r.Year,
		Season:        r.Season,
		Rating:        r.Rating,
		IsAdult:       r.IsAdult,
	}
}

// SummaryFromJikan builds the card representation straight from a Jikan list item.
func SummaryFromJikan(a jikan.Anime) model.AnimeSummary {
	return model.AnimeSummary{
		MalID:         a.MalID,
		Title:         a.Title,
		TitleEnglish:  a.TitleEnglish,
		ImageURL:      a.Images.JPG.ImageURL,
		ImageLargeURL: a.Images.JPG.LargeImageURL,
		Type:          a.Type,
		Episodes:      a.Episodes,
		Status:        a.Status,
		AiringStatus:  AiringStatus(a.Status, a.Airing),
		Airing:        a.Airing,
		Score:         a.Score,
		Rank:          a.Rank,
		Popularity:    a.Popularity,
		Members:       a.Members,
		Year:          a.Year,
		Season:        a.Season,
		Rating:        a.Rating,
		IsAdult:       IsAdult(a.Rating, a.ExplicitGenres),
	}
}

// DetailFromRow builds the full page from the cached row (raw payload supplies the long tail).
func DetailFromRow(r store.AnimeRow) (model.AnimeDetail, error) {
	var a jikan.Anime
	if err := json.Unmarshal(r.Raw, &a); err != nil {
		return model.AnimeDetail{}, err
	}
	d := model.AnimeDetail{
		AnimeSummary:  SummaryFromRow(r),
		TitleJapanese: r.TitleJapanese,
		Synopsis:      a.Synopsis,
		Background:    a.Background,
		Source:        r.Source,
		Duration:      r.Duration,
		ScoredBy:      r.ScoredBy,
		Favorites:     r.Favorites,
		AiredFrom:     r.AiredFrom,
		AiredTo:       r.AiredTo,
		AiredString:   a.Aired.String,
		TrailerURL:    a.Trailer.URL,
		MalURL:        a.URL,
		Genres:        r.Genres,
		Themes:        names(a.Themes),
		Demographics:  names(a.Demographics),
		Studios:       r.Studios,
		Producers:     names(a.Producers),
		Streaming:     links(a.Streaming),
		External:      links(a.External),
		Relations:     relationGroups(a.Relations),
	}
	if r.BroadcastDay != nil || r.BroadcastTime != nil || r.BroadcastString != nil {
		d.Broadcast = &model.BroadcastInfo{Day: r.BroadcastDay, Time: r.BroadcastTime, Timezone: r.BroadcastTimezone, String: r.BroadcastString}
	}
	return d, nil
}

// OverlayFromEntry converts a library row into the embedded overlay.
func OverlayFromEntry(e store.LibraryEntry) *model.LibraryOverlay {
	return &model.LibraryOverlay{Status: e.Status, Favorite: e.Favorite, EpisodesWatched: e.EpisodesWatched, UpdatedAt: e.UpdatedAt}
}

func names(in []jikan.Named) []string {
	out := make([]string, 0, len(in))
	for _, n := range in {
		out = append(out, n.Name)
	}
	return out
}

func links(in []jikan.External) []model.Link {
	out := make([]model.Link, 0, len(in))
	for _, l := range in {
		out = append(out, model.Link{Name: l.Name, URL: l.URL})
	}
	return out
}

func relationGroups(in []jikan.RelationGroup) []model.RelationGroup {
	out := make([]model.RelationGroup, 0, len(in))
	for _, g := range in {
		rg := model.RelationGroup{Relation: g.Relation, Entries: make([]model.RelationEntry, 0, len(g.Entry))}
		for _, e := range g.Entry {
			rg.Entries = append(rg.Entries, model.RelationEntry{MalID: e.MalID, Type: e.Type, Name: e.Name})
		}
		out = append(out, rg)
	}
	return out
}

func optional(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
