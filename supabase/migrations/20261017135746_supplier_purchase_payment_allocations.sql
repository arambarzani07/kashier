create table public.supplier_payment_allocations (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id),
 supplier_id uuid not null references public.suppliers(id),
 payment_entry_id uuid not null references public.supplier_entries(id),
 charge_entry_id uuid not null references public.supplier_entries(id),
 purchase_id uuid not null references public.purchases(id),
 amount bigint not null check(amount between 1 and 100000000000000),
 created_at timestamptz not null default now(),
 check(payment_entry_id<>charge_entry_id)
);
alter table public.supplier_payment_allocations enable row level security;
create policy supplier_payment_allocations_select_own on public.supplier_payment_allocations for select to authenticated using(owner_id=(select auth.uid()));
revoke all on table public.supplier_payment_allocations from public,anon,authenticated;
grant select on table public.supplier_payment_allocations to authenticated;
create unique index supplier_payment_allocations_payment_charge_uidx on public.supplier_payment_allocations(payment_entry_id,charge_entry_id);
create index supplier_payment_allocations_purchase_idx on public.supplier_payment_allocations(owner_id,purchase_id,created_at);
create index supplier_payment_allocations_charge_idx on public.supplier_payment_allocations(charge_entry_id);

alter table public.supplier_entries drop constraint supplier_entries_purchase_id_key;
alter table public.supplier_entries drop constraint supplier_entries_kind_check;
alter table public.supplier_entries drop constraint supplier_entries_check1;
alter table public.supplier_entries add constraint supplier_entries_kind_check check(kind in ('charge','payment','reversal'));
alter table public.supplier_entries add constraint supplier_entries_source_check check(
 (kind='charge' and cash_movement_id is null)
 or (kind='payment' and cash_movement_id is not null)
 or (kind='reversal' and cash_movement_id is null and purchase_id is not null)
);
create unique index supplier_entries_purchase_charge_uidx on public.supplier_entries(purchase_id) where kind='charge' and purchase_id is not null;
create index supplier_entries_purchase_activity_idx on public.supplier_entries(owner_id,purchase_id,kind,created_at) where purchase_id is not null;

