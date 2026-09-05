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

// TestScheduleEpisodeBudget covers SCHEDULE_EPISODE_BUDGET: default 6, any non-negative integer
// accepted, negative and non-integer values rejected.
func TestScheduleEpisodeBudget(t *testing.T) {
	base := map[string]string{"DATABASE_URL": "postgres://x", "SUPABASE_PROJECT_REF": "abc"}
	withBudget := func(v string) map[string]string {
		m := map[string]string{}
		for k, val := range base {
			m[k] = val
		}
		if v != "" {
			m["SCHEDULE_EPISODE_BUDGET"] = v
		}
		return m
	}

	cases := []struct {
		name       string
		value      string
		wantBudget int
		wantErr    string
	}{
		{name: "default is 6", value: "", wantBudget: 6},
		{name: "zero is allowed", value: "0", wantBudget: 0},
		{name: "any positive integer is allowed", value: "12", wantBudget: 12},
		{name: "negative is rejected", value: "-1", wantErr: "SCHEDULE_EPISODE_BUDGET"},
		{name: "non-integer is rejected", value: "soon", wantErr: "SCHEDULE_EPISODE_BUDGET"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c, err := Load(env(withBudget(tc.value)))
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected an error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if c.ScheduleEpisodeBudget != tc.wantBudget {
				t.Fatalf("ScheduleEpisodeBudget = %d, want %d", c.ScheduleEpisodeBudget, tc.wantBudget)
			}
		})
	}
}

// TestListCacheRetention covers LIST_CACHE_RETENTION: default 168h, 0 disables the sweep,
// negative and unparsable durations are rejected.
func TestListCacheRetention(t *testing.T) {
	base := map[string]string{"DATABASE_URL": "postgres://x", "SUPABASE_PROJECT_REF": "abc"}
	withRetention := func(v string) map[string]string {
		m := map[string]string{}
		for k, val := range base {
			m[k] = val
		}
		if v != "" {
			m["LIST_CACHE_RETENTION"] = v
		}
		return m
	}

	cases := []struct {
		name          string
		value         string
		wantRetention time.Duration
		wantErr       string
	}{
		{name: "default is 168h", value: "", wantRetention: 168 * time.Hour},
		{name: "zero disables the sweep", value: "0", wantRetention: 0},
		{name: "an explicit duration is honoured", value: "24h", wantRetention: 24 * time.Hour},
		{name: "negative is rejected", value: "-1h", wantErr: "LIST_CACHE_RETENTION"},
		{name: "garbage is rejected", value: "banana", wantErr: "LIST_CACHE_RETENTION"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c, err := Load(env(withRetention(tc.value)))
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected an error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if c.ListCacheRetention != tc.wantRetention {
				t.Fatalf("ListCacheRetention = %v, want %v", c.ListCacheRetention, tc.wantRetention)
			}
		})
	}
}
