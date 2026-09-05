package httpapi_test

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/danielssf/recanime/services/api/internal/anime"
	"github.com/danielssf/recanime/services/api/internal/auth"
	"github.com/danielssf/recanime/services/api/internal/cache"
	"github.com/danielssf/recanime/services/api/internal/catalog"
	"github.com/danielssf/recanime/services/api/internal/httpapi"
	"github.com/danielssf/recanime/services/api/internal/jikan"
	"github.com/danielssf/recanime/services/api/internal/library"
	"github.com/danielssf/recanime/services/api/internal/ratelimit"
	"github.com/danielssf/recanime/services/api/internal/schedule"
	"github.com/danielssf/recanime/services/api/internal/store"
	"github.com/danielssf/recanime/services/api/internal/testutil"
)

const devEmail = "dev@example.com"

type env struct {
	t       *testing.T
	srv     *httptest.Server
	jikan   *testutil.FakeJikan
	now     time.Time
	anime   *anime.Service
	catalog *catalog.Service
	sched   *schedule.Service
	coord   *cache.Coordinator
	pool    *pgxpool.Pool
}

// exec runs a statement against the test database (used to simulate rows the fixtures cannot express).
func (e *env) exec(sql string, args ...any) {
	e.t.Helper()
	if _, err := e.pool.Exec(context.Background(), sql, args...); err != nil {
		e.t.Fatalf("exec %q: %v", sql, err)
	}
}

// listFixture builds a Jikan list payload out of the cached full-anime fixtures.
func listFixture(t *testing.T, names ...string) []byte {
	t.Helper()
	var data []json.RawMessage
	for _, n := range names {
		var env struct {
			Data json.RawMessage `json:"data"`
		}
		if err := json.Unmarshal(testutil.ReadFixture(t, "jikan", n), &env); err != nil {
			t.Fatal(err)
		}
		data = append(data, env.Data)
	}
	body, _ := json.Marshal(map[string]any{
		"pagination": map[string]any{"last_visible_page": 1, "has_next_page": false, "current_page": 1,
			"items": map[string]int{"count": len(data), "total": len(data), "per_page": 25}},
		"data": data,
	})
	return body
}

func recommendationsFixture() []byte {
	entry := func(id int, title string) map[string]any {
		return map[string]any{"mal_id": id, "url": fmt.Sprintf("https://myanimelist.net/anime/%d", id), "title": title,
			"images": map[string]any{"jpg": map[string]string{"image_url": "https://cdn.example/x.jpg", "small_image_url": "", "large_image_url": ""}}}
	}
	body, _ := json.Marshal(map[string]any{
		"pagination": map[string]any{"last_visible_page": 20, "has_next_page": true},
		"data": []map[string]any{{
			"mal_id":  "52991-59978",
			"entry":   []map[string]any{entry(52991, "Sousou no Frieren"), entry(59978, "Sousou no Frieren 2nd Season")},
			"content": "If you liked the first season you will like the second.",
			"date":    "2026-08-20T00:00:00+00:00",
			"user":    map[string]string{"url": "https://myanimelist.net/profile/tester", "username": "tester"},
		}},
	})
	return body
}

