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

## Stock waste

The home waste tile opens `waste.html` with private waste history and a link to choose a catalog product. Stock rows include a waste action. Enter a positive wasted quantity in base units (up to three decimals) and a mandatory reason. Only that quantity is subtracted; the entered number is not an absolute replacement stock count. The preview shows before/after and delta. Waste cannot exceed displayed available stock and is rejected if an intervening stock movement changes the quantity/version. Waste may reduce a product to zero.

Waste and physical count corrections share the immutable stock_adjustments ledger with a checked `kind` discriminator; waste must have a negative delta. Both use the same atomic private posting engine and inventory/request locks. UUID replay includes kind, so a waste request cannot be replayed as a count correction. Existing count requests without a kind in their saved payload remain replay-compatible. Existing rows default to count. History lists are explicitly filtered by kind, movement links identify waste, and receipts preserve original product name/barcode/reason and before/after quantities. Print is available. No purchase, sale, cash, customer debt or supplier debt is posted; monetary waste valuation is not calculated.

Waste uses a separate tab-local retry journal, restores the originally entered wasted quantity, locks edits on uncertain outcomes and retries the exact request. Storage failure blocks sending; malformed/wrong-kind journals block replacement requests. Receipts reached through the wrong page redirect to the matching ledger kind. Fix a later stock discrepancy by a new count correction; existing waste records are not edited or deleted.

Validation: 190 Node tests pass. Live rollback SQL covers fractional waste, waste-to-zero, excess/zero rejection, required reasons, stale stock, exactly-once replay, cross-kind UUID conflicts, pre-migration count replay, immutable snapshots, owner isolation and unchanged financial ledgers. Physical count, inventory and supplier SQL regressions also pass. No fixtures remain. No new function/table security-advisor findings; the previously documented password-protection warning remains. Browser visual QA and physical printing remain unverified.

Migration: `20261017110912_stock_waste_with_shared_atomic_adjustment_ledger.sql`.

## Owner business data JSON export

The home backup tile now opens `export.html`. Click Prepare to read one stable database snapshot, review the generated time, record counts per business table and SHA-256 digest, then explicitly Download JSON. No business records are changed. Empty accounts produce a valid empty business export; account changes or sign-out invalidate cached downloads.

The owner-only invoker RPC exports all 16 current business tables: products, stock balances/movements/adjustments, sales/full reversals/partial returns, purchases, cash account/movements, customers/balances/debt entries, suppliers/balances/entries. Rows are owner-filtered under RLS and ordered by primary key. Idempotency payloads and historical snapshots are included. Authentication users/sessions/passwords/API keys, database DDL and RLS policies are excluded. This is a business data export, not a full database backup or an automatic restore feature.

Limits are 50,000 total records and 20 MiB of estimated row JSON, checked before array aggregation; oversized snapshots fail rather than truncate. Browser rejects files above 25 MiB. Larger installations need a database-level backup workflow. Export format is `kashier-owner-export`, version 1, business schema revision `20261017110912`. Future data schema changes must review the format/validator.

The download uses original response UTF-8 bytes, never JSON.parse/stringify output, so integer literals beyond JavaScript Number precision remain exact in the file. JSON is parsed only for validating owner/count metadata and table ownership; parsed numeric values are not re-emitted. SHA-256 hashes those exact downloaded bytes. Save the displayed digest alongside the file; it detects later changes but is not a signature or authenticity proof. A restore implementation must parse large numeric literals losslessly. No data file is saved in browser storage; the prepared file stays in page memory until replaced or closed.

Validation: 200 Node tests pass, including real SHA-256, UTF-8 and large-integer byte preservation, owner/table/count validation, empty exports, account switching, no stale downloads, failed refresh, busy guard and authenticated raw API responses. Live rollback SQL verifies all 16 tables, references, idempotency payloads, private owner isolation, empty exports, row/size caps and unchanged ledgers. Fixtures were rolled back. No new security-advisor function/table findings; the previously documented password-protection warning remains. Browser visual/download QA has not been performed.

Migration: `20261017111740_owner_business_data_snapshot_export.sql`.

## Local export-file verification

The home utilities tile and export page open `verify-export.html`. Select a previously downloaded JSON file and provide the original saved SHA-256 digest. The export page's verification link can prefill its prepared digest through a URL fragment. File bytes stay in the browser; verification calls no data API and changes no database records.

