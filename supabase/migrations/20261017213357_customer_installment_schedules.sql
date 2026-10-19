-- Scheduling metadata only: no debt, cash or inventory entries are created.
create table public.customer_installment_plans(
 id uuid primary key, owner_id uuid not null references auth.users(id),
 customer_id uuid not null references public.customers(id), charge_entry_id uuid not null references public.debt_entries(id),
 amount bigint not null check(amount between 1 and 100000000000000),
 schedule jsonb not null check(jsonb_typeof(schedule)='array' and jsonb_array_length(schedule) between 1 and 60),
 note text not null check(char_length(btrim(note)) between 1 and 500),
 created_at timestamptz not null default now(), request_payload jsonb not null
);
create index installment_plans_owner_customer_idx on public.customer_installment_plans(owner_id,customer_id,created_at,id);
create index installment_plans_customer_idx on public.customer_installment_plans(customer_id);
create index installment_plans_charge_idx on public.customer_installment_plans(charge_entry_id);
create table public.customer_installment_cancellations(
 id uuid primary key,owner_id uuid not null references auth.users(id),customer_id uuid not null references public.customers(id),
 plan_id uuid not null unique references public.customer_installment_plans(id),
 reason text not null check(char_length(btrim(reason)) between 1 and 500),created_at timestamptz not null default now(),request_payload jsonb not null
);
create index installment_cancellations_owner_customer_idx on public.customer_installment_cancellations(owner_id,customer_id);
create index installment_cancellations_customer_idx on public.customer_installment_cancellations(customer_id);
alter table public.customer_installment_plans enable row level security;
alter table public.customer_installment_cancellations enable row level security;
revoke all on public.customer_installment_plans,public.customer_installment_cancellations from public,anon,authenticated;
grant select on public.customer_installment_plans,public.customer_installment_cancellations to authenticated;
create policy installment_plans_read_own on public.customer_installment_plans for select to authenticated using((select auth.uid())=owner_id);
create policy installment_cancellations_read_own on public.customer_installment_cancellations for select to authenticated using((select auth.uid())=owner_id);

create function private.installment_schedule_total(p_schedule jsonb) returns bigint
language plpgsql immutable security invoker set search_path='' as $$
declare x jsonb;v_date date;v_last date;v_sum numeric:=0;begin
 if p_schedule is null or jsonb_typeof(p_schedule)<>'array' then raise exception 'installment_invalid_schedule';end if;
 if jsonb_array_length(p_schedule) not between 1 and 60 then raise exception 'installment_invalid_schedule';end if;
 for x in select value from jsonb_array_elements(p_schedule) loop
  if jsonb_typeof(x)<>'object' or (select count(*) from jsonb_object_keys(x))<>2 or jsonb_typeof(x->'due_date')<>'string' or jsonb_typeof(x->'amount')<>'string' or not(x ? 'due_date' and x ? 'amount') then raise exception 'installment_invalid_schedule';end if;
  if (x->>'due_date')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or (x->>'amount')!~'^[1-9][0-9]{0,14}$' then raise exception 'installment_invalid_schedule';end if;
  begin v_date:=(x->>'due_date')::date;exception when datetime_field_overflow or invalid_datetime_format then raise exception 'installment_invalid_schedule';end;
  if v_date not between date '2000-01-01' and date '2100-12-31' or v_last is not null and v_date<=v_last then raise exception 'installment_invalid_schedule';end if;
  v_sum:=v_sum+(x->>'amount')::numeric;if v_sum>100000000000000 then raise exception 'installment_invalid_schedule';end if;v_last:=v_date;
 end loop;
 return v_sum::bigint;
end $$;
revoke all on function private.installment_schedule_total(jsonb) from public,anon,authenticated;

