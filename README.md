# Kashier

سیستەمی کاشێری نوێ بە پێی وێنەی نموونەی پەسەندکراو لەم گفتوگۆیەدا.

## سنووری کار

- بنەمای دیزاین: شاشەی خانەیی بە دوگمە ڕەنگاوڕەنگەکان، هێما و ناونیشانی کوردی وەک وێنەی نموونە.
- پلان، کۆد و پێداویستییەکانی پڕۆژە پێشووەکان بەشێک نین لەم پڕۆژەیە.
- ئەم قۆناغە: کاتالۆگی کاڵا، کڕین، کۆگا، فرۆشتنی کاش و قەرز، پسوولە، قاسە، کڕیار و قەرزی دەستی.

## Live app

https://kashier.arambarzani.chatgpt.site — owner-private Sites deployment; Supabase authentication still controls the application data.

## Project

Supabase project: Kashier, reference `dhfyqxdfwhxlipbsasqf`, organization `yzqydecqltgvixelgrlk`, region eu-central-1.

Dashboard: https://supabase.com/dashboard/project/dhfyqxdfwhxlipbsasqf

## Signup form

`auth.html?mode=signup` opens a distinct registration form with password confirmation and a visible minimum of eight characters. Switching modes sends no request. Kurdish inline validation explains missing/invalid email, short passwords and mismatched confirmation before any signup attempt. Repeated submissions are blocked while pending. Login preserves safe local return destinations, including filtered stock and statements. Supabase confirmation requirements and data isolation are unchanged; no user is provisioned by this UI repair. Server Auth logs confirmed a real signup, email confirmation and successful password login on 17 October 2026; the full visual browser journey remains unverified.

## Run and first use

Serve this repository over HTTP, for example `python3 -m http.server 8000`, then open http://localhost:8000. No package installation or external frontend assets are required.

Create an account and confirm its email if required by Supabase. Register products, post a purchase to receive stock, then sell catalog items. New products have zero available stock until received through a purchase.

## Implemented

- Kurdish home screen with 33 reference-style tiles, module search and display density.
- Email/password authentication and private per-account catalogs.
- Products: name, optional unique barcode, integer IQD selling price; creation, editing, search and pagination.
- Purchases: catalog item selection, quantities, unit costs, optional supplier/invoice/note, atomic posting and saved purchase receipts. New tracked purchases require a registered supplier and record paid cash plus remaining debt atomically. A clearly labeled stock-only mode preserves the previous untracked workflow.
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
- Supplier purchase payments and later supplier debt payments debit cash in the same transaction as their receipt/payable entries. They have distinct cash movement kinds and report totals.

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

## Sale returns integrated from GitHub

The current source includes immutable full sale reversals and partial returns for cash receipts without discounts, along with atomic stock restoration/refunds and report integration. Partial credit or discounted returns are rejected. Full reversal is blocked after partial returns. These are separate reverse entries; original receipts remain unchanged.

## Daily report

Open the home tile دەفتەری ڕۆژانە or the daily report link in the cashbox. Select a Baghdad calendar day. The report reads one database snapshot and provides receipt counts, gross/subtotal, discounts, cash/credit sale totals, net sale cash received, newly created sale debt, manual debt charges, repayments, deposits, withdrawals, expenses, purchases and cash/debt opening and closing balances.

All totals and counts are exact integer strings, rendered with BigInt. Change given on cash sales is excluded from the cash intake. A credit receipt total includes any paid portion; that portion also appears in cash received, so those cards must not be added together as extra sales. Repayments/deposits are separate from sales. Daily purchases separately show paid cash, newly created supplier debt and the number of stock-only receipts; total purchase value alone does not imply a cash outflow. Empty days retain prior balances. This is a read-only live report, not an end-of-day close, profit report or locked accounting period. A4 landscape print uses the displayed snapshot; changing the date invalidates printing until refreshed.

## Suppliers and purchase financing

The supplier tile opens private supplier accounts: create/edit name/phone, search, outstanding-payable filter, immutable history, manual opening debt, cash payments, individual entry printing and Baghdad-date statements. Payments reject amounts above the supplier balance and insufficient cash. Supplier statements show outgoing payments and link purchase receipts.

New purchase drafts default to registered-supplier accounting. Enter paid cash (zero for full credit); the remaining amount becomes supplier debt. Posting validates stock/costs, adds inventory, debits paid cash and charges supplier debt in one transaction, using request → inventory → supplier → cash locks. Replays return the original receipt; conflicting payloads fail. Pending journals preserve supplier, amount and accounting mode across retry/reload.

Existing receipts remain `untracked` with no assumed historic cash/debt. Existing drafts retain stock-only behavior. The stock-only option remains explicitly available and posts no supplier cash/debt. No old purchases or balances are automatically backfilled. Supplier payments are account-level, with no invoice allocation or prepayment balances. IQD only.

