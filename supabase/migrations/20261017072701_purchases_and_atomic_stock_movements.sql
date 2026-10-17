create table public.purchases (
 id uuid primary key,
 receipt_no bigint generated always as identity unique,
 owner_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 supplier_name text not null default '' check(char_length(supplier_name)<=100),
 invoice_no text not null default '' check(char_length(invoice_no)<=64),
 note text not null default '' check(char_length(note)<=500),
 currency text not null default 'IQD' check(currency='IQD'),
 total bigint not null check(total between 0 and 100000000000000),
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 200),
 request_payload jsonb not null
);
create index purchases_owner_created_idx on public.purchases(owner_id,created_at desc,id);
alter table public.purchases enable row level security;
revoke all on public.purchases from anon,authenticated;
revoke all on sequence public.purchases_receipt_no_seq from anon,authenticated;
grant select on public.purchases to authenticated;
create policy purchases_read_own on public.purchases for select to authenticated using ((select auth.uid())=owner_id);

create table public.product_stock (
 product_id uuid primary key references public.products(id),
 owner_id uuid not null references auth.users(id),
 quantity_units bigint not null check(quantity_units between 0 and 1000000000000),
 updated_at timestamptz not null default now()
);
create index product_stock_owner_idx on public.product_stock(owner_id);
alter table public.product_stock enable row level security;
revoke all on public.product_stock from anon,authenticated;
grant select on public.product_stock to authenticated;
create policy stock_read_own on public.product_stock for select to authenticated using ((select auth.uid())=owner_id);

create table public.stock_movements (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id),
 product_id uuid not null references public.products(id),
 created_at timestamptz not null default now(),
 purchase_id uuid references public.purchases(id),
 sale_id uuid references public.sales(id),
 line_no integer not null check(line_no between 1 and 200),
 delta_units bigint not null check(delta_units<>0),
 balance_after bigint not null check(balance_after between 0 and 1000000000000),
 check((purchase_id is not null and sale_id is null and delta_units>0) or (sale_id is not null and purchase_id is null and delta_units<0)),
 unique(purchase_id,line_no),
 unique(sale_id,line_no)
);
create index stock_movements_owner_created_idx on public.stock_movements(owner_id,created_at desc,id);
create index stock_movements_product_created_idx on public.stock_movements(product_id,created_at desc,id);
alter table public.stock_movements enable row level security;
revoke all on public.stock_movements from anon,authenticated;
grant select on public.stock_movements to authenticated;
create policy movements_read_own on public.stock_movements for select to authenticated using ((select auth.uid())=owner_id);

create view public.stock_catalog with(security_invoker=true) as
 select p.id,p.name,p.barcode,p.sale_price,p.created_at,coalesce(s.quantity_units,0)::bigint as quantity_units
 from public.products p left join public.product_stock s on s.product_id=p.id and s.owner_id=p.owner_id
 where p.owner_id=(select auth.uid());
revoke all on public.stock_catalog from anon,authenticated;
grant select on public.stock_catalog to authenticated;

