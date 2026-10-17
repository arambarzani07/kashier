create function public.get_supplier_activity(p_supplier uuid,p_offset integer default 0,p_limit integer default 50)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 v_user uuid:=auth.uid();
 v_exists boolean;
 v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
 if p_supplier is null or p_offset<0 or p_limit not between 1 and 100 then raise exception 'supplier_activity_invalid_request';end if;
 select true into v_exists from public.suppliers where id=p_supplier and owner_id=v_user;
 if not found then raise exception 'supplier_unavailable';end if;
 with raw as materialized(
  select e.id,e.created_at,'entry'::text source_type,
   case when e.kind='charge' then 'charge' else 'payment' end kind,
   e.amount,e.delta,e.note,e.purchase_id,e.cash_movement_id,
   ('D-'||e.movement_no::text) reference_no,1 source_rank
  from public.supplier_entries e where e.owner_id=v_user and e.supplier_id=p_supplier
  union all
  select r.id,r.created_at,'full_return','return',r.total,0::bigint,r.reason,r.purchase_id,c.id,
   ('PRV-'||r.reversal_no::text),2
  from public.purchase_reversals r
  left join public.cash_movements c on c.purchase_reversal_id=r.id and c.owner_id=r.owner_id
  where r.owner_id=v_user and r.supplier_id=p_supplier and r.accounting_mode='tracked' and r.cash_refund>0
  union all
  select r.id,r.created_at,'partial_return','return',r.total,0::bigint,r.reason,r.purchase_id,c.id,
   ('PPR-'||r.return_no::text),3
  from public.purchase_returns r
  left join public.cash_movements c on c.purchase_return_id=r.id and c.owner_id=r.owner_id
  where r.owner_id=v_user and r.supplier_id=p_supplier and r.accounting_mode='tracked' and r.cash_refund>0
 ),numbered as materialized(
  select *,row_number() over(order by created_at,source_rank,id)::bigint movement_no,
   sum(delta) over(order by created_at,source_rank,id rows unbounded preceding)::bigint balance_after
  from raw
 ),page as(
  select * from numbered order by movement_no desc offset p_offset limit p_limit
 )
 select jsonb_build_object(
  'total',(select count(*) from numbered),
  'rows',coalesce((select jsonb_agg(jsonb_build_object(
   'id',id,'movement_no',movement_no::text,'reference_no',reference_no,'source_type',source_type,
   'created_at',created_at,'kind',kind,'amount',amount::text,'delta',delta::text,'balance_after',balance_after::text,
   'note',note,'purchase_id',purchase_id,'cash_movement_id',cash_movement_id
  ) order by movement_no desc) from page),'[]'::jsonb)
 ) into v_result;
 return v_result;
end $$;
revoke all on function public.get_supplier_activity(uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.get_supplier_activity(uuid,integer,integer) to authenticated;

create or replace function public.get_supplier_statement(p_supplier uuid,p_from date default null,p_to date default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_supplier public.suppliers%rowtype;v_from timestamptz;v_to timestamptz;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'statement_invalid_dates';end if;
 select * into v_supplier from public.suppliers where id=p_supplier and owner_id=v_user;
 if not found then raise exception 'supplier_unavailable';end if;
 v_from:=p_from::timestamp at time zone 'Asia/Baghdad';v_to:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 with raw as materialized(
  select e.id,e.created_at,'entry'::text source_type,
   case when e.kind='charge' then 'charge' else 'payment' end kind,e.amount,e.delta,e.note,e.purchase_id,e.cash_movement_id,
   ('D-'||e.movement_no::text) reference_no,1 source_rank
  from public.supplier_entries e where e.owner_id=v_user and e.supplier_id=p_supplier
  union all
  select r.id,r.created_at,'full_return','return',r.total,0::bigint,r.reason,r.purchase_id,c.id,
   ('PRV-'||r.reversal_no::text),2
  from public.purchase_reversals r left join public.cash_movements c on c.purchase_reversal_id=r.id and c.owner_id=r.owner_id
  where r.owner_id=v_user and r.supplier_id=p_supplier and r.accounting_mode='tracked' and r.cash_refund>0
  union all
  select r.id,r.created_at,'partial_return','return',r.total,0::bigint,r.reason,r.purchase_id,c.id,
   ('PPR-'||r.return_no::text),3
  from public.purchase_returns r left join public.cash_movements c on c.purchase_return_id=r.id and c.owner_id=r.owner_id
  where r.owner_id=v_user and r.supplier_id=p_supplier and r.accounting_mode='tracked' and r.cash_refund>0
 ),numbered as materialized(
  select *,row_number() over(order by created_at,source_rank,id)::bigint movement_no,
   sum(delta) over(order by created_at,source_rank,id rows unbounded preceding)::bigint lifetime_balance
  from raw
 ),opening as(
  select coalesce(sum(delta) filter(where v_from is not null and created_at<v_from),0)::bigint amount from numbered
 ),period as materialized(
  select * from numbered where (v_from is null or created_at>=v_from) and (v_to is null or created_at<v_to)
 ),totals as(
  select count(*) count,coalesce(sum(amount) filter(where kind='charge'),0)::bigint charges,
   coalesce(sum(amount) filter(where kind='payment'),0)::bigint payments,
   coalesce(sum(amount) filter(where kind='return'),0)::bigint reversals from period
 ),ordered as(
  select * from period order by movement_no limit 5001
 )
 select jsonb_build_object(
  'supplier',jsonb_build_object('id',v_supplier.id,'name',v_supplier.name,'phone',v_supplier.phone),
  'from',p_from,'to',p_to,'timezone','Asia/Baghdad','generated_at',statement_timestamp(),'currency','IQD',
  'opening',o.amount::text,'charges',t.charges::text,'payments',t.payments::text,'reversals',t.reversals::text,
  'closing',(o.amount+t.charges-t.payments)::text,'count',t.count,
  'rows',coalesce((select jsonb_agg(jsonb_build_object(
   'id',id,'movement_no',movement_no::text,'reference_no',reference_no,'source_type',source_type,
   'created_at',created_at,'kind',kind,'amount',amount::text,'delta',delta::text,'balance',lifetime_balance::text,
   'note',note,'purchase_id',purchase_id,'cash_movement_id',cash_movement_id
  ) order by movement_no) from ordered),'[]'::jsonb)
 ) into v_result from opening o cross join totals t;
 if (v_result->>'count')::bigint>5000 then raise exception 'statement_too_many_rows';end if;
 return v_result;
end $$;
revoke all on function public.get_supplier_statement(uuid,date,date) from public,anon,authenticated;
grant execute on function public.get_supplier_statement(uuid,date,date) to authenticated;
notify pgrst,'reload schema';
