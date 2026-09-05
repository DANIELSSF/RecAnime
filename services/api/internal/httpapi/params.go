package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/danielssf/recanime/services/api/internal/cache"
)

func pathInt(r *http.Request, name string) (int, error) {
	v, err := strconv.Atoi(chi.URLParam(r, name))
	if err != nil || v <= 0 {
		return 0, fmt.Errorf("%w: %s must be a positive integer", errValidation, name)
	}
	return v, nil
}

func queryInt(r *http.Request, name string, def int) (int, error) {
	raw := strings.TrimSpace(r.URL.Query().Get(name))
	if raw == "" {
		return def, nil
	}
	v, err := strconv.Atoi(raw)
	if err != nil || v < 0 {
		return 0, fmt.Errorf("%w: %s must be a non-negative integer", errValidation, name)
	}
	return v, nil
}

// maxPage bounds every paginated endpoint: Jikan itself never has more, and an unbounded
// page would mint a permanent list_cache row per value.
const maxPage = 100

// queryPage parses the shared `page` parameter (1..maxPage, default 1).
func queryPage(r *http.Request) (int, error) {
	v, err := queryInt(r, "page", 1)
	if err != nil {
		return 0, err
	}
	if v == 0 {
		v = 1
	}
	if v > maxPage {
		return 0, fmt.Errorf("%w: page must be between 1 and %d", errValidation, maxPage)
	}
	return v, nil
}

func queryBoolPtr(r *http.Request, name string) (*bool, error) {
	raw := strings.TrimSpace(r.URL.Query().Get(name))
	if raw == "" {
		return nil, nil
	}
	v, err := strconv.ParseBool(raw)
	if err != nil {
		return nil, fmt.Errorf("%w: %s must be true or false", errValidation, name)
	}
	return &v, nil
}

func queryStringPtr(r *http.Request, name string) *string {
	raw := strings.TrimSpace(r.URL.Query().Get(name))
	if raw == "" {
		return nil
	}
	return &raw
}

func decodeJSON(r *http.Request, v any) error {
	body, err := io.ReadAll(r.Body)
	if err != nil {
		return fmt.Errorf("%w: cannot read body", errValidation)
	}
	if len(strings.TrimSpace(string(body))) == 0 {
		return fmt.Errorf("%w: empty body", errValidation)
	}
	if err := json.Unmarshal(body, v); err != nil {
		var syntax *json.SyntaxError
		var typeErr *json.UnmarshalTypeError
		if errors.As(err, &syntax) || errors.As(err, &typeErr) {
			return fmt.Errorf("%w: malformed JSON body", errValidation)
		}
		return fmt.Errorf("%w: %w", errValidation, err)
	}
	return nil
}

// metaFor converts a cache result into the response meta block.
func metaFor(status cache.Status, fetchedAt time.Time, upstreamErr error) *Meta {
	m := &Meta{Cache: string(status), Stale: status == cache.Stale}
	if !fetchedAt.IsZero() {
		t := fetchedAt.UTC()
		m.FetchedAt = &t
	}
	if token := upstreamErrorToken(upstreamErr); token != "" {
		m.UpstreamError = &token
	}
	return m
}
