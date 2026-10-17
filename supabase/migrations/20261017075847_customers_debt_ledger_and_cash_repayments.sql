create table public.customers (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id),
 name text not null check(char_length(btrim(name)) between 1 and 150 and name=btrim(name)),
 phone text check(phone is null or (char_length(phone) between 1 and 35 and phone=btrim(phone))),
 created_at timestamptz not null default now()
);
create index customers_owner_created_idx on public.customers(owner_id,created_at desc,id);
alter table public.customers enable row level security;
revoke all on public.customers from anon,authenticated;
grant select on public.customers to authenticated;
grant insert(id,name,phone) on public.customers to authenticated;
grant update(name,phone) on public.customers to authenticated;
create policy customers_read_own on public.customers for select to authenticated using ((select auth.uid())=owner_id);
create policy customers_insert_own on public.customers for insert to authenticated with check ((select auth.uid())=owner_id);
create policy customers_update_own on public.customers for update to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);

create table public.customer_balances (
 customer_id uuid primary key references public.customers(id),
 owner_id uuid not null references auth.users(id),
 balance bigint not null default 0 check(balance between 0 and 100000000000000),
 updated_at timestamptz not null default now()
);
create index customer_balances_owner_idx on public.customer_balances(owner_id);
alter table public.customer_balances enable row level security;
revoke all on public.customer_balances from anon,authenticated;
grant select on public.customer_balances to authenticated;
create policy customer_balances_read_own on public.customer_balances for select to authenticated using ((select auth.uid())=owner_id);

alter table public.cash_movements add column customer_id uuid references public.customers(id);
create index cash_movements_customer_idx on public.cash_movements(customer_id) where customer_id is not null;
alter table public.cash_movements drop constraint cash_movements_kind_check,drop constraint cash_movements_check,drop constraint cash_movements_check1;
alter table public.cash_movements add constraint cash_movements_kind_check check(kind in ('sale','deposit','withdrawal','expense','repayment'));
alter table public.cash_movements add constraint cash_movements_direction_check check(delta=case when kind in ('sale','deposit','repayment') then amount else -amount end);
alter table public.cash_movements add constraint cash_movements_source_check check(
 (kind='sale' and sale_id is not null and customer_id is null)
 or (kind='repayment' and sale_id is null and customer_id is not null and amount>0 and char_length(btrim(note))>0)
 or (kind in ('deposit','withdrawal','expense') and sale_id is null and customer_id is null and amount>0 and char_length(btrim(note))>0)
);

create table public.debt_entries (
 id uuid primary key,
 movement_no bigint generated always as identity unique,
 owner_id uuid not null references auth.users(id),
 customer_id uuid not null references public.customers(id),
 customer_name text not null,
 created_at timestamptz not null default now(),
 kind text not null check(kind in ('charge','repayment')),
 amount bigint not null check(amount between 1 and 100000000000000),
 delta bigint not null,
 balance_after bigint not null check(balance_after between 0 and 100000000000000),
 note text not null check(char_length(btrim(note)) between 1 and 500),
 cash_movement_id uuid unique references public.cash_movements(id),
 request_payload jsonb not null,
 check(delta=case when kind='charge' then amount else -amount end),
 check((kind='charge' and cash_movement_id is null) or (kind='repayment' and cash_movement_id is not null))
);
create index debt_entries_owner_order_idx on public.debt_entries(owner_id,movement_no desc);
create index debt_entries_customer_order_idx on public.debt_entries(customer_id,movement_no desc);
alter table public.debt_entries enable row level security;
revoke all on public.debt_entries from anon,authenticated;
revoke all on sequence public.debt_entries_movement_no_seq from anon,authenticated;
grant select on public.debt_entries to authenticated;
create policy debt_entries_read_own on public.debt_entries for select to authenticated using ((select auth.uid())=owner_id);

create view public.customer_debt_catalog with(security_invoker=true) as
 select c.id,c.name,c.phone,c.created_at,coalesce(b.balance,0)::bigint balance
 from public.customers c left join public.customer_balances b on b.customer_id=c.id and b.owner_id=c.owner_id
 where c.owner_id=(select auth.uid());
revoke all on public.customer_debt_catalog from anon,authenticated;
grant select on public.customer_debt_catalog to authenticated;

