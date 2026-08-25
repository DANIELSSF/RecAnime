package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// AnimeRow is the cached, normalized anime plus the raw Jikan payload.
type AnimeRow struct {
	MalID             int
	Title             string
	TitleEnglish      *string
	TitleJapanese     *string
	Type              *string
	Source            *string
	Episodes          *int
	Status            *string
	Airing            bool
	AiredFrom         *time.Time
	AiredTo           *time.Time
	Duration          *string
	Rating            *string
	Score             *float64
	ScoredBy          *int
	Rank              *int
	Popularity        *int
	Members           *int
	Favorites         *int
	Season            *string
	Year              *int
	BroadcastDay      *string
	BroadcastTime     *string
	BroadcastTimezone *string
	BroadcastString   *string
	ImageURL          *string
	ImageLargeURL     *string
	Genres            []string
	Studios           []string
	IsAdult           bool
	Raw               json.RawMessage
	FetchedAt         time.Time
}

// RelationRow links an anime to a related entry (anime or manga).
type RelationRow struct {
	FromMalID int
	Relation  string
	ToType    string
	ToMalID   int
	ToName    string
}

const animeColumns = `mal_id, title, title_english, title_japanese, type, source, episodes, status, airing,
	aired_from, aired_to, duration, rating, score, scored_by, rank, popularity, members, favorites,
	season, year, broadcast_day, broadcast_time, broadcast_timezone, broadcast_string,
	image_url, image_large_url, genres, studios, is_adult, raw, fetched_at`

func scanAnime(row pgx.Row) (AnimeRow, error) {
	var a AnimeRow
	err := row.Scan(&a.MalID, &a.Title, &a.TitleEnglish, &a.TitleJapanese, &a.Type, &a.Source, &a.Episodes, &a.Status, &a.Airing,
		&a.AiredFrom, &a.AiredTo, &a.Duration, &a.Rating, &a.Score, &a.ScoredBy, &a.Rank, &a.Popularity, &a.Members, &a.Favorites,
		&a.Season, &a.Year, &a.BroadcastDay, &a.BroadcastTime, &a.BroadcastTimezone, &a.BroadcastString,
		&a.ImageURL, &a.ImageLargeURL, &a.Genres, &a.Studios, &a.IsAdult, &a.Raw, &a.FetchedAt)
	return a, err
}

// GetAnime returns the cached anime, found=false when absent.
func (s *Store) GetAnime(ctx context.Context, malID int) (AnimeRow, bool, error) {
	a, err := scanAnime(s.pool.QueryRow(ctx, `SELECT `+animeColumns+` FROM recanime.anime WHERE mal_id = $1`, malID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return AnimeRow{}, false, nil
		}
		return AnimeRow{}, false, fmt.Errorf("get anime: %w", err)
	}
	return a, true, nil
}

// GetAnimeBatch returns the cached rows for ids (missing ids are simply absent).
func (s *Store) GetAnimeBatch(ctx context.Context, ids []int) (map[int]AnimeRow, error) {
	out := make(map[int]AnimeRow, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `SELECT `+animeColumns+` FROM recanime.anime WHERE mal_id = ANY($1)`, ids)
	if err != nil {
		return nil, fmt.Errorf("get anime batch: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		a, err := scanAnime(rows)
		if err != nil {
			return nil, fmt.Errorf("scan anime: %w", err)
		}
		out[a.MalID] = a
	}
	return out, rows.Err()
}

// UpsertAnimeFull stores the anime and replaces its relations in one transaction.
func (s *Store) UpsertAnimeFull(ctx context.Context, a AnimeRow, relations []RelationRow) error {
	return s.withTx(ctx, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO recanime.anime (`+animeColumns+`)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32)
			ON CONFLICT (mal_id) DO UPDATE SET
				title = EXCLUDED.title, title_english = EXCLUDED.title_english, title_japanese = EXCLUDED.title_japanese,
				type = EXCLUDED.type, source = EXCLUDED.source, episodes = EXCLUDED.episodes, status = EXCLUDED.status,
				airing = EXCLUDED.airing, aired_from = EXCLUDED.aired_from, aired_to = EXCLUDED.aired_to,
				duration = EXCLUDED.duration, rating = EXCLUDED.rating, score = EXCLUDED.score, scored_by = EXCLUDED.scored_by,
				rank = EXCLUDED.rank, popularity = EXCLUDED.popularity, members = EXCLUDED.members, favorites = EXCLUDED.favorites,
				season = EXCLUDED.season, year = EXCLUDED.year, broadcast_day = EXCLUDED.broadcast_day,
				broadcast_time = EXCLUDED.broadcast_time, broadcast_timezone = EXCLUDED.broadcast_timezone,
				broadcast_string = EXCLUDED.broadcast_string, image_url = EXCLUDED.image_url, image_large_url = EXCLUDED.image_large_url,
				genres = EXCLUDED.genres, studios = EXCLUDED.studios, is_adult = EXCLUDED.is_adult, raw = EXCLUDED.raw,
				fetched_at = EXCLUDED.fetched_at`,
			a.MalID, a.Title, a.TitleEnglish, a.TitleJapanese, a.Type, a.Source, a.Episodes, a.Status, a.Airing,
			a.AiredFrom, a.AiredTo, a.Duration, a.Rating, a.Score, a.ScoredBy, a.Rank, a.Popularity, a.Members, a.Favorites,
			a.Season, a.Year, a.BroadcastDay, a.BroadcastTime, a.BroadcastTimezone, a.BroadcastString,
			a.ImageURL, a.ImageLargeURL, a.Genres, a.Studios, a.IsAdult, a.Raw, a.FetchedAt)
		if err != nil {
			return fmt.Errorf("upsert anime %d: %w", a.MalID, err)
		}
		if _, err := tx.Exec(ctx, `DELETE FROM recanime.anime_relation WHERE from_mal_id = $1`, a.MalID); err != nil {
			return fmt.Errorf("clear relations %d: %w", a.MalID, err)
		}
		if len(relations) == 0 {
			return nil
		}
		batch := &pgx.Batch{}
		for _, r := range relations {
			batch.Queue(`INSERT INTO recanime.anime_relation (from_mal_id, relation, to_type, to_mal_id, to_name)
				VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING`, a.MalID, r.Relation, r.ToType, r.ToMalID, r.ToName)
		}
		br := tx.SendBatch(ctx, batch)
		for range relations {
			if _, err := br.Exec(); err != nil {
				_ = br.Close()
				return fmt.Errorf("insert relation %d: %w", a.MalID, err)
			}
		}
		return br.Close()
	})
}

// GetRelations returns the cached relations of one anime.
func (s *Store) GetRelations(ctx context.Context, malID int) ([]RelationRow, error) {
	rows, err := s.pool.Query(ctx, `SELECT from_mal_id, relation, to_type, to_mal_id, to_name
		FROM recanime.anime_relation WHERE from_mal_id = $1 ORDER BY relation, to_mal_id`, malID)
	if err != nil {
		return nil, fmt.Errorf("get relations: %w", err)
	}
	defer rows.Close()
	var out []RelationRow
	for rows.Next() {
		var r RelationRow
		if err := rows.Scan(&r.FromMalID, &r.Relation, &r.ToType, &r.ToMalID, &r.ToName); err != nil {
			return nil, fmt.Errorf("scan relation: %w", err)
		}
		out = append(out, r)
	}
	return out, rows.Err()
}
