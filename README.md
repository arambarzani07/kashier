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


### Per-product low-stock thresholds

Set an optional minimum stock quantity in the product form. It supports exact thousandths (including Kurdish/Arabic digits), from zero to 1,000,000,000 product units. Blank clears the minimum and disables that product’s individual alert; zero alerts only when stock is empty. Existing products remain unset. The dashboard low-stock tile now opens `stock.html?mode=reorder`, showing only products whose current quantity is less than or equal to their own saved minimum. A separate threshold column, direct minimum-edit link and current-page print/CSV preserve the per-product context. The previous shared-threshold search remains available as `mode=low`; all/empty/movement modes continue working.

The nullable `products.reorder_units` stores thousandths with a database check and authenticated column-level insert/update grants under existing owner RLS. The read-only `low_stock_catalog` view uses `security_invoker` and `security_barrier`, filters by owner and minimum, and treats missing stock as zero. Server filtering/counting occurs before 50-row pagination. The existing `stock_catalog` shape and sale/purchase ledgers remain unchanged. Threshold edits do not adjust stock, reserve stock, create purchase orders or post cash/debt. JSON owner export includes the column automatically; the three-column catalog CSV import remains unchanged. Uncertain-create retries verify the saved minimum as part of the original payload.

Validation: 444 Node tests passed, including fractional parsing, null/zero distinction, form preservation/locking, read selection/retry consistency, per-product paging/context/CSV and malformed threshold rejection. Rollback-only `tests/reorder-rls.sql` passed live for inclusive thresholds, missing stock, clearing/bounds, export inclusion, no stock mutation, view read-only grants, pagination and owner/no-UID/anonymous isolation. Security advisors show only the previously documented leaked-password protection warning. Browser and physical printer QA remain unperformed.


### Home account summary

The home dashboard now displays one owner-specific snapshot with current cash balance, customer receivables, supplier liabilities, total product count, products at/below their individual stock minimum, and dated-expired products with positive stock. Each card links to the corresponding existing screen. These are current account totals, not today's sales. Expired means earlier than the server's Baghdad calendar date, excluding today; it uses the manually entered product date, not batch-level expiry allocation. Low-stock counts omit products without a minimum. The summary shows its server-generated time and updates on the explicit refresh button, initial verified account and restored-page account revalidation; there is no polling.

The stable security-invoker `get_dashboard_summary()` RPC aggregates existing owner-RLS-protected tables/views into one read-only snapshot. Amounts and counts are decimal strings, including sums beyond JavaScript Number precision. It requires an authenticated owner and returns an owner/scope marker. It creates no business records and does not change stock or financial ledgers. It adds no data-export table.

The home account controller now offers a small replaying subscription containing verification state and owner ID only. Summary loading waits for server-confirmed identity, including when verification completed before the summary script loaded. Verification failure, logout, pagehide and changed account invalidate private values; late replies cannot restore them. Loading/failure clears prior cards and never substitutes fabricated zeroes. A valid empty account snapshot displays zeroes.

Validation: 455 Node tests passed across the system, covering exact amounts, Baghdad rollover, strict response scope/count validation, verified-account gating, loading/retry, logout, stale responses and history lifecycle. Rollback-only `tests/dashboard-rls.sql` passed live for empty/current totals, large aggregates, stock/expiry boundaries and owner/no-UID/anonymous denial. Security advisors show only the previously documented leaked-password protection warning. Browser visual QA remains unperformed.


### Expense range report

`expense-report.html`, linked from cash, cash statements and daily reports, provides a date range and literal, case-insensitive expense-note search. It shows the total, matching expense count, active expense days, daily totals and reverse-chronological details. Baghdad date bounds include both selected days, with up to 366 days and 5,000 matching expense records. Only cash movements with kind `expense` count: withdrawals, supplier payments/purchases, refunds and deposits are excluded. This is an expense ledger report, not a gross/net profit calculation or every business cost.

The stable security-invoker `get_expense_report(date,date,text)` RPC filters existing owner-scoped cash movements before the 5,001-row sentinel. Unrelated cash activity does not consume the cap. Exceeding the cap requires narrowing dates or the note query; the app never prints a truncated result. UUIDs, chronological order, Baghdad days, exact decimal-string amounts and total reconciliation are validated before any result is rendered. The daily grouping and CSV derive from this same validated snapshot. CSV contains explicitly typed summary, daily and detailed rows, a UTF-8 BOM, quoted/escaped fields, exact numeric strings and formula protection for text. It performs no business writes and introduces no export table.

