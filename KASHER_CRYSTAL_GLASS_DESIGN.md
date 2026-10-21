# Kashêr Crystal Glass Enterprise UI — Design system v1 (2026-10-21)

## Status

**REAL SOURCE CODE CHANGE, NOT A PRODUCTION DESIGN CERTIFICATION.** The root \`glass-system.css\` is imported **last** in the document HEAD of all **42 application HTML pages** in this repository. The dedicated \`maintenance.html\` is purposely excluded. Current \`vercel.json\` continues to use the maintenance release gate; no login, role, financial privilege, RLS or database change accompanies the glass redesign.

The first release changes **presentation only**. Each existing page retains its business HTML, its original page-specific CSS/JS behavior and the same IDs/hooks. The new final CSS layer unifies their visual surface using common tokens and familiar Sorani RTL patterns. Print media is unaffected since all presentation selectors are scoped to \`@media screen\`. This change must be tested visually on Windows cashier resolution, iPhone/iPad RTL, and high-density tables before production approval.

## Design foundation

- **Font / RTL:** Noto Sans Arabic → Tahoma → Arial fallback; existing \`lang=ckb\`, \`dir=rtl\` retained on every app page. Do not reverse barcode digits or amounts.
- **Primary:** \`#205FC3\`; dark \`#153F88\`; text \`#132642\`; soft text \`#4E617A\`.
- **Semantic:** success \`#12765B\`, warning \`#915509\`, danger \`#AD3048\`, keyboard focus \`#3475E7\`.
- **Surfaces:** canvas \`#EEF4FC\`, strong white 93%, medium white 82%, light white 71% alpha.
- **Radius:** 12 / 18 / 24px. **Shadows:** three restrained layers. **Blur:** 14px only on suitable panels/modal containers; product tiles use no expensive per-tile blur.
- **Functional priority:** the POS cart and payment panels use bright glass to retain high contrast and fast barcode workflows. Tables keep tabular numerals. Print area explicitly uses white background and no blur/shadow; print styles are not modified.
- **Accessibility:** visible keyboard focus, readable placeholder contrast, reduced motion/transparency support, mobile radius/spacing accommodation.

## Screen groups covered

- **Entry and overview:** auth, home/index, account settings.
- **Checkout and refunds:** sale, receipt(s), return, quick return, purchase and purchase returns, receipt/return document.
- **Catalog and inventory:** products, product profile, import/export, stock, count, adjustments, expiry, labels, waste, price check.
- **Customers and debt:** customers, customer profile, debt balances, allocations, statements.
- **Finance/management:** cash, close, cash statement, purchase and sales reports, expense report, settings.
- **Supplier domain:** suppliers, supplier profile, payables, statements and balances.
- **Export verification:** data export and verification screens.

## Definition of done for the **next** phase

1. Inspect the rendered screens visually on 1366×768 and 1920×1080 Windows, iPhone narrow sizes, plus printer preview; improve any clipping, overflow or low-contrast combinations found.
2. Consolidate duplicated legacy component selectors into primitives rather than layering overrides indefinitely; account for existing RTL mobile breakpoints and accessibility.
3. Prove consistent states on real table content, empty lists, error/loading and offline; capture baseline screenshots/diff across pages.
4. Retain security/backup/restore gate and maintenance-only deployment until a separately authorized production release.

\`tests/crystal-glass-design.test.cjs\` provides static 42/42 link coverage + safety invariants. This static suite **does not constitute screenshot/visual QA or UX acceptance**.

## v2 — functional layout refinements

- Responsive cashier/cart has an explicit \`min-width:0\` grid sizing contract, with **local horizontal scrolling only inside the item table** at mobile widths. No forced whole-page sideways scrolling is intended.
- Barcode search and payment controls get minimum finger targets; price/total numerals use tabular figures. Payment total keeps readable high-contrast blue (rather than translucent text).
- The sticky top/nav region grows safely with text on narrow devices; heading/action wrapping is allowed without dropping controls.
- Glass-related changes remain CSS-only and under \`@media screen\`; printed receipts and all cashier financial code are unchanged.
- Browser screenshot verification of real viewports is separately required before claiming full visual parity; static CSS unit assertions alone are insufficient.

## Browser-based screenshot and overflow smoke QA (v2)

\`scripts/crystal-glass-browser-qa.cjs\` and \`.github/workflows/crystal-glass-visual.yml\` render actual Chromium screenshots of the source HTML in a **completely isolated local server**, at 1366×768 Windows and 390×844 iPhone-like viewports, for seven representative pages (14 captures), plus one fictional print receipt.

**Safety:** all original application JavaScript is removed from the offline HTML preview; only test-generated Kurdish labels and invented numeric amounts are inserted in the DOM. An explicit network route gate denies any request outside 127.0.0.1; CSP also denies remote connections. Tests cannot authenticate, contact Supabase, access customer records or process a payment. The screenshots/JSON report are short-lived GitHub Actions artifacts. This is layout smoke testing, *not production screenshot validation or user acceptance*.

The browser job fails on whole-document horizontal overflow, missing Kurdish RTL, missing unified stylesheet, bad local HTTP response, or hidden printed receipt. Local, intentional horizontal scrolling inside POS line-item table is permitted.

### v2 Chromium verification evidence — PASSED (2026-10-21)

- Initial real Chromium viewport audit caught **36px whole-document overflow** on \`products.html\` at 390px wide. Root cause traced to the non-wrapping \`.topbar .header-links\` + logout item on a Sorani RTL product header.
- Fixed with mobile \`flex-wrap:wrap\`, \`min-width:0\`, full-width link group on narrow screens and consistent touch-target heights, without removing any navigation link.
- [Final Chromium run 39576922067](https://github.com/arambarzani07/kashier/actions/runs/39576922067): **PASS 14/14 rendered viewport samples** (7 representative application pages × 1366×768 desktop / 390×844 phone), no document-level horizontal overflow, required \`lang=ckb\`/\`dir=rtl\` and CSS loaded. **Print-media synthetic receipt also passed**.
- [Artifact (short retention)](https://github.com/arambarzani07/kashier/actions/runs/39576922067/artifacts/12334234498): offline synthetic page screenshots and machine-readable layout measurements; does not contain real customers or transactions.
- [Node CI run 39576922139](https://github.com/arambarzani07/kashier/actions/runs/39576922139): **592/592** passing, **0** failures.
- Not verified: manual human visual acceptance of screenshots, actual live customer records, all 42 pages under full browser automation, logged-in roles, real peripherals, or production release. Keep production maintenance and data backup gates intact.
