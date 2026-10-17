begin;
select set_config('cs.a',gen_random_uuid()::text,true),set_config('cs.b',gen_random_uuid()::text,true),set_config('cs.open',gen_random_uuid()::text,true),set_config('cs.exp',gen_random_uuid()::text,true),set_config('cs.dep',gen_random_uuid()::text,true),set_config('cs.out',gen_random_uuid()::text,true),set_config('cs.s',gen_random_uuid()::text,true),set_config('cs.p',gen_random_uuid()::text,true),set_config('cs.c',gen_random_uuid()::text,true),set_config('cs.sale',gen_random_uuid()::text,true),set_config('cs.purchase',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('cs.a')::uuid,'cash-statement-a@example.invalid'),(current_setting('cs.b')::uuid,'cash-statement-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('cs.a'),'role','authenticated')::text,true);
set local role authenticated;
select public.post_cash_entry(current_setting('cs.open')::uuid,'deposit',10000,'Opening');
select public.post_cash_entry(current_setting('cs.exp')::uuid,'expense',1500,'Expense');
select public.post_cash_entry(current_setting('cs.dep')::uuid,'deposit',2000,'Deposit');
select public.post_cash_entry(current_setting('cs.out')::uuid,'withdrawal',500,'Withdrawal');
insert into public.suppliers(id,name) values(current_setting('cs.s')::uuid,'Cash statement supplier');
insert into public.customers(id,name) values(current_setting('cs.c')::uuid,'Cash statement customer');
insert into public.products(id,name,sale_price) values(current_setting('cs.p')::uuid,'Cash statement product',2000);
select public.post_supplier_purchase(current_setting('cs.purchase')::uuid,jsonb_build_array(jsonb_build_object('product_id',current_setting('cs.p'),'quantity_units',2000,'unit_cost',1000)),current_setting('cs.s')::uuid,500,'','');
select public.post_supplier_entry(gen_random_uuid(),current_setting('cs.s')::uuid,'payment',500,'Supplier repayment');
select public.post_cash_sale(current_setting('cs.sale')::uuid,jsonb_build_array(jsonb_build_object('product_id',current_setting('cs.p'),'quantity_units',1000,'expected_price',2000)),0,2000,'','');
select public.post_sale_return(gen_random_uuid(),current_setting('cs.sale')::uuid,'Cash refund',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',500)));
select public.post_debt_entry(gen_random_uuid(),current_setting('cs.c')::uuid,'charge',1000,'Old customer debt');
select public.post_debt_entry(gen_random_uuid(),current_setting('cs.c')::uuid,'repayment',300,'Customer repayment');
reset role;
update public.cash_movements set created_at='2026-05-01T10:00:00Z' where owner_id=current_setting('cs.a')::uuid;
update public.cash_movements set created_at='2026-04-30T20:59:59.999999Z' where id=current_setting('cs.open')::uuid;
-- Lower inclusive bound and upper exclusive bound, including an out-of-sequence date to test calculated running balances.
update public.cash_movements set created_at='2026-04-30T21:00:00Z' where id=current_setting('cs.dep')::uuid;
update public.cash_movements set created_at='2026-05-01T21:00:00Z' where id=current_setting('cs.out')::uuid;
set local role authenticated;
do $$declare v jsonb;row jsonb;balance numeric;before_count bigint;begin
 select count(*) into before_count from public.cash_movements;
 v:=public.get_cash_statement('2026-05-01','2026-05-01');
 if v->>'count'<>'7' or v#>>'{summary,opening}'<>'10000' or v#>>'{summary,inflows}'<>'4300' or v#>>'{summary,outflows}'<>'3500' or v#>>'{summary,closing}'<>'10800' then raise exception 'cash statement totals incorrect: %',v;end if;
 if v#>>'{rows,0,id}'<>current_setting('cs.dep') or v#>>'{rows,0,statement_balance}'<>'12000' then raise exception 'chronological running balance incorrect';end if;
 if v#>>'{by_kind,supplier_purchase}'<>'500' or v#>>'{by_kind,supplier_payment}'<>'500' or v#>>'{by_kind,repayment}'<>'300' or v#>>'{by_kind,refund}'<>'1000' then raise exception 'cash type totals incorrect';end if;
 for row in select value from jsonb_array_elements(v->'rows') loop
  if row->>'kind'='refund' and row->>'linked_sale_id'<>current_setting('cs.sale') then raise exception 'refund source missing';end if;
  if row->>'kind'='supplier_purchase' and row->>'purchase_id'<>current_setting('cs.purchase') then raise exception 'purchase source missing';end if;
 end loop;
 v:=public.get_cash_statement('2026-05-02','2026-05-02');if v#>>'{summary,opening}'<>'10800' or v#>>'{summary,outflows}'<>'500' or v#>>'{summary,closing}'<>'10300' then raise exception 'upper boundary incorrect';end if;
 v:=public.get_cash_statement('2026-05-03','2026-05-03');if v->>'count'<>'0' or v#>>'{summary,opening}'<>'10300' or v#>>'{summary,closing}'<>'10300' then raise exception 'empty statement lost opening';end if;
 begin perform public.get_cash_statement('2026-05-02','2026-05-01');raise exception 'reverse range accepted';exception when raise_exception then if sqlerrm<>'cash_statement_invalid_range' then raise;end if;end;
 if (select count(*) from public.cash_movements)<>before_count then raise exception 'statement wrote ledger';end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('cs.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin if (public.get_cash_statement('2026-05-01','2026-05-03')->>'count')<>'0' or (public.get_cash_statement('2026-05-01','2026-05-03')#>>'{summary,opening}')<>'0' then raise exception 'cash owner isolation failed';end if;end $$;
reset role;
-- Administrative rollback-only fixtures for exact large aggregates and the cap.
insert into public.cash_movements(owner_id,created_at,kind,amount,delta,balance_after,note,request_payload)
select current_setting('cs.b')::uuid,'2026-06-01T10:00:00Z','deposit',100000000000000,100000000000000,100000000000000,'Large exact aggregate','{}'::jsonb from generate_series(1,101);
set local role authenticated;
do $$declare v jsonb;begin v:=public.get_cash_statement('2026-06-01','2026-06-01');if v#>>'{summary,inflows}'<>'10100000000000000' or v#>>'{summary,closing}'<>'10100000000000000' then raise exception 'aggregate precision lost';end if;end $$;
reset role;
insert into public.cash_movements(owner_id,created_at,kind,amount,delta,balance_after,note,request_payload)
select current_setting('cs.b')::uuid,'2026-07-01T10:00:00Z','deposit',1,1,1,'Cap fixture','{}'::jsonb from generate_series(1,5001);
set local role authenticated;
do $$begin begin perform public.get_cash_statement('2026-07-01','2026-07-01');raise exception 'truncated statement accepted';exception when raise_exception then if sqlerrm<>'cash_statement_too_many_rows' then raise;end if;end;end $$;
reset role;
do $$begin if has_function_privilege('anon','public.get_cash_statement(date,date)','execute') then raise exception 'anon exposed';end if;end $$;
rollback;
