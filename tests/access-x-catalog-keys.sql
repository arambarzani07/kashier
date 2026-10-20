-- Isolated DB metadata fingerprints; no rows from business tables, no secrets.
\pset format unaligned
\pset tuples_only on
with items as (
 select 'routine'::text kind,
  n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' identity,
  md5(pg_get_functiondef(p.oid)) definition_hash,md5(coalesce(p.proacl::text,'DEFAULT')) access_hash
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private')
 union all
 select 'relation',n.nspname||'.'||c.relname||':'||c.relkind::text,
 md5(concat_ws('|',c.relkind::text,c.relrowsecurity::text,coalesce(array_to_string(c.reloptions,','),''),
 coalesce((select string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod),',' order by a.attnum)
 from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),''))),
 md5(coalesce(c.relacl::text,'DEFAULT'))
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','private') and c.relkind in ('r','p','v','m')
 union all
 select 'policy',n.nspname||'.'||c.relname||'/'||p.polname,
 md5(concat_ws('|',p.polcmd::text,pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid))),
 md5(p.polroles::text)
 from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','private')
 union all
 select 'schema',n.nspname,md5(n.nspname),md5(coalesce(n.nspacl::text,'DEFAULT'))
 from pg_namespace n where n.nspname in ('public','private')
)
select 'AX_META|'||kind||'|'||identity||'|'||definition_hash||'|'||access_hash from items order by kind,identity;
