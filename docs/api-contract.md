# RecAnime API contract (v1)

Base URL: `http://<mac>.local:8080` in development, the Cloud Run URL in production.
All `/v1` routes require `Authorization: Bearer <Supabase access token>` (ES256, verified against the
project JWKS). Only allow-listed emails are accepted (`403 email_not_allowed`).

## Envelope

```json
{ "data": ..., "meta": { "cache": "HIT|MISS|STALE|LIVE", "fetchedAt": "...", "stale": false, "upstreamError": null },
  "pagination": { "page": 1, "perPage": 25, "hasNextPage": true, "lastVisiblePage": 40, "total": 1000 } }
```

Errors: `{ "error": { "code", "message", "requestId" } }` with codes `validation_error` (400), `unauthorized` (401),
`email_not_allowed` (403), `not_found` (404), `upstream_rate_limited` (503 + `Retry-After`),
`upstream_unavailable` (502), `internal` (500). The `X-Cache` header mirrors `meta.cache`.

## Cache policy

| Data | TTL |
|---|---|
| Anime detail, franchise relations | 12 h (`anime` table) |
| Top, seasons, schedules, episodes, per-anime recommendations, search | 12 h per key (`list_cache`) |
| Live recommendations feed (`/v1/recommendations`) | never persisted; 30 s in-memory debounce; last good page served as `STALE` on upstream failure |

Stale-while-error: when Jikan fails (429/5xx/network) and an expired copy exists, it is served with `meta.stale=true`.

## Endpoints

| Method & path | Query / body | `data` |
|---|---|---|
| `GET /healthz`, `GET /readyz` | — | `{status, version}` (no auth) |
| `GET /v1/me` | — | `User` (creates the user row on first call) |
| `PATCH /v1/me/settings` | `{sfw?, timezone?}` | `Settings` |
| `GET /v1/anime/{id}` | — | `AnimeDetail` (includes `franchise` computed from cached data only) |
| `GET /v1/anime/{id}/franchise` | `budget` (≤ server budget, default 4 extra Jikan calls) | `Franchise` |
| `GET /v1/anime/{id}/episodes` | `page` | `Episode[]` + pagination |
| `GET /v1/anime/{id}/recommendations` | — | `AnimeRecommendation[]` |
| `GET /v1/seasons` | — | `SeasonIndex[]` |
| `GET /v1/seasons/now`, `/upcoming`, `/{year}/{season}` | `filter=tv|movie|ova|special|ona|music`, `page` | `AnimeSummary[]` + pagination |
| `GET /v1/top` | `filter=airing|upcoming|bypopularity|favorite`, `type`, `rating`, `page` | `AnimeSummary[]` + pagination |
| `GET /v1/recommendations` | `page` | `Recommendation[]` + pagination (`LIVE`) |
| `GET /v1/search` | `q` (3–100 chars), `type`, `status`, `orderBy`, `sort`, `genres`, `minScore`, `page` | `AnimeSummary[]` + pagination |
| `GET /v1/schedules` | `day=monday..sunday|unknown|other`, `page` | `AnimeSummary[]` + pagination |
| `GET /v1/me/library` | none → `LibraryGroups`; `status`/`favorite` → `LibraryItem[]` | see right |
| `GET /v1/me/library/{malId}` | — | `LibraryItem` |
| `PUT /v1/me/library/{malId}` | `{status?, favorite?, episodesWatched?}` | `LibraryItem` (upsert; `watched` fills episodes) |
| `POST /v1/me/library/{malId}/episodes` | `{episodesWatched}` or `{delta}` | `LibraryItem` (clamped to the episode count) |
| `DELETE /v1/me/library/{malId}` | — | 204 |
| `GET /v1/me/schedule` | `includeEpisodes=true` (≤2 extra Jikan calls per anime) | `ScheduleItem[]`, `meta.stale` when a refresh failed |

`sfw` comes from the user's settings and is forwarded to Jikan for lists and search; the detail page always
answers and flags `isAdult`.

## Types

The authoritative definitions are the Go structs in `services/api/internal/model/model.go`; the JSON examples in
`services/api/testdata/golden/*.json` are regenerated with `UPDATE_GOLDEN=1 pnpm api:test:it` and decoded by the
Swift package tests (`packages/RecAnimeKit`).

Key shapes:

- `AnimeSummary`: `malId, title, titleEnglish, imageUrl, imageLargeUrl, type, episodes, status, airingStatus (airing|finished|upcoming|unknown), airing, score, rank, popularity, members, year, season, rating, isAdult, library {status, favorite, episodesWatched, updatedAt} | null`
- `AnimeDetail`: `AnimeSummary` + `titleJapanese, synopsis, background, source, duration, scoredBy, favorites, airedFrom, airedTo, airedString, broadcast {day, time, timezone, string}, trailerUrl, malUrl, genres[], themes[], demographics[], studios[], producers[], streaming[{name,url}], external[{name,url}], relations[{relation, entries[{malId,type,name}]}], franchise`
- `Franchise`: `entries[{malId, title, position, resolved, relationToPrevious, anime}], requestedIndex, currentIndex, nextSeason, complete, sideEntries[{relation, malId, name}]`
- `LibraryItem`: `anime (AnimeSummary), entry {status, favorite, episodesWatched, createdAt, updatedAt}, progress {episodesTotal, remaining}`
- `ScheduleItem`: `malId, title, imageUrl, broadcast, nextAiringAt (UTC), nextEpisodeNumber, latestEpisode {number, airedAt, source: jikan|estimate}, episodesTotal, episodesWatched, remaining, status, airing, reason?`
- `Recommendation`: `id ("A-B"), entries[{malId, title, imageUrl, library}], content, date, user {username, url}`
