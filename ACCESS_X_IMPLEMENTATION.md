# Kashêr Access X — implementation blueprint and Phase 1 audit

Status: **Phase 1 started, verified; no authentication cutover**.
Date: 2026-10-20 (Asia/Baghdad).
Target: **exactly two user-visible roles per market: manager (بەڕێوەبەر) and cashier (کاشێر)**. One primary manager/account authority per market; multiple cashier identities. No third operational role, no invitation-link workflow. Kurdish Sorani RTL throughout.

## Scope and non-negotiable safety rules

- Preserve all existing products, stocks, customer/supplier debts, receipts, balances, ledgers, cash movements, audit entries, and authentication accounts. Never relabel ownership in place or delete historical records to accommodate roles.
- Every market has an isolated security scope. No role may read/write another market. Enforce authorization in server-side RPCs and Postgres RLS, not by hiding UI controls.
- Transactions must remain atomic, idempotent by request UUID, and have immutable actor/market attribution.
- Phase 1 through production online cutover comes **before** optional Windows/offline credentials. A 6-digit cashier PIN is not a standalone Supabase session; only use it to unlock a pre-authorized, expiry-limited, device-bound identity once a secure local component exists.
- Manager provisions cashier identities from inside the application, without email invitation links. Server-side privileged Auth administration only; **never** put service_role keys in browser JavaScript.
- Default-deny; individual cashier permissions never imply owner-level access. Document a specific permission/limit for credit, repayment, return, partial return, discount, price change, stock, reporting, export, and financial settings.
- Owner is the account authority. Existing `store_cashiers.role='manager'` is not proof that another owner account can exist; review and explicitly constrain delegated manager semantics before cutover.

## Observed baseline (live Supabase, 2026-10-20)

Repository: `arambarzani07/kashier`. Linked Supabase project: `dhfyqxdfwhxlipbsasqf`.

- Online frontend `auth.html` / `auth.js` uses email/password and self-signup; `data.js` uses browser session storage. No cashier PIN screen or secure offline unlock in this repository.
- Live database has `public.store_cashiers` (`owner_id`, `member_id`, `role`, `enabled`, `accepted_at`, `version`, capability booleans) and `public.staff_actions`. It has `public.save_store_cashier`, `public.accept_store_cashier`, `public.get_staff_workspace`, `public.get_cashier_catalog`, and guarded cashier posting functions. Current onboarding requires an existing `auth.users` member plus explicit acceptance; it **does not yet meet** the no-invitation requirement.
- All currently enumerated `public` ordinary tables have RLS enabled; key business SELECT policies scope to `auth.uid()=owner_id`; staff tables use owner/member read predicates. `private.cashier_membership` checks enabled and accepted status before privileged access.
- No `market_id` on core sales, products, cash movements, debts or existing staff rows; `owner_id` is currently the de facto market identifier. **Do not casually replace it**.
- Live database contains identity/staff and other later schema objects that have no matching migration in the repository's `supabase/migrations` folder. **Schema drift is a release blocker**: obtain and review the complete live schema as a migration baseline before modifying existing security primitives.
- Supabase security advisor: leaked-password protection disabled (WARN; configure in Auth settings); `private.owner_restore_receipts` RLS has no policy (INFO; private schema, inspect intended access before any modification).

## Verification executed against live database (transaction-rollback)

1. `tests/access-x-baseline-rls.sql` — PASS. Read-only transaction, enumerates table RLS; verifies critical owner/member policy shapes; rejects anon write RPC exposure and direct authenticated access to select private owner helpers; checks membership gating implementation.
2. `tests/access-x-membership-rls.sql` — PASS. Uses generated users and product only inside `BEGIN ... ROLLBACK`; verifies pending cashier denial, no direct owner-product read, accepted scoped catalog access, cross-owner rejection and revoked/disabled rejection. **No test fixtures persist.**

These are baseline regression checks, **not** an independent security penetration test. Function body checks and policy text checks alone do not prove arbitrary RPCs safe. Future changes require transaction-based end-to-end authorization tests for each privileged RPC and every supported role.

## Milestones and release gates

### Gate 1 — audit and reconciliation (started)

