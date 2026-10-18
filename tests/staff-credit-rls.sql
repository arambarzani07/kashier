begin;
select set_config('sc.owner',gen_random_uuid()::text,true),set_config('sc.member',gen_random_uuid()::text,true),set_config('sc.other',gen_random_uuid()::text,true),set_config('sc.product',gen_random_uuid()::text,true),set_config('sc.customer',gen_random_uuid()::text,true),set_config('sc.foreign',gen_random_uuid()::text,true),set_config('sc.sale',gen_random_uuid()::text,true),set_config('sc.zero',gen_random_uuid()::text,true),set_config('sc.action',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('sc.owner')::uuid,'credit-owner@example.invalid'),(current_setting('sc.member')::uuid,'credit-member@example.invalid'),(current_setting('sc.other')::uuid,'credit-stranger@example.invalid');
insert into public.customers(id,owner_id,name) values(current_setting('sc.foreign')::uuid,current_setting('sc.other')::uuid,'Other shop');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.owner'),'role','authenticated')::text,true);set local role authenticated;
insert into public.products(id,name,sale_price) values(current_setting('sc.product')::uuid,'Product',1000);
insert into public.customers(id,name,phone) values(current_setting('sc.customer')::uuid,repeat('ک',150),'07500000000');
insert into public.customers(name,phone) values('Literal % name',null),('Literal X name',null);
select public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',current_setting('sc.product')::uuid,'quantity_units',10000,'unit_cost',500)),'','','');
select public.save_store_cashier(current_setting('sc.action')::uuid,current_setting('sc.member')::uuid,'Credit cashier','Store',false,true,0,'manager');
select set_config('sc.membership',(public.get_staff_workspace()->'cashiers'->0->>'id'),true);
do $$begin if(public.get_staff_workspace()->'cashiers'->0->>'can_credit')::boolean then raise exception 'manager gained implicit credit';end if;end $$;
reset role;
-- Preserve exact pre-credit queued request compatibility.
update public.staff_actions set request_payload=request_payload-'credit' where id=current_setting('sc.action')::uuid;
set local role authenticated;
select public.save_store_cashier(current_setting('sc.action')::uuid,current_setting('sc.member')::uuid,'Credit cashier','Store',false,true,0,'manager');
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.member'),'role','authenticated')::text,true);set local role authenticated;
do $$begin begin perform public.get_cashier_customers(current_setting('sc.owner')::uuid);raise exception 'unaccepted read';exception when raise_exception then if sqlerrm<>'staff_access_denied' then raise;end if;end;end $$;
select public.accept_store_cashier(gen_random_uuid(),current_setting('sc.membership')::uuid);
do $$begin
 if exists(select 1 from public.customers) or exists(select 1 from public.sales) or exists(select 1 from public.debt_entries) then raise exception 'owner RLS changed';end if;
 begin perform public.get_cashier_customers(current_setting('sc.owner')::uuid);raise exception 'no permission read';exception when raise_exception then if sqlerrm<>'staff_credit_denied' then raise;end if;end;
 begin perform public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,current_setting('sc.sale')::uuid,jsonb_build_array(jsonb_build_object('product_id',current_setting('sc.product'),'quantity_units','1000','expected_price','1000')),0,200,current_setting('sc.customer')::uuid,'');raise exception 'no permission post';exception when raise_exception then if sqlerrm<>'staff_credit_denied' then raise;end if;end;
 begin perform private.post_credit_sale_for_owner(current_setting('sc.owner')::uuid,gen_random_uuid(),'[]',0,0,current_setting('sc.customer')::uuid,'');raise exception 'core exposed';exception when insufficient_privilege then null;end;
end $$;
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.owner'),'role','authenticated')::text,true);set local role authenticated;
select public.save_store_cashier(gen_random_uuid(),current_setting('sc.member')::uuid,'Credit cashier','Store',false,true,2,'cashier',true);
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.member'),'role','authenticated')::text,true);set local role authenticated;
do $$declare x jsonb;items jsonb:=jsonb_build_array(jsonb_build_object('product_id',current_setting('sc.product'),'quantity_units','1000','expected_price','1000'));begin
 x:=public.get_cashier_customers(current_setting('sc.owner')::uuid,'%');if x->>'total'<>'1' or x->'rows'->0->>'name'<>'Literal % name' then raise exception 'literal lookup';end if;
 x:=public.get_cashier_customers(current_setting('sc.owner')::uuid,'07500000000');if x->>'total'<>'1' or x->'rows'->0->>'id'<>current_setting('sc.customer') or (x->'rows'->0)?'balance' or(x->'rows'->0)?'owner_id' then raise exception 'customer scope/data';end if;
 begin perform public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,current_setting('sc.sale')::uuid,items,100,200,current_setting('sc.customer')::uuid,'');raise exception 'discount';exception when raise_exception then if sqlerrm<>'staff_discount_denied' then raise;end if;end;
 begin perform public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,gen_random_uuid(),items,0,200,current_setting('sc.foreign')::uuid,'');raise exception 'foreign customer';exception when raise_exception then if sqlerrm<>'debt_customer_unavailable' then raise;end if;end;
 begin perform public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,gen_random_uuid(),items,0,1000,current_setting('sc.customer')::uuid,'');raise exception 'no actual debt';exception when raise_exception then if sqlerrm<>'sale_credit_requires_debt' then raise;end if;end;
 begin perform public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',current_setting('sc.product'),'quantity_units','20000','expected_price','1000')),0,0,current_setting('sc.customer')::uuid,'');raise exception 'stock';exception when raise_exception then if sqlerrm<>'sale_insufficient_stock' then raise;end if;end;
 if auth.uid()<>current_setting('sc.member')::uuid then raise exception 'identity substituted';end if;
