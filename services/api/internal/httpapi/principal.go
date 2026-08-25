package httpapi

import (
	"context"

	"github.com/danielssf/recanime/services/api/internal/auth"
)

// principalFromContext returns the authenticated principal when the auth middleware ran.
func principalFromContext(ctx context.Context) *auth.Principal {
	return auth.PrincipalFromContext(ctx)
}