- [x] Inspect repository auth/login and state of live membership/RLS.
- [x] Execute repeatable baseline and dynamic membership-isolation SQL checks.
- [x] Store immutable baseline findings and tests alongside repository.
- [ ] Inventory all live RPC signatures/grants/triggers and align full migrations with production schema. Never apply an older migration that drops newer functions.
- [ ] Verify restorable database backup and non-production restore rehearsal. A data export alone is not a server-level database backup.
- [ ] Audit manager privileges separately from cashier privileges and enumerate every direct-data route.

**Exit:** schema history reconciled + recovery rehearsal + security review accepted. No production auth/RLS cutover before exit.

### Gate 2 — identity and market data model

- One primary manager owning the business namespace and zero or more cashiers. Reuse existing owner ID as compatibility scope; introduce stable `market_id` only with audited owner-to-market mapping.
- Separate authentication identity, market membership, role, permission grants, trusted devices, access sessions and approval tokens. Uniqueness and foreign keys; RLS enabled; deny anonymous access.
- Provision cashier from owner-authorized server endpoint, without invitation/acceptance flow, with initial credential rotation and verified identity binding.
- Never weaken current owner policies just to grant cashier access: use narrowly scoped RPCs and role checks.

**Exit:** complete owner/cashier/nonmember isolation tests, migrations forward/backward strategy, no business data loss.

### Gate 3 — permission engine and transaction protection

- Every sensitive RPC resolves actor from authenticated context, membership and market from database, and operation-level capability/limits inside the same SQL transaction.
- Manager approvals bind one request UUID, actor, market, action, amount, scope and expiry; single use, recorded audit and no duplicate posting. Limit discounts/returns independently of UI.
- Test role revocation, race conditions, duplicate requests, changed permissions during shift, cross-account payload injection and historical owner flows.

**Exit:** all privileges fail closed, all financial invariants preserved.

### Gate 4 — Kurdish RTL Access UI + staff center

- One responsive entry screen: recognized-market state, manager secure sign-in, cashier identity choice, locked/revoked state, account recovery. No email invitation links.
- Manager-only cashier creation, disable, reset, capability toggles, and history. Show only actionable sections for cashier; server gate remains source of truth.
- Preserve safe return URLs, accessibility, error feedback and current sessions until a verified cutover.

**Exit:** complete browser and authenticated multi-user QA with regression suite green.

### Gate 5 — controlled deployment

- Snapshot + rollback point; staged rollout; monitor rejected RPCs and financial-posting error rates.
- Cut over only if owner, cashier, denied user, and newly created user complete real authorized flows. Revert if membership or ledger access regresses.

### Gate 6 — later Windows offline access

- Only after online completion: hardware-bound secure local key storage, expiring offline authorization, PIN attempt limits, encrypted local database, device revoke propagation on reconnect and strict receipt/ledger sync conflict handling.
- Never claim remote revoke instant while a device is disconnected.

## Operational commands

With an authorized SQL connection, run the two scripts in `tests/`; each ends in `ROLLBACK`. GitHub CI currently executes Node tests only and **does not execute DB authorization tests without a supplied isolated test database**. Do not run migration write tests against real market records.

## Gate 1 checkpoint — migration history reconciled on 2026-10-20

**Observed: 72 applied migration history rows and 72 corresponding SQL files.** The `main` branch only held 48 files. The 24 missing *already applied* migration files were recovered byte-for-byte from the project's existing `fix/localized-allocation-amounts` branch and committed to `main` unchanged. These include installments, inventory costing, staff RPCs and daily cash close. **No SQL was executed/applied as part of this repository recovery**, and this is not a schema-change deployment. `supabase/applied-migrations-20261020.txt` is the verified server history inventory, and CI's `tests/migrations-baseline.test.cjs` checks that it still matches the repository. If newer migrations are intentionally added, update the baseline after applying and verifying them; do not update the baseline merely to hide drift.

This closes the **migration-file inventory mismatch only**. It does not prove that every SQL function, view, trigger, policy, grant or schema object currently in the live database exactly matches the text of its recorded migration (ad hoc DDL could also have changed them). Preserve a full `pg_dump --schema-only` / `supabase db pull` and compare against clean replay in a separate isolated database before any privilege cutover. Backup/restore rehearsal is still pending. Do **not** automatically run these historic migrations again on the live database.

