create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.sales (
 id uuid primary key,
 receipt_no bigint generated always as identity unique,
 owner_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 currency text not null default 'IQD' check(currency='IQD'),
 customer_name text not null default '' check(char_length(customer_name)<=100),
 note text not null default '' check(char_length(note)<=500),
 subtotal bigint not null check(subtotal between 0 and 100000000000000),
 discount bigint not null check(discount>=0 and discount<=subtotal),
 total bigint not null check(total=subtotal-discount),
 received bigint not null check(received>=total and received<=100000000000000),
 change_due bigint not null check(change_due=received-total),
 lines jsonb not null check(jsonb_typeof(lines)='array' and jsonb_array_length(lines) between 1 and 200),
 request_payload jsonb not null
);
create index sales_owner_created_idx on public.sales(owner_id,created_at desc,id);
alter table public.sales enable row level security;
revoke all on public.sales from anon,authenticated;
grant select on public.sales to authenticated;
revoke all on sequence public.sales_receipt_no_seq from anon,authenticated;
create policy sales_read_own on public.sales for select to authenticated using ((select auth.uid())=owner_id);

create function private.post_cash_sale(p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer text,p_note text)
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
 insert into public.sales(id,owner_id,customer_name,note,subtotal,discount,total,received,change_due,lines,request_payload)
 values(p_id,v_user,btrim(coalesce(p_customer,'')),btrim(coalesce(p_note,'')),v_subtotal,p_discount,v_subtotal-p_discount,p_received,p_received-(v_subtotal-p_discount),v_lines,v_payload)
 returning * into v_sale;
 return to_jsonb(v_sale)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_cash_sale(uuid,jsonb,bigint,bigint,text,text) from public,anon,authenticated;
grant execute on function private.post_cash_sale(uuid,jsonb,bigint,bigint,text,text) to authenticated;

create function public.post_cash_sale(p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer text default '',p_note text default '')
returns jsonb language sql security invoker set search_path='' as $$
 select private.post_cash_sale(p_id,p_items,p_discount,p_received,p_customer,p_note);
$$;
revoke all on function public.post_cash_sale(uuid,jsonb,bigint,bigint,text,text) from public,anon,authenticated;
grant execute on function public.post_cash_sale(uuid,jsonb,bigint,bigint,text,text) to authenticated;
notify pgrst,'reload schema';
