-- Access X owner administration matrix, transaction-only. Requires database-admin SQL connection.
-- All synthetic auth users, membership rows and audit rows are rolled back.
begin;
select set_config('ax2.owner',gen_random_uuid()::text,true),set_config('ax2.cashier',gen_random_uuid()::text,true),
       set_config('ax2.manager',gen_random_uuid()::text,true),set_config('ax2.other',gen_random_uuid()::text,true),
       set_config('ax2.create_req',gen_random_uuid()::text,true);
insert into auth.users(id,email) values
(current_setting('ax2.owner')::uuid,'ax2-owner@example.invalid'),
(current_setting('ax2.cashier')::uuid,'ax2-cashier@example.invalid'),
(current_setting('ax2.manager')::uuid,'ax2-manager@example.invalid'),
(current_setting('ax2.other')::uuid,'ax2-outsider@example.invalid');
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('ax2.owner'),'role','authenticated')::text,true);
set local role authenticated;
do $$
declare x jsonb;y jsonb;
begin
 x:=public.save_store_cashier(current_setting('ax2.create_req')::uuid,current_setting('ax2.cashier')::uuid,'Cashier','Market',false,true,0,'cashier',false,false,false,false);
 y:=public.save_store_cashier(current_setting('ax2.create_req')::uuid,current_setting('ax2.cashier')::uuid,'Cashier','Market',false,true,0,'cashier',false,false,false,false);
 if x<>y then raise exception 'staff idempotency failure';end if;
 perform set_config('ax2.cashier_membership',x->>'membership_id',true);
 begin
  perform public.save_store_cashier(current_setting('ax2.create_req')::uuid,current_setting('ax2.cashier')::uuid,'Changed Name','Market',false,true,0,'cashier',false,false,false,false);
  raise exception 'staff payload conflict accepted';
 exception when raise_exception then if sqlerrm<>'staff_request_conflict' then raise;end if;end;
 begin
  perform public.save_store_cashier(gen_random_uuid(),current_setting('ax2.cashier')::uuid,'Cashier','Market',false,true,0,'cashier',false,false,false,false);
  raise exception 'stale staff update accepted';
 exception when raise_exception then if sqlerrm<>'staff_changed' then raise;end if;end;
 y:=public.save_store_cashier(gen_random_uuid(),current_setting('ax2.manager')::uuid,'Other Manager','Market',false,true,0,'manager',false,false,false,false);
 perform set_config('ax2.manager_membership',y->>'membership_id',true);
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('ax2.cashier'),'role','authenticated')::text,true);
set local role authenticated;
select public.accept_store_cashier(gen_random_uuid(),current_setting('ax2.cashier_membership')::uuid);
do $$
declare x jsonb;
begin
 begin
  x:=public.save_store_cashier(gen_random_uuid(),current_setting('ax2.other')::uuid,'Outsider','Market',false,true,1,'manager',true,true,true,true);
  raise exception 'cashier altered owner membership: %',x;
 exception when raise_exception then if sqlerrm not in ('staff_changed','staff_access_denied') then raise;end if;end;
 if exists(select 1 from public.store_cashiers where owner_id=current_setting('ax2.owner')::uuid and member_id=current_setting('ax2.other')::uuid) then raise exception 'cashier injected owner membership';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('ax2.manager'),'role','authenticated')::text,true);
set local role authenticated;
select public.accept_store_cashier(gen_random_uuid(),current_setting('ax2.manager_membership')::uuid);
do $$
begin
 if exists(select 1 from public.store_cashiers where owner_id=current_setting('ax2.owner')::uuid and member_id=current_setting('ax2.manager')::uuid and role<>'manager') then raise exception 'manager role mutated';end if;
 begin
  perform public.save_store_cashier(gen_random_uuid(),current_setting('ax2.cashier')::uuid,'Changed Cashier','Market',false,false,1,'cashier',false,false,false,false);
  raise exception 'delegated manager changed owner membership';
 exception when raise_exception then if sqlerrm<>'staff_changed' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('ax2.owner'),'role','authenticated')::text,true);
set local role authenticated;
do $$
declare x jsonb;
begin
 if (select count(*) from public.store_cashiers where owner_id=current_setting('ax2.owner')::uuid)<>2 then raise exception 'owner staff corrupted';end if;
 x:=public.save_store_cashier(gen_random_uuid(),current_setting('ax2.cashier')::uuid,'Cashier','Market',false,false,2,'cashier',false,false,false,false);
 if x->>'version'<>'3' then raise exception 'cashier disable mismatch';end if;
end $$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('ax2.cashier'),'role','authenticated')::text,true);
set local role authenticated;
do $$
begin
 begin perform public.get_cashier_catalog(current_setting('ax2.owner')::uuid,'',0);raise exception 'disabled access accepted';
 exception when raise_exception then if sqlerrm<>'staff_access_denied' then raise;end if;end;
end $$;
reset role;
select 'PASS: owner staff create idempotent; request/version conflicts; cashier and manager cannot change owner staff; disable revokes catalog' as access_x_admin_test;
rollback;
