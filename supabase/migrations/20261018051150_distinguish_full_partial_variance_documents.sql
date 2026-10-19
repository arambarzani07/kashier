create or replace function public.get_purchase_return_variance(p_from date,p_to date) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_start timestamptz;v_end timestamptz;v_docs jsonb;v_rows jsonb;v_groups jsonb;v_count bigint;v_known bigint;begin
 if v_user is null then raise exception 'variance_auth_required';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>365 or p_from<date '2000-01-01' or p_to>date '2100-12-31' then raise exception 'variance_invalid_range';end if;
 v_start:=p_from::timestamp at time zone 'Asia/Baghdad';v_end:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 with docs as(
  select id,purchase_id,reversal_no document_no,created_at,accounting_mode,supplier_name,reason,total,lines,'full'::text kind from public.purchase_reversals where owner_id=v_user and created_at>=v_start and created_at<v_end
  union all select id,purchase_id,return_no,created_at,accounting_mode,supplier_name,reason,total,lines,'partial'::text from public.purchase_returns where owner_id=v_user and created_at>=v_start and created_at<v_end
 ),limited as(select * from docs order by created_at,id limit 5001)
 select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('receipt_no',p.receipt_no::text)),'[]'::jsonb) into v_docs from limited d left join public.purchases p on p.id=d.purchase_id and p.owner_id=v_user;
 if jsonb_array_length(v_docs)>5000 or (select coalesce(sum(jsonb_array_length(d->'lines')),0) from jsonb_array_elements(v_docs) d)>5000 then raise exception 'variance_too_many_rows';end if;
 if exists(select 1 from jsonb_array_elements(v_docs) d where d->>'receipt_no' is null
  or (select coalesce(sum((x->>'line_total')::numeric),0) from jsonb_array_elements(d->'lines') x)<>(d->>'total')::numeric
  or (select count(*) from public.stock_movements m where m.owner_id=v_user and ((d->>'kind'='full' and m.purchase_reversal_id=(d->>'id')::uuid) or (d->>'kind'='partial' and m.purchase_return_id=(d->>'id')::uuid)))<>jsonb_array_length(d->'lines')) then raise exception 'variance_incomplete_history';end if;
 with expected as(
  select d,x,case when d->>'kind'='full' then n::integer else (x->>'line_no')::integer end line_no
  from jsonb_array_elements(v_docs) d cross join lateral jsonb_array_elements(d->'lines') with ordinality t(x,n)
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'movement_no',m.movement_no::text,'document_id',d->>'id','document_no',d->>'document_no','kind',d->>'kind','purchase_id',d->>'purchase_id','receipt_no',d->>'receipt_no','mode',d->>'accounting_mode','supplier_name',d->>'supplier_name','reason',d->>'reason','created_at',d->>'created_at','day',((d->>'created_at')::timestamptz at time zone 'Asia/Baghdad')::date::text,'line_no',e.line_no,'product_id',x->>'product_id','name',x->>'name','barcode',x->'barcode','quantity_units',x->>'quantity_units','document_value',x->>'line_total','stock_cost',(-c.value_delta)::text,'variance',((x->>'line_total')::numeric+c.value_delta)::text,'coverage',case when c.id is null then 'legacy-no-cost-snapshot' else c.coverage end,
  'history_valid',m.id is not null and m.product_id=(x->>'product_id')::uuid and m.delta_units=-(x->>'quantity_units')::bigint and m.created_at=(d->>'created_at')::timestamptz and(c.id is null or(c.product_id=m.product_id and c.quantity_units=m.delta_units and c.created_at=m.created_at and(c.value_delta is null or c.value_delta<=0)))) order by m.movement_no),'[]'::jsonb)
 into v_rows from expected e left join public.stock_movements m on m.owner_id=v_user and m.line_no=e.line_no and((d->>'kind'='full' and m.purchase_reversal_id=(d->>'id')::uuid) or(d->>'kind'='partial' and m.purchase_return_id=(d->>'id')::uuid)) left join public.inventory_cost_movements c on c.id=m.id and c.owner_id=v_user;
 if exists(select 1 from jsonb_array_elements(v_rows) r where (r->>'history_valid')::boolean is distinct from true) then raise exception 'variance_incomplete_history';end if;
 select coalesce(jsonb_agg(r-'history_valid' order by (r->>'movement_no')::bigint),'[]'::jsonb),count(*),count(*) filter(where r->>'stock_cost' is not null) into v_rows,v_count,v_known from jsonb_array_elements(v_rows) r;
 with groups as(
  select mode,count(r) count,count(distinct (r->>'kind')||':'||(r->>'document_id')) document_count,count(r->>'stock_cost') known_count,
   coalesce(sum((r->>'document_value')::numeric),0) document_value,
   coalesce(sum((r->>'document_value')::numeric) filter(where r->>'stock_cost' is not null),0) known_value,
   coalesce(sum((r->>'stock_cost')::numeric),0) known_cost,coalesce(sum((r->>'variance')::numeric),0) known_variance
  from (values('tracked'),('untracked')) modes(mode) left join jsonb_array_elements(v_rows) r on r->>'mode'=mode group by mode
 ) select jsonb_object_agg(mode,jsonb_build_object('count',count,'document_count',document_count,'known_count',known_count,'document_value',document_value::text,'known_value',known_value::text,'known_cost',known_cost::text,'known_variance',known_variance::text,'complete',count=known_count)) into v_groups from groups;
 return jsonb_build_object('scope','owner-purchase-return-variance-v1','owner_id',v_user,'from',p_from::text,'to',p_to::text,'currency','IQD','timezone','Asia/Baghdad','policy','moving-average-whole-iqd-v1','generated_at',statement_timestamp(),'count',v_count,'known_count',v_known,'groups',v_groups,'rows',v_rows);
end $$;
revoke all on function public.get_purchase_return_variance(date,date) from public,anon,authenticated;
grant execute on function public.get_purchase_return_variance(date,date) to authenticated;
notify pgrst,'reload schema';
