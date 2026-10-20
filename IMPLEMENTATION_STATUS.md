# Kashier online completion status

User direction, 2026-10-18 Asia/Baghdad: finish the online system before working on offline behavior. Offline work is explicitly deferred. Work only on this Kashier project.

Implemented online: owner-isolated accounts, catalog, cash/credit sales, purchases, stock/stocktake/waste, customer/supplier debts and statements, sale/purchase returns, supplier invoice payments, searchable receipts, labels, price lookup, expiry/minimum-stock alerts, dashboard balances, reports, CSV/JSON exports and export verification. Own-account identity/password self-service and explicit customer repayment allocation/reversal are now implemented.

Remaining major online work:

- Installments: explicit invoice/manual-charge payment allocation is implemented, including immutable allocation reversals and protection against returning an allocated credit invoice. Attach installment schedules, overdue alerts and installment reports next. Historical repayments remain unassigned until the owner explicitly classifies them; never silently reallocate history or duplicate debt.
- Profit: define a consistent inventory-cost policy and record cost coverage. Existing historical sales do not contain an authoritative COGS snapshot. Never present sales minus all purchases, current sale price or guessed historical costs as profit.
- Access X identity: Phase 1 baseline, manager/cashier isolation, staff-administration and schema-fingerprint tests passed (transaction ROLLBACK; 2026-10-20). The 24 missing *already applied* SQL migration files were recovered from the project's existing development branch into `main` and 72/72 filenames match the verified live migration history. This fixes migration-file drift, **not** full schema equivalence. Current staff onboarding still uses existing Auth accounts + acceptance; no-invitation manager-created staff and manager role constraints remain pending in production. A staged fail-closed server-only provisioning core with isolated Node tests is added in `access-x/`, but has no durable adapter or deployed Auth integration. Auth/RLS cutover requires schema replay/diff, restore rehearsal and authorization tests. Details: `ACCESS_X_IMPLEMENTATION.md`.
- Complete browser flow QA, physical printing/scanning QA, and regression checks for real shop workflows before calling the online system finished.

The remaining installment/profit dashboard tiles still show unavailable-module UI. Do not report the whole system as complete. No offline app shell, offline posting queue or offline/online stock reconciliation has been started.
