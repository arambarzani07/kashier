alter table public.purchase_returns add column debt_reversed bigint not null default 0;
alter table public.purchase_returns add constraint purchase_returns_debt_reversed_check check(debt_reversed between 0 and 100000000000000);
alter table public.purchase_returns drop constraint purchase_returns_check;
alter table public.purchase_returns add constraint purchase_returns_finance_check check(
 (accounting_mode='tracked' and supplier_id is not null and cash_refund+debt_reversed=total)
 or (accounting_mode='untracked' and supplier_id is null and cash_refund=0 and debt_reversed=0)
);

alter table public.purchase_reversals add column debt_reversed bigint not null default 0;
alter table public.purchase_reversals add constraint purchase_reversals_debt_reversed_check check(debt_reversed between 0 and 100000000000000);
alter table public.purchase_reversals drop constraint purchase_reversals_check;
alter table public.purchase_reversals add constraint purchase_reversals_finance_check check(
 (accounting_mode='tracked' and supplier_id is not null and cash_refund+debt_reversed=total)
 or (accounting_mode='untracked' and supplier_id is null and cash_refund=0 and debt_reversed=0)
);

create or replace function private.post_purchase_return(p_id uuid,p_purchase uuid,p_reason text,p_lines jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_payload jsonb;v_return public.purchase_returns%rowtype;v_purchase public.purchases%rowtype;
 v_request jsonb;v_original jsonb;v_return_lines jsonb:='[]'::jsonb;v_seen integer[]:='{}';v_line_no integer;v_qty bigint;v_prev_qty bigint;v_original_qty bigint;v_cost bigint;v_line_value bigint;v_total bigint:=0;
 v_cash_refund bigint:=0;v_debt_reversed bigint:=0;v_product uuid;v_stock record;v_after bigint;v_cash_after bigint;
 v_charge public.supplier_entries%rowtype;v_allocated bigint:=0;v_prior_reversed bigint:=0;v_outstanding bigint:=0;v_supplier_balance bigint;v_supplier_after bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='purchase_return_auth_required';end if;
 if p_id is null or p_purchase is null or p_lines is null or jsonb_typeof(p_lines)<>'array' then raise exception 'purchase_return_invalid_request';end if;
 if jsonb_array_length(p_lines) not between 1 and 200 then raise exception 'purchase_return_invalid_items';end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'purchase_return_reason_required';end if;
 v_payload:=jsonb_build_object('purchase_id',p_purchase,'reason',btrim(p_reason),'lines',p_lines);
 perform pg_advisory_xact_lock(hashtextextended('kashier.purchase-return.'||p_id::text,0));
 select * into v_return from public.purchase_returns where id=p_id;
 if found then if v_return.owner_id<>v_user or v_return.request_payload<>v_payload then raise exception 'purchase_return_request_conflict';end if;return to_jsonb(v_return)-'owner_id'-'request_payload';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.purchase-adjustment.'||p_purchase::text,0));
 select * into v_purchase from public.purchases where id=p_purchase and owner_id=v_user for share;
 if not found then raise exception 'purchase_return_unavailable';end if;
 if exists(select 1 from public.purchase_reversals where purchase_id=p_purchase) then raise exception 'purchase_return_purchase_reversed';end if;
 if v_purchase.accounting_mode='tracked' then
  if v_purchase.supplier_id is null or v_purchase.amount_paid+v_purchase.debt_amount<>v_purchase.total then raise exception 'purchase_return_state_invalid';end if;
 elsif v_purchase.accounting_mode='untracked' then
  if v_purchase.supplier_id is not null or v_purchase.amount_paid<>0 or v_purchase.debt_amount<>0 then raise exception 'purchase_return_state_invalid';end if;
 else raise exception 'purchase_return_state_invalid';end if;

 for v_request in select value from jsonb_array_elements(p_lines) loop
  if jsonb_typeof(v_request)<>'object' or coalesce(v_request->>'line_no','') !~ '^[0-9]{1,3}$' or coalesce(v_request->>'quantity_units','') !~ '^[0-9]{1,8}$' then raise exception 'purchase_return_invalid_items';end if;
  v_line_no:=(v_request->>'line_no')::integer;v_qty:=(v_request->>'quantity_units')::bigint;
  if v_line_no not between 1 and jsonb_array_length(v_purchase.lines) or v_qty not between 1 and 10000000 then raise exception 'purchase_return_invalid_items';end if;
  if v_line_no=any(v_seen) then raise exception 'purchase_return_duplicate_line';end if;v_seen:=array_append(v_seen,v_line_no);
  v_original:=v_purchase.lines->(v_line_no-1);v_original_qty:=(v_original->>'quantity_units')::bigint;v_cost:=(v_original->>'unit_cost')::bigint;v_product:=(v_original->>'product_id')::uuid;
  select coalesce(sum((rl->>'quantity_units')::bigint),0) into v_prev_qty from public.purchase_returns pr cross join lateral jsonb_array_elements(pr.lines) rl where pr.purchase_id=p_purchase and pr.owner_id=v_user and (rl->>'line_no')::integer=v_line_no;
  if v_prev_qty+v_qty>v_original_qty then raise exception 'purchase_return_quantity_exceeds_remaining';end if;
  v_line_value:=(((v_prev_qty+v_qty)*v_cost+500)/1000)-((v_prev_qty*v_cost+500)/1000);if v_line_value<0 then raise exception 'purchase_return_invalid_money';end if;
  v_total:=v_total+v_line_value;if v_total>100000000000000 then raise exception 'purchase_return_total_limit';end if;
  v_return_lines:=v_return_lines||jsonb_build_array(jsonb_build_object('line_no',v_line_no,'product_id',v_product,'name',v_original->>'name','barcode',v_original->'barcode','quantity_units',v_qty,'original_quantity_units',v_original_qty,'unit_cost',v_cost,'line_total',v_line_value));
 end loop;

 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 for v_stock in select (x->>'product_id')::uuid product_id,sum((x->>'quantity_units')::bigint) returned from jsonb_array_elements(v_return_lines) x group by (x->>'product_id')::uuid order by (x->>'product_id')::uuid loop
  select quantity_units into v_after from public.product_stock where product_id=v_stock.product_id and owner_id=v_user for update;if not found or v_after<v_stock.returned then raise exception 'purchase_return_stock_insufficient';end if;
 end loop;

 if v_purchase.accounting_mode='tracked' then
  if v_purchase.debt_amount>0 then
   perform pg_advisory_xact_lock(hashtextextended('kashier.supplier.'||v_user::text,0));
   perform pg_advisory_xact_lock(hashtextextended('kashier.purchase-finance.'||p_purchase::text,0));
   select * into v_charge from public.supplier_entries where owner_id=v_user and purchase_id=p_purchase and kind='charge' for share;
   if not found or v_charge.amount<>v_purchase.debt_amount then raise exception 'purchase_return_ledger_mismatch';end if;
   select coalesce(sum(amount),0)::bigint into v_allocated from public.supplier_payment_allocations where owner_id=v_user and purchase_id=p_purchase;
   select coalesce(sum(amount),0)::bigint into v_prior_reversed from public.supplier_entries where owner_id=v_user and purchase_id=p_purchase and kind='reversal';
   v_outstanding:=v_charge.amount-v_allocated-v_prior_reversed;if v_outstanding<0 then raise exception 'purchase_return_ledger_mismatch';end if;
   v_debt_reversed:=least(v_total,v_outstanding);
   if v_debt_reversed>0 then
    select balance into v_supplier_balance from public.supplier_balances where supplier_id=v_purchase.supplier_id and owner_id=v_user for update;
    if not found or v_supplier_balance<v_debt_reversed then raise exception 'purchase_return_ledger_mismatch';end if;
    v_supplier_after:=v_supplier_balance-v_debt_reversed;
   end if;
  end if;
  v_cash_refund:=v_total-v_debt_reversed;
 elsif v_purchase.accounting_mode='untracked' then v_cash_refund:=0;v_debt_reversed:=0;end if;

 if v_cash_refund>0 then
  perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));insert into public.cash_accounts(owner_id,balance) values(v_user,0) on conflict(owner_id) do nothing;
  select balance+v_cash_refund into v_cash_after from public.cash_accounts where owner_id=v_user for update;if v_cash_after>100000000000000 then raise exception 'purchase_return_cash_limit';end if;
 end if;

 insert into public.purchase_returns(id,owner_id,purchase_id,supplier_id,supplier_name,reason,accounting_mode,total,cash_refund,debt_reversed,lines,request_payload)
 values(p_id,v_user,p_purchase,v_purchase.supplier_id,v_purchase.supplier_name,btrim(p_reason),v_purchase.accounting_mode,v_total,v_cash_refund,v_debt_reversed,v_return_lines,v_payload) returning * into v_return;
 for v_original in select value from jsonb_array_elements(v_return_lines) loop
  v_qty:=(v_original->>'quantity_units')::bigint;v_line_no:=(v_original->>'line_no')::integer;
  update public.product_stock set quantity_units=quantity_units-v_qty,updated_at=now() where product_id=(v_original->>'product_id')::uuid and owner_id=v_user and quantity_units>=v_qty returning quantity_units into v_after;
  if not found then raise exception 'purchase_return_stock_insufficient';end if;
  insert into public.stock_movements(owner_id,product_id,purchase_return_id,line_no,delta_units,balance_after) values(v_user,(v_original->>'product_id')::uuid,p_id,v_line_no,-v_qty,v_after);
 end loop;
 if v_debt_reversed>0 then
  update public.supplier_balances set balance=v_supplier_after,updated_at=now() where supplier_id=v_purchase.supplier_id and owner_id=v_user;
  insert into public.supplier_entries(owner_id,supplier_id,supplier_name,kind,amount,delta,balance_after,note,purchase_id,request_payload)
  values(v_user,v_purchase.supplier_id,v_purchase.supplier_name,'reversal',v_debt_reversed,-v_debt_reversed,v_supplier_after,'هەڵوەشاندنەوەی قەرز بە گەڕاندنەوەی بەشی کڕین P-'||v_purchase.receipt_no||' · '||btrim(p_reason),p_purchase,jsonb_build_object('purchase_return_id',p_id,'purchase_id',p_purchase));
 end if;
 if v_cash_refund>0 then
  update public.cash_accounts set balance=v_cash_after,updated_at=now() where owner_id=v_user;
  insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,supplier_id,purchase_return_id,note,request_payload)
  values(v_user,'supplier_refund',v_cash_refund,v_cash_refund,v_cash_after,v_purchase.supplier_id,p_id,'گەڕاندنەوەی بەشی کڕین P-'||v_purchase.receipt_no||' · '||btrim(p_reason),jsonb_build_object('purchase_return_id',p_id,'purchase_id',p_purchase));
 end if;
 return to_jsonb(v_return)-'owner_id'-'request_payload';
