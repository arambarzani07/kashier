-- All fixtures and financial records are rolled back.
begin;
select set_config('prv.a',gen_random_uuid()::text,true),set_config('prv.b',gen_random_uuid()::text,true),set_config('prv.supplier',gen_random_uuid()::text,true),set_config('prv.p1',gen_random_uuid()::text,true),set_config('prv.p2',gen_random_uuid()::text,true),set_config('prv.cash_purchase',gen_random_uuid()::text,true),set_config('prv.cash_reverse',gen_random_uuid()::text,true),set_config('prv.untracked_purchase',gen_random_uuid()::text,true),set_config('prv.untracked_reverse',gen_random_uuid()::text,true),set_config('prv.credit_purchase',gen_random_uuid()::text,true),set_config('prv.short_purchase',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('prv.a')::uuid,'purchase-reversal-a@example.invalid'),(current_setting('prv.b')::uuid,'purchase-reversal-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('prv.a'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.products(id,name,sale_price) values(current_setting('prv.p1')::uuid,'purchase reversal p1',8000),(current_setting('prv.p2')::uuid,'purchase reversal p2',7000);
insert into public.suppliers(id,name,phone) values(current_setting('prv.supplier')::uuid,'purchase reversal supplier','000');
do $$
declare
 tracked_items jsonb:=jsonb_build_array(jsonb_build_object('product_id',current_setting('prv.p1'),'quantity_units',2000,'unit_cost',5000));
 untracked_items jsonb:=jsonb_build_array(jsonb_build_object('product_id',current_setting('prv.p2'),'quantity_units',3000,'unit_cost',4000));
 credit_items jsonb:=jsonb_build_array(jsonb_build_object('product_id',current_setting('prv.p1'),'quantity_units',1000,'unit_cost',5000));
 short_items jsonb:=jsonb_build_array(jsonb_build_object('product_id',current_setting('prv.p2'),'quantity_units',1000,'unit_cost',4000));
 sale_items jsonb:=jsonb_build_array(jsonb_build_object('product_id',current_setting('prv.p2'),'quantity_units',500,'expected_price',7000));
 p jsonb;r jsonb;daily jsonb;stmt jsonb;before_cash bigint;
begin
 perform public.post_cash_entry(gen_random_uuid(),'deposit',100000,'fixture opening cash');
 p:=public.post_supplier_purchase(current_setting('prv.cash_purchase')::uuid,tracked_items,current_setting('prv.supplier')::uuid,10000,'CASH-1','full cash tracked');
 if (p->>'total')::bigint<>10000 or (select quantity_units from public.product_stock where product_id=current_setting('prv.p1')::uuid)<>2000 or (select balance from public.cash_accounts)<>90000 then raise exception 'tracked cash purchase setup wrong';end if;
 r:=public.post_purchase_reversal(current_setting('prv.cash_reverse')::uuid,current_setting('prv.cash_purchase')::uuid,'supplier accepted full return');
 if (r->>'cash_refund')::bigint<>10000 or r->>'accounting_mode'<>'tracked' or (select quantity_units from public.product_stock where product_id=current_setting('prv.p1')::uuid)<>0 or (select balance from public.cash_accounts)<>100000 then raise exception 'tracked reversal balances wrong';end if;
 if public.post_purchase_reversal(current_setting('prv.cash_reverse')::uuid,current_setting('prv.cash_purchase')::uuid,'supplier accepted full return')<>r or (select count(*) from public.purchase_reversals where purchase_id=current_setting('prv.cash_purchase')::uuid)<>1 then raise exception 'tracked reversal retry failed';end if;
 begin perform public.post_purchase_reversal(gen_random_uuid(),current_setting('prv.cash_purchase')::uuid,'duplicate');raise exception 'duplicate purchase reversal allowed';exception when raise_exception then if sqlerrm<>'purchase_reversal_already_exists' then raise;end if;end;
 if (select count(*) from public.cash_movements where kind='supplier_refund' and purchase_reversal_id=current_setting('prv.cash_reverse')::uuid)<>1 then raise exception 'supplier refund source missing';end if;
 if (select count(*) from public.stock_movements where purchase_reversal_id=current_setting('prv.cash_reverse')::uuid)<>1 then raise exception 'tracked reversal stock source missing';end if;

 p:=public.post_purchase(current_setting('prv.untracked_purchase')::uuid,untracked_items,'legacy supplier','U-1','stock only');
 before_cash:=(select balance from public.cash_accounts);
 r:=public.post_purchase_reversal(current_setting('prv.untracked_reverse')::uuid,current_setting('prv.untracked_purchase')::uuid,'return stock only');
 if (r->>'cash_refund')::bigint<>0 or r->>'accounting_mode'<>'untracked' or (select quantity_units from public.product_stock where product_id=current_setting('prv.p2')::uuid)<>0 or (select balance from public.cash_accounts)<>before_cash then raise exception 'untracked reversal wrong';end if;
 if exists(select 1 from public.cash_movements where purchase_reversal_id=current_setting('prv.untracked_reverse')::uuid) then raise exception 'untracked reversal invented cash';end if;

 p:=public.post_supplier_purchase(current_setting('prv.credit_purchase')::uuid,credit_items,current_setting('prv.supplier')::uuid,1000,'CR-1','credit purchase');
 before_cash:=(select balance from public.cash_accounts);
 begin perform public.post_purchase_reversal(gen_random_uuid(),current_setting('prv.credit_purchase')::uuid,'unsafe credit return');raise exception 'credit purchase reversal allowed';exception when raise_exception then if sqlerrm<>'purchase_reversal_credit_unsupported' then raise;end if;end;
 if (select quantity_units from public.product_stock where product_id=current_setting('prv.p1')::uuid)<>1000 or (select balance from public.cash_accounts)<>before_cash or exists(select 1 from public.purchase_reversals where purchase_id=current_setting('prv.credit_purchase')::uuid) then raise exception 'credit rejection not atomic';end if;

 p:=public.post_purchase(current_setting('prv.short_purchase')::uuid,short_items,'legacy supplier','S-1','will be consumed');
 perform public.post_cash_sale(gen_random_uuid(),sale_items,0,3500,'consume stock','');
 before_cash:=(select balance from public.cash_accounts);
 begin perform public.post_purchase_reversal(gen_random_uuid(),current_setting('prv.short_purchase')::uuid,'not enough stock');raise exception 'insufficient-stock reversal allowed';exception when raise_exception then if sqlerrm<>'purchase_reversal_stock_insufficient' then raise;end if;end;
 if (select quantity_units from public.product_stock where product_id=current_setting('prv.p2')::uuid)<>500 or (select balance from public.cash_accounts)<>before_cash or exists(select 1 from public.purchase_reversals where purchase_id=current_setting('prv.short_purchase')::uuid) then raise exception 'stock rejection not atomic';end if;

 if (select count(*) from public.purchase_reversals)<>2 then raise exception 'purchase reversal count wrong';end if;
 if (select count(*) from public.stock_movements where purchase_reversal_id is not null)<>2 then raise exception 'purchase reversal stock ledgers wrong';end if;
 if (select count(*) from public.cash_movements where kind='supplier_refund')<>1 then raise exception 'supplier refund ledger count wrong';end if;
 if (public.get_cash_summary()->>'supplier_refunds')::bigint<>10000 then raise exception 'cash summary supplier refund wrong';end if;
 stmt:=public.get_cash_statement((now() at time zone 'Asia/Baghdad')::date,(now() at time zone 'Asia/Baghdad')::date);
 if (stmt->'by_kind'->>'supplier_refund')::bigint<>10000 or not exists(select 1 from jsonb_array_elements(stmt->'rows') x where x->>'kind'='supplier_refund' and x->>'purchase_id'=current_setting('prv.cash_purchase')) then raise exception 'cash statement supplier refund wrong';end if;
 daily:=public.get_daily_report((now() at time zone 'Asia/Baghdad')::date);
 if (daily->'purchase_returns'->>'count')::bigint<>2 or (daily->'purchase_returns'->>'total')::bigint<>22000 or (daily->'purchase_returns'->>'cash_refund')::bigint<>10000 or (daily->'purchase_returns'->>'untracked_count')::bigint<>1 or (daily->'cash'->>'supplier_refunds')::bigint<>10000 then raise exception 'daily purchase reversal totals wrong';end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('prv.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin
 begin perform public.post_purchase_reversal(gen_random_uuid(),current_setting('prv.cash_purchase')::uuid,'other owner');raise exception 'cross owner purchase reversal allowed';exception when raise_exception then if sqlerrm<>'purchase_reversal_unavailable' then raise;end if;end;
 if (select count(*) from public.purchase_reversals)<>0 then raise exception 'purchase reversal RLS leak';end if;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.post_purchase_reversal(gen_random_uuid(),gen_random_uuid(),'anon');raise exception 'anonymous purchase reversal allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: tracked cash/untracked purchase reversals, stock/cash atomicity, retry, duplicate, credit and stock guards, reports and RLS' as verification;
rollback;