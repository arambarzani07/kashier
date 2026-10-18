alter table public.store_cashiers add column can_refund boolean not null default false;
alter table public.sale_reversals add column actor_id uuid,add column actor_name text check(actor_name is null or char_length(btrim(actor_name)) between 1 and 100);
alter table public.sale_reversals alter column actor_id set default auth.uid();
create index sale_reversals_staff_receipts_idx on public.sale_reversals(owner_id,actor_id,reversal_no desc) where actor_name is not null;
drop function public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean);
drop function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean);
create function private.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint,p_role text default 'cashier',p_credit boolean default false,p_repay boolean default false,p_refund boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r public.store_cashiers%rowtype;e public.staff_actions%rowtype;payload jsonb;old jsonb;result jsonb;k text;begin
 if u is null then raise exception 'staff_auth_required';end if;
 if p_refund is null or p_repay is null or p_credit is null or p_role is null or p_role not in ('cashier','manager') or p_id is null or p_member is null or p_member=u or p_discount is null or p_enabled is null or p_expected_version is null or p_expected_version<0 or char_length(btrim(coalesce(p_name,''))) not between 1 and 100 or char_length(btrim(coalesce(p_store,''))) not between 1 and 100 then raise exception 'staff_invalid_request';end if;
 payload:=jsonb_build_object('kind','save','member',p_member,'name',btrim(p_name),'store',btrim(p_store),'discount',p_discount,'enabled',p_enabled,'expected_version',p_expected_version,'role',p_role,'credit',p_credit,'repay',p_repay,'refund',p_refund);
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff-action.'||p_id::text,0));select * into e from public.staff_actions where id=p_id;
 if found then if e.actor_id<>u or e.owner_id<>u or (e.request_payload||jsonb_build_object('role',coalesce(e.request_payload->>'role','cashier'),'credit',coalesce((e.request_payload->>'credit')::boolean,false),'repay',coalesce((e.request_payload->>'repay')::boolean,false),'refund',coalesce((e.request_payload->>'refund')::boolean,false)))<>payload then raise exception 'staff_request_conflict';end if;return e.result_payload;end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||u::text,0));
 select * into r from public.store_cashiers where owner_id=u and member_id=p_member for update;old:=case when found then to_jsonb(r) else null end;
 if old is null then
  if p_expected_version<>0 then raise exception 'staff_changed';end if;
  if not exists(select 1 from auth.users where id=p_member) then raise exception 'staff_member_unavailable';end if;
  perform pg_advisory_xact_lock(hashtextextended('kashier.staff-member.'||p_member::text,0));
  if (select count(*) from public.store_cashiers where owner_id=u)>=50 or(select count(*) from public.store_cashiers where member_id=p_member)>=50 then raise exception 'staff_limit';end if;
  insert into public.store_cashiers(owner_id,member_id,member_name,store_name,can_discount,enabled,role,can_credit,can_repay,can_refund) values(u,p_member,btrim(p_name),btrim(p_store),p_discount,p_enabled,p_role,p_credit,p_repay,p_refund) returning * into r;k:='invite';
 else
  if r.version<>p_expected_version then raise exception 'staff_changed';end if;
  update public.store_cashiers set can_refund=p_refund,can_repay=p_repay,can_credit=p_credit,role=p_role,member_name=btrim(p_name),store_name=btrim(p_store),can_discount=p_discount,enabled=p_enabled,version=version+1,updated_at=now() where id=r.id returning * into r;k:='update';
 end if;
 result:=jsonb_build_object('id',p_id,'membership_id',r.id,'version',r.version::text);
 insert into public.staff_actions(id,owner_id,member_id,actor_id,membership_id,kind,before_state,after_state,request_payload,result_payload) values(p_id,u,p_member,u,r.id,k,old,to_jsonb(r),payload,result);return result;
