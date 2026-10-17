begin;
select set_config('sr.a',gen_random_uuid()::text,true),set_config('sr.b',gen_random_uuid()::text,true),set_config('sr.p1',gen_random_uuid()::text,true),set_config('sr.p2',gen_random_uuid()::text,true),set_config('sr.c',gen_random_uuid()::text,true),set_config('sr.s1',gen_random_uuid()::text,true),set_config('sr.s2',gen_random_uuid()::text,true),set_config('sr.s3',gen_random_uuid()::text,true),set_config('sr.big',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('sr.a')::uuid,'sales-report-a@example.invalid'),(current_setting('sr.b')::uuid,'sales-report-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('sr.a'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.products(id,name,barcode,sale_price) values(current_setting('sr.p1')::uuid,'P1 original','001234',1001),(current_setting('sr.p2')::uuid,'P2 original','009999',2000);
insert into public.customers(id,name) values(current_setting('sr.c')::uuid,'Report credit customer');
do $$declare a uuid:=current_setting('sr.p1')::uuid;b uuid:=current_setting('sr.p2')::uuid;begin
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',a,'quantity_units',20000,'unit_cost',500),jsonb_build_object('product_id',b,'quantity_units',20000,'unit_cost',500)),'','','');
 perform public.post_cash_sale(current_setting('sr.s1')::uuid,jsonb_build_array(jsonb_build_object('product_id',a,'quantity_units',1000,'expected_price',1001),jsonb_build_object('product_id',b,'quantity_units',1000,'expected_price',2000)),1000,2001,'','');
 perform public.post_cash_sale(current_setting('sr.s2')::uuid,jsonb_build_array(jsonb_build_object('product_id',a,'quantity_units',1001,'expected_price',1001)),0,1002,'','');
 perform public.post_credit_sale(current_setting('sr.s3')::uuid,jsonb_build_array(jsonb_build_object('product_id',b,'quantity_units',1000,'expected_price',2000)),0,500,current_setting('sr.c')::uuid,'');
 perform public.post_sale_reversal(gen_random_uuid(),current_setting('sr.s1')::uuid,'Full discounted reversal');
 perform public.post_sale_return(gen_random_uuid(),current_setting('sr.s2')::uuid,'First fractional return',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',1)));
 perform public.post_sale_return(gen_random_uuid(),current_setting('sr.s2')::uuid,'Second fractional return',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',500)));
end $$;
reset role;
update public.sales set created_at=case when id=current_setting('sr.s1')::uuid then '2026-04-30T21:00:00Z'::timestamptz when id=current_setting('sr.s2')::uuid then '2026-05-01T10:00:00Z'::timestamptz else '2026-05-01T20:59:59.999999Z'::timestamptz end where owner_id=current_setting('sr.a')::uuid;
update public.sale_reversals set created_at='2026-05-02T01:00:00Z' where owner_id=current_setting('sr.a')::uuid;
update public.sale_returns set created_at='2026-05-02T02:00:00Z' where owner_id=current_setting('sr.a')::uuid;
set local role authenticated;
update public.products set name='Current renamed catalog' where id=current_setting('sr.p1')::uuid;
do $$declare v jsonb;r jsonb;before_cash bigint;before_stock bigint;begin
 select count(*) into before_cash from public.cash_movements;select count(*) into before_stock from public.stock_movements;
 v:=public.get_sales_product_report('2026-05-01','2026-05-01');
 if v#>>'{summary,receipt_count}'<>'3' or v#>>'{summary,gross}'<>'6003' or v#>>'{summary,discounts}'<>'1000' or v#>>'{summary,sold_total}'<>'5003' or v#>>'{summary,returned_total}'<>'0' then raise exception 'sales summary/boundary incorrect: %',v;end if;
 select value into r from jsonb_array_elements(v->'rows') where value->>'product_id'=current_setting('sr.p1');
 if r->>'sold_total'<>'1670' or r->>'sold_units'<>'2001' or r->>'name'<>'P1 original' or r->>'barcode'<>'001234' then raise exception 'discount/product snapshot incorrect: %',r;end if;
 v:=public.get_sales_product_report('2026-05-02','2026-05-02');
 if v#>>'{summary,receipt_count}'<>'0' or v#>>'{summary,return_count}'<>'3' or v#>>'{summary,returned_total}'<>'2503' or v#>>'{summary,net_total}'<>'-2503' then raise exception 'returns-only period incorrect: %',v;end if;
 select value into r from jsonb_array_elements(v->'rows') where value->>'product_id'=current_setting('sr.p1');
 if r->>'returned_total'<>'1170' or r->>'net_units'<>'-1501' then raise exception 'fractional return rounding incorrect';end if;
 v:=public.get_sales_product_report('2026-05-01','2026-05-02');if v#>>'{summary,net_total}'<>'2500' then raise exception 'combined net incorrect';end if;
 if (public.get_sales_product_report('2026-04-30','2026-04-30')#>>'{summary,receipt_count}')<>'0' then raise exception 'lower boundary incorrect';end if;
 begin perform public.get_sales_product_report('2026-05-02','2026-05-01');raise exception 'reverse dates accepted';exception when raise_exception then if sqlerrm<>'sales_report_invalid_range' then raise;end if;end;
 if (select count(*) from public.cash_movements)<>before_cash or (select count(*) from public.stock_movements)<>before_stock then raise exception 'report wrote ledgers';end if;
end $$;
-- Regression for NUMERIC division rounding near a large integer. Integer div() must allocate exactly two IQD to P1.
update public.products set sale_price=1000000000 where id in(current_setting('sr.p1')::uuid,current_setting('sr.p2')::uuid);
do $$declare p uuid;v record;items jsonb;begin
 for p in select id from public.products loop
  select quantity_units,stock_version into v from public.stock_catalog where id=p;
  perform public.post_stock_adjustment(gen_random_uuid(),p,v.quantity_units,v.stock_version::bigint,100000000,'Large amount fixture');
 end loop;
 select jsonb_agg(jsonb_build_object('product_id',case when g<=5 then current_setting('sr.p1') else current_setting('sr.p2') end,'quantity_units',case when g=10 then 9999999 else 10000000 end,'expected_price',1000000000) order by g) into items from generate_series(1,10) g;
 perform public.post_cash_sale(current_setting('sr.big')::uuid,items,99999998999998,2,'','Large discount allocation');
end $$;
reset role;
update public.sales set created_at='2026-06-01T10:00:00Z' where id=current_setting('sr.big')::uuid;
set local role authenticated;
do $$declare v jsonb;r jsonb;begin v:=public.get_sales_product_report('2026-06-01','2026-06-01');select value into r from jsonb_array_elements(v->'rows') where value->>'product_id'=current_setting('sr.p1');if r->>'sold_total'<>'2' or v#>>'{summary,sold_total}'<>'2' then raise exception 'large-integer allocation drifted: %',v;end if;end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('sr.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin if (public.get_sales_product_report('2026-05-01','2026-05-02')->>'count')<>'0' then raise exception 'cross-owner rows exposed';end if;end $$;
reset role;
insert into public.products(owner_id,name,sale_price) select current_setting('sr.b')::uuid,'Sales cap '||g,1000 from generate_series(1,5001) g;
insert into public.sales(id,owner_id,created_at,subtotal,discount,total,received,change_due,lines,request_payload)
select gen_random_uuid(),current_setting('sr.b')::uuid,'2026-07-01T10:00:00Z'::timestamptz,count(*)*1000,0,count(*)*1000,count(*)*1000,0,jsonb_agg(jsonb_build_object('product_id',id,'name',name,'barcode',null,'quantity_units',1000,'unit_price',1000,'line_total',1000)),'{}'::jsonb from (select id,name,(row_number() over(order by id)-1)/200 as batch from public.products where owner_id=current_setting('sr.b')::uuid) p group by batch;
set local role authenticated;
do $$begin begin perform public.get_sales_product_report('2026-07-01','2026-07-01');raise exception 'truncated report accepted';exception when raise_exception then if sqlerrm<>'sales_report_too_many_rows' then raise;end if;end;end $$;
reset role;
do $$begin if has_function_privilege('anon','public.get_sales_product_report(date,date)','execute') then raise exception 'anonymous report exposed';end if;end $$;
rollback;
