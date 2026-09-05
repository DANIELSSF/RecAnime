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
	"strconv"
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
	return s.animeList(ctx, userID, sfw, listSource{
		kind: "top", ttl: s.ttl,
		key: func(pg int) string {
			return fmt.Sprintf("top:%s:%s:%s:p%d", dash(p.Type), dash(p.Filter), dash(p.Rating), pg)
		},
		fetch: func(ctx context.Context, pg int) (*jikan.Response[[]jikan.Anime], error) {
			return s.jikan.Top(ctx, jikan.ListQuery{Filter: p.Filter, Type: p.Type, Rating: p.Rating, Page: pg})
		},
	}, p.Page)
}

// SeasonNow serves /seasons/now.
func (s *Service) SeasonNow(ctx context.Context, userID string, sfw bool, p ListParams) (Page, error) {
	if err := validate("filter", p.Filter, animeTypes); err != nil {
		return Page{}, err
	}
	return s.animeList(ctx, userID, sfw, listSource{
		kind: "season", ttl: s.ttl,
		key: func(pg int) string { return fmt.Sprintf("season:now:%s:p%d", dash(p.Filter), pg) },
		fetch: func(ctx context.Context, pg int) (*jikan.Response[[]jikan.Anime], error) {
			return s.jikan.SeasonNow(ctx, jikan.ListQuery{Filter: p.Filter, Page: pg})
		},
	}, p.Page)
}

// SeasonUpcoming serves /seasons/upcoming.
func (s *Service) SeasonUpcoming(ctx context.Context, userID string, sfw bool, p ListParams) (Page, error) {
	if err := validate("filter", p.Filter, animeTypes); err != nil {
		return Page{}, err
	}
	return s.animeList(ctx, userID, sfw, listSource{
		kind: "season", ttl: s.ttl,
		key: func(pg int) string { return fmt.Sprintf("season:upcoming:%s:p%d", dash(p.Filter), pg) },
		fetch: func(ctx context.Context, pg int) (*jikan.Response[[]jikan.Anime], error) {
			return s.jikan.SeasonUpcoming(ctx, jikan.ListQuery{Filter: p.Filter, Page: pg})
		},
	}, p.Page)
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
	return s.animeList(ctx, userID, sfw, listSource{
		kind: "season", ttl: s.ttl,
		key: func(pg int) string { return fmt.Sprintf("season:%d:%s:%s:p%d", year, season, dash(p.Filter), pg) },
		fetch: func(ctx context.Context, pg int) (*jikan.Response[[]jikan.Anime], error) {
			return s.jikan.Season(ctx, year, season, jikan.ListQuery{Filter: p.Filter, Page: pg})
		},
	}, p.Page)
}

// Schedules serves /schedules?filter=<day>.
func (s *Service) Schedules(ctx context.Context, userID string, sfw bool, day string, pg int) (Page, error) {
	day = strings.ToLower(day)
	if err := validate("day", day, weekdays); err != nil {
		return Page{}, err
	}
	return s.animeList(ctx, userID, sfw, listSource{
		kind: "schedules", ttl: s.ttl,
		key: func(p int) string { return fmt.Sprintf("schedules:%s:p%d", dash(day), p) },
		fetch: func(ctx context.Context, p int) (*jikan.Response[[]jikan.Anime], error) {
			return s.jikan.Schedules(ctx, day, p, 0)
		},
	}, pg)
}

// Search serves /anime?q=...
// validateGenres accepts a comma-separated list of up to 5 positive MAL genre ids.
func validateGenres(v string) error {
	if v == "" {
		return nil
	}
	parts := strings.Split(v, ",")
	if len(parts) > 5 {
		return fmt.Errorf("%w: genres accepts at most 5 ids", ErrValidation)
	}
	for _, part := range parts {
		if n, err := strconv.Atoi(strings.TrimSpace(part)); err != nil || n <= 0 {
			return fmt.Errorf("%w: genres must be comma-separated positive integers", ErrValidation)
		}
	}
	return nil
}

func validateMinScore(v string) error {
	if v == "" {
		return nil
	}
	if f, err := strconv.ParseFloat(v, 64); err != nil || f < 0 || f > 10 {
		return fmt.Errorf("%w: minScore must be a number between 0 and 10", ErrValidation)
	}
	return nil
}

