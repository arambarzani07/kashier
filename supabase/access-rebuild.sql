-- Username access v2. Business records and immutable actor IDs are retained.
create table private.access_accounts (
 username text primary key check (username ~ '^[a-z0-9][a-z0-9._-]{2,39}$'),
 user_id uuid unique references auth.users(id),
 owner_id uuid references auth.users(id),
 request_id uuid unique not null,
 name text not null check (char_length(name) between 1 and 100),
 provisioning jsonb not null default '{}',
 must_change boolean not null default false,
 invalidated_at timestamptz,
 created_at timestamptz not null default now(),
 check (owner_id is null or owner_id <> user_id)
);
alter table private.access_accounts enable row level security;
revoke all on private.access_accounts from public,anon,authenticated;
create table private.access_attempts (key text primary key, window_at timestamptz not null, attempts integer not null);
alter table private.access_attempts enable row level security;
revoke all on private.access_attempts from public,anon,authenticated;
create table private.access_events (
 id uuid primary key default gen_random_uuid(), actor_id uuid not null,
 user_id uuid not null, kind text not null, created_at timestamptz not null default now()
);
alter table private.access_events enable row level security;
revoke all on private.access_events from public,anon,authenticated;

-- All access decisions use server-held rows and real Auth sessions, never user_metadata.
create function private.access_allowed(p_owner_only boolean default false) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare a private.access_accounts%rowtype; sid uuid;
begin
 if auth.uid() is null then return false; end if;
 select * into a from private.access_accounts where user_id=auth.uid();
 -- Existing owners remain compatible until they choose their username.
 if not found then return not exists(select 1 from public.store_cashiers where member_id=auth.uid()); end if;
 if a.must_change or (p_owner_only and a.owner_id is not null) then return false; end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid; exception when others then return false; end;
 if not exists(select 1 from auth.sessions where id=sid and user_id=a.user_id and (not_after is null or not_after>now())
   and (a.invalidated_at is null or created_at>a.invalidated_at)) then return false; end if;
 if a.owner_id is not null and not exists(select 1 from public.store_cashiers
   where owner_id=a.owner_id and member_id=a.user_id and enabled and accepted_at is not null) then return false; end if;
 return true;
end $$;
revoke all on function private.access_allowed(boolean) from public,anon;
grant execute on function private.access_allowed(boolean) to authenticated;
create function private.assert_access(p_owner_only boolean) returns void
language plpgsql stable security definer set search_path='' as $$
begin if not private.access_allowed(p_owner_only) then raise exception 'access_denied'; end if; end $$;
revoke all on function private.assert_access(boolean) from public,anon;
grant execute on function private.assert_access(boolean) to authenticated;

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
 and p.proname<>'access_admin'
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

