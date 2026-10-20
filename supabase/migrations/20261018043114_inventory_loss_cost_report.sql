-- Read-only historical waste and negative stock-count cost coverage.
create function public.get_inventory_loss_report(p_from date,p_to date) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_start timestamptz;v_end timestamptz;v_rows jsonb;v_count bigint;v_known bigint;v_cost numeric;v_waste_count bigint;v_waste_known bigint;v_waste_cost numeric;v_short_count bigint;v_short_known bigint;v_short_cost numeric;begin
 if v_user is null then raise exception 'loss_auth_required';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>365 or p_from<date '2000-01-01' or p_to>date '2100-12-31' then raise exception 'loss_invalid_range';end if;
 v_start:=p_from::timestamp at time zone 'Asia/Baghdad';v_end:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 if (select count(*) from public.stock_adjustments a where a.owner_id=v_user and a.delta_units<0 and a.created_at>=v_start and a.created_at<v_end)>5000 then raise exception 'loss_too_many_rows';end if;
 -- Missing legacy cost is explicit; missing or inconsistent physical history is an error.
 if exists(select 1 from public.stock_adjustments a left join public.stock_movements m on m.adjustment_id=a.id and m.owner_id=v_user
  left join public.inventory_cost_movements c on c.id=m.id and c.owner_id=v_user
  where a.owner_id=v_user and a.delta_units<0 and a.created_at>=v_start and a.created_at<v_end and
   (m.id is null or m.product_id<>a.product_id or m.delta_units<>a.delta_units or m.balance_after<>a.after_units or m.line_no<>1 or m.created_at<>a.created_at
    or c.id is not null and(c.product_id<>a.product_id or c.quantity_units<>m.delta_units or c.created_at<>m.created_at or c.value_delta>0))) then raise exception 'loss_incomplete_stock_history';end if;
 with rows as (
  select a.id,a.adjustment_no,a.product_id,a.product_name,a.barcode,a.created_at,a.note,a.kind,-a.delta_units quantity_units,
   m.movement_no,-c.value_delta cost_iqd,case when c.id is null then 'legacy-no-cost-snapshot' else c.coverage end coverage
  from public.stock_adjustments a join public.stock_movements m on m.adjustment_id=a.id and m.owner_id=v_user
  left join public.inventory_cost_movements c on c.id=m.id and c.owner_id=v_user
  where a.owner_id=v_user and a.delta_units<0 and a.created_at>=v_start and a.created_at<v_end
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'adjustment_no',adjustment_no::text,'movement_no',movement_no::text,'created_at',created_at,'day',(created_at at time zone 'Asia/Baghdad')::date::text,'kind',case when kind='waste' then 'waste' else 'count_shortage' end,'product_id',product_id,'name',product_name,'barcode',barcode,'quantity_units',quantity_units::text,'cost_iqd',cost_iqd::text,'coverage',coverage,'note',note) order by movement_no),'[]'::jsonb),count(*),count(cost_iqd),coalesce(sum(cost_iqd),0),
 count(*) filter(where kind='waste'),count(cost_iqd) filter(where kind='waste'),coalesce(sum(cost_iqd) filter(where kind='waste'),0),
 count(*) filter(where kind='count'),count(cost_iqd) filter(where kind='count'),coalesce(sum(cost_iqd) filter(where kind='count'),0)
 into v_rows,v_count,v_known,v_cost,v_waste_count,v_waste_known,v_waste_cost,v_short_count,v_short_known,v_short_cost from rows;
 return jsonb_build_object('scope','owner-inventory-loss-v1','owner_id',v_user,'currency','IQD','timezone','Asia/Baghdad','from',p_from::text,'to',p_to::text,'generated_at',statement_timestamp(),'policy','moving-average-whole-iqd-v1','count',v_count,'known_count',v_known,'known_cost',v_cost::text,'complete',v_count=v_known,
 'waste',jsonb_build_object('count',v_waste_count,'known_count',v_waste_known,'known_cost',v_waste_cost::text),
 'count_shortage',jsonb_build_object('count',v_short_count,'known_count',v_short_known,'known_cost',v_short_cost::text),'rows',v_rows);
end $$;
revoke all on function public.get_inventory_loss_report(date,date) from public,anon,authenticated;
grant execute on function public.get_inventory_loss_report(date,date) to authenticated;
notify pgrst,'reload schema';