func (s *Service) Search(ctx context.Context, userID string, sfw bool, p SearchParams) (Page, error) {
	q := strings.Join(strings.Fields(strings.ToLower(p.Q)), " ")
	// Without a query this is a browse request (Discover): Jikan lists /anime filtered by
	// genre/status/order, so at least one filter must narrow the result.
	if q == "" {
		if p.Genres == "" && p.Status == "" && p.OrderBy == "" {
			return Page{}, fmt.Errorf("%w: q (3–100 characters) or a filter (genres, status, orderBy) is required", ErrValidation)
		}
	} else if n := len([]rune(q)); n < 3 || n > 100 {
		return Page{}, fmt.Errorf("%w: q must be 3–100 characters", ErrValidation)
	}
	if err := errors.Join(validate("type", p.Type, animeTypes), validate("status", p.Status, searchStatus),
		validate("orderBy", p.OrderBy, searchOrderBy), validate("sort", p.Sort, sortDirs),
		validateGenres(p.Genres), validateMinScore(p.MinScore)); err != nil {
		return Page{}, err
	}
	h := sha1.Sum([]byte(strings.Join([]string{q, p.Type, p.Status, p.OrderBy, p.Sort, p.Genres, p.MinScore}, "|"))) //nolint:gosec
	digest := hex.EncodeToString(h[:])
	return s.animeList(ctx, userID, sfw, listSource{
		kind: "search", ttl: s.searchTTL,
		key: func(pg int) string { return fmt.Sprintf("search:%s:p%d", digest, pg) },
		fetch: func(ctx context.Context, pg int) (*jikan.Response[[]jikan.Anime], error) {
			return s.jikan.Search(ctx, jikan.SearchQuery{Q: q, Type: p.Type, Status: p.Status, OrderBy: p.OrderBy,
				Sort: p.Sort, Genres: p.Genres, MinScore: p.MinScore, Page: pg})
		},
	}, p.Page)
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
func (s *Service) AnimeRecommendations(ctx context.Context, userID string, sfw bool, malID int) ([]model.AnimeRecommendation, cache.Result[payload], error) {
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
	// Recommendation entries carry no rating, so adult titles are recognised by their cached row.
	adult, err := s.adultIDs(ctx, sfw, ids)
	if err != nil {
		return nil, res, err
	}
	overlay, err := s.store.LibraryEntriesFor(ctx, userID, ids)
	if err != nil {
		return nil, res, err
	}
	out := make([]model.AnimeRecommendation, 0, len(recs))
	for _, r := range recs {
		if adult[r.Entry.MalID] {
			continue
		}
		out = append(out, model.AnimeRecommendation{Anime: recEntry(r.Entry, overlay), Votes: r.Votes})
	}
	return out, res, nil
}

// adultIDs returns the ids whose cached anime row is flagged adult; unknown ids are not flagged
// (nothing is cached about them yet). It returns an empty set when the user allows adult titles.
func (s *Service) adultIDs(ctx context.Context, sfw bool, ids []int) (map[int]bool, error) {
	if !sfw || len(ids) == 0 {
		return nil, nil
	}
	rows, err := s.store.GetAnimeBatch(ctx, ids)
	if err != nil {
		return nil, err
	}
	out := make(map[int]bool, len(rows))
	for id, row := range rows {
		if row.IsAdult {
			out[id] = true
		}
	}
	return out, nil
}

// LiveRecommendations serves /recommendations/anime without persistent caching. A short
// in-memory debounce absorbs duplicate requests (Jikan itself caches for 24 h, so nothing is
// lost); the last good page is kept to serve as STALE if Jikan fails.
func (s *Service) LiveRecommendations(ctx context.Context, userID string, sfw bool, pg int) ([]model.Recommendation, model.Pagination, cache.Status, error) {
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
			s.rememberLive(pg, fresh)
		}
	}

	var ids []int
	for _, r := range res.Data {
		for _, e := range r.Entry {
			ids = append(ids, e.MalID)
		}
	}
	// A recommendation pairs two titles: if either is a known adult title, drop the pair.
	adult, err := s.adultIDs(ctx, sfw, ids)
	if err != nil {
		return nil, model.Pagination{}, "", err
	}
	overlay, err := s.store.LibraryEntriesFor(ctx, userID, ids)
	if err != nil {
		return nil, model.Pagination{}, "", err
	}
	out := make([]model.Recommendation, 0, len(res.Data))
	for _, r := range res.Data {
		if hasAdultEntry(r.Entry, adult) {
			continue
		}
		rec := model.Recommendation{ID: r.MalID, Content: r.Content, Date: r.Date, User: model.RecommendationUser{Username: r.User.Username, URL: r.User.URL}}
		for _, e := range r.Entry {
			rec.Entries = append(rec.Entries, recEntry(e, overlay))
		}
		out = append(out, rec)
	}
	return out, paginationOf(res.Pagination, pg, len(out)), status, nil
}