end $$;
create function public.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint,p_role text default 'cashier',p_credit boolean default false,p_repay boolean default false,p_refund boolean default false) returns jsonb language sql security invoker set search_path='' as $$select private.save_store_cashier(p_id,p_member,p_name,p_store,p_discount,p_enabled,p_expected_version,p_role,p_credit,p_repay,p_refund);$$;
revoke all on function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean,boolean),public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean,boolean),public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean,boolean) to authenticated;
create function private.post_sale_reversal_for_owner(p_owner uuid,p_id uuid,p_sale uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=p_owner;
 v_payload jsonb;
 v_reversal public.sale_reversals%rowtype;
 v_sale public.sales%rowtype;
 v_line jsonb;
 v_stock record;
 v_qty bigint;
 v_after bigint;
 v_index integer:=0;
 v_refund bigint;
 v_debt bigint;
 v_debt_after bigint;
 v_cash_after bigint;
begin
 if v_user is null or auth.uid() is null then raise exception using errcode='28000',message='reversal_auth_required'; end if;
 if p_id is null or p_sale is null then raise exception 'reversal_invalid_request'; end if;
 if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'reversal_reason_required'; end if;
 v_payload:=jsonb_build_object('sale_id',p_sale,'reason',btrim(p_reason));
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale-reversal.'||p_id::text,0));
 select * into v_reversal from public.sale_reversals where id=p_id;
 if found then
  if v_reversal.owner_id<>v_user or v_reversal.request_payload<>v_payload then raise exception 'reversal_request_conflict'; end if;
  return to_jsonb(v_reversal)-'owner_id'-'request_payload';
 end if;
 -- Shared with partial returns: all full/partial adjustments serialize on the same sale.
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale-adjustment.'||p_sale::text,0));
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale-reversal-sale.'||p_sale::text,0));
 select * into v_sale from public.sales where id=p_sale and owner_id=v_user for share;
 if not found then raise exception 'reversal_sale_unavailable'; end if;
 if exists(select 1 from public.sale_returns where owner_id=v_user and sale_id=p_sale) then raise exception 'reversal_partial_returns_exist';end if;
 if exists(select 1 from public.sale_reversals where sale_id=p_sale) then raise exception 'reversal_already_posted'; end if;
 v_debt:=v_sale.debt_amount;
 v_refund:=v_sale.total-v_debt;
 if v_refund<0 then raise exception 'reversal_invalid_sale'; end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
 if v_debt>0 then
  perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||v_user::text,0));
  select balance-v_debt into v_debt_after from public.customer_balances where customer_id=v_sale.customer_id and owner_id=v_user for update;
  if not found or v_debt_after<0 then raise exception 'reversal_debt_already_repaid'; end if;
 end if;
 if v_refund>0 then
  perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
  select balance-v_refund into v_cash_after from public.cash_accounts where owner_id=v_user for update;
  if not found or v_cash_after<0 then raise exception 'reversal_cash_insufficient'; end if;
 end if;
 for v_stock in
  select (x->>'product_id')::uuid as product_id,sum((x->>'quantity_units')::bigint) as returned
  from jsonb_array_elements(v_sale.lines) x group by (x->>'product_id')::uuid
 loop
  select quantity_units into v_after from public.product_stock where product_id=v_stock.product_id and owner_id=v_user for update;
  if not found then raise exception 'reversal_stock_unavailable'; end if;
  if v_after>1000000000000-v_stock.returned then raise exception 'reversal_stock_limit'; end if;
 end loop;
 insert into public.sale_reversals(id,owner_id,sale_id,reason,total,cash_refund,debt_reversed,lines,request_payload)
 values(p_id,v_user,p_sale,btrim(p_reason),v_sale.total,v_refund,v_debt,v_sale.lines,v_payload)
 returning * into v_reversal;
 for v_line in select value from jsonb_array_elements(v_sale.lines) loop
  v_index:=v_index+1;
  v_qty:=(v_line->>'quantity_units')::bigint;
  update public.product_stock set quantity_units=quantity_units+v_qty,updated_at=now()
   where product_id=(v_line->>'product_id')::uuid and owner_id=v_user returning quantity_units into v_after;
  if not found then raise exception 'reversal_stock_unavailable'; end if;
  insert into public.stock_movements(owner_id,product_id,reversal_id,line_no,delta_units,balance_after)
   values(v_user,(v_line->>'product_id')::uuid,p_id,v_index,v_qty,v_after);
 end loop;
 if v_debt>0 then
  update public.customer_balances set balance=v_debt_after,updated_at=now() where customer_id=v_sale.customer_id and owner_id=v_user;
  insert into public.debt_entries(id,owner_id,customer_id,customer_name,kind,amount,delta,balance_after,note,cash_movement_id,request_payload,sale_id,reversal_id)
   values(gen_random_uuid(),v_user,v_sale.customer_id,v_sale.customer_name,'reversal',v_debt,-v_debt,v_debt_after,btrim(p_reason),null,jsonb_build_object('reversal_id',p_id,'sale_id',p_sale),null,p_id);
 end if;
 if v_refund>0 then
  update public.cash_accounts set balance=v_cash_after,updated_at=now() where owner_id=v_user;
  insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,sale_id,note,request_payload,customer_id,reversal_id)
   values(v_user,'refund',v_refund,-v_refund,v_cash_after,null,btrim(p_reason),jsonb_build_object('reversal_id',p_id,'sale_id',p_sale),null,p_id);
 end if;
 return to_jsonb(v_reversal)-'owner_id'-'request_payload';
