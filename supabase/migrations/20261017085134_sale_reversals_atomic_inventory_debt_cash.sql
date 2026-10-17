create table public.sale_reversals (
 id uuid primary key,
 reversal_no bigint generated always as identity unique,
 owner_id uuid not null references auth.users(id),
 sale_id uuid not null unique references public.sales(id),
 created_at timestamptz not null default now(),
 reason text not null check(char_length(btrim(reason)) between 1 and 500),
 currency text not null default 'IQD' check(currency='IQD'),
 total bigint not null check(total between 0 and 100000000000000),
 cash_refund bigint not null check(cash_refund between 0 and 100000000000000),
 debt_reversed bigint not null check(debt_reversed between 0 and 100000000000000),
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 200),
 request_payload jsonb not null,
 check(total=cash_refund+debt_reversed)
);
create index sale_reversals_owner_created_idx on public.sale_reversals(owner_id,created_at desc,id);
alter table public.sale_reversals enable row level security;
revoke all on public.sale_reversals from anon,authenticated;
revoke all on sequence public.sale_reversals_reversal_no_seq from anon,authenticated;
grant select on public.sale_reversals to authenticated;
create policy sale_reversals_read_own on public.sale_reversals for select to authenticated using ((select auth.uid())=owner_id);

alter table public.stock_movements add column reversal_id uuid references public.sale_reversals(id);
alter table public.stock_movements drop constraint stock_movements_check;
alter table public.stock_movements add constraint stock_movements_source_check check(
 (purchase_id is not null and sale_id is null and reversal_id is null and delta_units>0)
 or (purchase_id is null and sale_id is not null and reversal_id is null and delta_units<0)
 or (purchase_id is null and sale_id is null and reversal_id is not null and delta_units>0)
);
alter table public.stock_movements add constraint stock_movements_reversal_line_key unique(reversal_id,line_no);
create index stock_movements_reversal_idx on public.stock_movements(reversal_id) where reversal_id is not null;

alter table public.cash_movements add column reversal_id uuid unique references public.sale_reversals(id);
alter table public.cash_movements drop constraint cash_movements_kind_check;
alter table public.cash_movements drop constraint cash_movements_direction_check;
alter table public.cash_movements drop constraint cash_movements_source_check;
alter table public.cash_movements add constraint cash_movements_kind_check check(kind in ('sale','deposit','withdrawal','expense','repayment','refund'));
alter table public.cash_movements add constraint cash_movements_direction_check check(delta=case when kind in ('sale','deposit','repayment') then amount else -amount end);
alter table public.cash_movements add constraint cash_movements_source_check check(
 (kind='sale' and sale_id is not null and customer_id is null and reversal_id is null)
 or (kind='repayment' and sale_id is null and customer_id is not null and reversal_id is null and amount>0 and char_length(btrim(note))>0)
 or (kind='refund' and sale_id is null and customer_id is null and reversal_id is not null and amount>0 and char_length(btrim(note))>0)
 or (kind in ('deposit','withdrawal','expense') and sale_id is null and customer_id is null and reversal_id is null and amount>0 and char_length(btrim(note))>0)
);

alter table public.debt_entries add column reversal_id uuid unique references public.sale_reversals(id);
alter table public.debt_entries drop constraint debt_entries_kind_check;
alter table public.debt_entries drop constraint debt_entries_check;
alter table public.debt_entries drop constraint debt_entries_check1;
alter table public.debt_entries add constraint debt_entries_kind_check check(kind in ('charge','repayment','reversal'));
alter table public.debt_entries add constraint debt_entries_direction_check check(delta=case when kind='charge' then amount else -amount end);
alter table public.debt_entries add constraint debt_entries_source_check check(
 (kind='charge' and cash_movement_id is null and reversal_id is null)
 or (kind='repayment' and cash_movement_id is not null and reversal_id is null and sale_id is null)
 or (kind='reversal' and cash_movement_id is null and reversal_id is not null and sale_id is null)
);

