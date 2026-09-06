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

# shellcheck source=infra/db/lib.sh
. "$(dirname -- "$0")/lib.sh"
pg_env_from_url "$DB_URL"
unset DB_URL DATABASE_URL

# Shown in the confirmation prompt so it is clear which database is about to be written to.
TARGET_HOST="$PGHOST:$PGPORT/$PGDATABASE"

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

MAJOR="$(pg_major pg_restore)"

# pg_restore needs -d to connect; the database NAME is not a secret, the rest of the connection comes
# from the PG* variables exported by pg_env_from_url.
if [ "$MAJOR" -ge 17 ]; then
    echo "==> pg_restore $MAJOR (local)"
    # shellcheck disable=SC2086  # FLAGS is a deliberate list of separate arguments.
    pg_restore $FLAGS -d "$PGDATABASE" "$ABS_FILE"
else
    echo "==> pg_restore in Docker (postgres:17-alpine)"
    # shellcheck disable=SC2086  # FLAGS is a deliberate list of separate arguments.
    PGHOST="$(pg_host_for_docker)" docker run --rm \
        -e PGHOST -e PGPORT -e PGUSER -e PGPASSWORD -e PGDATABASE -e PGSSLMODE \
        --add-host host.docker.internal:host-gateway \
        -v "$ABS_FILE:/backup.dump:ro" \
        postgres:17-alpine \
        pg_restore $FLAGS -d "$PGDATABASE" /backup.dump
fi

echo "restored $ABS_FILE"