-- A single service-only entry point. The Edge Function validates the caller's JWT
-- with Auth before supplying p_actor. Browser roles cannot execute this function.
create or replace function public.access_admin(p_action text,p_actor uuid,p_body jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare a private.access_accounts%rowtype; target private.access_accounts%rowtype;
 m public.store_cashiers%rowtype; uname text; uid uuid; rid uuid; stamp timestamptz:=clock_timestamp();
 k text; attempt_count integer; payload jsonb; old jsonb;
begin
 if current_setting('role')<>'service_role' then raise exception 'access_denied'; end if;
 if p_action='login' then
  uname:=lower(btrim(coalesce(p_body->>'username','')));
  -- Per-identity and per-network budgets include unknown usernames.
  foreach k in array array['u:'||uname,'ip:'||coalesce(p_body->>'network','unknown')] loop
   insert into private.access_attempts(key,window_at,attempts) values(k,stamp,1)
   on conflict(key) do update set window_at=case when private.access_attempts.window_at<stamp-interval '10 minutes' then stamp else private.access_attempts.window_at end,
    attempts=case when private.access_attempts.window_at<stamp-interval '10 minutes' then 1 else private.access_attempts.attempts+1 end
   returning attempts into attempt_count;
   if attempt_count>(case when k like 'u:%' then 12 else 120 end) then return jsonb_build_object('limited',true); end if;
  end loop;
  delete from private.access_attempts where window_at<stamp-interval '1 day';
  select * into a from private.access_accounts where username=uname and user_id is not null;
  return jsonb_build_object('email',coalesce((select email from auth.users where id=a.user_id),'unknown-login@accounts.kashier.invalid'));
 end if;
 if p_actor is null or not exists(select 1 from auth.users where id=p_actor) then raise exception 'access_denied'; end if;
 select * into a from private.access_accounts where user_id=p_actor;
 if not exists(select 1 from auth.sessions where id=(p_body->>'_session')::uuid and user_id=p_actor
  and (a.invalidated_at is null or created_at>a.invalidated_at)) then raise exception 'access_session_revoked'; end if;
 if p_action='profile' then
  if not found then return jsonb_build_object('needs_username',true,'role','owner'); end if;
  if a.owner_id is not null then
   select * into m from public.store_cashiers where owner_id=a.owner_id and member_id=p_actor;
   if not found or not m.enabled then raise exception 'access_disabled'; end if;
  end if;
  -- A temporary password session may only reach profile/change-password.
  return jsonb_build_object('username',a.username,'name',a.name,'role',coalesce(m.role,'owner'),
   'owner_id',a.owner_id,'must_change',a.must_change,'needs_username',false);
 end if;
 if p_action='bind' then
  uname:=lower(btrim(coalesce(p_body->>'username','')));
  if uname !~ '^[a-z0-9][a-z0-9._-]{2,39}$' or char_length(btrim(coalesce(p_body->>'name',''))) not between 1 and 100 then raise exception 'access_invalid'; end if;
  if a.user_id is not null then
   if a.username=uname then return jsonb_build_object('ok',true); end if;
   raise exception 'access_conflict';
  end if;
  -- Do not turn an existing staff membership into a new store owner.
  if exists(select 1 from public.store_cashiers where member_id=p_actor) then raise exception 'access_legacy_staff'; end if;
  insert into private.access_accounts(username,user_id,request_id,name) values(uname,p_actor,gen_random_uuid(),btrim(p_body->>'name'));
  insert into private.access_events(actor_id,user_id,kind) values(p_actor,p_actor,'username');
  return jsonb_build_object('ok',true);
 end if;
 if p_action='password_done' then
  if a.user_id is null then raise exception 'access_denied'; end if;
  update private.access_accounts set must_change=false where user_id=p_actor;
  insert into private.access_events(actor_id,user_id,kind) values(p_actor,p_actor,'password_change');
  return jsonb_build_object('ok',true);
 end if;
 if a.user_id is null or a.must_change or a.owner_id is not null then raise exception 'access_denied'; end if;
 -- Owner-only administration never accepts arbitrary foreign user IDs.
 if p_action='list' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('username',x.username,'must_change',x.must_change,'last_sign_in_at',u.last_sign_in_at,'version',c.version::text) order by c.created_at,c.id)
   from public.store_cashiers c join private.access_accounts x on x.user_id=c.member_id and x.owner_id=c.owner_id
   join auth.users u on u.id=c.member_id where c.owner_id=p_actor),'[]'::jsonb));
 end if;
 if p_action='reserve' then
  rid:=(p_body->>'request_id')::uuid; uname:=lower(btrim(coalesce(p_body->>'username','')));
  if uname !~ '^[a-z0-9][a-z0-9._-]{2,39}$' or char_length(btrim(coalesce(p_body->>'name',''))) not between 1 and 100
   or char_length(btrim(coalesce(p_body->>'store',''))) not between 1 and 100 or coalesce(p_body->>'role','') not in ('cashier','manager') then raise exception 'access_invalid'; end if;
  perform pg_advisory_xact_lock(hashtextextended('access.owner.'||p_actor::text,0));
  select * into target from private.access_accounts where request_id=rid;
  if found then
   if target.owner_id<>p_actor or target.username<>uname or target.name<>btrim(p_body->>'name') or target.provisioning<>(p_body-'_session'-'password'-'action') then raise exception 'access_conflict'; end if;
  else
   if (select count(*) from private.access_accounts where owner_id=p_actor)>=50 then raise exception 'access_limit'; end if;
   insert into private.access_accounts(username,owner_id,request_id,name,must_change,provisioning) values(uname,p_actor,rid,btrim(p_body->>'name'),true,p_body-'_session'-'password'-'action') returning * into target;
  end if;
  select id into uid from auth.users where email=rid::text||'@accounts.kashier.invalid';
  return jsonb_build_object('email',rid::text||'@accounts.kashier.invalid','user_id',uid,'finished',target.user_id is not null);
 end if;
 if p_action='finish' then
  rid:=(p_body->>'request_id')::uuid;
  select * into target from private.access_accounts where request_id=rid and owner_id=p_actor for update;
  if not found then raise exception 'access_denied'; end if;
  if target.provisioning<>(p_body-'_session'-'password'-'action') then raise exception 'access_conflict'; end if;
  select id into uid from auth.users where email=rid::text||'@accounts.kashier.invalid';
  if uid is null then raise exception 'access_incomplete'; end if;
  if target.user_id is not null then return jsonb_build_object('ok',true,'user_id',target.user_id); end if;
  if char_length(btrim(coalesce(p_body->>'store',''))) not between 1 and 100 or coalesce(p_body->>'role','') not in ('cashier','manager') then raise exception 'access_invalid'; end if;
  update private.access_accounts set user_id=uid where request_id=rid;
  insert into public.store_cashiers(owner_id,member_id,member_name,store_name,role,accepted_at,enabled,can_discount,can_credit,can_repay,can_refund,can_partial_refund)
   values(p_actor,uid,target.name,btrim(p_body->>'store'),p_body->>'role',stamp,coalesce((p_body->>'enabled')::boolean,true),coalesce((p_body->>'discount')::boolean,false),coalesce((p_body->>'credit')::boolean,false),coalesce((p_body->>'repay')::boolean,false),coalesce((p_body->>'refund')::boolean,false),coalesce((p_body->>'partial')::boolean,false));
  insert into private.access_events(actor_id,user_id,kind) values(p_actor,uid,'create');
  return jsonb_build_object('ok',true,'user_id',uid);
 end if;
 uid:=(p_body->>'user_id')::uuid;
 select * into target from private.access_accounts where user_id=uid and owner_id=p_actor for update;
 if not found then raise exception 'access_denied'; end if;
 select * into m from public.store_cashiers where owner_id=p_actor and member_id=uid for update;
 if p_action='reset_begin' or p_action='revoke' then
  update private.access_accounts set invalidated_at=stamp,must_change=case when p_action='reset_begin' then true else must_change end where user_id=uid;
  insert into private.access_events(actor_id,user_id,kind) values(p_actor,uid,p_action);
  return jsonb_build_object('ok',true,'user_id',uid);
 end if;
 if p_action='update' then
  if p_body->>'version' is null or m.version<>(p_body->>'version')::bigint then raise exception 'access_changed'; end if;
  if coalesce(p_body->>'role','') not in ('cashier','manager') or char_length(btrim(coalesce(p_body->>'name',''))) not between 1 and 100
   or char_length(btrim(coalesce(p_body->>'store',''))) not between 1 and 100 or jsonb_typeof(p_body->'enabled')<>'boolean' then raise exception 'access_invalid'; end if;
  update public.store_cashiers set member_name=btrim(p_body->>'name'),store_name=btrim(p_body->>'store'),role=p_body->>'role',enabled=(p_body->>'enabled')::boolean,
   can_discount=coalesce((p_body->>'discount')::boolean,false),can_credit=coalesce((p_body->>'credit')::boolean,false),can_repay=coalesce((p_body->>'repay')::boolean,false),
   can_refund=coalesce((p_body->>'refund')::boolean,false),can_partial_refund=coalesce((p_body->>'partial')::boolean,false),version=version+1,updated_at=stamp where id=m.id;
  update private.access_accounts set name=btrim(p_body->>'name'),invalidated_at=case when not (p_body->>'enabled')::boolean then stamp else invalidated_at end where user_id=uid;
  insert into private.access_events(actor_id,user_id,kind) values(p_actor,uid,'permissions');
  return jsonb_build_object('ok',true);
 end if;
 raise exception 'access_invalid';
end $$;
revoke all on function public.access_admin(text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.access_admin(text,uuid,jsonb) to service_role;
notify pgrst,'reload schema';
