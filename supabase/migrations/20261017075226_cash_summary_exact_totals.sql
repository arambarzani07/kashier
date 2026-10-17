create or replace function public.get_cash_summary()
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
 'balance',coalesce((select balance from public.cash_accounts where owner_id=(select auth.uid())),0)::text,
 'sales',coalesce(sum(amount) filter(where kind='sale'),0)::text,
 'deposits',coalesce(sum(amount) filter(where kind='deposit'),0)::text,
 'withdrawals',coalesce(sum(amount) filter(where kind='withdrawal'),0)::text,
 'expenses',coalesce(sum(amount) filter(where kind='expense'),0)::text,
 'count',count(*)::text
 ) from public.cash_movements where owner_id=(select auth.uid());
$$;
notify pgrst,'reload schema';
