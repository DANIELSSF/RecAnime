// Package catalog serves the browse sections (top, seasons, search, schedules, episodes,
// recommendations) from the 12 h list cache, plus the always-live recommendations feed.
package catalog

import (
	"context"
	"crypto/sha1" //nolint:gosec // cache key hashing, not security
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"

	"github.com/danielssf/recanime/services/api/internal/anime"
	"github.com/danielssf/recanime/services/api/internal/cache"
	"github.com/danielssf/recanime/services/api/internal/jikan"
	"github.com/danielssf/recanime/services/api/internal/model"
	"github.com/danielssf/recanime/services/api/internal/store"
)

// ErrValidation reports a bad query parameter.
var ErrValidation = errors.New("catalog: invalid parameter")

// Service coordinates list caching and overlays.
type Service struct {
	store        *store.Store
	jikan        *jikan.Client
	coord        *cache.Coordinator
	ttl          time.Duration
	searchTTL    time.Duration
	liveDebounce time.Duration
	logger       *slog.Logger
	now          func() time.Time

	liveMu sync.Mutex
	live   map[int]liveEntry
}

type liveEntry struct {
	at  time.Time
	res *jikan.Response[[]jikan.Recommendation]
}

// NewService wires the dependencies.
func NewService(st *store.Store, jk *jikan.Client, coord *cache.Coordinator, ttl, searchTTL, liveDebounce time.Duration, logger *slog.Logger) *Service {
	return &Service{store: st, jikan: jk, coord: coord, ttl: ttl, searchTTL: searchTTL, liveDebounce: liveDebounce, logger: logger, now: time.Now, live: map[int]liveEntry{}}
}

// SetNow overrides the clock (tests).
func (s *Service) SetNow(now func() time.Time) { s.now = now }

// ListParams are the accepted browse parameters.
type ListParams struct {
	Filter string
	Type   string
	Rating string
	Page   int
}

// SearchParams mirror the search endpoint.
type SearchParams struct {
	Q        string
	Type     string
	Status   string
	OrderBy  string
	Sort     string
	Genres   string
	MinScore string
	Page     int
}

// Page is a list response with provenance.
type Page struct {
	Items      []model.AnimeSummary
	Pagination model.Pagination
	Meta       cache.Result[payload]
}

// payload is what list_cache stores: Jikan's data element and pagination.
type payload struct {
	Data       json.RawMessage   `json:"data"`
	Pagination *jikan.Pagination `json:"pagination"`
}

