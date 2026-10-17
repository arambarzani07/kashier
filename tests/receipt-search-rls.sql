begin;
select set_config('rs.a',gen_random_uuid()::text,true),set_config('rs.b',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('rs.a')::uuid,'receipt-search-a@example.invalid'),(current_setting('rs.b')::uuid,'receipt-search-b@example.invalid');
-- Rollback-only administrative receipt fixtures; no stock or money is posted by this search test.
insert into public.sales(id,owner_id,created_at,customer_name,subtotal,discount,total,received,change_due,lines,request_payload)
select gen_random_uuid(),current_setting('rs.a')::uuid,'2026-05-01T10:00:00Z','Search customer '||g,1000,0,1000,1000,0,jsonb_build_array(jsonb_build_object('name','Fixture','quantity_units',1000,'unit_price',1000,'line_total',1000)),'{}'::jsonb from generate_series(1,61) g;
insert into public.purchases(id,owner_id,created_at,supplier_name,invoice_no,total,lines,request_payload) values
(gen_random_uuid(),current_setting('rs.a')::uuid,'2026-04-30T21:00:00Z','Supplier % literal','INV-ABC-001',2000,'[{"name":"Fixture","quantity_units":1000,"line_total":2000}]','{}'),
(gen_random_uuid(),current_setting('rs.a')::uuid,'2026-05-01T20:59:59.999999Z','Another supplier','INV-END',3000,'[{"name":"Fixture","quantity_units":1000,"line_total":3000}]','{}'),
(gen_random_uuid(),current_setting('rs.a')::uuid,'2026-05-01T21:00:00Z','Outside supplier','NEXT-DAY',4000,'[{"name":"Fixture","quantity_units":1000,"line_total":4000}]','{}');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('rs.a'),'role','authenticated')::text,true);
set local role authenticated;
do $$declare first_page jsonb;second_page jsonb;one jsonb;n bigint;v jsonb;before_count bigint;begin
 select count(*) into before_count from public.sales;
 first_page:=public.search_receipts('sale',0,null,'2026-05-01','2026-05-01','search customer');second_page:=public.search_receipts('sale',1,null,'2026-05-01','2026-05-01','search customer');
 if first_page->>'total'<>'61' or jsonb_array_length(first_page->'rows')<>50 or jsonb_array_length(second_page->'rows')<>11 then raise exception 'filtered pagination/count incorrect';end if;
 if exists(select 1 from jsonb_array_elements(first_page->'rows') a join jsonb_array_elements(second_page->'rows') b on a->>'id'=b->>'id') then raise exception 'duplicate receipt across pages';end if;
 select receipt_no into n from public.sales where customer_name='Search customer 61';
 one:=public.search_receipts('sale',0,n,null,null,'');if one->>'total'<>'1' or one#>>'{rows,0,customer_name}'<>'Search customer 61' or jsonb_typeof(one#>'{rows,0,receipt_no}')<>'string' or jsonb_typeof(one#>'{rows,0,total}')<>'string' then raise exception 'exact number/text precision incorrect';end if;
 v:=public.search_receipts('purchase',0,null,'2026-05-01','2026-05-01','');if v->>'total'<>'2' then raise exception 'Baghdad inclusive bounds incorrect';end if;
 v:=public.search_receipts('purchase',0,null,null,null,'abc-001');if v->>'total'<>'1' then raise exception 'invoice substring search incorrect';end if;
 v:=public.search_receipts('purchase',0,null,null,null,'%');if v->>'total'<>'1' then raise exception 'wildcard was not literal';end if;
 v:=public.search_receipts('purchase',0,null,'2026-05-02',null,'');if v->>'total'<>'1' then raise exception 'open date lower bound incorrect';end if;
 v:=public.search_receipts('purchase',0,null,null,'2026-05-01','');if v->>'total'<>'2' then raise exception 'open date upper bound incorrect';end if;
 begin perform public.search_receipts('other');raise exception 'invalid kind accepted';exception when raise_exception then if sqlerrm<>'receipt_search_invalid_filters' then raise;end if;end;
 begin perform public.search_receipts('sale',-1);raise exception 'negative page accepted';exception when raise_exception then if sqlerrm<>'receipt_search_invalid_filters' then raise;end if;end;
 begin perform public.search_receipts('sale',0,null,'2026-05-02','2026-05-01','');raise exception 'reverse dates accepted';exception when raise_exception then if sqlerrm<>'receipt_search_invalid_filters' then raise;end if;end;
 if (select count(*) from public.sales)<>before_count then raise exception 'search changed receipts';end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('rs.b'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin if public.search_receipts('sale')->>'total'<>'0' or public.search_receipts('purchase')->>'total'<>'0' then raise exception 'cross-owner search leak';end if;end $$;
reset role;
do $$begin if has_function_privilege('anon','public.search_receipts(text,integer,bigint,date,date,text)','execute') then raise exception 'anonymous search exposed';end if;end $$;
rollback;