// listSource describes one cached list endpoint, page by page: the cache key and the upstream
// call both depend on the page, so the SFW filter can walk forward when a page comes back empty.
type listSource struct {
	kind  string
	ttl   time.Duration
	key   func(page int) string
	fetch func(ctx context.Context, page int) (*jikan.Response[[]jikan.Anime], error)
}

// maxSFWPageWalk bounds how many pages one request may fetch while skipping fully filtered pages.
const maxSFWPageWalk = 3

// liveCacheMax bounds the in-memory live-feed micro-cache; each entry holds one Jikan page.
const liveCacheMax = 50

// rememberLive stores a freshly fetched page and evicts what the debounce can no longer use:
// nothing else ever shrinks the map, and `page` is client-controlled.
func (s *Service) rememberLive(pg int, res *jikan.Response[[]jikan.Recommendation]) {
	now := s.now()
	s.liveMu.Lock()
	defer s.liveMu.Unlock()
	s.live[pg] = liveEntry{at: now, res: res}
	if s.liveDebounce > 0 {
		cutoff := now.Add(-10 * s.liveDebounce)
		for k, e := range s.live {
			if k != pg && e.at.Before(cutoff) {
				delete(s.live, k)
			}
		}
	}
	for len(s.live) > liveCacheMax {
		oldest, oldestAt := 0, time.Time{}
		for k, e := range s.live {
			if k == pg {
				continue
			}
			if oldestAt.IsZero() || e.at.Before(oldestAt) {
				oldest, oldestAt = k, e.at
			}
		}
		if oldestAt.IsZero() {
			break
		}
		delete(s.live, oldest)
	}
}

// animeList runs the cache policy for an anime list, drops adult entries when the user keeps SFW on
// (Jikan's own sfw parameter is unreliable, so the filter is applied here) and applies the library
// overlay. A page left empty by the filter is skipped forward: the iOS loader only asks for more
// once a row appears, so returning an empty page with hasNextPage=true would strand it.
func (s *Service) animeList(ctx context.Context, userID string, sfw bool, src listSource, requested int) (Page, error) {
	current := page(requested)
	var (
		res   cache.Result[payload]
		items []model.AnimeSummary
		ids   []int
	)
	for walked := 0; walked < maxSFWPageWalk; walked++ {
		key := src.key(current)
		r, err := s.cachedPayload(ctx, key, src.kind, src.ttl, func(ctx context.Context) (json.RawMessage, *jikan.Pagination, error) {
			resp, err := src.fetch(ctx, current)
			if err != nil {
				return nil, nil, err
			}
			return resp.Raw, resp.Pagination, nil
		})
		if err != nil {
			return Page{}, err
		}
		res = r
		var list []jikan.Anime
		if err := json.Unmarshal(r.Value.Data, &list); err != nil {
			return Page{}, fmt.Errorf("decode cached list %s: %w", key, err)
		}
		ids = ids[:0]
		items = make([]model.AnimeSummary, 0, len(list))
		dropped := 0
		for _, a := range list {
			summary := anime.SummaryFromJikan(a)
			if sfw && summary.IsAdult {
				dropped++
				continue
			}
			ids = append(ids, a.MalID)
			items = append(items, summary)
		}
		hasNext := r.Value.Pagination != nil && r.Value.Pagination.HasNextPage
		// Stop on content, on an unfiltered page, at the end, or when the walk budget is spent, so that
		// `current` is always the page actually served (never one past the last fetch).
		if len(items) > 0 || dropped == 0 || !hasNext || walked+1 == maxSFWPageWalk {
			break
		}
		current++
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
	// total and lastVisiblePage stay upstream's pre-filter counts; page is the one actually served
	// (overriding Jikan's own current_page, which may disagree with the requested page).
	pagination := paginationOf(res.Value.Pagination, current, len(items))
	pagination.Page = current
	return Page{Items: items, Pagination: pagination, Meta: res}, nil
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

func hasAdultEntry(entries []jikan.RecommendationEntry, adult map[int]bool) bool {
	for _, e := range entries {
		if adult[e.MalID] {
			return true
		}
	}
	return false
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

func page(p int) int {
	if p < 1 {
		return 1
	}
	return p
}
