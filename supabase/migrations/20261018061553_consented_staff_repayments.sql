alter table public.store_cashiers add column can_repay boolean not null default false;
-- No guessed attribution for historical debt entries. Future owner/credit entries keep the real JWT actor.
alter table public.debt_entries add column actor_id uuid,add column actor_name text check(actor_name is null or char_length(btrim(actor_name)) between 1 and 100);
alter table public.debt_entries alter column actor_id set default auth.uid();
create index debt_entries_staff_receipts_idx on public.debt_entries(owner_id,actor_id,movement_no desc) where kind='repayment' and actor_name is not null;
drop function public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean);
drop function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean);
create function private.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint,p_role text default 'cashier',p_credit boolean default false,p_repay boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r public.store_cashiers%rowtype;e public.staff_actions%rowtype;payload jsonb;old jsonb;result jsonb;k text;begin
 if u is null then raise exception 'staff_auth_required';end if;
 if p_repay is null or p_credit is null or p_role is null or p_role not in ('cashier','manager') or p_id is null or p_member is null or p_member=u or p_discount is null or p_enabled is null or p_expected_version is null or p_expected_version<0 or char_length(btrim(coalesce(p_name,''))) not between 1 and 100 or char_length(btrim(coalesce(p_store,''))) not between 1 and 100 then raise exception 'staff_invalid_request';end if;
 payload:=jsonb_build_object('kind','save','member',p_member,'name',btrim(p_name),'store',btrim(p_store),'discount',p_discount,'enabled',p_enabled,'expected_version',p_expected_version,'role',p_role,'credit',p_credit,'repay',p_repay);
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff-action.'||p_id::text,0));select * into e from public.staff_actions where id=p_id;
 if found then if e.actor_id<>u or e.owner_id<>u or (e.request_payload||jsonb_build_object('role',coalesce(e.request_payload->>'role','cashier'),'credit',coalesce((e.request_payload->>'credit')::boolean,false),'repay',coalesce((e.request_payload->>'repay')::boolean,false)))<>payload then raise exception 'staff_request_conflict';end if;return e.result_payload;end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||u::text,0));
 select * into r from public.store_cashiers where owner_id=u and member_id=p_member for update;old:=case when found then to_jsonb(r) else null end;
 if old is null then
  if p_expected_version<>0 then raise exception 'staff_changed';end if;
  if not exists(select 1 from auth.users where id=p_member) then raise exception 'staff_member_unavailable';end if;
  perform pg_advisory_xact_lock(hashtextextended('kashier.staff-member.'||p_member::text,0));
  if (select count(*) from public.store_cashiers where owner_id=u)>=50 or(select count(*) from public.store_cashiers where member_id=p_member)>=50 then raise exception 'staff_limit';end if;
  insert into public.store_cashiers(owner_id,member_id,member_name,store_name,can_discount,enabled,role,can_credit,can_repay) values(u,p_member,btrim(p_name),btrim(p_store),p_discount,p_enabled,p_role,p_credit,p_repay) returning * into r;k:='invite';
 else
  if r.version<>p_expected_version then raise exception 'staff_changed';end if;
  update public.store_cashiers set can_repay=p_repay,can_credit=p_credit,role=p_role,member_name=btrim(p_name),store_name=btrim(p_store),can_discount=p_discount,enabled=p_enabled,version=version+1,updated_at=now() where id=r.id returning * into r;k:='update';
 end if;
 result:=jsonb_build_object('id',p_id,'membership_id',r.id,'version',r.version::text);
 insert into public.staff_actions(id,owner_id,member_id,actor_id,membership_id,kind,before_state,after_state,request_payload,result_payload) values(p_id,u,p_member,u,r.id,k,old,to_jsonb(r),payload,result);return result;
