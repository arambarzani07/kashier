begin;
select set_config('dash.a',gen_random_uuid()::text,true),set_config('dash.b',gen_random_uuid()::text,true),set_config('dash.c',gen_random_uuid()::text,true),set_config('dash.s',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('dash.a')::uuid,'dash-a@example.invalid'),(current_setting('dash.b')::uuid,'dash-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('dash.a'),'role','authenticated')::text,true);set local role authenticated;
do $$declare v jsonb;begin v:=public.get_dashboard_summary();if v->>'scope'<>'owner-dashboard-v1' or v->>'owner_id'<>current_setting('dash.a') or v->>'cash_balance'<>'0' or v->>'customer_balance'<>'0' or v->>'supplier_balance'<>'0' or v->>'product_count'<>'0' or v->>'low_stock_count'<>'0' or v->>'expired_count'<>'0' then raise exception 'empty summary incorrect';end if;end $$;
insert into public.customers(id,name) values(current_setting('dash.c')::uuid,'Summary customer');
insert into public.suppliers(id,name) values(current_setting('dash.s')::uuid,'Summary supplier');
select public.post_cash_entry(gen_random_uuid(),'deposit',10000,'Float');
select public.post_debt_entry(gen_random_uuid(),current_setting('dash.c')::uuid,'charge',1000,'Charge');
select public.post_debt_entry(gen_random_uuid(),current_setting('dash.c')::uuid,'repayment',200,'Payment');
select public.post_supplier_entry(gen_random_uuid(),current_setting('dash.s')::uuid,'charge',3000,'Charge');
select public.post_supplier_entry(gen_random_uuid(),current_setting('dash.s')::uuid,'payment',500,'Payment');
insert into public.products(name,sale_price,expiry_date,reorder_units) values
 ('Expired with stock',1,(statement_timestamp() at time zone 'Asia/Baghdad')::date-1,1000),
 ('Expired empty',1,(statement_timestamp() at time zone 'Asia/Baghdad')::date-1,null),
 ('Today',1,(statement_timestamp() at time zone 'Asia/Baghdad')::date,0),
 ('No date',1,null,null),('Minimum zero empty',1,null,0);
select public.post_purchase(gen_random_uuid(),(select jsonb_agg(jsonb_build_object('product_id',id,'quantity_units',1000,'unit_cost',1)) from public.products where name in ('Expired with stock','Today')),'','','');
do $$declare v jsonb;n bigint;begin
 select count(*) into n from public.stock_movements;
 v:=public.get_dashboard_summary();if v->>'cash_balance'<>'9700' or v->>'customer_balance'<>'800' or v->>'supplier_balance'<>'2500' or v->>'product_count'<>'5' or v->>'low_stock_count'<>'2' or v->>'expired_count'<>'1' then raise exception 'populated summary incorrect: %',v;end if;
 if v->>'today'<>((v->>'generated_at')::timestamptz at time zone 'Asia/Baghdad')::date::text or v->>'timezone'<>'Asia/Baghdad' or v->>'currency'<>'IQD' then raise exception 'summary date/scope incorrect';end if;
 if jsonb_typeof(v->'cash_balance')<>'string' or jsonb_typeof(v->'product_count')<>'string' then raise exception 'numbers are not exact strings';end if;
 if (select count(*) from public.stock_movements)<>n then raise exception 'summary mutated stock';end if;
end $$;
-- Verify aggregate totals remain exact beyond JS Number precision without posting unrealistic ledger entries.
reset role;
insert into public.customers(name,owner_id) select 'Large '||g,current_setting('dash.a')::uuid from generate_series(1,100) g;
insert into public.customer_balances(customer_id,owner_id,balance) select id,owner_id,100000000000000 from public.customers where owner_id=current_setting('dash.a')::uuid and name like 'Large %';
set local role authenticated;
do $$begin if public.get_dashboard_summary()->>'customer_balance'<>'10000000000000800' then raise exception 'large aggregate rounded';end if;end $$;
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('dash.b'),'role','authenticated')::text,true);set local role authenticated;
do $$declare v jsonb;begin v:=public.get_dashboard_summary();if v->>'owner_id'<>current_setting('dash.b') or v->>'cash_balance'<>'0' or v->>'customer_balance'<>'0' or v->>'supplier_balance'<>'0' or v->>'product_count'<>'0' or v->>'low_stock_count'<>'0' or v->>'expired_count'<>'0' then raise exception 'other owner leaked';end if;end $$;
reset role;select set_config('request.jwt.claims','{}',true);set local role authenticated;
do $$begin begin perform public.get_dashboard_summary();raise exception 'missing UID allowed';exception when raise_exception then if sqlerrm<>'dashboard_auth_required' then raise;end if;end;end $$;
reset role;set local role anon;
do $$begin begin perform public.get_dashboard_summary();raise exception 'anonymous allowed';exception when insufficient_privilege then null;end;end $$;
reset role;select 'PASS: dashboard empty/current totals, exact large sums, stock/expiry boundaries, owner and anonymous isolation' verification;
rollback;