## Low stock

The home tile کاڵا کەمبووەکان opens `stock.html?mode=low`. Select all stock, zero stock, or stock at/below a user-entered threshold (default 5). The threshold is a query filter shared by all products, not a saved per-product reorder level. Up to three decimal places are supported. Filtering, ordering and exact counts happen on the server before 50-row pagination, including unreceived products with zero stock. Name/barcode search combines with the threshold. Invalid thresholds fail explicitly. Movement links preserve filter/search context. Stock movements identify full and partial sale returns and resolve their original receipt through owner-protected source relations.

## Home account status

The home page verifies the signed-in identity through the Auth user endpoint and displays the account email, login/signup or logout actions. Failed authentication clears the displayed identity; a transient connection failure retains the session and offers retry. Late responses cannot restore a logged-out UI, and returning through back/forward cache rechecks the account. A short set of links explains product registration → purchase/stock receipt → sale. Previously outdated design-only footer copy is removed.

## Data and access

IQD amounts are whole integers. Quantities are represented in thousandths. Line totals round once to whole IQD on both client and server.

All catalogs, customers, debt entries, receipts, balances and movements are protected by per-account RLS. The stock catalog view is security-invoker. There is no cross-account sharing or staff-role model yet.

Only the public publishable key is in `config.js`. No service-role key, secret key or password is stored in the repository.

Controlled posting functions are in the unexposed `private` schema, check the authenticated user and use an empty search path with fully qualified tables. Public RPC wrappers are security-invoker. Browser roles cannot write receipts, stock balances, cash balances or movements directly.

Sessions and drafts use sessionStorage for the current tab. Logout clears ordinary drafts. Pending journals remain under account-scoped keys until resolved. Closing the tab clears sessionStorage; recovery across tab closure or another device is not implemented.

## Not implemented / field-verification limits

Initial-stock adjustments, stocktake corrections, multiple warehouses, supplier prepayments, supplier purchase returns/reversals, allocation of payments to specific supplier invoices, cost-of-goods/profit reporting, shared staff roles and the remaining home modules.

Browser visual QA, the complete visual email signup/login journey, simultaneous real-client field testing, physical scanner input and printer output remain unverified. Database and code tests do not establish complete field readiness.

## Verification

Run `node --test tests/*.test.cjs` (135 tests). All passed.

Tests cover money/quantity arithmetic, authentication refresh, catalog requests, sale and purchase journals, reload recovery, repeat clicks, journal failure, invalid draft rejection, customer lookup/selection, credit-mode validation and recovery, receipt rendering from saved snapshots, cash journal recovery, exact lifetime cash formatting, and complete statement rendering, date validation, stale-response protection, snapshot printing, malformed-response rejection large exact totals, and daily report day selection, Baghdad rollover, cross-ledger arithmetic, stale-response protection snapshot printing, low-stock filters/pagination/context links and return movement rendering. JavaScript syntax, HTML navigation/assets, labels and static selectors were checked.

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
- Daily report cash/full-credit/partial-credit splits, net cash after change, Baghdad day boundaries, opening/closing cash and debt, empty days, exact large totals, read-only behavior and owner isolation.
- Low stock: zero-stock inclusion, inclusive/fractional thresholds, combined search, pagination, owner isolation and no mutations.
- Full and partial sale-return rollback checks cover stock/cash/debt source ledgers, retries, scope guards and reporting.
- Suppliers: full-credit/partial/cash purchases, manual charges and payments, snapshot/retry safety, overpayment/insufficient-cash/debt-cap failures, full stock/cash/debt rollback, legacy receipts, statements and owner isolation.
- Cross-account isolation and denial of direct browser stock/cash mutations.

Security advisors found no new table/function access findings. The existing Auth advisory for disabled leaked-password protection remains; configuration guidance: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection . Live anonymous REST checks returned 401 for stock reading, purchase posting, cash summary, cash posting, debt summary, debt posting and credit-sale posting and customer statement reading and daily reporting, as well as the earlier sales checks.

Rollback checks never seed permanent users or business data. A real user has since registered and confirmed their email; that account is preserved. Test identity sequence gaps after rollback are harmless.

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

- `20261017083934_daily_sales_cash_and_debt_snapshot_report.sql`

- `20261017085134_sale_reversals_atomic_inventory_debt_cash.sql`
- `20261017094535_partial_cash_sale_returns_atomic_inventory_refund.sql`
- `20261017094610_guard_full_reversal_after_partial_returns.sql`

- `20261017101112_suppliers_purchase_financing_and_cash_payments.sql`

## Barcode and shelf price labels

