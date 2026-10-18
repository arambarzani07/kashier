-- Owner-confirmed value for a currently unknown positive stock pool, never a historical COGS backfill.
create table public.inventory_cost_bases(
 id uuid primary key,owner_id uuid not null references auth.users(id),product_id uuid not null references public.products(id),
 quantity_units bigint not null check(quantity_units between 1 and 1000000000000),stock_version bigint not null check(stock_version>=0),
 total_value bigint not null check(total_value between 0 and 100000000000000),note text not null check(char_length(btrim(note)) between 1 and 500),
 created_at timestamptz not null default now(),request_payload jsonb not null
);
create index inventory_cost_bases_owner_product_idx on public.inventory_cost_bases(owner_id,product_id,created_at,id);
create index inventory_cost_bases_product_idx on public.inventory_cost_bases(product_id);
create table public.inventory_cost_basis_cancellations(
 id uuid primary key,owner_id uuid not null references auth.users(id),product_id uuid not null references public.products(id),
 basis_id uuid not null unique references public.inventory_cost_bases(id),reason text not null check(char_length(btrim(reason)) between 1 and 500),
 created_at timestamptz not null default now(),request_payload jsonb not null
);
create index inventory_cost_basis_cancellations_owner_product_idx on public.inventory_cost_basis_cancellations(owner_id,product_id);
create index inventory_cost_basis_cancellations_product_idx on public.inventory_cost_basis_cancellations(product_id);
alter table public.inventory_cost_bases enable row level security;
alter table public.inventory_cost_basis_cancellations enable row level security;
revoke all on public.inventory_cost_bases,public.inventory_cost_basis_cancellations from public,anon,authenticated;
grant select on public.inventory_cost_bases,public.inventory_cost_basis_cancellations to authenticated;
create policy inventory_cost_bases_read_own on public.inventory_cost_bases for select to authenticated using((select auth.uid())=owner_id);
create policy inventory_cost_basis_cancellations_read_own on public.inventory_cost_basis_cancellations for select to authenticated using((select auth.uid())=owner_id);

