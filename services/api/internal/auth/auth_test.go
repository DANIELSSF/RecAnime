package auth

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const issuer = "https://testref.supabase.co/auth/v1"

type fixture struct {
	ec     *ecdsa.PrivateKey
	rsa    *rsa.PrivateKey
	server *httptest.Server
	hits   atomic.Int32
	keys   *KeySet
	v      *Verifier
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	ec, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	rsaKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	f := &fixture{ec: ec, rsa: rsaKey}
	f.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		f.hits.Add(1)
		b64 := func(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }
		point, _ := ec.PublicKey.Bytes() // 0x04 || X || Y
		doc := map[string]any{"keys": []map[string]any{
			{"kty": "EC", "kid": "ec-1", "use": "sig", "alg": "ES256", "crv": "P-256",
				"x": b64(point[1:33]), "y": b64(point[33:65])},
			{"kty": "RSA", "kid": "rsa-1", "use": "sig", "alg": "RS256",
				"n": b64(rsaKey.N.Bytes()), "e": b64([]byte{1, 0, 1})},
		}}
		_ = json.NewEncoder(w).Encode(doc)
	}))
	t.Cleanup(f.server.Close)
	f.keys = NewKeySet(f.server.URL, f.server.Client())
	f.v = NewVerifier(f.keys, issuer)
	return f
}

func (f *fixture) token(t *testing.T, kid string, method jwt.SigningMethod, mutate func(jwt.MapClaims)) string {
	t.Helper()
	claims := jwt.MapClaims{
		"iss":   issuer,
		"aud":   "authenticated",
		"sub":   "6f1c2a8e-3b4d-4c5e-9f60-1a2b3c4d5e6f",
		"exp":   time.Now().Add(time.Hour).Unix(),
		"iat":   time.Now().Unix(),
		"role":  "authenticated",
		"email": "Daniel@Example.com",
		"user_metadata": map[string]any{
			"full_name":  "Daniel",
			"avatar_url": "https://example.com/a.png",
		},
	}
	if mutate != nil {
		mutate(claims)
	}
	tok := jwt.NewWithClaims(method, claims)
	tok.Header["kid"] = kid
	var key any = f.ec
	if method.Alg() == "RS256" {
		key = f.rsa
	}
	if method.Alg() == "HS256" {
		key = []byte("legacy-secret")
	}
	s, err := tok.SignedString(key)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestVerifyValidES256(t *testing.T) {
	f := newFixture(t)
	p, err := f.v.Verify(context.Background(), f.token(t, "ec-1", jwt.SigningMethodES256, nil))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if p.Email != "daniel@example.com" || p.UserID != "6f1c2a8e-3b4d-4c5e-9f60-1a2b3c4d5e6f" || p.Name != "Daniel" || p.AvatarURL == "" {
		t.Fatalf("unexpected principal %+v", p)
	}
}

func TestVerifyValidRS256(t *testing.T) {
	f := newFixture(t)
	if _, err := f.v.Verify(context.Background(), f.token(t, "rsa-1", jwt.SigningMethodRS256, nil)); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestVerifyRejects(t *testing.T) {
	f := newFixture(t)
	cases := map[string]string{
		"expired":     f.token(t, "ec-1", jwt.SigningMethodES256, func(c jwt.MapClaims) { c["exp"] = time.Now().Add(-2 * time.Hour).Unix() }),
		"wrong iss":   f.token(t, "ec-1", jwt.SigningMethodES256, func(c jwt.MapClaims) { c["iss"] = "https://other.supabase.co/auth/v1" }),
		"wrong aud":   f.token(t, "ec-1", jwt.SigningMethodES256, func(c jwt.MapClaims) { c["aud"] = "anon" }),
		"wrong role":  f.token(t, "ec-1", jwt.SigningMethodES256, func(c jwt.MapClaims) { c["role"] = "service_role" }),
		"anonymous":   f.token(t, "ec-1", jwt.SigningMethodES256, func(c jwt.MapClaims) { c["is_anonymous"] = true }),
		"no email":    f.token(t, "ec-1", jwt.SigningMethodES256, func(c jwt.MapClaims) { delete(c, "email") }),
		"bad subject": f.token(t, "ec-1", jwt.SigningMethodES256, func(c jwt.MapClaims) { c["sub"] = "not-a-uuid" }),
		"no exp":      f.token(t, "ec-1", jwt.SigningMethodES256, func(c jwt.MapClaims) { delete(c, "exp") }),
		"unknown kid": f.token(t, "ec-9", jwt.SigningMethodES256, nil),
		"hs256":       f.token(t, "ec-1", jwt.SigningMethodHS256, nil),
		"garbage":     "not.a.jwt",
	}
	for name, raw := range cases {
		t.Run(name, func(t *testing.T) {
			_, err := f.v.Verify(context.Background(), raw)
			if !errors.Is(err, ErrInvalidToken) {
				t.Fatalf("expected ErrInvalidToken, got %v", err)
			}
		})
	}
}

func TestKeySetRefreshIsThrottled(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	if _, err := f.keys.Get(ctx, "ec-1"); err != nil {
		t.Fatal(err)
	}
	for range 5 {
		if _, err := f.keys.Get(ctx, "missing"); !errors.Is(err, ErrUnknownKey) {
			t.Fatalf("expected ErrUnknownKey, got %v", err)
		}
	}
	// One initial fetch; unknown kids must not trigger a refetch more than once per minute.
	if got := f.hits.Load(); got != 1 {
		t.Fatalf("expected 1 jwks fetch, got %d", got)
	}
}

func TestKeySetRefreshesWhenStale(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	now := time.Now()
	f.keys.now = func() time.Time { return now }
	if _, err := f.keys.Get(ctx, "ec-1"); err != nil {
		t.Fatal(err)
	}
	now = now.Add(11 * time.Minute)
	if _, err := f.keys.Get(ctx, "ec-1"); err != nil {
		t.Fatal(err)
	}
	if got := f.hits.Load(); got != 2 {
		t.Fatalf("expected a refresh after 10 minutes, got %d fetches", got)
	}
}

func TestAllowlist(t *testing.T) {
	if !NewAllowlist(nil).Allows("anyone@example.com") {
		t.Fatal("empty allowlist must allow everyone (development only)")
	}
	a := NewAllowlist([]string{"a@example.com"})
	if !a.Allows("A@Example.com") || a.Allows("b@example.com") {
		t.Fatal("allowlist must be case-insensitive and exclusive")
	}
}

func TestDevPrincipalIsDeterministicUUID(t *testing.T) {
	p1 := DevPrincipal("Dev@Example.com")
	p2 := DevPrincipal("dev@example.com")
	if p1.UserID != p2.UserID || !uuidRe.MatchString(p1.UserID) || !strings.HasPrefix(p1.UserID[14:], "5") {
		t.Fatalf("unexpected dev principal ids %q / %q", p1.UserID, p2.UserID)
	}
	if p1.Email != "dev@example.com" || p1.Name != "dev" {
		t.Fatalf("unexpected principal %+v", p1)
	}
}
