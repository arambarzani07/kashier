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
 if not found then return true; end if;
 if a.must_change or (p_owner_only and a.owner_id is not null) then return false; end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid; exception when others then return false; end;
 if not exists(select 1 from auth.sessions where id=sid and user_id=a.user_id
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
