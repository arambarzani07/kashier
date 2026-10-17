-- All fixtures and financial records are rolled back.
begin;
select set_config('rv.a',gen_random_uuid()::text,true),set_config('rv.b',gen_random_uuid()::text,true),set_config('rv.customer',gen_random_uuid()::text,true),set_config('rv.product',gen_random_uuid()::text,true),set_config('rv.cash_sale',gen_random_uuid()::text,true),set_config('rv.cash_rev',gen_random_uuid()::text,true),set_config('rv.credit_sale',gen_random_uuid()::text,true),set_config('rv.credit_rev',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('rv.a')::uuid,'reversal-a@example.invalid'),(current_setting('rv.b')::uuid,'reversal-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('rv.a'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.customers(id,name) values(current_setting('rv.customer')::uuid,'reversal customer');
insert into public.products(id,name,sale_price) values(current_setting('rv.product')::uuid,'reversal product',8000);
do $$
declare payload jsonb; s jsonb; r jsonb; c uuid:=current_setting('rv.customer')::uuid; stmt jsonb; daily jsonb; bad_sale uuid:=gen_random_uuid();
begin
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',current_setting('rv.product'),'quantity_units',30000,'unit_cost',5000)),'','','');
 payload:=jsonb_build_array(jsonb_build_object('product_id',current_setting('rv.product'),'quantity_units',1000,'expected_price',8000));
 s:=public.post_cash_sale(current_setting('rv.cash_sale')::uuid,payload,0,10000,'cash customer','');
 if (select quantity_units from public.product_stock)<>29000 or (select balance from public.cash_accounts)<>8000 then raise exception 'cash sale setup wrong'; end if;
 r:=public.post_sale_reversal(current_setting('rv.cash_rev')::uuid,(s->>'id')::uuid,'cash return');
 if (r->>'cash_refund')::bigint<>8000 or (r->>'debt_reversed')::bigint<>0 or (select quantity_units from public.product_stock)<>30000 or (select balance from public.cash_accounts)<>0 then raise exception 'cash reversal balances wrong'; end if;
 if public.post_sale_reversal(current_setting('rv.cash_rev')::uuid,(s->>'id')::uuid,'cash return')<>r or (select count(*) from public.sale_reversals)<>1 then raise exception 'cash reversal retry failed'; end if;
 begin perform public.post_sale_reversal(gen_random_uuid(),(s->>'id')::uuid,'duplicate'); raise exception 'duplicate reversal allowed'; exception when raise_exception then if sqlerrm<>'reversal_already_posted' then raise; end if; end;
 s:=public.post_credit_sale(current_setting('rv.credit_sale')::uuid,payload,0,2000,c,'partial credit');
 if (select quantity_units from public.product_stock)<>29000 or (select balance from public.cash_accounts)<>2000 or (select balance from public.customer_balances)<>6000 then raise exception 'credit sale setup wrong'; end if;
 r:=public.post_sale_reversal(current_setting('rv.credit_rev')::uuid,(s->>'id')::uuid,'credit return');
 if (r->>'cash_refund')::bigint<>2000 or (r->>'debt_reversed')::bigint<>6000 or (select quantity_units from public.product_stock)<>30000 or (select balance from public.cash_accounts)<>0 or (select balance from public.customer_balances)<>0 then raise exception 'credit reversal balances wrong'; end if;
 s:=public.post_credit_sale(bad_sale,payload,0,0,c,'will be repaid');
 perform public.post_debt_entry(gen_random_uuid(),c,'repayment',7000,'repayment before return');
 begin perform public.post_sale_reversal(gen_random_uuid(),bad_sale,'should reject'); raise exception 'repaid debt reversal allowed'; exception when raise_exception then if sqlerrm<>'reversal_debt_already_repaid' then raise; end if; end;
 if (select quantity_units from public.product_stock)<>29000 or (select balance from public.customer_balances)<>1000 then raise exception 'failed reversal was not atomic'; end if;
 stmt:=public.get_customer_statement(c,null,null);
 if (stmt->>'reversals')::bigint<>6000 or (stmt->>'closing')::bigint<>1000 then raise exception 'statement reversal totals wrong'; end if;
 daily:=public.get_daily_report((now() at time zone 'Asia/Baghdad')::date);
 if (daily->'returns'->>'count')::bigint<>2 or (daily->'returns'->>'cash_refund')::bigint<>10000 or (daily->'returns'->>'debt_reversed')::bigint<>6000 then raise exception 'daily return totals wrong'; end if;
 if (select count(*) from public.stock_movements where reversal_id is not null)<>2 or (select count(*) from public.cash_movements where kind='refund')<>2 or (select count(*) from public.debt_entries where kind='reversal')<>1 then raise exception 'reversal source ledgers wrong'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('rv.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 begin perform public.post_sale_reversal(gen_random_uuid(),current_setting('rv.cash_sale')::uuid,'other owner'); raise exception 'cross owner reversal allowed'; exception when raise_exception then if sqlerrm<>'reversal_sale_unavailable' then raise; end if; end;
 if (select count(*) from public.sale_reversals)<>0 then raise exception 'reversal RLS leak'; end if;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.post_sale_reversal(gen_random_uuid(),gen_random_uuid(),'anon'); raise exception 'anonymous reversal allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: full cash/credit reversal, inventory, cash, debt, retry, duplicate block, repaid-debt guard, reports and RLS' as verification;
rollback;