end $$;
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.owner'),'role','authenticated')::text,true);set local role authenticated;
select public.save_store_cashier(gen_random_uuid(),current_setting('sc.member')::uuid,'Credit cashier','Store',true,true,3,'cashier',true);
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.member'),'role','authenticated')::text,true);set local role authenticated;
select public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,current_setting('sc.sale')::uuid,jsonb_build_array(jsonb_build_object('product_id',current_setting('sc.product'),'quantity_units','1000','expected_price','1000')),100,200,current_setting('sc.customer')::uuid,'credit note');
select public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,current_setting('sc.zero')::uuid,jsonb_build_array(jsonb_build_object('product_id',current_setting('sc.product'),'quantity_units','1000','expected_price','1000')),0,0,current_setting('sc.customer')::uuid,'zero upfront');
do $$declare x jsonb;begin
 x:=public.get_cashier_sale(current_setting('sc.owner')::uuid,current_setting('sc.sale')::uuid);if x->>'actor_id'<>auth.uid()::text or x->>'actor_name'<>'Credit cashier' or x->>'debt_amount'<>'700' or x->>'received'<>'200' or x->>'total'<>'900' or x->>'customer_id'<>current_setting('sc.customer') then raise exception 'saved credit/actor';end if;
 begin perform public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,current_setting('sc.sale')::uuid,jsonb_build_array(jsonb_build_object('product_id',current_setting('sc.product'),'quantity_units','1000','expected_price','1000')),100,201,current_setting('sc.customer')::uuid,'credit note');raise exception 'conflict';exception when raise_exception then if sqlerrm<>'sale_request_conflict' then raise;end if;end;
end $$;
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.owner'),'role','authenticated')::text,true);set local role authenticated;
do $$begin
 if(select balance from public.cash_accounts)<>200 or(select balance from public.customer_balances where customer_id=current_setting('sc.customer')::uuid)<>1700 or(select quantity_units from public.product_stock where product_id=current_setting('sc.product')::uuid)<>8000 or(select value_iqd from public.inventory_cost_state where product_id=current_setting('sc.product')::uuid)<>4000 then raise exception 'atomic ledgers/cost';end if;
 if(select count(*) from public.sales)<>2 or(select count(*) from public.debt_entries)<>2 or(select count(*) from public.cash_movements where kind='sale')<>1 then raise exception 'failed writes or zero upfront cash';end if;
end $$;
select public.save_store_cashier(gen_random_uuid(),current_setting('sc.member')::uuid,'Renamed','Store',false,true,4,'cashier',false);
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.member'),'role','authenticated')::text,true);set local role authenticated;
select public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,current_setting('sc.sale')::uuid,jsonb_build_array(jsonb_build_object('product_id',current_setting('sc.product'),'quantity_units','1000','expected_price','1000')),100,200,current_setting('sc.customer')::uuid,'credit note');
do $$begin
 if public.get_cashier_sale(current_setting('sc.owner')::uuid,current_setting('sc.sale')::uuid)->>'actor_name'<>'Credit cashier' then raise exception 'actor renamed';end if;
 begin perform public.get_cashier_customers(current_setting('sc.owner')::uuid);raise exception 'revoked lookup';exception when raise_exception then if sqlerrm<>'staff_credit_denied' then raise;end if;end;
 begin perform public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',current_setting('sc.product'),'quantity_units','1000','expected_price','1000')),0,0,current_setting('sc.customer')::uuid,'');raise exception 'revoked new sale';exception when raise_exception then if sqlerrm<>'staff_credit_denied' then raise;end if;end;
end $$;
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.other'),'role','authenticated')::text,true);set local role authenticated;
do $$begin begin perform public.get_cashier_sale(current_setting('sc.owner')::uuid,current_setting('sc.sale')::uuid);raise exception 'foreign receipt';exception when raise_exception then if sqlerrm<>'staff_access_denied' then raise;end if;end;end $$;
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.owner'),'role','authenticated')::text,true);set local role authenticated;
select public.save_store_cashier(gen_random_uuid(),current_setting('sc.member')::uuid,'Renamed','Store',false,false,5,'cashier',false);
select public.post_sale_reversal(gen_random_uuid(),current_setting('sc.sale')::uuid,'owner return');
do $$begin
 if(select balance from public.cash_accounts)<>0 or(select balance from public.customer_balances where customer_id=current_setting('sc.customer')::uuid)<>1000 or(select quantity_units from public.product_stock where product_id=current_setting('sc.product')::uuid)<>9000 then raise exception 'owner return after staff credit';end if;
end $$;
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('sc.member'),'role','authenticated')::text,true);set local role authenticated;
do $$begin begin perform public.post_cashier_credit_sale(current_setting('sc.owner')::uuid,current_setting('sc.sale')::uuid,'[]',0,0,current_setting('sc.customer')::uuid,'');raise exception 'suspended retry';exception when raise_exception then if sqlerrm<>'staff_access_denied' then raise;end if;end;end $$;
reset role;set local role anon;
do $$begin begin perform public.get_cashier_customers(current_setting('sc.owner')::uuid);raise exception 'anonymous';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'PASS: explicit credit permission, consent, legacy retries, scoped lookup, real actor, atomic stock/cost/cash/debt, zero upfront, conflict/revocation, owner reversal and isolation' as verification;
rollback;
