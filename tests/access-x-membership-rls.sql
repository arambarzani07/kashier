-- Access X Phase 1: real RPC and RLS boundaries, transaction-only fixtures.
-- Requires administrative connection; all inserts and updates are rolled back.
begin;
select set_config('ax.owner',gen_random_uuid()::text,true),set_config('ax.member',gen_random_uuid()::text,true),set_config('ax.other',gen_random_uuid()::text,true),set_config('ax.membership',gen_random_uuid()::text,true);
insert into auth.users(id,email) values
(current_setting('ax.owner')::uuid,'access-x-rollback-owner@example.invalid'),
(current_setting('ax.member')::uuid,'access-x-rollback-cashier@example.invalid'),
(current_setting('ax.other')::uuid,'access-x-rollback-other@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ax.owner'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.products(id,name,sale_price) values(gen_random_uuid(),'Access X rollback-only product',1000);
do $ax$
declare x jsonb;
begin
 x:=public.save_store_cashier(gen_random_uuid(),current_setting('ax.member')::uuid,'Rollback Cashier','Rollback Store',false,true,0,'cashier',false,false,false,false);
 if x->>'membership_id'<>current_setting('ax.membership') then
  perform set_config('ax.membership',x->>'membership_id',true);
 end if;
end $ax$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ax.member'),'role','authenticated')::text,true);
set local role authenticated;
do $ax$
begin
 if (select count(*) from public.products where name='Access X rollback-only product')<>0 then raise exception 'Cashier bypassed owner-owned RLS';end if;
 begin
  perform public.get_cashier_catalog(current_setting('ax.owner')::uuid,'Access X rollback-only product',0);
  raise exception 'Pending cashier catalog allowed';
 exception when raise_exception then
  if sqlerrm<>'staff_access_denied' then raise;end if;
 end;
end $ax$;
select public.accept_store_cashier(gen_random_uuid(),current_setting('ax.membership')::uuid);
do $ax$
declare x jsonb;
begin
 x:=public.get_cashier_catalog(current_setting('ax.owner')::uuid,'Access X rollback-only product',0);
 if (x->>'total')<>'1' or jsonb_array_length(x->'rows')<>1 then raise exception 'Accepted cashier catalog failed';end if;
 begin
  perform public.get_cashier_catalog(current_setting('ax.other')::uuid,'',0);
  raise exception 'Cross-owner catalog allowed';
 exception when raise_exception then if sqlerrm<>'staff_access_denied' then raise;end if;end;
end $ax$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ax.owner'),'role','authenticated')::text,true);
set local role authenticated;
do $ax$
declare x jsonb;
begin
 x:=public.save_store_cashier(gen_random_uuid(),current_setting('ax.member')::uuid,'Rollback Cashier','Rollback Store',false,false,2,'cashier',false,false,false,false);
 if (x->>'version')<>'3' then raise exception 'Disabling cashier failed';end if;
end $ax$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ax.member'),'role','authenticated')::text,true);
set local role authenticated;
do $ax$
begin
 begin
  perform public.get_cashier_catalog(current_setting('ax.owner')::uuid,'',0);
  raise exception 'Disabled cashier catalog allowed';
 exception when raise_exception then if sqlerrm<>'staff_access_denied' then raise;end if;end;
end $ax$;
reset role;
select 'PASS: pending denied, accepted cashier scoped catalog, other-owner denied, disabled denied; all fixtures rolled back' as access_x_membership;
rollback;
