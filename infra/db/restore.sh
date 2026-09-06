#!/bin/sh
# Restores a dump written by infra/db/backup.sh: rows only, into an existing schema.
#
# The schema must already exist. Create it by starting the API once against the target database
# (DB_MIGRATE_ON_START=true) or with `cd services/api && go run ./cmd/api migrate up`.
# The three tables must be empty, or the restore fails on duplicate primary keys.
#
# Usage, from the repository root (the connection string travels ONLY through the environment):
#   DATABASE_URL='postgres://...' CONFIRM=yes sh infra/db/restore.sh backups/recanime-20260905T101500Z.dump
#   set -a; . ./.env; set +a; CONFIRM=yes make db-restore FILE=backups/<file>.dump
#
# --disable-triggers is on by default and is normally required: library_entry references
# recanime.anime, the Jikan cache, which the dump does not contain, so foreign-key checks would
# reject every row. It needs a superuser (true for the local Docker database). Set DISABLE_TRIGGERS=0
# only when the target already holds the referenced recanime.anime rows.
set -eu

FILE="${1:-}"
DB_URL="${DATABASE_URL:-}"
if [ -z "$FILE" ] || [ -z "$DB_URL" ]; then
    echo "usage: DATABASE_URL='<connection string>' CONFIRM=yes sh infra/db/restore.sh <file.dump>" >&2
    exit 2
fi
if [ ! -f "$FILE" ]; then
    echo "no such file: $FILE" >&2
    exit 1
fi
ABS_FILE="$(CDPATH='' cd -- "$(dirname -- "$FILE")" && pwd)/$(basename -- "$FILE")"

# Host of the target, so the confirmation prompt shows which database is about to be written to
# without echoing the password.
TARGET_HOST="$(printf '%s' "$DB_URL" | sed -n 's#^[a-z]*://\([^@]*@\)\{0,1\}\([^/?]*\).*$#\2#p')"

# --exit-on-error matters: by default pg_restore reports "errors ignored" and still exits 0, which
# would make a half-restored database look like a success.
FLAGS='--data-only --no-owner --exit-on-error'
if [ "${DISABLE_TRIGGERS:-1}" != "0" ]; then
    FLAGS="$FLAGS --disable-triggers"
fi

cat <<EOF
about to restore
  file:   $ABS_FILE
  into:   $TARGET_HOST
  tables: recanime.app_user, recanime.user_settings, recanime.library_entry
  mode:   pg_restore $FLAGS
EOF

if [ "${CONFIRM:-}" != "yes" ]; then
    echo "refusing to restore without CONFIRM=yes" >&2
    exit 1
fi

local_pg_major() {
    command -v pg_restore >/dev/null 2>&1 || return 0
    pg_restore --version 2>/dev/null | sed -n 's/^.*[[:space:]]\([0-9][0-9]*\).*$/\1/p'
}

MAJOR="$(local_pg_major)"
case "$MAJOR" in
    '' | *[!0-9]*) MAJOR=0 ;;
esac

# pg_restore needs -d to connect at all; the empty string makes libpq fall back to PGDATABASE, which
# accepts a full URI, so the password stays out of every command line (host and container).
if [ "$MAJOR" -ge 17 ]; then
    echo "==> pg_restore $MAJOR (local)"
    # shellcheck disable=SC2086  # FLAGS is a deliberate list of separate arguments.
    PGDATABASE="$DB_URL" pg_restore $FLAGS -d '' "$ABS_FILE"
else
    echo "==> pg_restore in Docker (postgres:17-alpine)"
    CONTAINER_URL="$(printf '%s' "$DB_URL" | sed -e 's#@127\.0\.0\.1:#@host.docker.internal:#' -e 's#@localhost:#@host.docker.internal:#')"
    PGDATABASE="$CONTAINER_URL" docker run --rm \
        -e PGDATABASE \
        --add-host host.docker.internal:host-gateway \
        -v "$ABS_FILE:/backup.dump:ro" \
        postgres:17-alpine \
        sh -c "exec pg_restore $FLAGS -d '' /backup.dump"
fi

echo "restored $ABS_FILE"
