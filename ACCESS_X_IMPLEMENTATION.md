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
