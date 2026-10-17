begin;
select set_config('ex.a',gen_random_uuid()::text,true),set_config('ex.b',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('ex.a')::uuid,'expense-a@example.invalid'),(current_setting('ex.b')::uuid,'expense-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ex.a'),'role','authenticated')::text,true);set local role authenticated;
select public.post_cash_entry(gen_random_uuid(),'deposit',10000,'Float');
select public.post_cash_entry(gen_random_uuid(),'expense',100,'Before boundary');
select public.post_cash_entry(gen_random_uuid(),'expense',200,'Literal%_expense');
select public.post_cash_entry(gen_random_uuid(),'expense',300,'Other expense');
select public.post_cash_entry(gen_random_uuid(),'withdrawal',500,'Not an expense');
reset role;
update public.cash_movements set created_at=case note when 'Before boundary' then '2026-10-17T20:59:59Z'::timestamptz when 'Literal%_expense' then '2026-10-17T21:00:00Z'::timestamptz when 'Other expense' then '2026-10-18T20:59:59Z'::timestamptz else '2026-10-18T21:00:00Z'::timestamptz end where owner_id=current_setting('ex.a')::uuid;
-- Other cash movement kinds do not consume the expense report cap.
insert into public.cash_movements(owner_id,created_at,kind,amount,delta,balance_after,note,request_payload)
select current_setting('ex.a')::uuid,'2026-10-18T10:00:00Z','deposit',1,1,1,'Unrelated','{}'::jsonb from generate_series(1,5001);
set local role authenticated;
do $$declare v jsonb;n bigint;begin
 select count(*) into n from public.cash_movements;
 v:=public.get_expense_report('2026-10-18','2026-10-18');if v->>'count'<>'2' or v->>'total'<>'500' or v#>>'{rows,0,note}'<>'Other expense' or v#>>'{rows,1,note}'<>'Literal%_expense' or v#>>'{rows,0,day}'<>'2026-10-18' or v->>'owner_id'<>current_setting('ex.a') then raise exception 'expense scope or inclusive Baghdad dates wrong';end if;
 if jsonb_typeof(v->'total')<>'string' or jsonb_typeof(v#>'{rows,0,amount}')<>'string' or jsonb_typeof(v#>'{rows,0,movement_no}')<>'string' then raise exception 'expense numbers not exact strings';end if;
 v:=public.get_expense_report('2026-10-18','2026-10-18','%_');if v->>'count'<>'1' or v->>'total'<>'200' then raise exception 'literal search wrong';end if;
 v:=public.get_expense_report('2026-10-17','2026-10-17');if v->>'count'<>'1' or v->>'total'<>'100' then raise exception 'previous Baghdad day wrong';end if;
 v:=public.get_expense_report('2026-10-19','2026-10-19');if v->>'count'<>'0' or v->>'total'<>'0' then raise exception 'empty report wrong';end if;
 begin perform public.get_expense_report('2026-10-19','2026-10-18');raise exception 'reversed dates allowed';exception when raise_exception then if sqlerrm<>'expense_invalid_filters' then raise;end if;end;
 begin perform public.get_expense_report('2025-01-01','2026-10-18');raise exception 'long range allowed';exception when raise_exception then if sqlerrm<>'expense_invalid_filters' then raise;end if;end;
 begin perform public.get_expense_report('2026-10-18','2026-10-18',repeat('x',101));raise exception 'long query allowed';exception when raise_exception then if sqlerrm<>'expense_invalid_filters' then raise;end if;end;
 if (select count(*) from public.cash_movements)<>n then raise exception 'report mutated ledger';end if;
end $$;
reset role;select set_config('request.jwt.claims',json_build_object('sub',current_setting('ex.b'),'role','authenticated')::text,true);set local role authenticated;
do $$begin if public.get_expense_report('2026-10-17','2026-10-19')->>'count'<>'0' then raise exception 'owner leak';end if;end $$;
reset role;
-- Rollback-only administrative fixtures exercise exact sums and truncation rejection.
insert into public.cash_movements(owner_id,created_at,kind,amount,delta,balance_after,note,request_payload)
select current_setting('ex.b')::uuid,'2026-09-01T10:00:00Z','expense',100000000000000,-100000000000000,0,'Large','{}'::jsonb from generate_series(1,101);
insert into public.cash_movements(owner_id,created_at,kind,amount,delta,balance_after,note,request_payload)
select current_setting('ex.b')::uuid,'2026-08-01T10:00:00Z','expense',1,-1,0,'Cap '||g,'{}'::jsonb from generate_series(1,5001) g;
set local role authenticated;
do $$declare v jsonb;begin v:=public.get_expense_report('2026-09-01','2026-09-01');if v->>'total'<>'10100000000000000' then raise exception 'large sum rounded';end if;begin perform public.get_expense_report('2026-08-01','2026-08-01');raise exception 'truncation accepted';exception when raise_exception then if sqlerrm<>'expense_too_many_rows' then raise;end if;end;v:=public.get_expense_report('2026-08-01','2026-08-01','Cap 5001');if v->>'count'<>'1' then raise exception 'cap narrowing failed';end if;end $$;
reset role;select set_config('request.jwt.claims','{}',true);set local role authenticated;
do $$begin begin perform public.get_expense_report('2026-10-18','2026-10-18');raise exception 'no UID allowed';exception when raise_exception then if sqlerrm<>'expense_auth_required' then raise;end if;end;end $$;
reset role;set local role anon;
do $$begin begin perform public.get_expense_report('2026-10-18','2026-10-18');raise exception 'anonymous allowed';exception when insufficient_privilege then null;end;end $$;
reset role;select 'PASS: expense-only scope, Baghdad dates, literal note search, exact sums, cap/narrowing, no mutation and owner/anonymous isolation' verification;
rollback;
