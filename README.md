# Kashier

سیستەمی کاشێری نوێ بە پێی وێنەی نموونەی پەسەندکراو لەم گفتوگۆیەدا.

## سنووری کار

- بنەمای دیزاین: شاشەی خانەیی بە دوگمە ڕەنگاوڕەنگەکان، هێما و ناونیشانی کوردی وەک وێنەی نموونە.
- پلان، کۆد و پێداویستییەکانی پڕۆژە پێشووەکان بەشێک نین لەم پڕۆژەیە.
- تۆمارکردنی فرۆشتنی کۆتایی هێشتا چالاک نییە.

## Project

- Supabase: Kashier
- Project reference: `dhfyqxdfwhxlipbsasqf`
- Organization: `yzqydecqltgvixelgrlk`
- Region: eu-central-1
- Dashboard: https://supabase.com/dashboard/project/dhfyqxdfwhxlipbsasqf

## Run

Serve this repository over HTTP, for example `python3 -m http.server 8000`, then open http://localhost:8000. No package installation or external frontend assets are required.

## Implemented

- Reference-style Kurdish home screen with 33 tiles, module search and display density controls.
- Product creation and editing: name, optional barcode, integer IQD selling price.
- Product list with server-side search, pagination and exact matching barcode lookup.
- Email/password sign-in and account creation. Email confirmation may be required by Supabase before login.
- Products are private to the authenticated account using server-enforced RLS. Anonymous access is denied; users cannot assign or change ownership.
- Sale draft: add catalog products by barcode/name, or enter manual draft rows. Quantities, prices, discounts, received cash, positive change/shortfall and explicitly marked draft printing.
- Sessions and user-scoped drafts stay in sessionStorage for the current tab. Logout clears draft data.

Only the public publishable key is in `config.js`. No service-role key, secret key or password is stored here. The database starts with no catalog or user seed data.

## Not implemented

Final sale posting, stock movement, final receipts, role sharing, and the remaining home screen modules. No draft changes a customer's balance, cash or stock. Browser layout, physical scanner/printer use, and the full email signup/login journey still require field verification.

## Verification

Run `node --test tests/*.test.cjs` (10 tests). JavaScript parsing, HTML assets/labels/selectors and draft handler checks passed.

The remote migration was applied as `20261017065506_create_products_with_owner_rls.sql`. Rollback-only database checks covered own create/read/update, cross-account isolation, anonymous denial, duplicate barcode and price constraints. The anonymous live REST check returned 401. Security advisors returned no findings. Following verification, the database held 0 products and 0 authentication users.

`tests/products-rls.sql` requires an administrative database connection and rolls back all fixtures. It is not an application endpoint.
