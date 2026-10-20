# Kashêr Access X — staged login server contract (NOT DEPLOYED)

**Status: code and simulated tests only.** Files `access-x/login-core.cjs` and `access-x/supabase-password-adapter.cjs` were prepared on 2026-10-20. They are standalone, server-only modules; there is **no deployed HTTP endpoint**, active market authorization database adapter, durable login rate limiter, session store, or login-release configuration. `vercel.json` continues to rewrite all paths, including `/api/access-x/login`, to `maintenance.html`. Do not open Production on the strength of these tests.

## Login flow and trust boundaries

1. Only the approved backend origin may POST JSON `{email,password}`. The handler rejects other methods, foreign `Origin`, cross-site requests, large bodies, extra parameters, malformed emails and empty credentials. No signup, self-selected `role`, market ID or redirect is accepted.
2. A required distributed `rateLimit` adapter controls attempts **before** calling the Supabase Auth password endpoint; never rely only on in-memory per-instance counters. Client IP must come from a **trusted proxy configuration**, not arbitrary user-supplied headers. Rate-limit failures are fail-closed.
3. `authenticatePassword` signs in against Supabase Auth with an ordinary publishable/anon key. The server then performs an independent network-backed `verifyUser` request. Neither `getSession` user metadata nor the unverified JWT payload can establish permissions. No service-role key is permitted in this Auth adapter.
4. A **new authoritative owner registry** (not present among the live database's ordinary tables on 2026-10-20) must recognize an existing approved market and its **single primary manager**. A generic Supabase Auth user is not automatically a market manager. The `resolveAuthority` adapter must read that authoritative registry and enabled/accepted cashier memberships using a **trusted server-side identity**. Cashier access must have exactly one explicit market scope, prove credential rotation and verify the current membership at every sensitive operation. Delegated legacy `role=manager` membership is never sufficient to become primary manager.
5. `createSession` must write a durable, centrally revocable, high-entropy opaque session ID and bind it to the verified user, market, role, expiry and a fresh authorization check. The caller returns an HTTP-only, Secure, Strict SameSite `__Host-ax_sid` cookie. The session value and Supabase Auth access token are never returned in the JSON body or recorded in logs. Revoke existing tokens/sessions when a cashier is disabled. Implement CSRF defenses and cookie validation on **all protected routes**; UI-only route hiding is not an authorization boundary.
6. Provisioned-but-disabled cashiers get `password_change_required` **without a privileged session cookie**. The initial credential rotation and activation must be implemented in a separate tightly scoped online flow. Avoid allowing an unactivated cashier into the POS even during short offline windows.
7. A valid approved primary manager receives `manager`, and a verified enabled/accepted cashier receives `cashier`; they navigate only to two fixed application destinations. Those destinations currently **do not exist as deployed authenticated workspaces**. There is no account creation or invitation in this login handler.

The handler's `releaseGate:true` is only injectable in isolated unit tests. In a production integration it must be derived from explicit operational signoff and enabled **only after** the backup/restore, owner registry and backend authorization gates are reviewed. Without all five required adapters it returns 503 and never attempts credential verification.

## What still blocks release

- Actual offsite encrypted backup inventory and **isolated successful restoration of real business data**; only synthetic dump/restore has passed.
- Owner/market authorization registry and reviewed no-invitation account provisioning database transition, including a role migration.
- Durable distributed rate limits, audited server-side auth/membership lookup and session creation/rotation/revocation, explicit signed-in page guards and route-level financial RBAC enforcement.
- First-login password rotation, MFA/step-up, lockout recovery, device/offline session revocation and password-leak checks.
- Real end-to-end integration tests with an **isolated Supabase test project**, before touching Production grants/RLS or unblocking maintenance.

## Verification

`node --test tests/access-x-login-core.test.cjs tests/access-x-login-staging.test.cjs`

This suite uses fake identities, fake password tokens and injected backend services only. It never connects to the real Supabase project or modifies data. The older `tests/auth-ui.test.cjs` verifies the Sorani-RTL frontend and its fail-closed response handling.

Documentation used: https://supabase.com/docs/guides/auth/passwords , https://supabase.com/docs/reference/javascript/auth-getuser and https://supabase.com/docs/guides/auth/server-side/creating-a-client .