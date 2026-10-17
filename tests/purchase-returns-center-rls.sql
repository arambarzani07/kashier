-- Rollback-only verification for Purchase Returns Center reporting and isolation.
begin;
select set_config('prc.a',gen_random_uuid()::text,true),set_config('prc.b',gen_random_uuid()::text,true),set_config('prc.s',gen_random_uuid()::text,true),set_config('prc.p',gen_random_uuid()::text,true),set_config('prc.full_purchase',gen_random_uuid()::text,true),set_config('prc.partial_purchase',gen_random_uuid()::text,true),set_config('prc.untracked_purchase',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('prc.a')::uuid,'prc-a@example.invalid'),(current_setting('prc.b')::uuid,'prc-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('prc.a'),'role','authenticated')::text,true);set local role authenticated;
insert into public.products(id,name,sale_price) values(current_setting('prc.p')::uuid,'Returns center product',9000);
insert into public.suppliers(id,name,phone) values(current_setting('prc.s')::uuid,'Center Supplier','000');
do $$
declare
 p uuid:=current_setting('prc.p')::uuid;
 s uuid:=current_setting('prc.s')::uuid;
 pf uuid:=current_setting('prc.full_purchase')::uuid;
 pp uuid:=current_setting('prc.partial_purchase')::uuid;
 pu uuid:=current_setting('prc.untracked_purchase')::uuid;
 full_id uuid:=gen_random_uuid();part_id uuid:=gen_random_uuid();stock_id uuid:=gen_random_uuid();
 r jsonb;today date:=(now() at time zone 'Asia/Baghdad')::date;receipt text;
begin
 perform public.post_cash_entry(gen_random_uuid(),'deposit',100000,'returns center cash');
 perform public.post_supplier_purchase(pf,jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',1000,'unit_cost',5000)),s,5000,'CENTER-FULL','full fixture');
 perform public.post_purchase_reversal(full_id,pf,'full return fixture');
 perform public.post_supplier_purchase(pp,jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',3000,'unit_cost',3333)),s,9999,'CENTER-PART','partial fixture');
 perform public.post_purchase_return(part_id,pp,'partial return fixture',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',1000)));
 perform public.post_purchase(pu,jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',1000,'unit_cost',4000)),'Legacy Supply','CENTER-LEG','legacy fixture');
 perform public.post_purchase_return(stock_id,pu,'stock only fixture',jsonb_build_array(jsonb_build_object('line_no',1,'quantity_units',500)));
 r:=public.get_purchase_returns_report('all',today,today,null,null,null,null,0,50);
 if (r->>'count')::int<>3 then raise exception 'all count wrong: %',r;end if;
 r:=public.get_purchase_returns_report('full',null,null,null,null,null,null,0,50);
 if (r->>'count')::int<>1 or r->'rows'->0->>'kind'<>'full' then raise exception 'full filter wrong';end if;
 r:=public.get_purchase_returns_report('partial',null,null,'Center Supplier',null,null,null,0,50);
 if (r->>'count')::int<>1 or r->'rows'->0->>'invoice_no'<>'CENTER-PART' then raise exception 'supplier/type filter wrong: %',r;end if;
 r:=public.get_purchase_returns_report('all',null,null,'Legacy',null,null,null,0,50);
 if (r->>'count')::int<>1 or (r->'rows'->0->>'cash_refund')::bigint<>0 then raise exception 'legacy supplier filter wrong: %',r;end if;
 r:=public.get_purchase_returns_report('all',null,null,null,'CENTER-PART',null,null,0,50);
 if (r->>'count')::int<>1 then raise exception 'invoice query wrong';end if;
 select receipt_no::text into receipt from public.purchases where id=pf;
 r:=public.get_purchase_returns_report('all',null,null,null,receipt,null,null,0,50);
 if (r->>'count')::int<>1 or r->'rows'->0->>'purchase_id'<>pf::text then raise exception 'receipt query wrong';end if;
 r:=public.get_purchase_returns_report('all',null,null,null,null,3000,4000,0,50);
 if (r->>'count')::int<>1 or (r->'rows'->0->>'total')::bigint<>3333 then raise exception 'amount range wrong: %',r;end if;
 begin perform public.get_purchase_returns_report('all',null,null,null,null,5000,4000,0,50);raise exception 'invalid range allowed';exception when raise_exception then if sqlerrm<>'purchase_returns_invalid_amount_range' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('prc.b'),'role','authenticated')::text,true);set local role authenticated;
do $$ declare r jsonb; begin r:=public.get_purchase_returns_report('all',null,null,null,null,null,null,0,50);if (r->>'count')::int<>0 then raise exception 'cross-owner leak';end if;end $$;
reset role;set local role anon;
do $$ begin begin perform public.get_purchase_returns_report('all',null,null,null,null,null,null,0,50);raise exception 'anon allowed';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'PASS: purchase returns center kind/date/supplier/query/amount filters, source fields, owner isolation and anon block' verification;
rollback;