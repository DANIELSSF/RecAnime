// Package model defines the JSON shapes (camelCase) the API returns to the apps.
// The Swift package RecAnimeKit decodes these one-to-one.
package model

import "time"

// Watch statuses.
const (
	StatusPending  = "pending"
	StatusWatching = "watching"
	StatusWatched  = "watched"
)

// Normalized airing states derived from MAL's status text.
const (
	AiringNow      = "airing"
	AiringFinished = "finished"
	AiringUpcoming = "upcoming"
	AiringUnknown  = "unknown"
)

// LibraryOverlay is the caller's relationship with an anime, embedded in summaries.
type LibraryOverlay struct {
	Status          string    `json:"status"`
	Favorite        bool      `json:"favorite"`
	EpisodesWatched int       `json:"episodesWatched"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

// AnimeSummary is the list/card representation.
type AnimeSummary struct {
	MalID         int             `json:"malId"`
	Title         string          `json:"title"`
	TitleEnglish  *string         `json:"titleEnglish"`
	ImageURL      string          `json:"imageUrl"`
	ImageLargeURL string          `json:"imageLargeUrl"`
	Type          *string         `json:"type"`
	Episodes      *int            `json:"episodes"`
	Status        *string         `json:"status"`
	AiringStatus  string          `json:"airingStatus"`
	Airing        bool            `json:"airing"`
	Score         *float64        `json:"score"`
	Rank          *int            `json:"rank"`
	Popularity    *int            `json:"popularity"`
	Members       *int            `json:"members"`
	Year          *int            `json:"year"`
	Season        *string         `json:"season"`
	Rating        *string         `json:"rating"`
	IsAdult       bool            `json:"isAdult"`
	Library       *LibraryOverlay `json:"library"`
}

// Link is a named URL (streaming service, external site).
type Link struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

// BroadcastInfo is the weekly airing slot.
type BroadcastInfo struct {
	Day      *string `json:"day"`
	Time     *string `json:"time"`
	Timezone *string `json:"timezone"`
	String   *string `json:"string"`
}

// RelationEntry is one related MAL entry.
type RelationEntry struct {
	MalID int    `json:"malId"`
	Type  string `json:"type"`
	Name  string `json:"name"`
}

// RelationGroup groups related entries by kind.
type RelationGroup struct {
	Relation string          `json:"relation"`
	Entries  []RelationEntry `json:"entries"`
}

// AnimeDetail is the full anime page.
type AnimeDetail struct {
	AnimeSummary
	TitleJapanese *string         `json:"titleJapanese"`
	Synopsis      *string         `json:"synopsis"`
	Background    *string         `json:"background"`
	Source        *string         `json:"source"`
	Duration      *string         `json:"duration"`
	ScoredBy      *int            `json:"scoredBy"`
	Favorites     *int            `json:"favorites"`
	AiredFrom     *time.Time      `json:"airedFrom"`
	AiredTo       *time.Time      `json:"airedTo"`
	AiredString   string          `json:"airedString"`
	Broadcast     *BroadcastInfo  `json:"broadcast"`
	TrailerURL    *string         `json:"trailerUrl"`
	MalURL        string          `json:"malUrl"`
	Genres        []string        `json:"genres"`
	Themes        []string        `json:"themes"`
	Demographics  []string        `json:"demographics"`
	Studios       []string        `json:"studios"`
	Producers     []string        `json:"producers"`
	Streaming     []Link          `json:"streaming"`
	External      []Link          `json:"external"`
	Relations     []RelationGroup `json:"relations"`
	Franchise     *Franchise      `json:"franchise"`
}

// FranchiseEntry is one season/movie in the prequel→sequel chain.
type FranchiseEntry struct {
	MalID              int           `json:"malId"`
	Title              string        `json:"title"`
	Position           int           `json:"position"` // 1-based order in the chain
	Resolved           bool          `json:"resolved"` // false when the anime is not cached yet (stub)
	RelationToPrevious string        `json:"relationToPrevious,omitempty"`
	Anime              *AnimeSummary `json:"anime"` // nil when unresolved
}

// SideEntry is a related anime outside the main chain (side story, spin-off...).
type SideEntry struct {
	Relation string `json:"relation"`
	MalID    int    `json:"malId"`
	Name     string `json:"name"`
}

// Franchise is the ordered chain around a requested anime plus the user's position in it.
type Franchise struct {
	Entries        []FranchiseEntry `json:"entries"`
	RequestedIndex int              `json:"requestedIndex"`
	CurrentIndex   int              `json:"currentIndex"`
	NextSeason     *FranchiseEntry  `json:"nextSeason"`
	Complete       bool             `json:"complete"`
	SideEntries    []SideEntry      `json:"sideEntries"`
}

// LibraryEntry is the stored per-user state.
type LibraryEntry struct {
	Status          string    `json:"status"`
	Favorite        bool      `json:"favorite"`
	EpisodesWatched int       `json:"episodesWatched"`
	CreatedAt       time.Time `json:"createdAt"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

// Progress summarizes episodes left.
type Progress struct {
	EpisodesTotal *int `json:"episodesTotal"`
	Remaining     *int `json:"remaining"`
}

// LibraryItem is an entry with its anime.
type LibraryItem struct {
	Anime    AnimeSummary `json:"anime"`
	Entry    LibraryEntry `json:"entry"`
	Progress Progress     `json:"progress"`
}

// LibraryGroups is the grouped "Mi lista" response.
type LibraryGroups struct {
	Watching  []LibraryItem `json:"watching"`
	Pending   []LibraryItem `json:"pending"`
	Watched   []LibraryItem `json:"watched"`
	Favorites []LibraryItem `json:"favorites"`
}

// Episode is one aired/planned episode.
type Episode struct {
	Number int        `json:"number"`
	Title  string     `json:"title"`
	Aired  *time.Time `json:"aired"`
	Filler bool       `json:"filler"`
	Recap  bool       `json:"recap"`
	Score  *float64   `json:"score"`
	URL    *string    `json:"url"`
}

// RecommendationEntry is the compact anime reference in recommendation payloads.
type RecommendationEntry struct {
	MalID    int             `json:"malId"`
	Title    string          `json:"title"`
	ImageURL string          `json:"imageUrl"`
	Library  *LibraryOverlay `json:"library"`
}

// Recommendation is one community pair from the live feed.
type Recommendation struct {
	ID      string                `json:"id"`
	Entries []RecommendationEntry `json:"entries"`
	Content string                `json:"content"`
	Date    *time.Time            `json:"date"`
	User    RecommendationUser    `json:"user"`
}

// RecommendationUser is the MAL user who wrote the recommendation.
type RecommendationUser struct {
	Username string `json:"username"`
	URL      string `json:"url"`
}

// AnimeRecommendation is a "users also liked" suggestion for one anime.
type AnimeRecommendation struct {
	Anime RecommendationEntry `json:"anime"`
	Votes int                 `json:"votes"`
}

// SeasonIndex is one year with its available seasons.
type SeasonIndex struct {
	Year    int      `json:"year"`
	Seasons []string `json:"seasons"`
}

// LatestEpisode is the newest episode we know (exact or estimated).
type LatestEpisode struct {
	Number  int        `json:"number"`
	AiredAt *time.Time `json:"airedAt"`
	Source  string     `json:"source"` // "jikan" | "estimate"
}

// ScheduleItem is one currently-watched, airing anime with its next airing time.
type ScheduleItem struct {
	MalID             int            `json:"malId"`
	Title             string         `json:"title"`
	ImageURL          string         `json:"imageUrl"`
	Broadcast         *BroadcastInfo `json:"broadcast"`
	NextAiringAt      *time.Time     `json:"nextAiringAt"`
	NextEpisodeNumber *int           `json:"nextEpisodeNumber"`
	LatestEpisode     *LatestEpisode `json:"latestEpisode"`
	EpisodesTotal     *int           `json:"episodesTotal"`
	EpisodesWatched   int            `json:"episodesWatched"`
	Remaining         *int           `json:"remaining"`
	Status            *string        `json:"status"`
	Airing            bool           `json:"airing"`
	Reason            string         `json:"reason,omitempty"` // e.g. "unknown_broadcast"
}

// Settings are the user's preferences.
type Settings struct {
	SFW      bool   `json:"sfw"`
	Timezone string `json:"timezone"`
}

// User is the authenticated account.
type User struct {
	ID          string    `json:"id"`
	Email       string    `json:"email"`
	DisplayName string    `json:"displayName"`
	AvatarURL   string    `json:"avatarUrl"`
	CreatedAt   time.Time `json:"createdAt"`
	Settings    Settings  `json:"settings"`
}

// Pagination mirrors Jikan's pagination in camelCase.
type Pagination struct {
	Page            int  `json:"page"`
	PerPage         int  `json:"perPage"`
	HasNextPage     bool `json:"hasNextPage"`
	LastVisiblePage int  `json:"lastVisiblePage"`
	Total           int  `json:"total"`
}
