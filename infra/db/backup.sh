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

# Major version of the local pg_dump, or empty when there is none.
local_pg_major() {
    command -v pg_dump >/dev/null 2>&1 || return 0
    pg_dump --version 2>/dev/null | sed -n 's/^.*[[:space:]]\([0-9][0-9]*\).*$/\1/p'
}

MAJOR="$(local_pg_major)"
case "$MAJOR" in
    '' | *[!0-9]*) MAJOR=0 ;;
esac

# Written to a .partial first and only renamed on success, so a failed dump never leaves behind a
# truncated file that looks like a backup.
PARTIAL="$OUT.partial"
trap 'rm -f "$PARTIAL"' EXIT INT TERM

# libpq reads the connection URI from PGDATABASE (it behaves like the dbname parameter, which
# accepts a full URI), so neither pg_dump nor the container command line ever carries the password.
if [ "$MAJOR" -ge 17 ]; then
    echo "==> pg_dump $MAJOR (local) -> $OUT"
    # shellcheck disable=SC2086  # TABLES is a deliberate list of separate -t arguments.
    PGDATABASE="$DB_URL" pg_dump --no-owner --no-privileges -Fc $TABLES -f "$PARTIAL"
else
    echo "==> pg_dump in Docker (postgres:17-alpine) -> $OUT"
    # Inside the container "localhost" is the container itself; point local URLs at the host.
    CONTAINER_URL="$(printf '%s' "$DB_URL" | sed -e 's#@127\.0\.0\.1:#@host.docker.internal:#' -e 's#@localhost:#@host.docker.internal:#')"
    PGDATABASE="$CONTAINER_URL" docker run --rm \
        -e PGDATABASE \
        --add-host host.docker.internal:host-gateway \
        postgres:17-alpine \
        sh -c "exec pg_dump --no-owner --no-privileges -Fc $TABLES" >"$PARTIAL"
fi

mv "$PARTIAL" "$OUT"
trap - EXIT INT TERM

echo "wrote $OUT ($(wc -c <"$OUT" | tr -d ' ') bytes)"
echo "restore with: CONFIRM=yes sh infra/db/restore.sh $OUT"
