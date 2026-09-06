#!/bin/sh
# Shared by infra/db/backup.sh and restore.sh. Sourced, never executed:
#
#   . "$(dirname -- "$0")/lib.sh"
#
# The connection string is split into libpq's PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE/PGSSLMODE
# variables, so the tools connect without any connection argument and the password never reaches a
# command line (`ps`, shell history, `docker inspect`). A bare PGDATABASE=<uri> does NOT work: libpq
# only expands URIs given as the dbname *argument*, the environment variable is taken literally.

DB_LIB_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

# pg_env_from_url URL — exports the PG* variables for URL (a shell function argument is not argv).
pg_env_from_url() {
    _assignments="$(PG_URL="$1" python3 "$DB_LIB_DIR/pgenv.py")" || return 1
    eval "$_assignments"
    unset _assignments
}

# pg_host_for_docker — inside a container "localhost" is the container itself; point local hosts at
# the Docker host instead. Prints the host to use.
pg_host_for_docker() {
    case "$PGHOST" in
        127.0.0.1 | localhost | ::1) echo host.docker.internal ;;
        *) echo "$PGHOST" ;;
    esac
}

# pg_major TOOL — major version of a local libpq tool, or 0 when absent/unparsable.
pg_major() {
    command -v "$1" >/dev/null 2>&1 || { echo 0; return; }
    _v="$("$1" --version 2>/dev/null | sed -n 's/^.*[[:space:]]\([0-9][0-9]*\).*$/\1/p')"
    case "$_v" in
        '' | *[!0-9]*) echo 0 ;;
        *) echo "$_v" ;;
    esac
}
