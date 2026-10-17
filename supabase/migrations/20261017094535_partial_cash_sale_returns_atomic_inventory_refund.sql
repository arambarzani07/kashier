create table public.sale_returns (
 id uuid primary key,
 return_no bigint generated always as identity unique,
 owner_id uuid not null references auth.users(id),
 sale_id uuid not null references public.sales(id),
 created_at timestamptz not null default now(),
 reason text not null check(char_length(btrim(reason)) between 1 and 500),
 currency text not null default 'IQD' check(currency='IQD'),
 total bigint not null check(total between 0 and 100000000000000),
 cash_refund bigint not null check(cash_refund between 0 and 100000000000000),
 debt_reversed bigint not null default 0 check(debt_reversed between 0 and 100000000000000),
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 200),
 request_payload jsonb not null,
 check(total=cash_refund+debt_reversed)
);
create index sale_returns_owner_created_idx on public.sale_returns(owner_id,created_at desc,id);
create index sale_returns_sale_created_idx on public.sale_returns(sale_id,created_at,id);
alter table public.sale_returns enable row level security;
revoke all on public.sale_returns from anon,authenticated;
revoke all on sequence public.sale_returns_return_no_seq from anon,authenticated;
grant select on public.sale_returns to authenticated;
create policy sale_returns_read_own on public.sale_returns for select to authenticated using ((select auth.uid())=owner_id);

alter table public.stock_movements add column return_id uuid references public.sale_returns(id);
alter table public.stock_movements drop constraint stock_movements_source_check;
alter table public.stock_movements add constraint stock_movements_source_check check(
 (purchase_id is not null and sale_id is null and reversal_id is null and return_id is null and delta_units>0)
 or (purchase_id is null and sale_id is not null and reversal_id is null and return_id is null and delta_units<0)
 or (purchase_id is null and sale_id is null and reversal_id is not null and return_id is null and delta_units>0)
 or (purchase_id is null and sale_id is null and reversal_id is null and return_id is not null and delta_units>0)
);
alter table public.stock_movements add constraint stock_movements_return_line_key unique(return_id,line_no);
create index stock_movements_return_idx on public.stock_movements(return_id) where return_id is not null;

alter table public.cash_movements add column return_id uuid unique references public.sale_returns(id);
alter table public.cash_movements drop constraint cash_movements_source_check;
alter table public.cash_movements add constraint cash_movements_source_check check(
 (kind='sale' and sale_id is not null and customer_id is null and reversal_id is null and return_id is null)
 or (kind='repayment' and sale_id is null and customer_id is not null and reversal_id is null and return_id is null and amount>0 and char_length(btrim(note))>0)
 or (kind='refund' and sale_id is null and customer_id is null and ((reversal_id is not null and return_id is null) or (reversal_id is null and return_id is not null)) and amount>0 and char_length(btrim(note))>0)
 or (kind in ('deposit','withdrawal','expense') and sale_id is null and customer_id is null and reversal_id is null and return_id is null and amount>0 and char_length(btrim(note))>0)
);

create function private.guard_sale_adjustment_conflict()
returns trigger language plpgsql set search_path='' as $$
begin
 if tg_table_name='sale_reversals' then
  if exists(select 1 from public.sale_returns where sale_id=new.sale_id) then
   raise exception 'reversal_partial_returns_exist';
  end if;
 elsif tg_table_name='sale_returns' then
  if exists(select 1 from public.sale_reversals where sale_id=new.sale_id) then
   raise exception 'return_sale_reversed';
  end if;
 end if;
 return new;
end $$;
revoke all on function private.guard_sale_adjustment_conflict() from public,anon,authenticated;
create trigger sale_reversal_no_partial_returns before insert on public.sale_reversals for each row execute function private.guard_sale_adjustment_conflict();
create trigger sale_return_no_full_reversal before insert on public.sale_returns for each row execute function private.guard_sale_adjustment_conflict();

