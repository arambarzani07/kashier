# Access X new login UI — staged, NOT production-enabled

2026-10-20: Replaced the legacy \`auth.html\` and \`auth.js\` *source* with a Sorani-RTL, responsive, accessible login screen; removed the legacy browser-side signup and direct navigation into owner POS after credentials are entered. New \`auth-access-x.css\` is a standalone light/liquid-glass style. This changes **source only**: Vercel still rewrites every request to the fail-closed maintenance screen. No production identity API has been deployed, no credentials can successfully sign in using the new flow, and no new owner/staff account can be provisioned via the page.

## Interaction and security contract

- One screen for manager and cashier; **user does not choose role**. Role is determined from a server-verified session.
- POST same origin \`/api/access-x/login\` with \`{email,password}\`, no cache, JSON-only, redirection disabled at fetch layer, cookies sent only same-origin.
- A deployed server handler **must** authenticate credentials through Supabase, verify the primary owner or current approved/enabled cashier membership, verify first-login password rotation, enforce rate limits and Origin checking, and issue an HTTP-only, Secure, SameSite cookie. It must not trust a browser-supplied owner ID, role or \`raw_user_meta_data\`. It must return \`{state:"authenticated",verified:true,role:"manager"|"cashier"}\` only on completed authorization. Incomplete staff setup returns \`{state:"password_change_required"}\`; do not mark account active until separately designed activation is complete.
- The browser only navigates to **fixed** \`/access-x/manager/\` or \`/access-x/cashier/\` routes after the strict response. Those destinations are **not published yet**. Query \`next\`, response \`next\`, self-chosen \`role\` or other paths never control redirect.
- Rejected credentials, HTML maintenance replies, no endpoint, timeout, wrong role, and malformed data **fail closed**. There is **no fallback to legacy \`KashierData.signIn\`**, and no temporary localStorage/sessionStorage token handling or public \`signUp\`.
- Form includes password reveal, Caps Lock hint, Kurdish status messages, busy locking, validation, accessible labels and narrow screen/reduced-motion support.
- The existing old dashboard/account pages still contain legacy signup links in their *source* and are still blocked by maintenance; cutover must remove/replace these links and preserve necessary account management flows. Do not lift the maintenance gate just because this UI is staged.

## Remaining production blockers

The \`/api/access-x/login\` server endpoint, step-up/MFA strategy, first-login activation, session cookie verification on every protected route, staff role migration, real backup/restore, data permission cutover and full security testing are NOT implemented. Server verification must also explicitly check *owner* authority in the DB rather than assuming any Supabase user is primary manager of a given market.

Test evidence: \`tests/auth-ui.test.cjs\`. The complete Node CI suite must pass after this UI change. No financial DB changes, roles or grants were applied.

## Staged Access X server-side login core — 2026-10-20 (NOT DEPLOYED)

- Added \`access-x/server/login-service.cjs\` to authenticate against an injected Supabase password adapter, explicitly verify the returned access token against \`auth/v1/user\`, and require a **database-verified** primary owner or exactly one enabled/accepted cashier membership whose password rotation is complete. No client-supplied role/market is trusted.
- Added \`access-x/server/supabase-password-auth.cjs\` to issue GoTrue password token requests via a configured HTTPS Supabase host and verify with GoTrue \`/user\`, without exposing Auth tokens in the browser or logging them. This adapter does **not** implement authoritative role lookup or session storage.
- Added \`access-x/server/login-handler.cjs\` with same-origin JSON POST, request-size cap, explicit trusted-client-IP requirement for the rate limiter, generic errors, and a Secure/HttpOnly/SameSite=Strict opaque cookie, written **only after** a durable session store confirms the new session. The core stores only a hash of that opaque cookie, not plaintext.
- All external dependencies are **required and fail closed**: persistent rate limit, real server-side principal/role lookup and durable session creation. **There is no published \`api/access-x/login.js\`**, no new Vercel API deployment, no session-store schema, no protected workspace, and no permission to use this for real cashier login. The new \`auth.js\` will receive maintenance HTML and deny login.
- The backend must implement per-request session validation against the current cashier membership / owner DB and instant revocation semantics, not rely solely on the signed-in cookie. Authentication via a valid Supabase user alone must never imply manager authority.
- Tested with isolated fake adapters and fake accounts only. No Supabase Auth account, privilege, membership or production data is modified. Real backup/restore Gate C still blocks any production cutover.
