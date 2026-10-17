begin;
select set_config('ct.a',gen_random_uuid()::text,true),set_config('ct.b',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('ct.a')::uuid,'stocktake-a@example.invalid'),(current_setting('ct.b')::uuid,'stocktake-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ct.a'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.products(name,barcode,sale_price) values('Count A','001234',1200),('Count % literal','PERCENT%',2000);
do $$declare v jsonb;begin
 v:=public.get_stocktake_snapshot('');if (v->>'count')::int<>2 or jsonb_array_length(v->'rows')<>2 then raise exception 'snapshot missing own rows';end if;
 if v#>>'{rows,1,barcode}'<>'001234' then raise exception 'barcode leading zeros lost';end if;
 if (v#>>'{rows,0,quantity_units}')::bigint<>0 then raise exception 'zero quantity missing';end if;
 v:=public.get_stocktake_snapshot('%');if (v->>'count')::int<>1 then raise exception 'wildcard not literal';end if;
 begin perform public.get_stocktake_snapshot(repeat('a',101));raise exception 'long filter accepted';exception when raise_exception then if sqlerrm<>'stocktake_query_too_long' then raise;end if;end;
end $$;
do $$declare p uuid;v jsonb;before_moves bigint;begin
 select id into p from public.products where barcode='001234';
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',2501,'unit_cost',1000)),'rollback supplier','CT','test');
 select count(*) into before_moves from public.stock_movements;
 v:=public.get_stocktake_snapshot('001234');if (v#>>'{rows,0,quantity_units}')::bigint<>2501 then raise exception 'real stock omitted';end if;
 perform public.get_stocktake_snapshot('001234');if (select count(*) from public.stock_movements)<>before_moves then raise exception 'snapshot wrote movements';end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ct.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin if (public.get_stocktake_snapshot('')->>'count')::int<>0 then raise exception 'owner isolation failed';end if;end $$;
insert into public.products(name,sale_price) select 'Bulk '||g,1000 from generate_series(1,5001) g;
do $$begin
 begin perform public.get_stocktake_snapshot('');raise exception 'truncated snapshot accepted';exception when raise_exception then if sqlerrm<>'stocktake_too_many_rows' then raise;end if;end;
 if (public.get_stocktake_snapshot('Bulk 5001')->>'count')::int<>1 then raise exception 'large catalog filter failed';end if;
end $$;
reset role;
do $$begin if has_function_privilege('anon','public.get_stocktake_snapshot(text)','execute') then raise exception 'anon execute exposed';end if;end $$;
rollback;
