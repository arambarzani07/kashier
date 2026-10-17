create table public.suppliers (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id),
 name text not null check(char_length(btrim(name)) between 1 and 100 and name=btrim(name)),
 phone text check(phone is null or (char_length(phone) between 1 and 35 and phone=btrim(phone))),
 created_at timestamptz not null default now()
);
create index suppliers_owner_created_idx on public.suppliers(owner_id,created_at desc,id);
alter table public.suppliers enable row level security;
revoke all on public.suppliers from anon,authenticated;
grant select on public.suppliers to authenticated;
grant insert(id,name,phone) on public.suppliers to authenticated;
grant update(name,phone) on public.suppliers to authenticated;
create policy suppliers_read_own on public.suppliers for select to authenticated using ((select auth.uid())=owner_id);
create policy suppliers_insert_own on public.suppliers for insert to authenticated with check ((select auth.uid())=owner_id);
create policy suppliers_update_own on public.suppliers for update to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);

create table public.supplier_balances (
 supplier_id uuid primary key references public.suppliers(id),
 owner_id uuid not null references auth.users(id),
 balance bigint not null default 0 check(balance between 0 and 100000000000000),
 updated_at timestamptz not null default now()
);
create index supplier_balances_owner_idx on public.supplier_balances(owner_id);
alter table public.supplier_balances enable row level security;
revoke all on public.supplier_balances from anon,authenticated;
grant select on public.supplier_balances to authenticated;
create policy supplier_balances_read_own on public.supplier_balances for select to authenticated using ((select auth.uid())=owner_id);

create table public.supplier_entries (
 id uuid primary key,
 movement_no bigint generated always as identity unique,
 owner_id uuid not null references auth.users(id),
 supplier_id uuid not null references public.suppliers(id),
 supplier_name text not null,
 created_at timestamptz not null default now(),
 kind text not null check(kind in ('charge','payment')),
 amount bigint not null check(amount between 1 and 100000000000000),
 delta bigint not null,
 balance_after bigint not null check(balance_after between 0 and 100000000000000),
 note text not null check(char_length(btrim(note)) between 1 and 500),
 purchase_id uuid unique references public.purchases(id),
 cash_movement_id uuid unique references public.cash_movements(id),
 request_payload jsonb not null,
 check(delta=case when kind='charge' then amount else -amount end),
 check((kind='charge' and cash_movement_id is null) or (kind='payment' and cash_movement_id is not null and purchase_id is null))
);
create index supplier_entries_owner_order_idx on public.supplier_entries(owner_id,movement_no desc);
create index supplier_entries_supplier_order_idx on public.supplier_entries(supplier_id,movement_no desc);
alter table public.supplier_entries enable row level security;
revoke all on public.supplier_entries from anon,authenticated;
revoke all on sequence public.supplier_entries_movement_no_seq from anon,authenticated;
grant select on public.supplier_entries to authenticated;
create policy supplier_entries_read_own on public.supplier_entries for select to authenticated using((select auth.uid())=owner_id);
create view public.supplier_debt_catalog with(security_invoker=true) as
 select s.id,s.name,s.phone,s.created_at,coalesce(b.balance,0)::bigint balance from public.suppliers s left join public.supplier_balances b on b.supplier_id=s.id and b.owner_id=s.owner_id where s.owner_id=(select auth.uid());
revoke all on public.supplier_debt_catalog from anon,authenticated;
grant select on public.supplier_debt_catalog to authenticated;
alter table public.purchases add column accounting_mode text not null default 'untracked',
 add column supplier_id uuid references public.suppliers(id),
 add column amount_paid bigint not null default 0,
 add column debt_amount bigint not null default 0,
 add column finance_payload jsonb,
 add constraint purchases_finance_source check((accounting_mode='untracked' and supplier_id is null and amount_paid=0 and debt_amount=0 and finance_payload is null) or (accounting_mode='tracked' and supplier_id is not null and amount_paid>=0 and debt_amount>=0 and amount_paid+debt_amount=total and finance_payload is not null));
