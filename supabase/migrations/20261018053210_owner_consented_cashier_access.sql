create or replace function private.post_cash_sale_for_owner(p_owner uuid,p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer text,p_note text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid := p_owner;
 v_payload jsonb;
 v_sale public.sales%rowtype;
 v_line jsonb;
 v_product public.products%rowtype;
 v_qty bigint;
 v_expected bigint;
 v_line_total bigint;
 v_subtotal bigint := 0;
 v_lines jsonb := '[]'::jsonb;
 v_stock record;
 v_after bigint;
 v_index integer := 0;
 v_cash_after bigint;
begin
 if v_user is null or auth.uid() is null then raise exception using errcode='28000',message='sale_auth_required'; end if;
 if p_id is null or p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'sale_invalid_items'; end if;
 if jsonb_array_length(p_items) not between 1 and 200 then raise exception 'sale_invalid_items'; end if;
 if p_discount is null or p_received is null or p_discount<0 or p_received<0 or p_received>100000000000000 then raise exception 'sale_invalid_money'; end if;
 if char_length(coalesce(p_customer,''))>100 or char_length(coalesce(p_note,''))>500 then raise exception 'sale_invalid_text'; end if;
 v_payload := jsonb_build_object('items',p_items,'discount',p_discount,'received',p_received,'customer',btrim(coalesce(p_customer,'')),'note',btrim(coalesce(p_note,'')));
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale.'||p_id::text,0));
 select * into v_sale from public.sales where id=p_id;
 if found then
  if v_sale.owner_id<>v_user or v_sale.request_payload<>v_payload then raise exception 'sale_request_conflict'; end if;
  return to_jsonb(v_sale)-'owner_id'-'request_payload';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 for v_line in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(v_line)<>'object' or coalesce(v_line->>'quantity_units','') !~ '^[0-9]{1,8}$' or coalesce(v_line->>'expected_price','') !~ '^[0-9]{1,10}$' then raise exception 'sale_invalid_items'; end if;
  v_qty := (v_line->>'quantity_units')::bigint;
  v_expected := (v_line->>'expected_price')::bigint;
  if v_qty not between 1 and 10000000 then raise exception 'sale_invalid_quantity'; end if;
  select * into v_product from public.products where id=(v_line->>'product_id')::uuid and owner_id=v_user for share;
  if not found then raise exception 'sale_product_unavailable'; end if;
  if v_expected<>v_product.sale_price then raise exception 'sale_price_changed'; end if;
  v_line_total := (v_qty*v_product.sale_price+500)/1000;
  v_subtotal := v_subtotal+v_line_total;
  if v_subtotal>100000000000000 then raise exception 'sale_total_limit'; end if;
  v_lines := v_lines || jsonb_build_array(jsonb_build_object('product_id',v_product.id,'name',v_product.name,'barcode',v_product.barcode,'quantity_units',v_qty,'unit_price',v_product.sale_price,'line_total',v_line_total));
 end loop;
 if p_discount>v_subtotal then raise exception 'sale_discount_exceeds_total'; end if;
 if p_received<v_subtotal-p_discount then raise exception 'sale_payment_shortfall'; end if;
 for v_stock in select (x->>'product_id')::uuid as product_id,sum((x->>'quantity_units')::bigint) as required from jsonb_array_elements(v_lines) x group by (x->>'product_id')::uuid loop
  select quantity_units into v_after from public.product_stock where product_id=v_stock.product_id and owner_id=v_user for update;
  if not found or v_after<v_stock.required then raise exception 'sale_insufficient_stock'; end if;
 end loop;
 insert into public.sales(id,owner_id,customer_name,note,subtotal,discount,total,received,change_due,lines,request_payload)
 values(p_id,v_user,btrim(coalesce(p_customer,'')),btrim(coalesce(p_note,'')),v_subtotal,p_discount,v_subtotal-p_discount,p_received,p_received-(v_subtotal-p_discount),v_lines,v_payload)
 returning * into v_sale;
 for v_line in select value from jsonb_array_elements(v_lines) loop
  v_index:=v_index+1;
  v_qty:=(v_line->>'quantity_units')::bigint;
  update public.product_stock set quantity_units=quantity_units-v_qty,updated_at=now()
   where product_id=(v_line->>'product_id')::uuid and owner_id=v_user and quantity_units>=v_qty returning quantity_units into v_after;
  if not found then raise exception 'sale_insufficient_stock'; end if;
  insert into public.stock_movements(owner_id,product_id,sale_id,line_no,delta_units,balance_after)
   values(v_user,(v_line->>'product_id')::uuid,p_id,v_index,-v_qty,v_after);
 end loop;
 perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
 insert into public.cash_accounts(owner_id,balance) values(v_user,v_sale.total)
  on conflict(owner_id) do update set balance=public.cash_accounts.balance+excluded.balance,updated_at=now() returning balance into v_cash_after;
 insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,sale_id,note,request_payload)
 values(v_user,'sale',v_sale.total,v_sale.total,v_cash_after,p_id,'',jsonb_build_object('sale_id',p_id));
 return to_jsonb(v_sale)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_cash_sale_for_owner(uuid,uuid,jsonb,bigint,bigint,text,text) from public,anon,authenticated;
