-- Administrative verification only. All temporary users/products/sales are rolled back.
begin;
select set_config('kashier.a',gen_random_uuid()::text,true),set_config('kashier.b',gen_random_uuid()::text,true),set_config('kashier.product',gen_random_uuid()::text,true),set_config('kashier.sale',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('kashier.a')::uuid,'sale-rollback-a@example.invalid'),(current_setting('kashier.b')::uuid,'sale-rollback-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('kashier.a'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.products(id,name,barcode,sale_price) values(current_setting('kashier.product')::uuid,'rollback-only','SALE-ROLLBACK',3000);
do $$ declare s jsonb; again jsonb; payload jsonb; n bigint; begin
 payload := jsonb_build_array(jsonb_build_object('product_id',current_setting('kashier.product'),'quantity_units',125,'expected_price',3000));
 s:=public.post_cash_sale(current_setting('kashier.sale')::uuid,payload,75,1000,'rollback customer','rollback note');
 if (s->>'subtotal')::bigint<>375 or (s->>'total')::bigint<>300 or (s->>'change_due')::bigint<>700 then raise exception 'Arithmetic mismatch'; end if;
 again:=public.post_cash_sale(current_setting('kashier.sale')::uuid,payload,75,1000,'rollback customer','rollback note');
 if again<>s or (select count(*) from public.sales)<>1 then raise exception 'Replay duplicated sale'; end if;
 update public.products set name='changed',sale_price=4000 where id=current_setting('kashier.product')::uuid;
 again:=public.post_cash_sale(current_setting('kashier.sale')::uuid,payload,75,1000,'rollback customer','rollback note');
 if again<>s or s->'lines'->0->>'name'<>'rollback-only' then raise exception 'Snapshot changed'; end if;
 begin perform public.post_cash_sale(current_setting('kashier.sale')::uuid,payload,75,2000,'rollback customer','rollback note'); raise exception 'Conflicting replay allowed'; exception when raise_exception then if sqlerrm<>'sale_request_conflict' then raise; end if; end;
 begin perform public.post_cash_sale(gen_random_uuid(),payload,0,1000,'',''); raise exception 'Stale price allowed'; exception when raise_exception then if sqlerrm<>'sale_price_changed' then raise; end if; end;
 payload:=jsonb_build_array(jsonb_build_object('product_id',current_setting('kashier.product'),'quantity_units',1000,'expected_price',4000));
 begin perform public.post_cash_sale(gen_random_uuid(),payload,0,100,'',''); raise exception 'Short payment allowed'; exception when raise_exception then if sqlerrm<>'sale_payment_shortfall' then raise; end if; end;
 begin perform public.post_cash_sale(gen_random_uuid(),payload,5000,10000,'',''); raise exception 'Overdiscount allowed'; exception when raise_exception then if sqlerrm<>'sale_discount_exceeds_total' then raise; end if; end;
 payload:=payload||jsonb_build_array(jsonb_build_object('product_id',gen_random_uuid(),'quantity_units',1000,'expected_price',1000));
 begin perform public.post_cash_sale(gen_random_uuid(),payload,0,10000,'',''); raise exception 'Missing product allowed'; exception when raise_exception then if sqlerrm<>'sale_product_unavailable' then raise; end if; end;
 if (select count(*) from public.sales)<>1 then raise exception 'Failed request left a sale'; end if;
 begin update public.sales set total=0; raise exception 'Direct update allowed'; exception when insufficient_privilege then null; end;
 begin delete from public.sales; raise exception 'Direct delete allowed'; exception when insufficient_privilege then null; end;
 begin insert into public.sales(id,owner_id,subtotal,discount,total,received,change_due,lines,request_payload) values(gen_random_uuid(),current_setting('kashier.a')::uuid,0,0,0,0,0,'[]','{}'); raise exception 'Direct insert allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('kashier.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare payload jsonb; begin
 if (select count(*) from public.sales)<>0 then raise exception 'Other account can read sale'; end if;
 payload:=jsonb_build_array(jsonb_build_object('product_id',current_setting('kashier.product'),'quantity_units',1000,'expected_price',4000));
 begin perform public.post_cash_sale(gen_random_uuid(),payload,0,10000,'',''); raise exception 'Other account can sell product'; exception when raise_exception then if sqlerrm<>'sale_product_unavailable' then raise; end if; end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.post_cash_sale(gen_random_uuid(),'[]',0,0,'',''); raise exception 'Anonymous RPC allowed'; exception when insufficient_privilege then null; end;
 begin perform count(*) from public.sales; raise exception 'Anonymous receipts allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: arithmetic, idempotency, immutable snapshots, conflicting retries, price validation, payment validation, rollback atomicity, RLS, write restrictions, anonymous denial' as verification;
rollback;
