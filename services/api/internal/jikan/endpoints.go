package jikan

import (
	"context"
	"fmt"
	"net/url"
	"strconv"
)

// ListQuery holds the common list parameters.
type ListQuery struct {
	Filter string // top: airing|upcoming|bypopularity|favorite ; seasons: tv|movie|ova|special|ona|music
	Type   string // top: tv|movie|ova|special|ona|music|cm|pv|tv_special
	Rating string // g|pg|pg13|r17|r|rx
	Page   int
	Limit  int // 0 = Jikan default (25 max)
}

func (q ListQuery) values() url.Values {
	v := url.Values{}
	setIf(v, "filter", q.Filter)
	setIf(v, "type", q.Type)
	setIf(v, "rating", q.Rating)
	setPage(v, q.Page, q.Limit)
	return v
}

// SearchQuery mirrors GET /anime search parameters.
type SearchQuery struct {
	Q        string
	Type     string
	Status   string // airing|complete|upcoming
	OrderBy  string // mal_id|title|start_date|end_date|episodes|score|scored_by|rank|popularity|members|favorites
	Sort     string // asc|desc
	Genres   string // comma-separated ids
	MinScore string
	Page     int
	Limit    int
}

func (q SearchQuery) values() url.Values {
	v := url.Values{}
	setIf(v, "q", q.Q)
	setIf(v, "type", q.Type)
	setIf(v, "status", q.Status)
	setIf(v, "order_by", q.OrderBy)
	setIf(v, "sort", q.Sort)
	setIf(v, "genres", q.Genres)
	setIf(v, "min_score", q.MinScore)
	setPage(v, q.Page, q.Limit)
	return v
}

// AnimeFull returns /anime/{id}/full (includes relations, streaming, external).
func (c *Client) AnimeFull(ctx context.Context, id int) (*Response[Anime], error) {
	return get[Anime](ctx, c, fmt.Sprintf("/anime/%d/full", id), nil)
}

// AnimeRelations returns /anime/{id}/relations.
func (c *Client) AnimeRelations(ctx context.Context, id int) (*Response[[]RelationGroup], error) {
	return get[[]RelationGroup](ctx, c, fmt.Sprintf("/anime/%d/relations", id), nil)
}

// AnimeEpisodes returns one page of /anime/{id}/episodes.
func (c *Client) AnimeEpisodes(ctx context.Context, id, page int) (*Response[[]Episode], error) {
	v := url.Values{}
	if page > 1 {
		v.Set("page", strconv.Itoa(page))
	}
	return get[[]Episode](ctx, c, fmt.Sprintf("/anime/%d/episodes", id), v)
}

// AnimeRecommendations returns /anime/{id}/recommendations.
func (c *Client) AnimeRecommendations(ctx context.Context, id int) (*Response[[]AnimeRecommendation], error) {
	return get[[]AnimeRecommendation](ctx, c, fmt.Sprintf("/anime/%d/recommendations", id), nil)
}

// Top returns /top/anime.
func (c *Client) Top(ctx context.Context, q ListQuery) (*Response[[]Anime], error) {
	return get[[]Anime](ctx, c, "/top/anime", q.values())
}

// SeasonNow returns /seasons/now.
func (c *Client) SeasonNow(ctx context.Context, q ListQuery) (*Response[[]Anime], error) {
	return get[[]Anime](ctx, c, "/seasons/now", q.values())
}

// SeasonUpcoming returns /seasons/upcoming.
func (c *Client) SeasonUpcoming(ctx context.Context, q ListQuery) (*Response[[]Anime], error) {
	return get[[]Anime](ctx, c, "/seasons/upcoming", q.values())
}

// Season returns /seasons/{year}/{season}.
func (c *Client) Season(ctx context.Context, year int, season string, q ListQuery) (*Response[[]Anime], error) {
	return get[[]Anime](ctx, c, fmt.Sprintf("/seasons/%d/%s", year, url.PathEscape(season)), q.values())
}

// SeasonsIndex returns /seasons (available years and seasons).
func (c *Client) SeasonsIndex(ctx context.Context) (*Response[[]SeasonIndex], error) {
	return get[[]SeasonIndex](ctx, c, "/seasons", nil)
}

// Schedules returns /schedules for a weekday (monday..sunday, unknown, other).
// The SFW filter is applied server-side from cached ratings, not by Jikan's own parameter.
func (c *Client) Schedules(ctx context.Context, day string, page, limit int) (*Response[[]Anime], error) {
	v := url.Values{}
	setIf(v, "filter", day)
	setPage(v, page, limit)
	return get[[]Anime](ctx, c, "/schedules", v)
}

// Search returns /anime?q=...
func (c *Client) Search(ctx context.Context, q SearchQuery) (*Response[[]Anime], error) {
	return get[[]Anime](ctx, c, "/anime", q.values())
}

// RecommendationsFeed returns /recommendations/anime (recent community recommendations).
func (c *Client) RecommendationsFeed(ctx context.Context, page int) (*Response[[]Recommendation], error) {
	v := url.Values{}
	if page > 1 {
		v.Set("page", strconv.Itoa(page))
	}
	return get[[]Recommendation](ctx, c, "/recommendations/anime", v)
}
