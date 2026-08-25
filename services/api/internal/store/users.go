package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// User is an app_user row joined with its settings.
type User struct {
	ID          string
	Email       string
	DisplayName string
	AvatarURL   string
	CreatedAt   time.Time
	Settings    Settings
}

// Settings are the per-user preferences.
type Settings struct {
	SFW      bool
	Timezone string
}

// SettingsPatch updates only the non-nil fields.
type SettingsPatch struct {
	SFW      *bool
	Timezone *string
}

// UpsertUser records the user on first sight and refreshes profile fields afterwards.
func (s *Store) UpsertUser(ctx context.Context, id, email, displayName, avatarURL string) error {
	return s.withTx(ctx, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			INSERT INTO recanime.app_user (id, email, display_name, avatar_url)
			VALUES ($1, $2, NULLIF($3, ''), NULLIF($4, ''))
			ON CONFLICT (id) DO UPDATE SET
				email        = EXCLUDED.email,
				display_name = COALESCE(EXCLUDED.display_name, recanime.app_user.display_name),
				avatar_url   = COALESCE(EXCLUDED.avatar_url, recanime.app_user.avatar_url),
				last_seen_at = now()`, id, email, displayName, avatarURL)
		if err != nil {
			return fmt.Errorf("upsert user: %w", err)
		}
		_, err = tx.Exec(ctx, `
			INSERT INTO recanime.user_settings (user_id) VALUES ($1)
			ON CONFLICT (user_id) DO NOTHING`, id)
		if err != nil {
			return fmt.Errorf("init settings: %w", err)
		}
		return nil
	})
}

// GetUser returns the user with settings.
func (s *Store) GetUser(ctx context.Context, id string) (User, error) {
	var u User
	var displayName, avatarURL *string
	err := s.pool.QueryRow(ctx, `
		SELECT u.id::text, u.email, u.display_name, u.avatar_url, u.created_at, st.sfw, st.timezone
		FROM recanime.app_user u
		JOIN recanime.user_settings st ON st.user_id = u.id
		WHERE u.id = $1`, id).Scan(&u.ID, &u.Email, &displayName, &avatarURL, &u.CreatedAt, &u.Settings.SFW, &u.Settings.Timezone)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return User{}, ErrNotFound
		}
		return User{}, fmt.Errorf("get user: %w", err)
	}
	u.DisplayName = deref(displayName)
	u.AvatarURL = deref(avatarURL)
	return u, nil
}

// GetSettings returns only the preferences.
func (s *Store) GetSettings(ctx context.Context, userID string) (Settings, error) {
	var st Settings
	err := s.pool.QueryRow(ctx, `SELECT sfw, timezone FROM recanime.user_settings WHERE user_id = $1`, userID).
		Scan(&st.SFW, &st.Timezone)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Settings{}, ErrNotFound
		}
		return Settings{}, fmt.Errorf("get settings: %w", err)
	}
	return st, nil
}

// UpdateSettings applies the patch and returns the new settings.
func (s *Store) UpdateSettings(ctx context.Context, userID string, patch SettingsPatch) (Settings, error) {
	var st Settings
	err := s.pool.QueryRow(ctx, `
		UPDATE recanime.user_settings
		SET sfw = COALESCE($2, sfw), timezone = COALESCE($3, timezone), updated_at = now()
		WHERE user_id = $1
		RETURNING sfw, timezone`, userID, patch.SFW, patch.Timezone).Scan(&st.SFW, &st.Timezone)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return Settings{}, ErrNotFound
		}
		return Settings{}, fmt.Errorf("update settings: %w", err)
	}
	return st, nil
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
