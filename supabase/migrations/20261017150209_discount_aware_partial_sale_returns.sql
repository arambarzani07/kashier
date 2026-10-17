create or replace function private.post_sale_return(p_id uuid,p_sale uuid,p_reason text,p_lines jsonb)
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
 v_line_gross bigint;
 v_cumulative_gross numeric;
 v_line_discount bigint;
 v_line_net bigint;
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
  v_line_gross:=(v_original->>'line_total')::bigint;
  select coalesce(sum((e.value->>'line_total')::numeric),0) into v_cumulative_gross
   from jsonb_array_elements(v_sale.lines) with ordinality e(value,ordinality)
   where e.ordinality<=v_line_no;
  if v_sale.discount=0 then
   v_line_discount:=0;
   v_line_net:=v_line_gross;
  else
   if v_sale.subtotal<=0 then raise exception 'return_invalid_money'; end if;
   v_line_discount:=(div(v_sale.discount::numeric*v_cumulative_gross,v_sale.subtotal::numeric)-div(v_sale.discount::numeric*(v_cumulative_gross-v_line_gross::numeric),v_sale.subtotal::numeric))::bigint;
   v_line_net:=v_line_gross-v_line_discount;
   if v_line_discount<0 or v_line_net<0 then raise exception 'return_invalid_money'; end if;
  end if;
  select coalesce(sum((rl->>'quantity_units')::bigint),0) into v_prev_qty
   from public.sale_returns sr cross join lateral jsonb_array_elements(sr.lines) rl
   where sr.sale_id=p_sale and sr.owner_id=v_user and (rl->>'line_no')::integer=v_line_no;
  if v_prev_qty+v_qty>v_original_qty then raise exception 'return_quantity_exceeds_remaining'; end if;
  if v_sale.discount=0 then
   v_line_refund:=(((v_prev_qty+v_qty)*v_price+500)/1000)-((v_prev_qty*v_price+500)/1000);
  else
   v_line_refund:=(div(v_line_net::numeric*(v_prev_qty+v_qty),v_original_qty::numeric)-div(v_line_net::numeric*v_prev_qty,v_original_qty::numeric))::bigint;
  end if;
  if v_line_refund<0 then raise exception 'return_invalid_money'; end if;
  v_total:=v_total+v_line_refund;
  if v_total>100000000000000 then raise exception 'return_total_limit'; end if;
  v_return_lines:=v_return_lines||jsonb_build_array(jsonb_build_object(
   'line_no',v_line_no,'product_id',v_product,'name',v_original->>'name','barcode',v_original->'barcode',
   'quantity_units',v_qty,'original_quantity_units',v_original_qty,'unit_price',v_price,'line_total',v_line_refund,
   'original_line_total',v_line_gross,'allocated_discount',v_line_discount,'net_line_total',v_line_net));
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

revoke all on function private.post_sale_return(uuid,uuid,text,jsonb) from public,anon;
grant execute on function private.post_sale_return(uuid,uuid,text,jsonb) to authenticated;
notify pgrst,'reload schema';
