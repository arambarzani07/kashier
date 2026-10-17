create or replace function public.get_sales_product_report(p_from date,p_to date) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_start timestamptz;v_end timestamptz;v_rows jsonb;v_summary jsonb;
begin
 if auth.uid() is null then raise exception 'sales_report_auth_required';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>365 then raise exception 'sales_report_invalid_range';end if;
 v_start:=p_from::timestamp at time zone 'Asia/Baghdad';v_end:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 with events as materialized(
 select 'sale'::text as kind,id,created_at,subtotal::numeric as subtotal,discount::numeric as discount,lines from public.sales where owner_id=auth.uid() and created_at>=v_start and created_at<v_end
 union all select 'reversal',r.id,r.created_at,s.subtotal::numeric,s.discount::numeric,r.lines from public.sale_reversals r join public.sales s on s.id=r.sale_id and s.owner_id=auth.uid() where r.owner_id=auth.uid() and r.created_at>=v_start and r.created_at<v_end
 union all select 'partial',id,created_at,total::numeric,0::numeric,lines from public.sale_returns where owner_id=auth.uid() and created_at>=v_start and created_at<v_end),
 expanded as (select e.kind,e.id,e.created_at,e.subtotal,e.discount,l.ordinality,(l.value->>'product_id')::uuid as product_id,l.value->>'name' as name,l.value->>'barcode' as barcode,(l.value->>'quantity_units')::numeric as qty,(l.value->>'line_total')::numeric as gross from events e cross join lateral jsonb_array_elements(e.lines) with ordinality l(value,ordinality)),
 cumulative as (select *,sum(gross) over(partition by kind,id order by ordinality rows unbounded preceding) as cumulative_gross from expanded),
 allocated as (select *,gross-case when subtotal=0 then 0 else div(discount*cumulative_gross,subtotal)-div(discount*(cumulative_gross-gross),subtotal) end as net from cumulative),
 totals as (select product_id,
 coalesce(sum(qty) filter(where kind='sale'),0) as sold_units,coalesce(sum(qty) filter(where kind<>'sale'),0) as returned_units,
 coalesce(sum(net) filter(where kind='sale'),0) as sold_total,coalesce(sum(net) filter(where kind<>'sale'),0) as returned_total,
 count(distinct id) filter(where kind='sale') as receipt_count,max(created_at) as last_activity_at from allocated group by product_id),
 names as (select distinct on(product_id) product_id,name,barcode from allocated order by product_id,created_at desc,kind desc,id desc,ordinality desc),
 grouped as (select t.product_id,n.name,n.barcode,t.sold_units::text as sold_units,t.returned_units::text as returned_units,(t.sold_units-t.returned_units)::text as net_units,t.sold_total::text as sold_total,t.returned_total::text as returned_total,(t.sold_total-t.returned_total)::text as net_total,t.receipt_count::text as receipt_count,t.last_activity_at from totals t join names n using(product_id) order by n.name,t.product_id limit 5001)
 select coalesce(jsonb_agg(to_jsonb(grouped) order by grouped.name,grouped.product_id),'[]'::jsonb),
 (select jsonb_build_object('receipt_count',count(*) filter(where kind='sale')::text,'return_count',count(*) filter(where kind<>'sale')::text,'gross',coalesce(sum(subtotal) filter(where kind='sale'),0)::text,'discounts',coalesce(sum(discount) filter(where kind='sale'),0)::text,'sold_total',coalesce(sum(subtotal-discount) filter(where kind='sale'),0)::text,'returned_total',coalesce(sum(subtotal-discount) filter(where kind<>'sale'),0)::text,'net_total',(coalesce(sum(subtotal-discount) filter(where kind='sale'),0)-coalesce(sum(subtotal-discount) filter(where kind<>'sale'),0))::text) from events)
 into v_rows,v_summary from grouped;
 if jsonb_array_length(v_rows)>5000 then raise exception 'sales_report_too_many_rows';end if;
 return jsonb_build_object('from',p_from,'to',p_to,'timezone','Asia/Baghdad','currency','IQD','generated_at',statement_timestamp(),'count',jsonb_array_length(v_rows),'summary',v_summary,'rows',v_rows);
end $$;
revoke all on function public.get_sales_product_report(date,date) from public,anon,authenticated;
grant execute on function public.get_sales_product_report(date,date) to authenticated;
notify pgrst,'reload schema';