func newEnv(t *testing.T, authCfg *httpapi.AuthConfig) *env {
	t.Helper()
	time.Local = time.UTC // deterministic golden fixtures
	pool := testutil.TestPool(t)
	fake := testutil.NewFakeJikan(t)
	fake.Route("/anime/52991/full", "anime_full_52991.json")
	fake.Route("/anime/59978/full", "anime_full_59978.json")
	fake.Route("/anime/52991/episodes", "anime_episodes_52991_p1.json")
	fake.Route("/seasons", "seasons_index.json")
	list := listFixture(t, "anime_full_52991.json", "anime_full_59978.json")
	for _, p := range []string{"/top/anime", "/seasons/now", "/seasons/upcoming", "/seasons/2023/fall", "/anime", "/schedules"} {
		fake.RouteBytes(p, list)
	}
	fake.RouteBytes("/recommendations/anime", recommendationsFixture())

	e := &env{t: t, jikan: fake, pool: pool, now: time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	limiter := ratelimit.New(1000, 60000)
	jk := jikan.New(fake.Server.URL, fake.Server.Client(), limiter, "test")
	e.coord = cache.NewCoordinator(jikan.IsTransient)
	e.coord.SetNow(e.clock)
	st := store.New(pool)
	e.anime = anime.NewService(st, jk, e.coord, 12*time.Hour, 4, logger)
	e.anime.SetNow(e.clock)
	e.catalog = catalog.NewService(st, jk, e.coord, 12*time.Hour, 12*time.Hour, 30*time.Second, logger)
	e.catalog.SetNow(e.clock)
	e.sched = schedule.NewService(st, e.anime, e.catalog, 6, logger)
	e.sched.SetNow(e.clock)

	cfg := httpapi.AuthConfig{DevBypass: true, DevBypassEmail: devEmail, Allowlist: auth.NewAllowlist([]string{devEmail, "second@example.com"})}
	if authCfg != nil {
		cfg = *authCfg
	}
	srv := httpapi.New(httpapi.Deps{
		Logger: logger, Pool: pool, Version: "test", Store: st, Anime: e.anime, Catalog: e.catalog,
		Library: library.NewService(st, e.anime), Schedule: e.sched, Auth: cfg, FranchiseBudget: 4,
	})
	e.srv = httptest.NewServer(srv)
	t.Cleanup(e.srv.Close)
	return e
}

func (e *env) clock() time.Time { return e.now }

type resp struct {
	status int
	header http.Header
	body   map[string]any
	raw    []byte
}

func (e *env) do(method, path string, body string, headers ...string) resp {
	e.t.Helper()
	var rdr io.Reader
	if body != "" {
		rdr = strings.NewReader(body)
	}
	req, err := http.NewRequestWithContext(context.Background(), method, e.srv.URL+path, rdr)
	if err != nil {
		e.t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	res, err := e.srv.Client().Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer func() { _ = res.Body.Close() }()
	raw, _ := io.ReadAll(res.Body)
	out := resp{status: res.StatusCode, header: res.Header, raw: raw}
	if len(raw) > 0 {
		_ = json.Unmarshal(raw, &out.body)
	}
	return out
}

func (r resp) data() map[string]any {
	d, _ := r.body["data"].(map[string]any)
	return d
}

func (r resp) meta() map[string]any {
	m, _ := r.body["meta"].(map[string]any)
	return m
}

func (r resp) errCode() string {
	e, _ := r.body["error"].(map[string]any)
	c, _ := e["code"].(string)
	return c
}

func TestAnimeDetailCachePolicy(t *testing.T) {
	e := newEnv(t, nil)

	r := e.do("GET", "/v1/anime/52991", "")
	if r.status != 200 || r.header.Get("X-Cache") != "MISS" || r.data()["title"] != "Sousou no Frieren" {
		t.Fatalf("first detail: status=%d cache=%s body=%s", r.status, r.header.Get("X-Cache"), r.raw[:200])
	}
	if r.data()["airingStatus"] != "finished" || r.data()["library"] != nil {
		t.Fatalf("unexpected normalized fields: %v %v", r.data()["airingStatus"], r.data()["library"])
	}
	fr, _ := r.data()["franchise"].(map[string]any)
	entries, _ := fr["entries"].([]any)
	if len(entries) != 2 || fr["complete"] != false { // sequel 59978 is not cached yet -> unresolved stub
		t.Fatalf("zero-budget franchise should include an unresolved sequel stub: %v", fr)
	}

	r = e.do("GET", "/v1/anime/52991", "")
	if r.header.Get("X-Cache") != "HIT" || e.jikan.Hits("/anime/52991/full") != 1 {
		t.Fatalf("second detail must be a HIT without Jikan calls (hits=%d)", e.jikan.Hits("/anime/52991/full"))
	}

	e.now = e.now.Add(13 * time.Hour)
	r = e.do("GET", "/v1/anime/52991", "")
	if r.header.Get("X-Cache") != "MISS" || e.jikan.Hits("/anime/52991/full") != 2 {
		t.Fatalf("after 12h the row must be refreshed (cache=%s hits=%d)", r.header.Get("X-Cache"), e.jikan.Hits("/anime/52991/full"))
	}

	// Upstream failure with an expired row -> STALE, not an error.
	e.now = e.now.Add(13 * time.Hour)
	e.jikan.FailNext(2, http.StatusServiceUnavailable, "")
	r = e.do("GET", "/v1/anime/52991", "")
	if r.status != 200 || r.header.Get("X-Cache") != "STALE" || r.meta()["stale"] != true {
		t.Fatalf("expected STALE fallback, got status=%d cache=%s meta=%v", r.status, r.header.Get("X-Cache"), r.meta())
	}
	// upstreamError is a class token, never the raw (internal) error string.
	if r.meta()["upstreamError"] != "upstream_unavailable" {
		t.Fatalf("upstreamError must be a token, got %v", r.meta()["upstreamError"])
	}

	// Unknown id -> 404 and negatively cached.
	r = e.do("GET", "/v1/anime/424242", "")
	if r.status != 404 || r.errCode() != "not_found" {
		t.Fatalf("expected 404 not_found, got %d %s", r.status, r.raw)
	}
	e.do("GET", "/v1/anime/424242", "")
	if e.jikan.Hits("/anime/424242/full") != 1 {
		t.Fatalf("404 must be negatively cached, got %d hits", e.jikan.Hits("/anime/424242/full"))
	}
}

func TestFranchiseWithBudgetResolvesChain(t *testing.T) {
	e := newEnv(t, nil)
	r := e.do("GET", "/v1/anime/52991/franchise?budget=4", "")
	if r.status != 200 {
		t.Fatalf("franchise: %d %s", r.status, r.raw)
	}
	d := r.data()
	entries, _ := d["entries"].([]any)
	// S1 -> S2 (fetched with the budget) -> the movie sequel, which the fake Jikan does not
	// know, so it stays an unresolved stub and the chain is reported as incomplete.
	if len(entries) != 3 || d["complete"] != false || d["requestedIndex"] != float64(0) {
		t.Fatalf("expected a 3-entry chain ending in a stub, got %s", r.raw)
	}
	second, _ := entries[1].(map[string]any)
	if second["malId"] != float64(59978) || second["resolved"] != true || second["relationToPrevious"] != "Sequel" {
		t.Fatalf("unexpected second entry: %v", second)
	}
	third, _ := entries[2].(map[string]any)
	if third["resolved"] != false || third["anime"] != nil {
		t.Fatalf("unexpected third entry: %v", third)
	}
	if e.jikan.Hits("/anime/59978/full") != 1 {
		t.Fatalf("the sequel must be fetched exactly once, got %d", e.jikan.Hits("/anime/59978/full"))
	}
	if next, _ := d["nextSeason"].(map[string]any); next == nil || next["malId"] != float64(59978) {
		t.Fatalf("nextSeason should be the sequel: %v", d["nextSeason"])
	}
	side, _ := d["sideEntries"].([]any)
	if len(side) == 0 {
		t.Fatalf("side stories should be listed: %s", r.raw)
	}
}

func TestLibraryFlow(t *testing.T) {
	e := newEnv(t, nil)

	r := e.do("PUT", "/v1/me/library/52991", `{"status":"watching","episodesWatched":3,"favorite":true}`)
	if r.status != 200 {
		t.Fatalf("put: %d %s", r.status, r.raw)
	}
	entry, _ := r.data()["entry"].(map[string]any)
	progress, _ := r.data()["progress"].(map[string]any)
	if entry["status"] != "watching" || entry["episodesWatched"] != float64(3) || entry["favorite"] != true || progress["remaining"] != float64(25) {
		t.Fatalf("unexpected entry/progress: %v %v", entry, progress)
	}
	if e.jikan.Hits("/anime/52991/full") != 1 {
		t.Fatal("library upsert must fetch and cache the anime once")
	}

	r = e.do("POST", "/v1/me/library/52991/episodes", `{"delta":1}`)
	if entry, _ := r.data()["entry"].(map[string]any); r.status != 200 || entry["episodesWatched"] != float64(4) {
		t.Fatalf("delta +1: %d %s", r.status, r.raw)
	}
	r = e.do("POST", "/v1/me/library/52991/episodes", `{"episodesWatched":99}`)
	if entry, _ := r.data()["entry"].(map[string]any); entry["episodesWatched"] != float64(28) {
		t.Fatalf("episodes must be clamped to the total: %s", r.raw)
	}
	r = e.do("POST", "/v1/me/library/52991/episodes", `{"delta":1,"episodesWatched":1}`)
	if r.status != 400 || r.errCode() != "validation_error" {
		t.Fatalf("delta and absolute together must fail: %d %s", r.status, r.raw)
	}

	r = e.do("PUT", "/v1/me/library/59978", `{"status":"watched"}`)
	if entry, _ := r.data()["entry"].(map[string]any); r.status != 200 || entry["episodesWatched"].(float64) <= 0 {
		t.Fatalf("watched must complete episodes: %d %s", r.status, r.raw)
	}

	r = e.do("GET", "/v1/me/library", "")
	watching, _ := r.data()["watching"].([]any)
	watched, _ := r.data()["watched"].([]any)
	favorites, _ := r.data()["favorites"].([]any)
	if len(watching) != 1 || len(watched) != 1 || len(favorites) != 1 {
		t.Fatalf("grouped library: %s", r.raw)
	}
	r = e.do("GET", "/v1/me/library?status=watched", "")
	if items, _ := r.body["data"].([]any); len(items) != 1 {
		t.Fatalf("flat filtered library: %s", r.raw)
	}

	// Overlay appears on catalog lists and the detail page.
	r = e.do("GET", "/v1/top", "")
	items, _ := r.body["data"].([]any)
	first, _ := items[0].(map[string]any)
	if r.status != 200 || len(items) != 2 || first["library"] == nil {
		t.Fatalf("top overlay: %d %s", r.status, r.raw[:300])
	}
	if pg, _ := r.body["pagination"].(map[string]any); pg["perPage"] != float64(25) || pg["hasNextPage"] != false {
		t.Fatalf("pagination: %v", pg)
	}

	// Second user sees an empty library (data is per user).
	r = e.do("GET", "/v1/me/library", "", "X-Dev-User", "second@example.com")
	if watching, _ := r.data()["watching"].([]any); len(watching) != 0 {
		t.Fatalf("second user must not see the first user's entries: %s", r.raw)
	}

	r = e.do("DELETE", "/v1/me/library/52991", "")
	if r.status != 204 {
		t.Fatalf("delete: %d", r.status)
	}
	r = e.do("GET", "/v1/me/library/52991", "")
	if r.status != 404 {
		t.Fatalf("deleted entry must be gone: %d", r.status)
	}
}

func TestLibraryBatch(t *testing.T) {
	e := newEnv(t, nil)
	r := e.do("PUT", "/v1/me/library/batch", `{"items":[{"malId":52991,"status":"watched"},{"malId":59978,"status":"watching","episodesWatched":0}]}`)
	if r.status != 200 {
		t.Fatalf("batch: %d %s", r.status, r.raw)
	}
	items, _ := r.body["data"].([]any)
	if len(items) != 2 {
		t.Fatalf("expected 2 items, got %s", r.raw)
	}
	first, _ := items[0].(map[string]any)
	entry, _ := first["entry"].(map[string]any)
	if entry["status"] != "watched" || entry["episodesWatched"] != float64(28) {
		t.Fatalf("watched must fill episodes in a batch: %v", entry)
	}
	r = e.do("GET", "/v1/me/library", "")
	if watched, _ := r.data()["watched"].([]any); len(watched) != 1 {
		t.Fatalf("grouped after batch: %s", r.raw)
	}
	if watching, _ := r.data()["watching"].([]any); len(watching) != 1 {
		t.Fatalf("grouped after batch: %s", r.raw)
	}
	// Atomic: a bad status in the second item leaves the first untouched.
	r = e.do("PUT", "/v1/me/library/batch", `{"items":[{"malId":52991,"status":"pending"},{"malId":59978,"status":"binge"}]}`)
	if r.status != 400 {
		t.Fatalf("invalid batch must fail: %d", r.status)
	}
	r = e.do("GET", "/v1/me/library/52991", "")
	if entry, _ := r.data()["entry"].(map[string]any); entry["status"] != "watched" {
		t.Fatalf("failed batch must not apply partially: %v", entry)
	}
	if r := e.do("PUT", "/v1/me/library/batch", `{"items":[]}`); r.status != 400 {
		t.Fatalf("empty batch: %d", r.status)
	}
}

func TestCatalogAndLiveFeed(t *testing.T) {
	e := newEnv(t, nil)
	for _, path := range []string{"/v1/seasons/now", "/v1/seasons/upcoming", "/v1/seasons/2023/fall", "/v1/search?q=frieren", "/v1/schedules?day=friday", "/v1/seasons", "/v1/anime/52991/episodes"} {
		r := e.do("GET", path, "")
		if r.status != 200 || r.header.Get("X-Cache") != "MISS" {
			t.Fatalf("%s: status=%d cache=%s body=%s", path, r.status, r.header.Get("X-Cache"), r.raw[:min(len(r.raw), 200)])
		}
		r = e.do("GET", path, "")
		if r.header.Get("X-Cache") != "HIT" {
			t.Fatalf("%s: second call must HIT", path)
		}
	}
	if r := e.do("GET", "/v1/search?q=ab", ""); r.status != 400 {
		t.Fatalf("short query must be rejected: %d", r.status)
	}
	if r := e.do("GET", "/v1/search", ""); r.status != 400 {
		t.Fatalf("browse without any filter must be rejected: %d", r.status)
	}
	if r := e.do("GET", "/v1/search?genres=1,x", ""); r.status != 400 {
		t.Fatalf("bad genres must be rejected: %d", r.status)
	}
	if r := e.do("GET", "/v1/search?genres=1&orderBy=score&sort=desc", ""); r.status != 200 || r.header.Get("X-Cache") != "MISS" {
		t.Fatalf("genre browse: %d %s %s", r.status, r.header.Get("X-Cache"), r.raw[:min(len(r.raw), 200)])
	}
	if r := e.do("GET", "/v1/seasons/2023/monsoon", ""); r.status != 400 {
		t.Fatalf("bad season must be rejected: %d", r.status)
	}
	if r := e.do("GET", "/v1/top?filter=bogus", ""); r.status != 400 || r.errCode() != "validation_error" {
		t.Fatalf("bad filter: %d %s", r.status, r.raw)
	}

	r := e.do("GET", "/v1/recommendations", "")
	if r.status != 200 || r.header.Get("X-Cache") != "LIVE" {
		t.Fatalf("live feed: %d %s", r.status, r.header.Get("X-Cache"))
	}
	items, _ := r.body["data"].([]any)
	rec, _ := items[0].(map[string]any)
	entries, _ := rec["entries"].([]any)
	if rec["id"] != "52991-59978" || len(entries) != 2 {
		t.Fatalf("unexpected recommendation: %v", rec)
	}
	e.do("GET", "/v1/recommendations", "")
	if e.jikan.Hits("/recommendations/anime") != 1 {
		t.Fatalf("debounce should absorb the immediate repeat, got %d hits", e.jikan.Hits("/recommendations/anime"))
	}
	e.now = e.now.Add(time.Minute)
	e.do("GET", "/v1/recommendations", "")
	if e.jikan.Hits("/recommendations/anime") != 2 {
		t.Fatalf("after the debounce window the feed must be fetched live again, got %d hits", e.jikan.Hits("/recommendations/anime"))
	}
	e.now = e.now.Add(time.Minute)
	e.jikan.FailNext(2, http.StatusBadGateway, "")
	r = e.do("GET", "/v1/recommendations", "")
	if r.status != 200 || r.header.Get("X-Cache") != "STALE" {
		t.Fatalf("live feed must serve the last good page as STALE on upstream failure: %d %s", r.status, r.header.Get("X-Cache"))
	}
}

func TestScheduleEndpoint(t *testing.T) {
	e := newEnv(t, nil)
	e.do("PUT", "/v1/me/library/59978", `{"status":"watching","episodesWatched":2}`)
	r := e.do("GET", "/v1/me/schedule", "")
	if r.status != 200 {
		t.Fatalf("schedule: %d %s", r.status, r.raw)
	}
	items, _ := r.body["data"].([]any)
	var body struct {
		Data struct {
			Status string `json:"status"`
			Airing bool   `json:"airing"`
		} `json:"data"`
	}
	_ = json.Unmarshal(e.do("GET", "/v1/anime/59978", "").raw, &body)
	if body.Data.Airing && len(items) != 1 {
		t.Fatalf("an airing watched anime must appear in the schedule: %s", r.raw)
	}
	if !body.Data.Airing && len(items) != 0 {
		t.Fatalf("finished anime must not appear in the schedule: %s", r.raw)
	}
}

func TestSettings(t *testing.T) {
	e := newEnv(t, nil)
	r := e.do("GET", "/v1/me", "")
	if r.status != 200 || r.data()["email"] != devEmail {
		t.Fatalf("me: %d %s", r.status, r.raw)
	}
	if settings, _ := r.data()["settings"].(map[string]any); settings["sfw"] != true {
		t.Fatalf("default sfw must be true: %v", settings)
	}
	r = e.do("PATCH", "/v1/me/settings", `{"sfw":false,"timezone":"America/Bogota"}`)
	if r.status != 200 || r.data()["sfw"] != false || r.data()["timezone"] != "America/Bogota" {
		t.Fatalf("patch settings: %d %s", r.status, r.raw)
	}
	if r := e.do("PATCH", "/v1/me/settings", `{"timezone":"Mars/Olympus"}`); r.status != 400 {
		t.Fatalf("bad timezone must be rejected: %d", r.status)
	}
	if r := e.do("PATCH", "/v1/me/settings", `{}`); r.status != 400 {
		t.Fatalf("empty patch must be rejected: %d", r.status)
	}
}

func TestJWTAuthentication(t *testing.T) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	jwks := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		b64 := func(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }
		point, _ := key.PublicKey.Bytes() // 0x04 || X || Y
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []map[string]any{{"kty": "EC", "kid": "k1", "use": "sig", "alg": "ES256", "crv": "P-256",
			"x": b64(point[1:33]), "y": b64(point[33:65])}}})
	}))
	t.Cleanup(jwks.Close)
	const issuer = "https://testref.supabase.co/auth/v1"
	verifier := auth.NewVerifier(auth.NewKeySet(jwks.URL, jwks.Client()), issuer)
	e := newEnv(t, &httpapi.AuthConfig{Verifier: verifier, Allowlist: auth.NewAllowlist([]string{"allowed@example.com"})})

	mint := func(email string, exp time.Time) string {
		tok := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.MapClaims{
			"iss": issuer, "aud": "authenticated", "sub": "0b1c2d3e-4f50-4a6b-8c7d-9e0f1a2b3c4d", "exp": exp.Unix(), "iat": time.Now().Unix(),
			"role": "authenticated", "email": email, "user_metadata": map[string]any{"full_name": "Allowed User"},
		})
		tok.Header["kid"] = "k1"
		s, err := tok.SignedString(key)
		if err != nil {
			t.Fatal(err)
		}
		return s
	}

	if r := e.do("GET", "/v1/me", ""); r.status != 401 || r.errCode() != "unauthorized" {
		t.Fatalf("missing token: %d %s", r.status, r.raw)
	}
	if r := e.do("GET", "/v1/me", "", "Authorization", "Bearer garbage"); r.status != 401 {
		t.Fatalf("garbage token: %d", r.status)
	}
	if r := e.do("GET", "/v1/me", "", "Authorization", "Bearer "+mint("allowed@example.com", time.Now().Add(-time.Hour))); r.status != 401 {
		t.Fatalf("expired token: %d", r.status)
	}
	if r := e.do("GET", "/v1/me", "", "Authorization", "Bearer "+mint("stranger@example.com", time.Now().Add(time.Hour))); r.status != 403 || r.errCode() != "email_not_allowed" {
		t.Fatalf("non-allowlisted: %d %s", r.status, r.raw)
	}
	r := e.do("GET", "/v1/me", "", "Authorization", "Bearer "+mint("allowed@example.com", time.Now().Add(time.Hour)))
	if r.status != 200 || r.data()["email"] != "allowed@example.com" || r.data()["displayName"] != "Allowed User" {
		t.Fatalf("valid token: %d %s", r.status, r.raw)
	}
	if r := e.do("GET", "/healthz", ""); r.status != 200 {
		t.Fatalf("health must not require auth: %d", r.status)
	}
}

