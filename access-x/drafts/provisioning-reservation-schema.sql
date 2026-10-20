-- DRAFT ONLY — NOT A LIVE MIGRATION. Do not execute on the production project.
-- Designed for isolated replay AFTER backup / restore and primary-manager authorization review.
-- Never copy this into supabase/migrations until the security review and isolated SQL tests pass.
--
-- All functions are exposed solely to the trusted *server-side service_role*.
-- A verified user JWT + fresh manager reauthentication MUST be checked by the server
-- BEFORE invoking any of these privileged RPCs. No public client receives the key.

create table public.access_x_provisioning_requests (
  owner_id uuid not null references auth.users(id),
  request_id uuid not null,
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  state text not null default 'reserved'
    check (state in ('reserved','claimed','identity_created','provisioned','reconciliation')),
  member_id uuid unique references auth.users(id),
  claimed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (owner_id, request_id),
  check (
    (state in ('reserved','claimed') and member_id is null)
    or (state in ('identity_created','provisioned') and member_id is not null)
    or state = 'reconciliation'
  ),
  check (claimed_at is null or state <> 'reserved')
);

create table public.access_x_provisioning_events (
  id bigint generated always as identity primary key,
  owner_id uuid not null,
  request_id uuid not null,
  from_state text,
  to_state text not null,
  member_id uuid,
  created_at timestamptz not null default now(),
  foreign key (owner_id,request_id)
    references public.access_x_provisioning_requests(owner_id,request_id),
  check (to_state in ('reserved','claimed','identity_created','provisioned','reconciliation'))
);

alter table public.access_x_provisioning_requests enable row level security;
alter table public.access_x_provisioning_events enable row level security;
-- No anon/authenticated RLS policies: no direct Data API reads or writes.
revoke all on public.access_x_provisioning_requests,public.access_x_provisioning_events
 from public,anon,authenticated;
grant select,insert,update on public.access_x_provisioning_requests to service_role;
grant select,insert on public.access_x_provisioning_events to service_role;
grant usage,select on sequence public.access_x_provisioning_events_id_seq to service_role;

