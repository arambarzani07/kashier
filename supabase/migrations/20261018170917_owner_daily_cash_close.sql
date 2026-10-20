create table public.daily_cash_closes(
 id uuid primary key,owner_id uuid not null references auth.users(id),day date not null,
 actual bigint not null check(actual between 0 and 100000000000000),expected numeric(40,0) not null check(expected>=0),difference numeric(40,0) not null,
 note text not null check(length(note)<=500 and note=btrim(note)),source_hash text not null check(source_hash~'^[0-9a-f]{64}$'),
 report_snapshot jsonb not null,request_payload jsonb not null,created_at timestamptz not null default now(),unique(owner_id,day),
 check(difference=actual-expected),check(difference=0 or length(note)>0)
);
alter table public.daily_cash_closes enable row level security;
revoke all on public.daily_cash_closes from public,anon,authenticated;
grant select on public.daily_cash_closes to authenticated;
create policy daily_cash_closes_owner on public.daily_cash_closes for select to authenticated using(owner_id=(select auth.uid()));
create function private.daily_close_json(r public.daily_cash_closes) returns jsonb language sql immutable set search_path='' as $$select to_jsonb(r)||jsonb_build_object('actual',r.actual::text,'expected',r.expected::text,'difference',r.difference::text)$$;
revoke all on function private.daily_close_json(public.daily_cash_closes) from public,anon,authenticated;
create function private.daily_close_preview(p_day date) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r jsonb;h text;c public.daily_cash_closes%rowtype;begin
 if u is null then raise exception 'close_auth_required';end if;if p_day is null or not isfinite(p_day) or p_day<'0001-01-01'::date or p_day>=(now() at time zone 'Asia/Baghdad')::date then raise exception 'close_completed_day_required';end if;
 r:=public.get_daily_report(p_day)-'generated_at';h:=encode(sha256(convert_to(jsonb_build_object('owner_id',u,'report',r)::text,'UTF8')),'hex');
 select * into c from public.daily_cash_closes where owner_id=u and day=p_day;
 return jsonb_build_object('scope','daily-close-preview-v1','owner_id',u,'day',p_day,'currency','IQD','timezone','Asia/Baghdad','snapshot_hash',h,'report',r,'close',case when c.id is null then null else private.daily_close_json(c) end);
