# Access X cashier provisioning — staged server-only core (NOT DEPLOYED)

This folder contains a server-side **orchestration contract** and Node test suite, **not** a configured service or operational password issuer. It is not imported by `auth.js`, served from `dist`, or deployed to Supabase Edge Functions. Do not call this code ready for cashier login.

## Inputs

Only `request_id` (UUID), `name` (cashier label), `login_email` (individual account email, without invitation), and allowlisted boolean `permissions`. Reject `role`, `owner_id`, `password`, arbitrary privilege flags or additional fields from the caller. Email+initial password is a **temporary online authentication approach**. The desired cashiers' local PIN sign-in is *not implemented*; do not use 6 digits as a new Supabase credential.

## Required durable server adapters

- `verifySession`: a **server-side verified access token** (Supabase `auth.getUser(token)`), not decoded unverified JWT or user-editable `user_metadata`.
- `requirePrimaryManager`: DB-backed current primary owner authority for this market only. A delegated `store_cashiers.role='manager'` is insufficient.
- `requireFreshAuthentication`: require a fresh strong login/step-up authentication verified server-side, especially for creating accounts.
- `reserve`: atomic unique constraint on owner+request UUID; persist canonical SHA-256 payload fingerprint, and return conflict on mismatched reuse. Lock/CAS status transitions across concurrent Edge Function instances and crashed invocations. It MUST NOT trust a caller-provided owner/role.
- `claim`: atomic compare-and-swap only once for a reserved request. Timeout/retry MUST enter controlled reconciliation, not blindly repeat `auth.admin.createUser`.
- `generateTemporaryPassword`: cryptographically secure random password generator in server runtime. Never allow client-selected shared PIN/password; never log plaintext.
- `createAuthUser`: `supabase.auth.admin.createUser({email,password,email_confirm:true})` **server-side only**, with privilege key in secure runtime environment; no `inviteUserByEmail` call. Email confirmation and initial-password policies must be reviewed before rollout.
- `recordAuthIdentity`: durable mapping to the newly created Auth user, before membership activation.
- `attachCashier`: exactly one cashier-only membership bound to authenticated owner, audited permissions, no extra manager. Use a reviewed SQL RPC. **Do not** satisfy legacy `accepted_at` merely by setting a timestamp without credential proof/first-login flow.
- `markReady`: commit active state and membership consistently, after all validations. Invariant: a partly provisioned identity cannot post sales.
- `markForReconciliation`: durable recovery state for ambiguous Auth/DB successes, with cleanup **only after checking** whether Auth user or membership already exists. This implementation intentionally DOES NOT auto-delete identities or retry an uncertain Auth creation.

## Response guarantees

- On success, the initial secret is returned **once** over an authenticated HTTPS response with `Cache-Control: no-store`, never to logs or replay. HTTP handler must enforce CORS origin allowlist, POST only, request size limit, rate limits and CSRF protection when using cookies; an access token in Authorization is required.
- Repeated completed requests return the member ID but **never** the initial password.
- Client-only impersonation fields are rejected. Stale/missing manager authority is hard-denied. No default role escalation.
- The initial secret is **not stored** by this core. Lost first password requires a separate manager-controlled credential reset after final deployment.
- The pure core uses injectable adapters for isolation and regression tests; **no durable adapters or production DB migrations are shipped here**. Failing to install them must refuse the request, not fall back to in-memory storage.

## Gate

Production remains in maintenance mode. Before implementing/deploying adapters, require reviewed backups, a successful isolated restore, verified complete schema replay, a durable provisioning-reservation migration, Auth transaction-reconciliation design, no-delegated-manager migration, first-login credential rotation enforcement, full authorization/financial tests and a staged pilot. Never introduce a service-role key into GitHub frontend assets.

Source: `access-x/provisioning-core.cjs`. Tests: `tests/access-x-provisioning-core.test.cjs`.