var (
	topFilters    = set("airing", "upcoming", "bypopularity", "favorite")
	animeTypes    = set("tv", "movie", "ova", "special", "ona", "music", "cm", "pv", "tv_special")
	ratings       = set("g", "pg", "pg13", "r17", "r", "rx")
	seasonNames   = set("winter", "spring", "summer", "fall")
	weekdays      = set("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "unknown", "other")
	searchStatus  = set("airing", "complete", "upcoming")
	searchOrderBy = set("mal_id", "title", "start_date", "end_date", "episodes", "score", "scored_by", "rank", "popularity", "members", "favorites")
	sortDirs      = set("asc", "desc")
)

func set(v ...string) map[string]bool {
	m := make(map[string]bool, len(v))
	for _, s := range v {
		m[s] = true
	}
	return m
}

func validate(name, value string, allowed map[string]bool) error {
	if value == "" || allowed[value] {
		return nil
	}
	return fmt.Errorf("%w: %s=%q", ErrValidation, name, value)
}

// Top serves /top/anime.
func (s *Service) Top(ctx context.Context, userID string, sfw bool, p ListParams) (Page, error) {
	if err := errors.Join(validate("filter", p.Filter, topFilters), validate("type", p.Type, animeTypes), validate("rating", p.Rating, ratings)); err != nil {
		return Page{}, err
	}
	if sfw && p.Rating == "rx" {
		return Page{}, fmt.Errorf("%w: rating=rx is not available while the SFW setting is on", ErrValidation)
	}
	key := fmt.Sprintf("top:%s:%s:%s:sfw%s:p%d", dash(p.Type), dash(p.Filter), dash(p.Rating), b(sfw), page(p.Page))
	q := jikan.ListQuery{Filter: p.Filter, Type: p.Type, Rating: p.Rating, SFW: sfw, Page: page(p.Page)}
	return s.animeList(ctx, userID, key, "top", s.ttl, func(ctx context.Context) (*jikan.Response[[]jikan.Anime], error) {
		return s.jikan.Top(ctx, q)
	})
}

// SeasonNow serves /seasons/now.
func (s *Service) SeasonNow(ctx context.Context, userID string, sfw bool, p ListParams) (Page, error) {
	if err := validate("filter", p.Filter, animeTypes); err != nil {
		return Page{}, err
	}
	key := fmt.Sprintf("season:now:%s:sfw%s:p%d", dash(p.Filter), b(sfw), page(p.Page))
	q := jikan.ListQuery{Filter: p.Filter, SFW: sfw, Page: page(p.Page)}
	return s.animeList(ctx, userID, key, "season", s.ttl, func(ctx context.Context) (*jikan.Response[[]jikan.Anime], error) {
		return s.jikan.SeasonNow(ctx, q)
	})
}

// SeasonUpcoming serves /seasons/upcoming.
func (s *Service) SeasonUpcoming(ctx context.Context, userID string, sfw bool, p ListParams) (Page, error) {
	if err := validate("filter", p.Filter, animeTypes); err != nil {
		return Page{}, err
	}
	key := fmt.Sprintf("season:upcoming:%s:sfw%s:p%d", dash(p.Filter), b(sfw), page(p.Page))
	q := jikan.ListQuery{Filter: p.Filter, SFW: sfw, Page: page(p.Page)}
	return s.animeList(ctx, userID, key, "season", s.ttl, func(ctx context.Context) (*jikan.Response[[]jikan.Anime], error) {
		return s.jikan.SeasonUpcoming(ctx, q)
	})
}

// Season serves /seasons/{year}/{season}.
func (s *Service) Season(ctx context.Context, userID string, sfw bool, year int, season string, p ListParams) (Page, error) {
	season = strings.ToLower(season)
	if !seasonNames[season] {
		return Page{}, fmt.Errorf("%w: season=%q", ErrValidation, season)
	}
	if year < 1917 || year > s.now().Year()+2 {
		return Page{}, fmt.Errorf("%w: year=%d", ErrValidation, year)
	}
	if err := validate("filter", p.Filter, animeTypes); err != nil {
		return Page{}, err
	}
	key := fmt.Sprintf("season:%d:%s:%s:sfw%s:p%d", year, season, dash(p.Filter), b(sfw), page(p.Page))
	q := jikan.ListQuery{Filter: p.Filter, SFW: sfw, Page: page(p.Page)}
	return s.animeList(ctx, userID, key, "season", s.ttl, func(ctx context.Context) (*jikan.Response[[]jikan.Anime], error) {
		return s.jikan.Season(ctx, year, season, q)
	})
}

// Schedules serves /schedules?filter=<day>.
func (s *Service) Schedules(ctx context.Context, userID string, sfw bool, day string, pg int) (Page, error) {
	day = strings.ToLower(day)
	if err := validate("day", day, weekdays); err != nil {
		return Page{}, err
	}
	key := fmt.Sprintf("schedules:%s:sfw%s:p%d", dash(day), b(sfw), page(pg))
	return s.animeList(ctx, userID, key, "schedules", s.ttl, func(ctx context.Context) (*jikan.Response[[]jikan.Anime], error) {
		return s.jikan.Schedules(ctx, day, sfw, page(pg), 0)
	})
}

// Search serves /anime?q=...
func (s *Service) Search(ctx context.Context, userID string, sfw bool, p SearchParams) (Page, error) {
	q := strings.Join(strings.Fields(strings.ToLower(p.Q)), " ")
	if n := len([]rune(q)); n < 3 || n > 100 {
		return Page{}, fmt.Errorf("%w: q must be 3–100 characters", ErrValidation)
	}
	if err := errors.Join(validate("type", p.Type, animeTypes), validate("status", p.Status, searchStatus),
		validate("orderBy", p.OrderBy, searchOrderBy), validate("sort", p.Sort, sortDirs)); err != nil {
		return Page{}, err
	}
	h := sha1.Sum([]byte(strings.Join([]string{q, p.Type, p.Status, p.OrderBy, p.Sort, p.Genres, p.MinScore, b(sfw)}, "|"))) //nolint:gosec
	key := fmt.Sprintf("search:%s:p%d", hex.EncodeToString(h[:]), page(p.Page))
	jq := jikan.SearchQuery{Q: q, Type: p.Type, Status: p.Status, OrderBy: p.OrderBy, Sort: p.Sort, Genres: p.Genres, MinScore: p.MinScore, SFW: sfw, Page: page(p.Page)}
	return s.animeList(ctx, userID, key, "search", s.searchTTL, func(ctx context.Context) (*jikan.Response[[]jikan.Anime], error) {
		return s.jikan.Search(ctx, jq)
	})
}

// SeasonsIndex serves /seasons.
func (s *Service) SeasonsIndex(ctx context.Context) ([]model.SeasonIndex, cache.Result[payload], error) {
	res, err := s.cachedPayload(ctx, "seasons:index", "seasons_index", s.ttl, func(ctx context.Context) (json.RawMessage, *jikan.Pagination, error) {
		r, err := s.jikan.SeasonsIndex(ctx)
		if err != nil {
			return nil, nil, err
		}
		return r.Raw, r.Pagination, nil
	})
	if err != nil {
		return nil, res, err
	}
	var idx []jikan.SeasonIndex
	if err := json.Unmarshal(res.Value.Data, &idx); err != nil {
		return nil, res, err
	}
	out := make([]model.SeasonIndex, 0, len(idx))
	for _, y := range idx {
		out = append(out, model.SeasonIndex{Year: y.Year, Seasons: y.Seasons})
	}
	return out, res, nil
}

// Episodes serves one page of /anime/{id}/episodes.
func (s *Service) Episodes(ctx context.Context, malID, pg int) ([]model.Episode, model.Pagination, cache.Result[payload], error) {
	key := fmt.Sprintf("episodes:%d:p%d", malID, page(pg))
	res, err := s.cachedPayload(ctx, key, "episodes", s.ttl, func(ctx context.Context) (json.RawMessage, *jikan.Pagination, error) {
		r, err := s.jikan.AnimeEpisodes(ctx, malID, page(pg))
		if err != nil {
			return nil, nil, err
		}
		return r.Raw, r.Pagination, nil
	})
	if err != nil {
		return nil, model.Pagination{}, res, err
	}
	var eps []jikan.Episode
	if err := json.Unmarshal(res.Value.Data, &eps); err != nil {
		return nil, model.Pagination{}, res, err
	}
	out := make([]model.Episode, 0, len(eps))
	for _, e := range eps {
		out = append(out, model.Episode{Number: e.MalID, Title: e.Title, Aired: e.Aired, Filler: e.Filler, Recap: e.Recap, Score: e.Score, URL: e.URL})
	}
	return out, paginationOf(res.Value.Pagination, page(pg), len(out)), res, nil
}

// AnimeRecommendations serves /anime/{id}/recommendations.
func (s *Service) AnimeRecommendations(ctx context.Context, userID string, malID int) ([]model.AnimeRecommendation, cache.Result[payload], error) {
	key := fmt.Sprintf("anime_recs:%d", malID)
	res, err := s.cachedPayload(ctx, key, "anime_recs", s.ttl, func(ctx context.Context) (json.RawMessage, *jikan.Pagination, error) {
		r, err := s.jikan.AnimeRecommendations(ctx, malID)
		if err != nil {
			return nil, nil, err
		}
		return r.Raw, r.Pagination, nil
	})
	if err != nil {
		return nil, res, err
	}
	var recs []jikan.AnimeRecommendation
	if err := json.Unmarshal(res.Value.Data, &recs); err != nil {
		return nil, res, err
	}
	ids := make([]int, 0, len(recs))
	for _, r := range recs {
		ids = append(ids, r.Entry.MalID)
	}
	overlay, err := s.store.LibraryEntriesFor(ctx, userID, ids)
	if err != nil {
		return nil, res, err
	}
	out := make([]model.AnimeRecommendation, 0, len(recs))
	for _, r := range recs {
		out = append(out, model.AnimeRecommendation{Anime: recEntry(r.Entry, overlay), Votes: r.Votes})
	}
	return out, res, nil
}

// LiveRecommendations serves /recommendations/anime without persistent caching. A short
// in-memory debounce absorbs duplicate requests (Jikan itself caches for 24 h, so nothing is
// lost); the last good page is kept to serve as STALE if Jikan fails.
func (s *Service) LiveRecommendations(ctx context.Context, userID string, pg int) ([]model.Recommendation, model.Pagination, cache.Status, error) {
	pg = page(pg)
	now := s.now()
	s.liveMu.Lock()
	entry, ok := s.live[pg]
	s.liveMu.Unlock()

	status := cache.Live
	var res *jikan.Response[[]jikan.Recommendation]
	if ok && s.liveDebounce > 0 && now.Sub(entry.at) < s.liveDebounce {
		res = entry.res
	} else {
		fresh, err := s.jikan.RecommendationsFeed(ctx, pg)
		if err != nil {
			if ok && jikan.IsTransient(err) {
				res, status = entry.res, cache.Stale
			} else {
				return nil, model.Pagination{}, "", err
			}
		} else {
			res = fresh
			s.liveMu.Lock()
			s.live[pg] = liveEntry{at: now, res: fresh}
			s.liveMu.Unlock()
		}
	}

	var ids []int
	for _, r := range res.Data {
		for _, e := range r.Entry {
			ids = append(ids, e.MalID)
		}
	}
	overlay, err := s.store.LibraryEntriesFor(ctx, userID, ids)
	if err != nil {
		return nil, model.Pagination{}, "", err
	}
	out := make([]model.Recommendation, 0, len(res.Data))
	for _, r := range res.Data {
		rec := model.Recommendation{ID: r.MalID, Content: r.Content, Date: r.Date, User: model.RecommendationUser{Username: r.User.Username, URL: r.User.URL}}
		for _, e := range r.Entry {
			rec.Entries = append(rec.Entries, recEntry(e, overlay))
		}
		out = append(out, rec)
	}
	return out, paginationOf(res.Pagination, pg, len(out)), status, nil
}

// animeList runs the cache policy for an anime list and applies the library overlay.
func (s *Service) animeList(ctx context.Context, userID, key, kind string, ttl time.Duration,
	fetch func(ctx context.Context) (*jikan.Response[[]jikan.Anime], error)) (Page, error) {
	res, err := s.cachedPayload(ctx, key, kind, ttl, func(ctx context.Context) (json.RawMessage, *jikan.Pagination, error) {
		r, err := fetch(ctx)
		if err != nil {
			return nil, nil, err
		}
		return r.Raw, r.Pagination, nil
	})
	if err != nil {
		return Page{}, err
	}
	var list []jikan.Anime
	if err := json.Unmarshal(res.Value.Data, &list); err != nil {
		return Page{}, fmt.Errorf("decode cached list %s: %w", key, err)
	}
	ids := make([]int, 0, len(list))
	items := make([]model.AnimeSummary, 0, len(list))
	for _, a := range list {
		ids = append(ids, a.MalID)
		items = append(items, anime.SummaryFromJikan(a))
	}
	overlay, err := s.store.LibraryEntriesFor(ctx, userID, ids)
	if err != nil {
		return Page{}, err
	}
	for i := range items {
		if e, ok := overlay[items[i].MalID]; ok {
			items[i].Library = anime.OverlayFromEntry(e)
		}
	}
	pg := 1
	if res.Value.Pagination != nil && res.Value.Pagination.CurrentPage > 0 {
		pg = res.Value.Pagination.CurrentPage
	}
	return Page{Items: items, Pagination: paginationOf(res.Value.Pagination, pg, len(items)), Meta: res}, nil
}

// cachedPayload applies cache.Through to a list_cache entry.
func (s *Service) cachedPayload(ctx context.Context, key, kind string, ttl time.Duration,
	fetch func(ctx context.Context) (json.RawMessage, *jikan.Pagination, error)) (cache.Result[payload], error) {
	return cache.Through(ctx, s.coord, key, ttl,
		func(ctx context.Context) (payload, time.Time, bool, error) {
			raw, at, found, err := s.store.ListCacheGet(ctx, key)
			if err != nil || !found {
				return payload{}, time.Time{}, false, err
			}
			var p payload
			if err := json.Unmarshal(raw, &p); err != nil {
				return payload{}, time.Time{}, false, nil // treat corrupt rows as a miss
			}
			return p, at, true, nil
		},
		func(ctx context.Context) (payload, error) {
			data, pg, err := fetch(ctx)
			if err != nil {
				return payload{}, err
			}
			return payload{Data: data, Pagination: pg}, nil
		},
		func(ctx context.Context, p payload, at time.Time) error {
			raw, err := json.Marshal(p)
			if err != nil {
				return err
			}
			return s.store.ListCachePut(ctx, key, kind, raw, at, nil)
		},
	)
}

func recEntry(e jikan.RecommendationEntry, overlay map[int]store.LibraryEntry) model.RecommendationEntry {
	out := model.RecommendationEntry{MalID: e.MalID, Title: e.Title, ImageURL: e.Images.JPG.ImageURL}
	if le, ok := overlay[e.MalID]; ok {
		out.Library = anime.OverlayFromEntry(le)
	}
	return out
}

func paginationOf(p *jikan.Pagination, pg, count int) model.Pagination {
	out := model.Pagination{Page: pg, PerPage: 25}
	if p == nil {
		return out
	}
	if p.CurrentPage > 0 {
		out.Page = p.CurrentPage
	}
	out.HasNextPage = p.HasNextPage
	out.LastVisiblePage = p.LastVisiblePage
	if p.Items.PerPage > 0 {
		out.PerPage = p.Items.PerPage
	}
	out.Total = p.Items.Total
	if out.Total == 0 && !p.HasNextPage {
		out.Total = count
	}
	return out
}

func dash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

func b(v bool) string {
	if v {
		return "1"
	}
	return "0"
}

func page(p int) int {
	if p < 1 {
		return 1
	}
	return p
}