// episodesFixture builds a small /anime/{id}/episodes payload (the repo only ships one).
func episodesFixture(count int, from time.Time) []byte {
	data := make([]map[string]any, 0, count)
	for i := 1; i <= count; i++ {
		data = append(data, map[string]any{
			"mal_id": i,
			"url":    fmt.Sprintf("https://myanimelist.net/anime/59978/episode/%d", i),
			"title":  fmt.Sprintf("Episode %d", i),
			"aired":  from.AddDate(0, 0, 7*(i-1)).Format(time.RFC3339),
			"filler": false,
			"recap":  false,
		})
	}
	body, _ := json.Marshal(map[string]any{
		"pagination": map[string]any{"last_visible_page": 1, "has_next_page": false},
		"data":       data,
	})
	return body
}

// TestScheduleEpisodeBudget: includeEpisodes costs up to two Jikan calls per anime, so a long
// watch list on a cold cache could blow the 25 s request budget. Past the budget the schedule
// falls back to the weekly estimate and says so with meta.stale.
func TestScheduleEpisodeBudget(t *testing.T) {
	e := newEnv(t, nil)
	e.jikan.RouteBytes("/anime/59978/episodes", episodesFixture(3, time.Date(2026, 1, 16, 0, 0, 0, 0, time.UTC)))
	e.sched.SetEpisodeBudget(1)

	e.do("PUT", "/v1/me/library/52991", `{"status":"watching","episodesWatched":1}`)
	e.do("PUT", "/v1/me/library/59978", `{"status":"watching","episodesWatched":1}`)
	// Both fixtures are finished shows; the schedule only lists airing ones.
	e.exec(`UPDATE recanime.anime SET airing = true WHERE mal_id = ANY($1)`, []int{52991, 59978})

	r := e.do("GET", "/v1/me/schedule?includeEpisodes=true", "")
	if r.status != 200 {
		t.Fatalf("schedule: %d %s", r.status, r.raw)
	}
	items, _ := r.body["data"].([]any)
	if len(items) != 2 {
		t.Fatalf("expected both watched shows, got %s", r.raw)
	}
	sources := map[string]int{}
	for _, it := range items {
		item, _ := it.(map[string]any)
		latest, _ := item["latestEpisode"].(map[string]any)
		if latest == nil {
			t.Fatalf("every item needs a latest episode: %v", item)
		}
		source, _ := latest["source"].(string)
		sources[source]++
	}
	if sources["jikan"] != 1 || sources["estimate"] != 1 {
		t.Fatalf("a budget of 1 must serve one exact and one estimated item, got %v", sources)
	}
	if r.meta()["stale"] != true {
		t.Fatalf("an exhausted budget must be reported as stale: %v", r.meta())
	}

	// The budget only counts upstream calls: once cached, both items are exact again.
	r = e.do("GET", "/v1/me/schedule?includeEpisodes=true", "")
	items, _ = r.body["data"].([]any)
	exact := 0
	for _, it := range items {
		item, _ := it.(map[string]any)
		latest, _ := item["latestEpisode"].(map[string]any)
		if latest["source"] == "jikan" {
			exact++
		}
	}
	if exact != 2 {
		t.Fatalf("cache hits must be free, got %d exact items: %s", exact, r.raw)
	}
}

