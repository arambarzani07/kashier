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


## Isolated replay investigation — 2026-10-20

The first disposable PostgreSQL run failed at migration 5 because `LOCK TABLE` required an explicit transaction. The replay harness now uses one atomic transaction for each unchanged historical migration, and all **72/72 migrations apply cleanly**.

A second test reported 36 apparent extra routines. They were all `pgcrypto` functions installed in scratch `public`; production has that extension in `extensions`. Moving the scratch extension to `extensions` aligned business routine signatures (**148/148**), relations (**35/35**), RLS policies (**36/36**) and noninternal triggers (**7/7**).

A deeper, read-only semantic comparison of **221 public/private schema objects** confirmed **221/221 equivalent effective `anon`/`authenticated` privileges and RLS policy targets**. This has now been captured as a hash-only, business-data-free CI baseline in `tests/access-x-semantic-rights-20261020.txt` and checked automatically during scratch replay. Role OIDs and raw ACL strings differ between managed Supabase and scratch PostgreSQL; those unnormalized hash differences alone do not prove different effective permissions.

**Remaining strict source-drift issue:** exactly **seven function definitions** differ in `pg_get_functiondef()` output between historical migrations and live production. The affected signatures are:

- `private.get_cashier_refund(p_owner uuid, p_id uuid)`
- `private.get_cashier_refund_sale(p_owner uuid, p_sale uuid, p_number bigint)`
- `private.get_cashier_refund_workspace(p_owner uuid)`
- `private.post_cashier_refund(p_owner uuid, p_id uuid, p_sale uuid, p_reason text)`
- `private.post_sale_reversal_for_owner(p_owner uuid, p_id uuid, p_sale uuid, p_reason text)`
- `public.get_cash_statement(p_from date, p_to date)`
- `public.get_supplier_payables_report(p_supplier text, p_query text, p_min_outstanding bigint, p_max_outstanding bigint, p_offset integer, p_limit integer)`

The metadata comparison confirmed the same object keys, **all 35 relation definitions**, **all 36 policy expressions**, **139 indexes**, **291 constraints** and **7 triggers**. The seven function-body differences may indicate post-migration patches or textual rendering differences and require code-level review before asserting schema parity. **Strict fingerprint remains failing intentionally; no production function was overwritten.**

**Do not confuse:** successful migration replay and permission matching is NOT proof that a production backup exists or that a full business-data restore works. Backup recovery Gate C remains **NOT DONE**.

## Complete migration-replay investigation — 2026-10-20

The seven pg_get_functiondef bytewise mismatches were separately fetched **from the production PostgreSQL catalog** and the isolated PostgreSQL 17 replay. Lexical inspection confirmed that five cashier/refund routines and the supplier payable report differ **only in whitespace**, while the cash statement also differs in two **optional AS keywords** for SELECT-column aliases. After preserving quoted SQL literals/comments and applying ONLY these two narrowly scoped alias normalizations, the complete token streams match **7/7**; no genuine SQL token/operation difference was detected.

A new CI gate is replacing the raw ACL/OID/whitespace-sensitive fingerprint comparison with three *pinned*, fail-closed checks: **221 effective grants and policy-target fingerprints** (already verified against live), **214 exact object-definition hashes** (all other routines, relation definitions, policies and schema definitions), and **7 source-token-equivalence fixtures**. The exact **139 index, 291 constraint and 7 trigger** fingerprint matches remain independently established by the earlier strict snapshot investigation, and the catalog-wide code tests must continue to catch unexpected changes.

The old raw fingerprint check deliberately reports differences due to database-specific raw ACL role identifiers, and formatting/optional AS tokens; it is retained for diagnosing live-catalog drift but is not a valid binary test of equivalent freshly replayed environments. The CI gate must pass on a clean isolated replay and must fail if any relevant semantic grant, definition or function token changes.

