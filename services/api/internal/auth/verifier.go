package auth

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// ErrInvalidToken wraps every verification failure so callers can map it to 401.
var ErrInvalidToken = errors.New("auth: invalid token")

var uuidRe = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// Verifier validates Supabase access tokens (ES256/RS256) against the project's JWKS.
type Verifier struct {
	keys     *KeySet
	issuer   string
	audience string
	parser   *jwt.Parser
}

// NewVerifier builds a verifier for tokens issued by issuer (https://<ref>.supabase.co/auth/v1).
func NewVerifier(keys *KeySet, issuer string) *Verifier {
	return &Verifier{
		keys:     keys,
		issuer:   issuer,
		audience: "authenticated",
		parser: jwt.NewParser(
			jwt.WithValidMethods([]string{"ES256", "RS256"}),
			jwt.WithIssuer(issuer),
			jwt.WithAudience("authenticated"),
			jwt.WithExpirationRequired(),
			jwt.WithLeeway(60*time.Second),
		),
	}
}

// supabaseClaims are the claims Supabase Auth puts in access tokens that we rely on.
type supabaseClaims struct {
	jwt.RegisteredClaims
	Role         string         `json:"role"`
	Email        string         `json:"email"`
	IsAnonymous  bool           `json:"is_anonymous"`
	UserMetadata map[string]any `json:"user_metadata"`
}

// Verify parses and validates raw and returns the principal it represents.
func (v *Verifier) Verify(ctx context.Context, raw string) (Principal, error) {
	claims := &supabaseClaims{}
	_, err := v.parser.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		kid, _ := t.Header["kid"].(string)
		if kid == "" {
			return nil, errors.New("missing kid header")
		}
		return v.keys.Get(ctx, kid)
	})
	if err != nil {
		return Principal{}, fmt.Errorf("%w: %w", ErrInvalidToken, err)
	}
	if claims.Role != "authenticated" {
		return Principal{}, fmt.Errorf("%w: role %q is not authenticated", ErrInvalidToken, claims.Role)
	}
	if claims.IsAnonymous {
		return Principal{}, fmt.Errorf("%w: anonymous sessions are not allowed", ErrInvalidToken)
	}
	if !uuidRe.MatchString(claims.Subject) {
		return Principal{}, fmt.Errorf("%w: subject is not a uuid", ErrInvalidToken)
	}
	email := strings.ToLower(strings.TrimSpace(claims.Email))
	if email == "" {
		return Principal{}, fmt.Errorf("%w: missing email claim", ErrInvalidToken)
	}
	p := Principal{UserID: strings.ToLower(claims.Subject), Email: email}
	if md := claims.UserMetadata; md != nil {
		p.Name = firstString(md, "full_name", "name")
		p.AvatarURL = firstString(md, "avatar_url", "picture")
	}
	return p, nil
}

func firstString(m map[string]any, keys ...string) string {
	for _, k := range keys {
		if s, ok := m[k].(string); ok && s != "" {
			return s
		}
	}
	return ""
}
