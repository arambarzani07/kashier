create function public.get_product_profile(p_product uuid,p_page integer default 0) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();p public.stock_catalog%rowtype;v_count bigint;v_rows jsonb;
begin
 if v_user is null then raise exception 'product_profile_auth_required';end if;
 if p_product is null or p_page is null or p_page<0 or p_page>1000000 then raise exception 'product_profile_invalid_request';end if;
 select * into p from public.stock_catalog where id=p_product;
 if not found then raise exception 'product_profile_unavailable';end if;
 select count(*) into v_count from public.stock_movements where product_id=p_product and owner_id=v_user;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.position),'[]'::jsonb) into v_rows from (
  select row_number() over(order by m.movement_no desc) as position,m.id,m.movement_no::text,m.created_at,m.delta_units::text,m.balance_after::text,
   case when m.adjustment_id is not null then case when a.kind='waste' then 'waste' else 'count' end
    when m.purchase_id is not null then 'purchase' when m.sale_id is not null then 'sale'
    when m.reversal_id is not null then 'sale_full' when m.return_id is not null then 'sale_partial'
    when m.purchase_reversal_id is not null then 'purchase_full' when m.purchase_return_id is not null then 'purchase_partial' end as source,
   coalesce(m.adjustment_id,m.purchase_id,m.sale_id,m.reversal_id,m.return_id,m.purchase_reversal_id,m.purchase_return_id) as source_id,
   a.note
  from public.stock_movements m left join public.stock_adjustments a on a.id=m.adjustment_id and a.owner_id=v_user
  where m.product_id=p_product and m.owner_id=v_user order by m.movement_no desc limit 50 offset p_page::bigint*50
 ) x;
 return jsonb_build_object('product',jsonb_build_object('id',p.id,'name',p.name,'barcode',p.barcode,'sale_price',p.sale_price::text,'quantity_units',p.quantity_units::text,'stock_version',p.stock_version,'created_at',p.created_at),
  'count',v_count::text,'page',p_page,'page_size',50,'rows',v_rows,'generated_at',statement_timestamp(),'timezone','Asia/Baghdad','currency','IQD');
end $$;
revoke all on function public.get_product_profile(uuid,integer) from public,anon,authenticated;
grant execute on function public.get_product_profile(uuid,integer) to authenticated;
notify pgrst,'reload schema';