None of these checks substitutes for a real **encrypted production backup and an isolated restore rehearsal**. Recovery Gate C and production release remain blocked. No migration, owner ID, financial record or production auth permission was modified.

## Validation update — 2026-10-20

The seven reviewed source differences were conclusively checked against `pg_get_functiondef()` output on both live production and replay; **all seven SQL token streams are equivalent**, preserving literal contents and with only two narrowly defined optional SELECT alias `AS` tokens normalized. No production SQL was changed. The isolated CI now enforces **72/72 historical migrations, 221 effective role/ACL/policy fingerprints, 214 byte-equal structural metadata fingerprints and 7 token-equal function definitions**. The run passed at https://github.com/arambarzani07/kashier/actions/runs/39385583050. The general Node suite was **530/530** at https://github.com/arambarzani07/kashier/actions/runs/39385582938.

Previous sections recording the original raw fingerprint mismatch are retained as audit history; those raw string/OID differences do not represent discovered business-logic drift. The stricter semantic replay pipeline is green. **Real-data backup and restore Gate C is still open and remains a production release blocker.**

## Synthetic financial-data dump/restore rehearsal — PASSED 2026-10-20

CI now runs an extra **isolated, synthetic-only** drill after the 72-migration schema replay:

- A single fake Auth ID, product, customer, stock quantity and **real Kashier posting RPCs** produce a 2,500 IQD cash sale, a 25,000 IQD debt charge and a 9,000 IQD repayment.
- The drill first checks that the product stock is **14,000 base units**, customer debt **16,000 IQD**, cash balance **11,500 IQD**, one sale and two debt ledger entries, with proper cash movement and Auth/customer foreign keys.
- A PostgreSQL **17** custom archive is produced using `pg_dump` **inside the same isolated Postgres 17 service container**, then restored with `pg_restore` into a **fresh second PostgreSQL database**, where all the same financial integrity assertions pass.
- CI refuses any nonlocal host, nondesignated database, or invocation without an explicit `ACCESS_X_SYNTHETIC_DRILL=true` opt-in; it does **not** access Supabase's production database, keys, real account data or actual backups. The archive is temporary and removed before job completion; only a sanitized test log is uploaded.
- [Successful synthetic drill and complete schema replay](https://github.com/arambarzani07/kashier/actions/runs/39387247355). [General 532/532 Node regression tests](https://github.com/arambarzani07/kashier/actions/runs/39387247291).
- Test scripts: `scripts/access-x-synthetic-restore.sh`, `tests/access-x-synthetic-fixture.sql`, `tests/access-x-synthetic-verify.sql` and `tests/access-x-synthetic-restore.test.cjs`.

**IMPORTANT: THIS IS NOT A SUCCESSFUL RESTORE OF KASHIER'S REAL DATABASE.** Synthetic recovery exercises Postgres dumping/restoration and sample financial invariants but does not verify the user's real records, full Supabase Auth, Storage, service secrets, off-site encryption, managed backup retention, or recoverability of a user-selected production recovery point. The dump is intentionally created with `--no-acl`, so the separate 221-rule effective grants check remains indispensable.

### Remaining real backup gate (BLOCKING)

1. Verify that an actual restorable backup or safe encrypted full logical export exists in the project dashboard. Check its creation time, retention period, integrity, access and protected storage. **Not checked or confirmed here.**
2. Restore that actual backup to a separately controlled isolated database/Supabase environment (not the production project), with Supabase-managed infrastructure configuration and storage objects treated independently.
3. Verify real owner/customer/debt/cash totals by secure internal audit without logging customer or financial records in CI or GitHub. Compare critical ledger balances, FK integrity and uniqueness with an authorized source snapshot.
4. Record a verifiable restore success with safe metadata and manager approval; only then decide whether Gate C can be closed. Never upload raw backup bytes or secrets into this repository.

Current **Gate C remains CLOSED**. No Production DB schema/Auth permission/data was modified by these tests, no provisioner was deployed, and maintenance routing is still enforced.
