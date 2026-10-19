alter table public.store_cashiers add column can_credit boolean not null default false;
drop function public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text);
drop function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text);
create function private.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint,p_role text default 'cashier',p_credit boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r public.store_cashiers%rowtype;e public.staff_actions%rowtype;payload jsonb;old jsonb;result jsonb;k text;begin
 if u is null then raise exception 'staff_auth_required';end if;
 if p_credit is null or p_role is null or p_role not in ('cashier','manager') or p_id is null or p_member is null or p_member=u or p_discount is null or p_enabled is null or p_expected_version is null or p_expected_version<0 or char_length(btrim(coalesce(p_name,''))) not between 1 and 100 or char_length(btrim(coalesce(p_store,''))) not between 1 and 100 then raise exception 'staff_invalid_request';end if;
 payload:=jsonb_build_object('kind','save','member',p_member,'name',btrim(p_name),'store',btrim(p_store),'discount',p_discount,'enabled',p_enabled,'expected_version',p_expected_version,'role',p_role,'credit',p_credit);
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff-action.'||p_id::text,0));select * into e from public.staff_actions where id=p_id;
 if found then if e.actor_id<>u or e.owner_id<>u or (e.request_payload||jsonb_build_object('role',coalesce(e.request_payload->>'role','cashier'),'credit',coalesce((e.request_payload->>'credit')::boolean,false)))<>payload then raise exception 'staff_request_conflict';end if;return e.result_payload;end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||u::text,0));
 select * into r from public.store_cashiers where owner_id=u and member_id=p_member for update;old:=case when found then to_jsonb(r) else null end;
 if old is null then
  if p_expected_version<>0 then raise exception 'staff_changed';end if;
  if not exists(select 1 from auth.users where id=p_member) then raise exception 'staff_member_unavailable';end if;
  perform pg_advisory_xact_lock(hashtextextended('kashier.staff-member.'||p_member::text,0));
  if (select count(*) from public.store_cashiers where owner_id=u)>=50 or(select count(*) from public.store_cashiers where member_id=p_member)>=50 then raise exception 'staff_limit';end if;
  insert into public.store_cashiers(owner_id,member_id,member_name,store_name,can_discount,enabled,role,can_credit) values(u,p_member,btrim(p_name),btrim(p_store),p_discount,p_enabled,p_role,p_credit) returning * into r;k:='invite';
 else
  if r.version<>p_expected_version then raise exception 'staff_changed';end if;
  update public.store_cashiers set can_credit=p_credit,role=p_role,member_name=btrim(p_name),store_name=btrim(p_store),can_discount=p_discount,enabled=p_enabled,version=version+1,updated_at=now() where id=r.id returning * into r;k:='update';
 end if;
 result:=jsonb_build_object('id',p_id,'membership_id',r.id,'version',r.version::text);
 insert into public.staff_actions(id,owner_id,member_id,actor_id,membership_id,kind,before_state,after_state,request_payload,result_payload) values(p_id,u,p_member,u,r.id,k,old,to_jsonb(r),payload,result);return result;
end $$;
create function public.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint,p_role text default 'cashier',p_credit boolean default false) returns jsonb language sql security invoker set search_path='' as $$select private.save_store_cashier(p_id,p_member,p_name,p_store,p_discount,p_enabled,p_expected_version,p_role,p_credit);$$;
revoke all on function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean),public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean) from public,anon,authenticated;
grant execute on function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean),public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean) to authenticated;
create function private.post_credit_sale_for_owner(p_owner uuid,p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer uuid,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid := p_owner;
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
 if v_user is null or auth.uid() is null then raise exception using errcode='28000',message='sale_auth_required'; end if;
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


revoke all on function private.post_credit_sale_for_owner(uuid,uuid,jsonb,bigint,bigint,uuid,text) from public,anon,authenticated;
create or replace function private.post_credit_sale(p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer uuid,p_note text) returns jsonb language sql security definer set search_path='' as $$select private.post_credit_sale_for_owner(auth.uid(),p_id,p_items,p_discount,p_received,p_customer,p_note);$$;
create or replace function private.get_cashier_catalog(p_owner uuid,p_query text default '',p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;q text:=btrim(coalesce(p_query,''));rows jsonb;total bigint;begin
 r:=private.cashier_membership(p_owner);if p_offset is null or p_offset not between 0 and 1000000 or char_length(q)>100 then raise exception 'staff_invalid_request';end if;
 select count(*) into total from public.products p where p.owner_id=p_owner and(q='' or strpos(lower(p.name),lower(q))>0 or strpos(coalesce(p.barcode,''),q)>0);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.name,x.id),'[]'::jsonb) into rows from(select p.id,p.name,p.barcode,p.sale_price::text,coalesce(s.quantity_units,0)::text quantity_units from public.products p left join public.product_stock s on s.product_id=p.id and s.owner_id=p_owner where p.owner_id=p_owner and(q='' or strpos(lower(p.name),lower(q))>0 or strpos(coalesce(p.barcode,''),q)>0) order by p.name,p.id limit 50 offset p_offset)x;
 return jsonb_build_object('scope','cashier-catalog-v1','owner_id',p_owner,'actor_id',auth.uid(),'membership_id',r.id,'store_name',r.store_name,'member_name',r.member_name,'can_discount',r.can_discount,'can_credit',r.can_credit,'version',r.version::text,'query',q,'offset',p_offset,'total',total::text,'rows',rows);end $$;
