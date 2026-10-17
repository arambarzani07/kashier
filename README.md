# Kashier

سیستەمی کاشێری نوێ بە پێی وێنەی نموونەی پەسەندکراو لەم گفتوگۆیەدا.

## سنووری کار

- بنەمای دیزاین: شاشەی خانەیی بە دوگمە ڕەنگاوڕەنگەکان، هێما و ناونیشانی کوردی وەک وێنەی نموونە.
- پلان، کۆد و پێداویستییەکانی پڕۆژە پێشووەکان بەشێک نین لەم پڕۆژەیە.
- ئەم قۆناغە: کاتالۆگی کاڵا، کڕین، کۆگا، فرۆشتنی کاش، پسوولە و قاسە.

## Project

Supabase project: Kashier, reference `dhfyqxdfwhxlipbsasqf`, organization `yzqydecqltgvixelgrlk`, region eu-central-1.

Dashboard: https://supabase.com/dashboard/project/dhfyqxdfwhxlipbsasqf

## Run and first use

Serve this repository over HTTP, for example `python3 -m http.server 8000`, then open http://localhost:8000. No package installation or external frontend assets are required.

Create an account and confirm its email if required by Supabase. Register products, post a purchase to receive stock, then sell catalog items. New products have zero available stock until received through a purchase.

## Implemented

- Kurdish home screen with 33 reference-style tiles, module search and display density.
- Email/password authentication and private per-account catalogs.
- Products: name, optional unique barcode, integer IQD selling price; creation, editing, search and pagination.
- Purchases: catalog item selection, quantities, unit costs, optional supplier/invoice/note, atomic posting and saved purchase receipts. Supplier payment is not recorded in this phase.
- Inventory: real available balances and immutable signed stock movements linked to each purchase or sale receipt. Movement sequence numbers provide a stable order.
- Cashier barcode/name lookup shows a balance snapshot. The server always rechecks the actual balance at posting.
- Sale posting: current catalog price validation, quantities, discounts, full cash tender and positive change. Manual rows remain draft-only.
- Each purchase adds stock and each sale subtracts stock in the same database transaction as its receipt and movement records.
- Negative stock is rejected. Repeated product lines are grouped for the availability check.
- A per-account inventory transaction lock serializes competing stock mutations. Conditional stock updates and nonnegative constraints provide additional protection.
- Immutable request IDs prevent duplicate receipt/stock changes on retry. A conflicting payload with the same ID is rejected.
- Pending posting journals are saved before sending. An ambiguous network response locks draft editing until the same request is retried. Same-tab reload restores the request; posting is blocked if the journal cannot be saved.
- Sale and purchase receipts use saved snapshots, support listing and reprinting, and survive later product name/price changes.

- Cashbox: deposits, reasoned expenses and withdrawals, stable movement numbering, filtering, saved entry details and single-entry printing.
- Each posted cash sale credits its final total (received minus change) to the cash balance in the same transaction as receipt and stock changes.
- Cash outflows reject insufficient funds. Cash balances and movements are private and cannot be edited or deleted through browser roles.
- Cash posting uses the same account-scoped same-tab retry journal pattern as purchases and sales.
- Lifetime cash summaries are returned as exact integer strings and rendered using BigInt to avoid numeric precision loss.
- Purchases still do not debit cash automatically; supplier payment accounting is separate and not implemented.

## Data and access

IQD amounts are whole integers. Quantities are represented in thousandths. Line totals round once to whole IQD on both client and server.

All catalogs, receipts, balances and movements are protected by per-account RLS. The stock catalog view is security-invoker. There is no cross-account sharing or staff-role model yet.

Only the public publishable key is in `config.js`. No service-role key, secret key or password is stored in the repository.

Controlled posting functions are in the unexposed `private` schema, check the authenticated user and use an empty search path with fully qualified tables. Public RPC wrappers are security-invoker. Browser roles cannot write receipts, stock balances, cash balances or movements directly.

Sessions and drafts use sessionStorage for the current tab. Logout clears ordinary drafts. Pending journals remain under account-scoped keys until resolved. Closing the tab clears sessionStorage; recovery across tab closure or another device is not implemented.

## Not implemented / field-verification limits

Returns/reversals, initial-stock adjustments, stocktake corrections, multiple warehouses, supplier debt/payments, cost-of-goods/profit reporting, shared staff roles and the remaining home modules.

Browser visual QA, the full email signup/login journey, simultaneous real-client field testing, physical scanner input and printer output remain unverified. Database and code tests do not establish complete field readiness.

## Verification

Run `node --test tests/*.test.cjs` (31 tests). All passed.

Tests cover money/quantity arithmetic, authentication refresh, catalog requests, sale and purchase journals, reload recovery, repeat clicks, journal failure, invalid draft rejection receipt rendering from saved snapshots, cash journal recovery, and exact lifetime cash formatting. JavaScript syntax, HTML navigation/assets, labels and static selectors were checked.

Remote rollback-only SQL checks cover:
- Catalog permissions and barcode validation.
- Cash sale arithmetic, snapshots, replay protection, stale-price/short-payment/discount rejection.
- Purchase stock additions, sale stock decrements, exactly-once stock changes on replay.
- Grouped repeated rows, insufficient stock rejection, atomic failure across multiple items.
- Movement sums matching balances and sequence ordering.
- Cash deposits, expenses, withdrawals, net sale cash, exactly-once retries, negative-balance rejection, limits, and agreement between cash movements and cached balances.
- Cross-account isolation and denial of direct browser stock/cash mutations.

Security advisors returned no findings. Live anonymous REST checks returned 401 for stock reading, purchase posting, cash summary and cash posting, as well as the earlier sales checks.

After verification: 0 users, 0 products, 0 sales, 0 purchases, 0 stock balances, 0 stock movements, 0 cash accounts and 0 cash movements. No test data is seeded. Test identity sequence gaps after rollback are harmless.

SQL files in `tests/` require administrative connections and roll back every fixture. They are not application endpoints.

## Migrations

- `20261017065506_create_products_with_owner_rls.sql`
- `20261017072010_post_cash_sales_atomically.sql`
- `20261017072701_purchases_and_atomic_stock_movements.sql`
- `20261017073202_stock_movement_order.sql`

- `20261017075033_cash_ledger_and_sale_cash_posting.sql`
- `20261017075226_cash_summary_exact_totals.sql`

The cash migration deliberately requires an empty sales table for its initial activation; an installation with pre-existing sales needs an explicit cash reconciliation rather than an assumed opening balance.
