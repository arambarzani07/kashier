# Kashier online completion status

User direction, 2026-10-18 Asia/Baghdad: finish the online system before working on offline behavior. Offline work is explicitly deferred. Work only on this Kashier project.

Implemented online: owner-isolated accounts, catalog, cash/credit sales, purchases, stock/stocktake/waste, customer/supplier debts and statements, sale/purchase returns, supplier invoice payments, searchable receipts, labels, price lookup, expiry/minimum-stock alerts, dashboard balances, reports, CSV/JSON exports and export verification. Own-account identity/password self-service is now implemented.

Remaining major online work:

- Installments: define and implement invoice-level customer payment allocation before attaching installment schedules, overdue alerts and installment reports. Existing customer repayments are account-level; do not silently reallocate history or duplicate debt.
- Profit: define a consistent inventory-cost policy and record cost coverage. Existing historical sales do not contain an authoritative COGS snapshot. Never present sales minus all purchases, current sale price or guessed historical costs as profit.
- Shared-store employees: role/membership-based store ownership, cashier permissions and audit need a deliberate migration. Self-service account settings do not supply employee administration; current owner RLS must not be weakened or reassigned without a reviewed design.
- Complete browser flow QA, physical printing/scanning QA, and regression checks for real shop workflows before calling the online system finished.

The remaining installment/profit dashboard tiles still show unavailable-module UI. Do not report the whole system as complete. No offline app shell, offline posting queue or offline/online stock reconciliation has been started.
