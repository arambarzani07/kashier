# Shared design audit — 2026-10-20

Latest runtime: `d9d5fcd34097134531d8330e7a581b1d13e05a1b`, production deployment `dpl_8wnjj64UmSPA9sVJYt9GvSHYVpD3`, READY on Node 24; build 16.6 seconds.

## Scope and corrections

Reviewed the shared styles and HTML structure of all 60 operational screens. Corrected white header links on white backgrounds (stocktake/report, label, account and price-check families), the invisible catalogue logout button, non-wrapping header navigation, small shared controls and supporting text, inconsistent panel/table treatment and modal scrolling. Keyboard focus indicators and narrow-screen form wrapping now follow shared rules.

Browser checks found two additional causes of page overflow: wide return tables lacked an overflow container, and absolutely positioned screen-reader captions could escape their table container. Shared table wrappers now contain horizontal scrolling and position those captions. Sale grid children can shrink without forcing the page wider. Data columns remain available by scrolling inside the table.

The public review tool provides disabled, script-isolated operational previews and four selectable iframe widths. Login, employee management, sales, catalogue, purchasing, customer statement, stocktake, returns, device settings and dashboard layouts are represented. Operational previews load only preferences.js, without auth or database scripts. Dashboard search/category scripts remain available for visual navigation testing.

## Verification

- Full release check: 82 regression files passed; final production build runs that same required release command.
- Final targeted auth UI, preview isolation and preference checks: 17 tests passed.
- Static deployment parity: 83 HTML files, 263 public assets, 1522 local references.
- HTML structure scan: no duplicate IDs, missing explicit label targets or missing image alt attributes.
- Initial browser matrix at `b487980`: ten layouts at requested iframe widths 320, 390, 768 and 1280 pixels (40 cases). No document horizontal overflow and no undersized visible buttons detected. Header links use the expected dark foreground. Measured content widths exclude the browser scrollbar.
- Dashboard category filtering returned five administration modules; searching for employees returned one module; clearing restored all forty.
- Visual inspection included the narrow catalogue and login layouts and the final desktop dashboard.

These checks use public, empty visual previews. They do not replace signed-in screens with real records, long names, validation errors, actual phone hardware or print-driver acceptance. Existing authorization, database writes, calculations and print styles are unchanged. Real-shop acceptance gates in PRODUCTION_READINESS.md remain open.

Browser measurements are retained in `docs/design-audit-2026-10-20.json`.

## Account, cash and backup follow-up

Customer/supplier identity cards now use shrinkable columns and wrap long names and balances. Profile action links and cash actions use consistent touch targets and responsive wrapping. Backup file inputs, hash fields and acknowledgement layout are aligned; technical implementation terms in supplier, cash and returns guidance were replaced with plain Kurdish descriptions. Preview navigation shows only primary destinations plus the current page, with the full selection available in the review tool.

All 82 release test files passed again. Five additional templates (customer, supplier, cash, export and restore) passed four iframe widths, for 20 additional browser cases with no document overflow, undersized visible buttons or enabled preview form controls. Results: `docs/profile-layout-audit-2026-10-20.json`. These were empty-template visual checks; no backup was downloaded/restored, no file uploaded and no financial transaction posted. Long live account values and physical-device testing remain separate acceptance work.

## Import and reporting follow-up

CSV import guidance now presents three ordered stages: prepare the file, check the preview and submit. Column names, UTF-8/barcode requirements, all-or-nothing handling, the 500-item/1 MiB limits and stock-entry guidance are retained. Report filter labels, date/search fields and related-action links share sizing and spacing. Summary cards can shrink and wrap long values; unknown-cost coverage notices keep their warning treatment.

All 82 release test files passed again. Import, sales report, gross profit and inventory valuation previews passed 320/390/768/1280 iframe widths (16 cases): no page overflow, undersized visible buttons or enabled preview inputs. Results: `docs/report-layout-audit-2026-10-20.json`. The final import layout was visually inspected. Reports with populated data, actual file submission and printing were not exercised in this pass; financial and import logic is unchanged.

## Price-check and label setup follow-up

Price scanning now uses a 20px search field and unified actions. Price output can wrap unusually long values. Label setup uses shrinkable grid tracks, readable form labels and a single column on smaller screens; queue items and print actions wrap consistently. All added feature CSS is inside screen media queries. Existing feature rules are retained verbatim; barcode generation, physical label dimensions and print rules are unchanged.

All 82 release test files passed. Two additional templates passed four iframe widths (8 cases), with no page overflow, undersized visible buttons or enabled preview controls. The scan field measured 20px at each width. Results: `docs/label-layout-audit-2026-10-20.json`. Label setup was visually inspected. No actual scanner, price record or physical printer was exercised.

## Receipt and return-screen follow-up

Receipt screen actions, summary wrapping and return-line controls were refined. Return filter labels/actions are larger, and desktop purchase-return filters use four shrinkable columns instead of a fixed-width eight-column row. Original CSS and print rules remain intact; additions are screen-only. No financial JavaScript or permissions were changed.

The local execution environment and cloud browser were unavailable. The Opera connector also reported Browser not connected. No local or rendered-browser verification is claimed. Production build logs confirmed all 82 regression files and static parity checks passed (83 pages, 263 assets, 1522 references); stable-alias receipt/purchase-return CSS fetched successfully with the new rules. Visual review, real populated receipts and physical printing remain unverified for this pass.
