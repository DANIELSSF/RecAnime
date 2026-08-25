package httpapi

import (
	"errors"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/danielssf/recanime/services/api/internal/auth"
)

// AuthConfig controls how /v1 requests are authenticated.
type AuthConfig struct {
	Verifier       *auth.Verifier // nil only when DevBypass is true
	Allowlist      auth.Allowlist
	DevBypass      bool   // development only: trust DEV_BYPASS_EMAIL / X-Dev-User instead of a JWT
	DevBypassEmail string // default principal when bypassing
}

// ensureInterval bounds how often the user row is refreshed from token claims.
const ensureInterval = 10 * time.Minute

type userEnsurer struct {
	mu   sync.Mutex
	seen map[string]time.Time
}

func (u *userEnsurer) due(userID string, now time.Time) bool {
	u.mu.Lock()
	defer u.mu.Unlock()
	if last, ok := u.seen[userID]; ok && now.Sub(last) < ensureInterval {
		return false
	}
	u.seen[userID] = now
	return true
}

// authenticate resolves the caller, enforces the allowlist and records the user.
func (s *Server) authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var p auth.Principal
		if s.deps.Auth.DevBypass {
			email := s.deps.Auth.DevBypassEmail
			if h := strings.TrimSpace(r.Header.Get("X-Dev-User")); h != "" {
				email = h
			}
			p = auth.DevPrincipal(email)
		} else {
			raw, ok := bearerToken(r.Header.Get("Authorization"))
			if !ok {
				writeError(w, r, http.StatusUnauthorized, "unauthorized", "missing bearer token")
				return
			}
			verified, err := s.deps.Auth.Verifier.Verify(r.Context(), raw)
			if err != nil {
				s.deps.Logger.DebugContext(r.Context(), "token rejected", "error", err)
				writeError(w, r, http.StatusUnauthorized, "unauthorized", "invalid or expired token")
				return
			}
			p = verified
		}
		if !s.deps.Auth.Allowlist.Allows(p.Email) {
			writeError(w, r, http.StatusForbidden, "email_not_allowed", "this account is not allowed to use RecAnime")
			return
		}
		if s.ensurer.due(p.UserID, time.Now()) {
			if err := s.deps.Store.UpsertUser(r.Context(), p.UserID, p.Email, p.Name, p.AvatarURL); err != nil {
				s.ensurer.forget(p.UserID)
				s.deps.Logger.ErrorContext(r.Context(), "ensure user", "error", err)
				writeError(w, r, http.StatusInternalServerError, "internal", "could not record user")
				return
			}
		}
		next.ServeHTTP(w, r.WithContext(auth.ContextWithPrincipal(r.Context(), &p)))
	})
}

func (u *userEnsurer) forget(userID string) {
	u.mu.Lock()
	defer u.mu.Unlock()
	delete(u.seen, userID)
}

func bearerToken(header string) (string, bool) {
	const prefix = "bearer "
	if len(header) <= len(prefix) || !strings.EqualFold(header[:len(prefix)], prefix) {
		return "", false
	}
	tok := strings.TrimSpace(header[len(prefix):])
	return tok, tok != ""
}

// mustPrincipal returns the principal set by authenticate (the middleware guarantees it).
func mustPrincipal(r *http.Request) *auth.Principal {
	p := principalFromContext(r.Context())
	if p == nil {
		panic(errors.New("httpapi: handler reached without principal"))
	}
	return p
}
