-- Choose the numeric newest20 before converting document identifiers to JSON strings.
do $migration$
declare body text;
begin
 body:=pg_get_functiondef('private.get_cashier_refund_workspace(uuid)'::regprocedure);
 if strpos(body,'order by receipt_no desc limit 20')=0 or strpos(body,'order by reversal_no desc limit 20')=0 then raise exception 'unexpected_refund_recent_definition';end if;
 body:=replace(body,'order by receipt_no desc limit 20','order by public.sales.receipt_no desc limit 20');
 body:=replace(body,'order by reversal_no desc limit 20','order by public.sale_reversals.reversal_no desc limit 20');execute body;
 body:=pg_get_functiondef('private.list_cashier_repayments(uuid)'::regprocedure);
 if strpos(body,'order by movement_no desc limit 20')=0 then raise exception 'unexpected_repayment_recent_definition';end if;
 execute replace(body,'order by movement_no desc limit 20','order by public.debt_entries.movement_no desc limit 20');
end $migration$;
notify pgrst,'reload schema';