end $$;

create or replace function private.post_purchase_reversal(p_id uuid,p_purchase uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_purchase public.purchases%rowtype;v_existing public.purchase_reversals%rowtype;v_result public.purchase_reversals%rowtype;
 v_payload jsonb;v_reason text:=btrim(coalesce(p_reason,''));v_cash_refund bigint:=0;v_debt_reversed bigint:=0;v_cash bigint;v_line jsonb;v_stock record;v_after bigint;v_index integer:=0;
 v_charge public.supplier_entries%rowtype;v_allocated bigint:=0;v_prior_reversed bigint:=0;v_outstanding bigint:=0;v_supplier_balance bigint;v_supplier_after bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='purchase_reversal_auth_required';end if;
 if p_id is null or p_purchase is null then raise exception 'purchase_reversal_invalid_request';end if;
 if char_length(v_reason) not between 1 and 500 then raise exception 'purchase_reversal_reason_required';end if;
 v_payload:=jsonb_build_object('purchase',p_purchase,'reason',v_reason);
 perform pg_advisory_xact_lock(hashtextextended('kashier.purchase-reversal.'||p_id::text,0));
 select * into v_existing from public.purchase_reversals where id=p_id;
 if found then if v_existing.owner_id<>v_user or v_existing.request_payload<>v_payload then raise exception 'purchase_reversal_request_conflict';end if;return to_jsonb(v_existing)-'owner_id'-'request_payload';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.purchase-adjustment.'||p_purchase::text,0));
 if exists(select 1 from public.purchase_returns where purchase_id=p_purchase and owner_id=v_user) then raise exception 'purchase_reversal_partial_returns_exist';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 select * into v_purchase from public.purchases where id=p_purchase and owner_id=v_user for share;if not found then raise exception 'purchase_reversal_unavailable';end if;
 select * into v_existing from public.purchase_reversals where purchase_id=p_purchase;if found then raise exception 'purchase_reversal_already_exists';end if;
 if v_purchase.accounting_mode='tracked' then
  if v_purchase.supplier_id is null or v_purchase.amount_paid+v_purchase.debt_amount<>v_purchase.total then raise exception 'purchase_reversal_state_invalid';end if;
  if v_purchase.debt_amount>0 then
   perform pg_advisory_xact_lock(hashtextextended('kashier.supplier.'||v_user::text,0));perform pg_advisory_xact_lock(hashtextextended('kashier.purchase-finance.'||p_purchase::text,0));
   select * into v_charge from public.supplier_entries where owner_id=v_user and purchase_id=p_purchase and kind='charge' for share;
   if not found or v_charge.amount<>v_purchase.debt_amount then raise exception 'purchase_reversal_ledger_mismatch';end if;
   select coalesce(sum(amount),0)::bigint into v_allocated from public.supplier_payment_allocations where owner_id=v_user and purchase_id=p_purchase;
   select coalesce(sum(amount),0)::bigint into v_prior_reversed from public.supplier_entries where owner_id=v_user and purchase_id=p_purchase and kind='reversal';
   v_outstanding:=v_charge.amount-v_allocated-v_prior_reversed;if v_outstanding<0 then raise exception 'purchase_reversal_ledger_mismatch';end if;
   v_debt_reversed:=least(v_purchase.total,v_outstanding);
   if v_debt_reversed>0 then select balance into v_supplier_balance from public.supplier_balances where supplier_id=v_purchase.supplier_id and owner_id=v_user for update;if not found or v_supplier_balance<v_debt_reversed then raise exception 'purchase_reversal_ledger_mismatch';end if;v_supplier_after:=v_supplier_balance-v_debt_reversed;end if;
  end if;
  v_cash_refund:=v_purchase.total-v_debt_reversed;
 elsif v_purchase.accounting_mode='untracked' then
  if v_purchase.supplier_id is not null or v_purchase.amount_paid<>0 or v_purchase.debt_amount<>0 then raise exception 'purchase_reversal_state_invalid';end if;v_cash_refund:=0;v_debt_reversed:=0;
 else raise exception 'purchase_reversal_state_invalid';end if;
 for v_stock in select (x->>'product_id')::uuid product_id,sum((x->>'quantity_units')::bigint) required from jsonb_array_elements(v_purchase.lines) x group by (x->>'product_id')::uuid order by (x->>'product_id')::uuid loop
  select quantity_units into v_after from public.product_stock where product_id=v_stock.product_id and owner_id=v_user for update;if not found or v_after<v_stock.required then raise exception 'purchase_reversal_stock_insufficient';end if;
 end loop;
 if v_cash_refund>0 then perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));insert into public.cash_accounts(owner_id,balance) values(v_user,0) on conflict(owner_id) do nothing;select balance into v_cash from public.cash_accounts where owner_id=v_user for update;if v_cash>100000000000000-v_cash_refund then raise exception 'purchase_reversal_cash_limit';end if;end if;
 insert into public.purchase_reversals(id,owner_id,purchase_id,supplier_id,supplier_name,reason,accounting_mode,total,cash_refund,debt_reversed,lines,request_payload)
 values(p_id,v_user,v_purchase.id,v_purchase.supplier_id,v_purchase.supplier_name,v_reason,v_purchase.accounting_mode,v_purchase.total,v_cash_refund,v_debt_reversed,v_purchase.lines,v_payload) returning * into v_result;
 for v_line in select value from jsonb_array_elements(v_purchase.lines) loop v_index:=v_index+1;update public.product_stock set quantity_units=quantity_units-(v_line->>'quantity_units')::bigint,updated_at=now() where product_id=(v_line->>'product_id')::uuid and owner_id=v_user and quantity_units>=(v_line->>'quantity_units')::bigint returning quantity_units into v_after;if not found then raise exception 'purchase_reversal_stock_insufficient';end if;insert into public.stock_movements(owner_id,product_id,line_no,delta_units,balance_after,purchase_reversal_id) values(v_user,(v_line->>'product_id')::uuid,v_index,-(v_line->>'quantity_units')::bigint,v_after,p_id);end loop;
 if v_debt_reversed>0 then
  update public.supplier_balances set balance=v_supplier_after,updated_at=now() where supplier_id=v_purchase.supplier_id and owner_id=v_user;
  insert into public.supplier_entries(owner_id,supplier_id,supplier_name,kind,amount,delta,balance_after,note,purchase_id,request_payload)
  values(v_user,v_purchase.supplier_id,v_purchase.supplier_name,'reversal',v_debt_reversed,-v_debt_reversed,v_supplier_after,'هەڵوەشاندنەوەی قەرز بە گەڕاندنەوەی تەواوی کڕین P-'||v_purchase.receipt_no||' · '||v_reason,p_purchase,jsonb_build_object('purchase_reversal_id',p_id,'purchase_id',p_purchase));
 end if;
 if v_cash_refund>0 then v_cash:=v_cash+v_cash_refund;update public.cash_accounts set balance=v_cash,updated_at=now() where owner_id=v_user;insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,supplier_id,purchase_reversal_id,note,request_payload) values(v_user,'supplier_refund',v_cash_refund,v_cash_refund,v_cash,v_purchase.supplier_id,p_id,'گەڕاندنەوەی کڕین P-'||v_purchase.receipt_no||' · '||v_reason,jsonb_build_object('purchase_reversal',p_id,'purchase',p_purchase));end if;
 return to_jsonb(v_result)-'owner_id'-'request_payload';
