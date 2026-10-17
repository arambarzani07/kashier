create function public.get_dashboard_summary() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_today date:=(statement_timestamp() at time zone 'Asia/Baghdad')::date;
begin
 if v_user is null then raise exception 'dashboard_auth_required';end if;
 return jsonb_build_object('scope','owner-dashboard-v1','owner_id',v_user,'generated_at',statement_timestamp(),'today',v_today,'timezone','Asia/Baghdad','currency','IQD',
  'cash_balance',coalesce((select balance::text from public.cash_accounts where owner_id=v_user),'0'),
  'customer_balance',(select coalesce(sum(balance::numeric),0)::text from public.customer_debt_catalog),
  'supplier_balance',(select coalesce(sum(balance::numeric),0)::text from public.supplier_debt_catalog),
  'product_count',(select count(*)::text from public.products where owner_id=v_user),
  'low_stock_count',(select count(*)::text from public.low_stock_catalog),
  'expired_count',(select count(*)::text from public.products p join public.product_stock s on s.product_id=p.id and s.owner_id=p.owner_id where p.owner_id=v_user and p.expiry_date<v_today and s.quantity_units>0));
end $$;
revoke all on function public.get_dashboard_summary() from public,anon,authenticated;
grant execute on function public.get_dashboard_summary() to authenticated;
notify pgrst,'reload schema';