end $$;
create function public.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint,p_role text default 'cashier',p_credit boolean default false,p_repay boolean default false) returns jsonb language sql security invoker set search_path='' as $$select private.save_store_cashier(p_id,p_member,p_name,p_store,p_discount,p_enabled,p_expected_version,p_role,p_credit,p_repay);$$;
revoke all on function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean),public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean) from public,anon,authenticated;
grant execute on function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean),public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text,boolean,boolean) to authenticated;
create or replace function private.get_cashier_customers(p_owner uuid,p_query text default '',p_offset integer default 0) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;q text:=btrim(coalesce(p_query,''));rows jsonb;total bigint;begin
 r:=private.cashier_membership(p_owner);if not r.can_credit and not r.can_repay then raise exception 'staff_credit_denied';end if;
 if p_offset is null or p_offset not between 0 and 1000000 or char_length(q)>100 then raise exception 'staff_invalid_request';end if;
 select count(*) into total from public.customers c where c.owner_id=p_owner and(q='' or strpos(lower(c.name),lower(q))>0 or strpos(coalesce(c.phone,''),q)>0 or c.id::text=q);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.name,x.id),'[]'::jsonb) into rows from(select c.id,c.name,c.phone from public.customers c where c.owner_id=p_owner and(q='' or strpos(lower(c.name),lower(q))>0 or strpos(coalesce(c.phone,''),q)>0 or c.id::text=q) order by c.name,c.id limit 50 offset p_offset)x;
 return jsonb_build_object('scope','cashier-customers-v1','owner_id',p_owner,'actor_id',auth.uid(),'query',q,'offset',p_offset,'total',total::text,'rows',rows);end $$;

