package jikan

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Limiter gates every outgoing request (including retries).
type Limiter interface {
	Wait(ctx context.Context) error
	Penalize(d time.Duration)
}

// Client talks to Jikan v4.
type Client struct {
	base      string
	http      *http.Client
	limiter   Limiter
	userAgent string
	// retryDelay is the pause before the single retry on 5xx/network errors.
	retryDelay time.Duration
}

// New builds a client for baseURL (e.g. https://api.jikan.moe/v4).
func New(baseURL string, httpClient *http.Client, limiter Limiter, userAgent string) *Client {
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 15 * time.Second}
	}
	if userAgent == "" {
		userAgent = "RecAnime/0.1 (+https://github.com/danielssf/recanime)"
	}
	return &Client{
		base:       strings.TrimRight(baseURL, "/"),
		http:       httpClient,
		limiter:    limiter,
		userAgent:  userAgent,
		retryDelay: 500 * time.Millisecond,
	}
}

type envelope struct {
	Data       json.RawMessage `json:"data"`
	Pagination *Pagination     `json:"pagination"`
}

type errorBody struct {
	Status  int    `json:"status"`
	Type    string `json:"type"`
	Message string `json:"message"`
}

// get performs one rate-limited GET with a single retry on transient failures and decodes into T.
func get[T any](ctx context.Context, c *Client, path string, q url.Values) (*Response[T], error) {
	u := c.base + path
	if len(q) > 0 {
		u += "?" + q.Encode()
	}
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return nil, ctx.Err()
			case <-time.After(c.retryDelay):
			}
		}
		if err := c.limiter.Wait(ctx); err != nil {
			return nil, err
		}
		resp, err := c.do(ctx, u)
		if err != nil {
			lastErr = err
			if errors.Is(err, ErrUpstream) || retriableRateLimit(err) {
				// The limiter already absorbed the cooldown in Wait, so the retry is paced.
				continue
			}
			return nil, err
		}
		var env envelope
		if err := json.Unmarshal(resp, &env); err != nil {
			return nil, fmt.Errorf("%w: decode envelope: %w", ErrUpstream, err)
		}
		var out Response[T]
		out.Raw = env.Data
		out.Pagination = env.Pagination
		if err := json.Unmarshal(env.Data, &out.Data); err != nil {
			return nil, fmt.Errorf("%w: decode data: %w", ErrUpstream, err)
		}
		return &out, nil
	}
	return nil, lastErr
}

// do issues the request and classifies the response.
func (c *Client) do(ctx context.Context, u string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, fmt.Errorf("%w: build request: %w", ErrBadRequest, err)
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", c.userAgent)
	resp, err := c.http.Do(req)
	if err != nil {
		var netErr net.Error
		if errors.As(err, &netErr) || errors.Is(err, context.DeadlineExceeded) {
			return nil, fmt.Errorf("%w: %w", ErrUpstream, err)
		}
		if errors.Is(err, context.Canceled) {
			return nil, err
		}
		return nil, fmt.Errorf("%w: %w", ErrUpstream, err)
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		return nil, fmt.Errorf("%w: read body: %w", ErrUpstream, err)
	}
	if resp.StatusCode == http.StatusOK {
		return body, nil
	}
	var eb errorBody
	_ = json.Unmarshal(body, &eb)
	if eb.Status == 0 {
		eb.Status = resp.StatusCode
	}
	if eb.Message == "" {
		eb.Message = http.StatusText(resp.StatusCode)
	}
	e := &Error{Status: resp.StatusCode, Type: eb.Type, Message: eb.Message}
	switch {
	case resp.StatusCode == http.StatusNotFound:
		e.kind = ErrNotFound
	case resp.StatusCode == http.StatusTooManyRequests:
		e.kind = ErrRateLimited
		e.RetryAfter = retryAfter(resp.Header.Get("Retry-After"))
		c.limiter.Penalize(e.RetryAfter)
	case resp.StatusCode >= 500:
		e.kind = ErrUpstream
	case resp.StatusCode >= 400:
		e.kind = ErrBadRequest
	default:
		e.kind = ErrUpstream
	}
	return nil, e
}

// maxRetryAfterRetry is the longest upstream cooldown still worth retrying inside the request:
// Penalize blocks Wait for exactly that long, and the request budget is 25 s.
const maxRetryAfterRetry = 5 * time.Second

// retriableRateLimit reports whether a 429 is worth one in-request retry.
func retriableRateLimit(err error) bool {
	if !errors.Is(err, ErrRateLimited) {
		return false
	}
	var je *Error
	if errors.As(err, &je) {
		return je.RetryAfter <= maxRetryAfterRetry
	}
	return true
}

// retryAfter parses a Retry-After header in seconds; 0 lets the limiter apply its default.
func retryAfter(v string) time.Duration {
	if v == "" {
		return 0
	}
	if secs, err := strconv.Atoi(strings.TrimSpace(v)); err == nil && secs > 0 {
		return time.Duration(secs) * time.Second
	}
	return 0
}

func setIf(q url.Values, key, val string) {
	if val != "" {
		q.Set(key, val)
	}
}

func setPage(q url.Values, page, limit int) {
	if page > 1 {
		q.Set("page", strconv.Itoa(page))
	}
	if limit > 0 {
		q.Set("limit", strconv.Itoa(limit))
	}
}