// animeRecommendationsFixture is a /anime/{id}/recommendations payload pointing at 59978.
func animeRecommendationsFixture() []byte {
	body, _ := json.Marshal(map[string]any{
		"data": []map[string]any{{
			"entry": map[string]any{"mal_id": 59978, "url": "https://myanimelist.net/anime/59978", "title": "Sousou no Frieren 2nd Season",
				"images": map[string]any{"jpg": map[string]string{"image_url": "https://cdn.example/x.jpg"}}},
			"url": "https://myanimelist.net/recommendations/anime/52991-59978", "votes": 12,
		}},
	})
	return body
}

// TestRecommendationsRespectSFW: recommendation entries carry no rating, so adult titles used to
// reach users with sfw=true through both feeds.
func TestRecommendationsRespectSFW(t *testing.T) {
	e := newEnv(t, nil)
	e.jikan.RouteBytes("/anime/52991/recommendations", animeRecommendationsFixture())

	// Cache 59978 and flag it adult the way a real Rx-rated row would be.
	if r := e.do("GET", "/v1/anime/59978", ""); r.status != 200 {
		t.Fatalf("cache 59978: %d %s", r.status, r.raw)
	}
	e.exec(`UPDATE recanime.anime SET is_adult = true WHERE mal_id = $1`, 59978)

	r := e.do("GET", "/v1/recommendations", "")
	if items, _ := r.body["data"].([]any); r.status != 200 || len(items) != 0 {
		t.Fatalf("a pair containing an adult title must be dropped: %d %s", r.status, r.raw)
	}
	r = e.do("GET", "/v1/anime/52991/recommendations", "")
	if items, _ := r.body["data"].([]any); r.status != 200 || len(items) != 0 {
		t.Fatalf("adult recommendations must be dropped: %d %s", r.status, r.raw)
	}

	// Turning SFW off brings them back.
	if r := e.do("PATCH", "/v1/me/settings", `{"sfw":false}`); r.status != 200 {
		t.Fatalf("patch settings: %d %s", r.status, r.raw)
	}
	e.now = e.now.Add(time.Minute) // past the live debounce
	r = e.do("GET", "/v1/recommendations", "")
	if items, _ := r.body["data"].([]any); len(items) != 1 {
		t.Fatalf("without SFW the pair must come back: %s", r.raw)
	}
	r = e.do("GET", "/v1/anime/52991/recommendations", "")
	if items, _ := r.body["data"].([]any); len(items) != 1 {
		t.Fatalf("without SFW the recommendation must come back: %s", r.raw)
	}
}