-- Server-invoked atomic reservation. Caller owner_id is NOT trustworthy; the
-- external server must first verify the JWT and primary manager in the database.
create function public.access_x_reserve_request(p_owner uuid,p_request uuid,p_hash text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r public.access_x_provisioning_requests%rowtype;
begin
 if p_owner is null or p_request is null or p_hash is null
    or p_hash !~ '^[0-9a-f]{64}$' then raise exception 'access_x_invalid_request';end if;
 insert into public.access_x_provisioning_requests(owner_id,request_id,payload_hash)
 values(p_owner,p_request,p_hash) on conflict(owner_id,request_id) do nothing;
 select * into r from public.access_x_provisioning_requests
 where owner_id=p_owner and request_id=p_request for update;
 if r.payload_hash<>p_hash then raise exception 'access_x_request_conflict';end if;
 return jsonb_build_object('state',case r.state
   when 'reserved' then 'new'
   when 'provisioned' then 'provisioned'
   when 'claimed' then 'pending'
   when 'identity_created' then 'pending'
   else 'reconciliation' end,
  'payloadHash',r.payload_hash,'memberId',r.member_id);
end $$;
revoke all on function public.access_x_reserve_request(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.access_x_reserve_request(uuid,uuid,text) to service_role;

-- Compare-and-swap: only one invocation may claim a reservation for Auth createUser.
-- NO automatic lease timeout/reclaim: after an uncertain network outcome, review manually.
create function public.access_x_claim_request(p_owner uuid,p_request uuid,p_hash text)
returns boolean language plpgsql security invoker set search_path='' as $$
declare changed integer;
begin
 update public.access_x_provisioning_requests
 set state='claimed',claimed_at=now(),updated_at=now()
 where owner_id=p_owner and request_id=p_request and payload_hash=p_hash and state='reserved';
 get diagnostics changed = row_count;
 if changed=1 then
  insert into public.access_x_provisioning_events(owner_id,request_id,from_state,to_state)
  values(p_owner,p_request,'reserved','claimed');
 end if;
 return changed=1;
end $$;
revoke all on function public.access_x_claim_request(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.access_x_claim_request(uuid,uuid,text) to service_role;

-- Called only after Auth admin createUser result is verified.
create function public.access_x_record_identity(p_owner uuid,p_request uuid,p_member uuid)
returns boolean language plpgsql security invoker set search_path='' as $$
declare changed integer;r public.access_x_provisioning_requests%rowtype;
begin
 if p_member is null or p_member=p_owner then raise exception 'access_x_invalid_member';end if;
 select * into r from public.access_x_provisioning_requests
 where owner_id=p_owner and request_id=p_request for update;
 if not found then raise exception 'access_x_request_missing';end if;
 if r.state='identity_created' and r.member_id=p_member then return true;end if;
 if r.state<>'claimed' or r.member_id is not null then raise exception 'access_x_invalid_transition';end if;
 update public.access_x_provisioning_requests set member_id=p_member,state='identity_created',updated_at=now()
 where owner_id=p_owner and request_id=p_request;
 get diagnostics changed=row_count;
 if changed<>1 then raise exception 'access_x_invalid_transition';end if;
 insert into public.access_x_provisioning_events(owner_id,request_id,from_state,to_state,member_id)
 values(p_owner,p_request,'claimed','identity_created',p_member);
 return true;
end $$;
revoke all on function public.access_x_record_identity(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.access_x_record_identity(uuid,uuid,uuid) to service_role;

-- Called AFTER reviewed cashier-only membership insertion (must start disabled!).
-- The only successful account-creation terminal state is PROVISIONED, NOT ACTIVE.
-- Initial online sign-in + enforced password rotation require a separate reviewed activation RPC.
create function public.access_x_mark_provisioned(p_owner uuid,p_request uuid,p_member uuid)
returns boolean language plpgsql security invoker set search_path='' as $$
declare r public.access_x_provisioning_requests%rowtype;
begin
 select * into r from public.access_x_provisioning_requests
 where owner_id=p_owner and request_id=p_request for update;
 if not found then raise exception 'access_x_request_missing';end if;
 if r.member_id is distinct from p_member then raise exception 'access_x_member_mismatch';end if;
 if r.state='provisioned' then return true;end if;
 if r.state<>'identity_created' then raise exception 'access_x_invalid_transition';end if;
 if not exists(select 1 from public.store_cashiers s
  where s.owner_id=p_owner and s.member_id=p_member and s.role='cashier'
    and s.enabled=false and s.accepted_at is null)
 then raise exception 'access_x_cashier_activation_guard';end if;
 update public.access_x_provisioning_requests
 set state='provisioned',updated_at=now() where owner_id=p_owner and request_id=p_request;
 insert into public.access_x_provisioning_events(owner_id,request_id,from_state,to_state,member_id)
 values(p_owner,p_request,'identity_created','provisioned',p_member);
 return true;
end $$;
revoke all on function public.access_x_mark_provisioned(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.access_x_mark_provisioned(uuid,uuid,uuid) to service_role;

-- Once claimed, ANY ambiguous Auth/DB status becomes a human-reviewed ticket.
-- Do not delete Auth users, reset claimed to reserved, or retry createUser automatically.
create function public.access_x_mark_reconciliation(p_owner uuid,p_request uuid,p_member uuid)
returns boolean language plpgsql security invoker set search_path='' as $$
declare r public.access_x_provisioning_requests%rowtype;
begin
 select * into r from public.access_x_provisioning_requests
 where owner_id=p_owner and request_id=p_request for update;
 if not found then raise exception 'access_x_request_missing';end if;
 if r.state='reconciliation' then return true;end if;
 if r.state not in ('claimed','identity_created','provisioned')
   or (r.member_id is not null and p_member is distinct from r.member_id)
 then raise exception 'access_x_invalid_transition';end if;
 update public.access_x_provisioning_requests
 set state='reconciliation',updated_at=now()
 where owner_id=p_owner and request_id=p_request;
 insert into public.access_x_provisioning_events(owner_id,request_id,from_state,to_state,member_id)
 values(p_owner,p_request,r.state,'reconciliation',coalesce(p_member,r.member_id));
 return true;
end $$;
revoke all on function public.access_x_mark_reconciliation(uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.access_x_mark_reconciliation(uuid,uuid,uuid) to service_role;

-- IMPORTANT: no activation RPC or browser-accessible staff-creation RPC exists here.
-- Before release also add append-only write protections on events, full backup/restore tests,
-- unique cashier email governance, audit/account recovery, and exact grants review.
