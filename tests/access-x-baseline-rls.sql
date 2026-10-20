-- Access X Phase 1: read-only schema/RLS authorization baseline.
-- Run with a database-admin connection. No DML, no users, no market data.
begin transaction read only;
do $access_x$
declare v text;
begin
 select string_agg(format('%I.%I',n.nspname,c.relname),', ') into v
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind in ('r','p') and not c.relrowsecurity;
 if v is not null then raise exception 'access_x_public_table_without_rls: %',v;end if;

 select string_agg(t.rel,', ') into v from (values
  ('products'),('sales'),('purchases'),('customers'),('customer_balances'),
  ('debt_entries'),('cash_accounts'),('cash_movements'),('sale_returns'),
  ('sale_reversals'),('store_cashiers'),('staff_actions')
 ) as t(rel) where to_regclass('public.'||t.rel) is null;
 if v is not null then raise exception 'access_x_required_tables_missing: %',v;end if;

 select string_agg(t.rel,', ') into v from (values
 ('products'),('sales'),('purchases'),('customers'),('customer_balances'),
 ('debt_entries'),('cash_accounts'),('cash_movements'),('sale_returns'),('sale_reversals')
 ) as t(rel)
 where not exists (
  select 1 from pg_policies p where p.schemaname='public' and p.tablename=t.rel
  and p.cmd in ('SELECT','ALL') and p.qual like '%auth.uid()%' and p.qual like '%owner_id%'
 );
 if v is not null then raise exception 'access_x_owner_read_policy_missing: %',v;end if;

 select string_agg(t.rel,', ') into v from (values('store_cashiers'),('staff_actions')) as t(rel)
 where not exists(
  select 1 from pg_policies p where p.schemaname='public' and p.tablename=t.rel
  and p.cmd in ('SELECT','ALL') and p.qual like '%auth.uid()%'
  and p.qual like '%owner_id%' and p.qual like '%member_id%'
 );
 if v is not null then raise exception 'access_x_membership_policy_missing: %',v;end if;

 select string_agg(p.proname,', ') into v from pg_proc p
 join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname in (
 'post_cash_sale','post_credit_sale','post_sale_return','post_sale_reversal',
 'save_store_cashier','accept_store_cashier','post_cashier_sale',
 'post_cashier_credit_sale','post_cashier_repayment','post_cashier_refund'
 ) and has_function_privilege('anon',p.oid,'execute');
 if v is not null then raise exception 'access_x_anon_write_rpc_exposed: %',v;end if;

 select string_agg(p.proname,', ') into v from pg_proc p
 join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname in (
 'post_cash_sale_for_owner','post_credit_sale_for_owner',
 'post_sale_return_for_owner','post_sale_reversal_for_owner','cashier_membership'
 ) and has_function_privilege('authenticated',p.oid,'execute');
 if v is not null then raise exception 'access_x_private_owner_bypass_granted: %',v;end if;

 if not exists(
  select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname='cashier_membership'
  and position('accepted_at' in pg_get_functiondef(p.oid))>0
  and position('enabled' in pg_get_functiondef(p.oid))>0
 ) then raise exception 'access_x_cashier_membership_gate_missing';end if;
end
$access_x$;
select 'PASS: public table RLS, owner scopes, staff participant scopes, no anonymous posting RPCs, and private owner helper locks' as access_x_baseline;
rollback;