create function private.confirm_inventory_cost_basis(p_id uuid,p_product uuid,p_expected_units bigint,p_expected_version bigint,p_total bigint,p_note text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_payload jsonb;v_row public.inventory_cost_bases%rowtype;v_units bigint;v_version bigint;v_state public.inventory_cost_state%rowtype;begin
 if v_user is null then raise exception 'basis_auth_required';end if;
 if p_id is null or p_product is null or p_expected_units is null or p_expected_units not between 1 and 1000000000000 or p_expected_version is null or p_expected_version<0 or p_total is null or p_total not between 0 and 100000000000000 then raise exception 'basis_invalid_request';end if;
 if char_length(btrim(coalesce(p_note,''))) not between 1 and 500 then raise exception 'basis_note_required';end if;
 v_payload:=jsonb_build_object('product',p_product,'units',p_expected_units,'version',p_expected_version,'total',p_total,'note',btrim(p_note));
 perform pg_advisory_xact_lock(hashtextextended('kashier.cost-basis.'||p_id::text,0));
 select * into v_row from public.inventory_cost_bases where id=p_id;
 if found then
  if v_row.owner_id<>v_user or v_row.request_payload<>v_payload then raise exception 'basis_request_conflict';end if;
  return jsonb_build_object('id',v_row.id,'product_id',v_row.product_id,'total_value',v_row.total_value::text);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 if not exists(select 1 from public.products where id=p_product and owner_id=v_user) then raise exception 'basis_product_unavailable';end if;
 select coalesce(quantity_units,0) into v_units from public.product_stock where product_id=p_product and owner_id=v_user for update;
 v_units:=coalesce(v_units,0);
 select coalesce(max(movement_no),0) into v_version from public.stock_movements where product_id=p_product and owner_id=v_user;
 if v_units<>p_expected_units or v_version<>p_expected_version then raise exception 'basis_stock_changed';end if;
 select * into v_state from public.inventory_cost_state where product_id=p_product for update;
 if found then
  if v_state.owner_id<>v_user or v_state.quantity_units<>v_units then raise exception 'basis_stock_changed';end if;
  if v_state.value_iqd is not null then raise exception 'basis_cost_already_known';end if;
 end if;
 if (select count(*) from public.inventory_cost_bases where owner_id=v_user and product_id=p_product)>=200 then raise exception 'basis_too_many_records';end if;
 insert into public.inventory_cost_bases(id,owner_id,product_id,quantity_units,stock_version,total_value,note,request_payload) values(p_id,v_user,p_product,v_units,v_version,p_total,btrim(p_note),v_payload);
 insert into public.inventory_cost_state(product_id,owner_id,quantity_units,value_iqd) values(p_product,v_user,v_units,p_total)
 on conflict(product_id) do update set value_iqd=excluded.value_iqd,updated_at=now();
 return jsonb_build_object('id',p_id,'product_id',p_product,'total_value',p_total::text);
end $$;
create function public.confirm_inventory_cost_basis(p_id uuid,p_product uuid,p_expected_units bigint,p_expected_version bigint,p_total bigint,p_note text) returns jsonb
language sql security invoker set search_path='' as $$select private.confirm_inventory_cost_basis(p_id,p_product,p_expected_units,p_expected_version,p_total,p_note);$$;
revoke all on function private.confirm_inventory_cost_basis(uuid,uuid,bigint,bigint,bigint,text),public.confirm_inventory_cost_basis(uuid,uuid,bigint,bigint,bigint,text) from public,anon,authenticated;
grant execute on function private.confirm_inventory_cost_basis(uuid,uuid,bigint,bigint,bigint,text),public.confirm_inventory_cost_basis(uuid,uuid,bigint,bigint,bigint,text) to authenticated;

create function private.cancel_inventory_cost_basis(p_id uuid,p_product uuid,p_basis uuid,p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();v_payload jsonb;v_row public.inventory_cost_basis_cancellations%rowtype;v_basis public.inventory_cost_bases%rowtype;v_units bigint;v_version bigint;v_value numeric;begin
 if v_user is null then raise exception 'basis_auth_required';end if;
 if p_id is null or p_product is null or p_basis is null then raise exception 'basis_invalid_request';end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'basis_note_required';end if;
 v_payload:=jsonb_build_object('product',p_product,'basis',p_basis,'reason',btrim(p_reason));
 perform pg_advisory_xact_lock(hashtextextended('kashier.cost-basis-cancel.'||p_id::text,0));
 select * into v_row from public.inventory_cost_basis_cancellations where id=p_id;
 if found then
  if v_row.owner_id<>v_user or v_row.request_payload<>v_payload then raise exception 'basis_request_conflict';end if;
  return jsonb_build_object('id',v_row.id,'product_id',v_row.product_id);
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 select * into v_basis from public.inventory_cost_bases where id=p_basis and owner_id=v_user and product_id=p_product;
 if not found then raise exception 'basis_product_unavailable';end if;
 if exists(select 1 from public.inventory_cost_basis_cancellations where basis_id=p_basis) then raise exception 'basis_already_cancelled';end if;
 select coalesce(quantity_units,0) into v_units from public.product_stock where product_id=p_product and owner_id=v_user for update;
 select coalesce(max(movement_no),0) into v_version from public.stock_movements where product_id=p_product and owner_id=v_user;
 select value_iqd into v_value from public.inventory_cost_state where product_id=p_product and owner_id=v_user and quantity_units=v_units for update;
 if v_units is distinct from v_basis.quantity_units or v_version<>v_basis.stock_version or v_value is distinct from v_basis.total_value::numeric then raise exception 'basis_used_by_movement';end if;
 insert into public.inventory_cost_basis_cancellations(id,owner_id,product_id,basis_id,reason,request_payload) values(p_id,v_user,p_product,p_basis,btrim(p_reason),v_payload);
 update public.inventory_cost_state set value_iqd=null,updated_at=now() where product_id=p_product and owner_id=v_user;
 return jsonb_build_object('id',p_id,'product_id',p_product);
end $$;
create function public.cancel_inventory_cost_basis(p_id uuid,p_product uuid,p_basis uuid,p_reason text) returns jsonb
language sql security invoker set search_path='' as $$select private.cancel_inventory_cost_basis(p_id,p_product,p_basis,p_reason);$$;
revoke all on function private.cancel_inventory_cost_basis(uuid,uuid,uuid,text),public.cancel_inventory_cost_basis(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.cancel_inventory_cost_basis(uuid,uuid,uuid,text),public.cancel_inventory_cost_basis(uuid,uuid,uuid,text) to authenticated;

create function public.get_inventory_cost_basis(p_product uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_product public.products%rowtype;v_units bigint;v_version bigint;v_state public.inventory_cost_state%rowtype;v_history jsonb;begin
 if v_user is null then raise exception 'basis_auth_required';end if;
 select * into v_product from public.products where id=p_product and owner_id=v_user;
 if not found then raise exception 'basis_product_unavailable';end if;
 select coalesce(quantity_units,0) into v_units from public.product_stock where product_id=p_product and owner_id=v_user;v_units:=coalesce(v_units,0);
 select coalesce(max(movement_no),0) into v_version from public.stock_movements where product_id=p_product and owner_id=v_user;
 select * into v_state from public.inventory_cost_state where product_id=p_product and owner_id=v_user;
 if found and v_state.quantity_units<>v_units then raise exception 'basis_stock_changed';end if;
 if (select count(*) from public.inventory_cost_bases where product_id=p_product and owner_id=v_user)>200 then raise exception 'basis_too_many_records';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'quantity_units',b.quantity_units::text,'stock_version',b.stock_version::text,'total_value',b.total_value::text,'note',b.note,'created_at',b.created_at,'cancellation_id',c.id,'cancel_reason',c.reason,'cancelled_at',c.created_at) order by b.created_at,b.id),'[]'::jsonb) into v_history
 from public.inventory_cost_bases b left join public.inventory_cost_basis_cancellations c on c.basis_id=b.id and c.owner_id=v_user where b.owner_id=v_user and b.product_id=p_product;
 return jsonb_build_object('scope','owner-inventory-cost-basis-v1','owner_id',v_user,'currency','IQD','timezone','Asia/Baghdad','generated_at',statement_timestamp(),'product',jsonb_build_object('id',v_product.id,'name',v_product.name,'quantity_units',v_units::text,'stock_version',v_version::text,'value_iqd',case when v_units=0 then '0' else v_state.value_iqd::text end),'history',v_history);
end $$;
revoke all on function public.get_inventory_cost_basis(uuid) from public,anon,authenticated;
grant execute on function public.get_inventory_cost_basis(uuid) to authenticated;

create or replace function public.export_owner_data() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_table text;v_key text;v_count bigint;v_size bigint;v_total bigint:=0;v_bytes bigint:=0;v_rows jsonb;v_counts jsonb:='{}'::jsonb;v_tables jsonb:='{}'::jsonb;
 v_names text[]:=array['products','product_stock','stock_movements','stock_adjustments','sales','sale_reversals','sale_returns','purchases','cash_accounts','cash_movements','customers','customer_balances','debt_entries','suppliers','supplier_balances','supplier_entries','purchase_reversals','purchase_returns','supplier_payment_allocations','customer_payment_allocations','customer_allocation_reversals','customer_installment_plans','customer_installment_cancellations','inventory_cost_state','inventory_cost_movements','inventory_cost_bases','inventory_cost_basis_cancellations'];
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
  v_key:=case v_table when 'inventory_cost_state' then 'product_id' when 'product_stock' then 'product_id' when 'cash_accounts' then 'owner_id' when 'customer_balances' then 'customer_id' when 'supplier_balances' then 'supplier_id' else 'id' end;
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by t.%I),''[]''::jsonb) from public.%I t where t.owner_id=$1',v_key,v_table) into v_rows using v_user;
  v_tables:=v_tables||jsonb_build_object(v_table,v_rows);
 end loop;
 return jsonb_build_object('format','kashier-owner-export','version',6,'schema_revision','audited-inventory-cost-basis-v1','owner_id',v_user,'generated_at',statement_timestamp(),'timezone','Asia/Baghdad','currency','IQD','record_count',v_total,'counts',v_counts,'tables',v_tables,
 'scope','business-data-only','excludes',jsonb_build_array('authentication accounts and sessions','passwords and API keys','database schema and RLS policies','automatic restore'));
end $$;
revoke all on function public.export_owner_data() from public,anon,authenticated;
grant execute on function public.export_owner_data() to authenticated;
notify pgrst,'reload schema';

