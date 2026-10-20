-- Forward-only perpetual weighted-average inventory valuation, rounded whole IQD per movement.
-- Existing stock/old sales receive no invented cost. Unknown stock stays unknown until depletion.
create table public.inventory_cost_state(
 product_id uuid primary key references public.products(id),owner_id uuid not null references auth.users(id),
 quantity_units bigint not null check(quantity_units between 0 and 1000000000000),
 value_iqd numeric(40,0) check(value_iqd>=0),updated_at timestamptz not null default now(),
 check(quantity_units<>0 or value_iqd=0)
);
create index inventory_cost_state_owner_idx on public.inventory_cost_state(owner_id);
create table public.inventory_cost_movements(
 id uuid primary key references public.stock_movements(id),owner_id uuid not null references auth.users(id),product_id uuid not null references public.products(id),
 created_at timestamptz not null,quantity_units bigint not null check(quantity_units<>0),value_delta numeric(40,0),
 balance_value numeric(40,0) check(balance_value>=0),policy text not null default 'moving-average-whole-iqd-v1' check(policy='moving-average-whole-iqd-v1'),
 coverage text not null check(coverage in ('known','unknown-opening-stock','unknown-return-cost','unknown-adjustment')),
 check((coverage='known')=(value_delta is not null)),check(value_delta is null or quantity_units*value_delta>=0)
);
create index inventory_cost_movements_owner_created_idx on public.inventory_cost_movements(owner_id,created_at,id);
create index inventory_cost_movements_product_idx on public.inventory_cost_movements(product_id);
alter table public.inventory_cost_state enable row level security;
alter table public.inventory_cost_movements enable row level security;
revoke all on public.inventory_cost_state,public.inventory_cost_movements from public,anon,authenticated;
grant select on public.inventory_cost_state,public.inventory_cost_movements to authenticated;
create policy inventory_cost_state_read_own on public.inventory_cost_state for select to authenticated using((select auth.uid())=owner_id);
create policy inventory_cost_movements_read_own on public.inventory_cost_movements for select to authenticated using((select auth.uid())=owner_id);

create function private.track_inventory_cost() returns trigger language plpgsql security definer set search_path='' as $$
declare v_state public.inventory_cost_state%rowtype;v_before bigint:=new.balance_after-new.delta_units;v_value numeric;v_delta numeric;v_added numeric;v_original record;v_sale uuid;v_previous numeric;v_reason text:='known';v_line jsonb;begin
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||new.owner_id::text,0));
 select * into v_state from public.inventory_cost_state where product_id=new.product_id for update;
 if found then
  if v_state.owner_id<>new.owner_id or v_state.quantity_units<>v_before then raise exception 'cost_stock_mismatch';end if;
  v_value:=v_state.value_iqd;
 else v_value:=case when v_before=0 then 0 else null end;
 end if;
 if new.delta_units<0 then
  if v_value is not null then
   if v_before<=0 or -new.delta_units>v_before then raise exception 'cost_stock_mismatch';end if;
   v_delta:=-round(v_value*(-new.delta_units)::numeric/v_before);
  else v_delta:=null;v_reason:='unknown-opening-stock';end if;
 else
  if new.purchase_id is not null then
   select p.lines->(new.line_no-1) into v_line from public.purchases p where p.id=new.purchase_id and p.owner_id=new.owner_id;
   if v_line is null or (v_line->>'product_id')::uuid<>new.product_id or (v_line->>'quantity_units')::bigint<>new.delta_units then raise exception 'cost_source_mismatch';end if;
   v_added:=(v_line->>'line_total')::numeric;
  elsif new.reversal_id is not null or new.return_id is not null then
   if new.reversal_id is not null then select sale_id into v_sale from public.sale_reversals where id=new.reversal_id and owner_id=new.owner_id;
   else select sale_id into v_sale from public.sale_returns where id=new.return_id and owner_id=new.owner_id;end if;
   select m.delta_units,c.value_delta into v_original from public.stock_movements m left join public.inventory_cost_movements c on c.id=m.id and c.owner_id=new.owner_id where m.sale_id=v_sale and m.line_no=new.line_no and m.owner_id=new.owner_id and m.product_id=new.product_id;
   if not found then raise exception 'cost_source_mismatch';end if;
   if v_original.value_delta is not null then
    select coalesce(sum(m.delta_units),0) into v_previous from public.stock_movements m
     left join public.sale_returns r on r.id=m.return_id and r.owner_id=new.owner_id left join public.sale_reversals z on z.id=m.reversal_id and z.owner_id=new.owner_id
     where m.owner_id=new.owner_id and m.product_id=new.product_id and m.line_no=new.line_no and (r.sale_id=v_sale or z.sale_id=v_sale) and m.id<>new.id;
    if v_previous+new.delta_units>-v_original.delta_units then raise exception 'cost_source_mismatch';end if;
    v_added:=round((-v_original.value_delta)*(v_previous+new.delta_units)/(-v_original.delta_units))-round((-v_original.value_delta)*v_previous/(-v_original.delta_units));
   else v_added:=null;v_reason:='unknown-return-cost';end if;
  else v_added:=null;v_reason:='unknown-adjustment';end if;
  -- Source value can be known even when the resulting pooled inventory is not.
  v_delta:=v_added;
 end if;
 if v_delta is not null then v_reason:='known';end if;
 v_value:=case when new.balance_after=0 then 0 when v_value is null or v_delta is null then null else v_value+v_delta end;
 insert into public.inventory_cost_state(product_id,owner_id,quantity_units,value_iqd) values(new.product_id,new.owner_id,new.balance_after,v_value)
 on conflict(product_id) do update set quantity_units=excluded.quantity_units,value_iqd=excluded.value_iqd,updated_at=now();
 insert into public.inventory_cost_movements(id,owner_id,product_id,created_at,quantity_units,value_delta,balance_value,coverage) values(new.id,new.owner_id,new.product_id,new.created_at,new.delta_units,v_delta,v_value,v_reason);
 return new;
