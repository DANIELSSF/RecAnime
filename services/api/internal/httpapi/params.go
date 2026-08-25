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
	if upstreamErr != nil {
		msg := upstreamErr.Error()
		m.UpstreamError = &msg
	}
	return m
}
