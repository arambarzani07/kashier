#!/usr/bin/env bash
# Synthetic-only recovery rehearsal on disposable GitHub PostgreSQL 17. NO real backup.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$PGHOST" != "127.0.0.1" || "$PGPORT" != "5432" || "$PGUSER" != "postgres" ||
      "$PGDATABASE" != "kashier_replay" || "$ACCESS_X_SYNTHETIC_DRILL" != "true" ]]; then
 echo 'REFUSED: recovery drill restricted to disposable CI PostgreSQL' >&2
 exit 2
fi
for tool in psql pg_dump pg_restore createdb; do
 command -v "$tool" >/dev/null || { echo "Missing local PostgreSQL tool: $tool" >&2; exit 1; }
done
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo 'Access X synthetic-only recovery: no production credentials or customer records'
psql -X -v ON_ERROR_STOP=1 -q -f tests/access-x-synthetic-fixture.sql >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -f tests/access-x-synthetic-verify.sql >/dev/null
pg_dump --format=custom --no-owner --no-acl --schema=auth --schema=public --schema=private \
  --file "$tmp/recovery.custom" kashier_replay
[[ -s "$tmp/recovery.custom" ]] || { echo 'Synthetic dump empty' >&2; exit 1; }
createdb --template=template0 kashier_restore_check
psql -X -v ON_ERROR_STOP=1 -q -d kashier_restore_check -c \
 'create schema extensions; create extension if not exists pgcrypto with schema extensions; create extension if not exists "uuid-ossp" with schema extensions;' >/dev/null
pg_restore --exit-on-error --single-transaction --no-owner --no-acl \
 --dbname=kashier_restore_check "$tmp/recovery.custom" >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -d kashier_restore_check -f tests/access-x-synthetic-verify.sql >/dev/null
echo 'PASS: synthetic Auth, sale, stock, debt, cash restored to a fresh isolated Postgres DB.'
echo 'NOT VERIFIED: production backup, encrypted storage, or real-data restoration.'
