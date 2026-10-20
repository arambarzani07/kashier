-- Synthetic-only verification before and after isolated dump/restore.
\set ON_ERROR_STOP on
do $ax_restore$
declare
 v_owner uuid:='90000000-0000-4000-8000-000000000001';
 v_product uuid:='90000000-0000-4000-8000-000000000002';
 v_customer uuid:='90000000-0000-4000-8000-000000000003';
 v_count integer;v_balance bigint;
begin
 select count(*) into v_count from auth.users where id=v_owner;
 if v_count<>1 then raise exception 'synthetic_auth_identity_missing';end if;
 select count(*) into v_count from public.products where id=v_product and owner_id=v_owner and sale_price=2500;
 if v_count<>1 then raise exception 'synthetic_product_missing';end if;
 select quantity_units into v_balance from public.product_stock where product_id=v_product and owner_id=v_owner;
 if v_balance<>14000 then raise exception 'synthetic_stock_incorrect: %',v_balance;end if;
 select count(*) into v_count from public.sales where owner_id=v_owner
  and id='90000000-0000-4000-8000-000000000004'::uuid
  and total=2500 and received=2500 and change_due=0;
 if v_count<>1 then raise exception 'synthetic_cash_sale_not_restored';end if;
 select count(*) into v_count from public.cash_movements where owner_id=v_owner and kind='sale' and amount=2500;
 if v_count<>1 then raise exception 'synthetic_sale_cash_missing';end if;
 select count(*) into v_count from public.customers where id=v_customer and owner_id=v_owner;
 if v_count<>1 then raise exception 'synthetic_customer_missing';end if;
 select balance into v_balance from public.customer_balances where customer_id=v_customer and owner_id=v_owner;
 if v_balance<>16000 then raise exception 'synthetic_debt_balance_incorrect: %',v_balance;end if;
 select count(*) into v_count from public.debt_entries where owner_id=v_owner and customer_id=v_customer
 and ((kind='charge' and amount=25000 and delta=25000) or (kind='repayment' and amount=9000 and delta=-9000));
 if v_count<>2 then raise exception 'synthetic_ledger_entries_missing';end if;
 select balance into v_balance from public.cash_accounts where owner_id=v_owner;
 if v_balance<>11500 then raise exception 'synthetic_cash_balance_incorrect: %',v_balance;end if;
 select count(*) into v_count from public.cash_movements where owner_id=v_owner and kind='repayment'
 and amount=9000 and customer_id=v_customer;
 if v_count<>1 then raise exception 'synthetic_repayment_cash_missing';end if;
end $ax_restore$;
select 'PASS: synthetic sale, stock, customer, debt/repayment, balances, auth ID restored' as access_x_synthetic_restore;