create function private.create_customer_installments(p_id uuid,p_customer uuid,p_charge uuid,p_schedule jsonb,p_note text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_payload jsonb;v_row public.customer_installment_plans%rowtype;v_charge public.debt_entries%rowtype;v_reversed numeric;v_total bigint;begin
 if v_user is null then raise exception 'installment_auth_required';end if;
 if p_id is null or p_customer is null or p_charge is null then raise exception 'installment_invalid_request';end if;
 if char_length(btrim(coalesce(p_note,''))) not between 1 and 500 then raise exception 'installment_note_required';end if;
 v_total:=private.installment_schedule_total(p_schedule);
 v_payload:=jsonb_build_object('customer',p_customer,'charge',p_charge,'schedule',p_schedule,'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended('kashier.installment.'||p_id::text,0));
 select * into v_row from public.customer_installment_plans where id=p_id;
 if found then
  if v_row.owner_id<>v_user or v_row.request_payload<>v_payload then raise exception 'installment_request_conflict';end if;
  return jsonb_build_object('id',v_row.id,'customer_id',v_row.customer_id,'amount',v_row.amount::text);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||v_user::text,0));
 select * into v_charge from public.debt_entries where id=p_charge and owner_id=v_user and customer_id=p_customer and kind='charge';
 if not found then raise exception 'installment_charge_unavailable';end if;
 select coalesce(sum(d.amount),0) into v_reversed from public.debt_entries d join public.sale_reversals r on r.id=d.reversal_id where d.owner_id=v_user and d.kind='reversal' and r.sale_id=v_charge.sale_id;
 if v_total<>v_charge.amount-v_reversed then raise exception 'installment_amount_mismatch';end if;
 if exists(select 1 from public.customer_installment_plans p where p.owner_id=v_user and p.charge_entry_id=p_charge and not exists(select 1 from public.customer_installment_cancellations c where c.plan_id=p.id)) then raise exception 'installment_plan_exists';end if;
 if (select count(*) from public.customer_installment_plans where owner_id=v_user)>=500 then raise exception 'installment_too_many_plans';end if;
 insert into public.customer_installment_plans(id,owner_id,customer_id,charge_entry_id,amount,schedule,note,request_payload) values(p_id,v_user,p_customer,p_charge,v_total,p_schedule,btrim(p_note),v_payload);
 return jsonb_build_object('id',p_id,'customer_id',p_customer,'amount',v_total::text);
end $$;
create function public.create_customer_installments(p_id uuid,p_customer uuid,p_charge uuid,p_schedule jsonb,p_note text) returns jsonb
language sql security invoker set search_path='' as $$select private.create_customer_installments(p_id,p_customer,p_charge,p_schedule,p_note);$$;
revoke all on function private.create_customer_installments(uuid,uuid,uuid,jsonb,text),public.create_customer_installments(uuid,uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function private.create_customer_installments(uuid,uuid,uuid,jsonb,text),public.create_customer_installments(uuid,uuid,uuid,jsonb,text) to authenticated;

create function private.cancel_customer_installments(p_id uuid,p_customer uuid,p_plan uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_payload jsonb;v_row public.customer_installment_cancellations%rowtype;begin
 if v_user is null then raise exception 'installment_auth_required';end if;
 if p_id is null or p_customer is null or p_plan is null then raise exception 'installment_invalid_request';end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'installment_note_required';end if;
 v_payload:=jsonb_build_object('customer',p_customer,'plan',p_plan,'reason',btrim(p_reason));
 perform pg_advisory_xact_lock(hashtextextended('kashier.installment-cancel.'||p_id::text,0));
 select * into v_row from public.customer_installment_cancellations where id=p_id;
 if found then
  if v_row.owner_id<>v_user or v_row.request_payload<>v_payload then raise exception 'installment_request_conflict';end if;
  return jsonb_build_object('id',v_row.id,'customer_id',v_row.customer_id);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||v_user::text,0));
 if not exists(select 1 from public.customer_installment_plans where id=p_plan and customer_id=p_customer and owner_id=v_user) then raise exception 'installment_plan_unavailable';end if;
 if exists(select 1 from public.customer_installment_cancellations where plan_id=p_plan) then raise exception 'installment_already_cancelled';end if;
 insert into public.customer_installment_cancellations(id,owner_id,customer_id,plan_id,reason,request_payload) values(p_id,v_user,p_customer,p_plan,btrim(p_reason),v_payload);
 return jsonb_build_object('id',p_id,'customer_id',p_customer);
end $$;
create function public.cancel_customer_installments(p_id uuid,p_customer uuid,p_plan uuid,p_reason text) returns jsonb
language sql security invoker set search_path='' as $$select private.cancel_customer_installments(p_id,p_customer,p_plan,p_reason);$$;
revoke all on function private.cancel_customer_installments(uuid,uuid,uuid,text),public.cancel_customer_installments(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.cancel_customer_installments(uuid,uuid,uuid,text),public.cancel_customer_installments(uuid,uuid,uuid,text) to authenticated;

-- Returning a scheduled invoice requires explicitly cancelling its schedule first.
create function private.guard_installment_sale_return() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.kind='reversal' then
  perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||new.owner_id::text,0));
  if exists(select 1 from public.customer_installment_plans p join public.debt_entries d on d.id=p.charge_entry_id join public.sale_reversals r on r.sale_id=d.sale_id where p.owner_id=new.owner_id and r.id=new.reversal_id and not exists(select 1 from public.customer_installment_cancellations c where c.plan_id=p.id)) then raise exception 'installment_cancel_before_return';end if;
 end if;return new;
