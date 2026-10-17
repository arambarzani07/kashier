-- Run only with a database administrative connection. All fixtures are rolled back.
begin;
select set_config('kashier.test_a',gen_random_uuid()::text,true),set_config('kashier.test_b',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('kashier.test_a')::uuid,'catalog-rollback-a@example.invalid'),(current_setting('kashier.test_b')::uuid,'catalog-rollback-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('kashier.test_a'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.products(id,name,barcode,sale_price) values(gen_random_uuid(),'rollback-only','TEST-ROLLBACK',1000);
do $$ begin
 if (select count(*) from public.products)<>1 then raise exception 'Own read failed'; end if;
 begin insert into public.products(id,name,barcode,sale_price) values(gen_random_uuid(),'duplicate','TEST-ROLLBACK',1000); raise exception 'Duplicate was allowed'; exception when unique_violation then null; end;
 begin insert into public.products(id,name,sale_price) values(gen_random_uuid(),'invalid',0); raise exception 'Zero price allowed'; exception when check_violation then null; end;
 update public.products set sale_price=2000 where barcode='TEST-ROLLBACK';
 if (select sale_price from public.products where barcode='TEST-ROLLBACK')<>2000 then raise exception 'Own update failed'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('kashier.test_b'),'role','authenticated')::text,true);
set local role authenticated;
do $$ declare n int; begin
 if (select count(*) from public.products)<>0 then raise exception 'Isolation failed'; end if;
 update public.products set sale_price=9000 where barcode='TEST-ROLLBACK'; get diagnostics n=row_count;
 if n<>0 then raise exception 'Cross-account update allowed'; end if;
 begin insert into public.products(id,owner_id,name,sale_price) values(gen_random_uuid(),current_setting('kashier.test_a')::uuid,'forged',1000); raise exception 'Forged owner allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin begin perform count(*) from public.products; raise exception 'Anonymous read allowed'; exception when insufficient_privilege then null; end; end $$;
reset role;
select 'PASS: owner create/read/update, isolation, anonymous denial, barcode uniqueness, price validation; all fixtures rolled back' as verification;
rollback;
