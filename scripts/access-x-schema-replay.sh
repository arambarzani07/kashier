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
  # One transaction per original migration is required for LOCK TABLE and atomic DDL.
  # All migrations are historical and run only on the empty ephemeral database.
  if ! psql -X -v ON_ERROR_STOP=1 --single-transaction -q -f "$file" >> "$report" 2>&1; then
    echo "SCHEMA REPLAY FAILED at migration $number: ${file##*/}" | tee -a "$report"
    exit 1
  fi
done
if ! psql -X -v ON_ERROR_STOP=1 -q -f tests/access-x-replay-inspect.sql >> "$report" 2>&1; then
  echo "Schema parity check FAILED after all 72 migration files applied. Baseline mismatch details:" 
  grep -E '^AX_REPLAY_(ROUTINE|COUNT)\\|' "$report" || true
  tail -n 8 "$report"
  exit 1
fi
# Hash-only metadata diagnostics; no production connection, no customer data.
psql -X -v ON_ERROR_STOP=1 -q -f tests/access-x-catalog-keys.sql >> "$report" 2>&1
psql -X -v ON_ERROR_STOP=1 -q -f tests/access-x-effective-rights.sql >> "$report" 2>&1
grep '^AX_SEM|' "$report" | LC_ALL=C sort -u > /tmp/access-x-actual-rights.txt
LC_ALL=C sort tests/access-x-semantic-rights-20261020.txt > /tmp/access-x-expected-rights.txt
if [[ "$(wc -l < /tmp/access-x-actual-rights.txt)" -ne 221 ]] || ! diff -u /tmp/access-x-expected-rights.txt /tmp/access-x-actual-rights.txt >> "$report" 2>&1; then
  echo "FAIL: effective authenticated/anonymous privileges or policy role scopes differ from live baseline." | tee -a "$report"
  tail -n 35 "$report"
  exit 1
fi
echo "PASS: 221 stable effective rights and RLS policy targets match production baseline." | tee -a "$report"
# Compare complete functions, role grants, policies, indexes, constraints and trigger
# catalog fingerprints with the reviewed production metadata snapshot.
if ! psql -X -v ON_ERROR_STOP=1 -q -f tests/access-x-schema-fingerprint.sql >> "$report" 2>&1; then
  echo "FULL SCHEMA FINGERPRINT FAILED: inspect the isolated metadata, DO NOT write to production." | tee -a "$report"
  grep -E '^(AX_META|AX_SEM)\\|' "$report" || true
  tail -n 12 "$report"
  exit 1
fi
echo "PASS: isolated schema replay and live-catalog fingerprint for all 72 migrations; NOT a production backup restore." | tee -a "$report"
