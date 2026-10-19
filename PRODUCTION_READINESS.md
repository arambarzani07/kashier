# Kashier production readiness — 2026-10-19

**Decision: not yet cleared for real-shop operation.** The evidence below supports the implemented online backend; authenticated browser acceptance and physical shop checks remain open. Offline operation is not implemented.

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

## Required acceptance before real-shop use

| Gate | Acceptance evidence needed | Status |
| --- | --- | --- |
| Authenticated browser workflows | Owner login; cash/credit sale; customer collection; supplier payment; own-cash return; close/history; export/checksum; and recovery in an empty test account | NOT RUN |
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

No launch approval or real-shop readiness claim is implied by this report. No real customer/store records were created for these checks.