create function private.post_cashier_credit_sale(p_owner uuid,p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer uuid,p_note text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;s public.sales%rowtype;result jsonb;begin
 if auth.uid() is null then raise exception 'staff_auth_required';end if;if p_owner is null or p_id is null then raise exception 'staff_invalid_request';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||p_owner::text,0));r:=private.cashier_membership(p_owner);
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale.'||p_id::text,0));select * into s from public.sales where id=p_id;
 if found and(s.owner_id<>p_owner or s.actor_id is distinct from auth.uid()) then raise exception 'staff_request_conflict';end if;
 -- Existing identical requests may be acknowledged after discount permission is withdrawn.
 if s.id is null and p_discount>0 and not r.can_discount then raise exception 'staff_discount_denied';end if;
 if s.id is null and not r.can_credit then raise exception 'staff_credit_denied';end if;
 result:=private.post_credit_sale_for_owner(p_owner,p_id,p_items,p_discount,p_received,p_customer,p_note);
 update public.sales set actor_name=r.member_name where id=p_id and actor_name is null;
 select * into s from public.sales where id=p_id;return to_jsonb(s)-'owner_id'-'request_payload';end $$;
create function private.get_cashier_customers(p_owner uuid,p_query text default '',p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;q text:=btrim(coalesce(p_query,''));rows jsonb;total bigint;begin
 r:=private.cashier_membership(p_owner);if not r.can_credit then raise exception 'staff_credit_denied';end if;
 if p_offset is null or p_offset not between 0 and 1000000 or char_length(q)>100 then raise exception 'staff_invalid_request';end if;
 select count(*) into total from public.customers c where c.owner_id=p_owner and(q='' or strpos(lower(c.name),lower(q))>0 or strpos(coalesce(c.phone,''),q)>0 or c.id::text=q);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.name,x.id),'[]'::jsonb) into rows from(select c.id,c.name,c.phone from public.customers c where c.owner_id=p_owner and(q='' or strpos(lower(c.name),lower(q))>0 or strpos(coalesce(c.phone,''),q)>0 or c.id::text=q) order by c.name,c.id limit 50 offset p_offset)x;
 return jsonb_build_object('scope','cashier-customers-v1','owner_id',p_owner,'actor_id',auth.uid(),'query',q,'offset',p_offset,'total',total::text,'rows',rows);end $$;
create function public.get_cashier_customers(p_owner uuid,p_query text default '',p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_customers(p_owner,p_query,p_offset);$$;
create function public.post_cashier_credit_sale(p_owner uuid,p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer uuid,p_note text) returns jsonb language sql security invoker set search_path='' as $$select private.post_cashier_credit_sale(p_owner,p_id,p_items,p_discount,p_received,p_customer,p_note);$$;
revoke all on function private.get_cashier_customers(uuid,text,integer),public.get_cashier_customers(uuid,text,integer),private.post_cashier_credit_sale(uuid,uuid,jsonb,bigint,bigint,uuid,text),public.post_cashier_credit_sale(uuid,uuid,jsonb,bigint,bigint,uuid,text) from public,anon,authenticated;
grant execute on function private.get_cashier_customers(uuid,text,integer),public.get_cashier_customers(uuid,text,integer),private.post_cashier_credit_sale(uuid,uuid,jsonb,bigint,bigint,uuid,text),public.post_cashier_credit_sale(uuid,uuid,jsonb,bigint,bigint,uuid,text) to authenticated;
notify pgrst,'reload schema';
