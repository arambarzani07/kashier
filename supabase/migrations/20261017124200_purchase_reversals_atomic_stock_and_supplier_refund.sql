create table public.purchase_reversals (
 id uuid primary key,
 reversal_no bigint generated always as identity unique,
 owner_id uuid not null references auth.users(id),
 purchase_id uuid not null unique references public.purchases(id),
 supplier_id uuid references public.suppliers(id),
 supplier_name text not null default '' check(char_length(supplier_name)<=100),
 created_at timestamptz not null default now(),
 reason text not null check(char_length(btrim(reason)) between 1 and 500 and reason=btrim(reason)),
 accounting_mode text not null check(accounting_mode in ('tracked','untracked')),
 currency text not null default 'IQD' check(currency='IQD'),
 total bigint not null check(total between 0 and 100000000000000),
 cash_refund bigint not null check(cash_refund between 0 and 100000000000000),
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 200),
 request_payload jsonb not null,
 check((accounting_mode='tracked' and supplier_id is not null and cash_refund=total) or (accounting_mode='untracked' and supplier_id is null and cash_refund=0))
);
create index purchase_reversals_owner_created_idx on public.purchase_reversals(owner_id,created_at desc,id);
alter table public.purchase_reversals enable row level security;
revoke all on public.purchase_reversals from anon,authenticated;
revoke all on sequence public.purchase_reversals_reversal_no_seq from anon,authenticated;
grant select on public.purchase_reversals to authenticated;
create policy purchase_reversals_read_own on public.purchase_reversals for select to authenticated using((select auth.uid())=owner_id);

alter table public.stock_movements add column purchase_reversal_id uuid references public.purchase_reversals(id);
create unique index stock_movements_purchase_reversal_line_key on public.stock_movements(purchase_reversal_id,line_no) where purchase_reversal_id is not null;
alter table public.stock_movements drop constraint stock_movements_source_check;
alter table public.stock_movements add constraint stock_movements_source_check check(
 (adjustment_id is null and purchase_reversal_id is null and purchase_id is not null and sale_id is null and reversal_id is null and return_id is null and delta_units>0)
 or (adjustment_id is null and purchase_reversal_id is null and purchase_id is null and sale_id is not null and reversal_id is null and return_id is null and delta_units<0)
 or (adjustment_id is null and purchase_reversal_id is null and purchase_id is null and sale_id is null and reversal_id is not null and return_id is null and delta_units>0)
 or (adjustment_id is null and purchase_reversal_id is null and purchase_id is null and sale_id is null and reversal_id is null and return_id is not null and delta_units>0)
 or (adjustment_id is not null and purchase_reversal_id is null and purchase_id is null and sale_id is null and reversal_id is null and return_id is null and line_no=1)
 or (adjustment_id is null and purchase_reversal_id is not null and purchase_id is null and sale_id is null and reversal_id is null and return_id is null and delta_units<0)
);

alter table public.cash_movements add column purchase_reversal_id uuid unique references public.purchase_reversals(id);
alter table public.cash_movements drop constraint cash_movements_kind_check,drop constraint cash_movements_direction_check,drop constraint cash_movements_source_check;
alter table public.cash_movements add constraint cash_movements_kind_check check(kind in ('sale','deposit','withdrawal','expense','repayment','refund','supplier_purchase','supplier_payment','supplier_refund'));
alter table public.cash_movements add constraint cash_movements_direction_check check(delta=case when kind in ('sale','deposit','repayment','supplier_refund') then amount else -amount end);
alter table public.cash_movements add constraint cash_movements_source_check check(
 (((kind='sale' and sale_id is not null and customer_id is null and reversal_id is null and return_id is null)
 or (kind='repayment' and sale_id is null and customer_id is not null and reversal_id is null and return_id is null and amount>0 and char_length(btrim(note))>0)
 or (kind='refund' and sale_id is null and customer_id is null and ((reversal_id is not null and return_id is null) or (reversal_id is null and return_id is not null)) and amount>0 and char_length(btrim(note))>0)
 or (kind in ('deposit','withdrawal','expense') and sale_id is null and customer_id is null and reversal_id is null and return_id is null and amount>0 and char_length(btrim(note))>0))
 and supplier_id is null and purchase_id is null and purchase_reversal_id is null)
 or (kind in ('supplier_purchase','supplier_payment') and supplier_id is not null and purchase_reversal_id is null and sale_id is null and customer_id is null and reversal_id is null and return_id is null and amount>0 and ((kind='supplier_purchase' and purchase_id is not null) or (kind='supplier_payment' and purchase_id is null and char_length(btrim(note))>0)))
 or (kind='supplier_refund' and supplier_id is not null and purchase_id is null and purchase_reversal_id is not null and sale_id is null and customer_id is null and reversal_id is null and return_id is null and amount>0 and char_length(btrim(note))>0)
);

