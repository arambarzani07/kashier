# Kashier online completion status

User direction, 2026-10-18 Asia/Baghdad: finish the online system before working on offline behavior. Offline work is explicitly deferred. Work only on this Kashier project.

Implemented online: owner-isolated accounts, catalog, cash/credit sales, purchases, stock/stocktake/waste, customer/supplier debts and statements, sale/purchase returns, supplier invoice payments, searchable receipts, labels, price lookup, expiry/minimum-stock alerts, dashboard balances, reports, CSV/JSON exports and export verification. Own-account identity/password self-service, explicit customer repayment allocation/reversal and customer installment schedules/cancellation, due-status reports, print/CSV and owner export v4 are implemented.

Remaining major online work:

- Installments: scheduled existing charges support 1–60 strictly ordered due dates, an immutable cancellation audit and one active plan per charge. Explicit allocations cover earliest due dates for reporting; unassigned customer repayments mark due statuses unconfirmed. Home alerts/report tiles and customer-profile editing are connected. No outbound reminders, fees, new loans or automatic classification. Verify the complete browser flow and real shop semantics next.
- Profit: define a consistent inventory-cost policy and record cost coverage. Existing historical sales do not contain an authoritative COGS snapshot. Never present sales minus all purchases, current sale price or guessed historical costs as profit.
- Shared-store employees: role/membership-based store ownership, cashier permissions and audit need a deliberate migration. Self-service account settings do not supply employee administration; current owner RLS must not be weakened or reassigned without a reviewed design.
- Complete browser flow QA, physical printing/scanning QA, and regression checks for real shop workflows before calling the online system finished.

The remaining profit dashboard tile still shows unavailable-module UI. Do not report the whole system as complete. No offline app shell, offline posting queue or offline/online stock reconciliation has been started.
