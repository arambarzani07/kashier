-- Effective end-user grants and RLS role targets; excludes business data.
\pset format unaligned
\pset tuples_only on
with items as (
 select 'routine'::text kind,n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' identity,
 md5(concat_ws('|',has_schema_privilege('anon',n.oid,'USAGE')::text,has_schema_privilege('authenticated',n.oid,'USAGE')::text,
 has_function_privilege('anon',p.oid,'EXECUTE')::text,has_function_privilege('authenticated',p.oid,'EXECUTE')::text)) rights
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private')
 union all
 select 'relation',n.nspname||'.'||c.relname||':'||c.relkind::text,
 md5(concat_ws('|',
 has_table_privilege('anon',c.oid,'SELECT')::text,has_table_privilege('anon',c.oid,'INSERT')::text,
 has_table_privilege('anon',c.oid,'UPDATE')::text,has_table_privilege('anon',c.oid,'DELETE')::text,
 has_table_privilege('authenticated',c.oid,'SELECT')::text,has_table_privilege('authenticated',c.oid,'INSERT')::text,
 has_table_privilege('authenticated',c.oid,'UPDATE')::text,has_table_privilege('authenticated',c.oid,'DELETE')::text,
 (select string_agg(a.attname||':'||
 has_column_privilege('authenticated',c.oid,a.attnum,'SELECT')::text||','||
 has_column_privilege('authenticated',c.oid,a.attnum,'INSERT')::text||','||
 has_column_privilege('authenticated',c.oid,a.attnum,'UPDATE')::text,'|' order by a.attnum)
 from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)
 )) rights
 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind in ('r','p','v','m')
 union all
 select 'policy',n.nspname||'.'||c.relname||'/'||p.polname,
 md5(concat_ws('|',p.polcmd::text,
 (select string_agg(case when x.oid=0 then 'PUBLIC' else pg_get_userbyid(x.oid) end,',' order by case when x.oid=0 then 'PUBLIC' else pg_get_userbyid(x.oid) end)
 from unnest(p.polroles) x(oid)),
 pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid)))
 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private')
 union all
 select 'schema',n.nspname,
 md5(concat_ws('|',has_schema_privilege('anon',n.oid,'USAGE')::text,
 has_schema_privilege('authenticated',n.oid,'USAGE')::text,
 has_schema_privilege('anon',n.oid,'CREATE')::text,
 has_schema_privilege('authenticated',n.oid,'CREATE')::text))
 from pg_namespace n where n.nspname in ('public','private')
)
select 'AX_SEM|'||kind||'|'||identity||'|'||rights from items order by kind,identity;
