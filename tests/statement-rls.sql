-- Administrative verification only: every fixture is rolled back.
begin;
select set_config('st.a',gen_random_uuid()::text,true),set_config('st.b',gen_random_uuid()::text,true),set_config('st.c',gen_random_uuid()::text,true),set_config('st.large',gen_random_uuid()::text,true),set_config('st.precise',gen_random_uuid()::text,true),set_config('st.empty',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('st.a')::uuid,'statement-a@example.invalid'),(current_setting('st.b')::uuid,'statement-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('st.a'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.customers(id,name,phone) values(current_setting('st.c')::uuid,'statement customer','123'),(current_setting('st.large')::uuid,'large statement',null),(current_setting('st.precise')::uuid,'exact totals',null),(current_setting('st.empty')::uuid,'empty account',null);
do $$ declare c uuid:=current_setting('st.c')::uuid;product uuid:=gen_random_uuid(); begin
 insert into public.products(id,name,sale_price) values(product,'statement item',8000);
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',product,'quantity_units',1000,'unit_cost',5000)),'','','');
 perform public.post_debt_entry(gen_random_uuid(),c,'charge',10000,'opening');
 perform public.post_debt_entry(gen_random_uuid(),c,'repayment',2000,'start boundary');
 perform public.post_credit_sale(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',product,'quantity_units',1000,'expected_price',8000)),0,2000,c,'end boundary');
 perform public.post_debt_entry(gen_random_uuid(),c,'charge',1000,'outside end');
end $$;
reset role;
-- Put records immediately around Baghdad midnight; timestamps are never editable by browser roles.
update public.debt_entries set created_at=case note when 'opening' then '2026-05-01 20:59:59+00'::timestamptz when 'start boundary' then '2026-05-01 21:00:00+00'::timestamptz when 'end boundary' then '2026-05-02 20:59:59.999+00'::timestamptz else '2026-05-02 21:00:00+00'::timestamptz end where customer_id=current_setting('st.c')::uuid;
insert into public.debt_entries(id,owner_id,customer_id,customer_name,kind,amount,delta,balance_after,note,request_payload,created_at)
select gen_random_uuid(),current_setting('st.a')::uuid,current_setting('st.large')::uuid,'large statement','charge',1,1,n,'limit test','{}','2025-01-01'::timestamptz from generate_series(1,5001) n;
set local role authenticated;
-- Repeated valid charge/repayment cycles keep current balances within limits,
-- while lifetime charges and repayments exceed JavaScript's safe integer range.
do $$ declare c uuid:=current_setting('st.precise')::uuid; begin
 perform public.post_cash_entry(gen_random_uuid(),'withdrawal',4000,'isolate precision test');
 for n in 1..100 loop
  perform public.post_debt_entry(gen_random_uuid(),c,'charge',100000000000000,'precision charge');
  perform public.post_debt_entry(gen_random_uuid(),c,'repayment',100000000000000,'precision repayment');
  perform public.post_cash_entry(gen_random_uuid(),'withdrawal',100000000000000,'precision cash cycle');
 end loop;
end $$;
do $$ declare s jsonb; all_s jsonb; r jsonb; c uuid:=current_setting('st.c')::uuid; begin
 s:=public.get_customer_statement(c,'2026-05-02','2026-05-02');
 if s->>'opening'<>'10000' or s->>'charges'<>'6000' or s->>'repayments'<>'2000' or s->>'closing'<>'14000' or (s->>'count')::int<>2 then raise exception 'Baghdad day bounds or totals wrong: %',s; end if;
 if s#>>'{rows,0,balance}'<>'8000' or s#>>'{rows,1,balance}'<>'14000' or s#>>'{rows,0,kind}'<>'repayment' or s#>>'{rows,1,sale_id}' is null then raise exception 'Statement order, running balances or source missing'; end if;
 all_s:=public.get_customer_statement(c);
 if all_s->>'opening'<>'0' or all_s->>'closing'<>'15000' or (all_s->>'count')::int<>4 then raise exception 'Full statement incomplete'; end if;
 s:=public.get_customer_statement(c,null,'2026-05-01');if s->>'closing'<>'10000' or (s->>'count')::int<>1 then raise exception 'Open lower bound wrong'; end if;
 s:=public.get_customer_statement(c,'2026-05-03',null);if s->>'opening'<>'14000' or s->>'closing'<>'15000' or (s->>'count')::int<>1 then raise exception 'Open upper bound wrong'; end if;
 s:=public.get_customer_statement(c,'2026-05-04','2026-05-04');if s->>'opening'<>'15000' or s->>'closing'<>'15000' or s->'rows'<>'[]'::jsonb then raise exception 'No activity must retain opening debt'; end if;
 s:=public.get_customer_statement(current_setting('st.empty')::uuid);if s->>'opening'<>'0' or s->>'closing'<>'0' or s->>'count'<>'0' then raise exception 'Empty account invented activity'; end if;
 s:=public.get_customer_statement(current_setting('st.precise')::uuid);if s->>'charges'<>'10000000000000000' or s->>'repayments'<>'10000000000000000' or s->>'closing'<>'0' or jsonb_typeof(s->'charges')<>'string' or s#>>'{rows,199,balance}'<>'0' then raise exception 'Exact aggregates lost precision'; end if;
 begin perform public.get_customer_statement(current_setting('st.large')::uuid);raise exception 'Oversized statement silently truncated';exception when raise_exception then if sqlerrm<>'statement_too_many_rows' then raise;end if;end;
 s:=public.get_customer_statement(current_setting('st.large')::uuid,'2026-01-01','2026-01-02');if s->>'opening'<>'5001' or s->>'count'<>'0' then raise exception 'Narrower limit recovery wrong';end if;
 begin perform public.get_customer_statement(c,'2026-05-03','2026-05-01');raise exception 'Reversed range accepted';exception when raise_exception then if sqlerrm<>'statement_invalid_dates' then raise;end if;end;
 if (select balance from public.customer_balances where customer_id=c)<>15000 or (select count(*) from public.sales)<>1 or (select count(*) from public.cash_movements)<>203 then raise exception 'Statement mutated data';end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('st.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 begin perform public.get_customer_statement(current_setting('st.c')::uuid);raise exception 'Cross-owner statement allowed';exception when raise_exception then if sqlerrm<>'debt_customer_unavailable' then raise;end if;end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.get_customer_statement(gen_random_uuid());raise exception 'Anonymous statement allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: inclusive Baghdad dates, open bounds, opening and closing totals, full ledger, ordered running balances, credit source, empty accounts, exact string aggregates, explicit 5000-row cap, read-only behavior and RLS' as verification;
rollback;