Filter edits, failed refreshes, history navigation and changed accounts invalidate the prior report and its print/CSV actions. Empty matches show an explicit zero summary and can be exported. Validation: 465 Node tests passed across the system, including exact large totals/movement identifiers, daily grouping, wrong scope/date/type/total rejection, CSV byte equality, retries/stale results and account/navigation guards. Rollback-only `tests/expense-report-rls.sql` passed live for expense-only scope, Baghdad midnight boundaries, literal `%_` note search, exact large sums, cap/narrowing, exclusion of 5,001 unrelated movements, no ledger mutation and owner/no-UID/anonymous isolation. Security advisors retain only the previously documented leaked-password protection warning. Browser and physical printer QA remain unperformed.


### Customer and supplier statement CSV

Both `statement.html?id=...` and `supplier-statement.html?id=...` now export the same validated snapshot used for printing. CSV includes party identity/phone, selected date bounds, server generation time, opening balance, individual movements with source IDs/references, and a period summary/closing balance. Row types distinguish opening, movements and summary; do not sum these different row types together. Exact numeric strings preserve large movement numbers and signed debt deltas. Import identifier, phone and long numeric columns as text in spreadsheet applications to retain their precision/leading zeroes. Text fields use CSV quoting and formula-prefix protection.

Supplier purchase returns have distinct gross returned-purchase value, debt reversed, cash refunded and debt delta columns. A debt-neutral cash return keeps a zero debt delta and unchanged balance while showing its cash refund. Customer statements retain customer repayment/reversal semantics; supplier-only gross-purchase/cash-refund fields are blank. Empty periods export opening and summary records without invented ledger rows. Party kind selects its own labels and endpoint as before.

The statement controller now checks printable text/source metadata and captured account ownership, invalidates both print/CSV on filter edits or history navigation, rejects stale replies after account changes and clears private data before an unauthorized print/export. The existing 5,000-row full-statement cap and date semantics remain unchanged. No database, ledger or RPC changes are involved.

Validation: 474 Node tests passed across the system, covering exact CSV bytes/column alignment, quoted multiline/formula text, large and negative values, customer/supplier scope, purchase-return cash/debt splits, empty statements, invalid metadata, account changes and navigation. Browser and physical printer QA remain unperformed.


### Own-account settings and password change

The home account tile and account panel now open `account-settings.html`, showing the server-verified identity, a current/new/confirm password form and logout. This is self-service for the current account, not shared-store employee administration. Password submission requires the current password, a different new password of at least eight characters, matching confirmation and the same verified identity. The app reauthenticates the server-verified email through the password grant, checks the returned user ID, then uses that fresh user's token for `PUT /auth/v1/user` with the new/current passwords. It adopts the fresh session only after a matching success. It never selects another user ID or uses an admin/service-role key.

Plaintext passwords are not put into app storage or URLs; fields clear after a request, logout or navigation. Browser password-manager behavior is browser-controlled. An uncertain mutation response does not trigger automatic retries and instructs the user to check sign-in with the new password. Fresh-session identity mismatch or changed stored login prevents session adoption; a login that changes after the write starts is not restored by a late response. The form disables duplicate saves and clears/reloads its identity when restored from browser history.

Shared auth plumbing now compares its in-memory session with the current tab's stored identity/access token before use and before accepting refresh/account responses. A stale page cannot overwrite or clear a newer login with a late refresh, GET-user response, 401 or logout, including a newer session for the same user. Logout clears only its own nonposting draft keys and retains pending/other-owner drafts. The prior in-memory fallback remains available when storage is blocked.