create function private.post_purchase(p_id uuid,p_items jsonb,p_supplier text,p_invoice text,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_payload jsonb;
 v_receipt public.purchases%rowtype;
 v_product public.products%rowtype;
 v_line jsonb;
 v_lines jsonb:='[]'::jsonb;
 v_qty bigint;
 v_cost bigint;
 v_total bigint:=0;
 v_line_total bigint;
 v_after bigint;
 v_index integer:=0;
begin
 if v_user is null then raise exception using errcode='28000',message='purchase_auth_required'; end if;
 if p_id is null or p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'purchase_invalid_items'; end if;
 if jsonb_array_length(p_items) not between 1 and 200 then raise exception 'purchase_invalid_items'; end if;
 if char_length(coalesce(p_supplier,''))>100 or char_length(coalesce(p_invoice,''))>64 or char_length(coalesce(p_note,''))>500 then raise exception 'purchase_invalid_text'; end if;
 v_payload:=jsonb_build_object('items',p_items,'supplier',btrim(coalesce(p_supplier,'')),'invoice',btrim(coalesce(p_invoice,'')),'note',btrim(coalesce(p_note,'')));
 perform pg_advisory_xact_lock(hashtextextended('kashier.purchase.'||p_id::text,0));
 select * into v_receipt from public.purchases where id=p_id;
 if found then
  if v_receipt.owner_id<>v_user or v_receipt.request_payload<>v_payload then raise exception 'purchase_request_conflict'; end if;
  return to_jsonb(v_receipt)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 for v_line in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(v_line)<>'object' or coalesce(v_line->>'quantity_units','') !~ '^[0-9]{1,8}$' or coalesce(v_line->>'unit_cost','') !~ '^[0-9]{1,10}$' then raise exception 'purchase_invalid_items'; end if;
  v_qty:=(v_line->>'quantity_units')::bigint;v_cost:=(v_line->>'unit_cost')::bigint;
  if v_qty not between 1 and 10000000 or v_cost not between 1 and 1000000000 then raise exception 'purchase_invalid_items'; end if;
  select * into v_product from public.products where id=(v_line->>'product_id')::uuid and owner_id=v_user for share;
  if not found then raise exception 'purchase_product_unavailable'; end if;
  v_line_total:=(v_qty*v_cost+500)/1000;
  v_total:=v_total+v_line_total;
  if v_total>100000000000000 then raise exception 'purchase_total_limit'; end if;
  v_lines:=v_lines||jsonb_build_array(jsonb_build_object('product_id',v_product.id,'name',v_product.name,'barcode',v_product.barcode,'quantity_units',v_qty,'unit_cost',v_cost,'line_total',v_line_total));
 end loop;
 insert into public.purchases(id,owner_id,supplier_name,invoice_no,note,total,lines,request_payload)
 values(p_id,v_user,btrim(coalesce(p_supplier,'')),btrim(coalesce(p_invoice,'')),btrim(coalesce(p_note,'')),v_total,v_lines,v_payload) returning * into v_receipt;
 for v_line in select value from jsonb_array_elements(v_lines) loop
  v_index:=v_index+1;v_qty:=(v_line->>'quantity_units')::bigint;
  insert into public.product_stock(product_id,owner_id,quantity_units)
   values((v_line->>'product_id')::uuid,v_user,v_qty)
   on conflict(product_id) do update set quantity_units=public.product_stock.quantity_units+excluded.quantity_units,updated_at=now()
    where public.product_stock.owner_id=v_user returning quantity_units into v_after;
  if not found then raise exception 'purchase_stock_conflict'; end if;
  insert into public.stock_movements(owner_id,product_id,purchase_id,line_no,delta_units,balance_after)
   values(v_user,(v_line->>'product_id')::uuid,p_id,v_index,v_qty,v_after);
 end loop;
 return to_jsonb(v_receipt)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_purchase(uuid,jsonb,text,text,text) from public,anon,authenticated;
grant execute on function private.post_purchase(uuid,jsonb,text,text,text) to authenticated;
create function public.post_purchase(p_id uuid,p_items jsonb,p_supplier text default '',p_invoice text default '',p_note text default '')
returns jsonb language sql security invoker set search_path='' as $$
 select private.post_purchase(p_id,p_items,p_supplier,p_invoice,p_note);
$$;
revoke all on function public.post_purchase(uuid,jsonb,text,text,text) from public,anon,authenticated;
grant execute on function public.post_purchase(uuid,jsonb,text,text,text) to authenticated;

create or replace function private.post_cash_sale(p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer text,p_note text)
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
begin
 if v_user is null then raise exception using errcode='28000',message='sale_auth_required'; end if;
 if p_id is null or p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'sale_invalid_items'; end if;
 if jsonb_array_length(p_items) not between 1 and 200 then raise exception 'sale_invalid_items'; end if;
 if p_discount is null or p_received is null or p_discount<0 or p_received<0 or p_received>100000000000000 then raise exception 'sale_invalid_money'; end if;
 if char_length(coalesce(p_customer,''))>100 or char_length(coalesce(p_note,''))>500 then raise exception 'sale_invalid_text'; end if;
 v_payload := jsonb_build_object('items',p_items,'discount',p_discount,'received',p_received,'customer',btrim(coalesce(p_customer,'')),'note',btrim(coalesce(p_note,'')));
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
 if p_received<v_subtotal-p_discount then raise exception 'sale_payment_shortfall'; end if;
 for v_stock in select (x->>'product_id')::uuid as product_id,sum((x->>'quantity_units')::bigint) as required from jsonb_array_elements(v_lines) x group by (x->>'product_id')::uuid loop
  select quantity_units into v_after from public.product_stock where product_id=v_stock.product_id and owner_id=v_user for update;
  if not found or v_after<v_stock.required then raise exception 'sale_insufficient_stock'; end if;
 end loop;
 insert into public.sales(id,owner_id,customer_name,note,subtotal,discount,total,received,change_due,lines,request_payload)
 values(p_id,v_user,btrim(coalesce(p_customer,'')),btrim(coalesce(p_note,'')),v_subtotal,p_discount,v_subtotal-p_discount,p_received,p_received-(v_subtotal-p_discount),v_lines,v_payload)
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
 return to_jsonb(v_sale)-'owner_id'-'request_payload';
end $$;

notify pgrst,'reload schema';