// adultListFixture is one list page whose only entry is Rx-rated.
func adultListFixture(t *testing.T) []byte {
	t.Helper()
	var wrapper struct {
		Data json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(testutil.ReadFixture(t, "jikan", "anime_full_52991.json"), &wrapper); err != nil {
		t.Fatal(err)
	}
	var obj map[string]any
	if err := json.Unmarshal(wrapper.Data, &obj); err != nil {
		t.Fatal(err)
	}
	obj["rating"] = "Rx - Hentai"
	body, _ := json.Marshal(map[string]any{
		"pagination": map[string]any{"last_visible_page": 3, "has_next_page": true, "current_page": 1,
			"items": map[string]int{"count": 1, "total": 3, "per_page": 25}},
		"data": []any{obj},
	})
	return body
}

// TestListSkipsFullyFilteredPage: a page whose entries are all adult used to answer with an empty
// data array and hasNextPage=true, which the iOS loader cannot advance past (it asks for more only
// when a row appears).
func TestListSkipsFullyFilteredPage(t *testing.T) {
	e := newEnv(t, nil)
	adult := adultListFixture(t)
	clean := listFixture(t, "anime_full_52991.json", "anime_full_59978.json")
	e.jikan.RouteFunc("/top/anime", func(r *http.Request) []byte {
		if r.URL.Query().Get("page") == "2" {
			return clean
		}
		return adult
	})

	r := e.do("GET", "/v1/top", "")
	items, _ := r.body["data"].([]any)
	if r.status != 200 || len(items) != 2 {
		t.Fatalf("the filtered page must be skipped forward: %d %s", r.status, r.raw)
	}
	pg, _ := r.body["pagination"].(map[string]any)
	if pg["page"] != float64(2) {
		t.Fatalf("pagination must report the page actually served: %v", pg)
	}
	if e.jikan.Hits("/top/anime") != 2 {
		t.Fatalf("expected exactly two upstream pages, got %d", e.jikan.Hits("/top/anime"))
	}

	// Without the SFW filter the first page is served as-is.
	e.do("PATCH", "/v1/me/settings", `{"sfw":false}`)
	r = e.do("GET", "/v1/top", "")
	items, _ = r.body["data"].([]any)
	pg, _ = r.body["pagination"].(map[string]any)
	if len(items) != 1 || pg["page"] != float64(1) {
		t.Fatalf("without SFW the first page must be served: %s", r.raw)
	}
}

// TestListSkipsFullyFilteredPageStopsAfterThreePages: an upstream that is adult forever (every
// page reports hasNextPage=true, none ever has a clean entry) must not walk indefinitely. The
// walk stops after 3 pages and answers with an empty page rather than pinning the request budget
// on a hostile or broken upstream feed.
func TestListSkipsFullyFilteredPageStopsAfterThreePages(t *testing.T) {
	e := newEnv(t, nil)
	e.jikan.RouteBytes("/top/anime", adultListFixture(t))

	r := e.do("GET", "/v1/top", "")
	items, _ := r.body["data"].([]any)
	if r.status != 200 || len(items) != 0 {
		t.Fatalf("expected an empty page once the walk budget is exhausted: %d %s", r.status, r.raw)
	}
	if e.jikan.Hits("/top/anime") != 3 {
		t.Fatalf("expected exactly 3 upstream pages, no more, got %d", e.jikan.Hits("/top/anime"))
	}
	pg, _ := r.body["pagination"].(map[string]any)
	if pg["page"] != float64(3) {
		t.Fatalf("pagination must report the last page actually fetched (3), got %v", pg)
	}
}

// TestPageBounds: page is a cache key, so an unbounded value mints permanent list_cache rows.
// Every list endpoint shares the same bound (1..100), so this walks all of them.
func TestPageBounds(t *testing.T) {
	e := newEnv(t, nil)
	for _, path := range []string{"/v1/top?page=101", "/v1/seasons/now?page=101", "/v1/seasons/upcoming?page=101",
		"/v1/seasons/2023/fall?page=101", "/v1/search?q=frieren&page=9999", "/v1/schedules?day=monday&page=101",
		"/v1/recommendations?page=101", "/v1/anime/52991/episodes?page=101"} {
		if r := e.do("GET", path, ""); r.status != 400 || r.errCode() != "validation_error" {
			t.Fatalf("%s must be rejected: %d %s", path, r.status, r.raw)
		}
	}
	for _, path := range []string{"/v1/top?page=100", "/v1/seasons/now?page=100"} {
		if r := e.do("GET", path, ""); r.status != 200 {
			t.Fatalf("%s: page 100 is still valid: %d %s", path, r.status, r.raw)
		}
	}
}

// TestRateLimitRetryAfterHeader: Retry-After used to be hardcoded to 2 s while the limiter can
// stay in cooldown for up to 30 s.
func TestRateLimitRetryAfterHeader(t *testing.T) {
	e := newEnv(t, nil)
	e.jikan.FailNext(1, http.StatusTooManyRequests, "7")
	r := e.do("GET", "/v1/anime/52991", "")
	if r.status != http.StatusServiceUnavailable || r.errCode() != "upstream_rate_limited" {
		t.Fatalf("expected 503 upstream_rate_limited, got %d %s", r.status, r.raw)
	}
	if got := r.header.Get("Retry-After"); got != "7" {
		t.Fatalf("Retry-After = %q, want 7", got)
	}
	if r.header.Get("X-Request-Id") == "" {
		t.Fatalf("every response must carry X-Request-Id: %v", r.header)
	}
}

// TestEpisodeDeltaIsAtomic: the delta used to be a read-modify-write over three round trips, so
// concurrent increments lost updates.
func TestEpisodeDeltaIsAtomic(t *testing.T) {
	e := newEnv(t, nil)
	if r := e.do("PUT", "/v1/me/library/52991", `{"status":"watching","episodesWatched":0}`); r.status != 200 {
		t.Fatalf("seed entry: %d %s", r.status, r.raw)
	}

	const concurrent = 10
	errs := make(chan error, concurrent)
	var wg sync.WaitGroup
	for range concurrent {
		wg.Add(1)
		go func() {
			defer wg.Done()
			req, err := http.NewRequestWithContext(context.Background(), "POST",
				e.srv.URL+"/v1/me/library/52991/episodes", strings.NewReader(`{"delta":1}`))
			if err != nil {
				errs <- err
				return
			}
			req.Header.Set("Content-Type", "application/json")
			res, err := e.srv.Client().Do(req)
			if err != nil {
				errs <- err
				return
			}
			_, _ = io.Copy(io.Discard, res.Body)
			_ = res.Body.Close()
			if res.StatusCode != 200 {
				errs <- fmt.Errorf("status %d", res.StatusCode)
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatalf("concurrent delta: %v", err)
	}

	r := e.do("GET", "/v1/me/library/52991", "")
	entry, _ := r.data()["entry"].(map[string]any)
	if entry["episodesWatched"] != float64(concurrent) {
		t.Fatalf("expected %d episodes after %d concurrent deltas, got %v", concurrent, concurrent, entry["episodesWatched"])
	}
	if entry["status"] != "watching" {
		t.Fatalf("status must stay watching: %v", entry)
	}

	// A pending entry starts watching as soon as progress is positive, and stays clamped.
	e.do("PUT", "/v1/me/library/59978", `{"status":"pending"}`)
	r = e.do("POST", "/v1/me/library/59978/episodes", `{"delta":1}`)
	entry, _ = r.data()["entry"].(map[string]any)
	if entry["status"] != "watching" || entry["episodesWatched"] != float64(1) {
		t.Fatalf("progress on a pending entry starts it: %v", entry)
	}
	r = e.do("POST", "/v1/me/library/59978/episodes", `{"episodesWatched":999}`)
	entry, _ = r.data()["entry"].(map[string]any)
	if entry["episodesWatched"] != float64(10) {
		t.Fatalf("absolute progress must stay clamped to the episode count: %v", entry)
	}
	r = e.do("POST", "/v1/me/library/59978/episodes", `{"delta":-99}`)
	entry, _ = r.data()["entry"].(map[string]any)
	if entry["episodesWatched"] != float64(0) {
		t.Fatalf("progress must not go negative: %v", entry)
	}
}

// TestGoldenFixtures keeps the Go responses and the Swift decoders in sync: every stored fixture
// is compared with the live response (volatile fields normalized). UPDATE_GOLDEN=1 rewrites them.
func TestGoldenFixtures(t *testing.T) {
	e := newEnv(t, nil)
	e.do("PUT", "/v1/me/library/52991", `{"status":"watching","episodesWatched":7,"favorite":true}`)
	e.do("PUT", "/v1/me/library/59978", `{"status":"pending"}`)
	cases := map[string]string{
		"me.json":               "/v1/me",
		"anime_detail.json":     "/v1/anime/52991",
		"anime_franchise.json":  "/v1/anime/52991/franchise",
		"anime_episodes.json":   "/v1/anime/52991/episodes",
		"seasons_index.json":    "/v1/seasons",
		"season_now.json":       "/v1/seasons/now",
		"top.json":              "/v1/top",
		"search.json":           "/v1/search?q=frieren",
		"recommendations.json":  "/v1/recommendations",
		"library_grouped.json":  "/v1/me/library",
		"library_item.json":     "/v1/me/library/52991",
		"schedule.json":         "/v1/me/schedule",
		"error_not_found.json":  "/v1/anime/424242",
		"error_validation.json": "/v1/top?filter=bogus",
	}
	dir := testutil.FixturePath(t, "golden")
	update := os.Getenv("UPDATE_GOLDEN") != ""
	if update {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	for name, path := range cases {
		r := e.do("GET", path, "")
		var pretty bytes.Buffer
		if err := json.Indent(&pretty, r.raw, "", "  "); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		pretty.WriteByte('\n')
		file := filepath.Join(dir, name)
		if update {
			if err := os.WriteFile(file, pretty.Bytes(), 0o644); err != nil {
				t.Fatal(err)
			}
			continue
		}
		want, err := os.ReadFile(file)
		if err != nil {
			t.Fatalf("%s: %v (regenerate with %s)", name, err, regenerateHint)
		}
		got, expected := normalizeGolden(t, name, pretty.Bytes()), normalizeGolden(t, name, want)
		if !reflect.DeepEqual(got, expected) {
			t.Errorf("%s drifted from its golden fixture.\n got: %s\nwant: %s\nregenerate with %s",
				name, compactJSON(got), compactJSON(expected), regenerateHint)
		}
	}
}

// TestGoldenNormalizationDetectsDrift proves the compare mode used by TestGoldenFixtures actually
// catches drift instead of always agreeing: a real content difference must compare unequal, while
// a difference confined to a volatile field (updatedAt) must still compare equal. This does not
// need the database; it drives the same normalizeGolden/scrubVolatile helpers directly.
func TestGoldenNormalizationDetectsDrift(t *testing.T) {
	a := []byte(`{"data":{"title":"Sousou no Frieren","updatedAt":"2026-01-01T00:00:00Z"},"meta":{"cache":"HIT"}}`)
	b := []byte(`{"data":{"title":"Sousou no Frieren 2nd Season","updatedAt":"2026-01-01T00:00:00Z"},"meta":{"cache":"HIT"}}`)
	if reflect.DeepEqual(normalizeGolden(t, "doc", a), normalizeGolden(t, "doc", b)) {
		t.Fatal("a real difference in a non-volatile field must not compare equal after normalization")
	}

	c := []byte(`{"data":{"title":"Sousou no Frieren","updatedAt":"2026-01-01T00:00:00Z"},"meta":{"cache":"HIT"}}`)
	d := []byte(`{"data":{"title":"Sousou no Frieren","updatedAt":"2027-06-15T08:30:00Z"},"meta":{"cache":"HIT"}}`)
	if !reflect.DeepEqual(normalizeGolden(t, "doc", c), normalizeGolden(t, "doc", d)) {
		t.Fatalf("a difference confined to updatedAt must compare equal after normalization: %s vs %s",
			compactJSON(normalizeGolden(t, "doc", c)), compactJSON(normalizeGolden(t, "doc", d)))
	}
}

const regenerateHint = "UPDATE_GOLDEN=1 pnpm api:test:it && pnpm fixtures:sync"

// volatileGoldenKeys change on every run by design and are blanked before comparing.
var volatileGoldenKeys = map[string]bool{"createdAt": true, "updatedAt": true, "fetchedAt": true, "requestId": true}

func normalizeGolden(t *testing.T, name string, raw []byte) any {
	t.Helper()
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("%s: decode: %v", name, err)
	}
	return scrubVolatile(v)
}

func scrubVolatile(v any) any {
	switch x := v.(type) {
	case map[string]any:
		out := make(map[string]any, len(x))
		for k, val := range x {
			if volatileGoldenKeys[k] && val != nil {
				out[k] = "<volatile>"
				continue
			}
			out[k] = scrubVolatile(val)
		}
		return out
	case []any:
		out := make([]any, len(x))
		for i, val := range x {
			out[i] = scrubVolatile(val)
		}
		return out
	default:
		return v
	}
}

func compactJSON(v any) string {
	b, err := json.Marshal(v)
	if err != nil {
		return fmt.Sprintf("%v", v)
	}
	return string(b)
}