Verification checks exact UTF-8 bytes against the supplied digest, the current session owner, export format/schema revision, all 16 business table keys, every row's owner and record counts. It rejects malformed UTF-8/JSON, wrong/missing digests, unsupported files, files above 25 MiB, mismatched owners and incomplete counts. Even a semantically harmless added newline fails the original checksum. Any file/hash change clears the previous result; late replies and session owner changes cannot restore a stale success. The UI reports metadata/count verification only, not financial-ledger reconciliation or restore readiness. SHA-256 is an integrity comparison against a trusted saved digest, not an authenticity signature.

No restore/import has been added. File selection and verification require the current account context. Successful verification shows the chosen filename, original export timestamp and counts; private file content is not rendered or sent to a server.

Validation: 208 Node tests pass, including real WebCrypto verification, changed-byte rejection, uppercase digest handling, malformed UTF-8, size/owner/count failures, no reads before input validation, late replies, busy guard, account changes and digest-prefill validation. Syntax/HTML/assets/DOM checks pass. Browser file-picker/visual QA has not been performed.

## Device appearance and receipt printing preferences

The home settings tile opens `settings.html`. Device-local choices cover home tile density, normal/large screen text, standard/high contrast, system/reduced motion and sale/purchase receipt paper (58 mm, 80 mm or A4). Preferences persist only in this browser's localStorage, are shared across its tabs and are not account/database settings. Reset restores defaults. Storage failures do not apply unsaved choices or claim they were saved. No business ledger or financial values are changed.

Every HTML screen loads the shared preference script before its feature scripts and the override stylesheet after its base styles. Stored values are restricted enums; malformed/unsupported storage values fall back to defaults. Screen appearance overrides do not affect printed label/report typography. Reduced motion disables CSS motion; system mode retains OS/browser behavior.

Receipt-only page rules are injected only when a receipt layout exists. Thermal layouts use a 4 mm page margin and content width 50 mm on 58 mm paper or 72 mm on 80 mm paper; A4 uses 10 mm margins and 190 mm content width. Select matching printer paper, 100% scale and disabled browser headers/footers in the print dialog. The setting does not configure a physical printer or force a thermal driver paper size. Long receipts may split between table rows; headers repeat. Label dimensions and report page rules remain independent. Default receipt paper is 80 mm.

Validation: 216 Node tests pass, including storage/reload/reset, invalid values, write failures, cross-tab subscription updates, receipt-only page rules, form mapping and shared asset inclusion on every HTML screen. Syntax, HTML/asset and DOM-selector checks pass. Browser visual/accessibility QA and physical print calibration remain unverified.

## Receipt search

Sale and purchase receipt lists now filter by exact receipt number, customer/supplier name and optional inclusive Baghdad date bounds. Purchase queries also match the saved supplier invoice number. Names/invoices use case-insensitive literal substring matching, so `%` and `_` are not wildcards. Numbers accept the matching K-/P- prefix, plain numbers and Arabic/Persian digits, preserving signed-bigint precision as strings. Invalid or wrong-kind prefixes are rejected. Either date bound can be omitted.

A stable invoker RPC applies owner RLS and all filters before exact counting and 50-row pagination. Order is created_at descending then UUID for deterministic ties. Searches include original immutable receipts even after returns, linking the existing receipt detail/print/return screen. Purchase results show the invoice number; sale results retain the credit indicator. Editing any filter clears links/pagination immediately; late replies cannot restore stale results. Clear resets filters and returns to the first page. No financial or stock records change.

Validation: 300 Node tests pass after integration with the current return/payment features, including large/normalized receipt numbers, date validation, invoice rendering, page context, stale results, clear/retry, guest guards and authenticated RPC payloads. Live rollback SQL verifies server-side count/pagination, exact number lookup, no page overlap, literal wildcard search, invoice matching, inclusive/open-ended Baghdad dates, owner isolation, invalid arguments and unchanged receipts. Fixtures were rolled back. No new function/table security-advisor findings; the previously documented password-protection warning remains. Browser visual QA remains unverified.

Migration: `20261017122202_owner_receipt_search_with_baghdad_date_filters.sql`.

### Owner export format v2

New JSON exports include all 19 business tables, including `purchase_reversals`, `purchase_returns` and `supplier_payment_allocations`. Format v2 uses schema revision `20261017135746`; the local verifier still accepts v1 (`20261017110912`, 16 tables) and displays a notice that v1 excludes those three tables. Both export previews show counts for the selected format. Downloads and SHA-256 use the exact original UTF-8 response bytes, preserving large integer values. This is a business data snapshot, not an automatic restore or authentication backup. The owner-only security-invoker RPC retains the 50,000-record and 20 MiB row-data caps.