create or replace function private.post_cash_sale(p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer text,p_note text) returns jsonb language sql security definer set search_path='' as $$select private.post_cash_sale_for_owner(auth.uid(),p_id,p_items,p_discount,p_received,p_customer,p_note);$$;
-- Owner-scoped cashier access. Existing owner RLS remains unchanged.
create table public.store_cashiers(id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users(id),member_id uuid not null references auth.users(id),member_name text not null check(char_length(btrim(member_name)) between 1 and 100),store_name text not null check(char_length(btrim(store_name)) between 1 and 100),can_discount boolean not null default false,enabled boolean not null default true,accepted_at timestamptz,version bigint not null default 1 check(version>0),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(owner_id,member_id),check(owner_id<>member_id));
create index store_cashiers_member_idx on public.store_cashiers(member_id,id);
create table public.staff_actions(id uuid primary key,owner_id uuid not null references auth.users(id),member_id uuid not null references auth.users(id),actor_id uuid not null references auth.users(id),membership_id uuid not null references public.store_cashiers(id),kind text not null check(kind in('invite','update','accept')),created_at timestamptz not null default now(),before_state jsonb,after_state jsonb not null,request_payload jsonb not null,result_payload jsonb not null);
create index staff_actions_owner_order_idx on public.staff_actions(owner_id,created_at desc,id);
create index staff_actions_member_idx on public.staff_actions(member_id,id);
create index staff_actions_actor_idx on public.staff_actions(actor_id);
create index staff_actions_membership_idx on public.staff_actions(membership_id);
alter table public.store_cashiers enable row level security;alter table public.staff_actions enable row level security;
revoke all on public.store_cashiers,public.staff_actions from public,anon,authenticated;grant select on public.store_cashiers,public.staff_actions to authenticated;
create policy store_cashiers_read_participant on public.store_cashiers for select to authenticated using((select auth.uid())=owner_id or(select auth.uid())=member_id);
create policy staff_actions_read_participant on public.staff_actions for select to authenticated using((select auth.uid())=owner_id or(select auth.uid())=member_id);
alter table public.sales add column actor_id uuid references auth.users(id),add column actor_name text check(actor_name is null or char_length(btrim(actor_name)) between 1 and 100);
alter table public.sales alter column actor_id set default auth.uid();
create index sales_owner_actor_order_idx on public.sales(owner_id,actor_id,created_at desc,id);
create index sales_actor_idx on public.sales(actor_id);

create function public.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r public.store_cashiers%rowtype;e public.staff_actions%rowtype;payload jsonb;old jsonb;result jsonb;k text;begin
 if u is null then raise exception 'staff_auth_required';end if;
 if p_id is null or p_member is null or p_member=u or p_discount is null or p_enabled is null or p_expected_version is null or p_expected_version<0 or char_length(btrim(coalesce(p_name,''))) not between 1 and 100 or char_length(btrim(coalesce(p_store,''))) not between 1 and 100 then raise exception 'staff_invalid_request';end if;
 payload:=jsonb_build_object('kind','save','member',p_member,'name',btrim(p_name),'store',btrim(p_store),'discount',p_discount,'enabled',p_enabled,'expected_version',p_expected_version);
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff-action.'||p_id::text,0));select * into e from public.staff_actions where id=p_id;
 if found then if e.actor_id<>u or e.owner_id<>u or e.request_payload<>payload then raise exception 'staff_request_conflict';end if;return e.result_payload;end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||u::text,0));
 select * into r from public.store_cashiers where owner_id=u and member_id=p_member for update;old:=case when found then to_jsonb(r) else null end;
 if old is null then
  if p_expected_version<>0 then raise exception 'staff_changed';end if;
  if not exists(select 1 from auth.users where id=p_member) then raise exception 'staff_member_unavailable';end if;
  perform pg_advisory_xact_lock(hashtextextended('kashier.staff-member.'||p_member::text,0));
  if (select count(*) from public.store_cashiers where owner_id=u)>=50 or(select count(*) from public.store_cashiers where member_id=p_member)>=50 then raise exception 'staff_limit';end if;
  insert into public.store_cashiers(owner_id,member_id,member_name,store_name,can_discount,enabled) values(u,p_member,btrim(p_name),btrim(p_store),p_discount,p_enabled) returning * into r;k:='invite';
 else
  if r.version<>p_expected_version then raise exception 'staff_changed';end if;
  update public.store_cashiers set member_name=btrim(p_name),store_name=btrim(p_store),can_discount=p_discount,enabled=p_enabled,version=version+1,updated_at=now() where id=r.id returning * into r;k:='update';
 end if;
 result:=jsonb_build_object('id',p_id,'membership_id',r.id,'version',r.version::text);
 insert into public.staff_actions(id,owner_id,member_id,actor_id,membership_id,kind,before_state,after_state,request_payload,result_payload) values(p_id,u,p_member,u,r.id,k,old,to_jsonb(r),payload,result);return result;
