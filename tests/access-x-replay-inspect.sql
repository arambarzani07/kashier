-- Schema-only compare proxy. Requires clean temporary DB after 72 migrations.
-- Do not claim actual business backup restoration from a schema-only migration replay.
-- Print only schema object names/counts (NO database rows) for diagnostics.
\pset format unaligned
\pset tuples_only on
select 'AX_REPLAY_ROUTINE|'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('public','private')
order by 1;
select 'AX_REPLAY_COUNT|'||label||'='||amount::text from (
 select 'relations' label,count(*) amount from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','private') and c.relkind in ('r','p','v','m')
 union all select 'routines',count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','private')
 union all select 'policies',count(*) from pg_policy p join pg_class c on c.oid=p.polrelid
 join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private')
 union all select 'triggers',count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
 join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and not t.tgisinternal
) a order by label;
do $access_x_replay$
declare v integer;
begin
 select count(*) into v from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','private') and c.relkind in ('r','p','v','m');
 if v<>35 then raise exception 'schema relations mismatch: expected 35 got %',v;end if;
 select count(*) into v from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private');
 if v<>148 then raise exception 'schema routines mismatch: expected 148 got %',v;end if;
 select count(*) into v from pg_policy p join pg_class c on c.oid=p.polrelid
 join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private');
 if v<>36 then raise exception 'schema policies mismatch: expected 36 got %',v;end if;
 select count(*) into v from pg_trigger t join pg_class c on c.oid=t.tgrelid
 join pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and n.nspname in ('public','private');
 if v<>7 then raise exception 'schema user triggers mismatch: expected 7 got %',v;end if;
end $access_x_replay$;
select 'PASS: relation/routine/policy/trigger counts match live 2026-10-20 snapshot' as schema_counts;
