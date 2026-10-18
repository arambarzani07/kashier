begin;
select set_config('gp.owner',gen_random_uuid()::text,true),set_config('gp.other',gen_random_uuid()::text,true),set_config('gp.product',gen_random_uuid()::text,true),set_config('gp.tiny',gen_random_uuid()::text,true),set_config('gp.legacy',gen_random_uuid()::text,true),set_config('gp.history',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('gp.owner')::uuid,'gross-a@example.invalid'),(current_setting('gp.other')::uuid,'gross-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('gp.owner'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.products(id,name,sale_price) values(current_setting('gp.product')::uuid,'weighted item',1000),(current_setting('gp.tiny')::uuid,'fractional item',1000),(current_setting('gp.legacy')::uuid,'unknown opening',1000),(current_setting('gp.history')::uuid,'legacy sale',1000);
reset role;
-- A pre-existing physical opening balance has no cost baseline. It is never backfilled.
insert into public.product_stock(product_id,owner_id,quantity_units) values(current_setting('gp.legacy')::uuid,current_setting('gp.owner')::uuid,1000);
set local role authenticated;
do $$declare p uuid:=current_setting('gp.product')::uuid;t uuid:=current_setting('gp.tiny')::uuid;l uuid:=current_setting('gp.legacy')::uuid;h uuid:=current_setting('gp.history')::uuid;buy jsonb;s1 jsonb;s2 jsonb;s3 jsonb;tiny_sale jsonb;old_sale jsonb;x jsonb;y jsonb;v numeric;ver bigint;ret uuid;today date:=(now() at time zone 'Asia/Baghdad')::date;begin
 x:=public.get_gross_profit_report(today,today);if x->>'count'<>'0' or x->>'complete'<>'true' then raise exception 'empty report';end if;
 buy:=public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',2000,'unit_cost',500)),'','','');
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',1000,'unit_cost',800)),'','','');
 if (select value_iqd from public.inventory_cost_state where product_id=p)<>1800 then raise exception 'purchase valuation';end if;
 s1:=public.post_cash_sale(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',1000,'expected_price',1000)),0,1000,'','');
 if (select -c.value_delta from public.inventory_cost_movements c join public.stock_movements m on m.id=c.id where m.sale_id=(s1->>'id')::uuid)<>600 then raise exception 'weighted average not applied';end if;
 x:=public.get_gross_profit_report(today,today);if x->>'known_cogs'<>'600' or x->>'known_margin'<>'400' or x->>'complete'<>'true' then raise exception 'known margin';end if;
 -- Request replay must not duplicate valuation or cost records.
 v:=(select count(*) from public.inventory_cost_movements);
 perform public.post_cash_sale((s1->>'id')::uuid,jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',1000,'expected_price',1000)),0,1000,'','');if (select count(*) from public.inventory_cost_movements)<>v then raise exception 'cost replay duplicated';end if;
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',1000,'unit_cost',1200)),'','','');
 s2:=public.post_cash_sale(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',1000,'expected_price',1000)),0,1000,'','');
 if (select value_iqd from public.inventory_cost_state where product_id=p)<>1600 then raise exception 'new weighted average';end if;
 ret:=gen_random_uuid();perform public.post_sale_reversal(ret,(s1->>'id')::uuid,'original cost return');
 if (select value_iqd from public.inventory_cost_state where product_id=p)<>2200 then raise exception 'return used current cost instead of original';end if;
 perform public.post_sale_reversal(gen_random_uuid(),(s2->>'id')::uuid,'second return');
 if (select value_iqd from public.inventory_cost_state where product_id=p)<>3000 then raise exception 'full returns conservation';end if;
 x:=public.get_gross_profit_report(today,today);if x->>'revenue'<>'0' or x->>'known_cogs'<>'0' or x->>'known_margin'<>'0' then raise exception 'return report signs';end if;
 s3:=public.post_cash_sale(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',1500,'expected_price',1000)),3,1497,'','discounted');
 for i in 1..3 loop perform public.post_sale_return(gen_random_uuid(),(s3->>'id')::uuid,'partial',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',500)));end loop;
 if (select value_iqd from public.inventory_cost_state where product_id=p)<>3000 then raise exception 'partial cost conservation';end if;
 -- Purchase returns remove average inventory value; supplier cash price never becomes COGS.
 perform public.post_purchase_return(gen_random_uuid(),(buy->>'id')::uuid,'purchase return',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',500)));
 if (select value_iqd from public.inventory_cost_state where product_id=p)<>2625 then raise exception 'purchase return average removal';end if;
 x:=public.get_gross_profit_report(today,today);if x->>'known_margin'<>'0' then raise exception 'purchase return fabricated gross profit';end if;
 -- Fractional quantities: cumulative rounding restores exactly the original two IQD cost (1,0,1).
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',t,'quantity_units',3,'unit_cost',500)),'','','');
 tiny_sale:=public.post_cash_sale(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',t,'quantity_units',3,'expected_price',1000)),0,3,'','tiny');
 for i in 1..3 loop perform public.post_sale_return(gen_random_uuid(),(tiny_sale->>'id')::uuid,'one thousandth',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',1)));end loop;
 if (select value_iqd from public.inventory_cost_state where product_id=t)<>2 or (select sum(c.value_delta) from public.inventory_cost_movements c join public.stock_movements m on m.id=c.id where m.product_id=t and(m.sale_id is not null or m.return_id is not null))<>0 then raise exception 'fractional cumulative rounding';end if;
 -- Unknown opening remains unknown even if a later purchase price is available.
 old_sale:=public.post_cash_sale(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',l,'quantity_units',1000,'expected_price',1000)),0,1000,'','opening unknown');
 if (select c.value_delta from public.inventory_cost_movements c join public.stock_movements m on m.id=c.id where m.sale_id=(old_sale->>'id')::uuid) is not null then raise exception 'opening cost guessed';end if;
 if (select value_iqd from public.inventory_cost_state where product_id=l)<>0 then raise exception 'depletion reset';end if;
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',l,'quantity_units',1000,'unit_cost',300)),'','','');
 if (select value_iqd from public.inventory_cost_state where product_id=l)<>300 then raise exception 'cost did not restart after empty';end if;
 y:=public.post_cash_sale(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',l,'quantity_units',1000,'expected_price',1000)),0,1000,'','known after empty');
 if (select -c.value_delta from public.inventory_cost_movements c join public.stock_movements m on m.id=c.id where m.sale_id=(y->>'id')::uuid)<>300 then raise exception 'future cost after empty';end if;
 perform public.post_sale_reversal(gen_random_uuid(),(old_sale->>'id')::uuid,'unknown return');
 if (select value_iqd from public.inventory_cost_state where product_id=l) is not null then raise exception 'unknown return failed to taint inventory';end if;
 -- Positive stock corrections taint a known pool; negative corrections keep average cost when known.
 select max(movement_no) into ver from public.stock_movements where product_id=p;
 perform public.post_stock_waste(gen_random_uuid(),p,3500,ver,500,'waste');if (select value_iqd from public.inventory_cost_state where product_id=p)<>2250 then raise exception 'waste average removal';end if;
 select max(movement_no) into ver from public.stock_movements where product_id=p;
 perform public.post_stock_adjustment(gen_random_uuid(),p,3000,ver,4000,'found stock');if (select value_iqd from public.inventory_cost_state where product_id=p) is not null then raise exception 'positive adjustment cost invented';end if;
 x:=public.get_gross_profit_report(today,today);if x->>'complete'<>'false' or (x->>'known_count')::integer=(x->>'count')::integer then raise exception 'unknown coverage not shown';end if;
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',h,'quantity_units',1000,'unit_cost',500)),'','','');
 y:=public.post_cash_sale(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',h,'quantity_units',1000,'expected_price',1000)),0,1000,'','historical');perform set_config('gp.historical_sale',y->>'id',true);
 begin perform public.get_gross_profit_report(today,today+366);raise exception 'range accepted';exception when raise_exception then if sqlerrm<>'profit_invalid_range' then raise;end if;end;
 x:=public.export_owner_data();if x->>'version'<>'6' or (select count(*) from jsonb_object_keys(x->'tables'))<>27 or not(x->'tables'?'inventory_cost_movements') then raise exception 'cost export incomplete';end if;
 begin update public.inventory_cost_state set value_iqd=0;raise exception 'state tamper';exception when insufficient_privilege then null;end;
 begin delete from public.inventory_cost_movements;raise exception 'cost delete';exception when insufficient_privilege then null;end;
end $$;
reset role;
-- Simulate a legacy sale with no recorded snapshot, without changing any original receipt.
delete from public.inventory_cost_movements c using public.stock_movements m where c.id=m.id and m.sale_id=current_setting('gp.historical_sale')::uuid;
set local role authenticated;
do $$declare x jsonb;today date:=(now() at time zone 'Asia/Baghdad')::date;begin
 x:=public.get_gross_profit_report(today,today);if not exists(select 1 from jsonb_array_elements(x->'rows') item where item->>'sale_id'=current_setting('gp.historical_sale') and item->>'coverage'='legacy-no-cost-snapshot' and item->'cogs'='null'::jsonb and item->'margin'='null'::jsonb) then raise exception 'historical profit invented';end if;
end $$;
reset role;set constraints all immediate;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('gp.other'),'role','authenticated')::text,true);set local role authenticated;
do $$declare today date:=(now() at time zone 'Asia/Baghdad')::date;begin
 if exists(select 1 from public.inventory_cost_state) or exists(select 1 from public.inventory_cost_movements) or public.get_gross_profit_report(today,today)->>'count'<>'0' then raise exception 'cost RLS leak';end if;
end $$;
reset role;select set_config('request.jwt.claims','{}',true);set local role authenticated;
do $$begin begin perform public.get_gross_profit_report(current_date,current_date);raise exception 'null uid';exception when raise_exception then if sqlerrm<>'profit_auth_required' then raise;end if;end;end $$;
reset role;set local role anon;
do $$begin begin perform public.get_gross_profit_report(current_date,current_date);raise exception 'anon read';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'PASS: forward weighted average, replay, original return costs, cumulative fractional rounding, purchase returns, unknown opening/return/adjustment, legacy coverage, export v6, owner isolation/grants' as verification;
rollback;
