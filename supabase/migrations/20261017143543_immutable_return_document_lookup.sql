create or replace function public.get_return_document(p_source text,p_kind text,p_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path=''
as $$
declare
 v_user uuid:=auth.uid();
 v_source text:=lower(btrim(coalesce(p_source,'')));
 v_kind text:=lower(btrim(coalesce(p_kind,'')));
 v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='return_document_auth_required';end if;
 if p_id is null or v_source not in ('sale','purchase') or v_kind not in ('full','partial') then raise exception 'return_document_invalid_request';end if;
 if v_source='sale' and v_kind='full' then
  select jsonb_build_object(
   'source','sale','kind','full','id',r.id,'return_no',r.reversal_no::text,'transaction_id',r.sale_id,
   'receipt_no',s.receipt_no::text,'created_at',r.created_at,'reason',r.reason,'currency','IQD',
   'total',r.total::text,'cash_refund',r.cash_refund::text,'debt_reversed',r.debt_reversed::text,'lines',r.lines,
   'counterparty_name',s.customer_name,'mode',s.payment_mode,'invoice_no',null
  ) into v_result
  from public.sale_reversals r join public.sales s on s.id=r.sale_id and s.owner_id=v_user
  where r.id=p_id and r.owner_id=v_user;
 elsif v_source='sale' and v_kind='partial' then
  select jsonb_build_object(
   'source','sale','kind','partial','id',r.id,'return_no',r.return_no::text,'transaction_id',r.sale_id,
   'receipt_no',s.receipt_no::text,'created_at',r.created_at,'reason',r.reason,'currency','IQD',
   'total',r.total::text,'cash_refund',r.cash_refund::text,'debt_reversed',r.debt_reversed::text,'lines',r.lines,
   'counterparty_name',s.customer_name,'mode',s.payment_mode,'invoice_no',null
  ) into v_result
  from public.sale_returns r join public.sales s on s.id=r.sale_id and s.owner_id=v_user
  where r.id=p_id and r.owner_id=v_user;
 elsif v_source='purchase' and v_kind='full' then
  select jsonb_build_object(
   'source','purchase','kind','full','id',r.id,'return_no',r.reversal_no::text,'transaction_id',r.purchase_id,
   'receipt_no',p.receipt_no::text,'created_at',r.created_at,'reason',r.reason,'currency','IQD',
   'total',r.total::text,'cash_refund',r.cash_refund::text,'debt_reversed',r.debt_reversed::text,'lines',r.lines,
   'counterparty_name',r.supplier_name,'mode',r.accounting_mode,'invoice_no',p.invoice_no
  ) into v_result
  from public.purchase_reversals r join public.purchases p on p.id=r.purchase_id and p.owner_id=v_user
  where r.id=p_id and r.owner_id=v_user;
 else
  select jsonb_build_object(
   'source','purchase','kind','partial','id',r.id,'return_no',r.return_no::text,'transaction_id',r.purchase_id,
   'receipt_no',p.receipt_no::text,'created_at',r.created_at,'reason',r.reason,'currency','IQD',
   'total',r.total::text,'cash_refund',r.cash_refund::text,'debt_reversed',r.debt_reversed::text,'lines',r.lines,
   'counterparty_name',r.supplier_name,'mode',r.accounting_mode,'invoice_no',p.invoice_no
  ) into v_result
  from public.purchase_returns r join public.purchases p on p.id=r.purchase_id and p.owner_id=v_user
  where r.id=p_id and r.owner_id=v_user;
 end if;
 if v_result is null then raise exception 'return_document_unavailable';end if;
 return v_result;
end $$;
revoke all on function public.get_return_document(text,text,uuid) from public,anon,authenticated;
grant execute on function public.get_return_document(text,text,uuid) to authenticated;
notify pgrst,'reload schema';