Validation: `node --test tests/*.test.cjs`; `tests/export-rls.sql` exercises all 19 nonempty tables, owner isolation, anonymous denial and export limits in a rollback-only transaction.

### Catalog CSV import

Open **لیستی کاڵاکان → هاوردەی CSV**. The empty downloadable UTF-8 template has exactly `name,barcode,sale_price` columns in that order. Files allow up to 500 new products / 1 MiB. Prices are whole IQD (1–1,000,000,000); barcodes stay strings with leading zeros and may be empty. Quoted commas and escaped quotes are supported. Invalid UTF-8, malformed CSV, extra columns, empty/oversized names, duplicate nonempty barcodes and invalid prices block the entire preview. No fabricated catalog entries are supplied.

Selecting a file only builds a local preview. Explicit submission calls `import_products(jsonb)` as the authenticated owner. The security-invoker function validates every row and atomically inserts new products, without changing any existing product, stock or money ledger. Existing barcodes conflict rather than silently updating products. A retry reuses every product UUID and recognizes exact already-present rows; changed rows fail explicitly. A late collision rolls back earlier inserts in the same request. Concurrent imports are serialized per owner; normal unique constraints remain enforced.

Before sending, the page must persist a per-owner sessionStorage retry journal. An uncertain response locks file selection and preserves the same IDs through reload. Users can retry or inspect the catalog before explicitly discarding the pending preview. A separate fresh import of a no-barcode item is a new product; matching names alone do not deduplicate it. CSV is a catalog import, not a JSON restore or opening-stock import. Use purchases or audited counts for stock. Larger catalogs require multiple files of at most 500 rows.

Verification: `tests/product-import.test.cjs`, shared API tests and rollback-only `tests/product-import-rls.sql` cover parsing/limits, explicit submit, retry/reload, storage errors, owner changes, transaction rollback, no ledger mutation, RLS and anonymous denial. Browser and physical device QA remain unperformed in this environment.

### Quick price checker

The dashboard tile **پشکنینی نرخ** and product catalog link open a large Sorani RTL price screen. It uses existing authenticated, owner-scoped catalog reads and does not write products, sales, cash or stock. A keyboard-style barcode scanner can submit with Enter; manual barcode/name entry works too. Exact barcodes retain leading zeroes and display a price immediately. Partial barcode/name results require an explicit product selection and refetch that product's current price by UUID. The result list is limited to 50; refine the search for more precise results. No camera scanning or scale-label decoding is introduced.

New input clears the old price immediately. Replies from earlier scans, changed accounts and removed result choices cannot replace the current selection. Refresh hides the old price until fresh data arrives, and failures leave it hidden. Hiding/leaving the page or restoring it from browser history clears displayed prices to require a new check. Each displayed price shows the device's Baghdad lookup time, not a server-issued price guarantee. Escape clears and refocuses the query; focus/select returns to it after scanning.

Validation: `tests/price-check.test.cjs` plus shared API tests cover exact/partial barcode behavior, current-price refetch, stale replies, duplicate submits, offline/malformed data, account changes, tab/history invalidation and read-only authenticated lookup. Browser, physical scanner and mobile keyboard QA remain unperformed.

### Per-product card and stock history

Click a product name in the catalog or stock list, or follow **کارتی کاڵا و جووڵەکانی کۆگا** from the price checker. `product.html?id=<uuid>` shows the current catalog name/barcode/sale price, stock quantity, stock state and 50 movements per page. Count and waste links open the existing audited workflows for that product. Every movement links to its exact original purchase, sale, return document or adjustment record. Historical quantities remain visible separately from current available stock.

`get_product_profile(uuid,integer)` is a stable security-invoker, authenticated-owner read using existing RLS and one PostgreSQL statement snapshot for product, current stock/version, total movement count and page. There are no new business tables or writes. Prices, quantities, movement versions and counts are JSON decimal strings; the frontend validates and formats them with BigInt. The newest movement must reconcile with current quantity/version; adjacent movements must reconcile in descending movement-number order. Empty products display zero stock and no invented activity. Refreshes, failures, account changes and browser-history restoration invalidate old snapshots.

Validation: `tests/product-profile.test.cjs`, shared API tests and rollback-only `tests/product-profile-rls.sql` cover all eight movement sources, current/historical balance consistency, exact integers, 50-row pagination, empty stock, no mutation, owner isolation and anonymous denial. Browser UI verification remains unavailable.

