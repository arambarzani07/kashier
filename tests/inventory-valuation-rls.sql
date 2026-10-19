begin;
select set_config('iv.owner',gen_random_uuid()::text,true),set_config('iv.other',gen_random_uuid()::text,true),set_config('iv.known',gen_random_uuid()::text,true),set_config('iv.unknown',gen_random_uuid()::text,true),set_config('iv.empty',gen_random_uuid()::text,true),set_config('iv.tiny',gen_random_uuid()::text,true),set_config('iv.legacy',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('iv.owner')::uuid,'valuation-a@example.invalid'),(current_setting('iv.other')::uuid,'valuation-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('iv.owner'),'role','authenticated')::text,true);set local role authenticated;
insert into public.products(id,name,barcode,sale_price) values(current_setting('iv.known')::uuid,'Known item','012345',1000),(current_setting('iv.unknown')::uuid,'Literal %_ item',null,1000),(current_setting('iv.empty')::uuid,'Empty item',null,1000),(current_setting('iv.tiny')::uuid,'Tiny rounding',null,1000),(current_setting('iv.legacy')::uuid,'Opening item',null,1000);
do $$declare p uuid:=current_setting('iv.known')::uuid;u uuid:=current_setting('iv.unknown')::uuid;t uuid:=current_setting('iv.tiny')::uuid;x jsonb;v_cash bigint;v_debt bigint;v_stock bigint;begin
 x:=public.get_inventory_valuation();if x->>'count'<>'0' or x->>'known_value'<>'0' or x->>'complete'<>'true' then raise exception 'empty valuation';end if;
 x:=public.get_inventory_valuation('',true);if x->>'count'<>'5' or x->>'known_count'<>'5' or not exists(select 1 from jsonb_array_elements(x->'rows') item where item->>'coverage'='empty' and item->>'value_iqd'='0') then raise exception 'empty products';end if;
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',2000,'unit_cost',500)),'','','');
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',t,'quantity_units',1,'unit_cost',1)),'','','');
 perform public.post_stock_adjustment(gen_random_uuid(),u,0,0,1000,'unknown positive count');
 v_stock:=(select sum(quantity_units) from public.product_stock);
 x:=public.get_inventory_valuation();if x->>'count'<>'3' or x->>'known_count'<>'2' or x->>'unknown_count'<>'1' or x->>'known_value'<>'1000' or x->>'complete'<>'false' or x->'rows'->0->>'product_id'<>u::text then raise exception 'coverage totals';end if;
 if not exists(select 1 from jsonb_array_elements(x->'rows') item where item->>'product_id'=t::text and item->>'value_iqd'='0' and item->>'coverage'='known') then raise exception 'known zero confused with unknown';end if;
 x:=public.get_inventory_valuation('%_',false);if x->>'count'<>'1' or x->'rows'->0->>'product_id'<>u::text then raise exception 'wildcard query not literal';end if;
 x:=public.get_inventory_valuation('  0123  ',false);if x->>'count'<>'1' or x->>'query'<>'0123' or x->>'complete'<>'true' then raise exception 'barcode filtering';end if;
 if (select sum(quantity_units) from public.product_stock)<>v_stock or exists(select 1 from public.sales) or exists(select 1 from public.cash_movements) then raise exception 'report mutated business';end if;
 begin perform public.get_inventory_valuation(repeat('a',101),false);raise exception 'long query accepted';exception when raise_exception then if sqlerrm<>'valuation_invalid_filters' then raise;end if;end;
 begin perform public.get_inventory_valuation('',null);raise exception 'null empty filter';exception when raise_exception then if sqlerrm<>'valuation_invalid_filters' then raise;end if;end;
end $$;
reset role;
-- An existing positive stock balance without any costing state remains unknown and is not seeded.
insert into public.product_stock(product_id,owner_id,quantity_units) values(current_setting('iv.legacy')::uuid,current_setting('iv.owner')::uuid,500);
update public.inventory_cost_state set quantity_units=1999 where product_id=current_setting('iv.known')::uuid;
set local role authenticated;
do $$declare x jsonb;begin
 begin perform public.get_inventory_valuation();raise exception 'mismatched valuation accepted';exception when raise_exception then if sqlerrm<>'valuation_stock_mismatch' then raise;end if;end;
 x:=public.get_inventory_valuation('Opening',false);if x->>'unknown_count'<>'1' or x->'rows'->0->'value_iqd'<>'null'::jsonb or exists(select 1 from public.inventory_cost_state where product_id=current_setting('iv.legacy')::uuid) then raise exception 'opening cost guessed';end if;
end $$;
reset role;update public.inventory_cost_state set quantity_units=2000 where product_id=current_setting('iv.known')::uuid;set local role authenticated;
insert into public.products(id,name,sale_price) select gen_random_uuid(),'Valuation cap fixture '||i,1000 from generate_series(1,5001) i;
do $$begin
 begin perform public.get_inventory_valuation('',true);raise exception 'cap not enforced';exception when raise_exception then if sqlerrm<>'valuation_too_many_rows' then raise;end if;end;
 if public.get_inventory_valuation('%_',true)->>'count'<>'1' then raise exception 'cap applied before filter';end if;
 if public.get_inventory_valuation('',false)->>'count'<>'4' then raise exception 'empty stock consumed cap';end if;
end $$;
reset role;set constraints all immediate;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('iv.other'),'role','authenticated')::text,true);set local role authenticated;
do $$begin if public.get_inventory_valuation('',true)->>'count'<>'0' or public.get_inventory_valuation('0123',true)->>'count'<>'0' then raise exception 'valuation RLS leak';end if;end $$;
reset role;select set_config('request.jwt.claims','{}',true);set local role authenticated;
do $$begin begin perform public.get_inventory_valuation();raise exception 'no uid accepted';exception when raise_exception then if sqlerrm<>'valuation_auth_required' then raise;end if;end;end $$;
reset role;set local role anon;
do $$begin begin perform public.get_inventory_valuation();raise exception 'anon read';exception when insufficient_privilege then null;end;end $$;
reset role;
select 'PASS: current value, known/unknown/empty coverage, zero-cost rounding, literal barcode/name filters, cap after filtering, mismatch refusal, no writes, owner/anonymous isolation' as verification;
rollback;