end $$;
create function public.accept_store_cashier(p_id uuid,p_membership uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r public.store_cashiers%rowtype;e public.staff_actions%rowtype;payload jsonb;old jsonb;result jsonb;begin
 if u is null then raise exception 'staff_auth_required';end if;if p_id is null or p_membership is null then raise exception 'staff_invalid_request';end if;
 payload:=jsonb_build_object('kind','accept','membership',p_membership);
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff-action.'||p_id::text,0));select * into e from public.staff_actions where id=p_id;
 if found then if e.actor_id<>u or e.request_payload<>payload then raise exception 'staff_request_conflict';end if;return e.result_payload;end if;
 select * into r from public.store_cashiers where id=p_membership and member_id=u;if not found then raise exception 'staff_unavailable';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||r.owner_id::text,0));select * into r from public.store_cashiers where id=p_membership and member_id=u for update;
 if not r.enabled then raise exception 'staff_disabled';end if;if r.accepted_at is not null then raise exception 'staff_already_accepted';end if;
 old:=to_jsonb(r);update public.store_cashiers set accepted_at=now(),version=version+1,updated_at=now() where id=r.id returning * into r;
 result:=jsonb_build_object('id',p_id,'membership_id',r.id,'version',r.version::text);
 insert into public.staff_actions(id,owner_id,member_id,actor_id,membership_id,kind,before_state,after_state,request_payload,result_payload) values(p_id,r.owner_id,u,u,r.id,'accept',old,to_jsonb(r),payload,result);return result;
end $$;
create function public.get_staff_workspace() returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare u uuid:=auth.uid();begin if u is null then raise exception 'staff_auth_required';end if;
 return jsonb_build_object('scope','owner-cashier-workspace-v1','actor_id',u,'generated_at',statement_timestamp(),
 'cashiers',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('version',c.version::text) order by c.created_at,c.id) from public.store_cashiers c where c.owner_id=u),'[]'::jsonb),
 'memberships',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('version',c.version::text) order by c.created_at,c.id) from public.store_cashiers c where c.member_id=u),'[]'::jsonb),
 'history',coalesce((select jsonb_agg(to_jsonb(a)-'request_payload'-'result_payload' order by a.created_at desc,a.id) from(select * from public.staff_actions where owner_id=u or member_id=u order by created_at desc,id limit 100)a),'[]'::jsonb));end $$;
create function private.cashier_membership(p_owner uuid) returns public.store_cashiers language plpgsql stable security definer set search_path='' as $$declare r public.store_cashiers%rowtype;begin
 if auth.uid() is null then raise exception 'staff_auth_required';end if;
 select * into r from public.store_cashiers where owner_id=p_owner and member_id=auth.uid();if not found or not r.enabled or r.accepted_at is null then raise exception 'staff_access_denied';end if;return r;end $$;
revoke all on function private.cashier_membership(uuid) from public,anon,authenticated;
create function public.get_cashier_catalog(p_owner uuid,p_query text default '',p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;q text:=btrim(coalesce(p_query,''));rows jsonb;total bigint;begin
 r:=private.cashier_membership(p_owner);if p_offset is null or p_offset not between 0 and 1000000 or char_length(q)>100 then raise exception 'staff_invalid_request';end if;
 select count(*) into total from public.products p where p.owner_id=p_owner and(q='' or strpos(lower(p.name),lower(q))>0 or strpos(coalesce(p.barcode,''),q)>0);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.name,x.id),'[]'::jsonb) into rows from(select p.id,p.name,p.barcode,p.sale_price::text,coalesce(s.quantity_units,0)::text quantity_units from public.products p left join public.product_stock s on s.product_id=p.id and s.owner_id=p_owner where p.owner_id=p_owner and(q='' or strpos(lower(p.name),lower(q))>0 or strpos(coalesce(p.barcode,''),q)>0) order by p.name,p.id limit 50 offset p_offset)x;
 return jsonb_build_object('scope','cashier-catalog-v1','owner_id',p_owner,'actor_id',auth.uid(),'membership_id',r.id,'store_name',r.store_name,'member_name',r.member_name,'can_discount',r.can_discount,'version',r.version::text,'query',q,'offset',p_offset,'total',total::text,'rows',rows);end $$;
