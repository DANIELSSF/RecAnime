// Package testutil holds helpers shared by the test suites: a fake Jikan server and fixtures.
package testutil

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"sync"
	"testing"
)

// FixturePath resolves a file under services/api/testdata.
func FixturePath(t testing.TB, parts ...string) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot resolve testdata path")
	}
	root := filepath.Join(filepath.Dir(file), "..", "..", "testdata")
	return filepath.Join(append([]string{root}, parts...)...)
}

// ReadFixture returns the bytes of testdata/<parts...>.
func ReadFixture(t testing.TB, parts ...string) []byte {
	t.Helper()
	b, err := os.ReadFile(FixturePath(t, parts...))
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	return b
}

// FakeJikan serves fixture files by request path and lets tests inject failures.
type FakeJikan struct {
	Server *httptest.Server

	mu       sync.Mutex
	routes   map[string]string                     // request path (no query) -> fixture file name
	inline   map[string][]byte                     // request path -> literal JSON body
	dynamic  map[string]func(*http.Request) []byte // request path -> body built from the query
	hits     map[string]int
	failNext []failure
}

type failure struct {
	status     int
	retryAfter string
}

// NewFakeJikan starts the fake server; call Close (or rely on t.Cleanup).
func NewFakeJikan(t testing.TB) *FakeJikan {
	t.Helper()
	f := &FakeJikan{routes: map[string]string{}, inline: map[string][]byte{},
		dynamic: map[string]func(*http.Request) []byte{}, hits: map[string]int{}}
	f.Server = httptest.NewServer(http.HandlerFunc(f.handle))
	t.Cleanup(f.Server.Close)
	return f
}

// Route maps a request path (without query string) to a fixture under testdata/jikan.
func (f *FakeJikan) Route(path, fixture string) *FakeJikan {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.routes[path] = fixture
	return f
}

// RouteBytes serves a literal JSON body for path.
func (f *FakeJikan) RouteBytes(path string, body []byte) *FakeJikan {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.inline[path] = body
	return f
}

// RouteFunc serves a body built per request, so a route can vary by query (page, filter...).
func (f *FakeJikan) RouteFunc(path string, fn func(r *http.Request) []byte) *FakeJikan {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.dynamic[path] = fn
	return f
}

// FailNext makes the next n requests fail with status (Retry-After optional).
func (f *FakeJikan) FailNext(n, status int, retryAfter string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for range n {
		f.failNext = append(f.failNext, failure{status: status, retryAfter: retryAfter})
	}
}

// Hits returns how many requests reached path.
func (f *FakeJikan) Hits(path string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.hits[path]
}

// TotalHits returns the number of requests served (including failures).
func (f *FakeJikan) TotalHits() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, v := range f.hits {
		n += v
	}
	return n
}

func (f *FakeJikan) handle(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	f.hits[r.URL.Path]++
	var fail *failure
	if len(f.failNext) > 0 {
		fail = &f.failNext[0]
		f.failNext = f.failNext[1:]
	}
	fixture, ok := f.routes[r.URL.Path]
	inline, hasInline := f.inline[r.URL.Path]
	fn, hasFunc := f.dynamic[r.URL.Path]
	f.mu.Unlock()

	w.Header().Set("Content-Type", "application/json")
	if fail != nil {
		if fail.retryAfter != "" {
			w.Header().Set("Retry-After", fail.retryAfter)
		}
		w.WriteHeader(fail.status)
		_, _ = w.Write([]byte(`{"status":` + strconv.Itoa(fail.status) + `,"type":"Injected","message":"injected failure","error":null}`))
		return
	}
	if hasFunc {
		_, _ = w.Write(fn(r))
		return
	}
	if hasInline {
		_, _ = w.Write(inline)
		return
	}
	if !ok {
		w.WriteHeader(http.StatusNotFound)
		_, _ = w.Write([]byte(`{"status":404,"type":"BadResponseException","message":"Resource does not exist","error":"404 on https://myanimelist.net/"}`))
		return
	}
	root := filepath.Dir(filepath.Dir(fixtureDir()))
	b, err := os.ReadFile(filepath.Join(root, "testdata", "jikan", fixture))
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(`{"status":500,"type":"FixtureMissing","message":"` + err.Error() + `"}`))
		return
	}
	_, _ = w.Write(b)
}

func fixtureDir() string {
	_, file, _, _ := runtime.Caller(0)
	return filepath.Dir(file)
}
