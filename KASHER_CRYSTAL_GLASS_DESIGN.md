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
