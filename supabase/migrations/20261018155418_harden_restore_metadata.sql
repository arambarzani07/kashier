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
 if d->>'format' is distinct from 'kashier-owner-export' or d->>'version' is distinct from '7' or d->>'schema_revision' is distinct from 'consented-cashier-access-v1' or d->>'owner_id' is distinct from u::text or d->>'scope' is distinct from 'business-data-only' or d->>'currency' is distinct from 'IQD' or d->>'timezone' is distinct from 'Asia/Baghdad' or jsonb_typeof(d->'tables') is distinct from 'object' or jsonb_typeof(d->'counts') is distinct from 'object' then raise exception 'restore_invalid_file';end if;
 if (select count(*) from jsonb_object_keys(d->'tables'))<>29 or (select count(*) from jsonb_object_keys(d->'counts'))<>29 then raise exception 'restore_invalid_file';end if;
 -- Lock every business table in a stable order, closing races with existing posting RPCs.
 perform set_config('lock_timeout','5s',true);
 for t in select unnest(names) order by 1 loop execute format('lock table public.%I in share row exclusive mode',t);end loop;
 foreach t in array names loop
 execute format('select exists(select 1 from public.%I where owner_id=$1)',t) into bad using u;
 if bad then raise exception 'restore_account_not_empty';end if;
 rows:=d->'tables'->t;if jsonb_typeof(rows) is distinct from 'array' then raise exception 'restore_invalid_file';end if;
 n:=jsonb_array_length(rows);if (d->'counts'->>t)::bigint is distinct from n then raise exception 'restore_invalid_file';end if;
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
 rows:=d->'tables'->t;
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
