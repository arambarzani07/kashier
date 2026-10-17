-- Rollback-only verification: purchase returns must be visible without changing supplier payable balance.
begin;
select set_config('sar.a',gen_random_uuid()::text,true),set_config('sar.b',gen_random_uuid()::text,true),set_config('sar.s',gen_random_uuid()::text,true),set_config('sar.p',gen_random_uuid()::text,true),set_config('sar.purchase_partial',gen_random_uuid()::text,true),set_config('sar.purchase_full',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('sar.a')::uuid,'sar-a@example.invalid'),(current_setting('sar.b')::uuid,'sar-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('sar.a'),'role','authenticated')::text,true);set local role authenticated;
insert into public.products(id,name,sale_price) values(current_setting('sar.p')::uuid,'Supplier audit product',8000);
insert into public.suppliers(id,name,phone) values(current_setting('sar.s')::uuid,'Supplier audit','000');
do $$
declare s uuid:=current_setting('sar.s')::uuid;pp uuid:=current_setting('sar.purchase_partial')::uuid;pf uuid:=current_setting('sar.purchase_full')::uuid;items_partial jsonb:=jsonb_build_array(jsonb_build_object('product_id',current_setting('sar.p'),'quantity_units',2000,'unit_cost',3000));items_full jsonb:=jsonb_build_array(jsonb_build_object('product_id',current_setting('sar.p'),'quantity_units',1000,'unit_cost',4000));activity jsonb;stmt jsonb;
begin
 perform public.post_cash_entry(gen_random_uuid(),'deposit',100000,'fixture cash');
 perform public.post_supplier_entry(gen_random_uuid(),s,'charge',5000,'old supplier debt');
 perform public.post_supplier_entry(gen_random_uuid(),s,'payment',1000,'pay old supplier debt');
 perform public.post_supplier_purchase(pp,items_partial,s,6000,'A-1','cash tracked partial source');
 perform public.post_purchase_return(gen_random_uuid(),pp,'partial return audit',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',1000)));
 perform public.post_supplier_purchase(pf,items_full,s,4000,'A-2','cash tracked full source');
 perform public.post_purchase_reversal(gen_random_uuid(),pf,'full return audit');
 if (select balance from public.supplier_balances where supplier_id=s)<>4000 then raise exception 'returns changed supplier payable balance';end if;
 activity:=public.get_supplier_activity(s,0,50);
 if (activity->>'total')::bigint<>4 or (select count(*) from jsonb_array_elements(activity->'rows') x where x->>'kind'='return')<>2 then raise exception 'supplier return activity missing';end if;
 if (select sum((x->>'amount')::bigint) from jsonb_array_elements(activity->'rows') x where x->>'kind'='return')<>7000 then raise exception 'supplier return total wrong';end if;
 if exists(select 1 from jsonb_array_elements(activity->'rows') x where x->>'kind'='return' and ((x->>'delta')::bigint<>0 or (x->>'balance_after')::bigint<>4000)) then raise exception 'supplier return changed payable balance';end if;
 if (select count(*) from jsonb_array_elements(activity->'rows') x where x->>'reference_no' like 'PPR-%')<>1 or (select count(*) from jsonb_array_elements(activity->'rows') x where x->>'reference_no' like 'PRV-%')<>1 then raise exception 'return references missing';end if;
 stmt:=public.get_supplier_statement(s,null,null);
 if (stmt->>'charges')::bigint<>5000 or (stmt->>'payments')::bigint<>1000 or (stmt->>'reversals')::bigint<>7000 or (stmt->>'closing')::bigint<>4000 or (stmt->>'count')::bigint<>4 then raise exception 'supplier statement totals wrong';end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('sar.b'),'role','authenticated')::text,true);set local role authenticated;
do $$ begin begin perform public.get_supplier_activity(current_setting('sar.s')::uuid,0,50);raise exception 'cross owner supplier activity allowed';exception when raise_exception then if sqlerrm<>'supplier_unavailable' then raise;end if;end;begin perform public.get_supplier_statement(current_setting('sar.s')::uuid,null,null);raise exception 'cross owner supplier statement allowed';exception when raise_exception then if sqlerrm<>'supplier_unavailable' then raise;end if;end;end $$;
reset role;set local role anon;
do $$ begin begin perform public.get_supplier_activity(gen_random_uuid(),0,50);raise exception 'anon supplier activity allowed';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'PASS: supplier activity shows full/partial cash purchase returns as debt-neutral audit events with correct balances, sources and RLS' verification;
rollback;
