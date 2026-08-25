// Package auth verifies Supabase access tokens and resolves the calling user.
package auth

import "context"

// Principal is the authenticated caller as derived from a verified Supabase JWT.
type Principal struct {
	UserID    string // Supabase auth user id (JWT sub)
	Email     string // lower-cased
	Name      string
	AvatarURL string
}

type principalKey struct{}

// ContextWithPrincipal stores the principal for downstream handlers.
func ContextWithPrincipal(ctx context.Context, p *Principal) context.Context {
	return context.WithValue(ctx, principalKey{}, p)
}

// PrincipalFromContext returns the principal set by the auth middleware, or nil.
func PrincipalFromContext(ctx context.Context) *Principal {
	p, _ := ctx.Value(principalKey{}).(*Principal)
	return p
}