end $$;

create or replace function public.get_supplier_activity(p_supplier uuid,p_offset integer default 0,p_limit integer default 50)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
 if p_supplier is null or p_offset<0 or p_limit not between 1 and 100 then raise exception 'supplier_activity_invalid_request';end if;
 if not exists(select 1 from public.suppliers where id=p_supplier and owner_id=v_user) then raise exception 'supplier_unavailable';end if;
 with raw as materialized(
  select e.id,e.created_at,'entry'::text source_type,e.kind,e.amount,e.delta,e.note,e.purchase_id,e.cash_movement_id,e.supplier_name,0::bigint cash_refund,0::bigint debt_reversed,('D-'||e.movement_no::text) reference_no,1 source_rank
  from public.supplier_entries e where e.owner_id=v_user and e.supplier_id=p_supplier and e.kind in ('charge','payment')
  union all
  select r.id,r.created_at,'full_return','return',r.total,-r.debt_reversed,r.reason,r.purchase_id,c.id,r.supplier_name,r.cash_refund,r.debt_reversed,('PRV-'||r.reversal_no::text),2
  from public.purchase_reversals r left join public.cash_movements c on c.purchase_reversal_id=r.id and c.owner_id=r.owner_id
  where r.owner_id=v_user and r.supplier_id=p_supplier and r.accounting_mode='tracked'
  union all
  select r.id,r.created_at,'partial_return','return',r.total,-r.debt_reversed,r.reason,r.purchase_id,c.id,r.supplier_name,r.cash_refund,r.debt_reversed,('PPR-'||r.return_no::text),3
  from public.purchase_returns r left join public.cash_movements c on c.purchase_return_id=r.id and c.owner_id=r.owner_id
  where r.owner_id=v_user and r.supplier_id=p_supplier and r.accounting_mode='tracked'
 ),numbered as materialized(
  select *,row_number() over(order by created_at,source_rank,id)::bigint movement_no,sum(delta) over(order by created_at,source_rank,id rows unbounded preceding)::bigint balance_after from raw
 ),page as(select * from numbered order by movement_no desc offset p_offset limit p_limit)
 select jsonb_build_object('total',(select count(*) from numbered),'rows',coalesce((select jsonb_agg(jsonb_build_object(
  'id',id,'movement_no',movement_no::text,'reference_no',reference_no,'source_type',source_type,'supplier_name',supplier_name,'created_at',created_at,'kind',kind,'amount',amount::text,'delta',delta::text,'balance_after',balance_after::text,'cash_refund',cash_refund::text,'debt_reversed',debt_reversed::text,'note',note,'purchase_id',purchase_id,'cash_movement_id',cash_movement_id
 ) order by movement_no desc) from page),'[]'::jsonb)) into v_result;return v_result;