### Production publishing guard

The previous `main` deployment failed because the Vercel project build command referenced absent `scripts/release-check.cjs`. This release restores that path with a **maintenance-only, fail-closed validator**, adds identical top-level and `dist/maintenance.html`, and sets the proven maintenance-only Vercel routing pattern. The build checks self-contained maintenance output and rejects script/form embedding or unauthorized app paths; it deliberately does **not** publish cashier UI. New `tests/maintenance-deploy.test.cjs` protects the route contract in GitHub CI.

**Release warning:** The current `main` `dist` directory is incomplete and is not a full application production build. Do not remove the maintenance rewrite until source/output parity, complete functional CI, reviewed authorization cutover, and owner acceptance. The full frontend/staff functionality on the separate development branch is not merged by this migration recovery.

## Gate 1 checkpoint — role isolation, schema fingerprint, and recovery blockers (2026-10-20)

### Live test evidence

- `tests/access-x-manager-rls.sql`: **PASS** using four synthetic Auth users *inside one rollback-only transaction*. Manager read of own market sales report succeeded, cross-market access failed, ordinary cashier access to a manager-only report failed, and manager-to-cashier downgrade removed access immediately. The manager's own account dashboard remained outside the membership's scope. SQL run creates **no persistent staff or business data**.
- `tests/access-x-schema-fingerprint.sql`: **PASS** in a read-only transaction. Reviewed live Postgres `public` and `private` catalog: **35 relations (tables/views), 148 routines, 36 RLS policies, 7 noninternal triggers, 139 indexes, 291 constraints and 2 schema ACL records**. The script fingerprints definitions, relation attributes/options/ACLs, policy roles/expressions, indexes, constraints, triggers and schema ACLs and fails on drift.
- Fingerprint verification is a **baseline integrity warning**, NOT a full schema-vs-clean-migration comparison. An intentional schema migration must be reviewed and re-baselined; the hash itself is not a backup.
- Live `public` views are `security_invoker=true` (four views); all public SQL RPCs are `SECURITY INVOKER`, and none grant direct `EXECUTE` to `anon`. RLS remains enabled on all ordinary `public` tables.

### Access-model gaps to resolve before release

1. Existing database distinguishes the primary `owner_id` (which controls core ledger and catalog via RLS) from a `store_cashiers.role='manager'` membership. A manager member currently gets guarded sales read/report endpoints, **not** all owner administrative rights. Define whether a manager membership should *ever* exist when the product requires a single primary manager, and migrate/limit carefully. Do not reassign data ownership by simply changing `role`.
2. Manager-created staff with **no invitation** is not available yet. Existing `private.save_store_cashier` accepts only existing `auth.users` and `private.accept_store_cashier` requires employee acceptance. Server-controlled Auth provisioning and employee-owned credentials are required; never put privileged keys in browser code.
3. Grant hygiene: `private.post_supplier_purchase_payment` currently inherits `EXECUTE` for `anon` via default `PUBLIC` function privilege, but **anon has no USAGE on the private schema**, so it is not an exposed anonymous Data API RPC. Explicitly `REVOKE EXECUTE ON FUNCTION ... FROM PUBLIC, anon` in a reviewed future migration and preserve required authenticated access; do not modify privileges until backup and restore gates pass.
4. The live Supabase security advisor still reports leaked-password checking disabled. Enable in the Auth project configuration as a separate review action: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection. The private restore receipts no-RLS-policy INFO should be reviewed against intended internal-only usage, not fixed by permissive public policy.

### Backup and restore gate (NOT passed)

