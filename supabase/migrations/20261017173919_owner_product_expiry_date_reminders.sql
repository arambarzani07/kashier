-- Optional product-level reminder date; no lot allocation or stock mutation.
alter table public.products add column expiry_date date check(expiry_date between date '1900-01-01' and date '2100-12-31');
grant insert(expiry_date),update(expiry_date) on public.products to authenticated;
create index products_owner_expiry_idx on public.products(owner_id,expiry_date,id) where expiry_date is not null;
create function public.get_expiry_report(p_mode text default 'expired',p_days integer default 30,p_query text default '',p_include_empty boolean default false) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare today date:=(statement_timestamp() at time zone 'Asia/Baghdad')::date;q text:=btrim(coalesce(p_query,''));rows jsonb;counts jsonb;
begin
 if auth.uid() is null then raise exception 'expiry_auth_required';end if;
 if p_mode is null or p_mode not in ('expired','today','upcoming','all') or p_days is null or p_days not between 1 and 365 or char_length(q)>100 or p_include_empty is null then raise exception 'expiry_invalid_filters';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.expiry_date,x.name,x.id),'[]'::jsonb) into rows from (
  select p.id,p.name,p.barcode,p.expiry_date,p.sale_price::text,coalesce(s.quantity_units,0)::text as quantity_units,p.expiry_date-today as days_left,
   case when p.expiry_date<today then 'expired' when p.expiry_date=today then 'today' else 'upcoming' end as stage
  from public.products p left join public.product_stock s on s.product_id=p.id and s.owner_id=p.owner_id
  where p.owner_id=(select auth.uid()) and p.expiry_date is not null and (p_include_empty or coalesce(s.quantity_units,0)>0)
   and (q='' or position(lower(q) in lower(p.name))>0 or position(lower(q) in lower(coalesce(p.barcode,'')))>0)
   and (p_mode='all' or p_mode='expired' and p.expiry_date<today or p_mode='today' and p.expiry_date=today or p_mode='upcoming' and p.expiry_date>today and p.expiry_date<=today+p_days)
  order by p.expiry_date,p.name,p.id limit 5001
 ) x;
 if jsonb_array_length(rows)>5000 then raise exception 'expiry_too_many_rows';end if;
 select jsonb_build_object('expired',count(*) filter(where r->>'stage'='expired'),'today',count(*) filter(where r->>'stage'='today'),'upcoming',count(*) filter(where r->>'stage'='upcoming')) into counts from jsonb_array_elements(rows) r;
 return jsonb_build_object('rows',rows,'count',jsonb_array_length(rows),'counts',counts,'today',today,'generated_at',statement_timestamp(),'mode',p_mode,'days',p_days,'query',q,'include_empty',p_include_empty,'timezone','Asia/Baghdad','currency','IQD','scope','product-date-reminders');
end $$;
revoke all on function public.get_expiry_report(text,integer,text,boolean) from public,anon,authenticated;
grant execute on function public.get_expiry_report(text,integer,text,boolean) to authenticated;
notify pgrst,'reload schema';
