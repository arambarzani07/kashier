create table public.stock_adjustments (
 id uuid primary key,
 adjustment_no bigint generated always as identity unique,
 owner_id uuid not null references auth.users(id),
 product_id uuid not null references public.products(id),
 created_at timestamptz not null default now(),
 product_name text not null,
 barcode text,
 before_units bigint not null check(before_units between 0 and 1000000000000),
 after_units bigint not null check(after_units between 0 and 1000000000000),
 delta_units bigint not null check(delta_units<>0 and delta_units=after_units-before_units),
 expected_version bigint not null check(expected_version>=0),
 note text not null check(char_length(btrim(note)) between 1 and 500),
 request_payload jsonb not null
);
create index stock_adjustments_owner_created_idx on public.stock_adjustments(owner_id,created_at desc,id);
create index stock_adjustments_product_created_idx on public.stock_adjustments(product_id,created_at desc,id);
alter table public.stock_adjustments enable row level security;
revoke all on public.stock_adjustments from public,anon,authenticated;
revoke all on sequence public.stock_adjustments_adjustment_no_seq from public,anon,authenticated;
grant select on public.stock_adjustments to authenticated;
create policy stock_adjustments_read_own on public.stock_adjustments for select to authenticated using ((select auth.uid())=owner_id);
alter table public.stock_movements add column adjustment_id uuid unique references public.stock_adjustments(id);
alter table public.stock_movements drop constraint stock_movements_source_check;
alter table public.stock_movements add constraint stock_movements_source_check check(
 (adjustment_id is null and purchase_id is not null and sale_id is null and reversal_id is null and return_id is null and delta_units>0)
 or (adjustment_id is null and purchase_id is null and sale_id is not null and reversal_id is null and return_id is null and delta_units<0)
 or (adjustment_id is null and purchase_id is null and sale_id is null and reversal_id is not null and return_id is null and delta_units>0)
 or (adjustment_id is null and purchase_id is null and sale_id is null and reversal_id is null and return_id is not null and delta_units>0)
 or (adjustment_id is not null and purchase_id is null and sale_id is null and reversal_id is null and return_id is null and line_no=1)
);
create index stock_movements_product_version_idx on public.stock_movements(product_id,movement_no desc);
create or replace view public.stock_catalog with(security_invoker=true) as
 select p.id,p.name,p.barcode,p.sale_price,p.created_at,coalesce(s.quantity_units,0)::bigint as quantity_units,
 coalesce((select max(m.movement_no) from public.stock_movements m where m.product_id=p.id and m.owner_id=p.owner_id),0)::text as stock_version
 from public.products p left join public.product_stock s on s.product_id=p.id and s.owner_id=p.owner_id
 where p.owner_id=(select auth.uid());
create function private.post_stock_adjustment(p_id uuid,p_product uuid,p_expected_units bigint,p_expected_version bigint,p_counted_units bigint,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_payload jsonb;v_entry public.stock_adjustments%rowtype;v_product public.products%rowtype;v_before bigint;v_version bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='adjustment_auth_required';end if;
 if p_id is null or p_product is null or p_expected_units is null or p_expected_version is null or p_counted_units is null or p_expected_units not between 0 and 1000000000000 or p_counted_units not between 0 and 1000000000000 or p_expected_version<0 then raise exception 'adjustment_invalid_quantity';end if;
 if p_note is null or char_length(btrim(p_note)) not between 1 and 500 then raise exception 'adjustment_note_required';end if;
 v_payload:=jsonb_build_object('product',p_product,'expected_units',p_expected_units,'expected_version',p_expected_version,'counted_units',p_counted_units,'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended('kashier.stock-adjustment.'||p_id::text,0));
 select * into v_entry from public.stock_adjustments where id=p_id;
 if found then
  if v_entry.owner_id<>v_user or v_entry.request_payload<>v_payload then raise exception 'adjustment_request_conflict';end if;
  return to_jsonb(v_entry)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 select * into v_product from public.products where id=p_product and owner_id=v_user for share;
 if not found then raise exception 'adjustment_product_unavailable';end if;
 select quantity_units into v_before from public.product_stock where product_id=p_product and owner_id=v_user for update;
 v_before:=coalesce(v_before,0);
 select coalesce(max(movement_no),0) into v_version from public.stock_movements where product_id=p_product and owner_id=v_user;
 if v_before<>p_expected_units or v_version<>p_expected_version then raise exception 'adjustment_stock_changed';end if;
 if p_counted_units=v_before then raise exception 'adjustment_no_change';end if;
 insert into public.stock_adjustments(id,owner_id,product_id,product_name,barcode,before_units,after_units,delta_units,expected_version,note,request_payload)
 values(p_id,v_user,p_product,v_product.name,v_product.barcode,v_before,p_counted_units,p_counted_units-v_before,v_version,btrim(p_note),v_payload) returning * into v_entry;
 insert into public.product_stock(product_id,owner_id,quantity_units) values(p_product,v_user,p_counted_units)
 on conflict(product_id) do update set quantity_units=excluded.quantity_units,updated_at=now() where public.product_stock.owner_id=v_user;
 if not found then raise exception 'adjustment_product_unavailable';end if;
 insert into public.stock_movements(owner_id,product_id,adjustment_id,line_no,delta_units,balance_after) values(v_user,p_product,p_id,1,p_counted_units-v_before,p_counted_units);
 return to_jsonb(v_entry)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_stock_adjustment(uuid,uuid,bigint,bigint,bigint,text) from public,anon,authenticated;
grant execute on function private.post_stock_adjustment(uuid,uuid,bigint,bigint,bigint,text) to authenticated;
create function public.post_stock_adjustment(p_id uuid,p_product uuid,p_expected_units bigint,p_expected_version bigint,p_counted_units bigint,p_note text) returns jsonb language sql security invoker set search_path='' as $$select private.post_stock_adjustment(p_id,p_product,p_expected_units,p_expected_version,p_counted_units,p_note)$$;
revoke all on function public.post_stock_adjustment(uuid,uuid,bigint,bigint,bigint,text) from public,anon,authenticated;
grant execute on function public.post_stock_adjustment(uuid,uuid,bigint,bigint,bigint,text) to authenticated;
notify pgrst,'reload schema';
