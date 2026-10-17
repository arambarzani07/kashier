create or replace function public.get_supplier_activity(p_supplier uuid,p_offset integer default 0,p_limit integer default 50)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_exists boolean;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
 if p_supplier is null or p_offset<0 or p_limit not between 1 and 100 then raise exception 'supplier_activity_invalid_request';end if;
 select true into v_exists from public.suppliers where id=p_supplier and owner_id=v_user;if not found then raise exception 'supplier_unavailable';end if;
 with raw as materialized(
  select e.id,e.created_at,'entry'::text source_type,case when e.kind='charge' then 'charge' else 'payment' end kind,e.amount,e.delta,e.note,e.purchase_id,e.cash_movement_id,e.supplier_name,('D-'||e.movement_no::text) reference_no,1 source_rank
  from public.supplier_entries e where e.owner_id=v_user and e.supplier_id=p_supplier
  union all
  select r.id,r.created_at,'full_return','return',r.total,0::bigint,r.reason,r.purchase_id,c.id,r.supplier_name,('PRV-'||r.reversal_no::text),2
  from public.purchase_reversals r left join public.cash_movements c on c.purchase_reversal_id=r.id and c.owner_id=r.owner_id
  where r.owner_id=v_user and r.supplier_id=p_supplier and r.accounting_mode='tracked' and r.cash_refund>0
  union all
  select r.id,r.created_at,'partial_return','return',r.total,0::bigint,r.reason,r.purchase_id,c.id,r.supplier_name,('PPR-'||r.return_no::text),3
  from public.purchase_returns r left join public.cash_movements c on c.purchase_return_id=r.id and c.owner_id=r.owner_id
  where r.owner_id=v_user and r.supplier_id=p_supplier and r.accounting_mode='tracked' and r.cash_refund>0
 ),numbered as materialized(
  select *,row_number() over(order by created_at,source_rank,id)::bigint movement_no,sum(delta) over(order by created_at,source_rank,id rows unbounded preceding)::bigint balance_after from raw
 ),page as(select * from numbered order by movement_no desc offset p_offset limit p_limit)
 select jsonb_build_object('total',(select count(*) from numbered),'rows',coalesce((select jsonb_agg(jsonb_build_object(
  'id',id,'movement_no',movement_no::text,'reference_no',reference_no,'source_type',source_type,'supplier_name',supplier_name,
  'created_at',created_at,'kind',kind,'amount',amount::text,'delta',delta::text,'balance_after',balance_after::text,
  'note',note,'purchase_id',purchase_id,'cash_movement_id',cash_movement_id
 ) order by movement_no desc) from page),'[]'::jsonb)) into v_result;
 return v_result;
end $$;
notify pgrst,'reload schema';