create function private.post_sale_reversal(p_id uuid,p_sale uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_payload jsonb;
 v_reversal public.sale_reversals%rowtype;
 v_sale public.sales%rowtype;
 v_line jsonb;
 v_stock record;
 v_qty bigint;
 v_after bigint;
 v_index integer:=0;
 v_refund bigint;
 v_debt bigint;
 v_debt_after bigint;
 v_cash_after bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='reversal_auth_required'; end if;
 if p_id is null or p_sale is null then raise exception 'reversal_invalid_request'; end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'reversal_reason_required'; end if;
 v_payload:=jsonb_build_object('sale_id',p_sale,'reason',btrim(p_reason));
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale-reversal.'||p_id::text,0));
 select * into v_reversal from public.sale_reversals where id=p_id;
 if found then
  if v_reversal.owner_id<>v_user or v_reversal.request_payload<>v_payload then raise exception 'reversal_request_conflict'; end if;
  return to_jsonb(v_reversal)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale-reversal-sale.'||p_sale::text,0));
 select * into v_sale from public.sales where id=p_sale and owner_id=v_user for share;
 if not found then raise exception 'reversal_sale_unavailable'; end if;
 if exists(select 1 from public.sale_reversals where sale_id=p_sale) then raise exception 'reversal_already_posted'; end if;
 v_debt:=v_sale.debt_amount;
 v_refund:=v_sale.total-v_debt;
 if v_refund<0 then raise exception 'reversal_invalid_sale'; end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 if v_debt>0 then
  perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||v_user::text,0));
  select balance-v_debt into v_debt_after from public.customer_balances where customer_id=v_sale.customer_id and owner_id=v_user for update;
  if not found or v_debt_after<0 then raise exception 'reversal_debt_already_repaid'; end if;
 end if;
 if v_refund>0 then
  perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
  select balance-v_refund into v_cash_after from public.cash_accounts where owner_id=v_user for update;
  if not found or v_cash_after<0 then raise exception 'reversal_cash_insufficient'; end if;
 end if;
 for v_stock in
  select (x->>'product_id')::uuid as product_id,sum((x->>'quantity_units')::bigint) as returned
  from jsonb_array_elements(v_sale.lines) x group by (x->>'product_id')::uuid
 loop
  select quantity_units into v_after from public.product_stock where product_id=v_stock.product_id and owner_id=v_user for update;
  if not found then raise exception 'reversal_stock_unavailable'; end if;
  if v_after>1000000000000-v_stock.returned then raise exception 'reversal_stock_limit'; end if;
 end loop;
 insert into public.sale_reversals(id,owner_id,sale_id,reason,total,cash_refund,debt_reversed,lines,request_payload)
 values(p_id,v_user,p_sale,btrim(p_reason),v_sale.total,v_refund,v_debt,v_sale.lines,v_payload)
 returning * into v_reversal;
 for v_line in select value from jsonb_array_elements(v_sale.lines) loop
  v_index:=v_index+1;
  v_qty:=(v_line->>'quantity_units')::bigint;
  update public.product_stock set quantity_units=quantity_units+v_qty,updated_at=now()
   where product_id=(v_line->>'product_id')::uuid and owner_id=v_user returning quantity_units into v_after;
  if not found then raise exception 'reversal_stock_unavailable'; end if;
  insert into public.stock_movements(owner_id,product_id,reversal_id,line_no,delta_units,balance_after)
   values(v_user,(v_line->>'product_id')::uuid,p_id,v_index,v_qty,v_after);
 end loop;
 if v_debt>0 then
  update public.customer_balances set balance=v_debt_after,updated_at=now() where customer_id=v_sale.customer_id and owner_id=v_user;
  insert into public.debt_entries(id,owner_id,customer_id,customer_name,kind,amount,delta,balance_after,note,cash_movement_id,request_payload,sale_id,reversal_id)
   values(gen_random_uuid(),v_user,v_sale.customer_id,v_sale.customer_name,'reversal',v_debt,-v_debt,v_debt_after,btrim(p_reason),null,jsonb_build_object('reversal_id',p_id,'sale_id',p_sale),null,p_id);
 end if;
 if v_refund>0 then
  update public.cash_accounts set balance=v_cash_after,updated_at=now() where owner_id=v_user;
  insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,sale_id,note,request_payload,customer_id,reversal_id)
   values(v_user,'refund',v_refund,-v_refund,v_cash_after,null,btrim(p_reason),jsonb_build_object('reversal_id',p_id,'sale_id',p_sale),null,p_id);
 end if;
 return to_jsonb(v_reversal)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_sale_reversal(uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.post_sale_reversal(uuid,uuid,text) to authenticated;

create function public.post_sale_reversal(p_id uuid,p_sale uuid,p_reason text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.post_sale_reversal(p_id,p_sale,p_reason);
$$;
revoke all on function public.post_sale_reversal(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.post_sale_reversal(uuid,uuid,text) to authenticated;

create or replace function public.get_cash_summary()
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
 'balance',coalesce((select balance from public.cash_accounts where owner_id=(select auth.uid())),0)::text,
 'sales',coalesce(sum(amount) filter(where kind='sale'),0)::text,
 'refunds',coalesce(sum(amount) filter(where kind='refund'),0)::text,
 'deposits',coalesce(sum(amount) filter(where kind='deposit'),0)::text,
 'withdrawals',coalesce(sum(amount) filter(where kind='withdrawal'),0)::text,
 'expenses',coalesce(sum(amount) filter(where kind='expense'),0)::text,
 'repayments',coalesce(sum(amount) filter(where kind='repayment'),0)::text,
 'count',count(*)::text
 ) from public.cash_movements where owner_id=(select auth.uid());
$$;

create or replace function public.get_customer_statement(p_customer uuid,p_from date default null,p_to date default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_customer public.customers%rowtype;v_from timestamptz;v_to timestamptz;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='debt_auth_required'; end if;
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'statement_invalid_dates'; end if;
 select * into v_customer from public.customers where id=p_customer and owner_id=v_user;
 if not found then raise exception 'debt_customer_unavailable'; end if;
 v_from:=p_from::timestamp at time zone 'Asia/Baghdad';
 v_to:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 with ledger as materialized (
  select id,movement_no,created_at,kind,amount,delta,note,sale_id,cash_movement_id,reversal_id from public.debt_entries where customer_id=p_customer and owner_id=v_user
 ), opening as (
  select coalesce(sum(delta) filter(where v_from is not null and created_at<v_from),0) as amount from ledger
 ), period as materialized (
  select * from ledger where (v_from is null or created_at>=v_from) and (v_to is null or created_at<v_to)
 ), totals as (
  select count(*) as count,coalesce(sum(amount) filter(where kind='charge'),0) as charges,coalesce(sum(amount) filter(where kind='repayment'),0) as repayments,coalesce(sum(amount) filter(where kind='reversal'),0) as reversals,coalesce(sum(delta),0) as delta from period
 ), ordered as (
  select *, (select amount from opening)+sum(delta) over(order by movement_no rows unbounded preceding) as statement_balance from period order by movement_no limit 5001
 )
 select jsonb_build_object(
  'customer',jsonb_build_object('id',v_customer.id,'name',v_customer.name,'phone',v_customer.phone),
  'from',p_from,'to',p_to,'timezone','Asia/Baghdad','generated_at',statement_timestamp(),'currency','IQD',
  'opening',o.amount::text,'charges',t.charges::text,'repayments',t.repayments::text,'reversals',t.reversals::text,'closing',(o.amount+t.delta)::text,'count',t.count,
  'rows',coalesce((select jsonb_agg(jsonb_build_object('id',id,'movement_no',movement_no::text,'created_at',created_at,'kind',kind,'amount',amount::text,'delta',delta::text,'balance',statement_balance::text,'note',note,'sale_id',sale_id,'cash_movement_id',cash_movement_id,'reversal_id',reversal_id) order by movement_no) from ordered),'[]'::jsonb)
 ) into v_result from opening o cross join totals t;
 if (v_result->>'count')::bigint>5000 then raise exception 'statement_too_many_rows'; end if;
 return v_result;
end $$;

create or replace function public.get_daily_report(p_day date)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_start timestamptz;v_end timestamptz;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='sale_auth_required'; end if;
 if p_day is null then raise exception 'report_day_required'; end if;
 v_start:=p_day::timestamp at time zone 'Asia/Baghdad';
 v_end:=(p_day+1)::timestamp at time zone 'Asia/Baghdad';
 with sales as (
  select count(*) as count,count(*) filter(where payment_mode='cash') as cash_count,count(*) filter(where payment_mode='credit') as credit_count,
   coalesce(sum(subtotal),0) as subtotal,coalesce(sum(discount),0) as discounts,coalesce(sum(total),0) as total,
   coalesce(sum(total) filter(where payment_mode='cash'),0) as cash_total,coalesce(sum(total) filter(where payment_mode='credit'),0) as credit_total,
   coalesce(sum(total-debt_amount),0) as cash_received,coalesce(sum(debt_amount),0) as debt_added
  from public.sales where owner_id=v_user and created_at>=v_start and created_at<v_end
 ), returns as (
  select count(*) as count,coalesce(sum(total),0) as total,coalesce(sum(cash_refund),0) as cash_refund,coalesce(sum(debt_reversed),0) as debt_reversed
  from public.sale_reversals where owner_id=v_user and created_at>=v_start and created_at<v_end
 ), cash as (
  select count(*) filter(where created_at>=v_start) as count,
   coalesce(sum(delta) filter(where created_at<v_start),0) as opening,
   coalesce(sum(delta) filter(where created_at>=v_start and delta>=0),0) as inflows,
   coalesce(-sum(delta) filter(where created_at>=v_start and delta<0),0) as outflows,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='sale'),0) as sales,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='refund'),0) as refunds,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='repayment'),0) as repayments,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='deposit'),0) as deposits,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='withdrawal'),0) as withdrawals,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='expense'),0) as expenses
  from public.cash_movements where owner_id=v_user and created_at<v_end
 ), debt as (
  select count(*) filter(where created_at>=v_start) as count,
   coalesce(sum(delta) filter(where created_at<v_start),0) as opening,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='charge' and sale_id is null),0) as manual_charges,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='charge' and sale_id is not null),0) as sale_charges,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='repayment'),0) as repayments,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='reversal'),0) as reversals
  from public.debt_entries where owner_id=v_user and created_at<v_end
 ), purchases as (
  select count(*) as count,coalesce(sum(total),0) as total from public.purchases where owner_id=v_user and created_at>=v_start and created_at<v_end
 )
 select jsonb_build_object('day',p_day,'timezone','Asia/Baghdad','currency','IQD','generated_at',statement_timestamp(),
  'sales',jsonb_build_object('count',s.count::text,'cash_count',s.cash_count::text,'credit_count',s.credit_count::text,'subtotal',s.subtotal::text,'discounts',s.discounts::text,'total',s.total::text,'cash_total',s.cash_total::text,'credit_total',s.credit_total::text,'cash_received',s.cash_received::text,'debt_added',s.debt_added::text),
  'returns',jsonb_build_object('count',r.count::text,'total',r.total::text,'cash_refund',r.cash_refund::text,'debt_reversed',r.debt_reversed::text),
  'cash',jsonb_build_object('count',c.count::text,'opening',c.opening::text,'inflows',c.inflows::text,'outflows',c.outflows::text,'closing',(c.opening+c.inflows-c.outflows)::text,'sales',c.sales::text,'refunds',c.refunds::text,'repayments',c.repayments::text,'deposits',c.deposits::text,'withdrawals',c.withdrawals::text,'expenses',c.expenses::text),
  'debt',jsonb_build_object('count',d.count::text,'opening',d.opening::text,'manual_charges',d.manual_charges::text,'sale_charges',d.sale_charges::text,'repayments',d.repayments::text,'reversals',d.reversals::text,'closing',(d.opening+d.manual_charges+d.sale_charges-d.repayments-d.reversals)::text),
  'purchases',jsonb_build_object('count',p.count::text,'total',p.total::text)
 ) into v_result from sales s cross join returns r cross join cash c cross join debt d cross join purchases p;
 return v_result;
end $$;

notify pgrst,'reload schema';