#!/bin/sh
# Dumps the only irreplaceable data in the database: the users, their settings and their library.
# Everything else (recanime.anime, anime_relation, list_cache) is a Jikan cache that rebuilds itself.
#
# Usage, from the repository root (the connection string travels ONLY through the environment, so
# the password never shows up in `ps` or in shell history):
#   DATABASE_URL='postgres://user:pass@host:5432/postgres?sslmode=require' sh infra/db/backup.sh
#   set -a; . ./.env; set +a; make db-backup          # local Docker database
#
# Writes backups/recanime-<UTC timestamp>.dump (custom format, restore with infra/db/restore.sh).
# Uses the local pg_dump when it is version 17 or newer, otherwise postgres:17-alpine in Docker.
set -eu
# Dumps hold the users' emails and libraries: owner-only files.
umask 077

DB_URL="${DATABASE_URL:-}"
if [ -z "$DB_URL" ]; then
    echo "usage: DATABASE_URL='<connection string>' sh infra/db/backup.sh" >&2
    exit 2
fi

# shellcheck source=infra/db/lib.sh
. "$(dirname -- "$0")/lib.sh"
pg_env_from_url "$DB_URL"
unset DB_URL DATABASE_URL

REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)"
OUT_DIR="$REPO_ROOT/backups"
OUT="$OUT_DIR/recanime-$(date -u +%Y%m%dT%H%M%SZ).dump"
if [ -e "$OUT" ]; then
    echo "refusing to overwrite $OUT" >&2
    exit 1
fi
mkdir -p "$OUT_DIR"

# The three tables the app owns, in FK order (app_user first).
TABLES='-t recanime.app_user -t recanime.user_settings -t recanime.library_entry'

MAJOR="$(pg_major pg_dump)"

# Written to a .partial first and only renamed on success, so a failed dump never leaves behind a
# truncated file that looks like a backup.
PARTIAL="$OUT.partial"
trap 'rm -f "$PARTIAL"' EXIT INT TERM

# The PG* variables exported by pg_env_from_url carry the connection; no argument does.
if [ "$MAJOR" -ge 17 ]; then
    echo "==> pg_dump $MAJOR (local) -> $OUT"
    # shellcheck disable=SC2086  # TABLES is a deliberate list of separate -t arguments.
    pg_dump --no-owner --no-privileges -Fc $TABLES -f "$PARTIAL"
else
    echo "==> pg_dump in Docker (postgres:17-alpine) -> $OUT"
    # shellcheck disable=SC2086  # TABLES is a deliberate list of separate -t arguments.
    PGHOST="$(pg_host_for_docker)" docker run --rm \
        -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE -e PGSSLMODE \
        --add-host host.docker.internal:host-gateway \
        postgres:17-alpine \
        pg_dump --no-owner --no-privileges -Fc $TABLES >"$PARTIAL"
fi

mv "$PARTIAL" "$OUT"
trap - EXIT INT TERM

echo "wrote $OUT ($(wc -c <"$OUT" | tr -d ' ') bytes)"
echo "restore with: CONFIRM=yes sh infra/db/restore.sh $OUT"
