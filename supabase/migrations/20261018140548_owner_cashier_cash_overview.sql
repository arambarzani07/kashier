create function private.get_owner_cashier_cash_overview(p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p_owner uuid:=auth.uid();items jsonb;result_rows jsonb;totals jsonb;start_at timestamptz;end_at timestamptz;
begin
 if p_owner is null then raise exception 'staff_auth_required';end if;
 if p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to) or p_to<p_from or p_to-p_from>30 then raise exception 'staff_cash_invalid_range';end if;
 start_at:=p_from::timestamp at time zone 'Asia/Baghdad';end_at:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 with activity as (
 select s.actor_id,s.id,case when s.payment_mode='cash' then 'sale_cash' else 'sale_credit_cash' end kind,s.receipt_no number,s.created_at,s.actor_name,case when s.payment_mode='cash' then s.total else s.received end amount
 from public.sales s where s.owner_id=p_owner and s.actor_name is not null and s.created_at>=start_at and s.created_at<end_at
 union all
 select d.actor_id,d.id,'collection',d.movement_no,d.created_at,d.actor_name,d.amount from public.debt_entries d where d.owner_id=p_owner and d.actor_name is not null and d.kind='repayment' and d.cash_movement_id is not null and d.created_at>=start_at and d.created_at<end_at
 union all
 select r.actor_id,r.id,'full_refund',r.reversal_no,r.created_at,r.actor_name,r.cash_refund from public.sale_reversals r join public.sales s on s.id=r.sale_id and s.owner_id=r.owner_id and s.payment_mode='cash' and s.actor_id=r.actor_id where r.owner_id=p_owner and r.actor_name is not null and r.created_at>=start_at and r.created_at<end_at
 union all
 select r.actor_id,r.id,'partial_refund',r.return_no,r.created_at,r.actor_name,r.cash_refund from public.sale_returns r join public.sales s on s.id=r.sale_id and s.owner_id=r.owner_id and s.payment_mode='cash' and s.actor_id=r.actor_id where r.owner_id=p_owner and r.actor_name is not null and r.created_at>=start_at and r.created_at<end_at

 ), bounded as(select a.* from activity a join public.store_cashiers c on c.owner_id=p_owner and c.member_id=a.actor_id limit 5001)
 select coalesce(jsonb_agg(jsonb_build_object('member_id',actor_id,'kind',kind,'amount',amount::text)),'[]'::jsonb) into items from bounded;
 if jsonb_array_length(items)>5000 then raise exception 'staff_cash_too_many_rows';end if;
 with sums as(select (x->>'member_id')::uuid member_id,
 coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind'='sale_cash'),0) sale_cash,
 coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind'='sale_credit_cash'),0) sale_credit_cash,
 coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind'='collection'),0) collection,
 coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind'='full_refund'),0) full_refund,
 coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind'='partial_refund'),0) partial_refund,count(*) count
 from jsonb_array_elements(items)x group by (x->>'member_id')::uuid),
 rows as(select c.member_id,c.member_name,c.store_name,c.enabled,c.accepted_at,
 coalesce(s.sale_cash,0) sale_cash,coalesce(s.sale_credit_cash,0) sale_credit_cash,coalesce(s.collection,0) collection,coalesce(s.full_refund,0) full_refund,coalesce(s.partial_refund,0) partial_refund,coalesce(s.count,0) count
 from public.store_cashiers c left join sums s on s.member_id=c.member_id where c.owner_id=p_owner)
 select coalesce(jsonb_agg(jsonb_build_object('member_id',member_id,'member_name',member_name,'store_name',store_name,'enabled',enabled,'accepted_at',accepted_at,'summary',jsonb_build_object('sale_cash',sale_cash::text,'sale_credit_cash',sale_credit_cash::text,'collection',collection::text,'full_refund',full_refund::text,'partial_refund',partial_refund::text,'inflow',(sale_cash+sale_credit_cash+collection)::text,'outflow',(full_refund+partial_refund)::text,'net',(sale_cash+sale_credit_cash+collection-full_refund-partial_refund)::text,'count',count::text)) order by member_id::text),'[]'::jsonb) into result_rows from rows;
 select jsonb_build_object('sale_cash',coalesce(sum((x#>>'{summary,sale_cash}')::numeric),0)::text,'sale_credit_cash',coalesce(sum((x#>>'{summary,sale_credit_cash}')::numeric),0)::text,'collection',coalesce(sum((x#>>'{summary,collection}')::numeric),0)::text,'full_refund',coalesce(sum((x#>>'{summary,full_refund}')::numeric),0)::text,'partial_refund',coalesce(sum((x#>>'{summary,partial_refund}')::numeric),0)::text,'inflow',coalesce(sum((x#>>'{summary,inflow}')::numeric),0)::text,'outflow',coalesce(sum((x#>>'{summary,outflow}')::numeric),0)::text,'net',coalesce(sum((x#>>'{summary,net}')::numeric),0)::text,'count',jsonb_array_length(items)::text) into totals from jsonb_array_elements(result_rows)x;
 return jsonb_build_object('scope','owner-cashier-cash-overview-v1','owner_id',p_owner,'viewer_id',p_owner,'from',p_from,'to',p_to,'currency','IQD','timezone','Asia/Baghdad','generated_at',now(),'members_count',jsonb_array_length(result_rows)::text,'summary',totals,'rows',result_rows);
end $$;
create function public.get_owner_cashier_cash_overview(p_from date,p_to date) returns jsonb language sql security invoker set search_path='' as $$select private.get_owner_cashier_cash_overview(p_from,p_to);$$;
revoke all on function public.get_owner_cashier_cash_overview(date,date),private.get_owner_cashier_cash_overview(date,date) from public,anon,authenticated;
grant execute on function public.get_owner_cashier_cash_overview(date,date),private.get_owner_cashier_cash_overview(date,date) to authenticated;
notify pgrst,'reload schema';