### Park and resume sale baskets

The sale screen can park up to 10 named baskets (up to 200 rows each) in the current browser tab. Parking preserves the draft's items, quantities, catalog prices, cash/credit mode, customer selection, note, discount and tender. It clears the active cart only after the combined active-plus-held envelope is successfully written to the existing per-owner sale sessionStorage key. Resuming into a nonempty cart swaps the active draft into the held collection, preserving both customers' work. The same-tab reload restores them; they are not shared across devices and can be lost when the tab is closed or the account signs out. These are drafts, not recorded sales, money movements or stock reservations.

A storage error leaves the active and held baskets in place. Malformed held collections are kept without an automatic overwrite, with an explicit confirmed reset action. Deleting a held draft requires confirmation. An uncertain/in-flight sale cannot be parked or replaced; its existing posting UUID and payload remain locked for the normal idempotent retry flow. A successful sale retains the other held drafts, rather than deleting the entire draft envelope. Owner changes block park/resume/post actions for the old account. Late product/customer lookups are invalidated when switching carts. Prices and stock are revalidated by the existing sale posting RPC; parking does not reserve either.

Validation: `tests/sale-holds.test.cjs` covers cash/credit field retention, reload, cart swaps, capacity, storage failures, confirmed deletion/reset, uncertain-sale lock, preserved baskets after posting, stale lookup replies and owner changes. Existing sale posting regression tests remain unchanged and pass. Browser/mobile dialog and physical scanner QA remain unperformed.

### Refresh active cart prices and stock

**نوێکردنەوەی نرخ و کۆگا** on the sale screen checks all active catalog products, including a resumed parked basket, in authenticated read-only batches of at most 50 UUIDs. Up to 200 cart rows are supported. Current name, barcode, sale price and available quantity update only after every batch validates and the whole refreshed draft is saved. Missing/invalid products, a later batch error, changed owner/draft or failed sessionStorage write leave previous cart values intact. Repeated clicks cannot start parallel refreshes; posting, editing and basket switching are locked while a refresh is in progress. Pending uncertain sales keep their immutable retry payload and cannot refresh.

The screen lists changed prices (old/current) and stock shortages, using the aggregate requested quantity for repeated product IDs. Item quantities, discount, tender, cash/credit mode, customer and note remain unchanged; manual rows and other parked baskets are not repriced. Totals recalculate at the new prices. Short cash payment or a discount above the new subtotal continues to block posting through existing validation. Further cart row changes invalidate the old summary. The new catalog read does not reserve stock or post any financial record, and the existing transactional sale RPC still checks expected prices and available stock at submission.

Validation: `tests/cart-refresh.test.cjs` and shared API tests exercise 200 rows / four batches, all-or-nothing refresh, missing/malformed data, stock shortages, preserved draft fields/parked baskets, storage errors, owner/draft changes, pending-sale protection and read-only bounded requests. Browser and physical device QA remain unperformed.

### Quick tender and keyboard navigation

The sale payment panel provides **پارەی تەواو** for the exact discounted cash total, additive buttons for 250 / 500 / 1,000 / 5,000 / 10,000 / 25,000 / 50,000 IQD, and a tender-only reset. The controls update the draft's received field, totals/change and existing validation; they do not record a sale or a cash movement. The exact-total button is cash-only; credit sales retain the normal partial-received entry and additive buttons. Inputs and sums keep the existing whole-IQD bounds. Exact tender can replace an invalid received value if the cart and discount are valid.

Keyboard: F2 focuses/selects the barcode field, F4 the received field, F8 fills exact cash tender, and F10 opens the existing park-basket dialog. These keys do not post sales. Modifier combinations, repeated keydown, open dialogs, changed accounts, pending sale requests and catalog refreshes suppress the shortcuts. Tender buttons follow the same locks and remain inactive on an empty cart. The screen includes visible shortcut help and `aria-keyshortcuts` annotations.

Validation: `tests/tender-ui.test.cjs` covers exact/partial/overpaid amounts, cumulative denominations, tender-only reset, credit mode, bounds, keyboard navigation, modifiers/dialog guards, account changes, uncertain-sale protection and in-flight catalog refresh. Existing cart/holding/posting suites also pass. Browser, hardware keyboard and mobile QA remain unperformed.

### Exact barcode selection in sale and purchase screens

