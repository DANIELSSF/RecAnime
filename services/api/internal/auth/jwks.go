package auth

import (
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"sync"
	"time"
)

// ErrUnknownKey is returned when a token's kid is not (or no longer) in the JWKS.
var ErrUnknownKey = errors.New("auth: unknown signing key")

// KeySet is a small JWKS cache: keys are refreshed every refreshInterval, and on an unknown kid
// (at most once per minute so a flood of bad tokens cannot hammer Supabase).
type KeySet struct {
	url             string
	client          *http.Client
	refreshInterval time.Duration
	now             func() time.Time

	mu           sync.Mutex
	keys         map[string]crypto.PublicKey
	fetchedAt    time.Time
	lastAttempt  time.Time
	minRetryGap  time.Duration
	refreshError error
}

// NewKeySet creates a cache for the JWKS at url.
func NewKeySet(url string, client *http.Client) *KeySet {
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	return &KeySet{
		url:             url,
		client:          client,
		refreshInterval: 10 * time.Minute,
		minRetryGap:     time.Minute,
		now:             time.Now,
		keys:            map[string]crypto.PublicKey{},
	}
}

// Get returns the public key for kid, refreshing the set when it is stale or the kid is unknown.
func (k *KeySet) Get(ctx context.Context, kid string) (crypto.PublicKey, error) {
	k.mu.Lock()
	defer k.mu.Unlock()
	now := k.now()
	if key, ok := k.keys[kid]; ok && now.Sub(k.fetchedAt) < k.refreshInterval {
		return key, nil
	}
	if now.Sub(k.lastAttempt) >= k.minRetryGap || k.fetchedAt.IsZero() {
		k.lastAttempt = now
		if err := k.refreshLocked(ctx); err != nil {
			k.refreshError = err
			// A stale set is still better than nothing: serve the known key if present.
			if key, ok := k.keys[kid]; ok {
				return key, nil
			}
			return nil, fmt.Errorf("auth: refresh jwks: %w", err)
		}
		k.fetchedAt = now
		k.refreshError = nil
	}
	if key, ok := k.keys[kid]; ok {
		return key, nil
	}
	return nil, ErrUnknownKey
}

// Prefetch loads the key set once; failures are returned but leave the set usable later.
func (k *KeySet) Prefetch(ctx context.Context) error {
	k.mu.Lock()
	defer k.mu.Unlock()
	k.lastAttempt = k.now()
	if err := k.refreshLocked(ctx); err != nil {
		return err
	}
	k.fetchedAt = k.now()
	return nil
}

type jwksDocument struct {
	Keys []jwk `json:"keys"`
}

type jwk struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	Crv string `json:"crv"`
	X   string `json:"x"`
	Y   string `json:"y"`
	N   string `json:"n"`
	E   string `json:"e"`
}

func (k *KeySet) refreshLocked(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, k.url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/json")
	resp, err := k.client.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("jwks endpoint returned %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return err
	}
	var doc jwksDocument
	if err := json.Unmarshal(body, &doc); err != nil {
		return fmt.Errorf("decode jwks: %w", err)
	}
	keys := make(map[string]crypto.PublicKey, len(doc.Keys))
	for _, j := range doc.Keys {
		if j.Use != "" && j.Use != "sig" {
			continue
		}
		pub, err := j.publicKey()
		if err != nil {
			// Skip keys we cannot use (e.g. symmetric "oct" legacy secrets are never published).
			continue
		}
		keys[j.Kid] = pub
	}
	if len(keys) == 0 {
		return errors.New("jwks contains no usable asymmetric keys")
	}
	k.keys = keys
	return nil
}

func (j jwk) publicKey() (crypto.PublicKey, error) {
	switch j.Kty {
	case "EC":
		var curve elliptic.Curve
		switch j.Crv {
		case "P-256":
			curve = elliptic.P256()
		case "P-384":
			curve = elliptic.P384()
		case "P-521":
			curve = elliptic.P521()
		default:
			return nil, fmt.Errorf("unsupported curve %q", j.Crv)
		}
		x, err := b64(j.X)
		if err != nil {
			return nil, err
		}
		y, err := b64(j.Y)
		if err != nil {
			return nil, err
		}
		size := (curve.Params().BitSize + 7) / 8
		if len(x) > size || len(y) > size {
			return nil, errors.New("ec coordinate too long for curve")
		}
		// Uncompressed SEC 1 encoding: 0x04 || X || Y with fixed-size, left-padded coordinates.
		point := make([]byte, 1+2*size)
		point[0] = 0x04
		copy(point[1+size-len(x):1+size], x)
		copy(point[1+2*size-len(y):], y)
		return ecdsa.ParseUncompressedPublicKey(curve, point)
	case "RSA":
		n, err := b64(j.N)
		if err != nil {
			return nil, err
		}
		e, err := b64(j.E)
		if err != nil {
			return nil, err
		}
		return &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: int(new(big.Int).SetBytes(e).Int64())}, nil
	default:
		return nil, fmt.Errorf("unsupported key type %q", j.Kty)
	}
}

func b64(s string) ([]byte, error) {
	if s == "" {
		return nil, errors.New("empty jwk field")
	}
	return base64.RawURLEncoding.DecodeString(s)
}
