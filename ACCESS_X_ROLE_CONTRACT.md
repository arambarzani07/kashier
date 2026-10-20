# Access X — two-role identity and provisioning contract

**Design decision (2026-10-20): per market, exactly two human roles: manager (بەڕێوەبەر) and cashier (کاشێر).**

## Authoritative identity mapping

- **Manager** is the authenticated `owner_id` who controls the market's business scope. One primary manager per existing owner-owned market. Do not create the manager as an extra `store_cashiers` member of their own market.
- **Cashier** is an authenticated `member_id` assigned to one market through an enabled cashier membership and a server-validated permission set. The member must not gain `owner_id` privileges by modifying JWT `user_metadata` or by supplying an owner UUID in a request.
- Existing database currently allows `store_cashiers.role='manager'` for a **delegated manager** with only a few manager-scoped reports. This is a transitional permission category, **not** the primary manager. It conflicts with the new identity model and must be migrated/restricted in one reviewed transaction when backups and all RPC rewrites are ready. On 2026-10-20, the live `store_cashiers` table contained zero rows and zero delegated managers. `tests/access-x-two-role-preflight.sql` catches future newly introduced delegated manager rows; it does not block their creation itself.
- Preserve existing historical `owner_id` attribution. Market isolation must be maintained while introducing any future `market_id` foreign key. The primary manager's user can be owner of a separate market even when a cashier in another, but market-specific authorization must be explicit at every endpoint.

## No-invitation cashier provisioning (future production transaction)

1. Primary manager authenticates with secure password/MFA and requests cashier creation **for their own derived market**, not one chosen by request body.
2. A secure server-only endpoint verifies current Supabase Auth user using the bearer access token (`auth.getUser`); checks that user is primary manager; validates cashier name, unique identifier and desired minimal permissions. NEVER trust client-provided `owner_id`, `role`, `auth.user_metadata`, or permissions as authorization evidence.
3. A server-only privileged Auth admin client calls `auth.admin.createUser`. Its secret/service-role key is stored in server/Edge Function secrets only, never in the browser, repository, logs, or downloadable backup. The manager sets a one-time initial password through a protected channel; a reset-at-first-login mechanism is required. No email invitation link is sent.
4. Server records the membership as cashier-only, enabled on first credential proof and with an immutable creation audit. Because Supabase Auth administration and Postgres membership SQL **are not one atomic transaction**, implement an idempotent request record and an explicit compensating cleanup/reconciliation state for a partially created Auth identity. Never mark creation as successful until the member is provisioned and reconciled.
5. Employee completes first online sign-in and credential change. Short PIN is *only* a future trusted-device-local unlock bound to an authenticated user/session, with attempt limits, secure hardware storage and bounded offline validity. It must not silently replace Supabase Auth.
6. Disabling a cashier immediately blocks new backend operations via an authoritative database check; already-issued JWTs cannot be assumed revoked immediately. Device revocation while disconnected cannot take effect until reconnect or local offline lease expiry.

## Cutover blockers

- Backup inventory, encrypted off-site backup and **isolated successful restore rehearsal** are not verified. Do not perform production Auth, membership, grant or RLS cutover without them.
- The current public staff RPC accepts `p_role='manager'`, its schema CHECK allows manager membership, and manager-specific report functions use that role. All of these need coordinated replacement or deprecation. Merely hiding an option in the frontend is not authorization.
- Existing employee acceptance workflow `accept_store_cashier` will be replaced by credential-proof onboarding rather than faked by setting `accepted_at` blindly.
- Backend policy must check the operation and limits inside the same transaction as the money/stock posting; UI role gates are hints only.
- Production Vercel stays in fail-closed maintenance routing; draft credentials must never be exercised against the live cashier screens during this phase.

## Minimum permission model (deny unless granted and validated on server)

| Operation | Primary manager | Cashier default | Conditional grant |
|---|---|---|---|
| Cash sale | allowed | allowed | validated market and session |
| Credit sale | allowed | denied | manager enables `can_credit` |
| Customer repayment | allowed | denied | manager enables `can_repay` |
| Discount | allowed | denied | `can_discount` and future numeric limit |
| Full/partial sale return | allowed | denied | `can_refund` / `can_partial_refund`, source/amount checks |
| Change prices/products | allowed | denied | future audited permission only |
| Inventory purchases/adjustments | allowed | denied | future audited permission only |
| Profit/aggregate financial reports | allowed | denied | manager only |
| Staff management and permission delegation | allowed | denied | NEVER grant to cashier |
| Export/backup/restore | allowed | denied | manager only |

These defaults are a **target specification**; the existing live cash/supplier/sale RPC behavior is **not** modified by this document.

## Verified transaction-only regressions

- `tests/access-x-admin-rls.sql`: detects staff-idempotency/payload conflicts, stale version, unauthorized staff edits by cashier/delegated manager, safe owner disable and immediate catalog denial.
- `tests/access-x-two-role-preflight.sql`: proves no existing delegated manager membership needs migration as of 2026-10-20, without changing constraints.
- Previous `tests/access-x-baseline-rls.sql`, `tests/access-x-membership-rls.sql`, `tests/access-x-manager-rls.sql`, and `tests/access-x-schema-fingerprint.sql` remain in place.

These manual SQL tests are not executed by GitHub's Node-only CI; production database tests were executed in `BEGIN ... ROLLBACK` with synthetic users, and no fixtures persisted.
