begin;
select set_config('ord.owner',gen_random_uuid()::text,true),set_config('ord.member',gen_random_uuid()::text,true),set_config('ord.customer',gen_random_uuid()::text,true),set_config('ord.product',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('ord.owner')::uuid,'recent-owner@example.invalid'),(current_setting('ord.member')::uuid,'recent-member@example.invalid');
insert into public.store_cashiers(owner_id,member_id,member_name,store_name,enabled,accepted_at) values(current_setting('ord.owner')::uuid,current_setting('ord.member')::uuid,'Collector','Store',true,now());
insert into public.customers(id,owner_id,name) values(current_setting('ord.customer')::uuid,current_setting('ord.owner')::uuid,'Customer');
-- Rollback-only historical rows straddle a decimal digit-length boundary.
do $$declare i bigint;s uuid;z uuid;c uuid;begin
 for i in -10..10 loop
  s:=gen_random_uuid();z:=gen_random_uuid();c:=gen_random_uuid();
  insert into public.sales(id,receipt_no,owner_id,customer_name,note,subtotal,discount,total,received,change_due,lines,request_payload,actor_id,actor_name)
  overriding system value values(s,1000000000000000+i,current_setting('ord.owner')::uuid,'Customer','',1,0,1,1,0,jsonb_build_array(jsonb_build_object('product_id',current_setting('ord.product'),'name','Item','barcode',null,'quantity_units',1000,'unit_price',1,'line_total',1)),'{}',current_setting('ord.member')::uuid,'Collector');
  insert into public.sale_reversals(id,reversal_no,owner_id,sale_id,reason,total,cash_refund,debt_reversed,lines,request_payload,actor_id,actor_name)
  overriding system value values(z,1000000000000000+i,current_setting('ord.owner')::uuid,s,'Returned',1,1,0,jsonb_build_array(jsonb_build_object('product_id',current_setting('ord.product'),'name','Item','barcode',null,'quantity_units',1000,'unit_price',1,'line_total',1)),'{}',current_setting('ord.member')::uuid,'Collector');
  insert into public.cash_movements(id,owner_id,kind,amount,delta,balance_after,note,customer_id,request_payload) values(c,current_setting('ord.owner')::uuid,'repayment',1,1,1,'Collected',current_setting('ord.customer')::uuid,'{}');
  insert into public.debt_entries(id,movement_no,owner_id,customer_id,customer_name,kind,amount,delta,balance_after,note,cash_movement_id,request_payload,actor_id,actor_name)
  overriding system value values(gen_random_uuid(),1000000000000000+i,current_setting('ord.owner')::uuid,current_setting('ord.customer')::uuid,'Customer','repayment',1,-1,0,'Collected',c,'{}',current_setting('ord.member')::uuid,'Collector');
 end loop;
end $$;
select set_config('request.jwt.claims',json_build_object('sub',current_setting('ord.member'),'role','authenticated')::text,true);set local role authenticated;
do $$declare x jsonb;rows jsonb;k text;begin
 x:=public.get_cashier_refund_workspace(current_setting('ord.owner')::uuid);
 foreach k in array array['sales','refunds'] loop
  rows:=x->k;
  if jsonb_array_length(rows)<>20 or coalesce(rows->0->>'receipt_no',rows->0->>'reversal_no')<>'1000000000000010' or coalesce(rows->19->>'receipt_no',rows->19->>'reversal_no')<>'999999999999991' then raise exception 'refund workspace top20 is lexicographic';end if;
 end loop;
 rows:=public.list_cashier_repayments(current_setting('ord.owner')::uuid)->'rows';
 if jsonb_array_length(rows)<>20 or rows->0->>'movement_no'<>'1000000000000010' or rows->19->>'movement_no'<>'999999999999991' then raise exception 'repayment top20 is lexicographic';end if;
end $$;
reset role;
select 'PASS: own sales/refunds/repayments select numeric newest20 across digit-length boundary before exact-string serialization' as verification;
rollback;
