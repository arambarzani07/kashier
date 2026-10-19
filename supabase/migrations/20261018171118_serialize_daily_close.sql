create or replace function private.post_daily_close(p_id uuid,p_day date,p_actual text,p_note text,p_hash text,p_ack boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();payload jsonb;r public.daily_cash_closes%rowtype;v jsonb;expected numeric;t text;begin
 if u is null then raise exception 'close_auth_required';end if;
 if p_id is null or p_actual is null or p_actual!~'^(0|[1-9][0-9]{0,14})$' or p_actual::numeric>100000000000000 or p_note is null or length(btrim(p_note))>500 or p_hash is null or p_hash!~'^[0-9a-f]{64}$' or p_day is null or not isfinite(p_day) or p_ack is distinct from true then raise exception 'close_invalid_request';end if;
 payload:=jsonb_build_object('day',p_day,'actual',p_actual,'note',btrim(p_note),'hash',p_hash);
 perform pg_advisory_xact_lock(hashtextextended('kashier.daily-close.'||u::text,0));
 select * into r from public.daily_cash_closes where id=p_id;
 if found then if r.owner_id<>u or r.request_payload<>payload then raise exception 'close_request_conflict';end if;return jsonb_build_object('scope','daily-close-receipt-v1','owner_id',u,'close',private.daily_close_json(r));end if;
 -- Stable order, brief read locks: existing posts must finish before the closing snapshot.
 perform set_config('lock_timeout','5s',true);
 for t in select unnest(private.owner_restore_tables()) order by 1 loop execute format('lock table public.%I in share row exclusive mode',t);end loop;
 v:=private.daily_close_preview(p_day);
 if v->'close'<>'null'::jsonb then raise exception 'close_day_already_closed';end if;
 if v->>'snapshot_hash'<>p_hash then raise exception 'close_snapshot_changed';end if;
 expected:=(v#>>'{report,cash,closing}')::numeric;
 if expected<>p_actual::numeric and btrim(p_note)='' then raise exception 'close_difference_reason_required';end if;
 insert into public.daily_cash_closes(id,owner_id,day,actual,expected,difference,note,source_hash,report_snapshot,request_payload) values(p_id,u,p_day,p_actual::bigint,expected,p_actual::numeric-expected,btrim(p_note),p_hash,v->'report',payload) returning * into r;
 return jsonb_build_object('scope','daily-close-receipt-v1','owner_id',u,'close',private.daily_close_json(r));
end $$;
