// Package jikan is a typed client for the Jikan v4 REST API (unofficial MyAnimeList API).
package jikan

import (
	"encoding/json"
	"time"
)

// Response wraps a decoded payload with the raw "data" element (persisted as-is) and pagination.
type Response[T any] struct {
	Data       T
	Raw        json.RawMessage // the "data" element exactly as Jikan sent it
	Pagination *Pagination
}

// Pagination is Jikan's pagination object.
type Pagination struct {
	LastVisiblePage int  `json:"last_visible_page"`
	HasNextPage     bool `json:"has_next_page"`
	CurrentPage     int  `json:"current_page"`
	Items           struct {
		Count   int `json:"count"`
		Total   int `json:"total"`
		PerPage int `json:"per_page"`
	} `json:"items"`
}

// ImageSet holds the three sizes MAL serves.
type ImageSet struct {
	ImageURL      string `json:"image_url"`
	SmallImageURL string `json:"small_image_url"`
	LargeImageURL string `json:"large_image_url"`
}

// Images groups the JPG and WebP variants.
type Images struct {
	JPG  ImageSet `json:"jpg"`
	WebP ImageSet `json:"webp"`
}

// Title is one of the alternative titles.
type Title struct {
	Type  string `json:"type"`
	Title string `json:"title"`
}

// DateRange is Jikan's aired object.
type DateRange struct {
	From   *time.Time `json:"from"`
	To     *time.Time `json:"to"`
	String string     `json:"string"`
}

// Broadcast is the weekly airing slot (fields may be null for finished/unknown shows).
type Broadcast struct {
	Day      *string `json:"day"`
	Time     *string `json:"time"`
	Timezone *string `json:"timezone"`
	String   *string `json:"string"`
}

// Named is a MAL entity reference (genre, studio, related entry...).
type Named struct {
	MalID int    `json:"mal_id"`
	Type  string `json:"type"`
	Name  string `json:"name"`
	URL   string `json:"url"`
}

// Trailer holds the YouTube trailer references.
type Trailer struct {
	YoutubeID *string `json:"youtube_id"`
	URL       *string `json:"url"`
	EmbedURL  *string `json:"embed_url"`
}

// RelationGroup groups related entries by relation kind (Sequel, Prequel, ...).
type RelationGroup struct {
	Relation string  `json:"relation"`
	Entry    []Named `json:"entry"`
}

// External is a named link (streaming platform, official site...).
type External struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

// Anime is the anime object shared by /anime/{id}/full and the list endpoints
// (lists omit relations/theme/external/streaming).
type Anime struct {
	MalID          int             `json:"mal_id"`
	URL            string          `json:"url"`
	Images         Images          `json:"images"`
	Trailer        Trailer         `json:"trailer"`
	Approved       bool            `json:"approved"`
	Titles         []Title         `json:"titles"`
	Title          string          `json:"title"`
	TitleEnglish   *string         `json:"title_english"`
	TitleJapanese  *string         `json:"title_japanese"`
	TitleSynonyms  []string        `json:"title_synonyms"`
	Type           *string         `json:"type"`
	Source         *string         `json:"source"`
	Episodes       *int            `json:"episodes"`
	Status         *string         `json:"status"`
	Airing         bool            `json:"airing"`
	Aired          DateRange       `json:"aired"`
	Duration       *string         `json:"duration"`
	Rating         *string         `json:"rating"`
	Score          *float64        `json:"score"`
	ScoredBy       *int            `json:"scored_by"`
	Rank           *int            `json:"rank"`
	Popularity     *int            `json:"popularity"`
	Members        *int            `json:"members"`
	Favorites      *int            `json:"favorites"`
	Synopsis       *string         `json:"synopsis"`
	Background     *string         `json:"background"`
	Season         *string         `json:"season"`
	Year           *int            `json:"year"`
	Broadcast      Broadcast       `json:"broadcast"`
	Producers      []Named         `json:"producers"`
	Licensors      []Named         `json:"licensors"`
	Studios        []Named         `json:"studios"`
	Genres         []Named         `json:"genres"`
	ExplicitGenres []Named         `json:"explicit_genres"`
	Themes         []Named         `json:"themes"`
	Demographics   []Named         `json:"demographics"`
	Relations      []RelationGroup `json:"relations"`
	External       []External      `json:"external"`
	Streaming      []External      `json:"streaming"`
}

// Episode is one entry of /anime/{id}/episodes.
type Episode struct {
	MalID         int        `json:"mal_id"`
	URL           *string    `json:"url"`
	Title         string     `json:"title"`
	TitleJapanese *string    `json:"title_japanese"`
	TitleRomanji  *string    `json:"title_romanji"`
	Aired         *time.Time `json:"aired"`
	Score         *float64   `json:"score"`
	Filler        bool       `json:"filler"`
	Recap         bool       `json:"recap"`
	ForumURL      *string    `json:"forum_url"`
}

// RecommendationEntry is the compact anime reference used by recommendation endpoints.
type RecommendationEntry struct {
	MalID  int    `json:"mal_id"`
	URL    string `json:"url"`
	Images Images `json:"images"`
	Title  string `json:"title"`
}

// AnimeRecommendation is one "users also liked" suggestion for a given anime.
type AnimeRecommendation struct {
	Entry RecommendationEntry `json:"entry"`
	URL   string              `json:"url"`
	Votes int                 `json:"votes"`
}

// Recommendation is one community recommendation pair from /recommendations/anime.
type Recommendation struct {
	MalID   string                `json:"mal_id"` // "A-B": both ids joined with a dash
	Entry   []RecommendationEntry `json:"entry"`
	Content string                `json:"content"`
	Date    *time.Time            `json:"date"`
	User    struct {
		URL      string `json:"url"`
		Username string `json:"username"`
	} `json:"user"`
}

// SeasonIndex is one year of /seasons.
type SeasonIndex struct {
	Year    int      `json:"year"`
	Seasons []string `json:"seasons"`
}
