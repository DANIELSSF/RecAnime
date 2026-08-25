package jikan

import (
	"context"
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/danielssf/recanime/services/api/internal/testutil"
)

type recordingLimiter struct {
	waits     int
	penalties []time.Duration
}

func (l *recordingLimiter) Wait(context.Context) error { l.waits++; return nil }
func (l *recordingLimiter) Penalize(d time.Duration)   { l.penalties = append(l.penalties, d) }

func newClient(t *testing.T) (*Client, *testutil.FakeJikan, *recordingLimiter) {
	t.Helper()
	fake := testutil.NewFakeJikan(t)
	fake.Route("/anime/52991/full", "anime_full_52991.json")
	fake.Route("/anime/52991/episodes", "anime_episodes_52991_p1.json")
	fake.Route("/seasons", "seasons_index.json")
	lim := &recordingLimiter{}
	c := New(fake.Server.URL, fake.Server.Client(), lim, "test-agent")
	c.retryDelay = time.Millisecond
	return c, fake, lim
}

func TestAnimeFullDecodesFixture(t *testing.T) {
	c, fake, lim := newClient(t)
	res, err := c.AnimeFull(context.Background(), 52991)
	if err != nil {
		t.Fatal(err)
	}
	a := res.Data
	if a.MalID != 52991 || a.Title != "Sousou no Frieren" || a.Episodes == nil || *a.Episodes != 28 {
		t.Fatalf("unexpected anime: %+v", a)
	}
	if a.Broadcast.Day == nil || *a.Broadcast.Day != "Fridays" || a.Aired.From == nil || a.Aired.From.Year() != 2023 {
		t.Fatalf("unexpected broadcast/aired: %+v %+v", a.Broadcast, a.Aired)
	}
	if len(a.Relations) == 0 || a.Relations[0].Relation != "Sequel" || a.Relations[0].Entry[0].MalID != 59978 {
		t.Fatalf("unexpected relations: %+v", a.Relations)
	}
	if len(res.Raw) == 0 || res.Pagination != nil || lim.waits != 1 || fake.Hits("/anime/52991/full") != 1 {
		t.Fatalf("raw/pagination/limiter bookkeeping wrong: raw=%d pg=%v waits=%d", len(res.Raw), res.Pagination, lim.waits)
	}
}

func TestPaginatedEndpoint(t *testing.T) {
	c, _, _ := newClient(t)
	res, err := c.AnimeEpisodes(context.Background(), 52991, 1)
	if err != nil {
		t.Fatal(err)
	}
	if res.Pagination == nil || res.Pagination.HasNextPage || len(res.Data) != 28 || res.Data[0].Aired == nil {
		t.Fatalf("unexpected page: %+v (len=%d)", res.Pagination, len(res.Data))
	}
	idx, err := c.SeasonsIndex(context.Background())
	if err != nil || len(idx.Data) == 0 || idx.Data[0].Year == 0 {
		t.Fatalf("seasons index: %v %+v", err, idx)
	}
}

func TestNotFound(t *testing.T) {
	c, _, lim := newClient(t)
	_, err := c.AnimeFull(context.Background(), 1)
	var je *Error
	if !errors.Is(err, ErrNotFound) || !errors.As(err, &je) || je.Status != http.StatusNotFound {
		t.Fatalf("expected ErrNotFound with status 404, got %v", err)
	}
	if IsTransient(err) || lim.waits != 1 {
		t.Fatalf("404 must not be transient nor retried (waits=%d)", lim.waits)
	}
}

func TestRateLimitedPenalizesAndDoesNotRetry(t *testing.T) {
	c, fake, lim := newClient(t)
	fake.FailNext(1, http.StatusTooManyRequests, "7")
	_, err := c.AnimeFull(context.Background(), 52991)
	if !errors.Is(err, ErrRateLimited) || !IsTransient(err) {
		t.Fatalf("expected ErrRateLimited, got %v", err)
	}
	if len(lim.penalties) != 1 || lim.penalties[0] != 7*time.Second || fake.Hits("/anime/52991/full") != 1 {
		t.Fatalf("expected one 7s penalty and no retry, got %v hits=%d", lim.penalties, fake.Hits("/anime/52991/full"))
	}
}

func TestServerErrorRetriesOnce(t *testing.T) {
	c, fake, lim := newClient(t)
	fake.FailNext(1, http.StatusBadGateway, "")
	res, err := c.AnimeFull(context.Background(), 52991)
	if err != nil || res.Data.MalID != 52991 {
		t.Fatalf("expected success after one retry, got %v", err)
	}
	if fake.Hits("/anime/52991/full") != 2 || lim.waits != 2 {
		t.Fatalf("expected exactly 2 attempts through the limiter, got hits=%d waits=%d", fake.Hits("/anime/52991/full"), lim.waits)
	}
	fake.FailNext(2, http.StatusServiceUnavailable, "")
	_, err = c.AnimeFull(context.Background(), 52991)
	if !errors.Is(err, ErrUpstream) || !IsTransient(err) {
		t.Fatalf("expected ErrUpstream after two failures, got %v", err)
	}
}

func TestQueryEncoding(t *testing.T) {
	q := ListQuery{Filter: "airing", Type: "tv", SFW: true, Page: 2, Limit: 25}.values()
	if q.Get("filter") != "airing" || q.Get("type") != "tv" || q.Get("sfw") != "true" || q.Get("page") != "2" || q.Get("limit") != "25" {
		t.Fatalf("unexpected list query: %v", q)
	}
	s := SearchQuery{Q: "frieren", OrderBy: "score", Sort: "desc", SFW: true}.values()
	if s.Get("q") != "frieren" || s.Get("order_by") != "score" || s.Get("sort") != "desc" || s.Has("page") {
		t.Fatalf("unexpected search query: %v", s)
	}
	if retryAfter("3") != 3*time.Second || retryAfter("") != 0 || retryAfter("bogus") != 0 {
		t.Fatal("retryAfter parsing")
	}
}