end $$;

create or replace function public.get_supplier_statement(p_supplier uuid,p_from date default null,p_to date default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_supplier public.suppliers%rowtype;v_from timestamptz;v_to timestamptz;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;if p_from is not null and p_to is not null and p_from>p_to then raise exception 'statement_invalid_dates';end if;
 select * into v_supplier from public.suppliers where id=p_supplier and owner_id=v_user;if not found then raise exception 'supplier_unavailable';end if;
 v_from:=p_from::timestamp at time zone 'Asia/Baghdad';v_to:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 with raw as materialized(
  select e.id,e.created_at,'entry'::text source_type,e.kind,e.amount,e.delta,e.note,e.purchase_id,e.cash_movement_id,0::bigint cash_refund,0::bigint debt_reversed,('D-'||e.movement_no::text) reference_no,1 source_rank
  from public.supplier_entries e where e.owner_id=v_user and e.supplier_id=p_supplier and e.kind in ('charge','payment')
  union all
  select r.id,r.created_at,'full_return','return',r.total,-r.debt_reversed,r.reason,r.purchase_id,c.id,r.cash_refund,r.debt_reversed,('PRV-'||r.reversal_no::text),2
  from public.purchase_reversals r left join public.cash_movements c on c.purchase_reversal_id=r.id and c.owner_id=r.owner_id where r.owner_id=v_user and r.supplier_id=p_supplier and r.accounting_mode='tracked'
  union all
  select r.id,r.created_at,'partial_return','return',r.total,-r.debt_reversed,r.reason,r.purchase_id,c.id,r.cash_refund,r.debt_reversed,('PPR-'||r.return_no::text),3
  from public.purchase_returns r left join public.cash_movements c on c.purchase_return_id=r.id and c.owner_id=r.owner_id where r.owner_id=v_user and r.supplier_id=p_supplier and r.accounting_mode='tracked'
 ),numbered as materialized(
  select *,row_number() over(order by created_at,source_rank,id)::bigint movement_no,sum(delta) over(order by created_at,source_rank,id rows unbounded preceding)::bigint lifetime_balance from raw
 ),opening as(select coalesce(sum(delta) filter(where v_from is not null and created_at<v_from),0)::bigint amount from numbered),
 period as materialized(select * from numbered where (v_from is null or created_at>=v_from) and (v_to is null or created_at<v_to)),
 totals as(select count(*) count,coalesce(sum(amount) filter(where kind='charge'),0)::bigint charges,coalesce(sum(amount) filter(where kind='payment'),0)::bigint payments,coalesce(sum(amount) filter(where kind='return'),0)::bigint returns_total,coalesce(sum(debt_reversed) filter(where kind='return'),0)::bigint reversals from period),
 ordered as(select * from period order by movement_no limit 5001)
 select jsonb_build_object('supplier',jsonb_build_object('id',v_supplier.id,'name',v_supplier.name,'phone',v_supplier.phone),'from',p_from,'to',p_to,'timezone','Asia/Baghdad','generated_at',statement_timestamp(),'currency','IQD','opening',o.amount::text,'charges',t.charges::text,'payments',t.payments::text,'returns_total',t.returns_total::text,'reversals',t.reversals::text,'closing',(o.amount+t.charges-t.payments-t.reversals)::text,'count',t.count,
  'rows',coalesce((select jsonb_agg(jsonb_build_object('id',id,'movement_no',movement_no::text,'reference_no',reference_no,'source_type',source_type,'created_at',created_at,'kind',kind,'amount',amount::text,'delta',delta::text,'balance',lifetime_balance::text,'cash_refund',cash_refund::text,'debt_reversed',debt_reversed::text,'note',note,'purchase_id',purchase_id,'cash_movement_id',cash_movement_id) order by movement_no) from ordered),'[]'::jsonb)) into v_result from opening o cross join totals t;
 if (v_result->>'count')::bigint>5000 then raise exception 'statement_too_many_rows';end if;return v_result;
end $$;

create or replace function public.get_purchase_returns_report(p_kind text default 'all',p_from date default null,p_to date default null,p_supplier text default null,p_query text default null,p_min_amount bigint default null,p_max_amount bigint default null,p_offset integer default 0,p_limit integer default 50)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_kind text:=lower(btrim(coalesce(p_kind,'all')));v_supplier text:=btrim(coalesce(p_supplier,''));v_query text:=btrim(coalesce(p_query,''));v_start timestamptz;v_end timestamptz;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='purchase_returns_auth_required';end if;if v_kind not in ('all','full','partial') then raise exception 'purchase_returns_invalid_kind';end if;if p_from is not null and p_to is not null and p_from>p_to then raise exception 'purchase_returns_invalid_dates';end if;
 if char_length(v_supplier)>100 then raise exception 'purchase_returns_invalid_supplier';end if;if char_length(v_query)>100 then raise exception 'purchase_returns_invalid_query';end if;if p_min_amount is not null and (p_min_amount<0 or p_min_amount>100000000000000) then raise exception 'purchase_returns_invalid_amount';end if;if p_max_amount is not null and (p_max_amount<0 or p_max_amount>100000000000000) then raise exception 'purchase_returns_invalid_amount';end if;if p_min_amount is not null and p_max_amount is not null and p_min_amount>p_max_amount then raise exception 'purchase_returns_invalid_amount_range';end if;if p_offset is null or p_offset<0 or p_offset>10000000 or p_limit is null or p_limit<1 or p_limit>100 then raise exception 'purchase_returns_invalid_page';end if;
 if p_from is not null then v_start:=p_from::timestamp at time zone 'Asia/Baghdad';end if;if p_to is not null then v_end:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';end if;
 with combined as(
  select 'full'::text kind,r.id,r.reversal_no return_no,r.purchase_id,r.created_at,r.reason,r.accounting_mode,r.total,r.cash_refund,r.debt_reversed,r.lines,r.supplier_id,r.supplier_name,p.receipt_no,p.invoice_no from public.purchase_reversals r join public.purchases p on p.id=r.purchase_id and p.owner_id=v_user where r.owner_id=v_user and v_kind in('all','full') and (v_start is null or r.created_at>=v_start) and (v_end is null or r.created_at<v_end)
  union all
  select 'partial',r.id,r.return_no,r.purchase_id,r.created_at,r.reason,r.accounting_mode,r.total,r.cash_refund,r.debt_reversed,r.lines,r.supplier_id,r.supplier_name,p.receipt_no,p.invoice_no from public.purchase_returns r join public.purchases p on p.id=r.purchase_id and p.owner_id=v_user where r.owner_id=v_user and v_kind in('all','partial') and (v_start is null or r.created_at>=v_start) and (v_end is null or r.created_at<v_end)
 ),filtered as(select * from combined c where (v_supplier='' or position(lower(v_supplier) in lower(coalesce(c.supplier_name,'')))>0) and (p_min_amount is null or c.total>=p_min_amount) and (p_max_amount is null or c.total<=p_max_amount) and (v_query='' or position(lower(v_query) in lower(coalesce(c.invoice_no,'')))>0 or position(lower(v_query) in lower(coalesce(c.reason,'')))>0 or (v_query~'^[0-9]{1,18}$' and (c.receipt_no=v_query::bigint or c.return_no=v_query::bigint)))),total as(select count(*)::text count from filtered),page as(select * from filtered order by created_at desc,id desc offset p_offset limit p_limit)
 select jsonb_build_object('count',t.count,'rows',coalesce((select jsonb_agg(jsonb_build_object('kind',p.kind,'id',p.id,'return_no',p.return_no::text,'purchase_id',p.purchase_id,'receipt_no',p.receipt_no::text,'invoice_no',p.invoice_no,'supplier_id',p.supplier_id,'supplier_name',p.supplier_name,'created_at',p.created_at,'reason',p.reason,'accounting_mode',p.accounting_mode,'total',p.total::text,'cash_refund',p.cash_refund::text,'debt_reversed',p.debt_reversed::text,'lines',p.lines) order by p.created_at desc,p.id desc) from page p),'[]'::jsonb)) into v_result from total t;return v_result;
end $$;

create or replace function public.get_daily_report(p_day date)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_start timestamptz;v_end timestamptz;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='sale_auth_required';end if;if p_day is null then raise exception 'report_day_required';end if;v_start:=p_day::timestamp at time zone 'Asia/Baghdad';v_end:=(p_day+1)::timestamp at time zone 'Asia/Baghdad';
 with sales as(select count(*) count,count(*) filter(where payment_mode='cash') cash_count,count(*) filter(where payment_mode='credit') credit_count,coalesce(sum(subtotal),0) subtotal,coalesce(sum(discount),0) discounts,coalesce(sum(total),0) total,coalesce(sum(total) filter(where payment_mode='cash'),0) cash_total,coalesce(sum(total) filter(where payment_mode='credit'),0) credit_total,coalesce(sum(total-debt_amount),0) cash_received,coalesce(sum(debt_amount),0) debt_added from public.sales where owner_id=v_user and created_at>=v_start and created_at<v_end),
 return_rows as(select total,cash_refund,debt_reversed from public.sale_reversals where owner_id=v_user and created_at>=v_start and created_at<v_end union all select total,cash_refund,debt_reversed from public.sale_returns where owner_id=v_user and created_at>=v_start and created_at<v_end),returns as(select count(*) count,coalesce(sum(total),0) total,coalesce(sum(cash_refund),0) cash_refund,coalesce(sum(debt_reversed),0) debt_reversed from return_rows),
 purchase_return_rows as(select total,cash_refund,debt_reversed,accounting_mode from public.purchase_reversals where owner_id=v_user and created_at>=v_start and created_at<v_end union all select total,cash_refund,debt_reversed,accounting_mode from public.purchase_returns where owner_id=v_user and created_at>=v_start and created_at<v_end),purchase_return_summary as(select count(*) count,coalesce(sum(total),0) total,coalesce(sum(cash_refund),0) cash_refund,coalesce(sum(debt_reversed),0) debt_reversed,count(*) filter(where accounting_mode='untracked') untracked_count from purchase_return_rows),
 cash as(select count(*) filter(where created_at>=v_start) count,coalesce(sum(delta) filter(where created_at<v_start),0) opening,coalesce(sum(delta) filter(where created_at>=v_start and delta>=0),0) inflows,coalesce(-sum(delta) filter(where created_at>=v_start and delta<0),0) outflows,coalesce(sum(amount) filter(where created_at>=v_start and kind='sale'),0) sales,coalesce(sum(amount) filter(where created_at>=v_start and kind='refund'),0) refunds,coalesce(sum(amount) filter(where created_at>=v_start and kind='supplier_purchase'),0) supplier_purchases,coalesce(sum(amount) filter(where created_at>=v_start and kind='supplier_payment'),0) supplier_payments,coalesce(sum(amount) filter(where created_at>=v_start and kind='supplier_refund'),0) supplier_refunds,coalesce(sum(amount) filter(where created_at>=v_start and kind='repayment'),0) repayments,coalesce(sum(amount) filter(where created_at>=v_start and kind='deposit'),0) deposits,coalesce(sum(amount) filter(where created_at>=v_start and kind='withdrawal'),0) withdrawals,coalesce(sum(amount) filter(where created_at>=v_start and kind='expense'),0) expenses from public.cash_movements where owner_id=v_user and created_at<v_end),
 debt as(select count(*) filter(where created_at>=v_start) count,coalesce(sum(delta) filter(where created_at<v_start),0) opening,coalesce(sum(amount) filter(where created_at>=v_start and kind='charge' and sale_id is null),0) manual_charges,coalesce(sum(amount) filter(where created_at>=v_start and kind='charge' and sale_id is not null),0) sale_charges,coalesce(sum(amount) filter(where created_at>=v_start and kind='repayment'),0) repayments,coalesce(sum(amount) filter(where created_at>=v_start and kind='reversal'),0) reversals from public.debt_entries where owner_id=v_user and created_at<v_end),
 purchases as(select count(*) count,coalesce(sum(total),0) total,coalesce(sum(amount_paid),0) paid,coalesce(sum(debt_amount),0) debt_added,count(*) filter(where accounting_mode='untracked') untracked_count from public.purchases where owner_id=v_user and created_at>=v_start and created_at<v_end)
 select jsonb_build_object('day',p_day,'timezone','Asia/Baghdad','currency','IQD','generated_at',statement_timestamp(),'sales',jsonb_build_object('count',s.count::text,'cash_count',s.cash_count::text,'credit_count',s.credit_count::text,'subtotal',s.subtotal::text,'discounts',s.discounts::text,'total',s.total::text,'cash_total',s.cash_total::text,'credit_total',s.credit_total::text,'cash_received',s.cash_received::text,'debt_added',s.debt_added::text),'returns',jsonb_build_object('count',r.count::text,'total',r.total::text,'cash_refund',r.cash_refund::text,'debt_reversed',r.debt_reversed::text),'purchase_returns',jsonb_build_object('count',pr.count::text,'total',pr.total::text,'cash_refund',pr.cash_refund::text,'debt_reversed',pr.debt_reversed::text,'untracked_count',pr.untracked_count::text),'cash',jsonb_build_object('count',c.count::text,'opening',c.opening::text,'inflows',c.inflows::text,'outflows',c.outflows::text,'closing',(c.opening+c.inflows-c.outflows)::text,'sales',c.sales::text,'refunds',c.refunds::text,'supplier_purchases',c.supplier_purchases::text,'supplier_payments',c.supplier_payments::text,'supplier_refunds',c.supplier_refunds::text,'repayments',c.repayments::text,'deposits',c.deposits::text,'withdrawals',c.withdrawals::text,'expenses',c.expenses::text),'debt',jsonb_build_object('count',d.count::text,'opening',d.opening::text,'manual_charges',d.manual_charges::text,'sale_charges',d.sale_charges::text,'repayments',d.repayments::text,'reversals',d.reversals::text,'closing',(d.opening+d.manual_charges+d.sale_charges-d.repayments-d.reversals)::text),'purchases',jsonb_build_object('count',p.count::text,'total',p.total::text,'paid',p.paid::text,'debt_added',p.debt_added::text,'untracked_count',p.untracked_count::text)) into v_result from sales s cross join returns r cross join purchase_return_summary pr cross join cash c cross join debt d cross join purchases p;return v_result;
end $$;
notify pgrst,'reload schema';
