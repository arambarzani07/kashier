# Kashier production readiness — 2026-10-19

**Decision: not yet cleared for real-shop operation.** The evidence below supports the implemented online backend; authenticated browser acceptance is partial and physical shop checks remain open. Offline operation is not implemented.

## Verified release

Runtime commit: `296e2124f2234425155db9677534bce57eba9b99`.
Production: https://kashier-hazel.vercel.app
The subsequent security-audit commit changes documentation/tests only.

- Full release check passed: 730 Node tests across 78 files, static references and source/output parity.
- Live configuration audit passed: 30 public tables with RLS, 84 public invoker RPCs denying anonymous execution, four invoker views, no anonymous relation/column grants or client TRUNCATE grants, and no direct client access to private restore receipts.
- Thirteen live database suites below passed. They run in temporary test accounts inside transactions ending in ROLLBACK. Follow-up verification found zero surviving fixture accounts. These tests exercise database functions under simulated JWT claims; they do not test actual browser sign-in, network/session behavior or printer/scanner hardware. PostgreSQL sequences can consume numbers even in rolled-back tests; numbering gaps are not duplicated transactions.

| Database suite | Verified behavior | Result |
| --- | --- | --- |
| sales-rls.sql | Cash arithmetic, immutable snapshots, replay/conflict safety, atomic failure and owner isolation | PASS |
| credit-rls.sql | Full/partial credit, repayments, stock/cash/debt reconciliation and isolation | PASS |
| supplier-purchase-payment-rls.sql | Invoice-specific payment allocation, cash reconciliation and isolation | PASS |
| staff-rls.sql | Consent, grants/revocation, discount controls and actor attribution | PASS |
| staff-credit-rls.sql | Explicit credit permission and atomic staff cash/stock/debt effects | PASS |
| staff-repayment-rls.sql | Collection permission, stale balance/overpayment refusal and idempotency | PASS |
| staff-partial-rls.sql | Scoped own-cash partial returns, grant checks and return arithmetic | PASS |
| daily-close-rls.sql | Immutable day close, replay/conflict checks and scoped receipts | PASS |
| daily-close-history-rls.sql | Owner/range/grant checks, classification and no cash mutation | PASS |
| restore-daily-close-rls.sql | Exact v8 restoration including saved daily close | PASS |
| restore-supplier-rls.sql | Restoration preserving supplier financial relationships | PASS |
| restore-installments-rls.sql | Restoration preserving installment relationships | PASS |
| gross-profit-rls.sql | Forward-cost gross profit and explicit unknown historical cost coverage | PASS |

## Authenticated browser acceptance — partial

Checked against the stable production URL on 2026-10-19 using the secure sign-in flow. A fresh rendered daily-close page confirmed successful authentication. The user subsequently explicitly identified this as a test account; no separate staff identity has been tested.

- Daily-close preview loaded for the completed Baghdad day 2026-10-18, showing an expected balance of 0 IQD.
- Entering `١٢٣` displayed a numeric counted amount of 123 and signed surplus of +123 before saving.
- Adding an explanation and acknowledgment enabled Save. Changing the amount to `١٢٤` updated the surplus to +124, cleared acknowledgment and disabled Save.
- Cleared all draft values without saving. History loaded for 2026-10-01 through 2026-10-18 with zero saved closes.
- A range starting 2026-08-01 was rejected with the Sorani maximum-31-days message and disabled print/CSV; restoring the valid range reloaded the empty report.

The initial checks above submitted no financial records. After the user explicitly designated the signed-in account as a test account, the following browser writes were completed:

