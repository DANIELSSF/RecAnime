package auth

import "strings"

// Allowlist is the set of emails allowed to use the API. An empty allowlist allows everyone,
// which the configuration only permits in development.
type Allowlist map[string]struct{}

// NewAllowlist builds an allowlist from already-normalized (lower-case) emails.
func NewAllowlist(emails []string) Allowlist {
	a := Allowlist{}
	for _, e := range emails {
		a[strings.ToLower(strings.TrimSpace(e))] = struct{}{}
	}
	return a
}

// Allows reports whether email may use the API.
func (a Allowlist) Allows(email string) bool {
	if len(a) == 0 {
		return true
	}
	_, ok := a[strings.ToLower(strings.TrimSpace(email))]
	return ok
}
