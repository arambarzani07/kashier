# Kashêr Crystal Glass — final design polish (draft branch)

This change applies **only** to the draft \`design/sales-workspace\` branch (PR #3), **not** to protected \`main\` or the production domain. It unifies the already-existing glass treatment, reduces blur/fixed-background rendering cost on mobile, normalizes form/toolbar shapes, limits oversized dialogs and confines long financial tables to horizontal in-panel scrolling.

Receipt, statement, label and report paper surfaces are opaque white **on screen**; all visual changes are inside \`@media screen\`, so business print styles and page sizes remain feature-owned. Browser preferences for reduced transparency/forced colors are respected.

The added \`tests/crystal-glass-final.test.cjs\` statically verifies these guardrails. GitHub CI may run because PR #3 is open; passing tests are not equivalent to complete browser/print/hardware/manual visual acceptance. Existing Auth, permission, ledger, POS business logic, offline data and Vercel release routing were not touched.

Keep PR #3 in draft until independently confirmed that it can be safely merged; do not promote a preview deployment to production without the separate release/backup gate.