end $$;
create function private.post_daily_close(p_id uuid,p_day date,p_actual text,p_note text,p_hash text,p_ack boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();payload jsonb;r public.daily_cash_closes%rowtype;v jsonb;expected numeric;t text;begin
 if u is null then raise exception 'close_auth_required';end if;
 if p_id is null or p_actual is null or p_actual!~'^(0|[1-9][0-9]{0,14})$' or p_actual::numeric>100000000000000 or p_note is null or length(btrim(p_note))>500 or p_hash is null or p_hash!~'^[0-9a-f]{64}$' or p_day is null or not isfinite(p_day) or p_ack is distinct from true then raise exception 'close_invalid_request';end if;
 payload:=jsonb_build_object('day',p_day,'actual',p_actual,'note',btrim(p_note),'hash',p_hash);
 perform pg_advisory_xact_lock(hashtextextended('kashier.daily-close.'||u::text,0));
 select * into r from public.daily_cash_closes where id=p_id;
 if found then if r.owner_id<>u or r.request_payload<>payload then raise exception 'close_request_conflict';end if;return jsonb_build_object('scope','daily-close-receipt-v1','owner_id',u,'close',private.daily_close_json(r));end if;
 -- Stable order, brief read locks: existing posts must finish before the closing snapshot.
 perform set_config('lock_timeout','5s',true);
 for t in select unnest(private.owner_restore_tables()) order by 1 loop execute format('lock table public.%I in share mode',t);end loop;
 v:=private.daily_close_preview(p_day);
 if v->'close'<>'null'::jsonb then raise exception 'close_day_already_closed';end if;
 if v->>'snapshot_hash'<>p_hash then raise exception 'close_snapshot_changed';end if;
 expected:=(v#>>'{report,cash,closing}')::numeric;
 if expected<>p_actual::numeric and btrim(p_note)='' then raise exception 'close_difference_reason_required';end if;
 insert into public.daily_cash_closes(id,owner_id,day,actual,expected,difference,note,source_hash,report_snapshot,request_payload) values(p_id,u,p_day,p_actual::bigint,expected,p_actual::numeric-expected,btrim(p_note),p_hash,v->'report',payload) returning * into r;
 return jsonb_build_object('scope','daily-close-receipt-v1','owner_id',u,'close',private.daily_close_json(r));
end $$;
revoke all on function private.daily_close_preview(date),private.post_daily_close(uuid,date,text,text,text,boolean) from public,anon,authenticated;
grant execute on function private.daily_close_preview(date),private.post_daily_close(uuid,date,text,text,text,boolean) to authenticated;
create function public.get_daily_close_preview(p_day date) returns jsonb language sql security invoker set search_path='' as $$select private.daily_close_preview(p_day)$$;
create function public.post_daily_close(p_id uuid,p_day date,p_actual text,p_note text,p_hash text,p_ack boolean) returns jsonb language sql security invoker set search_path='' as $$select private.post_daily_close(p_id,p_day,p_actual,p_note,p_hash,p_ack)$$;
revoke all on function public.get_daily_close_preview(date),public.post_daily_close(uuid,date,text,text,text,boolean) from public,anon,authenticated;
grant execute on function public.get_daily_close_preview(date),public.post_daily_close(uuid,date,text,text,text,boolean) to authenticated;

create or replace function private.owner_restore_tables() returns text[] language sql immutable set search_path='' as $$select array['products','suppliers','customers','store_cashiers','purchases','stock_adjustments','sales','sale_reversals','sale_returns','purchase_reversals','purchase_returns','cash_movements','debt_entries','supplier_entries','cash_accounts','customer_balances','supplier_balances','product_stock','inventory_cost_state','customer_payment_allocations','customer_allocation_reversals','customer_installment_plans','customer_installment_cancellations','supplier_payment_allocations','inventory_cost_bases','inventory_cost_basis_cancellations','stock_movements','inventory_cost_movements','staff_actions','daily_cash_closes']::text[]$$;
create or replace function public.export_owner_data() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_table text;v_key text;v_count bigint;v_size bigint;v_total bigint:=0;v_bytes bigint:=0;v_rows jsonb;v_counts jsonb:='{}'::jsonb;v_tables jsonb:='{}'::jsonb;
 v_names text[]:=array['products','product_stock','stock_movements','stock_adjustments','sales','sale_reversals','sale_returns','purchases','cash_accounts','cash_movements','customers','customer_balances','debt_entries','suppliers','supplier_balances','supplier_entries','purchase_reversals','purchase_returns','supplier_payment_allocations','customer_payment_allocations','customer_allocation_reversals','customer_installment_plans','customer_installment_cancellations','inventory_cost_state','inventory_cost_movements','inventory_cost_bases','inventory_cost_basis_cancellations','store_cashiers','staff_actions','daily_cash_closes'];
begin
 if v_user is null then raise exception 'export_auth_required';end if;
 foreach v_table in array v_names loop
  execute format('select count(*),coalesce(sum(octet_length(to_jsonb(t)::text)),0) from public.%I t where t.owner_id=$1',v_table) into v_count,v_size using v_user;
  v_total:=v_total+v_count;v_bytes:=v_bytes+v_size;
  if v_total>50000 then raise exception 'export_too_many_records';end if;
  if v_bytes>20971520 then raise exception 'export_too_large';end if;
  v_counts:=v_counts||jsonb_build_object(v_table,v_count);
 end loop;
 foreach v_table in array v_names loop
  v_key:=case v_table when 'inventory_cost_state' then 'product_id' when 'product_stock' then 'product_id' when 'cash_accounts' then 'owner_id' when 'customer_balances' then 'customer_id' when 'supplier_balances' then 'supplier_id' else 'id' end;
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by t.%I),''[]''::jsonb) from public.%I t where t.owner_id=$1',v_key,v_table) into v_rows using v_user;
  v_tables:=v_tables||jsonb_build_object(v_table,v_rows);
 end loop;
 return jsonb_build_object('format','kashier-owner-export','version',8,'schema_revision','owner-daily-cash-close-v1','owner_id',v_user,'generated_at',statement_timestamp(),'timezone','Asia/Baghdad','currency','IQD','record_count',v_total,'counts',v_counts,'tables',v_tables,
 'scope','business-data-only','excludes',jsonb_build_array('authentication accounts and sessions','passwords and API keys','database schema and RLS policies','automatic restore'));
