# Kashier

سیستەمی کاشێری نوێ بە پێی وێنەی نموونەی پەسەندکراو لەم گفتوگۆیەدا.

## سنووری کار

- بنەمای دیزاین: شاشەی خانەیی بە دوگمە ڕەنگاوڕەنگەکان، هێما و ناونیشانی کوردی وەک وێنەی نموونە.
- پلان، کۆد و پێداویستییەکانی پڕۆژە پێشووەکان بەشێک نین لەم پڕۆژەیە.
- ئەم قۆناغە: کاتالۆگی کاڵا، فرۆشتنی کاش و پسوولە؛ کۆگا و بەشەکانی تر هێشتا نەکراون.

## Project

Supabase project: Kashier, reference `dhfyqxdfwhxlipbsasqf`, organization `yzqydecqltgvixelgrlk`, region eu-central-1.

Dashboard: https://supabase.com/dashboard/project/dhfyqxdfwhxlipbsasqf

## Run

Serve this repository over HTTP, for example `python3 -m http.server 8000`, then open http://localhost:8000. No package installation or external frontend assets are required.

## Implemented

- Kurdish home screen with 33 reference-style tiles, module search and display density.
- Email/password sign-in and account creation. Email confirmation may be required by Supabase.
- Private per-account catalog: name, optional unique barcode, integer IQD selling price; creation, editing, search and pagination.
- Cashier lookup by exact barcode or name. Catalog prices are read-only in the draft. Manual rows remain draft-only and cannot be posted.
- Cash sale posting through a single database transaction. The server reads current catalog prices, validates expected prices, quantities, discounts and full cash tender, then freezes the receipt snapshot.
- Cash amounts use integer IQD and quantities use thousandths. Each line rounds once to whole IQD, matching the frontend.
- An immutable request ID and canonical payload prevent duplicate posting. An advisory transaction lock serializes repeated use of the same ID. A retry with a different payload is rejected.
- Pending requests are saved before sending. An ambiguous network result locks draft editing until the same request is retried. A page reload in the same tab restores that request. Posting is blocked if this journal cannot be saved.
- Final receipts are loaded from saved database records, with receipt number, timestamp, lines, discounts, paid amount and change. A receipt list supports reprinting.
- Receipt snapshots survive later product name/price changes. Browser roles cannot insert, update or delete sale records directly.
- Only the public publishable key is in `config.js`. No service-role key, secret key or password is stored in the repository.

## Data access

Products and receipts are private to the authenticated account via RLS. There is no cross-account sharing or staff-role model yet.

Posting uses an explicitly authenticated function in the unexposed `private` schema with an empty search path and fully qualified tables. The public RPC wrapper is security-invoker. Browser roles receive only SELECT on sales; the controlled internal posting function has insert authority.

Sessions and drafts use sessionStorage for the current tab. Ordinary drafts clear on logout. A pending posting journal is retained under its account-scoped key until resolved. Closing the tab clears sessionStorage, so recovery across tab closure or another device is not implemented.

## Not implemented / verification limits

Inventory quantities and stock movement, returns/reversals, cashbox accounting, shared staff roles, and remaining home modules. A posted sale does not decrement stock in this phase.

Browser visual QA, the full email signup/login journey, physical barcode scanner input and physical printer output remain unverified. Database security and calculation checks are not a claim of full field readiness.

## Checks

Run `node --test tests/*.test.cjs` (16 tests).

Checks cover arithmetic, auth refresh, catalog request behavior, ambiguous posting retries, reload recovery, duplicate clicks, journal failure and rejection of manual draft lines. All JavaScript files parse and HTML references resolve.

Remote rollback-only SQL tests cover own catalog create/read/update, cross-account isolation, duplicate barcode validation, sale arithmetic, idempotent replay, immutable snapshots, changed-price rejection, shortfall/overdiscount rejection, atomic rollback, direct write denial, and anonymous denial. The database held 0 users, 0 products and 0 sales after verification.

Live anonymous REST checks returned 401 for reading receipts and invoking posting. Security advisors returned no findings.

The SQL files in `tests/` require administrative connections and roll back all fixtures. They are not application endpoints. SQL identity sequences can retain harmless gaps after rollback.

## Migrations

- `20261017065506_create_products_with_owner_rls.sql`
- `20261017072010_post_cash_sales_atomically.sql`