create or replace function private.post_supplier_entry(p_id uuid,p_supplier uuid,p_kind text,p_amount bigint,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_supplier public.suppliers%rowtype;v_entry public.supplier_entries%rowtype;v_payload jsonb;v_after bigint;v_cash bigint;v_cash_id uuid;v_manual bigint;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
 if p_id is null or p_supplier is null or p_kind is null or p_kind not in ('charge','payment') then raise exception 'supplier_invalid_kind';end if;
 if p_amount is null or p_amount not between 1 and 100000000000000 then raise exception 'supplier_invalid_amount';end if;
 if char_length(btrim(coalesce(p_note,''))) not between 1 and 500 then raise exception 'supplier_note_required';end if;
 v_payload:=jsonb_build_object('supplier',p_supplier,'kind',p_kind,'amount',p_amount,'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended('kashier.supplier-entry.'||p_id::text,0));
 select * into v_entry from public.supplier_entries where id=p_id;
 if found then
  if v_entry.owner_id<>v_user or v_entry.request_payload<>v_payload or v_entry.purchase_id is not null then raise exception 'supplier_request_conflict';end if;
  return to_jsonb(v_entry)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.supplier.'||v_user::text,0));
 select * into v_supplier from public.suppliers where id=p_supplier and owner_id=v_user for share;
 if not found then raise exception 'supplier_unavailable';end if;
 insert into public.supplier_balances(supplier_id,owner_id,balance) values(p_supplier,v_user,0) on conflict(supplier_id) do nothing;
 select balance+case when p_kind='charge' then p_amount else -p_amount end into v_after from public.supplier_balances where supplier_id=p_supplier and owner_id=v_user for update;
 if p_kind='payment' then
  select coalesce(sum(case when kind='charge' then amount when kind='payment' then -amount else 0 end),0)::bigint into v_manual
  from public.supplier_entries where owner_id=v_user and supplier_id=p_supplier and purchase_id is null;
  if p_amount>v_manual then raise exception 'supplier_manual_overpayment';end if;
 end if;
 if v_after<0 then raise exception 'supplier_overpayment';end if;
 if v_after>100000000000000 then raise exception 'supplier_balance_limit';end if;
 if p_kind='payment' then
  perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
  select balance into v_cash from public.cash_accounts where owner_id=v_user for update;
  if not found or v_cash<p_amount then raise exception 'cash_insufficient_balance';end if;
  v_cash:=v_cash-p_amount;update public.cash_accounts set balance=v_cash,updated_at=now() where owner_id=v_user;
  insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,supplier_id,note,request_payload)
   values(v_user,'supplier_payment',p_amount,-p_amount,v_cash,p_supplier,btrim(p_note),jsonb_build_object('supplier_entry',p_id,'scope','manual')) returning id into v_cash_id;
 end if;
 update public.supplier_balances set balance=v_after,updated_at=now() where supplier_id=p_supplier and owner_id=v_user;
 insert into public.supplier_entries(id,owner_id,supplier_id,supplier_name,kind,amount,delta,balance_after,note,cash_movement_id,request_payload)
 values(p_id,v_user,p_supplier,v_supplier.name,p_kind,p_amount,case when p_kind='charge' then p_amount else -p_amount end,v_after,btrim(p_note),v_cash_id,v_payload) returning * into v_entry;
 return to_jsonb(v_entry)-'owner_id'-'request_payload';
end $$;

create or replace function public.get_supplier_purchase_finance(p_purchase uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_purchase public.purchases%rowtype;v_charge public.supplier_entries%rowtype;v_allocated bigint:=0;v_reversed bigint:=0;v_outstanding bigint:=0;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
 if p_purchase is null then raise exception 'supplier_purchase_unavailable';end if;
 select * into v_purchase from public.purchases where id=p_purchase and owner_id=v_user;
 if not found then raise exception 'supplier_purchase_unavailable';end if;
 if v_purchase.accounting_mode='tracked' and v_purchase.debt_amount>0 then
  select * into v_charge from public.supplier_entries where owner_id=v_user and purchase_id=p_purchase and kind='charge';
  if not found or v_charge.amount<>v_purchase.debt_amount then raise exception 'supplier_purchase_ledger_mismatch';end if;
  select coalesce(sum(amount),0)::bigint into v_allocated from public.supplier_payment_allocations where owner_id=v_user and purchase_id=p_purchase;
  select coalesce(sum(amount),0)::bigint into v_reversed from public.supplier_entries where owner_id=v_user and purchase_id=p_purchase and kind='reversal';
  v_outstanding:=v_charge.amount-v_allocated-v_reversed;
  if v_outstanding<0 then raise exception 'supplier_purchase_ledger_mismatch';end if;
 end if;
 return jsonb_build_object(
  'purchase_id',v_purchase.id,'receipt_no',v_purchase.receipt_no::text,'invoice_no',v_purchase.invoice_no,
  'supplier_id',v_purchase.supplier_id,'supplier_name',v_purchase.supplier_name,'accounting_mode',v_purchase.accounting_mode,
  'total',v_purchase.total::text,'initial_paid',v_purchase.amount_paid::text,'original_debt',v_purchase.debt_amount::text,
  'allocated_payments',v_allocated::text,'debt_reversed',v_reversed::text,'outstanding',v_outstanding::text,'currency',v_purchase.currency
 );
end $$;
revoke all on function public.get_supplier_purchase_finance(uuid) from public,anon,authenticated;
grant execute on function public.get_supplier_purchase_finance(uuid) to authenticated;

create or replace function private.post_supplier_purchase_payment(p_id uuid,p_purchase uuid,p_amount bigint,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_purchase public.purchases%rowtype;v_supplier public.suppliers%rowtype;v_charge public.supplier_entries%rowtype;v_entry public.supplier_entries%rowtype;
 v_payload jsonb;v_allocated bigint;v_reversed bigint;v_outstanding bigint;v_after bigint;v_cash bigint;v_cash_id uuid;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
 if p_id is null or p_purchase is null then raise exception 'supplier_purchase_unavailable';end if;
 if p_amount is null or p_amount not between 1 and 100000000000000 then raise exception 'supplier_invalid_amount';end if;
 if char_length(btrim(coalesce(p_note,''))) not between 1 and 500 then raise exception 'supplier_note_required';end if;
 v_payload:=jsonb_build_object('purchase',p_purchase,'amount',p_amount,'note',btrim(p_note),'scope','purchase');
 perform pg_advisory_xact_lock(hashtextextended('kashier.supplier-entry.'||p_id::text,0));
 select * into v_entry from public.supplier_entries where id=p_id;
 if found then
  if v_entry.owner_id<>v_user or v_entry.kind<>'payment' or v_entry.purchase_id is distinct from p_purchase or v_entry.request_payload<>v_payload then raise exception 'supplier_request_conflict';end if;
  return jsonb_build_object('entry',to_jsonb(v_entry)-'owner_id'-'request_payload','finance',public.get_supplier_purchase_finance(p_purchase));
 end if;
 select * into v_purchase from public.purchases where id=p_purchase and owner_id=v_user;
 if not found or v_purchase.accounting_mode<>'tracked' or v_purchase.supplier_id is null or v_purchase.debt_amount<=0 then raise exception 'supplier_purchase_no_payable';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.supplier.'||v_user::text,0));
 perform pg_advisory_xact_lock(hashtextextended('kashier.purchase-finance.'||p_purchase::text,0));
 select * into v_purchase from public.purchases where id=p_purchase and owner_id=v_user for share;
 select * into v_supplier from public.suppliers where id=v_purchase.supplier_id and owner_id=v_user for share;
 if not found then raise exception 'supplier_unavailable';end if;
 select * into v_charge from public.supplier_entries where owner_id=v_user and purchase_id=p_purchase and kind='charge' for share;
 if not found or v_charge.amount<>v_purchase.debt_amount then raise exception 'supplier_purchase_ledger_mismatch';end if;
 select coalesce(sum(amount),0)::bigint into v_allocated from public.supplier_payment_allocations where owner_id=v_user and purchase_id=p_purchase;
 select coalesce(sum(amount),0)::bigint into v_reversed from public.supplier_entries where owner_id=v_user and purchase_id=p_purchase and kind='reversal';
 v_outstanding:=v_charge.amount-v_allocated-v_reversed;
 if v_outstanding<=0 then raise exception 'supplier_purchase_already_paid';end if;
 if p_amount>v_outstanding then raise exception 'supplier_purchase_overpayment';end if;
 insert into public.supplier_balances(supplier_id,owner_id,balance) values(v_purchase.supplier_id,v_user,0) on conflict(supplier_id) do nothing;
 select balance-p_amount into v_after from public.supplier_balances where supplier_id=v_purchase.supplier_id and owner_id=v_user for update;
 if v_after<0 then raise exception 'supplier_purchase_ledger_mismatch';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
 select balance into v_cash from public.cash_accounts where owner_id=v_user for update;
 if not found or v_cash<p_amount then raise exception 'cash_insufficient_balance';end if;
 v_cash:=v_cash-p_amount;update public.cash_accounts set balance=v_cash,updated_at=now() where owner_id=v_user;
 insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,supplier_id,note,request_payload)
 values(v_user,'supplier_payment',p_amount,-p_amount,v_cash,v_purchase.supplier_id,btrim(p_note),jsonb_build_object('supplier_entry',p_id,'purchase_id',p_purchase,'scope','purchase')) returning id into v_cash_id;
 update public.supplier_balances set balance=v_after,updated_at=now() where supplier_id=v_purchase.supplier_id and owner_id=v_user;
 insert into public.supplier_entries(id,owner_id,supplier_id,supplier_name,kind,amount,delta,balance_after,note,purchase_id,cash_movement_id,request_payload)
 values(p_id,v_user,v_purchase.supplier_id,v_supplier.name,'payment',p_amount,-p_amount,v_after,btrim(p_note),p_purchase,v_cash_id,v_payload) returning * into v_entry;
 insert into public.supplier_payment_allocations(owner_id,supplier_id,payment_entry_id,charge_entry_id,purchase_id,amount)
 values(v_user,v_purchase.supplier_id,v_entry.id,v_charge.id,p_purchase,p_amount);
 return jsonb_build_object('entry',to_jsonb(v_entry)-'owner_id'-'request_payload','finance',public.get_supplier_purchase_finance(p_purchase));
end $$;

create or replace function public.post_supplier_purchase_payment(p_id uuid,p_purchase uuid,p_amount bigint,p_note text)
returns jsonb language sql security invoker set search_path='' as $$ select private.post_supplier_purchase_payment(p_id,p_purchase,p_amount,p_note); $$;
revoke all on function public.post_supplier_purchase_payment(uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public.post_supplier_purchase_payment(uuid,uuid,bigint,text) to authenticated;

create or replace function public.get_supplier_purchase_payables(p_supplier uuid,p_offset integer default 0,p_limit integer default 50)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='supplier_auth_required';end if;
 if p_supplier is null or p_offset<0 or p_limit not between 1 and 100 then raise exception 'supplier_activity_invalid_request';end if;
 if not exists(select 1 from public.suppliers where id=p_supplier and owner_id=v_user) then raise exception 'supplier_unavailable';end if;
 with rows as materialized(
  select p.id,p.receipt_no,p.invoice_no,p.created_at,p.total,p.amount_paid,p.debt_amount,e.id charge_entry_id,
   coalesce((select sum(a.amount) from public.supplier_payment_allocations a where a.owner_id=v_user and a.purchase_id=p.id),0)::bigint allocated_payments,
   coalesce((select sum(r.amount) from public.supplier_entries r where r.owner_id=v_user and r.purchase_id=p.id and r.kind='reversal'),0)::bigint debt_reversed
  from public.purchases p join public.supplier_entries e on e.owner_id=v_user and e.purchase_id=p.id and e.kind='charge'
  where p.owner_id=v_user and p.supplier_id=p_supplier and p.accounting_mode='tracked' and p.debt_amount>0
 ), open_rows as materialized(
  select *,debt_amount-allocated_payments-debt_reversed as outstanding from rows where debt_amount-allocated_payments-debt_reversed>0
 ), page as(
  select * from open_rows order by created_at,receipt_no offset p_offset limit p_limit
 )
 select jsonb_build_object('count',(select count(*)::text from open_rows),'rows',coalesce((select jsonb_agg(jsonb_build_object(
  'purchase_id',id,'receipt_no',receipt_no::text,'invoice_no',invoice_no,'created_at',created_at,'total',total::text,
  'initial_paid',amount_paid::text,'original_debt',debt_amount::text,'allocated_payments',allocated_payments::text,
  'debt_reversed',debt_reversed::text,'outstanding',outstanding::text,'charge_entry_id',charge_entry_id
 ) order by created_at,receipt_no) from page),'[]'::jsonb)) into v_result;
 return v_result;
end $$;
revoke all on function public.get_supplier_purchase_payables(uuid,integer,integer) from public,anon,authenticated;
grant execute on function public.get_supplier_purchase_payables(uuid,integer,integer) to authenticated;
notify pgrst,'reload schema';