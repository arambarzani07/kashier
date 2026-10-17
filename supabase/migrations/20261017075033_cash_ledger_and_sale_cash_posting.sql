lock table public.sales in access exclusive mode;
do $$ begin if exists(select 1 from public.sales) then raise exception 'cash_initialization_requires_reconciliation'; end if; end $$;
create table public.cash_accounts (
 owner_id uuid primary key references auth.users(id),
 balance bigint not null default 0 check(balance between 0 and 100000000000000),
 updated_at timestamptz not null default now()
);
alter table public.cash_accounts enable row level security;
revoke all on public.cash_accounts from anon,authenticated;
grant select on public.cash_accounts to authenticated;
create policy cash_accounts_read_own on public.cash_accounts for select to authenticated using ((select auth.uid())=owner_id);
create table public.cash_movements (
 id uuid primary key default gen_random_uuid(),
 movement_no bigint generated always as identity unique,
 owner_id uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 kind text not null check(kind in ('sale','deposit','withdrawal','expense')),
 amount bigint not null check(amount between 0 and 100000000000000),
 delta bigint not null,
 balance_after bigint not null check(balance_after between 0 and 100000000000000),
 sale_id uuid unique references public.sales(id),
 note text not null default '' check(char_length(note)<=500),
 request_payload jsonb not null,
 check(delta=case when kind in ('sale','deposit') then amount else -amount end),
 check((kind='sale' and sale_id is not null) or (kind<>'sale' and sale_id is null and amount>0 and char_length(btrim(note))>0))
);
create index cash_movements_owner_order_idx on public.cash_movements(owner_id,movement_no desc);
alter table public.cash_movements enable row level security;
revoke all on public.cash_movements from anon,authenticated;
revoke all on sequence public.cash_movements_movement_no_seq from anon,authenticated;
grant select on public.cash_movements to authenticated;
create policy cash_movements_read_own on public.cash_movements for select to authenticated using ((select auth.uid())=owner_id);

create function private.post_cash_entry(p_id uuid,p_kind text,p_amount bigint,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_payload jsonb;v_entry public.cash_movements%rowtype;v_before bigint;v_after bigint;v_delta bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='cash_auth_required'; end if;
 if p_id is null or p_kind is null or p_kind not in ('deposit','withdrawal','expense') then raise exception 'cash_invalid_kind'; end if;
 if p_amount is null or p_amount not between 1 and 100000000000000 then raise exception 'cash_invalid_amount'; end if;
 if char_length(btrim(coalesce(p_note,''))) not between 1 and 500 then raise exception 'cash_note_required'; end if;
 v_payload:=jsonb_build_object('kind',p_kind,'amount',p_amount,'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended('kashier.cash-entry.'||p_id::text,0));
 select * into v_entry from public.cash_movements where id=p_id;
 if found then
  if v_entry.owner_id<>v_user or v_entry.request_payload<>v_payload or v_entry.kind='sale' then raise exception 'cash_request_conflict'; end if;
  return to_jsonb(v_entry)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
 insert into public.cash_accounts(owner_id,balance) values(v_user,0) on conflict(owner_id) do nothing;
 select balance into v_before from public.cash_accounts where owner_id=v_user for update;
 v_delta:=case when p_kind='deposit' then p_amount else -p_amount end;
 v_after:=v_before+v_delta;
 if v_after<0 then raise exception 'cash_insufficient_balance'; end if;
 if v_after>100000000000000 then raise exception 'cash_balance_limit'; end if;
 update public.cash_accounts set balance=v_after,updated_at=now() where owner_id=v_user;
 insert into public.cash_movements(id,owner_id,kind,amount,delta,balance_after,note,request_payload)
  values(p_id,v_user,p_kind,p_amount,v_delta,v_after,btrim(p_note),v_payload) returning * into v_entry;
 return to_jsonb(v_entry)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_cash_entry(uuid,text,bigint,text) from public,anon,authenticated;
grant execute on function private.post_cash_entry(uuid,text,bigint,text) to authenticated;
create function public.post_cash_entry(p_id uuid,p_kind text,p_amount bigint,p_note text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.post_cash_entry(p_id,p_kind,p_amount,p_note);
$$;
revoke all on function public.post_cash_entry(uuid,text,bigint,text) from public,anon,authenticated;
grant execute on function public.post_cash_entry(uuid,text,bigint,text) to authenticated;
create function public.get_cash_summary()
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
 'balance',coalesce((select balance from public.cash_accounts where owner_id=(select auth.uid())),0),
 'sales',coalesce(sum(amount) filter(where kind='sale'),0),
 'deposits',coalesce(sum(amount) filter(where kind='deposit'),0),
 'withdrawals',coalesce(sum(amount) filter(where kind='withdrawal'),0),
 'expenses',coalesce(sum(amount) filter(where kind='expense'),0),
 'count',count(*)
 ) from public.cash_movements where owner_id=(select auth.uid());
$$;
revoke all on function public.get_cash_summary() from public,anon,authenticated;
grant execute on function public.get_cash_summary() to authenticated;

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
 v_cash_after bigint;
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
 perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
 insert into public.cash_accounts(owner_id,balance) values(v_user,v_sale.total)
  on conflict(owner_id) do update set balance=public.cash_accounts.balance+excluded.balance,updated_at=now() returning balance into v_cash_after;
 insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,sale_id,note,request_payload)
 values(v_user,'sale',v_sale.total,v_sale.total,v_cash_after,p_id,'',jsonb_build_object('sale_id',p_id));
 return to_jsonb(v_sale)-'owner_id'-'request_payload';
end $$;


notify pgrst,'reload schema';