create function private.get_cashier_customer_balance(p_owner uuid,p_customer uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;c public.customers%rowtype;b bigint;begin
 r:=private.cashier_membership(p_owner);if not r.can_repay then raise exception 'staff_repay_denied';end if;
 select * into c from public.customers where owner_id=p_owner and id=p_customer;if not found then raise exception 'debt_customer_unavailable';end if;
 select coalesce((select balance from public.customer_balances where owner_id=p_owner and customer_id=p_customer),0) into b;
 return jsonb_build_object('scope','cashier-customer-balance-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'customer',jsonb_build_object('id',c.id,'name',c.name,'phone',c.phone),'balance',b::text,'generated_at',statement_timestamp(),'currency','IQD');
end $$;
create function private.get_cashier_repayment(p_owner uuid,p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;e public.debt_entries%rowtype;begin
 r:=private.cashier_membership(p_owner);
 select * into e from public.debt_entries where id=p_id and owner_id=p_owner and actor_id=auth.uid() and kind='repayment' and actor_name is not null;
 if not found then raise exception 'staff_repayment_unavailable';end if;
 return jsonb_build_object('scope','cashier-repayment-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'entry',(to_jsonb(e)-'owner_id'-'request_payload')||jsonb_build_object('movement_no',e.movement_no::text,'amount',e.amount::text,'delta',e.delta::text,'balance_after',e.balance_after::text,'balance_before',(e.balance_after+e.amount)::text));
end $$;
create function private.list_cashier_repayments(p_owner uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;rows jsonb;begin
 r:=private.cashier_membership(p_owner);select coalesce(jsonb_agg(to_jsonb(x) order by x.movement_no::bigint desc),'[]'::jsonb) into rows from(select id,movement_no::text,created_at,amount::text,customer_name,actor_id,actor_name from public.debt_entries where owner_id=p_owner and actor_id=auth.uid() and kind='repayment' and actor_name is not null order by movement_no desc limit 20)x;
 return jsonb_build_object('scope','cashier-repayments-v1','owner_id',p_owner,'actor_id',auth.uid(),'rows',rows);
end $$;
create function private.post_cashier_repayment(p_owner uuid,p_id uuid,p_customer uuid,p_amount bigint,p_note text,p_expected_balance bigint) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;e public.debt_entries%rowtype;c public.customers%rowtype;payload jsonb;b bigint;cash_before bigint;cash_after bigint;cash_id uuid;begin
 if auth.uid() is null then raise exception 'staff_auth_required';end if;
 if p_owner is null or p_id is null or p_customer is null or p_expected_balance is null or p_expected_balance not between 0 and 100000000000000 then raise exception 'staff_invalid_request';end if;
 if p_amount is null or p_amount not between 1 and 100000000000000 then raise exception 'debt_invalid_amount';end if;
 if char_length(btrim(coalesce(p_note,''))) not between 1 and 500 then raise exception 'debt_note_required';end if;
 payload:=jsonb_build_object('customer_id',p_customer,'kind','repayment','amount',p_amount,'note',btrim(p_note),'staff_expected_balance',p_expected_balance);
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||p_owner::text,0));r:=private.cashier_membership(p_owner);
 perform pg_advisory_xact_lock(hashtextextended('kashier.debt-entry.'||p_id::text,0));select * into e from public.debt_entries where id=p_id;
 if found then
  if e.owner_id<>p_owner or e.actor_id is distinct from auth.uid() or e.actor_name is null or e.kind<>'repayment' or e.request_payload<>payload then raise exception 'staff_request_conflict';end if;
  return private.get_cashier_repayment(p_owner,p_id);
 end if;
 if not r.can_repay then raise exception 'staff_repay_denied';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.debt.'||p_owner::text,0));
 select * into c from public.customers where id=p_customer and owner_id=p_owner for share;if not found then raise exception 'debt_customer_unavailable';end if;
 insert into public.customer_balances(customer_id,owner_id,balance) values(p_customer,p_owner,0) on conflict(customer_id) do nothing;
 select balance into b from public.customer_balances where owner_id=p_owner and customer_id=p_customer for update;
 if b<>p_expected_balance then raise exception 'staff_balance_changed';end if;
 if p_amount>b then raise exception 'debt_overpayment';end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.cash.'||p_owner::text,0));
 insert into public.cash_accounts(owner_id,balance) values(p_owner,0) on conflict(owner_id) do nothing;
 select balance into cash_before from public.cash_accounts where owner_id=p_owner for update;cash_after:=cash_before+p_amount;
 if cash_after>100000000000000 then raise exception 'cash_balance_limit';end if;
 cash_id:=gen_random_uuid();
 insert into public.cash_movements(id,owner_id,kind,amount,delta,balance_after,note,customer_id,request_payload) values(cash_id,p_owner,'repayment',p_amount,p_amount,cash_after,btrim(p_note),p_customer,jsonb_build_object('debt_entry_id',p_id));
 update public.cash_accounts set balance=cash_after,updated_at=now() where owner_id=p_owner;
 update public.customer_balances set balance=b-p_amount,updated_at=now() where owner_id=p_owner and customer_id=p_customer;
 insert into public.debt_entries(id,owner_id,customer_id,customer_name,kind,amount,delta,balance_after,note,cash_movement_id,request_payload,actor_id,actor_name) values(p_id,p_owner,p_customer,c.name,'repayment',p_amount,-p_amount,b-p_amount,btrim(p_note),cash_id,payload,auth.uid(),r.member_name) returning * into e;
 return jsonb_build_object('scope','cashier-repayment-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'entry',(to_jsonb(e)-'owner_id'-'request_payload')||jsonb_build_object('movement_no',e.movement_no::text,'amount',e.amount::text,'delta',e.delta::text,'balance_after',e.balance_after::text,'balance_before',(e.balance_after+e.amount)::text));
end $$;
create function public.get_cashier_customer_balance(p_owner uuid,p_customer uuid) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_customer_balance(p_owner,p_customer);$$;
revoke all on function private.get_cashier_customer_balance(uuid,uuid),public.get_cashier_customer_balance(uuid,uuid) from public,anon,authenticated;
grant execute on function private.get_cashier_customer_balance(uuid,uuid),public.get_cashier_customer_balance(uuid,uuid) to authenticated;
create function public.get_cashier_repayment(p_owner uuid,p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_repayment(p_owner,p_id);$$;
revoke all on function private.get_cashier_repayment(uuid,uuid),public.get_cashier_repayment(uuid,uuid) from public,anon,authenticated;
grant execute on function private.get_cashier_repayment(uuid,uuid),public.get_cashier_repayment(uuid,uuid) to authenticated;
create function public.list_cashier_repayments(p_owner uuid) returns jsonb language sql security invoker set search_path='' as $$select private.list_cashier_repayments(p_owner);$$;
revoke all on function private.list_cashier_repayments(uuid),public.list_cashier_repayments(uuid) from public,anon,authenticated;
grant execute on function private.list_cashier_repayments(uuid),public.list_cashier_repayments(uuid) to authenticated;
create function public.post_cashier_repayment(p_owner uuid,p_id uuid,p_customer uuid,p_amount bigint,p_note text,p_expected_balance bigint) returns jsonb language sql security invoker set search_path='' as $$select private.post_cashier_repayment(p_owner,p_id,p_customer,p_amount,p_note,p_expected_balance);$$;
revoke all on function private.post_cashier_repayment(uuid,uuid,uuid,bigint,text,bigint),public.post_cashier_repayment(uuid,uuid,uuid,bigint,text,bigint) from public,anon,authenticated;
grant execute on function private.post_cashier_repayment(uuid,uuid,uuid,bigint,text,bigint),public.post_cashier_repayment(uuid,uuid,uuid,bigint,text,bigint) to authenticated;
notify pgrst,'reload schema';