Protocol references: [Supabase password auth](https://supabase.com/docs/guides/auth/passwords), [Auth server user endpoint](https://github.com/supabase/auth/blob/master/README.md). No Auth configuration, database schema, actual account password or business records were changed during development. Validation: 492 Node tests passed, including protocol ordering, same-user reauthentication, rejected current passwords, uncertain responses, plaintext-storage checks, cross-page session races, logout cleanup, blocked storage and account-form lifecycle. Security advisors retain only the previously documented leaked-password protection warning. Browser QA and a real-account password-change flow remain unperformed.


## Explicit customer repayment allocation — 2026-10-18

Customer profile → **دابەشکردنی پارەدان** opens `customer-allocations.html?id=<customer UUID>`. The owner explicitly classifies an existing repayment against an existing manual charge or credit-sale charge, with a positive whole-IQD amount and required note. Several classifications may split either source. There is no history backfill or FIFO assumption. This operation never posts cash, changes aggregate customer debt, or edits the original ledger. Reclassifying requires an immutable full allocation reversal with a reason, followed by a new allocation.

`allocate_customer_payment` and `reverse_customer_allocation` use private security-definer implementations with explicit owner checks, restricted invoker wrappers, per-request UUID deduplication and the existing debt-owner advisory lock. The amount cannot exceed either unassigned payment or unassigned charge capacity after linked sale reversals. An insertion guard prevents a credit-sale debt reversal from invalidating an active classification; reverse the classification first. Original sale-return cash/debt arithmetic remains in force. The UI saves pending requests before sending and retries identical UUID/payload after uncertain responses. It blocks mutations if pending storage is unreadable and checks account/navigation freshness.

`get_customer_allocations` is a stable invoker RPC under owner RLS with a 5,000 debt-entry / 5,000 allocation cap. A single snapshot includes source entries and immutable classification/reversal history with exact string amounts and order numbers. Client validation reconciles every allocation and `unassigned charge capacity - unassigned repayments = customer balance`. When any repayment is unassigned, per-invoice capacity is explicitly **not** represented as authoritative invoice debt. No installment schedule, collection queue, due-date reminder or automatic invoice repayment is supplied yet.

New owner export **v3**, revision `customer-allocations-v1`, includes all **21** business tables, adding `customer_payment_allocations` and `customer_allocation_reversals`. Original UTF-8 bytes and SHA-256 are preserved; v1/v2 remain verifiable with an older-format warning. Business records were not seeded. Migration: `20261017211636_explicit_customer_payment_allocations_and_export_v3.sql`.

Validation: rollback-only SQL checks cover explicit classification, replay/conflict safety, unchanged cash/debt balances, capacity rejection, reversal audit, atomic failure of an allocated-invoice return, successful return after unclassification, export coverage, owner isolation and anonymous/write-grant denial. Node tests cover snapshot invariants, exact large order numbers, safe rendering, amount validation, pending persistence/retry, corrupted storage, owner/navigation changes, APIs and all three export formats. Browser, printer and scanner QA remains outstanding. The security advisor still reports the previously documented leaked-password-protection warning; no new database security finding was returned.


### Local digits in customer repayment allocation

The allocation amount field accepts Kurdish/Persian, Arabic and ASCII digits, including mixed digit sets. It canonicalizes a positive whole-IQD value to an exact ASCII decimal string before saving the pending request or calling the API. Leading zeroes are removed; decimal/group separators, signs, exponents, zero and values above 100,000,000,000,000 IQD are rejected. Existing payment/charge capacity checks still apply. Server snapshots and restored pending payloads continue using strict canonical ASCII validation. The native HTML pattern accepts all three digit sets, and inline Kurdish help explains the integer-only format.

Validation: all 515 Node tests pass, including localized submission, exact upper bound, capacity rejection, invalid formats, canonical persistence/retry, native pattern compatibility and matching distributed assets. JavaScript syntax and whitespace checks pass. A real-browser interaction and live deployment have not been performed for this change.


## Customer installment schedules — 2026-10-18

Customer profile → **خشتەی قیست** creates a schedule against an existing manual/credit-sale debt charge. Enter 1–60 positive whole-IQD installments with strictly increasing calendar dates between 2000-01-01 and 2100-12-31 and a required note. The sum must equal the entire effective original charge, including previously allocated payments; scheduling only its unpaid remainder is rejected. A charge can have one active schedule. Cancel with a reason and create a replacement to change terms. All original schedules and cancellation records remain readable. This metadata never creates debt, receives cash, charges interest/fees, or changes inventory. No historical repayments are silently classified. The current bounded book supports at most 500 total schedules per owner, including cancellations.

The home installment book, report and alert tiles open `installments.html` (alerts use `?mode=alerts`). A customer-specific `?id=<uuid>` adds the editor and a link to existing payment classification. For planning, explicitly charge-bound repayments cover the earliest scheduled due dates first. Reversed classifications remove that coverage immediately. If any repayment for that customer is unassigned, unpaid installments show **needs payment classification** and are excluded from confirmed overdue/today totals. The remaining schedule total is unclassified schedule capacity, not the customer's aggregate debt. Totals cover all active schedules, while the table/CSV follow the selected active/alerts/history filter. Cancelled rows show original terms alongside the charge's current allocation coverage, not historical coverage at cancellation. Unassigned customer money repeats on each CSV installment row and must not be summed as separate payments.

The server supplies the Baghdad calendar date from the same snapshot as the report. Exact amounts/source numbers are decimal strings. CSV/print use the validated displayed snapshot; changing accounts or navigating away invalidates it. Request UUID/payload is persisted before creation/cancellation and retained after uncertain responses. Direct table mutations are denied to browser roles. Private posting functions explicitly check owner, serialize on the existing debt-owner lock, and expose restricted invoker wrappers. Returning a scheduled credit-sale invoice requires cancelling its active plan first; failed attempts roll back stock/cash/debt together.

Owner export **v4**, revision `customer-installments-v1`, includes all **23** business tables, adding `customer_installment_plans` and `customer_installment_cancellations`. v1/v2/v3 remain locally verifiable with an older-format notice. Migration: `20261017213357_customer_installment_schedules.sql`. All SQL fixtures use rollback-only transactions and do not seed permanent accounts or business data.

Validation: 534 Node tests passed, including exact FIFO coverage, Baghdad midnight, unassigned-payment uncertainty, cancellation history, format/date/sum limits, account/navigation races, storage failure, canonical retry, CSV and export v4 roundtrips. Live rollback-only SQL checks passed for isolated read/write permissions, exact schedule sums, replay/conflicts, cancellation, current allocations/reversals, atomic scheduled-invoice return rejection and export coverage. A real database response also passed the client validator. Security advisors report only the previously documented leaked-password-protection warning; performance notices are unused-index information. Browser and physical printing/scanning QA remain unperformed.


## Forward inventory costing and gross-profit report — 2026-10-18

The home **قازانجەکان** tile opens `gross-profit.html`. Choose up to 366 Baghdad calendar days, with a 5,000 sale/return movement-line cap. The report includes cash and credit sale revenue after invoice-discount allocation and signed full/partial returns on their own event dates. Every line shows its immutable cost snapshot or an explicit missing-cost reason. Known revenue minus known COGS gives a clearly labelled partial margin. A complete-period margin is shown only when every selected line has known cost; unknown costs are never zero-filled. Empty periods show no activity. Print/CSV use the same validated snapshot, clear on filter/history changes and block changed accounts. Numeric CSV fields keep exact signed values, while text is formula-protected.

**Cost policy:** forward-only perpetual weighted average, rounded to whole IQD per stock movement. Purchase receipt line totals add inventory value. For a known pool, sales, waste, negative counts and purchase returns/reversals remove `round(pool_value × outgoing_thousandths / pool_thousandths)`. Full depletion removes the entire remaining value. Supplier refund prices are not sale COGS; purchase-return valuation variances and waste are not included in this gross-profit figure. Full/partial sale returns restore the original sale movement's saved cost, using cumulative rounding across repeated partial returns so the full returned quantity restores exactly the original cost. They never use the current purchase price. The existing inventory-owner transaction lock serializes valuation with stock; failed postings roll back their cost records too, and receipt replays create no new movements.

**Unknown coverage:** existing positive stock gets no invented valuation baseline, and historical sales get no backfilled COGS. New purchases into an unknown pool do not make its existing cost known. Uncosted positive stock adjustments and returns from old/unknown-cost sales make the pool unknown. At zero quantity its value resets to zero; a subsequent known purchase or known-cost sale return starts a known pool. Zero-IQD cost created by rounding a tiny genuine purchase is a recorded cost, not an unknown cost. Metadata is recorded lazily on the first new stock movement; no business data is seeded or rewritten at migration. Stock/receipt history inconsistency rejects the report rather than silently omitting receipts.

The report is **gross sale margin before operating expenses**, not net business profit. It excludes operating expenses, stock losses and purchase-return valuation variances from its margin calculation. Those costs must be reconciled separately. Sale returns can produce negative revenue/COGS/margin in a period without the original sale. Count-based coverage stays incomplete even if unknown sale/return revenue nets to zero. Source UUIDs, movement/receipt numbers and amounts use exact decimal strings and BigInt validation.

Tables `inventory_cost_state` and immutable `inventory_cost_movements` are owner-scoped/read-only to browser roles. A restricted private trigger records all new stock movements without altering stock or financial ledger arithmetic. Owner export **v5**, revision `forward-inventory-cost-v1`, covers all **25** business tables; older formats remain verifiable with a format notice. Migration `20261017214043_forward_inventory_cost_and_gross_profit.sql`.

Validation: all 548 Node tests pass. Rollback-only live costing tests pass for mixed purchase prices, replay, original-cost full returns, discounted partial returns, fractional cumulative rounding, purchase-return/waste valuation, unknown opening stock/returns/positive counts, restart after depletion, legacy missing snapshots, export v5 and owner/anonymous isolation. The real database report also passed the client validator. Existing sale, inventory, credit, sale-return, purchase-return, waste, adjustment, installment and allocation SQL regression suites passed. The older purchase partial-return suite was corrected to test the already-supported credit debt/cash split, replacing its obsolete unsupported-credit expectation. Advisors returned no new security findings, with only the existing leaked-password warning and unused-index information. Browser and physical printer/scanner QA remain unperformed.


## Current inventory valuation and unknown-cost list — 2026-10-18

`inventory-valuation.html`, linked from stock and gross-profit reports, displays current available product quantities and recorded weighted-average inventory values. Unknown-cost products sort first and show no invented value. Optional empty-stock inclusion displays zero inventory value for empty products without inventing a unit cost. A genuine rounded zero cost on positive stock is distinguished from missing cost. The summary shows selected-product counts, known/unknown coverage and known value; a full selected-inventory value is unavailable if any selected positive-stock product is uncosted. It is cost value, not shelf retail value, expected sales or profit. Quantities of different products are not totalled.

The stable security-invoker `get_inventory_valuation(text,boolean)` returns one owner-RLS-protected snapshot. Name/barcode search is literal and case-insensitive; `%` and `_` have no wildcard meaning. Up to 5,000 matching products may be displayed; filtering/empty-stock selection occurs before the cap, and excessive results require narrowing the query. A cost-state/physical-quantity mismatch rejects the selected report. Missing cost state on existing positive stock remains unknown; reads do not seed or change valuation records. Print and exact CSV derive from the displayed snapshot, retain leading-zero barcodes and fractional quantities, protect text formulas, and invalidate on filters, accounts and history changes. CSV summary and detail rows must not be summed together. No schema tables, financial writes or export-version changes are introduced; owner export remains v5.

Migration `20261017215153_inventory_valuation_snapshot_report.sql`. Validation: 558 Node tests passed, covering coverage invariants, exact large values, malformed/stale snapshots, zero/unknown distinction, filters, API payloads, account/navigation races and identical CSV bytes. Rollback-only live SQL passed for known/unknown/empty stock, tiny rounded zero costs, literal filters, filter-before-cap with 5,001 unrelated empty products, mismatch refusal, no business writes and owner/no-UID/anonymous isolation. Security advisors retain only the existing leaked-password-protection warning. Browser and physical print QA remain unperformed.


## Audited unknown-inventory cost confirmation — 2026-10-18

The product profile and valuation rows in `inventory-valuation.html` link to `inventory-cost.html?id=PRODUCT_UUID`. The owner can enter the **total verified cost of all currently available stock**, not its unit price or retail value, with required evidence/reason and an explicit acknowledgement. Only a positive unknown pool is eligible. Whole IQD accepts Kurdish/Arabic digits, including a genuinely verified zero total, up to 100,000,000,000,000 IQD. No price-derived estimate is supplied.

Confirmation checks the expected physical quantity and last stock movement number under the existing owner inventory transaction lock, writes an immutable audit record and updates the present cost pool. Stock quantity, cash and debt do not change. Earlier sale cost snapshots remain unchanged; only later movements use the confirmed pool. A reasoned immutable cancellation restores unknown cost only before **any** subsequent stock movement, even if sale/return activity later restores the same quantity. Known pools cannot be overwritten. Each product allows at most 200 lifetime confirmations.

All three RPCs enforce owner identity; authenticated clients can only read the two audit tables directly. UUID/payload is persisted before posting and retained after uncertain responses for identical retries; corrupt/unavailable session storage blocks unsafe submissions. Account/navigation changes invalidate displayed private data and late replies. Owner export **v6**, revision `audited-inventory-cost-basis-v1`, includes all **27** business tables and cost confirmation/cancellation history. Older files remain verifiable with a format notice.

Migration: `20261017220549_audited_unknown_inventory_cost_basis.sql`. Rollback-only live checks cover stale quantity/version, exact totals, retry/conflicts, cancellation, movement locks, unchanged historical costs, future weighted-average COGS, true zero, owner/anonymous isolation and export v6. Node model/controller/export checks cover localized values, acknowledgement, audit invariants, storage/retry failures and account/navigation races. Browser and physical printing/scanning QA remain unperformed.

Validation for this increment: **569 Node tests passed** plus the rollback-only basis, gross-profit and inventory-valuation live SQL suites. Security advisors found no new schema issues.


## Waste and stock-count shortage cost report — 2026-10-18

`inventory-loss.html` is linked from gross-profit, valuation, waste and stock-count screens. It reports recorded waste and negative count adjustments separately over up to 366 Baghdad calendar days, capped at 5,000 negative adjustment records. Product names/barcodes, quantities and reasons come from the original adjustment snapshot. Each source links to the saved adjustment and product history. Positive counts, sale COGS and purchase returns are excluded; count shortages are not automatically classified as theft or a particular cause.

The report reads immutable historical moving-average cost snapshots, including genuine rounded zero costs. Existing movements without cost snapshots remain explicitly unknown. Per-kind and combined totals distinguish known-only costs from complete costs; unknown costs are never zero-filled. Quantities across unrelated products are not totalled. These losses are not subtracted by the separate gross-sale-margin report; this is not net-profit accounting.

`get_inventory_loss_report(date,date)` is a stable security-invoker RPC under existing owner RLS. Missing/inconsistent physical adjustment history rejects the report; missing legacy cost metadata remains visible with unknown coverage. Exact decimal source numbers/costs are validated with BigInt. Print/CSV use the same validated displayed snapshot, clear on filter/account/navigation changes and protect CSV text formulas. Reads create no stock, cash, debt or costing records; owner export remains v6 with 27 tables. Migration: `20261018043114_inventory_loss_cost_report.sql`.

Validation: 578 Node tests passed. Rollback-only live SQL checks passed for waste/count subtotals, zero/unknown/legacy coverage, saved names, retry deduplication, Baghdad midnight, missing/malformed history, date ranges, no writes and owner/no-UID/anonymous isolation. A real database response passed the client validator. No new security advisor findings. Browser and physical print QA remain unperformed.


## Purchase-return valuation differences — 2026-10-18

`purchase-variance.html`, linked from gross-profit, inventory-loss and purchase-return screens, compares each saved full/partial purchase-return line's document value against the historical moving-average inventory cost removed by that movement. Difference = document value minus removed stock cost; either sign is possible when multiple purchase prices share a pool. Partial returns use their original purchase line numbers and saved cumulative-rounding document totals. Names, barcodes and supplier names are document snapshots. Source links open the return document, original purchase and product history.

Tracked supplier purchases and untracked stock-only purchases have separate summaries. Document value is not cash received: tracked returns may reverse supplier debt and/or refund cash; untracked returns have no financial-ledger settlement. Untracked differences are document/stock comparisons, not recognized financial profit. The source return document provides the actual debt/cash split. No combined financial-result total is invented. Differences are not included in the existing gross-sales-margin report; net-profit accounting remains outstanding.

`get_purchase_return_variance(date,date)` is a stable security-invoker owner-RLS read, limited to 366 Baghdad days and 5,000 return lines. Missing historical cost snapshots remain visible as unknown and suppress complete group differences. Genuine zero remains known. Missing/inconsistent document or physical history rejects the report. Full/partial documents sharing a UUID are distinct source identities. Exact strings/BigInt validate rows, signed differences, mode subtotals, source identities and cost coverage. Same-snapshot CSV/print invalidate on filter, account or navigation changes; CSV text is formula-protected. Reads do not change cash, debt, quantities or historical costs. Export stays v6 with 27 tables.

Migrations: `20261018051132_purchase_return_valuation_variance_report.sql`, `20261018051150_distinguish_full_partial_variance_documents.sql`. Validation: 588 Node tests passed; rollback-only live tests passed for positive/negative differences, mixed purchase prices, credit/untracked separation, original partial-return line mapping, shared document UUIDs, replay, old names, known-zero/unknown/legacy coverage, Baghdad midnight, history refusal, unchanged business ledgers and owner/no-UID/anonymous isolation. A real database snapshot passed the client validator. No new schema security findings. Browser and physical print QA remain unperformed.
