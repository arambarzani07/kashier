# Kashier production readiness — 2026-10-19

**Decision: not yet cleared for real-shop operation.** The evidence below supports the implemented online backend; authenticated browser acceptance is partial and physical shop checks remain open. Offline operation is not implemented.

## Verified release

Runtime commit: `f45c6e04e1cc2ec5142550170e4e80938d39397a` (Sorani validation and purchase-payment journal safeguards).
Production: https://kashier-hazel.vercel.app
Earlier financial workflow checks below ran on runtime `296e2124f2234425155db9677534bce57eba9b99`; later releases add Sorani debt validation, delay new purchase-payment retry journals until confirmation, and stop payment when journals cannot be safely recovered or saved.

- Full release check passed: 738 Node tests across 78 files, static references and source/output parity.
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
- An attempted collection of 1,001 against the remaining 1,000 was blocked by native form validation before submission. Chrome initially displayed English `Value must be less than or equal to 1000.` Fixed in `ab6bfffd76444a6b9476fa9d336600c13692aefe`: capture native invalid events, suppress the browser bubble and show Sorani inline errors while preserving native constraints and financial guards. Two regressions cover overpayment, correction, missing fields and invalid numeric steps. Production deployment `dpl_GMHDq1UY8QubiruQT1rnkKvupyD9` reached READY. Browser verification against the stable production alias passed: 1,001 against debt 1,000 showed the Sorani overpayment message without the English bubble; empty amount and empty reason each showed Sorani instructions. Draft fields were cleared afterward. Refreshed profile retained 1,000 debt and three ledger entries; no additional financial entry was submitted.
- Fresh stock showed 8 units. Fresh daily report showed exactly two sales (one cash, one credit), 3,000 sales total, 2,000 sale cash plus 1,000 collections, zero returns/outflows, 3,000 closing cash. Debt reconciled as 1,000 opening + 1,000 new − 1,000 collected = 1,000 closing. No additional collection from the overpayment attempt appeared.

### Tracked supplier purchase — 2026-10-19

- Created explicitly labeled test supplier `4015b842-3ed4-4280-8c67-3e93a8a9a7fe`, starting at zero debt.
- Purchase `P-414` / `df6e4ddd-d9a5-4091-85d8-1eb4717f81f8`: one soap × 1,000 IQD, 250 initial cash payment and 750 supplier debt. Fresh supplier profile showed exactly one purchase-debt row `D-121` for 750.
- Fresh stock showed 9 units (8 + 1). Fresh daily report showed two purchases totaling 11,000, initial purchase cash paid 250, supplier debt created 750, zero subsequent supplier payments, and closing cash 2,750 (3,000 − 250). Customer debt remained 1,000.
- Prepared, but did not submit, a 750 IQD payment against P-414 with a Sorani test note. Source inspection confirmed that subsequent supplier payments use a native confirm dialog, the same browser capability previously blocked for returns. Manual browser handoff is needed to complete that acceptance step; no payment success is claimed.

- Following the user's explicit request, clicked Submit Payment for 750. Native dialog access was again rejected by the browser runtime. After permitted canonical-origin recovery, a fresh purchase finance panel still showed subsequent payments 0 and outstanding 750. Its retry draft retained the same request identity; no supplier payment was completed.

### Posted daily close and history — 2026-10-19

- Posted the completed Baghdad day 2026-10-18 with expected 0, test counted amount `٠` (0), difference 0 and an explicit Sorani note stating this is a QA document, not a physical till count.
- Saved close ID: `e1ca33e2-3f0e-4a18-b46b-1843cd191d12`; created at `2026-10-19T14:53:13.257144+00:00`.
- Fresh rendered receipt reported success and no cash transaction, with amount/note/acknowledgment/save controls disabled. Print and CSV controls were enabled. This verifies UI locking, not an attempted server-side tamper.
- Navigated to history: exactly one saved close appeared, classified balanced, with date 2026-10-18, expected/counted/difference all zero and the saved QA note. The date link pointed to that day's detail page.
- CSV-download observation failed with the browser runtime's `retained_data_restricted` error and reset its kernel before a file path was returned. Rebinding the existing tab was refused because native credential state could not safely resume. CSV completion and subsequent detail navigation remain UNKNOWN; no further browser recovery was attempted. This is an automation limitation, not evidence of an application CSV failure.

### Live export plus local verification — 2026-10-19