end $$;
revoke all on function private.track_inventory_cost() from public,anon,authenticated;
create trigger track_inventory_cost after insert on public.stock_movements for each row execute function private.track_inventory_cost();

create function public.get_gross_profit_report(p_from date,p_to date) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_start timestamptz;v_end timestamptz;v_rows jsonb;v_count bigint;v_known bigint;v_revenue numeric;v_covered numeric;v_cost numeric;v_unknown numeric;begin
 if v_user is null then raise exception 'profit_auth_required';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>365 or p_from<date '2000-01-01' or p_to>date '2100-12-31' then raise exception 'profit_invalid_range';end if;
 v_start:=p_from::timestamp at time zone 'Asia/Baghdad';v_end:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 if (select count(*) from public.stock_movements m where m.owner_id=v_user and m.created_at>=v_start and m.created_at<v_end and(m.sale_id is not null or m.return_id is not null or m.reversal_id is not null))>5000 then raise exception 'profit_too_many_rows';end if;
 -- Never silently omit a receipt whose stock history is absent or malformed.
 if (select coalesce(sum(jsonb_array_length(lines)),0) from public.sales where owner_id=v_user and created_at>=v_start and created_at<v_end)
    <> (select count(*) from public.stock_movements where owner_id=v_user and created_at>=v_start and created_at<v_end and sale_id is not null)
 or (select coalesce(sum(jsonb_array_length(lines)),0) from public.sale_returns where owner_id=v_user and created_at>=v_start and created_at<v_end)
    <> (select count(*) from public.stock_movements where owner_id=v_user and created_at>=v_start and created_at<v_end and return_id is not null)
 or (select coalesce(sum(jsonb_array_length(lines)),0) from public.sale_reversals where owner_id=v_user and created_at>=v_start and created_at<v_end)
    <> (select count(*) from public.stock_movements where owner_id=v_user and created_at>=v_start and created_at<v_end and reversal_id is not null)
 then raise exception 'profit_incomplete_stock_history';end if;
 with events as (
  select m.*,coalesce(m.sale_id,r.sale_id,z.sale_id) original_sale_id,case when m.sale_id is not null then 'sale' when m.return_id is not null then 'partial_return' else 'full_return' end kind,
   r.lines return_lines,z.reversal_no,r.return_no
  from public.stock_movements m left join public.sale_returns r on r.id=m.return_id and r.owner_id=v_user left join public.sale_reversals z on z.id=m.reversal_id and z.owner_id=v_user
  where m.owner_id=v_user and m.created_at>=v_start and m.created_at<v_end and(m.sale_id is not null or m.return_id is not null or m.reversal_id is not null)
 ), amounts as (
  select e.*,s.receipt_no,s.lines->(e.line_no-1) original_line,s.subtotal,s.discount,
   coalesce((select sum((x->>'line_total')::numeric) from jsonb_array_elements(s.lines) with ordinality t(x,n) where n<=e.line_no),0) cumulative,
   c.value_delta,c.coverage,c.id cost_id
  from events e join public.sales s on s.id=e.original_sale_id and s.owner_id=v_user left join public.inventory_cost_movements c on c.id=e.id and c.owner_id=v_user
 ), rows as (
  select a.*,case when a.kind='partial_return' then -coalesce((select (x->>'line_total')::numeric from jsonb_array_elements(a.return_lines) x where (x->>'line_no')::integer=a.line_no),0)
   else (case when a.kind='sale' then 1 else -1 end)*((a.original_line->>'line_total')::numeric-case when a.subtotal=0 then 0 else div(a.discount::numeric*a.cumulative,a.subtotal)-div(a.discount::numeric*(a.cumulative-(a.original_line->>'line_total')::numeric),a.subtotal) end) end revenue,
   case when a.cost_id is null then 'legacy-no-cost-snapshot' else a.coverage end cost_coverage
  from amounts a
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'movement_no',movement_no::text,'created_at',created_at,'day',(created_at at time zone 'Asia/Baghdad')::date::text,'kind',kind,'sale_id',original_sale_id,'receipt_no',receipt_no::text,'return_id',coalesce(return_id,reversal_id),'line_no',line_no,'product_id',product_id,'name',original_line->>'name','quantity_units',delta_units::text,'revenue',revenue::text,'cogs',(-value_delta)::text,'margin',(revenue+value_delta)::text,'coverage',cost_coverage) order by movement_no),'[]'::jsonb),count(*),count(value_delta),coalesce(sum(revenue),0),coalesce(sum(revenue) filter(where value_delta is not null),0),coalesce(sum(-value_delta),0),coalesce(sum(revenue) filter(where value_delta is null),0)
 into v_rows,v_count,v_known,v_revenue,v_covered,v_cost,v_unknown from rows;
 return jsonb_build_object('scope','owner-gross-profit-v1','owner_id',v_user,'currency','IQD','timezone','Asia/Baghdad','from',p_from::text,'to',p_to::text,'generated_at',statement_timestamp(),'policy','moving-average-whole-iqd-v1','count',v_count,'known_count',v_known,'revenue',v_revenue::text,'covered_revenue',v_covered::text,'unknown_revenue',v_unknown::text,'known_cogs',v_cost::text,'known_margin',(v_covered-v_cost)::text,'complete',v_count=v_known,'rows',v_rows);
