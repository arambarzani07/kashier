create or replace function public.get_purchase_returns_report(
  p_kind text default 'all',
  p_from date default null,
  p_to date default null,
  p_supplier text default null,
  p_query text default null,
  p_min_amount bigint default null,
  p_max_amount bigint default null,
  p_offset integer default 0,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security invoker
set search_path=''
as $$
declare
  v_user uuid := auth.uid();
  v_kind text := lower(btrim(coalesce(p_kind,'all')));
  v_supplier text := btrim(coalesce(p_supplier,''));
  v_query text := btrim(coalesce(p_query,''));
  v_start timestamptz;
  v_end timestamptz;
  v_result jsonb;
begin
  if v_user is null then
    raise exception using errcode='28000', message='purchase_returns_auth_required';
  end if;
  if v_kind not in ('all','full','partial') then
    raise exception 'purchase_returns_invalid_kind';
  end if;
  if p_from is not null and p_to is not null and p_from > p_to then
    raise exception 'purchase_returns_invalid_dates';
  end if;
  if char_length(v_supplier) > 100 then
    raise exception 'purchase_returns_invalid_supplier';
  end if;
  if char_length(v_query) > 100 then
    raise exception 'purchase_returns_invalid_query';
  end if;
  if p_min_amount is not null and (p_min_amount < 0 or p_min_amount > 100000000000000) then
    raise exception 'purchase_returns_invalid_amount';
  end if;
  if p_max_amount is not null and (p_max_amount < 0 or p_max_amount > 100000000000000) then
    raise exception 'purchase_returns_invalid_amount';
  end if;
  if p_min_amount is not null and p_max_amount is not null and p_min_amount > p_max_amount then
    raise exception 'purchase_returns_invalid_amount_range';
  end if;
  if p_offset is null or p_offset < 0 or p_offset > 10000000 or p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'purchase_returns_invalid_page';
  end if;

  if p_from is not null then v_start := p_from::timestamp at time zone 'Asia/Baghdad'; end if;
  if p_to is not null then v_end := (p_to + 1)::timestamp at time zone 'Asia/Baghdad'; end if;

  with combined as (
    select
      'full'::text as kind,
      r.id,
      r.reversal_no as return_no,
      r.purchase_id,
      r.created_at,
      r.reason,
      r.accounting_mode,
      r.total,
      r.cash_refund,
      r.lines,
      r.supplier_id,
      r.supplier_name,
      p.receipt_no,
      p.invoice_no
    from public.purchase_reversals r
    join public.purchases p on p.id=r.purchase_id and p.owner_id=v_user
    where r.owner_id=v_user
      and v_kind in ('all','full')
      and (v_start is null or r.created_at >= v_start)
      and (v_end is null or r.created_at < v_end)
    union all
    select
      'partial'::text,
      r.id,
      r.return_no,
      r.purchase_id,
      r.created_at,
      r.reason,
      r.accounting_mode,
      r.total,
      r.cash_refund,
      r.lines,
      r.supplier_id,
      r.supplier_name,
      p.receipt_no,
      p.invoice_no
    from public.purchase_returns r
    join public.purchases p on p.id=r.purchase_id and p.owner_id=v_user
    where r.owner_id=v_user
      and v_kind in ('all','partial')
      and (v_start is null or r.created_at >= v_start)
      and (v_end is null or r.created_at < v_end)
  ), filtered as (
    select * from combined c
    where (v_supplier='' or position(lower(v_supplier) in lower(coalesce(c.supplier_name,''))) > 0)
      and (p_min_amount is null or c.total >= p_min_amount)
      and (p_max_amount is null or c.total <= p_max_amount)
      and (
        v_query=''
        or position(lower(v_query) in lower(coalesce(c.invoice_no,''))) > 0
        or position(lower(v_query) in lower(coalesce(c.reason,''))) > 0
        or (v_query ~ '^[0-9]{1,18}$' and (c.receipt_no=v_query::bigint or c.return_no=v_query::bigint))
      )
  ), total as (
    select count(*)::text as count from filtered
  ), page as (
    select * from filtered order by created_at desc,id desc offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'count',t.count,
    'rows',coalesce((select jsonb_agg(jsonb_build_object(
      'kind',p.kind,
      'id',p.id,
      'return_no',p.return_no::text,
      'purchase_id',p.purchase_id,
      'receipt_no',p.receipt_no::text,
      'invoice_no',p.invoice_no,
      'supplier_id',p.supplier_id,
      'supplier_name',p.supplier_name,
      'created_at',p.created_at,
      'reason',p.reason,
      'accounting_mode',p.accounting_mode,
      'total',p.total::text,
      'cash_refund',p.cash_refund::text,
      'lines',p.lines
    ) order by p.created_at desc,p.id desc) from page p),'[]'::jsonb)
  ) into v_result from total t;
  return v_result;
end $$;

revoke all on function public.get_purchase_returns_report(text,date,date,text,text,bigint,bigint,integer,integer) from public,anon,authenticated;
grant execute on function public.get_purchase_returns_report(text,date,date,text,text,bigint,bigint,integer,integer) to authenticated;
notify pgrst,'reload schema';