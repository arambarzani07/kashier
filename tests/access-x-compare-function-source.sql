-- Temporary scratch-only source review. These routines are already declared in the public repository.
-- This query reads PostgreSQL function DDL only, NEVER reads business records.
\pset format unaligned
\pset tuples_only on
with selected (signature) as (values
 ('private.get_cashier_refund(uuid,uuid)'),
 ('private.get_cashier_refund_sale(uuid,uuid,bigint)'),
 ('private.get_cashier_refund_workspace(uuid)'),
 ('private.post_cashier_refund(uuid,uuid,uuid,text)'),
 ('private.post_sale_reversal_for_owner(uuid,uuid,uuid,text)'),
 ('public.get_cash_statement(date,date)'),
 ('public.get_supplier_payables_report(text,text,bigint,bigint,integer,integer)')
)
select 'AX_FUNCTION_SOURCE|'||signature||'|'||
 encode(convert_to(pg_get_functiondef(signature::regprocedure),'UTF8'),'hex')
from selected order by signature;
