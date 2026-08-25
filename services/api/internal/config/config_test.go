package config

import (
	"strings"
	"testing"
	"time"
)

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestLoadDefaults(t *testing.T) {
	c, err := Load(env(map[string]string{
		"DATABASE_URL":         "postgres://x",
		"SUPABASE_PROJECT_REF": "abc",
	}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if c.Port != "8080" || c.CacheTTL != 12*time.Hour || c.JikanRPS != 3 || c.JikanRPM != 60 {
		t.Fatalf("unexpected defaults: %+v", c)
	}
	if got := c.JWKSURL(); got != "https://abc.supabase.co/auth/v1/.well-known/jwks.json" {
		t.Fatalf("jwks url = %q", got)
	}
	if got := c.Issuer(); got != "https://abc.supabase.co/auth/v1" {
		t.Fatalf("issuer = %q", got)
	}
}

func TestLoadRejectsBypassOutsideDevelopment(t *testing.T) {
	_, err := Load(env(map[string]string{
		"DATABASE_URL":        "postgres://x",
		"APP_ENV":             "production",
		"DEV_BYPASS_AUTH":     "true",
		"AUTH_ALLOWED_EMAILS": "a@b.c",
	}))
	if err == nil || !strings.Contains(err.Error(), "DEV_BYPASS_AUTH") {
		t.Fatalf("expected DEV_BYPASS_AUTH error, got %v", err)
	}
}

func TestLoadRequiresAllowlistInProduction(t *testing.T) {
	_, err := Load(env(map[string]string{
		"DATABASE_URL":         "postgres://x",
		"APP_ENV":              "production",
		"SUPABASE_PROJECT_REF": "abc",
	}))
	if err == nil || !strings.Contains(err.Error(), "AUTH_ALLOWED_EMAILS") {
		t.Fatalf("expected AUTH_ALLOWED_EMAILS error, got %v", err)
	}
}

func TestAllowlistNormalization(t *testing.T) {
	c, err := Load(env(map[string]string{
		"DATABASE_URL":         "postgres://x",
		"SUPABASE_PROJECT_REF": "abc",
		"AUTH_ALLOWED_EMAILS":  " A@B.com, c@d.com ,, ",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if len(c.AllowedEmails) != 2 || c.AllowedEmails[0] != "a@b.com" || c.AllowedEmails[1] != "c@d.com" {
		t.Fatalf("allowlist = %v", c.AllowedEmails)
	}
}
