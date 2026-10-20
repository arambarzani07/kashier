-- Access X: catalog metadata fingerprint of live public/private schema, without business data.
-- Checked against production 2026-10-20 before any authorization cutover.
-- Intentional DDL changes require security review and a new approved baseline.
-- A match DOES NOT replace pg_dump/replay or prove that historical migrations reproduce this schema.
begin transaction read only;
do $access_x$
declare
 actual jsonb;
 expected jsonb:='{
  "constraints":{"count":291,"fingerprint":"2e6d99ea2cd8e0e285d695c262a97204"},
  "indexes":{"count":139,"fingerprint":"5eff7421cfeb8a7027872d245b243cd8"},
  "policies":{"count":36,"fingerprint":"1aefe671545964cc80916344e7680950"},
  "relations":{"count":35,"fingerprint":"cea69863126211dab44b31e7e2cc5d54"},
  "routines":{"count":148,"fingerprint":"f17ea705354b10a860d7db53d1c413fc"},
  "schemas":{"count":2,"fingerprint":"8f4a3ad9b21a4978998be1f830808c9a"},
  "triggers":{"count":7,"fingerprint":"085344aa8075e43eb095d7eb68a516da"}
 }'::jsonb;
begin
 with routine as (
  select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' identity,
  md5(pg_get_functiondef(p.oid)||'|ACL='||coalesce(p.proacl::text,'DEFAULT')) digest
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private')
 ), catalog as (
  select n.nspname||'.'||c.relname||':'||c.relkind::text identity,
  md5(concat_ws('|',c.relkind::text,c.relrowsecurity::text,
   coalesce(array_to_string(c.reloptions,','),''),coalesce(c.relacl::text,'DEFAULT'),
   coalesce((select string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod),',' order by a.attnum)
    from pg_attribute a where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped),'')
  )) digest
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private') and c.relkind in ('r','p','v','m')
 ), pol as (
  select n.nspname||'.'||c.relname||'/'||p.polname identity,
  md5(concat_ws('|',p.polcmd::text,p.polroles::text,pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid))) digest
  from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private')
 ), trig as (
  select n.nspname||'.'||c.relname||'/'||t.tgname identity,md5(pg_get_triggerdef(t.oid)) digest
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal and n.nspname in ('public','private')
 ), idx as (
  select n.nspname||'.'||c.relname identity,md5(pg_get_indexdef(c.oid)) digest
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private') and c.relkind in ('i','I')
 ), cons as (
  select n.nspname||'.'||c.relname||'/'||k.conname identity,md5(pg_get_constraintdef(k.oid)) digest
  from pg_constraint k join pg_class c on c.oid=k.conrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','private')
 ), schema_acl as (
  select n.nspname identity,md5(coalesce(n.nspacl::text,'DEFAULT')) digest
  from pg_namespace n where n.nspname in ('public','private')
 ), summary as (
  select 'routines' kind,count(*) as row_count,md5(coalesce(string_agg(identity||'='||digest,E'\n' order by identity),'')) fingerprint from routine
  union all select 'relations',count(*),md5(coalesce(string_agg(identity||'='||digest,E'\n' order by identity),'')) from catalog
  union all select 'policies',count(*),md5(coalesce(string_agg(identity||'='||digest,E'\n' order by identity),'')) from pol
  union all select 'triggers',count(*),md5(coalesce(string_agg(identity||'='||digest,E'\n' order by identity),'')) from trig
  union all select 'indexes',count(*),md5(coalesce(string_agg(identity||'='||digest,E'\n' order by identity),'')) from idx
  union all select 'constraints',count(*),md5(coalesce(string_agg(identity||'='||digest,E'\n' order by identity),'')) from cons
  union all select 'schemas',count(*),md5(coalesce(string_agg(identity||'='||digest,E'\n' order by identity),'')) from schema_acl
 )
 select jsonb_object_agg(kind,jsonb_build_object('count',row_count,'fingerprint',fingerprint)) into actual from summary;
 if actual is distinct from expected then
  raise exception 'access_x_schema_drift_detected'
   using detail='Metadata fingerprints differ from the 2026-10-20 reviewed snapshot; inspect exact objects and grants before any deployment. Actual category hashes='||actual::text||'; Expected category hashes='||expected::text;
 end if;
end
$access_x$;
select 'PASS: all seven public/private catalog fingerprint groups match reviewed baseline, no business data read' as access_x_schema;
rollback;