create index purchases_supplier_idx on public.purchases(supplier_id) where supplier_id is not null;
alter table public.cash_movements add column supplier_id uuid references public.suppliers(id),add column purchase_id uuid unique references public.purchases(id);
create index cash_movements_supplier_idx on public.cash_movements(supplier_id) where supplier_id is not null;
alter table public.cash_movements drop constraint cash_movements_kind_check,drop constraint cash_movements_source_check;
alter table public.cash_movements add constraint cash_movements_kind_check check(kind in ('sale','deposit','withdrawal','expense','repayment','refund','supplier_purchase','supplier_payment'));
alter table public.cash_movements add constraint cash_movements_source_check check(
 ((
 (kind='sale' and sale_id is not null and customer_id is null and reversal_id is null and return_id is null)
 or (kind='repayment' and sale_id is null and customer_id is not null and reversal_id is null and return_id is null and amount>0 and char_length(btrim(note))>0)
 or (kind='refund' and sale_id is null and customer_id is null and ((reversal_id is not null and return_id is null) or (reversal_id is null and return_id is not null)) and amount>0 and char_length(btrim(note))>0)
 or (kind in ('deposit','withdrawal','expense') and sale_id is null and customer_id is null and reversal_id is null and return_id is null and amount>0 and char_length(btrim(note))>0)) and supplier_id is null and purchase_id is null)
 or (kind in ('supplier_purchase','supplier_payment') and supplier_id is not null and sale_id is null and customer_id is null and reversal_id is null and return_id is null and amount>0 and ((kind='supplier_purchase' and purchase_id is not null) or (kind='supplier_payment' and purchase_id is null and char_length(btrim(note))>0)))
);
create function private.post_supplier_entry(p_id uuid,p_supplier uuid,p_kind text,p_amount bigint,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_supplier public.suppliers%rowtype;v_entry public.supplier_entries%rowtype;v_payload jsonb;v_after bigint;v_cash bigint;v_cash_id uuid;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
 if p_id is null or p_supplier is null or p_kind is null or p_kind not in ('charge','payment') then raise exception 'supplier_invalid_kind';end if;
 if p_amount is null or p_amount not between 1 and 100000000000000 then raise exception 'supplier_invalid_amount';end if;
 if char_length(btrim(coalesce(p_note,''))) not between 1 and 500 then raise exception 'supplier_note_required';end if;
 v_payload:=jsonb_build_object('supplier',p_supplier,'kind',p_kind,'amount',p_amount,'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended('kashier.supplier-entry.'||p_id::text,0));
 select * into v_entry from public.supplier_entries where id=p_id;
 if found then
  if v_entry.owner_id<>v_user or v_entry.request_payload<>v_payload then raise exception 'supplier_request_conflict';end if;
  return to_jsonb(v_entry)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.supplier.'||v_user::text,0));
 select * into v_supplier from public.suppliers where id=p_supplier and owner_id=v_user for share;
 if not found then raise exception 'supplier_unavailable';end if;
 insert into public.supplier_balances(supplier_id,owner_id,balance) values(p_supplier,v_user,0) on conflict(supplier_id) do nothing;
 select balance+case when p_kind='charge' then p_amount else -p_amount end into v_after from public.supplier_balances where supplier_id=p_supplier and owner_id=v_user for update;
 if v_after<0 then raise exception 'supplier_overpayment';end if;
 if v_after>100000000000000 then raise exception 'supplier_balance_limit';end if;
 if p_kind='payment' then
  perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
  select balance into v_cash from public.cash_accounts where owner_id=v_user for update;
  if not found or v_cash<p_amount then raise exception 'cash_insufficient_balance';end if;
  v_cash:=v_cash-p_amount;update public.cash_accounts set balance=v_cash,updated_at=now() where owner_id=v_user;
  insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,supplier_id,note,request_payload)
   values(v_user,'supplier_payment',p_amount,-p_amount,v_cash,p_supplier,btrim(p_note),jsonb_build_object('supplier_entry',p_id)) returning id into v_cash_id;
 end if;
 update public.supplier_balances set balance=v_after,updated_at=now() where supplier_id=p_supplier and owner_id=v_user;
 insert into public.supplier_entries(id,owner_id,supplier_id,supplier_name,kind,amount,delta,balance_after,note,cash_movement_id,request_payload)
 values(p_id,v_user,p_supplier,v_supplier.name,p_kind,p_amount,case when p_kind='charge' then p_amount else -p_amount end,v_after,btrim(p_note),v_cash_id,v_payload) returning * into v_entry;
 return to_jsonb(v_entry)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_supplier_entry(uuid,uuid,text,bigint,text) from public,anon,authenticated;
grant execute on function private.post_supplier_entry(uuid,uuid,text,bigint,text) to authenticated;
create function public.post_supplier_entry(p_id uuid,p_supplier uuid,p_kind text,p_amount bigint,p_note text)
returns jsonb language sql security invoker set search_path='' as $$ select private.post_supplier_entry(p_id,p_supplier,p_kind,p_amount,p_note); $$;
revoke all on function public.post_supplier_entry(uuid,uuid,text,bigint,text) from public,anon,authenticated;
grant execute on function public.post_supplier_entry(uuid,uuid,text,bigint,text) to authenticated;

create function private.post_supplier_purchase(p_id uuid,p_items jsonb,p_supplier uuid,p_paid bigint,p_invoice text,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_supplier public.suppliers%rowtype;v_receipt public.purchases%rowtype;v_payload jsonb;v_debt bigint;v_after bigint;v_cash bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
 if p_id is null or p_supplier is null or p_paid is null or p_paid not between 0 and 100000000000000 then raise exception 'supplier_invalid_amount';end if;
 v_payload:=jsonb_build_object('items',p_items,'supplier',p_supplier,'paid',p_paid,'invoice',btrim(coalesce(p_invoice,'')),'note',btrim(coalesce(p_note,'')));
 perform pg_advisory_xact_lock(hashtextextended('kashier.purchase.'||p_id::text,0));
 select * into v_receipt from public.purchases where id=p_id;
 if found then
  if v_receipt.owner_id<>v_user or v_receipt.finance_payload is distinct from v_payload then raise exception 'purchase_request_conflict';end if;
  return to_jsonb(v_receipt)-'owner_id'-'request_payload'-'finance_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 perform pg_advisory_xact_lock(hashtextextended('kashier.supplier.'||v_user::text,0));
 select * into v_supplier from public.suppliers where id=p_supplier and owner_id=v_user for share;
 if not found then raise exception 'supplier_unavailable';end if;
 -- Reuse the validated atomic stock receipt implementation under the same locks.
 perform private.post_purchase(p_id,p_items,v_supplier.name,p_invoice,p_note);
 select * into v_receipt from public.purchases where id=p_id and owner_id=v_user;
 if p_paid>v_receipt.total then raise exception 'supplier_purchase_overpaid';end if;
 v_debt:=v_receipt.total-p_paid;
 if v_debt>0 then
  insert into public.supplier_balances(supplier_id,owner_id,balance) values(p_supplier,v_user,0) on conflict(supplier_id) do nothing;
  select balance+v_debt into v_after from public.supplier_balances where supplier_id=p_supplier and owner_id=v_user for update;
  if v_after>100000000000000 then raise exception 'supplier_balance_limit';end if;
  update public.supplier_balances set balance=v_after,updated_at=now() where supplier_id=p_supplier and owner_id=v_user;
  insert into public.supplier_entries(id,owner_id,supplier_id,supplier_name,kind,amount,delta,balance_after,note,purchase_id,request_payload)
  values(gen_random_uuid(),v_user,p_supplier,v_supplier.name,'charge',v_debt,v_debt,v_after,coalesce(nullif(btrim(p_note),''),'قەرزی کڕینی کاڵا'),p_id,jsonb_build_object('purchase_id',p_id));
 end if;
 if p_paid>0 then
  perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
  select balance into v_cash from public.cash_accounts where owner_id=v_user for update;
  if not found or v_cash<p_paid then raise exception 'cash_insufficient_balance';end if;
  v_cash:=v_cash-p_paid;update public.cash_accounts set balance=v_cash,updated_at=now() where owner_id=v_user;
  insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,supplier_id,purchase_id,note,request_payload)
  values(v_user,'supplier_purchase',p_paid,-p_paid,v_cash,p_supplier,p_id,btrim(coalesce(p_note,'')),jsonb_build_object('purchase_id',p_id));
 end if;
 update public.purchases set accounting_mode='tracked',supplier_id=p_supplier,amount_paid=p_paid,debt_amount=v_debt,finance_payload=v_payload where id=p_id returning * into v_receipt;
 return to_jsonb(v_receipt)-'owner_id'-'request_payload'-'finance_payload';
end $$;
revoke all on function private.post_supplier_purchase(uuid,jsonb,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function private.post_supplier_purchase(uuid,jsonb,uuid,bigint,text,text) to authenticated;
create function public.post_supplier_purchase(p_id uuid,p_items jsonb,p_supplier uuid,p_paid bigint,p_invoice text,p_note text)
returns jsonb language sql security invoker set search_path='' as $$ select private.post_supplier_purchase(p_id,p_items,p_supplier,p_paid,p_invoice,p_note); $$;
revoke all on function public.post_supplier_purchase(uuid,jsonb,uuid,bigint,text,text) from public,anon,authenticated;
grant execute on function public.post_supplier_purchase(uuid,jsonb,uuid,bigint,text,text) to authenticated;
create function public.get_supplier_summary()
returns jsonb language sql stable security invoker set search_path='' as $$ select jsonb_build_object('balance',coalesce(sum(balance),0)::text,'debtors',count(*) filter(where balance>0)::text) from public.supplier_balances where owner_id=(select auth.uid()); $$;
revoke all on function public.get_supplier_summary() from public,anon,authenticated;
grant execute on function public.get_supplier_summary() to authenticated;

-- One read snapshot; security invoker keeps all existing owner policies in force.
create function public.get_supplier_statement(p_supplier uuid,p_from date default null,p_to date default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_supplier public.suppliers%rowtype;v_from timestamptz;v_to timestamptz;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required'; end if;
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'statement_invalid_dates'; end if;
 select * into v_supplier from public.suppliers where id=p_supplier and owner_id=v_user;
 if not found then raise exception 'supplier_unavailable'; end if;
 v_from:=p_from::timestamp at time zone 'Asia/Baghdad';
 v_to:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 with ledger as materialized (
  select id,movement_no,created_at,kind,amount,delta,note,purchase_id,cash_movement_id from public.supplier_entries where supplier_id=p_supplier and owner_id=v_user
 ), opening as (
  select coalesce(sum(delta) filter(where v_from is not null and created_at<v_from),0) as amount from ledger
 ), period as materialized (
  select * from ledger where (v_from is null or created_at>=v_from) and (v_to is null or created_at<v_to)
 ), totals as (
  select count(*) as count,coalesce(sum(amount) filter(where kind='charge'),0) as charges,coalesce(sum(amount) filter(where kind='payment'),0) as repayments from period
 ), ordered as (
  select *, (select amount from opening)+sum(delta) over(order by movement_no rows unbounded preceding) as statement_balance from period order by movement_no limit 5001
 )
 select jsonb_build_object(
  'supplier',jsonb_build_object('id',v_supplier.id,'name',v_supplier.name,'phone',v_supplier.phone),
  'from',p_from,'to',p_to,'timezone','Asia/Baghdad','generated_at',statement_timestamp(),'currency','IQD',
  'opening',o.amount::text,'charges',t.charges::text,'payments',t.repayments::text,'reversals','0','closing',(o.amount+t.charges-t.repayments)::text,'count',t.count,
  'rows',coalesce((select jsonb_agg(jsonb_build_object('id',id,'movement_no',movement_no::text,'created_at',created_at,'kind',kind,'amount',amount::text,'delta',delta::text,'balance',statement_balance::text,'note',note,'purchase_id',purchase_id,'cash_movement_id',cash_movement_id) order by movement_no) from ordered),'[]'::jsonb)
 ) into v_result from opening o cross join totals t;
 if (v_result->>'count')::bigint>5000 then raise exception 'statement_too_many_rows'; end if;
 return v_result;
end $$;
revoke all on function public.get_supplier_statement(uuid,date,date) from public,anon,authenticated;
grant execute on function public.get_supplier_statement(uuid,date,date) to authenticated;

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
 'supplier_purchases',coalesce(sum(amount) filter(where kind='supplier_purchase'),0)::text,
 'supplier_payments',coalesce(sum(amount) filter(where kind='supplier_payment'),0)::text,
 'count',count(*)::text
 ) from public.cash_movements where owner_id=(select auth.uid());
$$;


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
 ), return_rows as (
  select total,cash_refund,debt_reversed from public.sale_reversals where owner_id=v_user and created_at>=v_start and created_at<v_end
  union all
  select total,cash_refund,debt_reversed from public.sale_returns where owner_id=v_user and created_at>=v_start and created_at<v_end
 ), returns as (
  select count(*) as count,coalesce(sum(total),0) as total,coalesce(sum(cash_refund),0) as cash_refund,coalesce(sum(debt_reversed),0) as debt_reversed from return_rows
 ), cash as (
  select count(*) filter(where created_at>=v_start) as count,
   coalesce(sum(delta) filter(where created_at<v_start),0) as opening,
   coalesce(sum(delta) filter(where created_at>=v_start and delta>=0),0) as inflows,
   coalesce(-sum(delta) filter(where created_at>=v_start and delta<0),0) as outflows,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='sale'),0) as sales,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='refund'),0) as refunds,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='supplier_purchase'),0) as supplier_purchases,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='supplier_payment'),0) as supplier_payments,
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
  select count(*) as count,coalesce(sum(total),0) as total,coalesce(sum(amount_paid),0) as paid,coalesce(sum(debt_amount),0) as debt_added,count(*) filter(where accounting_mode='untracked') as untracked_count from public.purchases where owner_id=v_user and created_at>=v_start and created_at<v_end
 )
 select jsonb_build_object('day',p_day,'timezone','Asia/Baghdad','currency','IQD','generated_at',statement_timestamp(),
  'sales',jsonb_build_object('count',s.count::text,'cash_count',s.cash_count::text,'credit_count',s.credit_count::text,'subtotal',s.subtotal::text,'discounts',s.discounts::text,'total',s.total::text,'cash_total',s.cash_total::text,'credit_total',s.credit_total::text,'cash_received',s.cash_received::text,'debt_added',s.debt_added::text),
  'returns',jsonb_build_object('count',r.count::text,'total',r.total::text,'cash_refund',r.cash_refund::text,'debt_reversed',r.debt_reversed::text),
  'cash',jsonb_build_object('count',c.count::text,'opening',c.opening::text,'inflows',c.inflows::text,'outflows',c.outflows::text,'closing',(c.opening+c.inflows-c.outflows)::text,'sales',c.sales::text,'refunds',c.refunds::text,'supplier_purchases',c.supplier_purchases::text,'supplier_payments',c.supplier_payments::text,'repayments',c.repayments::text,'deposits',c.deposits::text,'withdrawals',c.withdrawals::text,'expenses',c.expenses::text),
  'debt',jsonb_build_object('count',d.count::text,'opening',d.opening::text,'manual_charges',d.manual_charges::text,'sale_charges',d.sale_charges::text,'repayments',d.repayments::text,'reversals',d.reversals::text,'closing',(d.opening+d.manual_charges+d.sale_charges-d.repayments-d.reversals)::text),
  'purchases',jsonb_build_object('count',p.count::text,'total',p.total::text,'paid',p.paid::text,'debt_added',p.debt_added::text,'untracked_count',p.untracked_count::text)
 ) into v_result from sales s cross join returns r cross join cash c cross join debt d cross join purchases p;
 return v_result;
end $$;


notify pgrst,'reload schema';
