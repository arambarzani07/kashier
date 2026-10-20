-- Kashêr Access X: manager vs cashier scope, RLS and immediate downgrade.
-- Administrative test connection only. All users and role actions are ROLLED BACK.
begin;
select set_config('accessx.owner',gen_random_uuid()::text,true),set_config('accessx.cashier',gen_random_uuid()::text,true),set_config('accessx.manager',gen_random_uuid()::text,true),set_config('accessx.other',gen_random_uuid()::text,true);
insert into auth.users(id,email) values
(current_setting('accessx.owner')::uuid,'access-x-roles-owner@example.invalid'),
(current_setting('accessx.cashier')::uuid,'access-x-roles-cashier@example.invalid'),
(current_setting('accessx.manager')::uuid,'access-x-roles-manager@example.invalid'),
(current_setting('accessx.other')::uuid,'access-x-roles-other@example.invalid');
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('accessx.owner'),'role','authenticated')::text,true);
set local role authenticated;
do $test$
declare m jsonb;c jsonb;
begin
 m:=public.save_store_cashier(gen_random_uuid(),current_setting('accessx.manager')::uuid,'Access X Manager','Access X Market',false,true,0,'manager',false,false,false,false);
 c:=public.save_store_cashier(gen_random_uuid(),current_setting('accessx.cashier')::uuid,'Access X Cashier','Access X Market',false,true,0,'cashier',false,false,false,false);
 perform set_config('accessx.manager_membership',m->>'membership_id',true);
 perform set_config('accessx.cashier_membership',c->>'membership_id',true);
end $test$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('accessx.manager'),'role','authenticated')::text,true);
set local role authenticated;
select public.accept_store_cashier(gen_random_uuid(),current_setting('accessx.manager_membership')::uuid);
do $test$
declare r jsonb;
begin
 r:=public.get_manager_sales_report(current_setting('accessx.owner')::uuid,date '2026-10-19',date '2026-10-20');
 if r->>'scope'<>'store-manager-sales-v1' or r->>'count'<>'0' then raise exception 'manager report mismatch';end if;
 begin
  perform public.get_manager_sales_report(current_setting('accessx.other')::uuid,date '2026-10-19',date '2026-10-20');
  raise exception 'cross-market manager report allowed';
 exception when raise_exception then if sqlerrm<>'staff_access_denied' then raise;end if;end;
 begin
  perform public.get_dashboard_summary();
  raise exception 'manager bypassed owner dashboard';
 exception when raise_exception then
  if sqlerrm not in ('dashboard_auth_required','dashboard_owner_required','dashboard_unavailable') and position('dashboard' in sqlerrm)=0 then raise;end if;
 end;
end $test$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('accessx.cashier'),'role','authenticated')::text,true);
set local role authenticated;
select public.accept_store_cashier(gen_random_uuid(),current_setting('accessx.cashier_membership')::uuid);
do $test$
begin
 begin
  perform public.get_manager_sales_report(current_setting('accessx.owner')::uuid,date '2026-10-19',date '2026-10-20');
  raise exception 'cashier allowed manager-only report';
 exception when raise_exception then if sqlerrm<>'staff_manager_required' then raise;end if;end;
end $test$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('accessx.owner'),'role','authenticated')::text,true);
set local role authenticated;
do $test$
declare v jsonb;
begin
 v:=public.save_store_cashier(gen_random_uuid(),current_setting('accessx.manager')::uuid,'Access X Manager','Access X Market',false,true,2,'cashier',false,false,false,false);
 if v->>'version'<>'3' then raise exception 'manager downgrade failed';end if;
end $test$;
reset role;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('accessx.manager'),'role','authenticated')::text,true);
set local role authenticated;
do $test$
begin
 begin
  perform public.get_manager_sales_report(current_setting('accessx.owner')::uuid,date '2026-10-19',date '2026-10-20');
  raise exception 'downgraded manager retained manager report';
 exception when raise_exception then if sqlerrm<>'staff_manager_required' then raise;end if;end;
end $test$;
reset role;
select 'PASS: own manager report; other market denied; cashier denied; downgrade immediate; transaction rolled back' as access_x_roles;
rollback;
