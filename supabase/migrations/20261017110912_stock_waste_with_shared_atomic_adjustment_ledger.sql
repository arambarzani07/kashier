alter table public.stock_adjustments add column kind text not null default 'count' check(kind in ('count','waste'));
alter table public.stock_adjustments add constraint stock_adjustments_waste_direction check(kind<>'waste' or delta_units<0);
create index stock_adjustments_owner_kind_order_idx on public.stock_adjustments(owner_id,kind,adjustment_no desc);
create function private.post_inventory_adjustment(p_id uuid,p_product uuid,p_expected_units bigint,p_expected_version bigint,p_counted_units bigint,p_note text,p_kind text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_payload jsonb;v_entry public.stock_adjustments%rowtype;v_product public.products%rowtype;v_before bigint;v_version bigint;
begin
 if p_kind is null or p_kind not in ('count','waste') then raise exception 'adjustment_invalid_kind';end if;
 if v_user is null then raise exception using errcode='28000',message='adjustment_auth_required';end if;
 if p_id is null or p_product is null or p_expected_units is null or p_expected_version is null or p_counted_units is null or p_expected_units not between 0 and 1000000000000 or p_counted_units not between 0 and 1000000000000 or p_expected_version<0 then raise exception 'adjustment_invalid_quantity';end if;
 if p_note is null or char_length(btrim(p_note)) not between 1 and 500 then raise exception 'adjustment_note_required';end if;
 if p_kind='waste' and p_counted_units>=p_expected_units then raise exception 'waste_invalid_quantity';end if;
 v_payload:=jsonb_build_object('kind',p_kind,'product',p_product,'expected_units',p_expected_units,'expected_version',p_expected_version,'counted_units',p_counted_units,'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended('kashier.stock-adjustment.'||p_id::text,0));
 select * into v_entry from public.stock_adjustments where id=p_id;
 if found then
  if v_entry.owner_id<>v_user or (v_entry.request_payload||jsonb_build_object('kind',v_entry.kind))<>v_payload then raise exception 'adjustment_request_conflict';end if;
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
 insert into public.stock_adjustments(id,owner_id,product_id,product_name,barcode,before_units,after_units,delta_units,expected_version,note,request_payload,kind)
 values(p_id,v_user,p_product,v_product.name,v_product.barcode,v_before,p_counted_units,p_counted_units-v_before,v_version,btrim(p_note),v_payload,p_kind) returning * into v_entry;
 insert into public.product_stock(product_id,owner_id,quantity_units) values(p_product,v_user,p_counted_units)
 on conflict(product_id) do update set quantity_units=excluded.quantity_units,updated_at=now() where public.product_stock.owner_id=v_user;
 if not found then raise exception 'adjustment_product_unavailable';end if;
 insert into public.stock_movements(owner_id,product_id,adjustment_id,line_no,delta_units,balance_after) values(v_user,p_product,p_id,1,p_counted_units-v_before,p_counted_units);
 return to_jsonb(v_entry)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_inventory_adjustment(uuid,uuid,bigint,bigint,bigint,text,text) from public,anon,authenticated;
grant execute on function private.post_inventory_adjustment(uuid,uuid,bigint,bigint,bigint,text,text) to authenticated;
create or replace function private.post_stock_adjustment(p_id uuid,p_product uuid,p_expected_units bigint,p_expected_version bigint,p_counted_units bigint,p_note text) returns jsonb language sql security invoker set search_path='' as $$select private.post_inventory_adjustment(p_id,p_product,p_expected_units,p_expected_version,p_counted_units,p_note,'count')$$;
create function private.post_stock_waste(p_id uuid,p_product uuid,p_expected_units bigint,p_expected_version bigint,p_waste_units bigint,p_note text) returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if p_expected_units is null or p_expected_units not between 0 and 1000000000000 or p_waste_units is null or p_waste_units not between 1 and 1000000000000 then raise exception 'waste_invalid_quantity';end if;
 if p_waste_units>p_expected_units then raise exception 'waste_insufficient_stock';end if;
 return private.post_inventory_adjustment(p_id,p_product,p_expected_units,p_expected_version,p_expected_units-p_waste_units,p_note,'waste');
end $$;
revoke all on function private.post_stock_waste(uuid,uuid,bigint,bigint,bigint,text) from public,anon,authenticated;
grant execute on function private.post_stock_waste(uuid,uuid,bigint,bigint,bigint,text) to authenticated;
create function public.post_stock_waste(p_id uuid,p_product uuid,p_expected_units bigint,p_expected_version bigint,p_waste_units bigint,p_note text) returns jsonb language sql security invoker set search_path='' as $$select private.post_stock_waste(p_id,p_product,p_expected_units,p_expected_version,p_waste_units,p_note)$$;
revoke all on function public.post_stock_waste(uuid,uuid,bigint,bigint,bigint,text) from public,anon,authenticated;
grant execute on function public.post_stock_waste(uuid,uuid,bigint,bigint,bigint,text) to authenticated;
notify pgrst,'reload schema';
