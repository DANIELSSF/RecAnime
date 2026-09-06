"""Prints `export PG*=...` lines for the postgres:// URL found in the PG_URL environment variable.

Used by infra/db/lib.sh so pg_dump/pg_restore connect through libpq's standard variables and the
password never appears on a command line. The URL arrives through the environment for the same reason.
"""

import os
import shlex
import sys
from urllib.parse import parse_qs, unquote, urlsplit

url = os.environ.get("PG_URL", "")
parts = urlsplit(url)
if parts.scheme not in ("postgres", "postgresql") or not parts.hostname:
    sys.exit("PG_URL must be a postgres://user:password@host:port/database?sslmode=... URL")

query = parse_qs(parts.query)
values = {
    "PGHOST": parts.hostname,
    "PGPORT": str(parts.port or 5432),
    "PGUSER": unquote(parts.username or ""),
    "PGPASSWORD": unquote(parts.password or ""),
    "PGDATABASE": unquote(parts.path.lstrip("/")) or "postgres",
    "PGSSLMODE": query.get("sslmode", ["prefer"])[0],
}
for key, value in values.items():
    print(f"export {key}={shlex.quote(value)}")
