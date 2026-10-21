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

- 588 Node tests passed; maintenance release guard and whitespace checks passed.
- All 43 source screens rendered at 1440, 390, and 320 CSS pixels: 129 checks,
  no document-wide horizontal overflow and no uncaught JavaScript errors.
- All 43 screens rendered again at 390 pixels with large text, high contrast,
  and reduced motion; all 18 existing dialogs fitted the viewport.
- Fixed the purchase-returns filter's oversized desktop grid and an absolutely
  positioned table accessibility label that expanded the narrow purchase page.
- Screens were inspected with empty/guest states. The local layout harness
  suppressed guest navigation to login while leaving the page's scripts running;
  it did not authenticate a user, mock a business response, or mutate a database.
  This is UI validation, not evidence that the staged backend is production-ready.
