-- Preserve bigint receipt identifiers as decimal strings in every staff refund response.
do $migration$
declare signature text;body text;needle text:=$old$to_jsonb(s)-'owner_id'-'request_payload'$old$;
 replacement text:=$new$(to_jsonb(s)-'owner_id'-'request_payload')||jsonb_build_object('receipt_no',s.receipt_no::text)$new$;
begin
 foreach signature in array array['private.get_cashier_refund_sale(uuid,uuid,bigint)','private.get_cashier_refund(uuid,uuid)','private.post_cashier_refund(uuid,uuid,uuid,text)'] loop
  body:=pg_get_functiondef(signature::regprocedure);
  if strpos(body,needle)=0 then raise exception 'unexpected_staff_refund_definition';end if;
  execute replace(body,needle,replacement);
 end loop;
end $migration$;
notify pgrst,'reload schema';