create function private.post_purchase_reversal(p_id uuid,p_purchase uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_purchase public.purchases%rowtype;
 v_existing public.purchase_reversals%rowtype;
 v_result public.purchase_reversals%rowtype;
 v_payload jsonb;
 v_reason text:=btrim(coalesce(p_reason,''));
 v_cash_refund bigint;
 v_cash bigint;
 v_line jsonb;
 v_stock record;
 v_after bigint;
 v_index integer:=0;
begin
 if v_user is null then raise exception using errcode='28000',message='purchase_reversal_auth_required';end if;
 if p_id is null or p_purchase is null then raise exception 'purchase_reversal_invalid_request';end if;
 if char_length(v_reason) not between 1 and 500 then raise exception 'purchase_reversal_reason_required';end if;
 v_payload:=jsonb_build_object('purchase',p_purchase,'reason',v_reason);
 perform pg_advisory_xact_lock(hashtextextended('kashier.purchase-reversal.'||p_id::text,0));
 select * into v_existing from public.purchase_reversals where id=p_id;
 if found then
  if v_existing.owner_id<>v_user or v_existing.request_payload<>v_payload then raise exception 'purchase_reversal_request_conflict';end if;
  return to_jsonb(v_existing)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 select * into v_purchase from public.purchases where id=p_purchase and owner_id=v_user for share;
 if not found then raise exception 'purchase_reversal_unavailable';end if;
 select * into v_existing from public.purchase_reversals where purchase_id=p_purchase;
 if found then raise exception 'purchase_reversal_already_exists';end if;
 if v_purchase.accounting_mode='tracked' then
  if v_purchase.debt_amount<>0 then raise exception 'purchase_reversal_credit_unsupported';end if;
  if v_purchase.supplier_id is null or v_purchase.amount_paid<>v_purchase.total then raise exception 'purchase_reversal_state_invalid';end if;
  v_cash_refund:=v_purchase.total;
 elsif v_purchase.accounting_mode='untracked' then
  if v_purchase.supplier_id is not null or v_purchase.amount_paid<>0 or v_purchase.debt_amount<>0 then raise exception 'purchase_reversal_state_invalid';end if;
  v_cash_refund:=0;
 else
  raise exception 'purchase_reversal_state_invalid';
 end if;
 for v_stock in
  select (x->>'product_id')::uuid product_id,sum((x->>'quantity_units')::bigint) required
  from jsonb_array_elements(v_purchase.lines) x group by (x->>'product_id')::uuid order by (x->>'product_id')::uuid
 loop
  select quantity_units into v_after from public.product_stock where product_id=v_stock.product_id and owner_id=v_user for update;
  if not found or v_after<v_stock.required then raise exception 'purchase_reversal_stock_insufficient';end if;
 end loop;
 if v_cash_refund>0 then
  perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
  insert into public.cash_accounts(owner_id,balance) values(v_user,0) on conflict(owner_id) do nothing;
  select balance into v_cash from public.cash_accounts where owner_id=v_user for update;
  if v_cash>100000000000000-v_cash_refund then raise exception 'purchase_reversal_cash_limit';end if;
 end if;
 insert into public.purchase_reversals(id,owner_id,purchase_id,supplier_id,supplier_name,reason,accounting_mode,total,cash_refund,lines,request_payload)
 values(p_id,v_user,v_purchase.id,v_purchase.supplier_id,v_purchase.supplier_name,v_reason,v_purchase.accounting_mode,v_purchase.total,v_cash_refund,v_purchase.lines,v_payload)
 returning * into v_result;
 for v_line in select value from jsonb_array_elements(v_purchase.lines) loop
  v_index:=v_index+1;
  update public.product_stock set quantity_units=quantity_units-(v_line->>'quantity_units')::bigint,updated_at=now()
   where product_id=(v_line->>'product_id')::uuid and owner_id=v_user and quantity_units>=(v_line->>'quantity_units')::bigint returning quantity_units into v_after;
  if not found then raise exception 'purchase_reversal_stock_insufficient';end if;
  insert into public.stock_movements(owner_id,product_id,line_no,delta_units,balance_after,purchase_reversal_id)
  values(v_user,(v_line->>'product_id')::uuid,v_index,-(v_line->>'quantity_units')::bigint,v_after,p_id);
 end loop;
 if v_cash_refund>0 then
  v_cash:=v_cash+v_cash_refund;
  update public.cash_accounts set balance=v_cash,updated_at=now() where owner_id=v_user;
  insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,supplier_id,purchase_reversal_id,note,request_payload)
  values(v_user,'supplier_refund',v_cash_refund,v_cash_refund,v_cash,v_purchase.supplier_id,p_id,'گەڕاندنەوەی کڕین P-'||v_purchase.receipt_no||' · '||v_reason,jsonb_build_object('purchase_reversal',p_id,'purchase',p_purchase));
 end if;
 return to_jsonb(v_result)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_purchase_reversal(uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.post_purchase_reversal(uuid,uuid,text) to authenticated;
create function public.post_purchase_reversal(p_id uuid,p_purchase uuid,p_reason text)
returns jsonb language sql security invoker set search_path='' as $$ select private.post_purchase_reversal(p_id,p_purchase,p_reason); $$;
revoke all on function public.post_purchase_reversal(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.post_purchase_reversal(uuid,uuid,text) to authenticated;

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
 'supplier_refunds',coalesce(sum(amount) filter(where kind='supplier_refund'),0)::text,
 'count',count(*)::text
 ) from public.cash_movements where owner_id=(select auth.uid());
$$;

create or replace function public.get_cash_statement(p_from date,p_to date)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_start timestamptz;v_end timestamptz;v_opening numeric;v_rows jsonb;v_totals jsonb;v_kinds jsonb;
begin
 if auth.uid() is null then raise exception 'cash_statement_auth_required';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>365 then raise exception 'cash_statement_invalid_range';end if;
 v_start:=p_from::timestamp at time zone 'Asia/Baghdad';v_end:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 select coalesce(sum(delta::numeric),0) into v_opening from public.cash_movements where owner_id=auth.uid() and created_at<v_start;
 with entries as materialized(
  select c.id,c.movement_no,c.created_at,c.kind,c.amount,c.delta,c.note,c.customer_id,c.supplier_id,
   coalesce(c.purchase_id,pr.purchase_id) as purchase_id,coalesce(c.sale_id,r.sale_id,t.sale_id) as linked_sale_id
  from public.cash_movements c
  left join public.sale_reversals r on r.id=c.reversal_id
  left join public.sale_returns t on t.id=c.return_id
  left join public.purchase_reversals pr on pr.id=c.purchase_reversal_id
  where c.owner_id=auth.uid() and c.created_at>=v_start and c.created_at<v_end
 ),ordered as(
  select id,movement_no::text as movement_no,created_at,kind,amount::text as amount,delta::text as delta,note,customer_id,supplier_id,purchase_id,linked_sale_id,
   (v_opening+sum(delta::numeric) over(order by created_at,movement_no rows unbounded preceding))::text as statement_balance
  from entries order by created_at,movement_no limit 5001
 ),totals as(select coalesce(sum(delta::numeric) filter(where delta>0),0) inflows,coalesce(-sum(delta::numeric) filter(where delta<0),0) outflows from entries),
 kinds as(select kind,sum(amount::numeric)::text total from entries group by kind)
 select coalesce(jsonb_agg(to_jsonb(ordered) order by ordered.created_at,ordered.movement_no::bigint),'[]'::jsonb),
 (select jsonb_build_object('opening',v_opening::text,'inflows',inflows::text,'outflows',outflows::text,'closing',(v_opening+inflows-outflows)::text) from totals),
 (select coalesce(jsonb_object_agg(kind,total),'{}'::jsonb) from kinds) into v_rows,v_totals,v_kinds from ordered;
 if jsonb_array_length(v_rows)>5000 then raise exception 'cash_statement_too_many_rows';end if;
 return jsonb_build_object('from',p_from,'to',p_to,'timezone','Asia/Baghdad','currency','IQD','generated_at',statement_timestamp(),'count',jsonb_array_length(v_rows),'summary',v_totals,'by_kind',v_kinds,'rows',v_rows);
end $$;

create or replace function public.get_daily_report(p_day date)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_start timestamptz;v_end timestamptz;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='sale_auth_required';end if;
 if p_day is null then raise exception 'report_day_required';end if;
 v_start:=p_day::timestamp at time zone 'Asia/Baghdad';v_end:=(p_day+1)::timestamp at time zone 'Asia/Baghdad';
 with sales as(
  select count(*) count,count(*) filter(where payment_mode='cash') cash_count,count(*) filter(where payment_mode='credit') credit_count,
   coalesce(sum(subtotal),0) subtotal,coalesce(sum(discount),0) discounts,coalesce(sum(total),0) total,
   coalesce(sum(total) filter(where payment_mode='cash'),0) cash_total,coalesce(sum(total) filter(where payment_mode='credit'),0) credit_total,
   coalesce(sum(total-debt_amount),0) cash_received,coalesce(sum(debt_amount),0) debt_added from public.sales where owner_id=v_user and created_at>=v_start and created_at<v_end
 ),return_rows as(
  select total,cash_refund,debt_reversed from public.sale_reversals where owner_id=v_user and created_at>=v_start and created_at<v_end
  union all select total,cash_refund,debt_reversed from public.sale_returns where owner_id=v_user and created_at>=v_start and created_at<v_end
 ),returns as(select count(*) count,coalesce(sum(total),0) total,coalesce(sum(cash_refund),0) cash_refund,coalesce(sum(debt_reversed),0) debt_reversed from return_rows),
 purchase_returns as(
  select count(*) count,coalesce(sum(total),0) total,coalesce(sum(cash_refund),0) cash_refund,count(*) filter(where accounting_mode='untracked') untracked_count
  from public.purchase_reversals where owner_id=v_user and created_at>=v_start and created_at<v_end
 ),cash as(
  select count(*) filter(where created_at>=v_start) count,coalesce(sum(delta) filter(where created_at<v_start),0) opening,
   coalesce(sum(delta) filter(where created_at>=v_start and delta>=0),0) inflows,coalesce(-sum(delta) filter(where created_at>=v_start and delta<0),0) outflows,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='sale'),0) sales,coalesce(sum(amount) filter(where created_at>=v_start and kind='refund'),0) refunds,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='supplier_purchase'),0) supplier_purchases,coalesce(sum(amount) filter(where created_at>=v_start and kind='supplier_payment'),0) supplier_payments,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='supplier_refund'),0) supplier_refunds,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='repayment'),0) repayments,coalesce(sum(amount) filter(where created_at>=v_start and kind='deposit'),0) deposits,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='withdrawal'),0) withdrawals,coalesce(sum(amount) filter(where created_at>=v_start and kind='expense'),0) expenses
  from public.cash_movements where owner_id=v_user and created_at<v_end
 ),debt as(
  select count(*) filter(where created_at>=v_start) count,coalesce(sum(delta) filter(where created_at<v_start),0) opening,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='charge' and sale_id is null),0) manual_charges,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='charge' and sale_id is not null),0) sale_charges,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='repayment'),0) repayments,coalesce(sum(amount) filter(where created_at>=v_start and kind='reversal'),0) reversals
  from public.debt_entries where owner_id=v_user and created_at<v_end
 ),purchases as(
  select count(*) count,coalesce(sum(total),0) total,coalesce(sum(amount_paid),0) paid,coalesce(sum(debt_amount),0) debt_added,count(*) filter(where accounting_mode='untracked') untracked_count
  from public.purchases where owner_id=v_user and created_at>=v_start and created_at<v_end
 )
 select jsonb_build_object('day',p_day,'timezone','Asia/Baghdad','currency','IQD','generated_at',statement_timestamp(),
  'sales',jsonb_build_object('count',s.count::text,'cash_count',s.cash_count::text,'credit_count',s.credit_count::text,'subtotal',s.subtotal::text,'discounts',s.discounts::text,'total',s.total::text,'cash_total',s.cash_total::text,'credit_total',s.credit_total::text,'cash_received',s.cash_received::text,'debt_added',s.debt_added::text),
  'returns',jsonb_build_object('count',r.count::text,'total',r.total::text,'cash_refund',r.cash_refund::text,'debt_reversed',r.debt_reversed::text),
  'purchase_returns',jsonb_build_object('count',pr.count::text,'total',pr.total::text,'cash_refund',pr.cash_refund::text,'untracked_count',pr.untracked_count::text),
  'cash',jsonb_build_object('count',c.count::text,'opening',c.opening::text,'inflows',c.inflows::text,'outflows',c.outflows::text,'closing',(c.opening+c.inflows-c.outflows)::text,'sales',c.sales::text,'refunds',c.refunds::text,'supplier_purchases',c.supplier_purchases::text,'supplier_payments',c.supplier_payments::text,'supplier_refunds',c.supplier_refunds::text,'repayments',c.repayments::text,'deposits',c.deposits::text,'withdrawals',c.withdrawals::text,'expenses',c.expenses::text),
  'debt',jsonb_build_object('count',d.count::text,'opening',d.opening::text,'manual_charges',d.manual_charges::text,'sale_charges',d.sale_charges::text,'repayments',d.repayments::text,'reversals',d.reversals::text,'closing',(d.opening+d.manual_charges+d.sale_charges-d.repayments-d.reversals)::text),
  'purchases',jsonb_build_object('count',p.count::text,'total',p.total::text,'paid',p.paid::text,'debt_added',p.debt_added::text,'untracked_count',p.untracked_count::text)
 ) into v_result from sales s cross join returns r cross join purchase_returns pr cross join cash c cross join debt d cross join purchases p;
 return v_result;
end $$;
notify pgrst,'reload schema';