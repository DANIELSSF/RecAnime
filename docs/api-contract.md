# RecAnime API contract (v1)

Base URL: `http://<mac>.local:8080` in development, the Cloud Run URL in production.
All `/v1` routes require `Authorization: Bearer <Supabase access token>` (ES256, verified against the
project JWKS). Only allow-listed emails are accepted (`403 email_not_allowed`).

## Envelope

```json
{ "data": ..., "meta": { "cache": "HIT|MISS|STALE|LIVE", "fetchedAt": "...", "stale": false, "upstreamError": null },
  "pagination": { "page": 1, "perPage": 25, "hasNextPage": true, "lastVisiblePage": 40, "total": 1000 } }
```

`meta` is optional: library (`/v1/me/library*`) and franchise responses carry no `meta` block at all.
`meta.upstreamError` is a class token, never a raw message: `rate_limited`, `upstream_unavailable`, `timeout`,
`not_found` or `error` (and `null` when nothing failed).

Pagination: `total` and `lastVisiblePage` are upstream's **pre-filter** counts, so they can exceed the number of
items actually returned once the SFW filter drops entries. `page` is the page actually served: when the filter
empties a page the API walks forward (up to 3 pages) until it finds rows, and reports the page it stopped on.

Errors: `{ "error": { "code", "message", "requestId" } }` with codes `validation_error` (400), `unauthorized` (401),
`email_not_allowed` (403), `not_found` (404), `method_not_allowed` (405), `client_closed` (499),
`upstream_rate_limited` (503 + `Retry-After`, mirroring upstream's own value clamped to 1–30 s),
`upstream_unavailable` (502), `timeout` (504, the 25 s request budget expired), `internal` (500).
The `X-Cache` header mirrors `meta.cache`; every response (success or error) carries `X-Request-Id`.

## Cache policy

| Data | TTL |
|---|---|
| Anime detail, franchise relations | 12 h (`anime` table) |
| Top, seasons, schedules, episodes, per-anime recommendations, search | 12 h per key (`list_cache`) |
| Live recommendations feed (`/v1/recommendations`) | never persisted; 30 s in-memory debounce (`LIVE_DEBOUNCE`, ≤50 pages kept); last good page served as `STALE` on upstream failure |
| `list_cache` retention | rows older than `LIST_CACHE_RETENTION` (default 168 h) are swept at boot and every 6 h; 0 disables |
| Schedule episode lookups | `SCHEDULE_EPISODE_BUDGET` (default 6) upstream episode fetches per `includeEpisodes=true` request; cache hits are free, and once the budget is spent the remaining rows fall back to the estimate with `meta.stale=true` |

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
| `GET /v1/top` | `filter=airing|upcoming|bypopularity|favorite`, `type=tv|movie|ova|special|ona|music|cm|pv|tv_special`, `rating=g|pg|pg13|r17|r|rx`, `page` | `AnimeSummary[]` + pagination |
| `GET /v1/recommendations` | `page` | `Recommendation[]` + pagination (`LIVE`) |
| `GET /v1/search` | `q` (3–100 chars; optional when `genres`, `status` or `orderBy` is set — that is the Discover browse), `type`, `status`, `orderBy`, `sort`, `genres` (≤5 MAL ids, comma-separated), `minScore` (0–10), `page` | `AnimeSummary[]` + pagination |
| `GET /v1/schedules` | `day=monday..sunday|unknown|other`, `page` | `AnimeSummary[]` + pagination |
| `GET /v1/me/library` | none → `LibraryGroups`; `status`/`favorite` → `LibraryItem[]` | see right |
| `GET /v1/me/library/{malId}` | — | `LibraryItem` |
| `PUT /v1/me/library/{malId}` | `{status?, favorite?, episodesWatched?}` | `LibraryItem` (upsert; `watched` fills episodes) |
| `PUT /v1/me/library/batch` | `{items:[{malId, status?, favorite?, episodesWatched?}]}` (1–50, no duplicate `malId`, applied atomically) | `LibraryItem[]` |
| `POST /v1/me/library/{malId}/episodes` | `{episodesWatched}` or `{delta}` (exactly one) | `LibraryItem` (applied in one SQL statement, clamped to `[0, episodes]`; progress on a `pending` entry starts it) |
| `DELETE /v1/me/library/{malId}` | — | 204 |
| `GET /v1/me/schedule` | `includeEpisodes=true` (≤2 extra Jikan calls per anime, `SCHEDULE_EPISODE_BUDGET` per request) | `ScheduleItem[]`, `meta.stale` when a refresh failed or the budget ran out |

`page` is 1–100 on every paginated endpoint (it is part of the cache key); anything larger is a
`validation_error`.

`sfw` comes from the user's settings and is applied **server-side** (Jikan's own `sfw` parameter is unreliable and
is never sent): lists, search, schedules and both recommendation feeds drop adult entries — feeds use the cached
`is_adult` of each entry, and a community recommendation is dropped when either of its two titles is known to be
adult. `rating=rx` is rejected while SFW is on. The detail endpoint always answers and flags `isAdult`.

## Types

The authoritative definitions are the Go structs in `services/api/internal/model/model.go`; the JSON examples in
`services/api/testdata/golden/*.json` are regenerated with `UPDATE_GOLDEN=1 pnpm api:test:it` and decoded by the
Swift package tests (`packages/RecAnimeKit`).

Key shapes:

- `AnimeSummary`: `malId, title, titleEnglish, imageUrl, imageLargeUrl, type, episodes, status, airingStatus (airing|finished|upcoming|unknown), airing, score, rank, popularity, members, year, season, rating, isAdult, library {status, favorite, episodesWatched, updatedAt} | null`
- `AnimeDetail`: `AnimeSummary` + `titleJapanese, synopsis, background, source, duration, scoredBy, favorites, airedFrom, airedTo, airedString, broadcast {day, time, timezone, string}, trailerUrl, trailerEmbedUrl, trailerImageUrl, trailerVideoId, malUrl, genres[], themes[], demographics[], studios[], producers[], streaming[{name,url}], external[{name,url}], relations[{relation, entries[{malId,type,name}]}], franchise`
- `Franchise`: `entries[{malId, title, position, resolved, relationToPrevious, anime}], requestedIndex, currentIndex, nextSeason, complete, sideEntries[{relation, malId, name}]`
- `LibraryItem`: `anime (AnimeSummary), entry {status, favorite, episodesWatched, createdAt, updatedAt}, progress {episodesTotal, remaining}` (no `meta` block)
- `ScheduleItem`: `malId, title, imageUrl, broadcast, nextAiringAt (UTC), nextEpisodeNumber, latestEpisode {number, airedAt, source: jikan|estimate}, episodesTotal, episodesWatched, remaining, status, airing, reason?`
- `Recommendation`: `id ("A-B"), entries[{malId, title, imageUrl, library}], content, date, user {username, url}`
