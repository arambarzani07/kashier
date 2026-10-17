-- Explicit classification of existing customer repayments. No cash or debt posting and no history backfill.
create table public.customer_payment_allocations (
 id uuid primary key,
 owner_id uuid not null references auth.users(id),
 customer_id uuid not null references public.customers(id),
 payment_entry_id uuid not null references public.debt_entries(id),
 charge_entry_id uuid not null references public.debt_entries(id),
 amount bigint not null check(amount between 1 and 100000000000000),
 note text not null check(char_length(btrim(note)) between 1 and 500),
 created_at timestamptz not null default now(),
 request_payload jsonb not null,
 check(payment_entry_id<>charge_entry_id)
);
create index customer_allocations_owner_customer_idx on public.customer_payment_allocations(owner_id,customer_id,created_at,id);
create index customer_allocations_payment_idx on public.customer_payment_allocations(payment_entry_id);
create index customer_allocations_charge_idx on public.customer_payment_allocations(charge_entry_id);
create index customer_allocations_customer_idx on public.customer_payment_allocations(customer_id);
create table public.customer_allocation_reversals (
 id uuid primary key,
 owner_id uuid not null references auth.users(id),
 customer_id uuid not null references public.customers(id),
 allocation_id uuid not null unique references public.customer_payment_allocations(id),
 reason text not null check(char_length(btrim(reason)) between 1 and 500),
 created_at timestamptz not null default now(),
 request_payload jsonb not null
);
create index customer_allocation_reversals_owner_customer_idx on public.customer_allocation_reversals(owner_id,customer_id,created_at,id);
create index customer_allocation_reversals_customer_idx on public.customer_allocation_reversals(customer_id);
alter table public.customer_payment_allocations enable row level security;
alter table public.customer_allocation_reversals enable row level security;
revoke all on public.customer_payment_allocations,public.customer_allocation_reversals from public,anon,authenticated;
grant select on public.customer_payment_allocations,public.customer_allocation_reversals to authenticated;
create policy customer_allocations_read_own on public.customer_payment_allocations for select to authenticated using ((select auth.uid())=owner_id);
create policy customer_allocation_reversals_read_own on public.customer_allocation_reversals for select to authenticated using ((select auth.uid())=owner_id);

create function private.allocate_customer_payment(p_id uuid,p_customer uuid,p_payment uuid,p_charge uuid,p_amount bigint,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_payload jsonb;v_row public.customer_payment_allocations%rowtype;v_payment public.debt_entries%rowtype;v_charge public.debt_entries%rowtype;v_used numeric;v_reversed numeric;
begin
 if v_user is null then raise exception 'allocation_auth_required';end if;
 if p_id is null or p_customer is null or p_payment is null or p_charge is null or p_payment=p_charge then raise exception 'allocation_invalid_request';end if;
 if p_amount is null or p_amount not between 1 and 100000000000000 then raise exception 'allocation_invalid_amount';end if;
 if char_length(btrim(coalesce(p_note,''))) not between 1 and 500 then raise exception 'allocation_note_required';end if;
 v_payload:=jsonb_build_object('customer',p_customer,'payment',p_payment,'charge',p_charge,'amount',p_amount,'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended('kashier.customer-allocation.'||p_id::text,0));
 select * into v_row from public.customer_payment_allocations where id=p_id;
 if found then
  if v_row.owner_id<>v_user or v_row.request_payload<>v_payload then raise exception 'allocation_request_conflict';end if;
  return jsonb_build_object('id',v_row.id,'customer_id',v_row.customer_id,'amount',v_row.amount::text);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||v_user::text,0));
 select * into v_payment from public.debt_entries where id=p_payment and owner_id=v_user and customer_id=p_customer and kind='repayment';
 select * into v_charge from public.debt_entries where id=p_charge and owner_id=v_user and customer_id=p_customer and kind='charge';
 if v_payment.id is null or v_charge.id is null then raise exception 'allocation_entry_unavailable';end if;
 select coalesce(sum(a.amount),0) into v_used from public.customer_payment_allocations a where a.payment_entry_id=p_payment and not exists(select 1 from public.customer_allocation_reversals r where r.allocation_id=a.id);
 if v_used+p_amount>v_payment.amount then raise exception 'allocation_payment_exceeded';end if;
 select coalesce(sum(a.amount),0) into v_used from public.customer_payment_allocations a where a.charge_entry_id=p_charge and not exists(select 1 from public.customer_allocation_reversals r where r.allocation_id=a.id);
 select coalesce(sum(d.amount),0) into v_reversed from public.debt_entries d join public.sale_reversals r on r.id=d.reversal_id where d.owner_id=v_user and d.customer_id=p_customer and d.kind='reversal' and r.sale_id=v_charge.sale_id;
 if v_used+p_amount>v_charge.amount-v_reversed then raise exception 'allocation_charge_exceeded';end if;
 insert into public.customer_payment_allocations(id,owner_id,customer_id,payment_entry_id,charge_entry_id,amount,note,request_payload)
 values(p_id,v_user,p_customer,p_payment,p_charge,p_amount,btrim(p_note),v_payload);
 return jsonb_build_object('id',p_id,'customer_id',p_customer,'amount',p_amount::text);
