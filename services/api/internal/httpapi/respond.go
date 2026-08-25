// Package httpapi wires the HTTP surface: router, middleware, handlers and the JSON envelope.
package httpapi

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5/middleware"

	"github.com/danielssf/recanime/services/api/internal/model"
)

// Cache status values reported in meta.cache and the X-Cache header.
const (
	CacheHit   = "HIT"
	CacheMiss  = "MISS"
	CacheStale = "STALE"
	CacheLive  = "LIVE"
)

// Meta describes how the data in the envelope was obtained.
type Meta struct {
	Cache         string     `json:"cache,omitempty"`
	FetchedAt     *time.Time `json:"fetchedAt,omitempty"`
	Stale         bool       `json:"stale"`
	UpstreamError *string    `json:"upstreamError"`
}

// Pagination is the camelCase pagination block shared with the apps.
type Pagination = model.Pagination

type envelope struct {
	Data       any         `json:"data"`
	Meta       *Meta       `json:"meta,omitempty"`
	Pagination *Pagination `json:"pagination,omitempty"`
}

type errorBody struct {
	Error errorDetail `json:"error"`
}

type errorDetail struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	RequestID string `json:"requestId,omitempty"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		slog.Default().Warn("encode response", "error", err)
	}
}

// writeData writes the success envelope and mirrors the cache status in X-Cache.
func writeData(w http.ResponseWriter, status int, data any, meta *Meta, pg *Pagination) {
	if meta != nil && meta.Cache != "" {
		w.Header().Set("X-Cache", meta.Cache)
	}
	writeJSON(w, status, envelope{Data: data, Meta: meta, Pagination: pg})
}

// writeError writes the error envelope with the request id for log correlation.
func writeError(w http.ResponseWriter, r *http.Request, status int, code, message string) {
	writeJSON(w, status, errorBody{Error: errorDetail{
		Code:      code,
		Message:   message,
		RequestID: middleware.GetReqID(r.Context()),
	}})
}
