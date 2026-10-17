-- All fixtures and financial records are rolled back.
begin;
select set_config('pr.a',gen_random_uuid()::text,true),set_config('pr.b',gen_random_uuid()::text,true),set_config('pr.customer',gen_random_uuid()::text,true),set_config('pr.product',gen_random_uuid()::text,true),set_config('pr.sale',gen_random_uuid()::text,true),set_config('pr.r1',gen_random_uuid()::text,true),set_config('pr.r2',gen_random_uuid()::text,true),set_config('pr.sale2',gen_random_uuid()::text,true),set_config('pr.rev2',gen_random_uuid()::text,true),set_config('pr.credit',gen_random_uuid()::text,true),set_config('pr.discount',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('pr.a')::uuid,'partial-return-a@example.invalid'),(current_setting('pr.b')::uuid,'partial-return-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('pr.a'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.customers(id,name) values(current_setting('pr.customer')::uuid,'partial return customer');
insert into public.products(id,name,sale_price) values(current_setting('pr.product')::uuid,'rounding product',3333);
do $$
declare
 items jsonb; s jsonb; s2 jsonb; cr jsonb; ds jsonb; r1 jsonb; r2 jsonb; rd jsonb; rv jsonb; daily jsonb; discount_line jsonb;
 p uuid:=current_setting('pr.product')::uuid; c uuid:=current_setting('pr.customer')::uuid;
begin
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',20000,'unit_cost',2000)),'','','');
 items:=jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',3000,'expected_price',3333));
 s:=public.post_cash_sale(current_setting('pr.sale')::uuid,items,0,12000,'cash partial','');
 if (s->>'total')::bigint<>9999 or (select quantity_units from public.product_stock where product_id=p)<>17000 or (select balance from public.cash_accounts)<>9999 then raise exception 'partial setup wrong'; end if;
 r1:=public.post_sale_return(current_setting('pr.r1')::uuid,(s->>'id')::uuid,'first half',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',500)));
 if (r1->>'total')::bigint<>1667 or (select quantity_units from public.product_stock where product_id=p)<>17500 or (select balance from public.cash_accounts)<>8332 then raise exception 'first partial return wrong'; end if;
 if public.post_sale_return(current_setting('pr.r1')::uuid,(s->>'id')::uuid,'first half',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',500)))<>r1 or (select count(*) from public.sale_returns where sale_id=(s->>'id')::uuid)<>1 then raise exception 'partial retry failed'; end if;
 begin perform public.post_sale_return(current_setting('pr.r1')::uuid,(s->>'id')::uuid,'changed reason',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',500))); raise exception 'return request conflict allowed'; exception when raise_exception then if sqlerrm<>'return_request_conflict' then raise; end if; end;
 r2:=public.post_sale_return(current_setting('pr.r2')::uuid,(s->>'id')::uuid,'second half',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',500)));
 if (r2->>'total')::bigint<>1666 or (r1->>'total')::bigint+(r2->>'total')::bigint<>3333 then raise exception 'cumulative rounding wrong'; end if;
 if (select quantity_units from public.product_stock where product_id=p)<>18000 or (select balance from public.cash_accounts)<>6666 then raise exception 'second partial balances wrong'; end if;
 begin perform public.post_sale_return(gen_random_uuid(),(s->>'id')::uuid,'too much',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',2500))); raise exception 'over return allowed'; exception when raise_exception then if sqlerrm<>'return_quantity_exceeds_remaining' then raise; end if; end;
 begin perform public.post_sale_return(gen_random_uuid(),(s->>'id')::uuid,'duplicate line',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',100),jsonb_build_object('line_no',1,'quantity_units',100))); raise exception 'duplicate return line allowed'; exception when raise_exception then if sqlerrm<>'return_duplicate_line' then raise; end if; end;
 begin perform public.post_sale_reversal(gen_random_uuid(),(s->>'id')::uuid,'full after partial'); raise exception 'full reversal after partial allowed'; exception when raise_exception then if sqlerrm<>'reversal_partial_returns_exist' then raise; end if; end;

 items:=jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',1000,'expected_price',3333));
 s2:=public.post_cash_sale(current_setting('pr.sale2')::uuid,items,0,4000,'full first','');
 rv:=public.post_sale_reversal(current_setting('pr.rev2')::uuid,(s2->>'id')::uuid,'full first');
 begin perform public.post_sale_return(gen_random_uuid(),(s2->>'id')::uuid,'partial after full',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',100))); raise exception 'partial after full allowed'; exception when raise_exception then if sqlerrm<>'return_sale_reversed' then raise; end if; end;

 cr:=public.post_credit_sale(current_setting('pr.credit')::uuid,items,0,1000,c,'credit');
 begin perform public.post_sale_return(gen_random_uuid(),(cr->>'id')::uuid,'credit partial',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',100))); raise exception 'credit partial allowed'; exception when raise_exception then if sqlerrm<>'return_credit_not_supported' then raise; end if; end;

 ds:=public.post_cash_sale(current_setting('pr.discount')::uuid,items,333,4000,'discounted','');
 rd:=public.post_sale_return(gen_random_uuid(),(ds->>'id')::uuid,'discount partial',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',100)));
 discount_line:=rd->'lines'->0;
 if (rd->>'total')::bigint<>300 or (discount_line->>'allocated_discount')::bigint<>333 or (discount_line->>'net_line_total')::bigint<>3000 or (discount_line->>'line_total')::bigint<>300 then raise exception 'discount-aware partial return wrong: %',rd; end if;

 if (select count(*) from public.sale_returns)<>3 or (select count(*) from public.stock_movements where return_id is not null)<>3 or (select count(*) from public.cash_movements where return_id is not null and kind='refund')<>3 then raise exception 'partial source ledgers wrong'; end if;
 daily:=public.get_daily_report((now() at time zone 'Asia/Baghdad')::date);
 if (daily->'returns'->>'count')::bigint<>4 or (daily->'returns'->>'cash_refund')::bigint<>6966 or (daily->'returns'->>'debt_reversed')::bigint<>0 then raise exception 'daily partial totals wrong: %',daily->'returns'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('pr.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 if (select count(*) from public.sale_returns)<>0 then raise exception 'sale return RLS leak'; end if;
 begin perform public.post_sale_return(gen_random_uuid(),current_setting('pr.sale')::uuid,'other owner',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',100))); raise exception 'cross owner return allowed'; exception when raise_exception then if sqlerrm<>'return_sale_unavailable' then raise; end if; end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.post_sale_return(gen_random_uuid(),gen_random_uuid(),'anon',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',100))); raise exception 'anonymous return allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: cash partial returns, discounted net allocation, cumulative rounding, inventory, refunds, retry/conflict, credit guard, reversal conflicts, scope guards, daily report and RLS' as verification;
rollback;