end $$;
revoke all on function private.guard_installment_sale_return() from public,anon,authenticated;
create trigger installment_sale_return_guard before insert on public.debt_entries for each row execute function private.guard_installment_sale_return();

create function public.get_customer_installments(p_customer uuid default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_ledger jsonb;v_plans jsonb;begin
 if v_user is null then raise exception 'installment_auth_required';end if;
 if p_customer is not null then v_ledger:=public.get_customer_allocations(p_customer);end if;
 if (select count(*) from public.customer_installment_plans where owner_id=v_user and(p_customer is null or customer_id=p_customer))>500 then raise exception 'installment_too_many_plans';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'customer_id',p.customer_id,'customer_name',c.name,'charge_entry_id',p.charge_entry_id,'charge_no',d.movement_no::text,'amount',p.amount::text,'schedule',p.schedule,'note',p.note,'created_at',p.created_at,'allocated',a.amount::text,'unassigned',u.amount::text,'cancellation_id',z.id,'cancelled_at',z.created_at,'cancel_reason',z.reason) order by p.created_at,p.id),'[]'::jsonb) into v_plans
 from public.customer_installment_plans p join public.customers c on c.id=p.customer_id and c.owner_id=v_user join public.debt_entries d on d.id=p.charge_entry_id and d.owner_id=v_user
 left join public.customer_installment_cancellations z on z.plan_id=p.id and z.owner_id=v_user
 cross join lateral(select coalesce(sum(x.amount),0) amount from public.customer_payment_allocations x where x.charge_entry_id=p.charge_entry_id and x.owner_id=v_user and not exists(select 1 from public.customer_allocation_reversals r where r.allocation_id=x.id)) a
 cross join lateral(select coalesce((select sum(e.amount) from public.debt_entries e where e.owner_id=v_user and e.customer_id=p.customer_id and e.kind='repayment'),0)-coalesce((select sum(x.amount) from public.customer_payment_allocations x where x.owner_id=v_user and x.customer_id=p.customer_id and not exists(select 1 from public.customer_allocation_reversals r where r.allocation_id=x.id)),0) amount) u
 where p.owner_id=v_user and(p_customer is null or p.customer_id=p_customer);
 return jsonb_build_object('owner_id',v_user,'customer_id',p_customer,'currency','IQD','timezone','Asia/Baghdad','today',(statement_timestamp() at time zone 'Asia/Baghdad')::date::text,'generated_at',statement_timestamp(),'ledger',v_ledger,'plans',v_plans);
end $$;
revoke all on function public.get_customer_installments(uuid) from public,anon,authenticated;
grant execute on function public.get_customer_installments(uuid) to authenticated;

create or replace function public.export_owner_data() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_table text;v_key text;v_count bigint;v_size bigint;v_total bigint:=0;v_bytes bigint:=0;v_rows jsonb;v_counts jsonb:='{}'::jsonb;v_tables jsonb:='{}'::jsonb;
 v_names text[]:=array['products','product_stock','stock_movements','stock_adjustments','sales','sale_reversals','sale_returns','purchases','cash_accounts','cash_movements','customers','customer_balances','debt_entries','suppliers','supplier_balances','supplier_entries','purchase_reversals','purchase_returns','supplier_payment_allocations','customer_payment_allocations','customer_allocation_reversals','customer_installment_plans','customer_installment_cancellations'];
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
 return jsonb_build_object('format','kashier-owner-export','version',4,'schema_revision','customer-installments-v1','owner_id',v_user,'generated_at',statement_timestamp(),'timezone','Asia/Baghdad','currency','IQD','record_count',v_total,'counts',v_counts,'tables',v_tables,
 'scope','business-data-only','excludes',jsonb_build_array('authentication accounts and sessions','passwords and API keys','database schema and RLS policies','automatic restore'));
end $$;
revoke all on function public.export_owner_data() from public,anon,authenticated;
grant execute on function public.export_owner_data() to authenticated;
notify pgrst,'reload schema';