- Called `export_owner_data()` for the explicitly designated test owner in a READ ONLY transaction with authenticated role and simulated JWT claims, ending ROLLBACK. This tests the database export path, not browser authentication/download.
- The JSON v8 archive contained 29 records across all 30 table keys, including the posted daily close. Its original JSON text was preserved for local validation (17,043 UTF-8 bytes).
- Ran the production `ExportFile.prepare`, `verify`, relationship checks and checksum-sidecar reader against that archive. SHA-256: `320f416b6abc63fe7fe54114c97612ebda90e5d2a6c42fb7383449ff1472e781`.
- Archive balances matched fresh browser evidence: stock 9 units, cash 2,750 IQD, customer debt 1,000, supplier debt 750, one daily close. It contained exactly two sales, two purchases, three customer ledger entries and zero subsequent supplier payment allocations.
- Exact-byte roundtrip and sidecar verification passed. Appending one newline was rejected with the original digest; verification under a different owner was rejected. No data was restored or changed by this audit.

Supplier payment completion, completed return, browser CSV/export/download/restore, interruption recovery and separate staff boundaries still need browser evidence. Physical till reconciliation remains untested; the saved zero close is explicitly test data.

## Live gross-profit and inventory-value reconciliation — 2026-10-19

Read-only database RPCs ran as the test owner with simulated authenticated JWT claims in a READ ONLY transaction ending ROLLBACK. The actual production frontend models validated both returned reports locally; this does not establish browser UI/download acceptance.

- Gross-profit report for 2026-10-19 contained exactly cash receipt K-473 and partial-credit receipt K-474: revenue 3,000 IQD, known COGS 2,000, gross margin 1,000. Both cost lines had known coverage; no unknown cost was treated as zero.
- Current inventory valuation contained one product, 9 units at total value 9,000 IQD, with complete known cost coverage. This reconciles 11 purchased units at 1,000 each minus two sold units at cost 1,000 each.
- Frontend validators rejected altered summary totals (margin 1,001 and stock value 9,001). Both CSV model outputs contained the expected summary/detail row counts and source receipts/product barcode. No browser download is claimed.
- The 1,000 margin is gross profit before expenses, not net profit. It is distinct from cash balance 2,750, customer debt 1,000 and supplier debt 750.

## Purchase-payment cancellation fix — 2026-10-19

Source review found that a new purchase-payment journal was saved before the native confirmation. Cancelling therefore left a false pending request and could block correcting the amount/note after reload.

- New requests are now journaled only after confirmation. Cancelling shows a Sorani cancellation message and leaves no new pending journal or network call.
- Previously submitted ambiguous requests retain their original journal/UUID when retry confirmation is cancelled. Retrying again reuses exactly the same payload.
- Confirmation remains required. A journal-storage failure after approval still blocks sending.
- Three new UI regressions cover cancel/edit/reload, ambiguous retry cancellation/identity preservation, and storage failure. Full release check passed with 735 tests across 78 files.
- This fix does not clear old ambiguous journals, submit the outstanding 750 payment, or resolve the cloud browser's native dialog restriction. Deployment `dpl_6nvPADDny5Jn367j9GWSkMhfR8JW` reached READY; the stable production asset returned HTTP 200 with confirmation preceding journal save and both Sorani cancellation messages. Browser acceptance of this change remains blocked.

## Corrupt payment-journal safeguards — 2026-10-19

Source review found that a failed journal read or malformed JSON was silently interpreted as no pending payment, allowing a new request identity despite an unknown prior outcome.

- Missing storage entry alone means no draft. Unreadable storage, invalid JSON, null/array/invalid journal fields now stop payment with a Sorani support message. The stored value is preserved.
- Failed finance/journal loading hides the payment form; the submit path independently refuses an invalid journal even if triggered directly.
- Journal writes must be read back exactly before a request is sent. Silent failed writes block posting. Overlong notes are rejected before journaling.
- Three new regressions cover corrupt journal values, unavailable reads/silent write loss and valid pending-request recovery after reload. All 738 tests and static parity checks passed.
- No old browser journal was cleared and no outstanding supplier payment was submitted. Deployment `dpl_A3kPEg24zPkBrJRZjS8wTRb8CR16` reached READY and the stable production asset returned HTTP 200 with strict journal reads and exact write-readback verification. Native dialog/browser acceptance remains open.

## Required acceptance before real-shop use

| Gate | Acceptance evidence needed | Status |
| --- | --- | --- |
| Authenticated browser workflows | Login, stock-only/tracked purchases, cash/partial-credit sales, collection, stock/cash/debt reconciliation and posted close/history checks passed; supplier payment, completed return, export/checksum and empty-account recovery remain | PARTIAL |
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