- No existing Supabase development branch was found during this inspection. This connector does **not** expose a scheduled-backups inventory or produce a verified full Postgres backup, so backup coverage **has not been confirmed**. An application export is not equivalent to a physical/logical database backup.
- Using the Supabase Dashboard, check [Database Backups](https://supabase.com/dashboard/project/dhfyqxdfwhxlipbsasqf/database/backups/scheduled), retention and recovery availability. If the project's plan has no scheduled backups, create a secure `supabase db dump` / `pg_dump` to a **private** encrypted destination off the production service; never commit user/financial data, credentials or dumps to GitHub.
- Before enabling new roles: restore into a separately isolated local/test Postgres (no production writes), replay the 72 historic migrations there, compare `pg_dump --schema-only` results and verify representative anonymized account/ledger balances and referential integrity. Provisioning a paid Supabase branch requires an explicit cost agreement; none was created here.

**Release gate remains closed.** Do not re-enable auth, financial posting screens, or offline PIN unlock until schema equivalence and restore verification are proven.

## Gate 1 checkpoint — single primary manager and staff administration (2026-10-20)

- **PASS**: `tests/access-x-admin-rls.sql` runs authenticated owner/cashier/delegated manager sessions in a synthetic rolled-back transaction; request replay is idempotent, payload conflict and stale versions rejected, member roles cannot mutate owner-controlled staff, owner disable revokes privileged cashier catalog reads. The test does **not** claim a cashier is unable to be the owner of their own separate account.
- **PASS**: `tests/access-x-two-role-preflight.sql` verified no existing delegated manager membership needs migration (live membership count: 0). This is a read-only preflight, **not** future-role enforcement; current manager member creation is still possible until the coordinated cutover.
- Target business model, manager-created cashier without invitation, activation/security constraints and the full two-role permission matrix are in `ACCESS_X_ROLE_CONTRACT.md`.
- Backup inventory and isolated restore remain **unverified**. No server Auth or RLS modification was applied; maintenance UI remains on.

## Gate 2 development checkpoint — no-invitation provisioner (STAGED, not live)

- Added `access-x/provisioning-core.cjs` pure Node server orchestration and `tests/access-x-provisioning-core.test.cjs` regression suite. Only authenticated primary managers with fresh identity verification can initiate requests. Untrusted role/owner/password fields are rejected. The service requires durable reservations and concurrency-safe compare-and-swap, generates the initial password on server, creates a cashier-only identity, and transitions ambiguous Auth/SQL outcomes to manual reconciliation without deleting or retrying blindly.
- This is **not a working production endpoint**. The adapter interfaces are deliberately unimplemented and fail closed. No Supabase Auth user is created, no production SQL migration applied, no secrets provisioned, no Vercel runtime route added and no live cashier login enabled. See `access-x/README.md`.
- Next prerequisites are backups/restore, exact schema replay, reviewed server-side durable reservation schema, provisioning endpoint and credential rotation policy; then a controlled test-environment deployment.

## Gate 2 checkpoint — staged durable reservation draft (not live)

- Drafted `access-x/drafts/provisioning-reservation-schema.sql` with service-role-only reserved/claimed/identity_created/provisioned/reconciliation transitions, server-origin authorization contract and one-way concurrency claim. No production DDL has been applied; the draft has only static checks, **not** an isolated Postgres execution test.
- Updated the server-only provisioning core to refuse calling a newly provisioned cashier "ready" before credentials are proven and rotated. Membership must be recorded disabled, not accepted/activated on issuance.
- Added `tests/access-x-provisioning-schema.test.cjs` to CI to guard draft permission patterns and ensure it stays outside `supabase/migrations`. Durable production adapters, event immutability, token freshness, real isolated SQL tests, off-site backup + restore and user activation are still missing.

## Gate 1: isolated schema replay harness (2026-10-20)

Added a GitHub Actions runner with disposable PostgreSQL 17 and a minimal Supabase Auth stub to replay the 72 historic migration files and compare relation/function/policy/trigger counts. This is a **schema-only test**, not a backup, not a real restore, and does not authorize release. See `ACCESS_X_RECOVERY_GATE.md`. Test status must be checked in the Actions run, not inferred from the existence of this document. Production backup inventory and isolated *real-data* restore remain unavailable/unverified.

## Gate 1 — isolated replay and semantic equivalence (VERIFIED 2026-10-20)

- **PASS, isolated GitHub PostgreSQL 17:** all 72 unchanged migration scripts replay on an empty temporary DB, with one atomic transaction per migration. This validates reproducibility of the application schema without connecting to live production. Run: https://github.com/arambarzani07/kashier/actions/runs/39385583050
- **PASS, 221/221** exact fingerprints of effective \`anon\`/\`authenticated\` access, column/table/function privileges and RLS policy role scope.
- **PASS, 214/214** exact catalog definition fingerprints of the remaining application functions, relations, policies and schema catalog keys.
- **PASS, 7/7** lexical SQL-token equivalence: residual function-definition string differences consist of whitespace formatting and two explicit optional \`AS\` aliases in the cash statement. The verifier preserves SQL string literal text and only normalizes those two reviewed alias locations.
- **PASS, 530/530** general Node CI assertions (https://github.com/arambarzani07/kashier/actions/runs/39385582938), including deliberate metadata tampering regression tests that must fail.
- The older \`access-x-schema-fingerprint.sql\` *raw* hash check remains available for direct production drift monitoring. It is **not appropriate as the isolated replay acceptance gate**, because raw role OIDs/ACL format and whitespace-dependent SQL output differ between Supabase and scratch Postgres; it was replaced in the disposable CI job by specific effective privilege + structural + token checks.
- Still **NOT VERIFIED:** whether a restorable real production backup exists; no offsite encrypted DB export, successful real-data restore, isolated end-to-end Auth recreation, or financial balance restoration has been demonstrated. **Production authorization and cashier activation remain blocked**.


## Backup rehearsal checkpoint — staged Gate C subtest (2026-10-20)

- **PASS, synthetic-only**: one fake customer/product and actual app cash-sale and debt/repayment posting RPCs were backed up with PostgreSQL 17 `pg_dump` and restored using `pg_restore` into a fresh disposable database. Asserted product stock, cash balance, customer debt, sale, cash movement and debt entries both before and after restoration.
- **PASS 532/532** Node tests, and **PASS** combined schema parity + synthetic financial restore workflow. Evidence: `ACCESS_X_RECOVERY_GATE.md`; [CI run](https://github.com/arambarzani07/kashier/actions/runs/39387247355).
- **NOT DONE**: a real market database backup and isolated restore. This cannot be inferred from generated fixtures or migration replay. Production activation, RLS/privilege cutover and no-invitation Auth provisioning still blocked.


## Access X login source design checkpoint — STAGED (2026-10-20)

Old self-signup/browser-based login entry was replaced with a standalone Sorani RTL two-role, no-registration UI at `auth.html`/`auth.js`. Server-verified manager/cashier session is mandatory for any redirect; unsupported role or absent backend denies login. The backend and role workspaces are NOT deployed; the Vercel maintenance gate remains in force. See `ACCESS_X_LOGIN_UI.md`.

## Access X login backend checkpoint — staged 2026-10-20

- Added framework-agnostic **server-only** HTTP login contract in `access-x/login-core.cjs` (disabled without explicit complete release gate + backend adapters), a dependency-free HTTPS Supabase Auth password / getUser adapter using only a publishable/anon key, and 15 isolated Node tests. Tests cover wrong origins, malformed requests, rate limits, generic invalid-credential behavior, authoritative primary owner and cashier proof, nonactive cashier activation, safe cookie flags, no password/token leaks, and maintenance-only routes.
- **No endpoint was deployed, no session store/market registry/rate-limit adapter was implemented, no service-role key was added, no Auth account or financial record was changed**. All role/market authorities still require a reviewed server/database implementation. `vercel.json` stays maintenance-only. See `ACCESS_X_LOGIN_BACKEND.md`.
- Next gate: real market/owner registry, durable rate limits + sessions, credential rotation, protected workspaces and successfully restored actual offsite backup. Never treat client UI or injected test adapters as production authorization.

## Access X server login checkpoint — backend orchestration STAGED

A fail-closed server-only login core and HTTP adapter under `access-x/server/` now require verified Auth identity, a primary owner market register or enabled accepted cashier membership, first-password-rotation evidence, manager step-up and a durable opaque session cookie. The handler is default-disabled (503) and **NOT deployed at any /api path**. Current live database lacks a dedicated primary market register and durable session/rotation stores; production release stays blocked. See `ACCESS_X_SERVER_LOGIN.md`.
