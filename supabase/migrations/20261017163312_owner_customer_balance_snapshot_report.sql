create function public.get_customer_balances_report(p_query text default '',p_debt_only boolean default true) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare q text:=btrim(coalesce(p_query,''));rows jsonb;total numeric;debtors bigint;
begin
 if auth.uid() is null then raise exception 'customer_report_auth_required';end if;
 if char_length(q)>100 or p_debt_only is null then raise exception 'customer_report_invalid_filters';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.amount desc,x.name,x.id),'[]'::jsonb) into rows from (
  select c.id,c.name,c.phone,c.balance::text as balance,c.balance as amount from public.customer_debt_catalog c
  where (not p_debt_only or c.balance>0) and (q='' or position(lower(q) in lower(c.name))>0 or position(lower(q) in lower(coalesce(c.phone,'')))>0)
  order by c.balance desc,c.name,c.id limit 5001
 ) x;
 if jsonb_array_length(rows)>5000 then raise exception 'customer_report_too_many_rows';end if;
 select coalesce(sum((r->>'balance')::numeric),0),count(*) filter(where (r->>'balance')::numeric>0) into total,debtors from jsonb_array_elements(rows) r;
 -- Only exact decimal strings for amounts; remove the internal numeric sort field.
 select coalesce(jsonb_agg(r-'amount' order by ord),'[]'::jsonb) into rows from jsonb_array_elements(rows) with ordinality e(r,ord);
 return jsonb_build_object('generated_at',statement_timestamp(),'query',q,'debt_only',p_debt_only,'currency','IQD','timezone','Asia/Baghdad','count',jsonb_array_length(rows),'debtors',debtors::text,'balance',total::text,'rows',rows);
end $$;
revoke all on function public.get_customer_balances_report(text,boolean) from public,anon,authenticated;
grant execute on function public.get_customer_balances_report(text,boolean) to authenticated;
notify pgrst,'reload schema';