end $$;

revoke all on function private.post_sale_reversal_for_owner(uuid,uuid,uuid,text) from public,anon,authenticated;
create or replace function private.post_sale_reversal(p_id uuid,p_sale uuid,p_reason text) returns jsonb language sql security definer set search_path='' as $$select private.post_sale_reversal_for_owner(auth.uid(),p_id,p_sale,p_reason);$$;
create function private.get_cashier_refund_sale(p_owner uuid,p_sale uuid default null,p_number bigint default null) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;s public.sales%rowtype;z uuid;n bigint;begin
 r:=private.cashier_membership(p_owner);if (p_sale is null)=(p_number is null) or(p_number is not null and p_number<1) then raise exception 'staff_invalid_request';end if;
 select * into s from public.sales where owner_id=p_owner and actor_id=auth.uid() and(case when p_sale is not null then id=p_sale else receipt_no=p_number end);
 if not found then raise exception 'staff_sale_unavailable';end if;if s.payment_mode<>'cash' then raise exception 'staff_refund_cash_only';end if;
 select id into z from public.sale_reversals where owner_id=p_owner and sale_id=s.id;
 select count(*) into n from public.sale_returns where owner_id=p_owner and sale_id=s.id;
 return jsonb_build_object('scope','cashier-refund-sale-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'sale',to_jsonb(s)-'owner_id'-'request_payload','can_refund',r.can_refund,'full_refund_id',z,'partial_count',n::text,'eligible',r.can_refund and z is null and n=0);
end $$;
create function private.get_cashier_refund(p_owner uuid,p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;z public.sale_reversals%rowtype;s public.sales%rowtype;begin
 r:=private.cashier_membership(p_owner);
 select * into z from public.sale_reversals where id=p_id and owner_id=p_owner and actor_id=auth.uid() and actor_name is not null;if not found then raise exception 'staff_refund_unavailable';end if;
 select * into s from public.sales where id=z.sale_id and owner_id=p_owner and actor_id=auth.uid() and payment_mode='cash';if not found then raise exception 'staff_sale_unavailable';end if;
 return jsonb_build_object('scope','cashier-refund-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'sale',to_jsonb(s)-'owner_id'-'request_payload','refund',(to_jsonb(z)-'owner_id'-'request_payload')||jsonb_build_object('reversal_no',z.reversal_no::text));
end $$;
create function private.get_cashier_refund_workspace(p_owner uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;v_sales jsonb;v_refunds jsonb;begin
 r:=private.cashier_membership(p_owner);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.receipt_no::bigint desc),'[]'::jsonb) into v_sales from(select id,receipt_no::text,created_at,total::text,actor_id from public.sales where owner_id=p_owner and actor_id=auth.uid() and payment_mode='cash' order by receipt_no desc limit 20)x;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.reversal_no::bigint desc),'[]'::jsonb) into v_refunds from(select id,sale_id,reversal_no::text,created_at,total::text,actor_id,actor_name from public.sale_reversals where owner_id=p_owner and actor_id=auth.uid() and actor_name is not null order by reversal_no desc limit 20)x;
 return jsonb_build_object('scope','cashier-refund-workspace-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'can_refund',r.can_refund,'sales',v_sales,'refunds',v_refunds);
end $$;
create function private.post_cashier_refund(p_owner uuid,p_id uuid,p_sale uuid,p_reason text) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;z public.sale_reversals%rowtype;s public.sales%rowtype;result jsonb;begin
 if auth.uid() is null then raise exception 'staff_auth_required';end if;if p_owner is null or p_id is null or p_sale is null then raise exception 'staff_invalid_request';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||p_owner::text,0));r:=private.cashier_membership(p_owner);
 perform pg_advisory_xact_lock(hashtextextended('kashier.sale-reversal.'||p_id::text,0));
 select * into z from public.sale_reversals where id=p_id;
 if found and(z.owner_id<>p_owner or z.actor_id is distinct from auth.uid() or z.actor_name is null) then raise exception 'staff_request_conflict';end if;
 select * into s from public.sales where id=p_sale and owner_id=p_owner and actor_id=auth.uid();if not found then raise exception 'staff_sale_unavailable';end if;
 if s.payment_mode<>'cash' then raise exception 'staff_refund_cash_only';end if;
 if z.id is null and not r.can_refund then raise exception 'staff_refund_denied';end if;
 result:=private.post_sale_reversal_for_owner(p_owner,p_id,p_sale,p_reason);
 update public.sale_reversals set actor_name=r.member_name where id=p_id and actor_name is null;
 select * into z from public.sale_reversals where id=p_id;
 return jsonb_build_object('scope','cashier-refund-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'sale',to_jsonb(s)-'owner_id'-'request_payload','refund',(to_jsonb(z)-'owner_id'-'request_payload')||jsonb_build_object('reversal_no',z.reversal_no::text));
end $$;
create function public.get_cashier_refund_sale(p_owner uuid,p_sale uuid default null,p_number bigint default null) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_refund_sale(p_owner,p_sale,p_number);$$;
revoke all on function private.get_cashier_refund_sale(uuid,uuid,bigint),public.get_cashier_refund_sale(uuid,uuid,bigint) from public,anon,authenticated;
grant execute on function private.get_cashier_refund_sale(uuid,uuid,bigint),public.get_cashier_refund_sale(uuid,uuid,bigint) to authenticated;
create function public.get_cashier_refund(p_owner uuid,p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_refund(p_owner,p_id);$$;
revoke all on function private.get_cashier_refund(uuid,uuid),public.get_cashier_refund(uuid,uuid) from public,anon,authenticated;
grant execute on function private.get_cashier_refund(uuid,uuid),public.get_cashier_refund(uuid,uuid) to authenticated;
create function public.get_cashier_refund_workspace(p_owner uuid) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_refund_workspace(p_owner);$$;
revoke all on function private.get_cashier_refund_workspace(uuid),public.get_cashier_refund_workspace(uuid) from public,anon,authenticated;
grant execute on function private.get_cashier_refund_workspace(uuid),public.get_cashier_refund_workspace(uuid) to authenticated;
create function public.post_cashier_refund(p_owner uuid,p_id uuid,p_sale uuid,p_reason text) returns jsonb language sql security invoker set search_path='' as $$select private.post_cashier_refund(p_owner,p_id,p_sale,p_reason);$$;
revoke all on function private.post_cashier_refund(uuid,uuid,uuid,text),public.post_cashier_refund(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function private.post_cashier_refund(uuid,uuid,uuid,text),public.post_cashier_refund(uuid,uuid,uuid,text) to authenticated;
notify pgrst,'reload schema';
