-- Run with the administrative connector for this Kashier database.
-- Catalog/ACL configuration regression only; does not prove user-flow isolation.
-- No business rows are read and no writes or persistent changes are performed.
begin read only;
do $audit$
declare bad text;
begin
 select string_agg(c.relname,', ' order by c.relname) into bad
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind in ('r','p') and not c.relrowsecurity;
 if bad is not null then raise exception 'Public business tables without RLS: %',bad;end if;

 select string_agg(c.relname,', ' order by c.relname) into bad
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind in ('r','p','v','m') and (
 has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
 or has_any_column_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,REFERENCES'));
 if bad is not null then raise exception 'Anonymous relation or column grants: %',bad;end if;

 select string_agg(c.relname,', ' order by c.relname) into bad
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind in ('r','p') and has_table_privilege('authenticated',c.oid,'TRUNCATE');
 if bad is not null then raise exception 'Authenticated TRUNCATE grants bypass RLS: %',bad;end if;

 select string_agg(p.oid::regprocedure::text,', ' order by p.oid::regprocedure::text) into bad
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and (p.prosecdef or has_function_privilege('anon',p.oid,'EXECUTE'));
 if bad is not null then raise exception 'Public definer functions or anonymous RPC access: %',bad;end if;

 select string_agg(c.relname,', ' order by c.relname) into bad
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and c.relkind='v' and not coalesce(c.reloptions @> array['security_invoker=true'],false);
 if bad is not null then raise exception 'Public views not using caller permissions: %',bad;end if;

 if not exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='private' and c.relname='owner_restore_receipts' and c.relrowsecurity
 and not has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
 and not has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
 and not has_any_column_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,REFERENCES')
 and not has_any_column_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,REFERENCES'))
 then raise exception 'Private restore receipts missing or accessible to client roles';end if;
end
$audit$;
select jsonb_build_object(
 'status','PASS',
 'scope','catalog-and-acl-only',
 'public_tables',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p')),
 'public_views',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='v'),
 'public_rpcs',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'),
 'business_rows_read',false,
 'business_writes',false
) as security_configuration_audit;
rollback;
