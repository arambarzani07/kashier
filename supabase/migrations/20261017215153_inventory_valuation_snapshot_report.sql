-- Read-only current stock value and missing-cost coverage, from one owner-scoped snapshot.
create function public.get_inventory_valuation(p_query text default '',p_include_empty boolean default false) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_query text:=btrim(coalesce(p_query,''));v_rows jsonb;v_count bigint;v_known bigint;v_value numeric;begin
 if v_user is null then raise exception 'valuation_auth_required';end if;
 if char_length(v_query)>100 or p_include_empty is null then raise exception 'valuation_invalid_filters';end if;
 -- Filter first, then cap; never export a silently truncated inventory valuation.
 if (select count(*) from public.products p left join public.product_stock s on s.product_id=p.id and s.owner_id=v_user where p.owner_id=v_user and(p_include_empty or coalesce(s.quantity_units,0)>0) and(v_query='' or strpos(lower(p.name),lower(v_query))>0 or strpos(lower(coalesce(p.barcode,'')),lower(v_query))>0))>5000 then raise exception 'valuation_too_many_rows';end if;
 if exists(select 1 from public.products p left join public.product_stock s on s.product_id=p.id and s.owner_id=v_user join public.inventory_cost_state c on c.product_id=p.id and c.owner_id=v_user where p.owner_id=v_user and(p_include_empty or coalesce(s.quantity_units,0)>0) and(v_query='' or strpos(lower(p.name),lower(v_query))>0 or strpos(lower(coalesce(p.barcode,'')),lower(v_query))>0) and c.quantity_units<>coalesce(s.quantity_units,0)) then raise exception 'valuation_stock_mismatch';end if;
 with filtered as(
  select p.id,p.name,p.barcode,coalesce(s.quantity_units,0) quantity_units,
   case when coalesce(s.quantity_units,0)=0 then 0::numeric else c.value_iqd end value_iqd,
   case when coalesce(s.quantity_units,0)=0 then 'empty' when c.value_iqd is null then 'unknown' else 'known' end coverage
  from public.products p left join public.product_stock s on s.product_id=p.id and s.owner_id=v_user left join public.inventory_cost_state c on c.product_id=p.id and c.owner_id=v_user
  where p.owner_id=v_user and(p_include_empty or coalesce(s.quantity_units,0)>0) and(v_query='' or strpos(lower(p.name),lower(v_query))>0 or strpos(lower(coalesce(p.barcode,'')),lower(v_query))>0)
 )
 select coalesce(jsonb_agg(jsonb_build_object('product_id',id,'name',name,'barcode',barcode,'quantity_units',quantity_units::text,'value_iqd',value_iqd::text,'coverage',coverage) order by case when coverage='unknown' then 0 else 1 end,name,id),'[]'::jsonb),count(*),count(value_iqd),coalesce(sum(value_iqd),0)
 into v_rows,v_count,v_known,v_value from filtered;
 return jsonb_build_object('scope','owner-inventory-valuation-v1','owner_id',v_user,'currency','IQD','timezone','Asia/Baghdad','policy','moving-average-whole-iqd-v1','generated_at',statement_timestamp(),'query',v_query,'include_empty',p_include_empty,'count',v_count,'known_count',v_known,'unknown_count',v_count-v_known,'known_value',v_value::text,'complete',v_count=v_known,'rows',v_rows);
end $$;
revoke all on function public.get_inventory_valuation(text,boolean) from public,anon,authenticated;
grant execute on function public.get_inventory_valuation(text,boolean) to authenticated;
notify pgrst,'reload schema';