Sale and purchase searches now automatically add a product only when its complete barcode equals the entered query, preserving leading zeroes. A single fuzzy barcode/name match still requires explicit selection, with the product barcode shown in the result. For example, typing/scanning `1234` cannot silently add a product whose barcode is `001234`. Repeated completed exact scans increment the existing product quantity; purchase cost still starts empty/zero for the user to enter, rather than copying the selling price.

Shared `catalog-lookup.js` validates bounded catalog replies (UUIDs, names, barcodes, prices and stock quantities) and rejects duplicate/ambiguous rows before either cart changes. New searches invalidate older responses and detached choice buttons. Choosing a result clears its search generation, so an old button cannot add again. Account changes prevent old lookup results/choices from entering either cart, and purchase posting now keeps the same original-owner guard as sale posting. Existing pending-transaction and catalog-refresh locks remain in effect. No database schema, stock or money ledger is changed by searching/choosing products.

Validation: `tests/catalog-scanning.test.cjs` covers exact/partial/name queries, leading zeroes, repeated scans, choosing the actual matching result, malformed replies, stale responses/choices, changed owners and locked pending requests in both screens. All existing cart/purchase/posting tests pass. Browser and physical scanner QA remain unperformed; this does not introduce a hardware scan queue or camera/scale barcode decoder.

### Customer balances report

Open **کڕیارەکان → ڕاپۆرتی گشتی قەرز** (`customer-balances.html`). The explicit-load report shows current outstanding customer balances in descending balance order, with literal name/phone search and a debtors-only/all-customers toggle. Summary debt, debtor count and displayed-customer count cover only the selected list, not the unfiltered owner total. Customer names link to their individual profiles/statements. This is a current balance snapshot, not historical aging, an accounting close or a profit report.

The stable security-invoker RPC `get_customer_balances_report(text,boolean)` uses the existing owner-scoped customer view/RLS and one statement snapshot. Above 5,000 matching customers it fails explicitly; refine the query rather than accepting a truncated report. All money values and aggregate balances are exact decimal strings, validated and summed with BigInt before rendering, A4 landscape print or CSV export. Empty searches with no matches produce real zero totals. Filter edits, account changes, failures and browser-history restoration invalidate print/export snapshots. No customer, debt or cash records are posted by this feature, and no new business tables are added.

CSV is UTF-8 with BOM, quoted/escaped fields and formula-prefix protection for customer/phone text. Import phone and identifier columns as text in spreadsheets to preserve leading zeroes. CSV and printing use the same validated prepared snapshot.

Validation: `tests/customer-balances.test.cjs`, shared API tests and rollback-only `tests/customer-balances-rls.sql` cover exact totals beyond Number precision, summary reconciliation, sorting/filters, zero balances, 5,001-row rejection, owner isolation/anonymous denial, snapshot invalidation and exact CSV bytes. Browser and physical print QA remain unperformed.

### Supplier account balance report

Open **دابینکەرەکان → ڕاپۆرتی گشتی حساب** (`supplier-balances.html`). This report summarizes the current total account balance per supplier, including manual debt and tracked purchase debt after payments/returns. It complements the existing invoice-level payables center, whose rows cover individual open purchase receipts. Filter by literal name/phone or debtors-only/all suppliers, print the prepared A4 landscape snapshot or download CSV. Totals cover the selected supplier list, sorted by descending balance; they do not mix customer receivables with supplier liabilities.

`get_supplier_balances_report(text,boolean)` is a stable security-invoker RPC over the existing owner-scoped supplier catalog. It returns exact decimal-string balances and an explicit `party_kind: supplier` scope, fails above 5,000 matches and does not post/alter any business records. Supplier and customer reports share the validated snapshot/print/export controller and CSV escaping code. The supplier screen selects its own authenticated endpoint, supplier profile links, labels and CSV headers; customer reports reject supplier-scoped results and supplier reports require their scope marker. Existing customer reporting behavior remains supported.

Validation: rollback-only `tests/supplier-balances-rls.sql` covers manual charges/payments plus tracked invoice financing, allocated payments and purchase returns, exact large sums, filtering, zero balances, row cap, no mutation and owner/anonymous isolation. Shared frontend/API tests cover routing, scope mismatch, links, exact supplier CSV bytes and customer compatibility. Browser and physical print QA remain unperformed.


### Product expiry date reminders

