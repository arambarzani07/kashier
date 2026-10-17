create function public.get_stocktake_snapshot(p_query text default '') returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_rows jsonb;v_query text:=btrim(coalesce(p_query,''));
begin
 if auth.uid() is null then raise exception 'stocktake_auth_required';end if;
 if char_length(v_query)>100 then raise exception 'stocktake_query_too_long';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.name,x.id),'[]'::jsonb) into v_rows
 from (select id,name,barcode,sale_price,quantity_units from public.stock_catalog
 where v_query='' or position(lower(v_query) in lower(name))>0 or position(lower(v_query) in lower(coalesce(barcode,'')))>0
 order by name,id limit 5001) x;
 if jsonb_array_length(v_rows)>5000 then raise exception 'stocktake_too_many_rows';end if;
 return jsonb_build_object('generated_at',statement_timestamp(),'query',v_query,'count',jsonb_array_length(v_rows),'rows',v_rows);
end $$;
revoke all on function public.get_stocktake_snapshot(text) from public,anon;
grant execute on function public.get_stocktake_snapshot(text) to authenticated;
notify pgrst,'reload schema';
