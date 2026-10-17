create function public.get_purchase_report(p_from date,p_to date) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_start timestamptz;v_end timestamptz;v_rows jsonb;v_summary jsonb;
begin
 if auth.uid() is null then raise exception 'purchase_report_auth_required';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>365 then raise exception 'purchase_report_invalid_range';end if;
 v_start:=p_from::timestamp at time zone 'Asia/Baghdad';v_end:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 with receipts as materialized(select id,receipt_no,created_at,lines from public.purchases where owner_id=auth.uid() and created_at>=v_start and created_at<v_end),
 expanded as (select r.id as receipt_id,r.receipt_no,r.created_at,l.ordinality,(l.value->>'product_id')::uuid as product_id,l.value->>'name' as name,l.value->>'barcode' as barcode,(l.value->>'quantity_units')::numeric as quantity_units,(l.value->>'line_total')::numeric as line_total from receipts r cross join lateral jsonb_array_elements(r.lines) with ordinality l(value,ordinality)),
 totals as (select product_id,sum(quantity_units) as quantity_units,sum(line_total) as total,count(distinct receipt_id) as receipt_count,max(created_at) as last_purchase_at from expanded group by product_id),
 latest as (select distinct on(product_id) product_id,name,barcode from expanded order by product_id,created_at desc,receipt_no desc,ordinality desc),
 rows as (select t.product_id,l.name,l.barcode,t.quantity_units::text as quantity_units,t.total::text as total,t.receipt_count::text as receipt_count,t.last_purchase_at from totals t join latest l using(product_id) order by l.name,t.product_id limit 5001)
 select coalesce(jsonb_agg(to_jsonb(rows) order by rows.name,rows.product_id),'[]'::jsonb) into v_rows from rows;
 if jsonb_array_length(v_rows)>5000 then raise exception 'purchase_report_too_many_rows';end if;
 select jsonb_build_object('receipt_count',count(*)::text,'tracked_count',count(*) filter(where accounting_mode='tracked')::text,'untracked_count',count(*) filter(where accounting_mode='untracked')::text,
 'total',coalesce(sum(total::numeric),0)::text,'paid',coalesce(sum(amount_paid::numeric) filter(where accounting_mode='tracked'),0)::text,
 'debt_added',coalesce(sum(debt_amount::numeric) filter(where accounting_mode='tracked'),0)::text,
 'untracked_total',coalesce(sum(total::numeric) filter(where accounting_mode='untracked'),0)::text)
 into v_summary from public.purchases where owner_id=auth.uid() and created_at>=v_start and created_at<v_end;
 return jsonb_build_object('from',p_from,'to',p_to,'timezone','Asia/Baghdad','currency','IQD','generated_at',statement_timestamp(),'count',jsonb_array_length(v_rows),'summary',v_summary,'rows',v_rows);
end $$;
revoke all on function public.get_purchase_report(date,date) from public,anon,authenticated;
grant execute on function public.get_purchase_report(date,date) to authenticated;
notify pgrst,'reload schema';
