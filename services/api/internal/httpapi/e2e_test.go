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
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"

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

	e := &env{t: t, jikan: fake, now: time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)}
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
	e.sched = schedule.NewService(st, e.anime, e.catalog, logger)
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

// TestGoldenFixtures writes representative responses for the Swift package when UPDATE_GOLDEN=1.
func TestGoldenFixtures(t *testing.T) {
	if os.Getenv("UPDATE_GOLDEN") == "" {
		t.Skip("set UPDATE_GOLDEN=1 to regenerate testdata/golden")
	}
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
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	for name, path := range cases {
		r := e.do("GET", path, "")
		var pretty bytes.Buffer
		if err := json.Indent(&pretty, r.raw, "", "  "); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		pretty.WriteByte('\n')
		if err := os.WriteFile(filepath.Join(dir, name), pretty.Bytes(), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}