end $$;
revoke all on function public.get_gross_profit_report(date,date) from public,anon,authenticated;
grant execute on function public.get_gross_profit_report(date,date) to authenticated;

create or replace function public.export_owner_data() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_table text;v_key text;v_count bigint;v_size bigint;v_total bigint:=0;v_bytes bigint:=0;v_rows jsonb;v_counts jsonb:='{}'::jsonb;v_tables jsonb:='{}'::jsonb;
 v_names text[]:=array['products','product_stock','stock_movements','stock_adjustments','sales','sale_reversals','sale_returns','purchases','cash_accounts','cash_movements','customers','customer_balances','debt_entries','suppliers','supplier_balances','supplier_entries','purchase_reversals','purchase_returns','supplier_payment_allocations','customer_payment_allocations','customer_allocation_reversals','customer_installment_plans','customer_installment_cancellations','inventory_cost_state','inventory_cost_movements'];
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
 return jsonb_build_object('format','kashier-owner-export','version',5,'schema_revision','forward-inventory-cost-v1','owner_id',v_user,'generated_at',statement_timestamp(),'timezone','Asia/Baghdad','currency','IQD','record_count',v_total,'counts',v_counts,'tables',v_tables,
 'scope','business-data-only','excludes',jsonb_build_array('authentication accounts and sessions','passwords and API keys','database schema and RLS policies','automatic restore'));
end $$;
revoke all on function public.export_owner_data() from public,anon,authenticated;
grant execute on function public.export_owner_data() to authenticated;
notify pgrst,'reload schema';