create function private.post_debt_entry(p_id uuid,p_customer uuid,p_kind text,p_amount bigint,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_payload jsonb;v_entry public.debt_entries%rowtype;v_customer public.customers%rowtype;
 v_before bigint;v_after bigint;v_delta bigint;v_cash_before bigint;v_cash_after bigint;v_cash_id uuid;
begin
 if v_user is null then raise exception using errcode='28000',message='debt_auth_required'; end if;
 if p_id is null or p_customer is null or p_kind is null or p_kind not in ('charge','repayment') then raise exception 'debt_invalid_kind'; end if;
 if p_amount is null or p_amount not between 1 and 100000000000000 then raise exception 'debt_invalid_amount'; end if;
 if char_length(btrim(coalesce(p_note,''))) not between 1 and 500 then raise exception 'debt_note_required'; end if;
 v_payload:=jsonb_build_object('customer_id',p_customer,'kind',p_kind,'amount',p_amount,'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended('kashier.debt-entry.'||p_id::text,0));
 select * into v_entry from public.debt_entries where id=p_id;
 if found then
  if v_entry.owner_id<>v_user or v_entry.request_payload<>v_payload then raise exception 'debt_request_conflict'; end if;
  return to_jsonb(v_entry)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||v_user::text,0));
 select * into v_customer from public.customers where id=p_customer and owner_id=v_user for share;
 if not found then raise exception 'debt_customer_unavailable'; end if;
 insert into public.customer_balances(customer_id,owner_id,balance) values(p_customer,v_user,0) on conflict(customer_id) do nothing;
 select balance into v_before from public.customer_balances where customer_id=p_customer and owner_id=v_user for update;
 if not found then raise exception 'debt_customer_unavailable'; end if;
 v_delta:=case when p_kind='charge' then p_amount else -p_amount end;
 v_after:=v_before+v_delta;
 if v_after<0 then raise exception 'debt_overpayment'; end if;
 if v_after>100000000000000 then raise exception 'debt_balance_limit'; end if;
 if p_kind='repayment' then
  perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
  insert into public.cash_accounts(owner_id,balance) values(v_user,0) on conflict(owner_id) do nothing;
  select balance into v_cash_before from public.cash_accounts where owner_id=v_user for update;
  v_cash_after:=v_cash_before+p_amount;
  if v_cash_after>100000000000000 then raise exception 'cash_balance_limit'; end if;
  v_cash_id:=gen_random_uuid();
  insert into public.cash_movements(id,owner_id,kind,amount,delta,balance_after,note,customer_id,request_payload)
   values(v_cash_id,v_user,'repayment',p_amount,p_amount,v_cash_after,btrim(p_note),p_customer,jsonb_build_object('debt_entry_id',p_id));
  update public.cash_accounts set balance=v_cash_after,updated_at=now() where owner_id=v_user;
 end if;
 update public.customer_balances set balance=v_after,updated_at=now() where customer_id=p_customer and owner_id=v_user;
 insert into public.debt_entries(id,owner_id,customer_id,customer_name,kind,amount,delta,balance_after,note,cash_movement_id,request_payload)
  values(p_id,v_user,p_customer,v_customer.name,p_kind,p_amount,v_delta,v_after,btrim(p_note),v_cash_id,v_payload) returning * into v_entry;
 return to_jsonb(v_entry)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_debt_entry(uuid,uuid,text,bigint,text) from public,anon,authenticated;
grant execute on function private.post_debt_entry(uuid,uuid,text,bigint,text) to authenticated;
create function public.post_debt_entry(p_id uuid,p_customer uuid,p_kind text,p_amount bigint,p_note text)
returns jsonb language sql security invoker set search_path='' as $$
 select private.post_debt_entry(p_id,p_customer,p_kind,p_amount,p_note);
$$;
revoke all on function public.post_debt_entry(uuid,uuid,text,bigint,text) from public,anon,authenticated;
grant execute on function public.post_debt_entry(uuid,uuid,text,bigint,text) to authenticated;

create or replace function public.get_cash_summary()
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
 'balance',coalesce((select balance from public.cash_accounts where owner_id=(select auth.uid())),0)::text,
 'sales',coalesce(sum(amount) filter(where kind='sale'),0)::text,
 'deposits',coalesce(sum(amount) filter(where kind='deposit'),0)::text,
 'withdrawals',coalesce(sum(amount) filter(where kind='withdrawal'),0)::text,
 'expenses',coalesce(sum(amount) filter(where kind='expense'),0)::text,
 'repayments',coalesce(sum(amount) filter(where kind='repayment'),0)::text,
 'count',count(*)::text
 ) from public.cash_movements where owner_id=(select auth.uid());
$$;
create function public.get_debt_summary()
returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('balance',coalesce(sum(balance),0)::text,'debtors',count(*) filter(where balance>0)::text)
 from public.customer_balances where owner_id=(select auth.uid());
$$;
revoke all on function public.get_debt_summary() from public,anon,authenticated;
grant execute on function public.get_debt_summary() to authenticated;
notify pgrst,'reload schema';
