-- Administrative rollback-only test; leaves no business or account records.
begin;
select set_config('dr.a',gen_random_uuid()::text,true),set_config('dr.b',gen_random_uuid()::text,true),set_config('dr.c',gen_random_uuid()::text,true),set_config('dr.p',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('dr.a')::uuid,'daily-a@example.invalid'),(current_setting('dr.b')::uuid,'daily-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('dr.a'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.customers(id,name) values(current_setting('dr.c')::uuid,'daily customer');
insert into public.products(id,name,sale_price) values(current_setting('dr.p')::uuid,'daily product',3000);
do $$ declare c uuid:=current_setting('dr.c')::uuid;items jsonb:=jsonb_build_array(jsonb_build_object('product_id',current_setting('dr.p'),'quantity_units',1000,'expected_price',3000));begin
 perform public.post_cash_entry(gen_random_uuid(),'deposit',10000,'opening');
 perform public.post_debt_entry(gen_random_uuid(),c,'charge',5000,'opening');
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',current_setting('dr.p'),'quantity_units',20000,'unit_cost',1000)),'','','opening');
 perform public.post_cash_sale(gen_random_uuid(),items,500,5000,'','cash day');
 perform public.post_credit_sale(gen_random_uuid(),items,0,1000,c,'partial day');
 perform public.post_credit_sale(gen_random_uuid(),items,0,0,c,'full day');
 perform public.post_debt_entry(gen_random_uuid(),c,'charge',1000,'manual day');
 perform public.post_debt_entry(gen_random_uuid(),c,'repayment',2000,'repayment day');
 perform public.post_cash_entry(gen_random_uuid(),'deposit',500,'deposit day');
 perform public.post_cash_entry(gen_random_uuid(),'withdrawal',1000,'withdrawal day');
 perform public.post_cash_entry(gen_random_uuid(),'expense',300,'expense day');
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',current_setting('dr.p'),'quantity_units',1000,'unit_cost',2000)),'','','purchase day');
 perform public.post_cash_entry(gen_random_uuid(),'deposit',700,'next day');
 perform public.post_debt_entry(gen_random_uuid(),c,'charge',800,'next day');
end $$;
reset role;
update public.sales set created_at=case note when 'cash day' then '2026-05-01 21:00:00+00'::timestamptz when 'full day' then '2026-05-02 20:59:59.999+00'::timestamptz else '2026-05-02 10:00:00+00'::timestamptz end where owner_id=current_setting('dr.a')::uuid;
update public.purchases set created_at=case note when 'opening' then '2026-05-01 20:59:59+00'::timestamptz else '2026-05-02 10:00:00+00'::timestamptz end where owner_id=current_setting('dr.a')::uuid;
update public.cash_movements set created_at=case note when 'opening' then '2026-05-01 20:59:59+00'::timestamptz when 'next day' then '2026-05-02 21:00:00+00'::timestamptz else '2026-05-02 10:00:00+00'::timestamptz end where owner_id=current_setting('dr.a')::uuid;
update public.cash_movements m set created_at=s.created_at from public.sales s where m.sale_id=s.id;
update public.debt_entries set created_at=case note when 'opening' then '2026-05-01 20:59:59+00'::timestamptz when 'next day' then '2026-05-02 21:00:00+00'::timestamptz else '2026-05-02 10:00:00+00'::timestamptz end where owner_id=current_setting('dr.a')::uuid;
update public.debt_entries d set created_at=s.created_at from public.sales s where d.sale_id=s.id;
set local role authenticated;
do $$ declare r jsonb;begin
 r:=public.get_daily_report('2026-05-02');
 if r->>'day'<>'2026-05-02' or r->>'timezone'<>'Asia/Baghdad' or r#>>'{sales,count}'<>'3' or r#>>'{sales,cash_count}'<>'1' or r#>>'{sales,credit_count}'<>'2' then raise exception 'Date or sales counts wrong: %',r;end if;
 if r#>>'{sales,subtotal}'<>'9000' or r#>>'{sales,discounts}'<>'500' or r#>>'{sales,total}'<>'8500' or r#>>'{sales,cash_total}'<>'2500' or r#>>'{sales,credit_total}'<>'6000' or r#>>'{sales,cash_received}'<>'3500' or r#>>'{sales,debt_added}'<>'5000' then raise exception 'Sale split or net change calculation wrong';end if;
 if r#>>'{cash,opening}'<>'10000' or r#>>'{cash,inflows}'<>'6000' or r#>>'{cash,outflows}'<>'1300' or r#>>'{cash,closing}'<>'14700' or r#>>'{cash,sales}'<>'3500' or r#>>'{cash,repayments}'<>'2000' or r#>>'{cash,deposits}'<>'500' or r#>>'{cash,withdrawals}'<>'1000' or r#>>'{cash,expenses}'<>'300' or r#>>'{cash,count}'<>'6' then raise exception 'Cash classification or bounds wrong: %',r;end if;
 if r#>>'{debt,opening}'<>'5000' or r#>>'{debt,sale_charges}'<>'5000' or r#>>'{debt,manual_charges}'<>'1000' or r#>>'{debt,repayments}'<>'2000' or r#>>'{debt,closing}'<>'9000' then raise exception 'Debt arithmetic wrong';end if;
 if r#>>'{purchases,count}'<>'1' or r#>>'{purchases,total}'<>'2000' then raise exception 'Purchase bounds wrong';end if;
 r:=public.get_daily_report('2026-05-04');if r#>>'{cash,opening}'<>'15400' or r#>>'{cash,closing}'<>'15400' or r#>>'{debt,opening}'<>'9800' or r#>>'{debt,closing}'<>'9800' or r#>>'{sales,total}'<>'0' or r#>>'{purchases,count}'<>'0' or r#>>'{cash,count}'<>'0' then raise exception 'Empty day lost opening balances or invented activity';end if;
 r:=public.get_daily_report('2026-04-30');if r#>>'{cash,opening}'<>'0' or r#>>'{debt,opening}'<>'0' then raise exception 'Before-first day not empty';end if;
 begin perform public.get_daily_report(null);raise exception 'Null day accepted';exception when raise_exception then if sqlerrm<>'report_day_required' then raise;end if;end;
 if (select balance from public.cash_accounts)<>15400 or (select balance from public.customer_balances)<>9800 or (select count(*) from public.sales)<>3 then raise exception 'Read report changed data';end if;
end $$;
reset role;
-- Exercise exact aggregates above Number.MAX_SAFE_INTEGER with valid bounded cycles.
select set_config('request.jwt.claims',json_build_object('sub',current_setting('dr.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare r jsonb;begin
 r:=public.get_daily_report('2026-05-02');if r#>>'{sales,total}'<>'0' or r#>>'{cash,opening}'<>'0' or r#>>'{debt,closing}'<>'0' or r#>>'{purchases,total}'<>'0' then raise exception 'Cross-owner report leak';end if;
 for n in 1..100 loop
  perform public.post_cash_entry(gen_random_uuid(),'deposit',100000000000000,'exact in');
  perform public.post_cash_entry(gen_random_uuid(),'withdrawal',100000000000000,'exact out');
 end loop;
 r:=public.get_daily_report((now() at time zone 'Asia/Baghdad')::date);
 if r#>>'{cash,inflows}'<>'10000000000000000' or r#>>'{cash,outflows}'<>'10000000000000000' or r#>>'{cash,closing}'<>'0' or jsonb_typeof(r#>'{cash,inflows}')<>'string' then raise exception 'Lifetime-sized daily totals lost precision';end if;
end $$;
reset role;
set local role anon;
do $$ begin begin perform public.get_daily_report('2026-05-02');raise exception 'Anonymous report allowed';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'PASS: Baghdad midnight bounds, cash/full/partial credit splits, net cash after change, manual charges, repayments, outflows, opening/closing balances, purchases, empty days, exact strings, no writes and RLS' as verification;
rollback;