end $$;
revoke all on function public.export_owner_data() from public,anon,authenticated;
grant execute on function public.export_owner_data() to authenticated;

create or replace function private.restore_owner_data(p_id uuid,p_raw text,p_sha256 text,p_confirm_empty boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();d jsonb;names text[]:=private.owner_restore_tables();t text;k text;c record;v jsonb;item jsonb;rows jsonb;bad boolean;n bigint;total bigint:=0;wanted bigint;last_number bigint;sequence_called boolean;r private.owner_restore_receipts%rowtype;
begin
 if u is null then raise exception 'restore_auth_required';end if;
 if p_id is null or p_confirm_empty is distinct from true or p_raw is null or octet_length(p_raw)>26214400 or p_sha256 is null or p_sha256!~'^[0-9a-f]{64}$' then raise exception 'restore_invalid_request';end if;
 if encode(sha256(convert_to(p_raw,'UTF8')),'hex')<>p_sha256 then raise exception 'restore_checksum_mismatch';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.restore.'||u::text,0));
 select * into r from private.owner_restore_receipts where owner_id=u and id=p_id;
 if found then if r.sha256<>p_sha256 then raise exception 'restore_request_conflict';end if;return private.owner_restore_status(p_id);end if;
 d:=p_raw::jsonb;
 if d->>'format' is distinct from 'kashier-owner-export' or not ((d->>'version'='7' and d->>'schema_revision'='consented-cashier-access-v1') or (d->>'version'='8' and d->>'schema_revision'='owner-daily-cash-close-v1')) or d->>'version' is null or d->>'schema_revision' is null or d->>'owner_id' is distinct from u::text or d->>'scope' is distinct from 'business-data-only' or d->>'currency' is distinct from 'IQD' or d->>'timezone' is distinct from 'Asia/Baghdad' or jsonb_typeof(d->'tables') is distinct from 'object' or jsonb_typeof(d->'counts') is distinct from 'object' then raise exception 'restore_invalid_file';end if;
 if (select count(*) from jsonb_object_keys(d->'tables'))<>(case when d->>'version'='8' then 30 else 29 end) or (select count(*) from jsonb_object_keys(d->'counts'))<>(case when d->>'version'='8' then 30 else 29 end) then raise exception 'restore_invalid_file';end if;
 -- Lock every business table in a stable order, closing races with existing posting RPCs.
 perform set_config('lock_timeout','5s',true);
 for t in select unnest(names) order by 1 loop execute format('lock table public.%I in share row exclusive mode',t);end loop;
 foreach t in array names loop
 execute format('select exists(select 1 from public.%I where owner_id=$1)',t) into bad using u;
 if bad then raise exception 'restore_account_not_empty';end if;
 rows:=case when t='daily_cash_closes' and d->>'version'='7' then '[]'::jsonb else d->'tables'->t end;if jsonb_typeof(rows) is distinct from 'array' then raise exception 'restore_invalid_file';end if;
 n:=jsonb_array_length(rows);if (case when t='daily_cash_closes' and d->>'version'='7' then 0 else (d->'counts'->>t)::bigint end) is distinct from n then raise exception 'restore_invalid_file';end if;
 total:=total+n;if total>50000 then raise exception 'restore_too_many_records';end if;
 if exists(select 1 from jsonb_array_elements(rows) x where jsonb_typeof(x)<>'object' or x->>'owner_id' is distinct from u::text) then raise exception 'restore_invalid_file';end if;
 -- Reject schema drift or omitted columns; populate_recordset otherwise silently ignores them.
 for item in select value from jsonb_array_elements(rows) loop
 if (select array_agg(key order by key) from jsonb_object_keys(item) key) is distinct from (select array_agg(attname::text order by attname::text) from pg_attribute where attrelid=format('public.%I',t)::regclass and attnum>0 and not attisdropped) then raise exception 'restore_schema_mismatch';end if;
 end loop;
 -- Never change shared identity sequences. This path recovers IDs already issued by this database.
 for c in select attname,pg_get_serial_sequence(format('public.%I',t),attname) as seq from pg_attribute where attrelid=format('public.%I',t)::regclass and attidentity<>'' loop
 execute format('select last_value,is_called from %s',c.seq) into last_number,sequence_called;
 if exists(select 1 from jsonb_array_elements(rows) x where (x->>c.attname)::bigint<1) then raise exception 'restore_sequence_unavailable';end if;
 select max((x->>c.attname)::bigint) into wanted from jsonb_array_elements(rows) x;
 if wanted is not null and (wanted<1 or wanted>last_number or wanted=last_number and not sequence_called) then raise exception 'restore_sequence_unavailable';end if;
 end loop;
 end loop;
 if total is distinct from (d->>'record_count')::bigint then raise exception 'restore_invalid_file';end if;
 -- All public FK targets must be inside this owner snapshot, never in another owner's live rows.
 for c in select s.relname as source,a.attname as field,z.relname as target,b.attname as target_field
 from pg_constraint f join pg_class s on s.oid=f.conrelid join pg_namespace sn on sn.oid=s.relnamespace join pg_class z on z.oid=f.confrelid join pg_namespace zn on zn.oid=z.relnamespace join pg_attribute a on a.attrelid=s.oid and a.attnum=f.conkey[1] join pg_attribute b on b.attrelid=z.oid and b.attnum=f.confkey[1]
 where f.contype='f' and sn.nspname='public' and zn.nspname='public' and s.relname=any(names) loop
 if exists(select 1 from jsonb_array_elements(d->'tables'->c.source) x where x->>c.field is not null and not exists(select 1 from jsonb_array_elements(d->'tables'->c.target) y where y->>c.target_field=x->>c.field)) then raise exception 'restore_broken_reference';end if;
 end loop;
 foreach t in array array['sales','purchases'] loop
 if exists(select 1 from jsonb_array_elements(d->'tables'->t) x cross join lateral jsonb_array_elements(x->'lines') line where not exists(select 1 from jsonb_array_elements(d#>'{tables,products}') product where product->>'id'=line->>'product_id')) then raise exception 'restore_broken_reference';end if;
 end loop;
 insert into private.owner_restore_receipts(owner_id,id,sha256,record_count,source_generated_at,transaction_id) values(u,p_id,p_sha256,total,(d->>'generated_at')::timestamptz,txid_current());
 -- Credit sale charges refer forward to sales through an already-deferred FK.

 foreach t in array names loop
 if t='sales' then
 execute 'insert into public.debt_entries overriding system value select (jsonb_populate_record(null::public.debt_entries,x)).* from jsonb_array_elements($1) x where x->>''kind''=''charge''' using d#>'{tables,debt_entries}';
 end if;
 rows:=case when t='daily_cash_closes' and d->>'version'='7' then '[]'::jsonb else d->'tables'->t end;
 if t='debt_entries' then select coalesce(jsonb_agg(x),'[]'::jsonb) into rows from jsonb_array_elements(rows) x where x->>'kind'<>'charge';end if;
 if t='store_cashiers' then
 select coalesce(jsonb_agg(x||jsonb_build_object('enabled',false,'accepted_at',null,'can_discount',false,'can_credit',false,'can_repay',false,'can_refund',false,'can_partial_refund',false)),'[]'::jsonb) into rows from jsonb_array_elements(rows) x;
 end if;
 execute format('insert into public.%I overriding system value select * from jsonb_populate_recordset(null::public.%I,$1)',t,t) using rows;
 end loop;
 set constraints all immediate;
 update private.owner_restore_receipts set completed_at=clock_timestamp() where owner_id=u and id=p_id;
 return private.owner_restore_status(p_id);
exception when unique_violation or foreign_key_violation or check_violation or not_null_violation then raise exception 'restore_conflict_or_invalid_data';
end $$;

notify pgrst,'reload schema';
