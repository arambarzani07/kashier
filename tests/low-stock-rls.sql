-- Administrative rollback-only fixtures. No products or users remain.
begin;
select set_config('ls.a',gen_random_uuid()::text,true),set_config('ls.b',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('ls.a')::uuid,'low-stock-a@example.invalid'),(current_setting('ls.b')::uuid,'low-stock-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ls.a'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare product uuid;qty bigint;payload jsonb:='[]';begin
 foreach qty in array array[0,1,2500,5000,5001]::bigint[] loop
  product:=gen_random_uuid();insert into public.products(id,name,sale_price) values(product,'low stock '||qty,1000);
  if qty>0 then payload:=payload||jsonb_build_array(jsonb_build_object('product_id',product,'quantity_units',qty,'unit_cost',1000));end if;
 end loop;
 perform public.post_purchase(gen_random_uuid(),payload,'','','low stock fixture');
 if (select count(*) from public.stock_catalog where quantity_units<=0)<>1 then raise exception 'Unreceived catalog item must be included as zero stock';end if;
 if (select count(*) from public.stock_catalog where quantity_units<=5000)<>4 then raise exception 'Threshold must be inclusive';end if;
 if (select count(*) from public.stock_catalog where quantity_units<=2501)<>3 then raise exception 'Fractional threshold is not exact';end if;
 if (select quantity_units from public.stock_catalog where quantity_units<=5000 order by quantity_units,name,id offset 3 limit 1)<>5000 then raise exception 'Threshold pagination skipped or included wrong item';end if;
 if (select count(*) from public.stock_catalog where quantity_units<=5000 and name like '%2500%')<>1 then raise exception 'Search and threshold failed';end if;
 if (select count(*) from public.stock_catalog)<>5 then raise exception 'Read filter mutated stock';end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ls.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$ begin if (select count(*) from public.stock_catalog where quantity_units<=5000)<>0 then raise exception 'Cross-owner low stock leak';end if;end $$;
reset role;
set local role anon;
do $$ begin begin perform count(*) from public.stock_catalog where quantity_units<=5000;raise exception 'Anonymous low stock allowed';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'PASS: zero-stock catalog inclusion, inclusive and fractional thresholds, server pagination/search, no writes, owner RLS and anonymous denial' as verification;
rollback;