end $$;
create function public.allocate_customer_payment(p_id uuid,p_customer uuid,p_payment uuid,p_charge uuid,p_amount bigint,p_note text)
returns jsonb language sql security invoker set search_path='' as $$ select private.allocate_customer_payment(p_id,p_customer,p_payment,p_charge,p_amount,p_note); $$;
revoke all on function private.allocate_customer_payment(uuid,uuid,uuid,uuid,bigint,text),public.allocate_customer_payment(uuid,uuid,uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function private.allocate_customer_payment(uuid,uuid,uuid,uuid,bigint,text),public.allocate_customer_payment(uuid,uuid,uuid,uuid,bigint,text) to authenticated;

create function private.reverse_customer_allocation(p_id uuid,p_customer uuid,p_allocation uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_payload jsonb;v_row public.customer_allocation_reversals%rowtype;
begin
 if v_user is null then raise exception 'allocation_auth_required';end if;
 if p_id is null or p_customer is null or p_allocation is null then raise exception 'allocation_invalid_request';end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'allocation_note_required';end if;
 v_payload:=jsonb_build_object('customer',p_customer,'allocation',p_allocation,'reason',btrim(p_reason));
 perform pg_advisory_xact_lock(hashtextextended('kashier.customer-allocation-reversal.'||p_id::text,0));
 select * into v_row from public.customer_allocation_reversals where id=p_id;
 if found then
  if v_row.owner_id<>v_user or v_row.request_payload<>v_payload then raise exception 'allocation_request_conflict';end if;
  return jsonb_build_object('id',v_row.id,'customer_id',v_row.customer_id);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||v_user::text,0));
 if not exists(select 1 from public.customer_payment_allocations where id=p_allocation and customer_id=p_customer and owner_id=v_user) then raise exception 'allocation_entry_unavailable';end if;
 if exists(select 1 from public.customer_allocation_reversals where allocation_id=p_allocation) then raise exception 'allocation_already_reversed';end if;
 insert into public.customer_allocation_reversals(id,owner_id,customer_id,allocation_id,reason,request_payload) values(p_id,v_user,p_customer,p_allocation,btrim(p_reason),v_payload);
 return jsonb_build_object('id',p_id,'customer_id',p_customer);
end $$;
create function public.reverse_customer_allocation(p_id uuid,p_customer uuid,p_allocation uuid,p_reason text)
returns jsonb language sql security invoker set search_path='' as $$ select private.reverse_customer_allocation(p_id,p_customer,p_allocation,p_reason); $$;
revoke all on function private.reverse_customer_allocation(uuid,uuid,uuid,text),public.reverse_customer_allocation(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.reverse_customer_allocation(uuid,uuid,uuid,text),public.reverse_customer_allocation(uuid,uuid,uuid,text) to authenticated;

-- Existing sale reversal already serializes on the same debt-owner lock. Defend invoice capacity atomically.
create function private.guard_customer_allocated_debt_reversal() returns trigger language plpgsql security definer set search_path='' as $$
declare v_sale uuid;v_charge public.debt_entries%rowtype;v_used numeric;v_previous numeric;
begin
 if new.kind<>'reversal' then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||new.owner_id::text,0));
 select sale_id into v_sale from public.sale_reversals where id=new.reversal_id and owner_id=new.owner_id;
 select * into v_charge from public.debt_entries where sale_id=v_sale and kind='charge' and owner_id=new.owner_id and customer_id=new.customer_id;
 if v_charge.id is null then raise exception 'allocation_invalid_reversal';end if;
 select coalesce(sum(a.amount),0) into v_used from public.customer_payment_allocations a where a.charge_entry_id=v_charge.id and not exists(select 1 from public.customer_allocation_reversals r where r.allocation_id=a.id);
 select coalesce(sum(d.amount),0) into v_previous from public.debt_entries d join public.sale_reversals r on r.id=d.reversal_id where d.owner_id=new.owner_id and d.kind='reversal' and r.sale_id=v_sale;
 if v_used+v_previous+new.amount>v_charge.amount then raise exception 'allocation_reverse_before_sale_return';end if;
 return new;
end $$;
revoke all on function private.guard_customer_allocated_debt_reversal() from public,anon,authenticated;
create trigger customer_allocated_debt_reversal_guard before insert on public.debt_entries for each row execute function private.guard_customer_allocated_debt_reversal();

