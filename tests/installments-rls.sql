begin;
select set_config('ip.owner',gen_random_uuid()::text,true),set_config('ip.other',gen_random_uuid()::text,true),set_config('ip.customer',gen_random_uuid()::text,true),set_config('ip.charge',gen_random_uuid()::text,true),set_config('ip.payment',gen_random_uuid()::text,true),set_config('ip.plan',gen_random_uuid()::text,true),set_config('ip.cancel',gen_random_uuid()::text,true),set_config('ip.product',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('ip.owner')::uuid,'installment-a@example.invalid'),(current_setting('ip.other')::uuid,'installment-b@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ip.owner'),'role','authenticated')::text,true);
set local role authenticated;
insert into public.customers(id,name) values(current_setting('ip.customer')::uuid,'installment fixture');
insert into public.products(id,name,sale_price) values(current_setting('ip.product')::uuid,'installment item',1000);
do $$declare c uuid:=current_setting('ip.customer')::uuid;ch uuid:=current_setting('ip.charge')::uuid;pay uuid:=current_setting('ip.payment')::uuid;p uuid:=current_setting('ip.plan')::uuid;can uuid:=current_setting('ip.cancel')::uuid;s jsonb:='[{"due_date":"2026-10-01","amount":"3000"},{"due_date":"2026-11-01","amount":"7000"}]';x jsonb;y jsonb;bad jsonb;a uuid:=gen_random_uuid();sale jsonb;sp uuid:=gen_random_uuid();st bigint;before_debt bigint;before_cash bigint;begin
 x:=public.get_customer_installments(c);if x->'plans'<>'[]'::jsonb or x->'ledger'->>'balance'<>'0' then raise exception 'empty book';end if;
 perform public.post_debt_entry(ch,c,'charge',10000,'opening');perform public.post_debt_entry(pay,c,'repayment',4000,'received');perform public.allocate_customer_payment(a,c,pay,ch,3000,'classified');
 x:=public.create_customer_installments(p,c,ch,s,'agreed');if public.create_customer_installments(p,c,ch,s,'agreed')<>x then raise exception 'create replay';end if;
 if (select balance from public.customer_balances where customer_id=c)<>6000 or (select balance from public.cash_accounts)<>4000 or (select count(*) from public.debt_entries)<>2 or (select count(*) from public.cash_movements)<>1 then raise exception 'schedule changed money';end if;
 begin perform public.create_customer_installments(p,c,ch,s,'different');raise exception 'conflict allowed';exception when raise_exception then if sqlerrm<>'installment_request_conflict' then raise;end if;end;
 begin perform public.create_customer_installments(gen_random_uuid(),c,ch,s,'duplicate active');raise exception 'duplicate allowed';exception when raise_exception then if sqlerrm<>'installment_plan_exists' then raise;end if;end;
 begin perform public.create_customer_installments(gen_random_uuid(),c,ch,'[{"due_date":"2026-11-01","amount":"6000"}]','remaining only');raise exception 'amount mismatch allowed';exception when raise_exception then if sqlerrm<>'installment_amount_mismatch' then raise;end if;end;
 for bad in select value from jsonb_array_elements('[[],[{"due_date":"2026-02-30","amount":"10000"}],[{"due_date":"2026-11-01","amount":"10000.0"}],[{"due_date":"2026-11-01","amount":10000}],[{"due_date":"2026-11-01","amount":"0"}],[{"due_date":"2026-11-01","amount":"5000"},{"due_date":"2026-11-01","amount":"5000"}],[{"due_date":"2026-11-02","amount":"5000"},{"due_date":"2026-11-01","amount":"5000"}],[{"due_date":"1999-12-31","amount":"10000"}]]'::jsonb) loop
  begin perform public.create_customer_installments(gen_random_uuid(),c,ch,bad,'bad');raise exception 'bad schedule allowed';exception when raise_exception then if sqlerrm<>'installment_invalid_schedule' then raise;end if;end;
 end loop;
 x:=public.get_customer_installments(c);if x->'plans'->0->>'allocated'<>'3000' or x->'plans'->0->>'unassigned'<>'1000' or x->'plans'->0->>'amount'<>'10000' or x->'ledger'->>'balance'<>'6000' then raise exception 'plan totals wrong';end if;
 if (public.get_customer_installments()->'ledger')<>'null'::jsonb then raise exception 'global ledger';end if;
 perform public.reverse_customer_allocation(gen_random_uuid(),c,a,'correction');x:=public.get_customer_installments(c);if x->'plans'->0->>'allocated'<>'0' or x->'plans'->0->>'unassigned'<>'4000' then raise exception 'allocation reversal not reflected';end if;
 y:=public.cancel_customer_installments(can,c,p,'new terms');if public.cancel_customer_installments(can,c,p,'new terms')<>y then raise exception 'cancel replay';end if;
 begin perform public.cancel_customer_installments(gen_random_uuid(),c,p,'again');raise exception 'duplicate cancel';exception when raise_exception then if sqlerrm<>'installment_already_cancelled' then raise;end if;end;
 perform public.create_customer_installments(gen_random_uuid(),c,ch,s,'replacement');x:=public.get_customer_installments(c);if jsonb_array_length(x->'plans')<>2 or not exists(select 1 from jsonb_array_elements(x->'plans') item where item->>'cancellation_id'=can::text and item->>'cancel_reason'='new terms') then raise exception 'audit lost';end if;
 -- An active credit-invoice plan protects a return in the same transaction.
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',current_setting('ip.product'),'quantity_units',10000,'unit_cost',500)),'','','');
 sale:=public.post_credit_sale(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',current_setting('ip.product'),'quantity_units',1000,'expected_price',1000)),0,0,c,'credit');
 perform public.create_customer_installments(sp,c,(sale->>'debt_entry_id')::uuid,'[{"due_date":"2026-12-01","amount":"1000"}]','invoice plan');
 st:=(select quantity_units from public.product_stock);before_debt:=(select balance from public.customer_balances);before_cash:=(select balance from public.cash_accounts);
 begin perform public.post_sale_reversal(gen_random_uuid(),(sale->>'id')::uuid,'return');raise exception 'scheduled invoice reversed';exception when raise_exception then if sqlerrm<>'installment_cancel_before_return' then raise;end if;end;
 if (select quantity_units from public.product_stock)<>st or (select balance from public.customer_balances)<>before_debt or (select balance from public.cash_accounts)<>before_cash or exists(select 1 from public.sale_reversals) then raise exception 'return not atomic';end if;
 perform public.cancel_customer_installments(gen_random_uuid(),c,sp,'invoice return');perform public.post_sale_reversal(gen_random_uuid(),(sale->>'id')::uuid,'return');
 x:=public.export_owner_data();if x->>'version'<>'4' or (select count(*) from jsonb_object_keys(x->'tables'))<>23 or x->'counts'->>'customer_installment_plans'<>'3' or x->'counts'->>'customer_installment_cancellations'<>'2' then raise exception 'export incomplete';end if;
 begin delete from public.customer_installment_plans;raise exception 'direct delete';exception when insufficient_privilege then null;end;
 begin update public.customer_installment_cancellations set reason='tamper';raise exception 'direct update';exception when insufficient_privilege then null;end;
 begin insert into public.customer_installment_plans(id) values(gen_random_uuid());raise exception 'direct insert';exception when insufficient_privilege then null;end;
end $$;
reset role;set constraints all immediate;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ip.other'),'role','authenticated')::text,true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.customer_installment_plans) or exists(select 1 from public.customer_installment_cancellations) or public.get_customer_installments()->'plans'<>'[]'::jsonb then raise exception 'RLS leak';end if;
 begin perform public.get_customer_installments(current_setting('ip.customer')::uuid);raise exception 'customer leak';exception when raise_exception then if sqlerrm<>'debt_customer_unavailable' then raise;end if;end;
 begin perform public.cancel_customer_installments(gen_random_uuid(),current_setting('ip.customer')::uuid,current_setting('ip.plan')::uuid,'cross owner');raise exception 'cancel leak';exception when raise_exception then if sqlerrm<>'installment_plan_unavailable' then raise;end if;end;
 begin perform public.create_customer_installments(current_setting('ip.plan')::uuid,current_setting('ip.customer')::uuid,current_setting('ip.charge')::uuid,'[{"due_date":"2026-10-01","amount":"3000"},{"due_date":"2026-11-01","amount":"7000"}]','agreed');raise exception 'replay leak';exception when raise_exception then if sqlerrm<>'installment_request_conflict' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims','{}',true);set local role authenticated;
do $$begin begin perform public.get_customer_installments();raise exception 'null uid';exception when raise_exception then if sqlerrm<>'installment_auth_required' then raise;end if;end;end $$;
reset role;set local role anon;
do $$begin
 begin perform public.get_customer_installments();raise exception 'anon read';exception when insufficient_privilege then null;end;
 begin perform public.create_customer_installments(gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),'[]','anon');raise exception 'anon write';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: installment schedules, replay/conflict, exact sum/date bounds, allocation/reversal read, cancellation audit, atomic sale-return guard, export v4, RLS/grants' as verification;
rollback;
