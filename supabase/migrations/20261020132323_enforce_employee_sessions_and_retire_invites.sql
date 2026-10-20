-- Add an independent restrictive gate to every exposed business table.
do $$declare t record; owner_only boolean; begin
 for t in select tablename from pg_tables where schemaname='public' loop
  owner_only:=t.tablename not in ('store_cashiers','staff_actions');
  execute format('create policy access_account_gate on public.%I as restrictive for all to authenticated using (private.access_allowed(%L)) with check (private.access_allowed(%L))',t.tablename,owner_only,owner_only);
 end loop;
end $$;
-- Guard invoker RPCs too: a SECURITY DEFINER implementation otherwise bypasses RLS.
do $$declare f record; d text; owner_only boolean; begin
 for f in select p.oid,p.proname,l.lanname from pg_proc p
 join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
 where n.nspname='public' and p.proowner=(select oid from pg_roles where rolname='postgres')
 and l.lanname in ('sql','plpgsql') and p.prokind='f'
 and not exists(select 1 from pg_depend where classid='pg_proc'::regclass and objid=p.oid and deptype='e')
 loop
  owner_only:= f.proname not like '%cashier%' and f.proname not in ('get_staff_workspace','get_manager_sales_report','get_manager_receipt');
  -- Legacy invitation endpoints are deliberately retired, not repurposed.
  if f.proname in ('save_store_cashier','accept_store_cashier') then
   execute format('revoke execute on function %s from authenticated',f.oid::regprocedure);
   execute format('revoke execute on function private.%I(%s) from authenticated',f.proname,pg_get_function_identity_arguments(f.oid)); continue;
  end if;
  d:=pg_get_functiondef(f.oid);
  if f.lanname='sql' then d:=replace(d,'AS $function$',format('AS $function$select private.assert_access(%L);',owner_only));
  else d:=regexp_replace(d,'\mBEGIN\M',format('BEGIN PERFORM private.assert_access(%L);',owner_only),'i'); end if;
  execute d;
 end loop;
end $$;
