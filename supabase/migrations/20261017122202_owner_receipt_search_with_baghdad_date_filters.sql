create function public.search_receipts(p_kind text,p_page integer default 0,p_number bigint default null,p_from date default null,p_to date default null,p_query text default '') returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_start timestamptz;v_end timestamptz;v_rows jsonb;v_total bigint;v_query text:=btrim(coalesce(p_query,''));
begin
 if auth.uid() is null then raise exception 'receipt_search_auth_required';end if;
 if p_kind is null or p_kind not in ('sale','purchase') or p_page is null or p_page<0 or p_page>1000000 or (p_number is not null and p_number<1) or char_length(v_query)>100 or (p_from is not null and p_to is not null and p_from>p_to) then raise exception 'receipt_search_invalid_filters';end if;
 v_start:=p_from::timestamp at time zone 'Asia/Baghdad';v_end:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 if p_kind='sale' then
  select count(*) into v_total from public.sales where owner_id=auth.uid() and (p_number is null or receipt_no=p_number) and (v_start is null or created_at>=v_start) and (v_end is null or created_at<v_end) and (v_query='' or position(lower(v_query) in lower(customer_name))>0);
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc,t.id),'[]'::jsonb) into v_rows from (select id,receipt_no::text,created_at,customer_name,total::text,payment_mode,debt_amount::text from public.sales where owner_id=auth.uid() and (p_number is null or receipt_no=p_number) and (v_start is null or created_at>=v_start) and (v_end is null or created_at<v_end) and (v_query='' or position(lower(v_query) in lower(customer_name))>0) order by created_at desc,id limit 50 offset p_page*50) t;
 else
  select count(*) into v_total from public.purchases where owner_id=auth.uid() and (p_number is null or receipt_no=p_number) and (v_start is null or created_at>=v_start) and (v_end is null or created_at<v_end) and (v_query='' or position(lower(v_query) in lower(supplier_name))>0 or position(lower(v_query) in lower(invoice_no))>0);
  select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc,t.id),'[]'::jsonb) into v_rows from (select id,receipt_no::text,created_at,supplier_name,invoice_no,total::text from public.purchases where owner_id=auth.uid() and (p_number is null or receipt_no=p_number) and (v_start is null or created_at>=v_start) and (v_end is null or created_at<v_end) and (v_query='' or position(lower(v_query) in lower(supplier_name))>0 or position(lower(v_query) in lower(invoice_no))>0) order by created_at desc,id limit 50 offset p_page*50) t;
 end if;
 return jsonb_build_object('rows',v_rows,'total',v_total::text);
end $$;
revoke all on function public.search_receipts(text,integer,bigint,date,date,text) from public,anon,authenticated;
grant execute on function public.search_receipts(text,integer,bigint,date,date,text) to authenticated;
notify pgrst,'reload schema';