Open the expiry dashboard tile (`expiry.html`). Products have an optional expiry date (1900–2100), editable in the product form. Existing products retain a null date; no dates are invented. The report separates expired, expiring today, upcoming within 1–365 days, and all dated products using the server’s Baghdad calendar day. It supports literal name/barcode search, optional zero-stock rows, direct product editing, and printing/CSV from the same validated snapshot. Above 5,000 matching products, narrow the filters.

This is one manually maintained reminder date per product. If stock has several batches, enter the nearest relevant date and update it as stock changes. Displayed quantity is total product stock, not expired-batch quantity. There is no batch allocation, FEFO, or sale blocking. The existing three-column catalog CSV import does not import dates. Owner JSON exports include the nullable date; historical documents, stock catalogue shape and financial/stock ledgers are unchanged.

The stable security-invoker `get_expiry_report` RPC reads products and stock under existing owner RLS. Validation includes 410 passing Node tests across the system and rollback-only SQL checks for date boundaries, date grants/checks, owner isolation, anonymous denial, zero stock, literal filters, export inclusion, no movements and the 5,001-row limit. Browser and physical printer QA remain unperformed.


### Stock page print and CSV

`stock.html` now prints or downloads the currently displayed page (up to 50 rows), for all/low/empty stock and product movement history. It labels page number, total matching count, displayed count, search, threshold/product context and read time in Baghdad. This is a page export, not a full-catalog or atomic multi-page snapshot. Reload to obtain current values; CSV and print use the same prepared display. Movement exports include the saved movement reason and relative source-document link; print shows that link too. Quantities preserve exact thousandths without floating-point division. CSV uses a UTF-8 BOM, escaped quoted fields and formula-prefix protection (signed movement quantities are exported as protected text).

Filter changes, page requests and restored history invalidate the export. Changed accounts cannot render a late response or export/print a prior owner's rows. Bad quantities reject the entire page. No database records, schema or financial calculations change. Tests cover page scope, exact quantities, CSV escaping, movement sources, stale filters, account changes and navigation. Browser and physical printer QA remain unperformed.


### Duplicate barcode preflight

The product form now offers an explicit exact-barcode check and automatically checks a nonblank barcode before create/update. A duplicate on a different product shows that product’s name and profile link while retaining the entered fields. Keeping the edited product’s own barcode and leaving an optional barcode blank remain allowed. An uncertain-create retry with its original UUID can reach the existing payload-verifying retry logic. Leading zeroes, case and punctuation remain literal; there is no fuzzy fallback or numeric conversion.

`findProductByBarcode` performs an authenticated, owner-RLS-protected products SELECT capped at two rows and validates the exact result. This check does not reserve a barcode: the existing `(owner_id,barcode)` unique constraint remains authoritative for concurrent writes. No database schema or business records are modified by checking. The existing server conflict message remains available if another write takes the barcode after checking.

Saving prevents double submission and locks inputs while the preflight/write is pending. Changed form values/accounts cannot post after a delayed check; stale checks after barcode edits/dialog closure cannot restore an old product match. A failed check retains the form for retry. Validation: 425 Node tests passed across the system; live metadata confirms products RLS, owner barcode uniqueness, authenticated SELECT and anonymous denial. The previously documented leaked-password protection warning remains; browser/scanner QA is unperformed.


### Optional cash count comparison

The daily report (`daily.html`) now accepts optional manually counted cash and compares it with the selected report snapshot’s closing cash balance. It shows equality, surplus or shortage (`counted − expected`) with exact integer arithmetic, records the entry time, includes the comparison in the report print and downloads a dedicated one-row comparison CSV. English, Arabic and Kurdish digits are accepted; counted cash must be a whole nonnegative IQD amount up to 100,000,000,000,000. Blank means no count entered; zero is a real count.

This is a temporary comparison, not a saved cash-count record or day close. It never posts an expense, withdrawal, deposit or adjustment. For a historical report, enter the count recorded for that historical day. Compare current cash against a freshly loaded report; activity after its generated time can change the expected balance. Refresh/day edits, navigation/history restoration and account changes discard the entered count. There is no local storage persistence. Invalid count input removes the old comparison and disables report printing/CSV until corrected or cleared. The ordinary daily report remains printable when no count is entered.

Validation: 435 Node tests passed across the system. New coverage checks exact signed differences, zero/blank, numeral normalization, input limits, snapshot CSV consistency, refresh/history invalidation, stale replies/account guards and browser print event handling. Database behavior and the report RPC are unchanged. Browser and physical printer QA remain unperformed.