create function private.post_sale_return(p_id uuid,p_sale uuid,p_reason text,p_lines jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_payload jsonb;
 v_return public.sale_returns%rowtype;
 v_sale public.sales%rowtype;
 v_request jsonb;
 v_original jsonb;
 v_return_lines jsonb:='[]'::jsonb;
 v_seen integer[]:='{}';
 v_line_no integer;
 v_qty bigint;
 v_prev_qty bigint;
 v_original_qty bigint;
 v_price bigint;
 v_line_refund bigint;
 v_total bigint:=0;
 v_product uuid;
 v_stock record;
 v_after bigint;
 v_cash_after bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='return_auth_required'; end if;
 if p_id is null or p_sale is null or p_lines is null or jsonb_typeof(p_lines)<>'array' then raise exception 'return_invalid_request'; end if;
 if jsonb_array_length(p_lines) not between 1 and 200 then raise exception 'return_invalid_items'; end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'return_reason_required'; end if;
 v_payload:=jsonb_build_object('sale_id',p_sale,'reason',btrim(p_reason),'lines',p_lines);
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale-return.'||p_id::text,0));
 select * into v_return from public.sale_returns where id=p_id;
 if found then
  if v_return.owner_id<>v_user or v_return.request_payload<>v_payload then raise exception 'return_request_conflict'; end if;
  return to_jsonb(v_return)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale-adjustment.'||p_sale::text,0));
 select * into v_sale from public.sales where id=p_sale and owner_id=v_user for share;
 if not found then raise exception 'return_sale_unavailable'; end if;
 if exists(select 1 from public.sale_reversals where sale_id=p_sale) then raise exception 'return_sale_reversed'; end if;
 if v_sale.payment_mode<>'cash' then raise exception 'return_credit_not_supported'; end if;
 if v_sale.discount<>0 then raise exception 'return_discount_not_supported'; end if;

 for v_request in select value from jsonb_array_elements(p_lines) loop
  if jsonb_typeof(v_request)<>'object' or coalesce(v_request->>'line_no','') !~ '^[0-9]{1,3}$' or coalesce(v_request->>'quantity_units','') !~ '^[0-9]{1,8}$' then raise exception 'return_invalid_items'; end if;
  v_line_no:=(v_request->>'line_no')::integer;
  v_qty:=(v_request->>'quantity_units')::bigint;
  if v_line_no not between 1 and jsonb_array_length(v_sale.lines) or v_qty not between 1 and 10000000 then raise exception 'return_invalid_items'; end if;
  if v_line_no=any(v_seen) then raise exception 'return_duplicate_line'; end if;
  v_seen:=array_append(v_seen,v_line_no);
  v_original:=v_sale.lines->(v_line_no-1);
  v_original_qty:=(v_original->>'quantity_units')::bigint;
  v_price:=(v_original->>'unit_price')::bigint;
  v_product:=(v_original->>'product_id')::uuid;
  select coalesce(sum((rl->>'quantity_units')::bigint),0) into v_prev_qty
   from public.sale_returns sr cross join lateral jsonb_array_elements(sr.lines) rl
   where sr.sale_id=p_sale and sr.owner_id=v_user and (rl->>'line_no')::integer=v_line_no;
  if v_prev_qty+v_qty>v_original_qty then raise exception 'return_quantity_exceeds_remaining'; end if;
  v_line_refund:=(((v_prev_qty+v_qty)*v_price+500)/1000)-((v_prev_qty*v_price+500)/1000);
  if v_line_refund<0 then raise exception 'return_invalid_money'; end if;
  v_total:=v_total+v_line_refund;
  if v_total>100000000000000 then raise exception 'return_total_limit'; end if;
  v_return_lines:=v_return_lines||jsonb_build_array(jsonb_build_object(
   'line_no',v_line_no,'product_id',v_product,'name',v_original->>'name','barcode',v_original->'barcode',
   'quantity_units',v_qty,'original_quantity_units',v_original_qty,'unit_price',v_price,'line_total',v_line_refund));
 end loop;

 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 for v_stock in
  select (x->>'product_id')::uuid as product_id,sum((x->>'quantity_units')::bigint) as returned
  from jsonb_array_elements(v_return_lines) x group by (x->>'product_id')::uuid
 loop
  select quantity_units into v_after from public.product_stock where product_id=v_stock.product_id and owner_id=v_user for update;
  if not found then raise exception 'return_stock_unavailable'; end if;
  if v_after>1000000000000-v_stock.returned then raise exception 'return_stock_limit'; end if;
 end loop;

 if v_total>0 then
  perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
  select balance-v_total into v_cash_after from public.cash_accounts where owner_id=v_user for update;
  if not found or v_cash_after<0 then raise exception 'return_cash_insufficient'; end if;
 end if;

 insert into public.sale_returns(id,owner_id,sale_id,reason,total,cash_refund,debt_reversed,lines,request_payload)
 values(p_id,v_user,p_sale,btrim(p_reason),v_total,v_total,0,v_return_lines,v_payload)
 returning * into v_return;

 for v_original in select value from jsonb_array_elements(v_return_lines) loop
  v_qty:=(v_original->>'quantity_units')::bigint;
  v_line_no:=(v_original->>'line_no')::integer;
  update public.product_stock set quantity_units=quantity_units+v_qty,updated_at=now()
   where product_id=(v_original->>'product_id')::uuid and owner_id=v_user returning quantity_units into v_after;
  if not found then raise exception 'return_stock_unavailable'; end if;
  insert into public.stock_movements(owner_id,product_id,return_id,line_no,delta_units,balance_after)
   values(v_user,(v_original->>'product_id')::uuid,p_id,v_line_no,v_qty,v_after);
 end loop;

 if v_total>0 then
  update public.cash_accounts set balance=v_cash_after,updated_at=now() where owner_id=v_user;
  insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,sale_id,note,request_payload,customer_id,reversal_id,return_id)
   values(v_user,'refund',v_total,-v_total,v_cash_after,null,btrim(p_reason),jsonb_build_object('return_id',p_id,'sale_id',p_sale),null,null,p_id);
 end if;
 return to_jsonb(v_return)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_sale_return(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function private.post_sale_return(uuid,uuid,text,jsonb) to authenticated;

create function public.post_sale_return(p_id uuid,p_sale uuid,p_reason text,p_lines jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.post_sale_return(p_id,p_sale,p_reason,p_lines);
$$;
revoke all on function public.post_sale_return(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.post_sale_return(uuid,uuid,text,jsonb) to authenticated;

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