Home barcode and shelf tiles open `labels.html`. Select up to 50 products, 1–100 copies each (500 labels per batch), A4 or single-label roll paper, width 40–120 mm and height 30–80 mm. Shelf labels with barcodes need at least 35 mm height. Prices and barcodes are re-read from the authenticated owner catalog immediately before print; missing products or failed refreshes block printing. No stock or financial writes occur.

Existing ASCII barcodes are encoded as CODE128 with locally vendored JsBarcode 3.12.3 (MIT); original leading zeros are retained. No new product code is assigned. SVG bars include ten-module quiet zones and reject widths below 0.25 mm per module. Shelf price labels may omit barcodes. Use 100% print scale, matching printer paper dimensions, and disable browser headers/footers. Current queue is tab-local and is lost when the page closes. A4 layout is an uncalibrated grid, not a template for pre-cut sticker sheets.

Validation: 135 Node tests pass, including real encoder output, quantity and size bounds, fresh pricing, failed refresh prevention, shelf mode and stale catalog search handling. HTML, local assets and script syntax checks pass. Physical scanner/printer and browser visual validation have not been performed.

## Stocktake worksheet

The home stocktake tile opens `stocktake.html`: a complete, read-only catalog snapshot from one stable invoker RPC, with timestamp in Baghdad time, literal name/barcode search, recorded base-unit quantity and blank physical count/note columns. Print landscape A4 or download UTF-8 BOM CSV. Snapshots never adjust stock or cash. Changed search inputs invalidate old results. Printing and export use the displayed snapshot; reload to obtain a newer one.

Maximum 5000 rows per snapshot: larger results fail explicitly rather than truncate, and the user must narrow search. CSV quotes embedded quotes/newlines and neutralizes spreadsheet formulas. Import barcode and ID columns as text in spreadsheet tools to retain leading zeros; CSV itself retains the original values. The worksheet remains read-only; its product links open the separate stock adjustment workflow. No saved multi-product count sessions are included yet.

Validation: 143 Node tests pass, including exact quantities, CSV escaping, request authentication, stale results, failed and incomplete snapshots. Live rollback SQL verifies owner isolation, real stock quantities, literal wildcard search, no ledger writes, anonymous denial and the 5000-row guard. Browser and physical printing remain unverified. Security advisor still reports the previously documented leaked-password-protection warning, with no new function/table findings.

Migration: `20261017103630_readonly_stocktake_snapshot.sql`.

## Stock count adjustments

From a stocktake row or stock catalog product, open `stock-adjustment.html?product=<uuid>`. Read the current quantity, physically count the product in base units, enter up to three decimal places and a mandatory reason, then submit the displayed difference. Counts can raise or lower stock, including down to zero; equal counts are rejected as unnecessary. Each adjustment preserves the product name/barcode, before/after quantities, delta, reason and timestamp. History and immutable receipt printing are available at `stock-adjustment.html`; stock movements link to the saved count record. No cash, customer debt or supplier debt is posted.

The atomic posting function locks the owner inventory account and checks both expected quantity and last stock-movement version. Any intervening movement rejects the count, including a sequence that restores the same quantity. Refresh and recount explicitly. UUID replay returns the original saved result without a second movement; changed-payload and cross-owner replay are rejected. Unknown outcomes lock editing and retain the exact request in sessionStorage for retry after reload. Initial storage failure prevents sending; malformed retry evidence blocks a replacement request. Keep the tab/session until uncertain requests are resolved.

The adjustment ledger has owner-only SELECT RLS and no client insert/update/delete grants. The privileged posting implementation is in the private schema, checks auth.uid(), uses an empty search_path, and is exposed through a restricted invoker RPC. Migration: `20261017104146_audited_stock_count_adjustments.sql`. The stock catalog adds a string stock_version and an index supports latest-movement lookups.

Validation: 156 Node tests pass. Live rollback SQL covers initial stock, negative deltas, stale quantity/version, ABA changes, UUID replay/conflict, unchanged counts, range/reason checks, historical product snapshots, owner isolation, denied direct writes and no cash/debt changes. Inventory, full reversal, partial return and worksheet SQL regression suites also pass. No fixtures remain. Browser visual QA and physical receipt printing remain unverified.

## Purchased product range report

Home purchased-products tile opens `purchase-report.html`, with a default Baghdad month-to-date range. The purchase statement tile now opens supplier accounts; receipt listing also links to the purchase report. Select an inclusive date range of up to 366 days, then view/print the report or export its per-product rows as CSV. Values come from one stable invoker RPC under owner RLS; no stock, cash or debt is changed.

The report groups immutable purchase lines by product UUID, sums exact quantity and recorded line totals, counts distinct receipts, and uses the last purchase-line name/barcode within the selected range. Catalog renames do not rewrite historical snapshots. Summary totals reconcile tracked purchase cash-at-posting, debt-at-posting and untracked stock-only purchases. Later supplier repayments and current outstanding balances are not included. This is purchase activity, not current stock or profit. Range boundaries use Baghdad midnight, including both selected dates. More than 5000 product groups fails explicitly; narrow the dates rather than exporting a truncated report.

