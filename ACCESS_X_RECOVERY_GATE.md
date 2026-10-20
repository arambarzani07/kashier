# Kashêr Access X: Disaster recovery — current evidence

**2026-10-20 status: production backup/restore NOT verified. Release gate remains CLOSED.**

This document differentiates three independently necessary recovery proofs.

## A. Scheduled backup availability: UNKNOWN

The connected Supabase project's metadata confirms project `dhfyqxdfwhxlipbsasqf` is `ACTIVE_HEALTHY`, PostgreSQL **17.11.0.003**, region `eu-central-1`. This is *not* evidence of an existing usable database backup. There is currently **no Supabase development branch** associated with the project, and the available connector actions do not include backup inventory/download.

Check the [Supabase Database Backups dashboard](https://supabase.com/dashboard/project/dhfyqxdfwhxlipbsasqf/database/backups/scheduled) for timestamps, retention and restore eligibility. Official docs: https://supabase.com/docs/guides/platform/backups

Supabase documentation says scheduled daily backups are included with Pro, Team, and Enterprise tiers; on Free, regular offsite logical dumps are recommended. We have **not confirmed this project's billing plan or its backup coverage**.

## B. Isolated schema replay: AUTOMATED TEST

`GitHub Actions → Access X isolated schema replay` provisions temporary **PostgreSQL 17** (not a real Supabase project) and replays the **72 historical production migration SQL files** into an empty disposable database, with a small `auth.uid()`/`auth.users`/database-role bootstrap. Failures stop at the exact migration and produce a report artifact.

This verifies syntax and a subset of PostgreSQL schema operations and compares selected counts with the production snapshot. **It does not restore real data**, cannot prove Supabase Auth/Storage internals or secret configuration, and does not establish byte-for-byte schema parity. Its bootstrap is a deliberate approximation, not a cloned production Supabase system.

Files: `tests/access-x-replay-bootstrap.sql`, `tests/access-x-replay-inspect.sql`, `scripts/access-x-schema-replay.sh`, and `.github/workflows/access-x-schema-replay.yml`. Never pass production credentials into this job.

## C. Real offsite backup + isolated restore: NOT DONE

After securing an appropriate database-only private storage destination and obtaining authorized production database credentials (never put credentials or DB dumps in a chat, frontend, CI logs or GitHub):

1. Get a correct Supabase-managed backup if available, *or* create encrypted offsite logical dumps using the [Supabase CLI](https://supabase.com/docs/reference/cli/supabase-db-dump), with schema, data and necessary roles exported separately. Follow the [official restore guide](https://supabase.com/docs/guides/self-hosting/restore-from-platform), and include any external Storage objects separately.
2. Restore into an isolated temporary PostgreSQL/Supabase test environment with no connection to live market data, verify identity mapping, foreign keys, ledger totals and receipt uniqueness; ensure sensitive data stays encrypted and is removed after authorization.
3. Run schema-only diff (functions/grants/policies/indexes/triggers) against fresh migration replay. Investigate and fix discrepancies before adopting the role/permission migration.
4. Record backup timestamp, checksum, encrypted location reference (not credential), restore timestamp, tool versions, counts of failed checks and the manager sign-off. Never share customer details in artifacts.

**DO NOT** call the production project `restore_project` to perform a recovery rehearsal. That command unpauses a project and is not a backup-restore test. Do not create a paid Supabase branch without knowing and approving its cost. The Access X cutover remains blocked until proof C passes.

## Known unresolved security issues

- Supabase advisor warns that leaked-password protection is off: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
- Private restore-receipts table with RLS but no policy is informational (internal service access); do not add a permissive policy casually.
- The draft provisioning reservation tables in `access-x/drafts/` are **not deployed**.

