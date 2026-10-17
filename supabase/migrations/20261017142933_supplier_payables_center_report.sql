create or replace function public.get_supplier_payables_report(
  p_supplier text default null,
  p_query text default null,
  p_min_outstanding bigint default null,
  p_max_outstanding bigint default null,
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
  v_user uuid:=auth.uid();
  v_supplier text:=btrim(coalesce(p_supplier,''));
  v_query text:=btrim(coalesce(p_query,''));
  v_result jsonb;
begin
  if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
  if char_length(v_supplier)>100 then raise exception 'supplier_payables_invalid_supplier';end if;
  if char_length(v_query)>100 then raise exception 'supplier_payables_invalid_query';end if;
  if p_min_outstanding is not null and (p_min_outstanding<0 or p_min_outstanding>100000000000000) then raise exception 'supplier_payables_invalid_amount';end if;
  if p_max_outstanding is not null and (p_max_outstanding<0 or p_max_outstanding>100000000000000) then raise exception 'supplier_payables_invalid_amount';end if;
  if p_min_outstanding is not null and p_max_outstanding is not null and p_min_outstanding>p_max_outstanding then raise exception 'supplier_payables_invalid_amount_range';end if;
  if p_offset is null or p_offset<0 or p_offset>10000000 or p_limit is null or p_limit<1 or p_limit>100 then raise exception 'supplier_payables_invalid_page';end if;
  with base as materialized(
    select p.id purchase_id,p.receipt_no,p.invoice_no,p.created_at,p.supplier_id,p.supplier_name,p.total,p.amount_paid initial_paid,p.debt_amount original_debt,e.id charge_entry_id,
      coalesce((select sum(a.amount) from public.supplier_payment_allocations a where a.owner_id=v_user and a.purchase_id=p.id),0)::bigint allocated_payments,
      coalesce((select sum(r.amount) from public.supplier_entries r where r.owner_id=v_user and r.purchase_id=p.id and r.kind='reversal'),0)::bigint debt_reversed
    from public.purchases p
    join public.supplier_entries e on e.owner_id=v_user and e.purchase_id=p.id and e.kind='charge'
    where p.owner_id=v_user and p.accounting_mode='tracked' and p.supplier_id is not null and p.debt_amount>0
  ), open_rows as materialized(
    select *,original_debt-allocated_payments-debt_reversed as outstanding
    from base
    where original_debt-allocated_payments-debt_reversed>0
      and (v_supplier='' or position(lower(v_supplier) in lower(coalesce(supplier_name,'')))>0)
      and (p_min_outstanding is null or original_debt-allocated_payments-debt_reversed>=p_min_outstanding)
      and (p_max_outstanding is null or original_debt-allocated_payments-debt_reversed<=p_max_outstanding)
      and (v_query='' or position(lower(v_query) in lower(coalesce(invoice_no,'')))>0 or position(lower(v_query) in lower(coalesce(supplier_name,'')))>0 or (v_query~'^[0-9]{1,18}$' and receipt_no=v_query::bigint))
  ), totals as(
    select count(*)::text count,coalesce(sum(outstanding),0)::text outstanding,coalesce(sum(original_debt),0)::text original_debt,coalesce(sum(allocated_payments),0)::text allocated_payments,coalesce(sum(debt_reversed),0)::text debt_reversed
    from open_rows
  ), page as(
    select * from open_rows order by created_at,receipt_no,purchase_id offset p_offset limit p_limit
  )
  select jsonb_build_object(
    'count',t.count,'outstanding',t.outstanding,'original_debt',t.original_debt,'allocated_payments',t.allocated_payments,'debt_reversed',t.debt_reversed,
    'rows',coalesce((select jsonb_agg(jsonb_build_object(
      'purchase_id',p.purchase_id,'receipt_no',p.receipt_no::text,'invoice_no',p.invoice_no,'created_at',p.created_at,
      'supplier_id',p.supplier_id,'supplier_name',p.supplier_name,'total',p.total::text,'initial_paid',p.initial_paid::text,
      'original_debt',p.original_debt::text,'allocated_payments',p.allocated_payments::text,'debt_reversed',p.debt_reversed::text,
      'outstanding',p.outstanding::text,'charge_entry_id',p.charge_entry_id
    ) order by p.created_at,p.receipt_no,p.purchase_id) from page p),'[]'::jsonb)
  ) into v_result from totals t;
  return v_result;
end $$;
revoke all on function public.get_supplier_payables_report(text,text,bigint,bigint,integer,integer) from public,anon,authenticated;
grant execute on function public.get_supplier_payables_report(text,text,bigint,bigint,integer,integer) to authenticated;
notify pgrst,'reload schema';
