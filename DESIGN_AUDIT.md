# Shared design audit — 2026-10-20

Runtime: `b48798077ffde57b4d8559205aaa0a0c505074fd`, production deployment `dpl_Ezcazbo4pKfi3rFvxprK5y3iKs9a`, READY on Node 24; build 15.4 seconds.

## Scope and corrections

Reviewed the shared styles and HTML structure of all 60 operational screens. Corrected white header links on white backgrounds (stocktake/report, label, account and price-check families), the invisible catalogue logout button, non-wrapping header navigation, small shared controls and supporting text, inconsistent panel/table treatment and modal scrolling. Keyboard focus indicators and narrow-screen form wrapping now follow shared rules.

Browser checks found two additional causes of page overflow: wide return tables lacked an overflow container, and absolutely positioned screen-reader captions could escape their table container. Shared table wrappers now contain horizontal scrolling and position those captions. Sale grid children can shrink without forcing the page wider. Data columns remain available by scrolling inside the table.

The public review tool provides disabled, script-isolated operational previews and four selectable iframe widths. Login, employee management, sales, catalogue, purchasing, customer statement, stocktake, returns, device settings and dashboard layouts are represented. Operational previews load only preferences.js, without auth or database scripts. Dashboard search/category scripts remain available for visual navigation testing.

## Verification

- Full release check: 82 regression files passed; final production build runs that same required release command.
- Final targeted auth UI, preview isolation and preference checks: 17 tests passed.
- Static deployment parity: 72 HTML files, 252 public assets, 1362 local references.
- HTML structure scan: no duplicate IDs, missing explicit label targets or missing image alt attributes.
- Final browser matrix: ten layouts at requested iframe widths 320, 390, 768 and 1280 pixels (40 cases). No document horizontal overflow and no undersized visible buttons detected. Header links use the expected dark foreground. Measured content widths exclude the browser scrollbar.
- Dashboard category filtering returned five administration modules; searching for employees returned one module; clearing restored all forty.
- Visual inspection included the narrow catalogue and login layouts and the final desktop dashboard.

These checks use public, empty visual previews. They do not replace signed-in screens with real records, long names, validation errors, actual phone hardware or print-driver acceptance. Existing authorization, database writes, calculations and print styles are unchanged. Real-shop acceptance gates in PRODUCTION_READINESS.md remain open.

Browser measurements are retained in `docs/design-audit-2026-10-20.json`.
