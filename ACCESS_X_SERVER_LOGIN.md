# Access X — server login contract (STAGED, NOT DEPLOYED)

As of 2026-10-20, \`access-x/server/login-core.cjs\` includes a **fail-closed** server-only login orchestration and HTTP adapter. It is **not** under Vercel's \`api/\` directory, cannot be called over the Internet, and defaults to HTTP 503 if instantiated without \`enabled:true\`. Production Vercel routing remains maintenance-only. No Supabase credentials or customer data are stored in this file.

## Server validation sequence

1. Require POST, exact known HTTPS Origin, JSON, payload limit, and a durable server-controlled rate limiter. Validate *only* email and password input. Refuse request-supplied market, user ID, role, admin, next URL or cookie parameters.
2. The server auth adapter calls Supabase Auth \`signInWithPassword\`; a **separate** \`getUser(access_token)\` adapter verifies the authenticated identity. Never use a decoded JWT, \`getSession\`, a user-editable \`user_metadata\`, or an \`owner_id\` supplied by the browser to grant authority.
3. Read **authoritative DB-backed owner scopes** and complete cashier memberships for the verified user. Only one primary owned market is allowed for manager login; a cashier must have exactly one membership with \`role='cashier'\`, \`enabled=true\`, \`accepted_at\` present, and a valid owner/market scope. Ambiguous multi-market memberships fail closed until a separately designed scoped workspace picker exists. Delegated \`role='manager'\` does not count as a primary manager.
4. A separate database-backed credential policy must prove that first-login password rotation completed and account use is permitted. Manager requires appropriate step-up assurance (\`aal2\` in this staging contract). A disabled, unaccepted cashier may receive a \`password_change_required\` status **only after** an independent server-verified provisioning state check; this result creates **NO** authenticated session.
5. The session adapter must mint and durably persist a random opaque session token (43-256 base64url characters) with a maximum 15-minute lease. This handler emits a \`__Host-kashier_access_x\` cookie with \`Secure; HttpOnly; SameSite=Strict; Path=/\`. Every protected request and *every* financial RPC must re-check current role/membership/session and revoke immediately once online; cookie existence alone NEVER authorizes a sale. Offline revocations require separate bounded lease design.
6. HTTP errors remain generic, do not disclose which email exists, never put access/refresh tokens into JSON, localStorage or logs. \`/access-x/manager/\` and \`/access-x/cashier/\` workspace routes are not deployed.

## What is still missing

- **Authoritative primary market registry**: current production \`public.store_cashiers\` contains \`owner_id\` + \`member_id\` but does not supply the separate immutable primary market register/market ID required by this contract. It must be established without breaking historical ownership/tenant data. Thus \`ownedScopes\` and \`memberships\` are required *unimplemented* DB adapters, never inferred from arbitrary authenticated users.
- **Actual adapter implementations**: secure Supabase Auth client, durable rate limiter, verified fresh membership query, credential rotation and \`aal2\` policy, secret/private opaque session store, session revocation endpoint, CSRF and per-route enforcement, first-login password-update API. Avoid a privileged service-role key in public/client code; secret management and an isolated test environment must be reviewed.
- **Recovery gate**: no restorable real-market backup and isolated restore has been verified. No live login, grant/RLS/privilege cutover or production route should be enabled before Gate C passes.
- **Integration**: no deployed endpoint at \`/api/access-x/login\`. No \`api/...\` file is authored by this module. Existing maintenance routing deliberately continues to return maintenance HTML for the login form.

## Tests

\`tests/access-x-server-login.test.cjs\` covers default gate closed, no self-signup, exact scopes, cashier activation, role spoofing, ambiguous/cross-market memberships, password rotation, step-up, rate limiting, Origin, safe cookie shape, and server errors. Node suite must be green before accepting this stage.

Supabase docs: https://supabase.com/docs/guides/auth/passwords , https://supabase.com/docs/guides/auth/server-side/advanced-guide

## Supabase Auth HTTP transport — STAGED 2026-10-20

Added \`access-x/server/supabase-auth-transport.cjs\` and \`tests/access-x-supabase-auth.test.cjs\`.

This adapter directly implements the *authentication-only* boundaries of the existing \`login-core.cjs\`:

- \`authenticate({email,password})\`: calls \`POST /auth/v1/token?grant_type=password\` using an explicitly provided **publishable** (or legacy **anon**) key; extracts only \`access_token\`, and discards the upstream refresh token.
- \`verifyUser(accessToken)\`: calls \`GET /auth/v1/user\` with the bearer token to verify the identity against Supabase Auth; returns only \`id\` and anonymous-user flag. Never trusts either user metadata or JWT content as *authoritative market role*.
- Only a fixed, exact HTTPS Supabase project origin is accepted. A service-role/secret key is rejected at construction. Requests use \`redirect:error\`, \`cache:no-store\`, a bounded timeout, JSON Content-Type/size validation, and generic failures without secret-bearing error logs.
- The adapter has **no production project URL, credentials, environment variables or live deployment configuration**. The test suite injects a fake network client. It does not read financial records or create any Auth user.
- **Important:** correct Auth credentials do NOT establish owner authority. \`ownedScopes\`, \`memberships\`, \`credentialPolicy\`, \`issueSession\` and shared rate limiting **remain unimplemented durable server adapters**. The signed-in user is denied until those are established and tested.
- Real deployment still blocked by the production backup/restore gate; Vercel continues to return maintenance HTML. The \`/api/access-x/login\` endpoint is **not deployed**.

Supabase documentation: https://supabase.com/docs/guides/auth/passwords and https://supabase.com/docs/guides/auth/server-side/advanced-guide

## Opaque session verification — STAGED 2026-10-20

Added \`access-x/server/session-core.cjs\` and \`tests/access-x-session-core.test.cjs\`. This provides a **server-only** cryptographically generated 256-bit base64url session token, with only its SHA-256 fingerprint passed to a required durable storage adapter. No plaintext session secret, refresh token or password is stored in this module.

- A successful verified user/role can receive an opaque, owner+market+role-bound, **10-minute** (configurable 60-900 seconds) session. The cookie shape must match \`__Host-kashier_access_x\`, as the existing default-disabled HTTP handler already sets.
- \`verifySession(cookieHeader)\` rejects duplicate/malformed cookies, invalid scopes, expired/revoked sessions and expired records with impossible lifetimes. It calls \`requireCurrentAccess()\` **fresh on every request**; if a cashier is disabled or membership revoked, access is denied and the stored session is revoked.
- \`revokeSession(cookieHeader)\` is available for an explicit future signout endpoint. This module does NOT itself implement a public HTTP handler, browser routes or an in-memory production fallback.
- The **production backing store, durable atomic insert/lookup/revoke implementation, live owner/cashier authorization registry, session refresh strategy and protected route guards remain unimplemented**. The unit tests inject an isolated mock store only.
- Supabase JWT sessions are distinct from this app's short-lived opaque sessions. A valid Supabase Auth token *alone* does not grant market access. Production rollout must decide how to honor Supabase session revocation, password changes and any active \`auth.sessions\` invalidation, in addition to Kashêr's own DB membership checks.

Reference: https://supabase.com/docs/guides/auth/sessions and https://supabase.com/docs/guides/auth/signout. Production maintenance and unresolved real backup gate remain unchanged.
