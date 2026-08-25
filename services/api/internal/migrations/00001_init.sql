-- +goose Up
CREATE SCHEMA IF NOT EXISTS recanime;

CREATE TABLE recanime.app_user (
  id            uuid PRIMARY KEY,                     -- Supabase auth user id (JWT sub); no FK to auth.users
  email         text NOT NULL,
  display_name  text,
  avatar_url    text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_seen_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX app_user_email_lower_uidx ON recanime.app_user (lower(email));

CREATE TABLE recanime.user_settings (
  user_id     uuid PRIMARY KEY REFERENCES recanime.app_user(id) ON DELETE CASCADE,
  sfw         boolean NOT NULL DEFAULT true,
  timezone    text NOT NULL DEFAULT 'UTC',            -- IANA name, client hint for schedule rendering
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- 12 h cache of GET /anime/{id}/full. Normalized columns for queries, raw payload for everything else.
CREATE TABLE recanime.anime (
  mal_id              integer PRIMARY KEY,
  title               text NOT NULL,
  title_english       text,
  title_japanese      text,
  type                text,
  source              text,
  episodes            integer,
  status              text,                           -- 'Finished Airing' | 'Currently Airing' | 'Not yet aired'
  airing              boolean NOT NULL DEFAULT false,
  aired_from          timestamptz,
  aired_to            timestamptz,
  duration            text,
  rating              text,
  score               numeric(4,2),
  scored_by           integer,
  rank                integer,
  popularity          integer,
  members             integer,
  favorites           integer,
  season              text,
  year                integer,
  broadcast_day       text,
  broadcast_time      text,
  broadcast_timezone  text,
  broadcast_string    text,
  image_url           text,
  image_large_url     text,
  genres              text[] NOT NULL DEFAULT '{}',
  studios             text[] NOT NULL DEFAULT '{}',
  is_adult            boolean NOT NULL DEFAULT false, -- rating Rx or explicit genres (computed in Go)
  raw                 jsonb NOT NULL,                 -- full Jikan "data" object
  fetched_at          timestamptz NOT NULL
);
CREATE INDEX anime_fetched_at_idx ON recanime.anime (fetched_at);
CREATE INDEX anime_airing_idx ON recanime.anime (airing) WHERE airing;

CREATE TABLE recanime.anime_relation (
  from_mal_id  integer NOT NULL REFERENCES recanime.anime(mal_id) ON DELETE CASCADE,
  relation     text NOT NULL,                         -- 'Sequel', 'Prequel', 'Side story', ...
  to_type      text NOT NULL,                         -- 'anime' | 'manga'
  to_mal_id    integer NOT NULL,
  to_name      text NOT NULL,
  PRIMARY KEY (from_mal_id, relation, to_type, to_mal_id)
);
CREATE INDEX anime_relation_to_idx ON recanime.anime_relation (to_mal_id) WHERE to_type = 'anime';

-- Cached list payloads: top / season / seasons_index / search / schedules / anime_recs / episodes.
CREATE TABLE recanime.list_cache (
  cache_key            text PRIMARY KEY,
  kind                 text NOT NULL,
  payload              jsonb NOT NULL,                -- Jikan body: {data, pagination}
  fetched_at           timestamptz NOT NULL,
  upstream_expires_at  timestamptz
);
CREATE INDEX list_cache_kind_fetched_idx ON recanime.list_cache (kind, fetched_at);

CREATE TABLE recanime.library_entry (
  user_id           uuid    NOT NULL REFERENCES recanime.app_user(id) ON DELETE CASCADE,
  mal_id            integer NOT NULL REFERENCES recanime.anime(mal_id),
  status            text    NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','watching','watched')),
  favorite          boolean NOT NULL DEFAULT false,
  episodes_watched  integer NOT NULL DEFAULT 0 CHECK (episodes_watched >= 0),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, mal_id)
);
CREATE INDEX library_entry_user_status_idx ON recanime.library_entry (user_id, status, updated_at DESC);
CREATE INDEX library_entry_user_fav_idx ON recanime.library_entry (user_id, updated_at DESC) WHERE favorite;

-- Belt and braces on Supabase: RLS on with zero policies. The API connects as the table owner,
-- which bypasses RLS, so this only blocks the anon/authenticated PostgREST roles.
ALTER TABLE recanime.app_user        ENABLE ROW LEVEL SECURITY;
ALTER TABLE recanime.user_settings   ENABLE ROW LEVEL SECURITY;
ALTER TABLE recanime.anime           ENABLE ROW LEVEL SECURITY;
ALTER TABLE recanime.anime_relation  ENABLE ROW LEVEL SECURITY;
ALTER TABLE recanime.list_cache      ENABLE ROW LEVEL SECURITY;
ALTER TABLE recanime.library_entry   ENABLE ROW LEVEL SECURITY;

-- Only meaningful on Supabase; the roles do not exist in the local Docker database.
-- +goose StatementBegin
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON SCHEMA recanime FROM anon, authenticated';
    EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA recanime FROM anon, authenticated';
  END IF;
END $$;
-- +goose StatementEnd

-- +goose Down
DROP SCHEMA recanime CASCADE;