create function public.post_cashier_sale(p_owner uuid,p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer text,p_note text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;s public.sales%rowtype;result jsonb;begin
 if auth.uid() is null then raise exception 'staff_auth_required';end if;if p_owner is null or p_id is null then raise exception 'staff_invalid_request';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||p_owner::text,0));r:=private.cashier_membership(p_owner);
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale.'||p_id::text,0));select * into s from public.sales where id=p_id;
 if found and(s.owner_id<>p_owner or s.actor_id is distinct from auth.uid()) then raise exception 'staff_request_conflict';end if;
 -- Existing identical requests may be acknowledged after discount permission is withdrawn.
 if s.id is null and p_discount>0 and not r.can_discount then raise exception 'staff_discount_denied';end if;
 result:=private.post_cash_sale_for_owner(p_owner,p_id,p_items,p_discount,p_received,p_customer,p_note);
 update public.sales set actor_name=r.member_name where id=p_id and actor_name is null;
 select * into s from public.sales where id=p_id;return to_jsonb(s)-'owner_id'-'request_payload';end $$;
create function public.get_cashier_sale(p_owner uuid,p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;s public.sales%rowtype;begin r:=private.cashier_membership(p_owner);select * into s from public.sales where id=p_id and owner_id=p_owner and actor_id=auth.uid();if not found then raise exception 'staff_sale_unavailable';end if;return to_jsonb(s)-'owner_id'-'request_payload';end $$;
create function public.list_cashier_sales(p_owner uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$declare r public.store_cashiers%rowtype;rows jsonb;begin r:=private.cashier_membership(p_owner);select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]'::jsonb) into rows from(select id,receipt_no::text,created_at,total::text,actor_id,actor_name from public.sales where owner_id=p_owner and actor_id=auth.uid() order by created_at desc,id limit 20)x;return jsonb_build_object('owner_id',p_owner,'actor_id',auth.uid(),'rows',rows);end $$;
revoke all on function public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint),public.accept_store_cashier(uuid,uuid),public.get_staff_workspace(),public.get_cashier_catalog(uuid,text,integer),public.post_cashier_sale(uuid,uuid,jsonb,bigint,bigint,text,text),public.get_cashier_sale(uuid,uuid),public.list_cashier_sales(uuid) from public,anon,authenticated;
grant execute on function public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint),public.accept_store_cashier(uuid,uuid),public.get_staff_workspace(),public.get_cashier_catalog(uuid,text,integer),public.post_cashier_sale(uuid,uuid,jsonb,bigint,bigint,text,text),public.get_cashier_sale(uuid,uuid),public.list_cashier_sales(uuid) to authenticated;
create or replace function public.export_owner_data() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_table text;v_key text;v_count bigint;v_size bigint;v_total bigint:=0;v_bytes bigint:=0;v_rows jsonb;v_counts jsonb:='{}'::jsonb;v_tables jsonb:='{}'::jsonb;
 v_names text[]:=array['products','product_stock','stock_movements','stock_adjustments','sales','sale_reversals','sale_returns','purchases','cash_accounts','cash_movements','customers','customer_balances','debt_entries','suppliers','supplier_balances','supplier_entries','purchase_reversals','purchase_returns','supplier_payment_allocations','customer_payment_allocations','customer_allocation_reversals','customer_installment_plans','customer_installment_cancellations','inventory_cost_state','inventory_cost_movements','inventory_cost_bases','inventory_cost_basis_cancellations','store_cashiers','staff_actions'];
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
 return jsonb_build_object('format','kashier-owner-export','version',7,'schema_revision','consented-cashier-access-v1','owner_id',v_user,'generated_at',statement_timestamp(),'timezone','Asia/Baghdad','currency','IQD','record_count',v_total,'counts',v_counts,'tables',v_tables,
 'scope','business-data-only','excludes',jsonb_build_array('authentication accounts and sessions','passwords and API keys','database schema and RLS policies','automatic restore'));
end $$;
revoke all on function public.export_owner_data() from public,anon,authenticated;
grant execute on function public.export_owner_data() to authenticated;
notify pgrst,'reload schema';

