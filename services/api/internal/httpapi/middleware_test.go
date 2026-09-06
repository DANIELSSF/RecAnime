package httpapi

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func testServer() *Server {
	return &Server{deps: Deps{Logger: slog.New(slog.NewTextHandler(io.Discard, nil)), Version: "test"}}
}

// TestRecoverPanicsWritesJSONEnvelope replaces chi's Recoverer: clients must always get the JSON
// error envelope with a request id, never an empty 500 plus an ANSI stack trace on stderr.
func TestRecoverPanicsWritesJSONEnvelope(t *testing.T) {
	r := chi.NewRouter()
	r.Use(requestID)
	r.Use(recoverPanics(slog.New(slog.NewTextHandler(io.Discard, nil))))
	r.Get("/boom", func(http.ResponseWriter, *http.Request) { panic("kaboom") })
	r.Get("/late", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		panic("after the response")
	})
	srv := httptest.NewServer(r)
	t.Cleanup(srv.Close)

	get := func(path string) (int, http.Header, map[string]any) {
		req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, srv.URL+path, nil)
		if err != nil {
			t.Fatal(err)
		}
		res, err := srv.Client().Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer func() { _ = res.Body.Close() }()
		raw, _ := io.ReadAll(res.Body)
		var body map[string]any
		_ = json.Unmarshal(raw, &body)
		return res.StatusCode, res.Header, body
	}

	status, header, body := get("/boom")
	if status != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", status)
	}
	if ct := header.Get("Content-Type"); ct != "application/json; charset=utf-8" {
		t.Fatalf("content type = %q", ct)
	}
	detail, _ := body["error"].(map[string]any)
	if detail["code"] != "internal" || detail["requestId"] == "" || detail["requestId"] == nil {
		t.Fatalf("unexpected error body: %v", body)
	}

	// A panic after the response was written must not append a second body.
	status, _, body = get("/late")
	if status != http.StatusOK || body["status"] != "ok" {
		t.Fatalf("late panic corrupted the response: %d %v", status, body)
	}
}

// TestRequestIDHeader documents that every response carries X-Request-Id for support tickets.
func TestRequestIDHeader(t *testing.T) {
	r := chi.NewRouter()
	r.Use(requestID)
	r.Use(requestLogger(slog.New(slog.NewTextHandler(io.Discard, nil))))
	r.Get("/ok", func(w http.ResponseWriter, _ *http.Request) { writeJSON(w, http.StatusOK, map[string]bool{"ok": true}) })
	srv := httptest.NewServer(r)
	t.Cleanup(srv.Close)

	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, srv.URL+"/ok", nil)
	if err != nil {
		t.Fatal(err)
	}
	res, err := srv.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = res.Body.Close() }()
	if res.Header.Get("X-Request-Id") == "" {
		t.Fatalf("X-Request-Id missing: %v", res.Header)
	}
}

// TestWriteServiceErrorTimeout covers the request budget expiring: a 504 with the `timeout` code,
// not a 500 logged as an internal bug.
func TestWriteServiceErrorTimeout(t *testing.T) {
	s := testServer()
	r := chi.NewRouter()
	r.Use(requestID)
	r.Use(middleware.Timeout(50 * time.Millisecond))
	r.Get("/slow", func(w http.ResponseWriter, req *http.Request) {
		<-req.Context().Done()
		s.writeServiceError(w, req, req.Context().Err())
	})
	srv := httptest.NewServer(r)
	t.Cleanup(srv.Close)

	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, srv.URL+"/slow", nil)
	if err != nil {
		t.Fatal(err)
	}
	res, err := srv.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = res.Body.Close() }()
	raw, _ := io.ReadAll(res.Body)
	var body map[string]any
	_ = json.Unmarshal(raw, &body)
	detail, _ := body["error"].(map[string]any)
	if res.StatusCode != http.StatusGatewayTimeout || detail["code"] != "timeout" {
		t.Fatalf("expected 504 timeout, got %d %s", res.StatusCode, raw)
	}
}

// TestRequestIDValidation covers the replacement for chi's middleware.RequestID: a client-supplied
// id reaches the response header, the error envelope and the logs, so only short URL-safe values
// are echoed back and everything else is replaced by a generated id.
func TestRequestIDValidation(t *testing.T) {
	tests := []struct {
		name   string
		header string
		echoed bool
	}{
		{name: "missing", header: "", echoed: false},
		{name: "plain", header: "abc123", echoed: true},
		{name: "uuid like", header: "5f2b8c1e-9a4d-4f77-b0d1-0c9a1e2f3b44", echoed: true},
		{name: "dots and underscores", header: "recanime.ios_1-2.3", echoed: true},
		{name: "max length", header: strings.Repeat("a", 64), echoed: true},
		{name: "too long", header: strings.Repeat("a", 65), echoed: false},
		{name: "newline", header: "abc\ndef", echoed: false},
		{name: "quote", header: `abc"def`, echoed: false},
		{name: "space", header: "abc def", echoed: false},
		{name: "slash", header: "abc/def", echoed: false},
		{name: "non ascii", header: "abcé", echoed: false},
	}
	generated := regexp.MustCompile(`^[0-9a-f]{32}$`)
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			var seen string
			h := requestID(requestLogger(slog.New(slog.NewTextHandler(io.Discard, nil)))(
				http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
					seen = middleware.GetReqID(r.Context())
					writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
				})))

			req := httptest.NewRequestWithContext(context.Background(), http.MethodGet, "/ok", nil)
			if tc.header != "" {
				req.Header.Set("X-Request-Id", tc.header)
			}
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, req)

			got := rec.Header().Get("X-Request-Id")
			if got == "" {
				t.Fatal("X-Request-Id missing from the response")
			}
			if got != seen {
				t.Fatalf("response header %q differs from the context id %q", got, seen)
			}
			if tc.echoed {
				if got != tc.header {
					t.Fatalf("X-Request-Id = %q, want the client value %q", got, tc.header)
				}
				return
			}
			if got == tc.header {
				t.Fatalf("X-Request-Id echoed the rejected value %q", tc.header)
			}
			if !generated.MatchString(got) {
				t.Fatalf("generated X-Request-Id = %q, want 32 hex characters", got)
			}
		})
	}
}

// TestNewRequestIDIsUnique guards against a generator that returns a constant.
func TestNewRequestIDIsUnique(t *testing.T) {
	seen := map[string]struct{}{}
	for range 100 {
		id := newRequestID()
		if _, dup := seen[id]; dup {
			t.Fatalf("duplicate request id %q", id)
		}
		seen[id] = struct{}{}
	}
}
