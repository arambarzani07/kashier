create function public.get_expense_report(p_from date,p_to date,p_query text default '') returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();q text:=btrim(coalesce(p_query,''));v_rows jsonb;v_total numeric;
begin
 if v_user is null then raise exception 'expense_auth_required';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>365 or p_from<date '0001-01-01' or p_to>date '9999-12-31' or char_length(q)>100 then raise exception 'expense_invalid_filters';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'movement_no',x.movement_no::text,'created_at',x.created_at,'day',(x.created_at at time zone 'Asia/Baghdad')::date,'kind',x.kind,'note',x.note,'amount',x.amount::text) order by x.created_at desc,x.movement_no desc),'[]'::jsonb) into v_rows
 from (select id,movement_no,created_at,kind,note,amount from public.cash_movements
  where owner_id=v_user and kind='expense' and created_at>=(p_from::timestamp at time zone 'Asia/Baghdad') and created_at<((p_to+1)::timestamp at time zone 'Asia/Baghdad')
   and (q='' or position(lower(q) in lower(note))>0)
  order by created_at desc,movement_no desc limit 5001) x;
 if jsonb_array_length(v_rows)>5000 then raise exception 'expense_too_many_rows';end if;
 select coalesce(sum((r->>'amount')::numeric),0) into v_total from jsonb_array_elements(v_rows) r;
 return jsonb_build_object('scope','owner-expense-report-v1','owner_id',v_user,'from',p_from,'to',p_to,'query',q,'generated_at',statement_timestamp(),'timezone','Asia/Baghdad','currency','IQD','count',jsonb_array_length(v_rows),'total',v_total::text,'rows',v_rows);
end $$;
revoke all on function public.get_expense_report(date,date,text) from public,anon,authenticated;
grant execute on function public.get_expense_report(date,date,text) to authenticated;
notify pgrst,'reload schema';
