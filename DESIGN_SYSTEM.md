# Kashêr interface

All 42 interactive source screens use `design-system.css`. The standalone
maintenance screen embeds the same tokens; `dist/maintenance.html` stays identical
to its source. Existing maintenance routing and authentication gates stay in place.

## Ownership

- Feature stylesheets own page structure, business states, and physical print sizes.
- `design-system.css` owns screen colors, typography, spacing, headers, cards,
  controls, dialogs, and tables. Its component rules are screen-only.
- `preferences.css` loads last so large text, high contrast, reduced motion, and
  receipt paper preferences take precedence.
- Functional IDs, event handlers, links, ledger calculations, and data APIs are
  preserved. Protected pages still require authentication.

## Adding a screen

Use Sorani `lang="ckb"`, `dir="rtl"`, a `kashier-ui` body, and the shared
`topbar` / `brand` / `brand-mark` header classes. Load feature CSS first, then
`design-system.css`, then `preferences.css`. Use `primary`, `secondary`, and
`danger` button roles. Extend shared tokens/components rather than adding new
page-specific colors or control geometry. Purpose-specific layouts and print
templates can remain different.

Run `node --test tests/*.test.cjs`, `node scripts/release-check.cjs`, and
`git diff --check`. The design-system tests cover every source HTML screen,
stylesheet order, RTL, maintenance token parity, and print isolation.

## Verification — 2026-10-21

- 591 Node tests passed; maintenance release guard and whitespace checks passed.
- 43 source screens at 1440, 390, and 320 CSS pixels, each with normal and
  large-text/high-contrast/reduced-motion preferences: **258 render checks**.
- 39 data-bearing screens were required to show populated content through their
  actual browser renderers and data adapters. Synthetic read responses were
  intercepted in-process. The other four screens are login, maintenance, settings,
  and account settings. The local test session is synthetic, not a real login.
- Fixtures include a 50-product catalog, 25 customers/suppliers and ledger rows,
  15-line receipts and carts, long Sorani names/notes, and populated reports,
  allocations, import previews, export verification, labels, and price lookup.
- Ten additional money-sensitive screens were checked at all three widths with
  both preference profiles: **60 boundary-value render checks**, including
  1,000,000,000 IQD unit prices and 100,000,000,000,000 IQD balances.
- All 318 checks passed without document overflow, uncaught JavaScript errors,
  missing expected populated content, unresolved fixture requests, control role
  color/geometry/font mismatches, card radius mismatches, or table font/padding
  mismatches. Normal and high-contrast headers each use one consistent color;
  every screen uses the shared font stack. All existing dialogs fit the viewport.
- Sale and purchase receipt previews were additionally rendered into six PDFs:
  58 mm, 80 mm, and A4 for each. All 15 line items remained in the print DOM, the
  paper/table bounds fitted, and the screen scroll wrapper became visible overflow
  for print. This does not test a physical printer or its driver.
- The audit found and fixed legacy field ID overrides, secondary/primary button
  color differences, table typography, a populated allocation grid's minimum
  width, narrow-screen large money values, and the receipt table's screen overflow.

## Reproducing browser checks

`scripts/design-audit.cjs` requires Playwright and Chromium. Optionally set
`PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` to an installed Chromium binary. By default
it checks every source page at three widths with both accessibility profiles and
writes local results under `/tmp/kashier-populated-audit`.

```sh
node scripts/design-audit.cjs
```

Optional environment variables:

- `KASHIER_UI_AUDIT_OUTPUT`: result/screenshot/PDF directory.
- `KASHIER_UI_AUDIT_WIDTHS`: comma-separated widths (default `1440,390,320`).
- `KASHIER_UI_AUDIT_PROFILES`: `normal,accessible` by default.
- `KASHIER_UI_AUDIT_PAGES`: comma-separated HTML filenames for focused checks.
- `KASHIER_UI_AUDIT_EDGE=1`: enable valid large-money boundary fixtures.
- `KASHIER_UI_AUDIT_SCREENSHOTS=1`: capture full-page screenshots.
- `KASHIER_UI_AUDIT_PRINT=1`: generate receipt PDFs and check print bounds.

Business-service requests are fulfilled from explicit synthetic fixtures;
mutations and unknown endpoints are blocked. Nothing is added to a real market.
Application authentication/authorization, production data, physical devices, and
production deployment were not verified by this UI audit. Passing this finite
matrix is evidence of consistency in the checked states, not a guarantee for
all possible data, browsers, or devices. The PR remains separate from `main`.
