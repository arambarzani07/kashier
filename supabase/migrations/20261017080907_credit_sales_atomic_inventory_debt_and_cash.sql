alter table public.sales add column payment_mode text not null default 'cash',
 add column customer_id uuid references public.customers(id),
 add column debt_amount bigint not null default 0,
 add column debt_entry_id uuid unique references public.debt_entries(id);
alter table public.debt_entries add column sale_id uuid unique references public.sales(id) deferrable initially deferred;
create index sales_customer_idx on public.sales(customer_id) where customer_id is not null;
alter table public.debt_entries add constraint debt_sale_source check(sale_id is null or kind='charge');
alter table public.sales drop constraint sales_check2, drop constraint sales_check3, drop constraint sales_customer_name_check;
alter table public.sales add constraint sales_received_range check(received between 0 and 100000000000000),
 add constraint sales_change_exact check(change_due=greatest(received-total,0)),
 add constraint sales_customer_name_length check(char_length(customer_name)<=150),
 add constraint sales_payment_source check(
 (payment_mode='cash' and received>=total and customer_id is null and debt_amount=0 and debt_entry_id is null)
 or (payment_mode='credit' and customer_id is not null and received<total and debt_amount=total-received and debt_entry_id is not null));
create function private.post_credit_sale(p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer uuid,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid := auth.uid();
 v_payload jsonb;
 v_sale public.sales%rowtype;
 v_line jsonb;
 v_product public.products%rowtype;
 v_qty bigint;
 v_expected bigint;
 v_line_total bigint;
 v_subtotal bigint := 0;
 v_lines jsonb := '[]'::jsonb;
 v_stock record;
 v_after bigint;
 v_index integer := 0;
 v_cash_after bigint;
 v_customer public.customers%rowtype;
 v_debt bigint;
 v_debt_after bigint;
 v_debt_id uuid:=gen_random_uuid();
begin
 if v_user is null then raise exception using errcode='28000',message='sale_auth_required'; end if;
 if p_id is null or p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'sale_invalid_items'; end if;
 if jsonb_array_length(p_items) not between 1 and 200 then raise exception 'sale_invalid_items'; end if;
 if p_discount is null or p_received is null or p_discount<0 or p_received<0 or p_received>100000000000000 then raise exception 'sale_invalid_money'; end if;
 if p_customer is null or char_length(coalesce(p_note,''))>500 then raise exception 'sale_invalid_text'; end if;
 v_payload := jsonb_build_object('items',p_items,'discount',p_discount,'received',p_received,'customer',p_customer,'mode','credit','note',btrim(coalesce(p_note,'')));
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale.'||p_id::text,0));
 select * into v_sale from public.sales where id=p_id;
 if found then
  if v_sale.owner_id<>v_user or v_sale.request_payload<>v_payload then raise exception 'sale_request_conflict'; end if;
  return to_jsonb(v_sale)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 for v_line in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(v_line)<>'object' or coalesce(v_line->>'quantity_units','') !~ '^[0-9]{1,8}$' or coalesce(v_line->>'expected_price','') !~ '^[0-9]{1,10}$' then raise exception 'sale_invalid_items'; end if;
  v_qty := (v_line->>'quantity_units')::bigint;
  v_expected := (v_line->>'expected_price')::bigint;
  if v_qty not between 1 and 10000000 then raise exception 'sale_invalid_quantity'; end if;
  select * into v_product from public.products where id=(v_line->>'product_id')::uuid and owner_id=v_user for share;
  if not found then raise exception 'sale_product_unavailable'; end if;
  if v_expected<>v_product.sale_price then raise exception 'sale_price_changed'; end if;
  v_line_total := (v_qty*v_product.sale_price+500)/1000;
  v_subtotal := v_subtotal+v_line_total;
  if v_subtotal>100000000000000 then raise exception 'sale_total_limit'; end if;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('product_id',v_product.id,'name',v_product.name,'barcode',v_product.barcode,'quantity_units',v_qty,'unit_price',v_product.sale_price,'line_total',v_line_total));
 end loop;
 if p_discount>v_subtotal then raise exception 'sale_discount_exceeds_total'; end if;
 if p_received>=v_subtotal-p_discount then raise exception 'sale_credit_requires_debt'; end if;
 v_debt:=v_subtotal-p_discount-p_received;
 perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||v_user::text,0));
 select * into v_customer from public.customers where id=p_customer and owner_id=v_user for share;
 if not found then raise exception 'debt_customer_unavailable'; end if;
 for v_stock in select (x->>'product_id')::uuid as product_id,sum((x->>'quantity_units')::bigint) as required from jsonb_array_elements(v_lines) x group by (x->>'product_id')::uuid loop
  select quantity_units into v_after from public.product_stock where product_id=v_stock.product_id and owner_id=v_user for update;
  if not found or v_after<v_stock.required then raise exception 'sale_insufficient_stock'; end if;
 end loop;
 insert into public.customer_balances(customer_id,owner_id,balance) values(p_customer,v_user,0) on conflict(customer_id) do nothing;
 select balance+v_debt into v_debt_after from public.customer_balances where customer_id=p_customer and owner_id=v_user for update;
 if v_debt_after>100000000000000 then raise exception 'debt_balance_limit'; end if;
 update public.customer_balances set balance=v_debt_after,updated_at=now() where customer_id=p_customer and owner_id=v_user;
 insert into public.debt_entries(id,owner_id,customer_id,customer_name,kind,amount,delta,balance_after,note,request_payload,sale_id)
 values(v_debt_id,v_user,p_customer,v_customer.name,'charge',v_debt,v_debt,v_debt_after,coalesce(nullif(btrim(p_note),''),'قەرزی فرۆشتن'),jsonb_build_object('sale_id',p_id),p_id);
 insert into public.sales(id,owner_id,customer_name,note,subtotal,discount,total,received,change_due,lines,request_payload,payment_mode,customer_id,debt_amount,debt_entry_id)
 values(p_id,v_user,v_customer.name,btrim(coalesce(p_note,'')),v_subtotal,p_discount,v_subtotal-p_discount,p_received,0,v_lines,v_payload,'credit',p_customer,v_debt,v_debt_id)
 returning * into v_sale;
 for v_line in select value from jsonb_array_elements(v_lines) loop
  v_index:=v_index+1;
  v_qty:=(v_line->>'quantity_units')::bigint;
  update public.product_stock set quantity_units=quantity_units-v_qty,updated_at=now()
   where product_id=(v_line->>'product_id')::uuid and owner_id=v_user and quantity_units>=v_qty returning quantity_units into v_after;
  if not found then raise exception 'sale_insufficient_stock'; end if;
  insert into public.stock_movements(owner_id,product_id,sale_id,line_no,delta_units,balance_after)
   values(v_user,(v_line->>'product_id')::uuid,p_id,v_index,-v_qty,v_after);
 end loop;
 if p_received>0 then
 perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
 insert into public.cash_accounts(owner_id,balance) values(v_user,p_received)
  on conflict(owner_id) do update set balance=public.cash_accounts.balance+excluded.balance,updated_at=now() returning balance into v_cash_after;
 insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,sale_id,note,request_payload)
 values(v_user,'sale',p_received,p_received,v_cash_after,p_id,'',jsonb_build_object('sale_id',p_id));
 end if;
 return to_jsonb(v_sale)-'owner_id'-'request_payload';
end $$;


revoke all on function private.post_credit_sale(uuid,jsonb,bigint,bigint,uuid,text) from public,anon,authenticated;
grant execute on function private.post_credit_sale(uuid,jsonb,bigint,bigint,uuid,text) to authenticated;
create function public.post_credit_sale(p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer uuid,p_note text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.post_credit_sale(p_id,p_items,p_discount,p_received,p_customer,p_note);
$$;
revoke all on function public.post_credit_sale(uuid,jsonb,bigint,bigint,uuid,text) from public,anon,authenticated;
grant execute on function public.post_credit_sale(uuid,jsonb,bigint,bigint,uuid,text) to authenticated;
notify pgrst,'reload schema';
