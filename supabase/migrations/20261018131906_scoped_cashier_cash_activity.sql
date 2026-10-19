create function private.get_cashier_cash_activity(p_owner uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare member public.store_cashiers%rowtype;items jsonb;sums jsonb;start_at timestamptz;end_at timestamptz;
begin
 member:=private.cashier_membership(p_owner);
 if p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to) or p_to<p_from or p_to-p_from>30 then raise exception 'staff_cash_invalid_range';end if;
 start_at:=p_from::timestamp at time zone 'Asia/Baghdad';end_at:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 with activity as (
 select s.id,case when s.payment_mode='cash' then 'sale_cash' else 'sale_credit_cash' end kind,s.receipt_no number,s.created_at,s.actor_name,case when s.payment_mode='cash' then s.total else s.received end amount
 from public.sales s where s.owner_id=p_owner and s.actor_id=auth.uid() and s.actor_name is not null and s.created_at>=start_at and s.created_at<end_at
 union all
 select d.id,'collection',d.movement_no,d.created_at,d.actor_name,d.amount from public.debt_entries d where d.owner_id=p_owner and d.actor_id=auth.uid() and d.actor_name is not null and d.kind='repayment' and d.cash_movement_id is not null and d.created_at>=start_at and d.created_at<end_at
 union all
 select r.id,'full_refund',r.reversal_no,r.created_at,r.actor_name,r.cash_refund from public.sale_reversals r join public.sales s on s.id=r.sale_id and s.owner_id=r.owner_id and s.actor_id=auth.uid() and s.payment_mode='cash' where r.owner_id=p_owner and r.actor_id=auth.uid() and r.actor_name is not null and r.created_at>=start_at and r.created_at<end_at
 union all
 select r.id,'partial_refund',r.return_no,r.created_at,r.actor_name,r.cash_refund from public.sale_returns r join public.sales s on s.id=r.sale_id and s.owner_id=r.owner_id and s.actor_id=auth.uid() and s.payment_mode='cash' where r.owner_id=p_owner and r.actor_id=auth.uid() and r.actor_name is not null and r.created_at>=start_at and r.created_at<end_at
 ), bounded as(select * from activity order by created_at desc,id::text desc,kind desc limit 5001)
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'number',number::text,'created_at',created_at,'actor_id',auth.uid(),'actor_name',actor_name,'amount',amount::text,'delta',(case when kind in('full_refund','partial_refund') then -amount else amount end)::text) order by created_at desc,id::text desc,kind desc),'[]'::jsonb) into items from bounded;
 if jsonb_array_length(items)>5000 then raise exception 'staff_cash_too_many_rows';end if;
 select jsonb_build_object('sale_cash',coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind'='sale_cash'),0)::text,'sale_credit_cash',coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind'='sale_credit_cash'),0)::text,'collection',coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind'='collection'),0)::text,'full_refund',coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind'='full_refund'),0)::text,'partial_refund',coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind'='partial_refund'),0)::text,'inflow',coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind' not in('full_refund','partial_refund')),0)::text,'outflow',coalesce(sum((x->>'amount')::numeric)filter(where x->>'kind' in('full_refund','partial_refund')),0)::text,'net',coalesce(sum((x->>'delta')::numeric),0)::text,'count',jsonb_array_length(items)::text) into sums from jsonb_array_elements(items)x;
 return jsonb_build_object('scope','cashier-cash-activity-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',member.store_name,'member_name',member.member_name,'currency','IQD','timezone','Asia/Baghdad','from',p_from,'to',p_to,'generated_at',now(),'summary',sums,'rows',items);
end $$;
create function public.get_cashier_cash_activity(p_owner uuid,p_from date,p_to date) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_cash_activity(p_owner,p_from,p_to);$$;
revoke all on function public.get_cashier_cash_activity(uuid,date,date),private.get_cashier_cash_activity(uuid,date,date) from public,anon,authenticated;
grant execute on function public.get_cashier_cash_activity(uuid,date,date),private.get_cashier_cash_activity(uuid,date,date) to authenticated;
notify pgrst,'reload schema';