Aggregates are decimal strings, validated and formatted using BigInt to retain exact totals and thousandth-unit quantities beyond Number safety. CSV preserves exact raw numbers, escapes quotes/newlines and neutralizes formula-like text. Import barcode and UUID columns as text in spreadsheet software. Print/export always use the displayed snapshot; changed dates invalidate it and late replies are ignored.

Validation: 165 Node tests pass, including accounting identities, exact large aggregates, CSV escaping, inclusive date limits, stale replies, invalid responses, auth and result-cap feedback. Live rollback SQL verifies real tracked/untracked purchases, inclusive Baghdad boundaries, product snapshot names/codes, owner isolation, empty reports, the 5000-product cap and unchanged stock/cash ledgers. Fixtures were rolled back. No new security-advisor function/table findings; the previously documented password-protection warning remains. Browser visual QA and physical printing remain unverified.

Migration: `20261017104816_purchase_product_range_report.sql`.

## Product sales report including returns

The home sold-products tile and receipt listing open `sales-report.html`. Inclusive Baghdad date ranges (up to 366 days) show sold, returned and net base-unit quantities plus sold, returned and net amounts per product. Printable report and product-row CSV exports use the displayed immutable snapshot. Changed dates invalidate results; mismatched/inconsistent replies cannot print or export. Reports above 5000 product groups fail explicitly.

Receipt discounts are allocated proportionally to original line gross amounts using differences of cumulative integer quotients in original line order. Allocations sum exactly to each receipt discount; full reversal restores the same allocation. Partial cash returns use their saved actual line refunds, including cumulative fractional rounding. Sales are dated by sale time; returns are dated by return/reversal time, even when the sale lies outside the selected range. Return-only ranges therefore legitimately show negative net quantities and amounts. This is sales activity after discounts, not profit or cash received. The report does not post or alter any ledger.

All aggregate numbers are exact decimal strings; browser calculation/formatting uses BigInt. Per-product names/barcodes come from historical activity snapshots (timestamp ties have deterministic ordering), not mutable catalog names. CSV keeps signed numeric results as numeric literals and neutralizes formulas only in untrusted text. Barcode/ID columns should be imported as text in spreadsheet software.

Validation: 173 Node tests pass. Live rollback SQL checks mixed cash/credit sales, proportional discount allocation, full and partial returns, fractional refunds, Baghdad boundaries, return-only negatives, owner RLS, empty reports, the 5000-group cap and unchanged ledgers. A high-value regression proves exact integer division avoids NUMERIC division rounding moving one IQD between product allocations. No fixtures remain. Browser visual QA and physical printing remain unverified. No new security-advisor function/table findings; the previously documented password-protection warning remains.

Migrations:
- `20261017105405_sales_product_report_with_returns_and_discount_allocation.sql`
- `20261017105443_exact_integer_discount_allocation_in_sales_report.sql`

## Cash account range statement

The home cash-statement tile and cash account screen open `cash-statement.html`. Default range is Baghdad month-to-date. Select up to 366 inclusive days to view all cash movement types, opening balance before the range, inflows, outflows, closing balance, per-type totals and source links. Refunds link the original sale; tracked purchase cash links its receipt; supplier payments and customer repayments link their accounts. Statements above 5000 rows fail explicitly and require a narrower range.

The stable invoker RPC reads only the current owner's RLS-protected ledger. Opening is the exact sum of all earlier dated deltas. Row statement balances are opening plus a running sum in created_at/movement_no order; they intentionally describe chronological statement balances rather than reusing each movement's historical posting-order balance_after. This keeps dated statements internally consistent even when transaction start timestamps and posting order differ. Original ledger records are unchanged. An empty period retains its carried opening/closing balance.

UI validates row order, movement directions, running balances, type totals and overall reconciliation with BigInt. CSV includes an explicit summary row (also for empty periods) followed by movement rows; signed numeric fields remain numeric literals, notes are escaped and formula-neutralized. Print/export use the displayed validated snapshot; date changes and failed/inconsistent replies disable both.

Validation: 182 Node tests pass. Live rollback SQL covers all cash movement types, Baghdad date boundaries, out-of-order dated entries, linked refund/purchase sources, chronological running balances, empty carry-forward, owner isolation, exact aggregates beyond Number range, result cap and no ledger writes. Fixtures were rolled back. No new function/table security-advisor findings; the previously documented password-protection warning remains. Browser visual QA and physical printing remain unverified.

Migration: `20261017110018_cash_range_statement_with_chronological_balances.sql`.
