package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// Watch statuses stored in library_entry.status.
const (
	StatusPending  = "pending"
	StatusWatching = "watching"
	StatusWatched  = "watched"
)

// LibraryEntry is one user's relationship with one anime.
type LibraryEntry struct {
	UserID          string
	MalID           int
	Status          string
	Favorite        bool
	EpisodesWatched int
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

// LibraryPatch updates only the non-nil fields; a missing row is created with defaults.
type LibraryPatch struct {
	Status          *string
	Favorite        *bool
	EpisodesWatched *int
}

// LibraryItem pairs an entry with its cached anime row.
type LibraryItem struct {
	Entry LibraryEntry
	Anime AnimeRow
}

const entryColumns = `user_id::text, mal_id, status, favorite, episodes_watched, created_at, updated_at`

func scanEntry(row pgx.Row) (LibraryEntry, error) {
	var e LibraryEntry
	err := row.Scan(&e.UserID, &e.MalID, &e.Status, &e.Favorite, &e.EpisodesWatched, &e.CreatedAt, &e.UpdatedAt)
	return e, err
}

// UpsertLibraryEntry creates or patches the entry. The anime row must already exist.
func (s *Store) UpsertLibraryEntry(ctx context.Context, userID string, malID int, patch LibraryPatch) (LibraryEntry, error) {
	e, err := scanEntry(s.pool.QueryRow(ctx, `
		INSERT INTO recanime.library_entry (user_id, mal_id, status, favorite, episodes_watched)
		VALUES ($1, $2, COALESCE($3, 'pending'), COALESCE($4, false), COALESCE($5, 0))
		ON CONFLICT (user_id, mal_id) DO UPDATE SET
			status           = COALESCE($3, recanime.library_entry.status),
			favorite         = COALESCE($4, recanime.library_entry.favorite),
			episodes_watched = COALESCE($5, recanime.library_entry.episodes_watched),
			updated_at       = now()
		RETURNING `+entryColumns, userID, malID, patch.Status, patch.Favorite, patch.EpisodesWatched))
	if err != nil {
		return LibraryEntry{}, fmt.Errorf("upsert library entry: %w", err)
	}
	return e, nil
}

// BatchPatch is one item of a multi-entry update.
type BatchPatch struct {
	MalID int
	Patch LibraryPatch
}

// UpsertLibraryEntries applies every patch in one transaction (all or nothing).
func (s *Store) UpsertLibraryEntries(ctx context.Context, userID string, items []BatchPatch) ([]LibraryEntry, error) {
	out := make([]LibraryEntry, 0, len(items))
	err := s.withTx(ctx, func(tx pgx.Tx) error {
		for _, it := range items {
			e, err := scanEntry(tx.QueryRow(ctx, `
				INSERT INTO recanime.library_entry (user_id, mal_id, status, favorite, episodes_watched)
				VALUES ($1, $2, COALESCE($3, 'pending'), COALESCE($4, false), COALESCE($5, 0))
				ON CONFLICT (user_id, mal_id) DO UPDATE SET
					status           = COALESCE($3, recanime.library_entry.status),
					favorite         = COALESCE($4, recanime.library_entry.favorite),
					episodes_watched = COALESCE($5, recanime.library_entry.episodes_watched),
					updated_at       = now()
				RETURNING `+entryColumns, userID, it.MalID, it.Patch.Status, it.Patch.Favorite, it.Patch.EpisodesWatched))
			if err != nil {
				return fmt.Errorf("batch upsert %d: %w", it.MalID, err)
			}
			out = append(out, e)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// AdjustEpisodes moves the progress absolutely (set) or relatively (delta) in a single
// statement, so concurrent deltas cannot lose an increment. total bounds the progress
// (nil = unknown). A new row starts as "watching"; a pending row switches to "watching"
// as soon as the resulting progress is positive; any other status is preserved.
func (s *Store) AdjustEpisodes(ctx context.Context, userID string, malID int, set, delta, total *int) (LibraryEntry, error) {
	// The clamped target, spelled out for the insert and the update branch.
	const target = `LEAST(GREATEST(COALESCE($3::int, recanime.library_entry.episodes_watched + COALESCE($4::int, 0)), 0), COALESCE($5::int, 2147483647))`
	e, err := scanEntry(s.pool.QueryRow(ctx, `
		INSERT INTO recanime.library_entry (user_id, mal_id, status, favorite, episodes_watched)
		VALUES ($1, $2, 'watching', false,
			LEAST(GREATEST(COALESCE($3::int, $4::int, 0), 0), COALESCE($5::int, 2147483647)))
		ON CONFLICT (user_id, mal_id) DO UPDATE SET
			episodes_watched = `+target+`,
			status = CASE WHEN recanime.library_entry.status = 'pending' AND `+target+` > 0
			              THEN 'watching' ELSE recanime.library_entry.status END,
			updated_at = now()
		RETURNING `+entryColumns, userID, malID, set, delta, total))
	if err != nil {
		return LibraryEntry{}, fmt.Errorf("adjust episodes: %w", err)
	}
	return e, nil
}

// GetLibraryEntry returns one entry or ErrNotFound.
func (s *Store) GetLibraryEntry(ctx context.Context, userID string, malID int) (LibraryEntry, error) {
	e, err := scanEntry(s.pool.QueryRow(ctx, `SELECT `+entryColumns+` FROM recanime.library_entry
		WHERE user_id = $1 AND mal_id = $2`, userID, malID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return LibraryEntry{}, ErrNotFound
		}
		return LibraryEntry{}, fmt.Errorf("get library entry: %w", err)
	}
	return e, nil
}

// DeleteLibraryEntry removes the entry; deleting a missing entry is not an error.
func (s *Store) DeleteLibraryEntry(ctx context.Context, userID string, malID int) error {
	if _, err := s.pool.Exec(ctx, `DELETE FROM recanime.library_entry WHERE user_id = $1 AND mal_id = $2`, userID, malID); err != nil {
		return fmt.Errorf("delete library entry: %w", err)
	}
	return nil
}

// LibraryEntriesFor returns the user's entries for the given anime ids (overlay for lists).
func (s *Store) LibraryEntriesFor(ctx context.Context, userID string, ids []int) (map[int]LibraryEntry, error) {
	out := make(map[int]LibraryEntry, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `SELECT `+entryColumns+` FROM recanime.library_entry
		WHERE user_id = $1 AND mal_id = ANY($2)`, userID, ids)
	if err != nil {
		return nil, fmt.Errorf("library entries for: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		e, err := scanEntry(rows)
		if err != nil {
			return nil, fmt.Errorf("scan entry: %w", err)
		}
		out[e.MalID] = e
	}
	return out, rows.Err()
}

// ListLibrary returns all of the user's items (entry + cached anime), newest updates first.
// status/favorite filter when non-nil.
func (s *Store) ListLibrary(ctx context.Context, userID string, status *string, favorite *bool) ([]LibraryItem, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT `+prefixed("e", entryColumns)+`, `+prefixed("a", animeColumns)+`
		FROM recanime.library_entry e
		JOIN recanime.anime a ON a.mal_id = e.mal_id
		WHERE e.user_id = $1
		  AND ($2::text IS NULL OR e.status = $2)
		  AND ($3::boolean IS NULL OR e.favorite = $3)
		ORDER BY e.updated_at DESC`, userID, status, favorite)
	if err != nil {
		return nil, fmt.Errorf("list library: %w", err)
	}
	defer rows.Close()
	return collectItems(rows)
}

// WatchingAiring returns the user's "watching" entries whose anime is airing or not yet aired.
func (s *Store) WatchingAiring(ctx context.Context, userID string) ([]LibraryItem, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT `+prefixed("e", entryColumns)+`, `+prefixed("a", animeColumns)+`
		FROM recanime.library_entry e
		JOIN recanime.anime a ON a.mal_id = e.mal_id
		WHERE e.user_id = $1 AND e.status = 'watching' AND (a.airing OR a.status = 'Not yet aired')
		ORDER BY e.updated_at DESC`, userID)
	if err != nil {
		return nil, fmt.Errorf("watching airing: %w", err)
	}
	defer rows.Close()
	return collectItems(rows)
}

func collectItems(rows pgx.Rows) ([]LibraryItem, error) {
	var out []LibraryItem
	for rows.Next() {
		var it LibraryItem
		e, a := &it.Entry, &it.Anime
		err := rows.Scan(&e.UserID, &e.MalID, &e.Status, &e.Favorite, &e.EpisodesWatched, &e.CreatedAt, &e.UpdatedAt,
			&a.MalID, &a.Title, &a.TitleEnglish, &a.TitleJapanese, &a.Type, &a.Source, &a.Episodes, &a.Status, &a.Airing,
			&a.AiredFrom, &a.AiredTo, &a.Duration, &a.Rating, &a.Score, &a.ScoredBy, &a.Rank, &a.Popularity, &a.Members, &a.Favorites,
			&a.Season, &a.Year, &a.BroadcastDay, &a.BroadcastTime, &a.BroadcastTimezone, &a.BroadcastString,
			&a.ImageURL, &a.ImageLargeURL, &a.Genres, &a.Studios, &a.IsAdult, &a.Raw, &a.FetchedAt)
		if err != nil {
			return nil, fmt.Errorf("scan library item: %w", err)
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// prefixed qualifies a comma-separated column list with a table alias.
func prefixed(alias, columns string) string {
	out := ""
	for i, c := range splitColumns(columns) {
		if i > 0 {
			out += ", "
		}
		out += alias + "." + c
	}
	return out
}

func splitColumns(s string) []string {
	var cols []string
	cur := ""
	for _, r := range s {
		switch r {
		case ',':
			cols = append(cols, trim(cur))
			cur = ""
		default:
			cur += string(r)
		}
	}
	if t := trim(cur); t != "" {
		cols = append(cols, t)
	}
	return cols
}

func trim(s string) string {
	start, end := 0, len(s)
	for start < end && (s[start] == ' ' || s[start] == '\n' || s[start] == '\t') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\n' || s[end-1] == '\t') {
		end--
	}
	return s[start:end]
}
