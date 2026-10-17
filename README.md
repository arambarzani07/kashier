# Kashier

سیستەمی کاشێری نوێ بە پێی وێنەی نموونەی پەسەندکراو لەم گفتوگۆیەدا.

## سنووری کار

- بنەمای دیزاین: شاشەی خانەیی بە دوگمە ڕەنگاوڕەنگەکان، هێما و ناونیشانی کوردی وەک وێنەی نموونە.
- پلان، کۆد و پێداویستییەکانی پڕۆژە پێشووەکان بەشێک نین لەم پڕۆژەیە.
- ئەم قۆناغە: کاتالۆگی کاڵا، کڕین، کۆگا، فرۆشتنی کاش و قەرز، پسوولە، قاسە، کڕیار و قەرزی دەستی.

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
- Sale posting: current catalog price validation, quantities, discounts, full cash tender and positive change, or full/partial credit against a selected registered customer. Manual rows remain draft-only.
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

- Customers: create/edit name and optional phone, search and private profiles with current debt and paginated history.
- Manual debt charges increase a customer's balance without posting a sale, moving stock or increasing cash.
- Cash repayments decrease customer debt and increase the same owner's cash balance in one transaction. Overpayment and balance limits are rejected.
- Debt entries are immutable, idempotent and retain the customer's name at posting. Each repayment links to its cash movement.
- Debt form retries preserve customer, amount and request ID across ambiguous responses and same-tab reload. Saved entries support individual printing.
- Cash statements distinguish debt repayments from sales and owner deposits.
- Credit sales atomically subtract stock, post an immutable receipt, increase customer debt by total minus received, and add only the received portion to cash. Full credit creates no cash movement. Zero-debt credit is rejected; fully paid sales use cash mode.
- Credit requests preserve payment mode and selected customer across retries and same-tab reload. Receipt/debt/cash source links support tracing. Receipt debt is the original amount, not a current per-invoice outstanding balance; repayments are account-level and are not allocated to invoices.
- Inventory → debt → cash locks give credit sales a consistent ordering with other posting functions. Customer statements support full-period or Baghdad date ranges, opening/closing debt, charge/repayment totals, ordered movements, credit receipt links and A4 landscape printing. CSV/PDF file export is not implemented.

Statements are read-only, use one database snapshot and derive balances from immutable ledger deltas. They return exact integer strings. A 5000-entry period limit fails explicitly; select a shorter range instead of printing a truncated statement. Changing dates invalidates the displayed snapshot and disables printing until refreshed. Empty periods retain opening debt; no activity is invented. Print uses the complete displayed snapshot without refetching.

## Data and access

IQD amounts are whole integers. Quantities are represented in thousandths. Line totals round once to whole IQD on both client and server.

All catalogs, customers, debt entries, receipts, balances and movements are protected by per-account RLS. The stock catalog view is security-invoker. There is no cross-account sharing or staff-role model yet.

Only the public publishable key is in `config.js`. No service-role key, secret key or password is stored in the repository.

Controlled posting functions are in the unexposed `private` schema, check the authenticated user and use an empty search path with fully qualified tables. Public RPC wrappers are security-invoker. Browser roles cannot write receipts, stock balances, cash balances or movements directly.

Sessions and drafts use sessionStorage for the current tab. Logout clears ordinary drafts. Pending journals remain under account-scoped keys until resolved. Closing the tab clears sessionStorage; recovery across tab closure or another device is not implemented.

## Not implemented / field-verification limits

Returns/reversals, initial-stock adjustments, stocktake corrections, multiple warehouses, supplier debt/payments, cost-of-goods/profit reporting, shared staff roles and the remaining home modules.

Browser visual QA, the full email signup/login journey, simultaneous real-client field testing, physical scanner input and printer output remain unverified. Database and code tests do not establish complete field readiness.

## Verification

Run `node --test tests/*.test.cjs` (57 tests). All passed.

Tests cover money/quantity arithmetic, authentication refresh, catalog requests, sale and purchase journals, reload recovery, repeat clicks, journal failure, invalid draft rejection, customer lookup/selection, credit-mode validation and recovery, receipt rendering from saved snapshots, cash journal recovery, exact lifetime cash formatting, and complete statement rendering, date validation, stale-response protection, snapshot printing, malformed-response rejection and large exact totals. JavaScript syntax, HTML navigation/assets, labels and static selectors were checked.

Remote rollback-only SQL checks cover:
- Catalog permissions and barcode validation.
- Cash sale arithmetic, snapshots, replay protection, stale-price/short-payment/discount rejection.
- Purchase stock additions, sale stock decrements, exactly-once stock changes on replay.
- Grouped repeated rows, insufficient stock rejection, atomic failure across multiple items.
- Movement sums matching balances and sequence ordering.
- Cash deposits, expenses, withdrawals, net sale cash, exactly-once retries, negative-balance rejection, limits, and agreement between cash movements and cached balances.
- Customer charges, atomic debt/cash repayments, overpayment rejection, cached debt agreement, cross-account denial and frozen customer names.
- Full and partial credit, discounts, no fictitious cash on full credit, source links, cross-mode replay conflicts, immutable debt amounts after repayments, and atomic stock/cash/debt limit failures.
- Customer statement opening/closing arithmetic, inclusive Baghdad midnight boundaries, full/open date ranges, empty periods, credit source links, lifetime precision, the 5000-row guard, no data mutation and owner isolation.
- Cross-account isolation and denial of direct browser stock/cash mutations.

Security advisors returned no findings. Live anonymous REST checks returned 401 for stock reading, purchase posting, cash summary, cash posting, debt summary, debt posting and credit-sale posting and customer statement reading, as well as the earlier sales checks.

After verification: 0 users, 0 products, 0 sales, 0 purchases, 0 stock balances, 0 stock movements, 0 cash accounts, 0 cash movements, 0 customers, 0 customer balances and 0 debt entries. No test data is seeded. Test identity sequence gaps after rollback are harmless.

SQL files in `tests/` require administrative connections and roll back every fixture. They are not application endpoints.

## Migrations

- `20261017065506_create_products_with_owner_rls.sql`
- `20261017072010_post_cash_sales_atomically.sql`
- `20261017072701_purchases_and_atomic_stock_movements.sql`
- `20261017073202_stock_movement_order.sql`

- `20261017075033_cash_ledger_and_sale_cash_posting.sql`
- `20261017075226_cash_summary_exact_totals.sql`

The cash migration deliberately requires an empty sales table for its initial activation; an installation with pre-existing sales needs an explicit cash reconciliation rather than an assumed opening balance.

- `20261017075847_customers_debt_ledger_and_cash_repayments.sql`

- `20261017080907_credit_sales_atomic_inventory_debt_and_cash.sql`

- `20261017081327_customer_statements_with_baghdad_date_bounds.sql`