- Existing soap item `10101010` started at stock 0, sale price 1,500 IQD.
- Stock-only purchase `P-413` / `895ad85c-3805-4947-bb0d-591d799fb80b`: 10 units × 1,000 IQD = 10,000 IQD. The receipt explicitly records no cash/debt effect.
- Cash sale `K-473` / `90830334-a069-4e7f-b931-b6b9d269b06a`: 1 unit × 1,500 IQD; tender 5,000; change 3,500. The fresh stock page showed 9 remaining.
- Fresh daily report showed one cash sale, 1,500 cash inflow and 1,500 closing cash balance; stock-only purchase had zero paid cash and zero new supplier debt. Existing customer debt of 1,000 was unchanged.
- Full-return submission reached its browser confirmation boundary. The browser runtime refused dialog access with `retained_data_restricted`; explicit navigation to the retained canonical origin restored page observation. A further fresh daily report confirmed zero returns, zero refunds and cash balance still 1,500. Return acceptance remains BLOCKED by browser automation, not established as an application failure.

Test purchase and sales remain recorded for review.

### Credit sale and collection — 2026-10-19

- Partial-credit sale `K-474` / `97c0d246-a09c-45c8-ba70-f9c0551f008c`: one soap at 1,500 IQD, 500 cash received, 1,000 new debt. Fresh customer profile showed balance moving from 1,000 to 2,000 and sale debt entry `D-10560`.
- Collection `D-10561` / `71b91071-83a9-4f43-a46a-d2b60754cb7a`: 1,000 IQD, cash movement `8b58a322-b4d0-451c-9f75-4f52610f3079`. Fresh profile showed 1,000 remaining debt and exactly three ledger rows including the original historical charge.
- An attempted collection of 1,001 against the remaining 1,000 was blocked by native form validation before submission. OPEN localization finding: Chrome displayed English `Value must be less than or equal to 1000.` The financial guard worked, but the message needs Sorani localization.
- Fresh stock showed 8 units. Fresh daily report showed exactly two sales (one cash, one credit), 3,000 sales total, 2,000 sale cash plus 1,000 collections, zero returns/outflows, 3,000 closing cash. Debt reconciled as 1,000 opening + 1,000 new − 1,000 collected = 1,000 closing. No additional collection from the overpayment attempt appeared.

Supplier payment, completed return, close posting, export/restore, interruption recovery and separate staff boundaries still need browser evidence.

## Required acceptance before real-shop use

| Gate | Acceptance evidence needed | Status |
| --- | --- | --- |
| Authenticated browser workflows | Login, stock-only purchase, cash/partial-credit sales, collection, stock/cash/debt reconciliation and read-only close/history checks passed; supplier payment, completed return, export/checksum and empty-account recovery remain | PARTIAL |
| Cashier/manager browser boundaries | Separate identities, consent, allowed actions, denied actions and owner suspension | NOT RUN |
| Interruptions and retry in browser | Refresh/back navigation/account change during pending requests; identical UUID recovery without duplicated financial entries | NOT RUN |
| Physical receipt and labels | Actual shop printer, Kurdish rendering, paper dimensions, totals, long names and barcode readability | NOT RUN |
| Physical scan workflow | Actual scanner and supported item barcodes; scale-label behavior must be explicitly verified before weighted goods are used | NOT RUN |
| Real till reconciliation | Opening cash plus recorded inflows minus outflows agrees with counted cash; differences have a recorded explanation | NOT RUN |
| Security setting | Existing leaked-password protection warning reviewed/resolved in Auth settings | OPEN |

Auth settings reference: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
The INFO advisory on private restore receipts having RLS without policies reflects deliberate denial of direct client access; the scoped internal recovery functions remain the access path.

## Unsupported scope

Staff credit-sale returns, returns of other actors' receipts, staff purchasing/inventory writes, broader staff financial reporting, shift cash handover, net-profit accounting and offline operation remain unimplemented. Do not enable or describe these as supported. Gross profit is coverage-aware; it must not be described as net profit. Same-owner archive recovery is restricted to an empty account in the same database and is not a migration or merge.

No launch approval or real-shop readiness claim is implied by this report. Database suites created no lasting fixture accounts. Browser acceptance subsequently created the explicitly authorized test-account records listed above; they remain for review.
