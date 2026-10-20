#!/usr/bin/env bash
# Offline migration replay in an EPHEMERAL GitHub PostgreSQL 17 service.
# NEVER run this against the production database or with production credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
report="access-x-schema-replay-report.txt"
: > "$report"
if [[ "${PGDATABASE:-}" != "kashier_replay" ]] || [[ "${PGHOST:-}" != "127.0.0.1" ]]; then
  echo "REFUSED: only disposable local kashier_replay is allowed" | tee -a "$report"
  exit 1
fi
if ! command -v psql >/dev/null 2>&1; then
  echo "PostgreSQL client is unavailable on this runner" | tee -a "$report"
  exit 1
fi
echo "Access X isolated Postgres 17 schema replay; NO production connection, NO real records." >> "$report"
psql -X -v ON_ERROR_STOP=1 -q -f tests/access-x-replay-bootstrap.sql >> "$report" 2>&1
mapfile -t files < <(find supabase/migrations -maxdepth 1 -type f -name '*.sql' | LC_ALL=C sort)
if [[ "${#files[@]}" -ne 72 ]]; then
  echo "REFUSED: expected exactly 72 verified migration files, got ${#files[@]}" | tee -a "$report"
  exit 1
fi
number=0
for file in "${files[@]}"; do
  number=$((number+1))
  echo "Apply schema $number/72: ${file##*/}" | tee -a "$report"
  # All migrations are preexisting, historical, and now replayed on empty ephemeral DB only.
  if ! psql -X -v ON_ERROR_STOP=1 -q -f "$file" >> "$report" 2>&1; then
    echo "SCHEMA REPLAY FAILED at migration $number: ${file##*/}" | tee -a "$report"
    exit 1
  fi
done
psql -X -v ON_ERROR_STOP=1 -q -f tests/access-x-replay-inspect.sql >> "$report" 2>&1
echo "PASS: isolated schema replay of all 72 historical migrations; NOT a production backup restore." | tee -a "$report"