create function public.get_customer_allocations(p_customer uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_customer public.customers%rowtype;v_entries jsonb;v_allocations jsonb;v_balance numeric;v_ledger numeric;
begin
 if v_user is null then raise exception 'allocation_auth_required';end if;
 select * into v_customer from public.customers where id=p_customer and owner_id=v_user;
 if not found then raise exception 'debt_customer_unavailable';end if;
 if (select count(*) from public.debt_entries where customer_id=p_customer and owner_id=v_user)>5000 or (select count(*) from public.customer_payment_allocations where customer_id=p_customer and owner_id=v_user)>5000 then raise exception 'allocation_too_many_rows';end if;
 select coalesce(balance,0) into v_balance from public.customer_balances where customer_id=p_customer and owner_id=v_user;
 v_balance:=coalesce(v_balance,0);
 select coalesce(sum(delta),0) into v_ledger from public.debt_entries where customer_id=p_customer and owner_id=v_user;
 if v_balance<>v_ledger then raise exception 'allocation_ledger_mismatch';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'movement_no',d.movement_no::text,'kind',d.kind,'amount',d.amount::text,'sale_id',d.sale_id,'note',d.note,'created_at',d.created_at,'allocated',a.used::text,'reversed',r.amount::text,'available',(d.amount-a.used-r.amount)::text) order by d.movement_no),'[]'::jsonb) into v_entries
 from public.debt_entries d
 cross join lateral(select coalesce(sum(x.amount),0) used from public.customer_payment_allocations x where (x.charge_entry_id=d.id or x.payment_entry_id=d.id) and x.owner_id=v_user and not exists(select 1 from public.customer_allocation_reversals z where z.allocation_id=x.id)) a
 cross join lateral(select coalesce(sum(x.amount),0) amount from public.debt_entries x join public.sale_reversals sr on sr.id=x.reversal_id where x.owner_id=v_user and x.customer_id=p_customer and x.kind='reversal' and sr.sale_id=d.sale_id) r
 where d.customer_id=p_customer and d.owner_id=v_user and d.kind in ('charge','repayment');
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'payment_entry_id',a.payment_entry_id,'charge_entry_id',a.charge_entry_id,'amount',a.amount::text,'note',a.note,'created_at',a.created_at,'reversal_id',r.id,'reversal_reason',r.reason,'reversed_at',r.created_at) order by a.created_at,a.id),'[]'::jsonb) into v_allocations
 from public.customer_payment_allocations a left join public.customer_allocation_reversals r on r.allocation_id=a.id and r.owner_id=v_user where a.customer_id=p_customer and a.owner_id=v_user;
 return jsonb_build_object('customer',jsonb_build_object('id',v_customer.id,'name',v_customer.name),'owner_id',v_user,'currency','IQD','timezone','Asia/Baghdad','generated_at',statement_timestamp(),'balance',v_balance::text,'entries',v_entries,'allocations',v_allocations);
end $$;
revoke all on function public.get_customer_allocations(uuid) from public,anon,authenticated;
grant execute on function public.get_customer_allocations(uuid) to authenticated;

create or replace function public.export_owner_data() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_table text;v_key text;v_count bigint;v_size bigint;v_total bigint:=0;v_bytes bigint:=0;v_rows jsonb;v_counts jsonb:='{}'::jsonb;v_tables jsonb:='{}'::jsonb;
 v_names text[]:=array['products','product_stock','stock_movements','stock_adjustments','sales','sale_reversals','sale_returns','purchases','cash_accounts','cash_movements','customers','customer_balances','debt_entries','suppliers','supplier_balances','supplier_entries','purchase_reversals','purchase_returns','supplier_payment_allocations','customer_payment_allocations','customer_allocation_reversals'];
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
  v_key:=case v_table when 'product_stock' then 'product_id' when 'cash_accounts' then 'owner_id' when 'customer_balances' then 'customer_id' when 'supplier_balances' then 'supplier_id' else 'id' end;
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by t.%I),''[]''::jsonb) from public.%I t where t.owner_id=$1',v_key,v_table) into v_rows using v_user;
  v_tables:=v_tables||jsonb_build_object(v_table,v_rows);
 end loop;
 return jsonb_build_object('format','kashier-owner-export','version',3,'schema_revision','customer-allocations-v1','owner_id',v_user,'generated_at',statement_timestamp(),'timezone','Asia/Baghdad','currency','IQD','record_count',v_total,'counts',v_counts,'tables',v_tables,
 'scope','business-data-only','excludes',jsonb_build_array('authentication accounts and sessions','passwords and API keys','database schema and RLS policies','automatic restore'));
end $$;
revoke all on function public.export_owner_data() from public,anon,authenticated;
grant execute on function public.export_owner_data() to authenticated;
notify pgrst,'reload schema';
