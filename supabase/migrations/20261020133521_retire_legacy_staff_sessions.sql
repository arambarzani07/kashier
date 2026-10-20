create or replace function private.access_allowed(p_owner_only boolean default false) returns boolean
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
