begin;
select set_config('imp.a',gen_random_uuid()::text,true),set_config('imp.b',gen_random_uuid()::text,true),set_config('imp.p',gen_random_uuid()::text,true),set_config('imp.q',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('imp.a')::uuid,'import-a@example.invalid'),(current_setting('imp.b')::uuid,'import-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('imp.a'),'role','authenticated')::text,true);set local role authenticated;
do $$declare rows jsonb:=jsonb_build_array(jsonb_build_object('id',current_setting('imp.p'),'name','کاڵای هاوردە','barcode','00123','sale_price',1500),jsonb_build_object('id',current_setting('imp.q'),'name','No barcode','barcode',null,'sale_price',1));r jsonb;before_stock bigint;before_cash bigint;bad jsonb;begin
 select count(*) into before_stock from public.stock_movements;select count(*) into before_cash from public.cash_movements;
 r:=public.import_products(rows);if r->>'inserted'<>'2' or r->>'total'<>'2' or r->>'already_present'<>'0' then raise exception 'wrong first result';end if;
 r:=public.import_products(rows);if r->>'inserted'<>'0' or r->>'already_present'<>'2' then raise exception 'retry duplicated';end if;
 if (select count(*) from public.products)<>2 or not exists(select 1 from public.products where barcode='00123' and sale_price=1500) then raise exception 'catalog import wrong';end if;
 if (select count(*) from public.stock_movements)<>before_stock or (select count(*) from public.cash_movements)<>before_cash or exists(select 1 from public.product_stock where quantity_units<>0) then raise exception 'import touched ledgers';end if;
 -- A late collision must roll back an earlier row in the same request.
 bad:=jsonb_build_array(jsonb_build_object('id','00000000-0000-4000-8000-000000000001','name','must roll back','barcode','fresh','sale_price',10),jsonb_build_object('id','ffffffff-ffff-4fff-8fff-ffffffffffff','name','collision','barcode','00123','sale_price',10));
 begin perform public.import_products(bad);raise exception 'barcode collision accepted';exception when unique_violation then null;end;
 if (select count(*) from public.products)<>2 then raise exception 'partial import committed';end if;
 begin perform public.import_products(jsonb_set(rows,'{0,sale_price}','12'));raise exception 'changed retry accepted';exception when raise_exception then if sqlerrm<>'import_request_conflict' then raise;end if;end;
 for bad in select value from jsonb_array_elements(jsonb_build_array('null'::jsonb,'{}'::jsonb,'[]'::jsonb,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'name','x','barcode',null,'sale_price',0)),jsonb_set(rows,'{0,owner_id}',to_jsonb(current_setting('imp.b'))),jsonb_set(rows,'{0,sale_price}','1.5'),jsonb_set(rows,'{0,barcode}','""'),jsonb_set(rows,'{0,name}','" "'))) loop
  begin perform public.import_products(bad);raise exception 'invalid import accepted';exception when raise_exception then if sqlerrm<>'import_invalid_rows' then raise;end if;end;
 end loop;
 begin perform public.import_products(rows||rows);raise exception 'duplicate rows accepted';exception when raise_exception then if sqlerrm<>'import_duplicate_rows' then raise;end if;end;
 begin perform public.import_products((select jsonb_agg(rows->0) from generate_series(1,501)));raise exception 'cap bypassed';exception when raise_exception then if sqlerrm<>'import_invalid_rows' then raise;end if;end;
end $$;
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('imp.b'),'role','authenticated')::text,true);set local role authenticated;
do $$declare r jsonb;begin
 if exists(select 1 from public.products) then raise exception 'owner leak';end if;
 r:=public.import_products(jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'name','B product','barcode','00123','sale_price',10)));if r->>'inserted'<>'1' then raise exception 'owner barcode scope wrong';end if;
 begin perform public.import_products(jsonb_build_array(jsonb_build_object('id',current_setting('imp.p'),'name','cross owner','barcode',null,'sale_price',10)));raise exception 'cross owner overwrite';exception when unique_violation then null;end;
end $$;
reset role;select set_config('request.jwt.claims','{}',true);set local role authenticated;
do $$begin begin perform public.import_products('[]');raise exception 'no UID allowed';exception when raise_exception then if sqlerrm<>'import_auth_required' then raise;end if;end;end $$;
reset role;set local role anon;
do $$begin begin perform public.import_products('[]');raise exception 'anon import allowed';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'PASS: atomic product import, exact idempotent retry, collision rollback, validation/caps, no stock/cash changes, RLS and anonymous denial' verification;
rollback;
