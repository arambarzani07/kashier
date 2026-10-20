alter table public.store_cashiers add column can_partial_refund boolean not null default false;
alter table public.sale_returns add column actor_id uuid,add column actor_name text check(actor_name is null or char_length(btrim(actor_name)) between 1 and 100),add column staff_context jsonb check(staff_context is null or jsonb_typeof(staff_context)='object');
alter table public.sale_returns alter column actor_id set default auth.uid();
create index sale_returns_staff_documents_idx on public.sale_returns(owner_id,actor_id,return_no desc) where actor_name is not null;
drop function public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean,boolean);
drop function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean,boolean);
create function private.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint,p_role text default 'cashier',p_credit boolean default false,p_repay boolean default false,p_refund boolean default false,p_partial boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r public.store_cashiers%rowtype;e public.staff_actions%rowtype;payload jsonb;old jsonb;result jsonb;k text;begin
if u is null then raise exception 'staff_auth_required';end if;
if p_partial is null or p_refund is null or p_repay is null or p_credit is null or p_role is null or p_role not in ('cashier','manager') or p_id is null or p_member is null or p_member=u or p_discount is null or p_enabled is null or p_expected_version is null or p_expected_version<0 or char_length(btrim(coalesce(p_name,''))) not between 1 and 100 or char_length(btrim(coalesce(p_store,''))) not between 1 and 100 then raise exception 'staff_invalid_request';end if;
payload:=jsonb_build_object('kind','save','member',p_member,'name',btrim(p_name),'store',btrim(p_store),'discount',p_discount,'enabled',p_enabled,'expected_version',p_expected_version,'role',p_role,'credit',p_credit,'repay',p_repay,'refund',p_refund,'partial',p_partial);
perform pg_advisory_xact_lock(hashtextextended('kashier.staff-action.'||p_id::text,0));select * into e from public.staff_actions where id=p_id;
if found then if e.actor_id<>u or e.owner_id<>u or (e.request_payload||jsonb_build_object('role',coalesce(e.request_payload->>'role','cashier'),'credit',coalesce((e.request_payload->>'credit')::boolean,false),'repay',coalesce((e.request_payload->>'repay')::boolean,false),'refund',coalesce((e.request_payload->>'refund')::boolean,false),'partial',coalesce((e.request_payload->>'partial')::boolean,false)))<>payload then raise exception 'staff_request_conflict';end if;return e.result_payload;end if;
perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||u::text,0));
select * into r from public.store_cashiers where owner_id=u and member_id=p_member for update;old:=case when found then to_jsonb(r) else null end;
if old is null then
if p_expected_version<>0 then raise exception 'staff_changed';end if;
if not exists(select 1 from auth.users where id=p_member) then raise exception 'staff_member_unavailable';end if;
perform pg_advisory_xact_lock(hashtextextended('kashier.staff-member.'||p_member::text,0));
if (select count(*) from public.store_cashiers where owner_id=u)>=50 or(select count(*) from public.store_cashiers where member_id=p_member)>=50 then raise exception 'staff_limit';end if;
insert into public.store_cashiers(owner_id,member_id,member_name,store_name,can_discount,enabled,role,can_credit,can_repay,can_refund,can_partial_refund) values(u,p_member,btrim(p_name),btrim(p_store),p_discount,p_enabled,p_role,p_credit,p_repay,p_refund,p_partial) returning * into r;k:='invite';
else
if r.version<>p_expected_version then raise exception 'staff_changed';end if;
update public.store_cashiers set can_partial_refund=p_partial,can_refund=p_refund,can_repay=p_repay,can_credit=p_credit,role=p_role,member_name=btrim(p_name),store_name=btrim(p_store),can_discount=p_discount,enabled=p_enabled,version=version+1,updated_at=now() where id=r.id returning * into r;k:='update';
end if;
result:=jsonb_build_object('id',p_id,'membership_id',r.id,'version',r.version::text);
insert into public.staff_actions(id,owner_id,member_id,actor_id,membership_id,kind,before_state,after_state,request_payload,result_payload) values(p_id,u,p_member,u,r.id,k,old,to_jsonb(r),payload,result);return result;
end $$;
create function public.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint,p_role text default 'cashier',p_credit boolean default false,p_repay boolean default false,p_refund boolean default false,p_partial boolean default false) returns jsonb language sql security invoker set search_path='' as $$select private.save_store_cashier(p_id,p_member,p_name,p_store,p_discount,p_enabled,p_expected_version,p_role,p_credit,p_repay,p_refund,p_partial);$$;
revoke all on function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean,boolean,boolean),public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean,boolean,boolean),public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean,boolean,boolean) to authenticated;
create or replace function private.post_sale_return_for_owner(p_owner uuid,p_id uuid,p_sale uuid,p_reason text,p_lines jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
v_user uuid:=p_owner;
v_payload jsonb;
v_return public.sale_returns%rowtype;
v_sale public.sales%rowtype;
v_request jsonb;
v_original jsonb;
v_return_lines jsonb:='[]'::jsonb;
v_seen integer[]:='{}';
v_line_no integer;
v_qty bigint;
v_prev_qty bigint;
v_original_qty bigint;
v_price bigint;
v_line_refund bigint;
v_total bigint:=0;
v_product uuid;
v_stock record;
v_after bigint;
v_cash_after bigint;
v_line_gross bigint;
v_cumulative_gross numeric;
v_line_discount bigint;
v_line_net bigint;
begin
if v_user is null or auth.uid() is null then raise exception using errcode='28000',message='return_auth_required'; end if;
if p_id is null or p_sale is null or p_lines is null or jsonb_typeof(p_lines)<>'array' then raise exception 'return_invalid_request'; end if;
if jsonb_array_length(p_lines) not between 1 and 200 then raise exception 'return_invalid_items'; end if;
if char_length(btrim(coalesce(p_reason,''))) not between 1 and 500 then raise exception 'return_reason_required'; end if;
v_payload:=jsonb_build_object('sale_id',p_sale,'reason',btrim(p_reason),'lines',p_lines);
perform pg_advisory_xact_lock(hashtextextended('kashier.sale-return.'||p_id::text,0));
select * into v_return from public.sale_returns where id=p_id;
if found then
if v_return.owner_id<>v_user or v_return.request_payload<>v_payload then raise exception 'return_request_conflict'; end if;
return to_jsonb(v_return)-'owner_id'-'request_payload';
end if;
perform pg_advisory_xact_lock(hashtextextended('kashier.sale-adjustment.'||p_sale::text,0));
select * into v_sale from public.sales where id=p_sale and owner_id=v_user for share;
if not found then raise exception 'return_sale_unavailable'; end if;
if exists(select 1 from public.sale_reversals where sale_id=p_sale) then raise exception 'return_sale_reversed'; end if;
if v_sale.payment_mode<>'cash' then raise exception 'return_credit_not_supported'; end if;
for v_request in select value from jsonb_array_elements(p_lines) loop
if jsonb_typeof(v_request)<>'object' or coalesce(v_request->>'line_no','') !~ '^[0-9]{1,3}$' or coalesce(v_request->>'quantity_units','') !~ '^[0-9]{1,8}$' then raise exception 'return_invalid_items'; end if;
v_line_no:=(v_request->>'line_no')::integer;
v_qty:=(v_request->>'quantity_units')::bigint;
if v_line_no not between 1 and jsonb_array_length(v_sale.lines) or v_qty not between 1 and 10000000 then raise exception 'return_invalid_items'; end if;
if v_line_no=any(v_seen) then raise exception 'return_duplicate_line'; end if;
v_seen:=array_append(v_seen,v_line_no);
v_original:=v_sale.lines->(v_line_no-1);
v_original_qty:=(v_original->>'quantity_units')::bigint;
v_price:=(v_original->>'unit_price')::bigint;
v_product:=(v_original->>'product_id')::uuid;
v_line_gross:=(v_original->>'line_total')::bigint;
select coalesce(sum((e.value->>'line_total')::numeric),0) into v_cumulative_gross
from jsonb_array_elements(v_sale.lines) with ordinality e(value,ordinality)
where e.ordinality<=v_line_no;
if v_sale.discount=0 then
v_line_discount:=0;
v_line_net:=v_line_gross;
else
if v_sale.subtotal<=0 then raise exception 'return_invalid_money'; end if;
v_line_discount:=(div(v_sale.discount::numeric*v_cumulative_gross,v_sale.subtotal::numeric)-div(v_sale.discount::numeric*(v_cumulative_gross-v_line_gross::numeric),v_sale.subtotal::numeric))::bigint;
v_line_net:=v_line_gross-v_line_discount;
if v_line_discount<0 or v_line_net<0 then raise exception 'return_invalid_money'; end if;
end if;
select coalesce(sum((rl->>'quantity_units')::bigint),0) into v_prev_qty
from public.sale_returns sr cross join lateral jsonb_array_elements(sr.lines) rl
where sr.sale_id=p_sale and sr.owner_id=v_user and (rl->>'line_no')::integer=v_line_no;
if v_prev_qty+v_qty>v_original_qty then raise exception 'return_quantity_exceeds_remaining'; end if;
if v_sale.discount=0 then
v_line_refund:=(((v_prev_qty+v_qty)*v_price+500)/1000)-((v_prev_qty*v_price+500)/1000);
else
v_line_refund:=(div(v_line_net::numeric*(v_prev_qty+v_qty),v_original_qty::numeric)-div(v_line_net::numeric*v_prev_qty,v_original_qty::numeric))::bigint;
end if;
if v_line_refund<0 then raise exception 'return_invalid_money'; end if;
v_total:=v_total+v_line_refund;
if v_total>100000000000000 then raise exception 'return_total_limit'; end if;
v_return_lines:=v_return_lines||jsonb_build_array(jsonb_build_object(
'line_no',v_line_no,'product_id',v_product,'name',v_original->>'name','barcode',v_original->'barcode',
'quantity_units',v_qty,'original_quantity_units',v_original_qty,'unit_price',v_price,'line_total',v_line_refund,
'original_line_total',v_line_gross,'allocated_discount',v_line_discount,'net_line_total',v_line_net));
end loop;
perform pg_advisory_xact_lock(hashtextextended('kashier.inventory.'||v_user::text,0));
for v_stock in
select (x->>'product_id')::uuid as product_id,sum((x->>'quantity_units')::bigint) as returned
from jsonb_array_elements(v_return_lines) x group by (x->>'product_id')::uuid
loop
select quantity_units into v_after from public.product_stock where product_id=v_stock.product_id and owner_id=v_user for update;
if not found then raise exception 'return_stock_unavailable'; end if;
if v_after>1000000000000-v_stock.returned then raise exception 'return_stock_limit'; end if;
end loop;
if v_total>0 then
perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||v_user::text,0));
select balance-v_total into v_cash_after from public.cash_accounts where owner_id=v_user for update;
if not found or v_cash_after<0 then raise exception 'return_cash_insufficient'; end if;
end if;
insert into public.sale_returns(id,owner_id,sale_id,reason,total,cash_refund,debt_reversed,lines,request_payload)
values(p_id,v_user,p_sale,btrim(p_reason),v_total,v_total,0,v_return_lines,v_payload)
returning * into v_return;
for v_original in select value from jsonb_array_elements(v_return_lines) loop
v_qty:=(v_original->>'quantity_units')::bigint;
v_line_no:=(v_original->>'line_no')::integer;
update public.product_stock set quantity_units=quantity_units+v_qty,updated_at=now()
where product_id=(v_original->>'product_id')::uuid and owner_id=v_user returning quantity_units into v_after;
if not found then raise exception 'return_stock_unavailable'; end if;
insert into public.stock_movements(owner_id,product_id,return_id,line_no,delta_units,balance_after)
values(v_user,(v_original->>'product_id')::uuid,p_id,v_line_no,v_qty,v_after);
end loop;
if v_total>0 then
update public.cash_accounts set balance=v_cash_after,updated_at=now() where owner_id=v_user;
insert into public.cash_movements(owner_id,kind,amount,delta,balance_after,sale_id,note,request_payload,customer_id,reversal_id,return_id)
values(v_user,'refund',v_total,-v_total,v_cash_after,null,btrim(p_reason),jsonb_build_object('return_id',p_id,'sale_id',p_sale),null,null,p_id);
end if;
return to_jsonb(v_return)-'owner_id'-'request_payload';
end $$;
revoke all on function private.post_sale_return_for_owner(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
create or replace function private.post_sale_return(p_id uuid,p_sale uuid,p_reason text,p_lines jsonb) returns jsonb language sql security definer set search_path='' as $$select private.post_sale_return_for_owner(auth.uid(),p_id,p_sale,p_reason,p_lines);$$;
create function private.get_cashier_partial_source(p_owner uuid,p_sale uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;s public.sales%rowtype;states jsonb;cnt bigint;full_id uuid;begin
r:=private.cashier_membership(p_owner);select * into s from public.sales where id=p_sale and owner_id=p_owner and actor_id=auth.uid();if not found then raise exception 'staff_sale_unavailable';end if;if s.payment_mode<>'cash' then raise exception 'staff_refund_cash_only';end if;
with returned as(select (l->>'line_no')::integer line_no,sum((l->>'quantity_units')::bigint) units,sum((l->>'line_total')::bigint) amount from public.sale_returns t cross join lateral jsonb_array_elements(t.lines) l where t.owner_id=p_owner and t.sale_id=p_sale group by (l->>'line_no')::integer)
select jsonb_agg(jsonb_build_object('line_no',n,'returned_units',coalesce(t.units,0)::text,'refunded',coalesce(t.amount,0)::text) order by n) into states from jsonb_array_elements(s.lines) with ordinality a(line,n) left join returned t on t.line_no=n;
select count(*) into cnt from public.sale_returns where owner_id=p_owner and sale_id=p_sale;
select id into full_id from public.sale_reversals where owner_id=p_owner and sale_id=p_sale;
return jsonb_build_object('scope','cashier-partial-source-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'sale',(to_jsonb(s)-'owner_id'-'request_payload')||jsonb_build_object('receipt_no',s.receipt_no::text),'can_partial_refund',r.can_partial_refund,'full_refund_id',full_id,'context',jsonb_build_object('count',cnt::text,'states',states));
end $$;
create function private.get_cashier_partial_return(p_owner uuid,p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;s public.sales%rowtype;z public.sale_returns%rowtype;begin
r:=private.cashier_membership(p_owner);select * into z from public.sale_returns where id=p_id and owner_id=p_owner and actor_id=auth.uid() and actor_name is not null;if not found then raise exception 'staff_partial_unavailable';end if;
select * into s from public.sales where id=z.sale_id and owner_id=p_owner and actor_id=auth.uid() and payment_mode='cash';if not found then raise exception 'staff_sale_unavailable';end if;
return jsonb_build_object('scope','cashier-partial-return-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'sale',(to_jsonb(s)-'owner_id'-'request_payload')||jsonb_build_object('receipt_no',s.receipt_no::text),'returned',(to_jsonb(z)-'owner_id'-'request_payload')||jsonb_build_object('return_no',z.return_no::text));
end $$;
create function private.get_cashier_partial_workspace(p_owner uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;sales jsonb;documents jsonb;begin
r:=private.cashier_membership(p_owner);
select coalesce(jsonb_agg(to_jsonb(x) order by x.receipt_no::bigint desc),'[]'::jsonb) into sales from(select id,receipt_no::text,created_at,total::text,actor_id from public.sales where owner_id=p_owner and actor_id=auth.uid() and payment_mode='cash' order by public.sales.receipt_no desc limit 20)x;
select coalesce(jsonb_agg(to_jsonb(x) order by x.return_no::bigint desc),'[]'::jsonb) into documents from(select id,sale_id,return_no::text,created_at,total::text,actor_id,actor_name from public.sale_returns where owner_id=p_owner and actor_id=auth.uid() and actor_name is not null order by public.sale_returns.return_no desc limit 20)x;
return jsonb_build_object('scope','cashier-partial-workspace-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'can_partial_refund',r.can_partial_refund,'sales',sales,'documents',documents);
end $$;
create function private.post_cashier_partial_return(p_owner uuid,p_id uuid,p_sale uuid,p_reason text,p_lines jsonb,p_expected_count bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;s public.sales%rowtype;z public.sale_returns%rowtype;states jsonb;cnt bigint;result jsonb;before_state jsonb;begin
if auth.uid() is null then raise exception 'staff_auth_required';end if;if p_owner is null or p_id is null or p_sale is null or p_expected_count is null or p_expected_count<0 then raise exception 'staff_invalid_request';end if;
perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||p_owner::text,0));r:=private.cashier_membership(p_owner);
perform pg_advisory_xact_lock(hashtextextended('kashier.sale-return.'||p_id::text,0));select * into z from public.sale_returns where id=p_id;
if found and(z.owner_id<>p_owner or z.actor_id is distinct from auth.uid() or z.actor_name is null or z.staff_context->>'count' is distinct from p_expected_count::text) then raise exception 'staff_request_conflict';end if;
select * into s from public.sales where id=p_sale and owner_id=p_owner and actor_id=auth.uid();if not found then raise exception 'staff_sale_unavailable';end if;if s.payment_mode<>'cash' then raise exception 'staff_refund_cash_only';end if;
if z.id is null then
if not r.can_partial_refund then raise exception 'staff_partial_denied';end if;
perform pg_advisory_xact_lock(hashtextextended('kashier.sale-adjustment.'||p_sale::text,0));
with returned as(select (l->>'line_no')::integer line_no,sum((l->>'quantity_units')::bigint) units,sum((l->>'line_total')::bigint) amount from public.sale_returns t cross join lateral jsonb_array_elements(t.lines) l where t.owner_id=p_owner and t.sale_id=p_sale group by (l->>'line_no')::integer)
select jsonb_agg(jsonb_build_object('line_no',n,'returned_units',coalesce(t.units,0)::text,'refunded',coalesce(t.amount,0)::text) order by n) into states from jsonb_array_elements(s.lines) with ordinality a(line,n) left join returned t on t.line_no=n;
select count(*) into cnt from public.sale_returns where owner_id=p_owner and sale_id=p_sale;
if cnt<>p_expected_count then raise exception 'staff_return_changed';end if;
before_state:=jsonb_build_object('count',cnt::text,'states',states);
end if;
result:=private.post_sale_return_for_owner(p_owner,p_id,p_sale,p_reason,p_lines);
if z.id is null then update public.sale_returns set actor_name=r.member_name,staff_context=before_state where id=p_id;end if;
select * into z from public.sale_returns where id=p_id;return jsonb_build_object('scope','cashier-partial-return-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'sale',(to_jsonb(s)-'owner_id'-'request_payload')||jsonb_build_object('receipt_no',s.receipt_no::text),'returned',(to_jsonb(z)-'owner_id'-'request_payload')||jsonb_build_object('return_no',z.return_no::text));
end $$;
create function public.get_cashier_partial_source(p_owner uuid,p_sale uuid) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_partial_source(p_owner,p_sale);$$;
revoke all on function private.get_cashier_partial_source(uuid,uuid),public.get_cashier_partial_source(uuid,uuid) from public,anon,authenticated;
grant execute on function private.get_cashier_partial_source(uuid,uuid),public.get_cashier_partial_source(uuid,uuid) to authenticated;
create function public.get_cashier_partial_return(p_owner uuid,p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_partial_return(p_owner,p_id);$$;
revoke all on function private.get_cashier_partial_return(uuid,uuid),public.get_cashier_partial_return(uuid,uuid) from public,anon,authenticated;
grant execute on function private.get_cashier_partial_return(uuid,uuid),public.get_cashier_partial_return(uuid,uuid) to authenticated;
create function public.get_cashier_partial_workspace(p_owner uuid) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_partial_workspace(p_owner);$$;
revoke all on function private.get_cashier_partial_workspace(uuid),public.get_cashier_partial_workspace(uuid) from public,anon,authenticated;
grant execute on function private.get_cashier_partial_workspace(uuid),public.get_cashier_partial_workspace(uuid) to authenticated;
create function public.post_cashier_partial_return(p_owner uuid,p_id uuid,p_sale uuid,p_reason text,p_lines jsonb,p_expected_count bigint) returns jsonb language sql security invoker set search_path='' as $$select private.post_cashier_partial_return(p_owner,p_id,p_sale,p_reason,p_lines,p_expected_count);$$;
revoke all on function private.post_cashier_partial_return(uuid,uuid,uuid,text,jsonb,bigint),public.post_cashier_partial_return(uuid,uuid,uuid,text,jsonb,bigint) from public,anon,authenticated;
grant execute on function private.post_cashier_partial_return(uuid,uuid,uuid,text,jsonb,bigint),public.post_cashier_partial_return(uuid,uuid,uuid,text,jsonb,bigint) to authenticated;
notify pgrst,'reload schema';

