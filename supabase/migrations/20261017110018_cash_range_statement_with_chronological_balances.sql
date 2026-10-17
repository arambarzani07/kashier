create index cash_movements_owner_created_order_idx on public.cash_movements(owner_id,created_at,movement_no);
create function public.get_cash_statement(p_from date,p_to date) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_start timestamptz;v_end timestamptz;v_opening numeric;v_rows jsonb;v_totals jsonb;v_kinds jsonb;
begin
 if auth.uid() is null then raise exception 'cash_statement_auth_required';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>365 then raise exception 'cash_statement_invalid_range';end if;
 v_start:=p_from::timestamp at time zone 'Asia/Baghdad';v_end:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 select coalesce(sum(delta::numeric),0) into v_opening from public.cash_movements where owner_id=auth.uid() and created_at<v_start;
 with entries as materialized(select c.id,c.movement_no,c.created_at,c.kind,c.amount,c.delta,c.note,c.customer_id,c.supplier_id,c.purchase_id,coalesce(c.sale_id,r.sale_id,t.sale_id) as linked_sale_id from public.cash_movements c left join public.sale_reversals r on r.id=c.reversal_id left join public.sale_returns t on t.id=c.return_id where c.owner_id=auth.uid() and c.created_at>=v_start and c.created_at<v_end),
 ordered as(select id,movement_no::text as movement_no,created_at,kind,amount::text as amount,delta::text as delta,note,customer_id,supplier_id,purchase_id,linked_sale_id,(v_opening+sum(delta::numeric) over(order by created_at,movement_no rows unbounded preceding))::text as statement_balance from entries order by created_at,movement_no limit 5001),
 totals as(select coalesce(sum(delta::numeric) filter(where delta>0),0) as inflows,coalesce(-sum(delta::numeric) filter(where delta<0),0) as outflows from entries),
 kinds as(select kind,sum(amount::numeric)::text as total from entries group by kind)
 select coalesce(jsonb_agg(to_jsonb(ordered) order by ordered.created_at,ordered.movement_no::bigint),'[]'::jsonb),
 (select jsonb_build_object('opening',v_opening::text,'inflows',inflows::text,'outflows',outflows::text,'closing',(v_opening+inflows-outflows)::text) from totals),
 (select coalesce(jsonb_object_agg(kind,total),'{}'::jsonb) from kinds)
 into v_rows,v_totals,v_kinds from ordered;
 if jsonb_array_length(v_rows)>5000 then raise exception 'cash_statement_too_many_rows';end if;
 return jsonb_build_object('from',p_from,'to',p_to,'timezone','Asia/Baghdad','currency','IQD','generated_at',statement_timestamp(),'count',jsonb_array_length(v_rows),'summary',v_totals,'by_kind',v_kinds,'rows',v_rows);
end $$;
revoke all on function public.get_cash_statement(date,date) from public,anon,authenticated;
grant execute on function public.get_cash_statement(date,date) to authenticated;
notify pgrst,'reload schema';
