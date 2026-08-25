// Package config loads and validates the API configuration from environment variables.
package config

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

const (
	EnvDevelopment = "development"
	EnvProduction  = "production"
)

// Config is the fully validated runtime configuration.
type Config struct {
	Host     string
	Port     string
	AppEnv   string
	LogLevel string

	DatabaseURL      string
	DBMaxConns       int32
	DBMigrateOnStart bool
	DBSessionLock    bool

	SupabaseProjectRef string
	JWKSURLOverride    string // AUTH_JWKS_URL, tests / self-hosted
	IssuerOverride     string // AUTH_ISSUER, tests / self-hosted
	AllowedEmails      []string
	DevBypassAuth      bool
	DevBypassEmail     string

	JikanBaseURL string
	JikanRPS     int
	JikanRPM     int

	CacheTTL             time.Duration
	SearchTTL            time.Duration
	LiveDebounce         time.Duration
	FranchiseFetchBudget int
}

// IsProduction reports whether the API runs with production safety rules.
func (c Config) IsProduction() bool { return c.AppEnv == EnvProduction }

// JWKSURL is the Supabase JWKS discovery endpoint used to verify access tokens.
func (c Config) JWKSURL() string {
	if c.JWKSURLOverride != "" {
		return c.JWKSURLOverride
	}
	return fmt.Sprintf("https://%s.supabase.co/auth/v1/.well-known/jwks.json", c.SupabaseProjectRef)
}

// Issuer is the expected `iss` claim of Supabase access tokens.
func (c Config) Issuer() string {
	if c.IssuerOverride != "" {
		return c.IssuerOverride
	}
	return fmt.Sprintf("https://%s.supabase.co/auth/v1", c.SupabaseProjectRef)
}

// Load reads the configuration through getenv (usually os.Getenv) and validates it.
func Load(getenv func(string) string) (Config, error) {
	get := func(key, def string) string {
		if v := strings.TrimSpace(getenv(key)); v != "" {
			return v
		}
		return def
	}
	var errs []error
	getInt := func(key string, def int) int {
		v := get(key, "")
		if v == "" {
			return def
		}
		n, err := strconv.Atoi(v)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: expected integer, got %q", key, v))
			return def
		}
		return n
	}
	getBool := func(key string, def bool) bool {
		v := get(key, "")
		if v == "" {
			return def
		}
		b, err := strconv.ParseBool(v)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: expected boolean, got %q", key, v))
			return def
		}
		return b
	}
	getDuration := func(key string, def time.Duration) time.Duration {
		v := get(key, "")
		if v == "" {
			return def
		}
		d, err := time.ParseDuration(v)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: expected duration like 12h, got %q", key, v))
			return def
		}
		return d
	}

	c := Config{
		Host:                 get("HOST", "0.0.0.0"),
		Port:                 get("PORT", "8080"),
		AppEnv:               get("APP_ENV", EnvDevelopment),
		LogLevel:             get("LOG_LEVEL", "info"),
		DatabaseURL:          get("DATABASE_URL", ""),
		DBMaxConns:           int32(getInt("DB_MAX_CONNS", 4)),
		DBMigrateOnStart:     getBool("DB_MIGRATE_ON_START", true),
		DBSessionLock:        getBool("DB_SESSION_LOCK", true),
		SupabaseProjectRef:   get("SUPABASE_PROJECT_REF", ""),
		JWKSURLOverride:      get("AUTH_JWKS_URL", ""),
		IssuerOverride:       get("AUTH_ISSUER", ""),
		AllowedEmails:        splitEmails(get("AUTH_ALLOWED_EMAILS", "")),
		DevBypassAuth:        getBool("DEV_BYPASS_AUTH", false),
		DevBypassEmail:       strings.ToLower(get("DEV_BYPASS_EMAIL", "dev@example.com")),
		JikanBaseURL:         strings.TrimRight(get("JIKAN_BASE_URL", "https://api.jikan.moe/v4"), "/"),
		JikanRPS:             getInt("JIKAN_RPS", 3),
		JikanRPM:             getInt("JIKAN_RPM", 60),
		CacheTTL:             getDuration("CACHE_TTL", 12*time.Hour),
		SearchTTL:            getDuration("SEARCH_TTL", 12*time.Hour),
		LiveDebounce:         getDuration("LIVE_DEBOUNCE", 30*time.Second),
		FranchiseFetchBudget: getInt("FRANCHISE_FETCH_BUDGET", 4),
	}

	switch c.AppEnv {
	case EnvDevelopment, EnvProduction:
	default:
		errs = append(errs, fmt.Errorf("APP_ENV: must be %q or %q, got %q", EnvDevelopment, EnvProduction, c.AppEnv))
	}
	if c.DatabaseURL == "" {
		errs = append(errs, errors.New("DATABASE_URL: required"))
	}
	if c.DBMaxConns < 1 {
		errs = append(errs, errors.New("DB_MAX_CONNS: must be >= 1"))
	}
	if c.JikanRPS < 1 || c.JikanRPM < 1 {
		errs = append(errs, errors.New("JIKAN_RPS and JIKAN_RPM: must be >= 1"))
	}
	if c.FranchiseFetchBudget < 0 {
		errs = append(errs, errors.New("FRANCHISE_FETCH_BUDGET: must be >= 0"))
	}
	if c.DevBypassAuth && c.AppEnv != EnvDevelopment {
		// Refuse to start: the bypass must never reach a deployed binary.
		errs = append(errs, errors.New("DEV_BYPASS_AUTH: only allowed when APP_ENV=development"))
	}
	if !c.DevBypassAuth && c.SupabaseProjectRef == "" && c.JWKSURLOverride == "" {
		errs = append(errs, errors.New("SUPABASE_PROJECT_REF: required unless DEV_BYPASS_AUTH=true"))
	}
	if c.IsProduction() && len(c.AllowedEmails) == 0 {
		errs = append(errs, errors.New("AUTH_ALLOWED_EMAILS: required in production"))
	}
	if len(errs) > 0 {
		return Config{}, fmt.Errorf("invalid configuration: %w", errors.Join(errs...))
	}
	return c, nil
}

// splitEmails normalizes a comma-separated allowlist to lower-case, trimmed entries.
func splitEmails(raw string) []string {
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.ToLower(strings.TrimSpace(p))
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
