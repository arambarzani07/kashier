-- Synthetic fixture ONLY: never run on production.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values('90000000-0000-4000-8000-000000000001');
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
set local role authenticated;
insert into public.products(id,name,barcode,sale_price)
values('90000000-0000-4000-8000-000000000002','ACCESS X SYNTHETIC PRODUCT','AX-RECOVERY-ONLY',2500);
insert into public.customers(id,name)
values('90000000-0000-4000-8000-000000000003','ACCESS X SYNTHETIC CUSTOMER');
reset role;
insert into public.product_stock(product_id,owner_id,quantity_units)
values('90000000-0000-4000-8000-000000000002','90000000-0000-4000-8000-000000000001',15000)
on conflict(product_id) do update set quantity_units=15000;
set local role authenticated;
select public.post_cash_sale(
 '90000000-0000-4000-8000-000000000004',
 '[{"product_id":"90000000-0000-4000-8000-000000000002","quantity_units":"1000","expected_price":"2500"}]'::jsonb,
 0,2500,'Synthetic only','offline restore drill');
select public.post_debt_entry(
 '90000000-0000-4000-8000-000000000005',
 '90000000-0000-4000-8000-000000000003','charge',25000,'synthetic charge');
select public.post_debt_entry(
 '90000000-0000-4000-8000-000000000006',
 '90000000-0000-4000-8000-000000000003','repayment',9000,'synthetic repayment');
commit;
