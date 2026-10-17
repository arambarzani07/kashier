-- All fixtures and financial records are rolled back.
begin;
select set_config('cr.a',gen_random_uuid()::text,true),set_config('cr.b',gen_random_uuid()::text,true),set_config('cr.customer',gen_random_uuid()::text,true),set_config('cr.product',gen_random_uuid()::text,true),set_config('cr.sale',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('cr.a')::uuid,'credit-rollback-a@example.invalid'),(current_setting('cr.b')::uuid,'credit-rollback-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('cr.a'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.customers(id,name) values(current_setting('cr.customer')::uuid,'original credit customer');
insert into public.products(id,name,sale_price) values(current_setting('cr.product')::uuid,'credit product',8000);
do $$ declare payload jsonb; s jsonb; full_sale jsonb; c uuid:=current_setting('cr.customer')::uuid; begin
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',current_setting('cr.product'),'quantity_units',20000,'unit_cost',5000)),'','','');
 payload:=jsonb_build_array(jsonb_build_object('product_id',current_setting('cr.product'),'quantity_units',1000,'expected_price',8000));
 full_sale:=public.post_credit_sale(gen_random_uuid(),payload,0,0,c,'');
 if (full_sale->>'debt_amount')::bigint<>8000 or (full_sale->>'change_due')::bigint<>0 or (select count(*) from public.cash_movements)<>0 or (select count(*) from public.cash_accounts)<>0 then raise exception 'Full credit created fictitious cash'; end if;
 s:=public.post_credit_sale(current_setting('cr.sale')::uuid,payload,1000,2000,c,'partial');
 if (s->>'total')::bigint<>7000 or (s->>'debt_amount')::bigint<>5000 or s->>'payment_mode'<>'credit' then raise exception 'Split totals wrong'; end if;
 if (select balance from public.customer_balances)<>13000 or (select balance from public.cash_accounts)<>2000 or (select quantity_units from public.product_stock)<>18000 then raise exception 'Atomic balances wrong'; end if;
 if not exists(select 1 from public.debt_entries where id=(s->>'debt_entry_id')::uuid and sale_id=(s->>'id')::uuid and amount=5000 and customer_id=c) then raise exception 'Debt source link missing'; end if;
 if not exists(select 1 from public.cash_movements where sale_id=(s->>'id')::uuid and amount=2000) then raise exception 'Cash portion source wrong'; end if;
 update public.customers set name='renamed credit customer' where id=c;
 if public.post_credit_sale(current_setting('cr.sale')::uuid,payload,1000,2000,c,'partial')<>s or s->>'customer_name'<>'original credit customer' or (select count(*) from public.debt_entries)<>2 then raise exception 'Credit replay or snapshot failed'; end if;
 begin perform public.post_credit_sale(current_setting('cr.sale')::uuid,payload,0,2000,c,'partial'); raise exception 'Conflicting credit allowed'; exception when raise_exception then if sqlerrm<>'sale_request_conflict' then raise; end if; end;
 begin perform public.post_cash_sale(current_setting('cr.sale')::uuid,payload,0,10000,'',''); raise exception 'Cross-mode replay allowed'; exception when raise_exception then if sqlerrm<>'sale_request_conflict' then raise; end if; end;
 begin perform public.post_credit_sale(gen_random_uuid(),payload,0,8000,c,''); raise exception 'Paid credit allowed'; exception when raise_exception then if sqlerrm<>'sale_credit_requires_debt' then raise; end if; end;
 begin perform public.post_credit_sale(gen_random_uuid(),payload,0,9000,c,''); raise exception 'Overpaid credit allowed'; exception when raise_exception then if sqlerrm<>'sale_credit_requires_debt' then raise; end if; end;
 begin perform public.post_credit_sale(gen_random_uuid(),payload,0,0,gen_random_uuid(),''); raise exception 'Missing customer allowed'; exception when raise_exception then if sqlerrm<>'debt_customer_unavailable' then raise; end if; end;
 begin perform public.post_credit_sale(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',current_setting('cr.product'),'quantity_units',19000,'expected_price',8000)),0,0,c,''); raise exception 'Oversold credit'; exception when raise_exception then if sqlerrm<>'sale_insufficient_stock' then raise; end if; end;
 perform public.post_cash_sale(gen_random_uuid(),payload,0,10000,'cash','');
 if (select balance from public.cash_accounts)<>10000 then raise exception 'Cash regression'; end if;
 perform public.post_debt_entry(gen_random_uuid(),c,'repayment',3000,'payment');
 if (select balance from public.customer_balances)<>10000 or (select balance from public.cash_accounts)<>13000 or (select debt_amount from public.sales where id=(s->>'id')::uuid)<>5000 then raise exception 'Repayment or historical amount wrong'; end if;
 perform public.post_cash_entry(gen_random_uuid(),'deposit',99999999987000,'cap');
 begin perform public.post_credit_sale(gen_random_uuid(),payload,0,1,c,'cash cap'); raise exception 'Cash cap ignored'; exception when check_violation then null; end;
 if (select count(*) from public.sales)<>3 or (select count(*) from public.debt_entries)<>3 or (select quantity_units from public.product_stock)<>17000 or (select balance from public.customer_balances)<>10000 then raise exception 'Cash failure not atomic'; end if;
 perform public.post_debt_entry(gen_random_uuid(),c,'charge',99999999990000,'debt cap');
 begin perform public.post_credit_sale(gen_random_uuid(),payload,0,0,c,'debt cap'); raise exception 'Debt cap ignored'; exception when raise_exception then if sqlerrm<>'debt_balance_limit' then raise; end if; end;
 if (select count(*) from public.sales)<>3 or (select quantity_units from public.product_stock)<>17000 or (select count(*) from public.debt_entries)<>4 then raise exception 'Debt failure not atomic'; end if;
 begin update public.sales set debt_amount=0; raise exception 'Direct edit allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Verify deferred circular source references before rollback.
set constraints all immediate;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('cr.b'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.products(id,name,sale_price) values(gen_random_uuid(),'other owner',8000);
do $$ declare payload jsonb; begin
 payload:=jsonb_build_array(jsonb_build_object('product_id',(select id from public.products limit 1),'quantity_units',1000,'expected_price',8000));
 begin perform public.post_credit_sale(gen_random_uuid(),payload,0,0,current_setting('cr.customer')::uuid,''); raise exception 'Cross-owner customer allowed'; exception when raise_exception then if sqlerrm<>'debt_customer_unavailable' then raise; end if; end;
 if (select count(*) from public.sales)<>0 or (select count(*) from public.debt_entries)<>0 then raise exception 'Credit RLS leak'; end if;
 begin perform public.post_credit_sale(current_setting('cr.sale')::uuid,payload,0,0,current_setting('cr.customer')::uuid,''); raise exception 'Cross-owner replay allowed'; exception when raise_exception then if sqlerrm<>'sale_request_conflict' then raise; end if; end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.post_credit_sale(gen_random_uuid(),'[]',0,0,gen_random_uuid(),''); raise exception 'Anonymous credit allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: full and partial credit, discount, source links, immutable snapshots, idempotency, cross-mode conflict, repayments, cash regression, stock/cash/debt failure atomicity and RLS' as verification;
rollback;
