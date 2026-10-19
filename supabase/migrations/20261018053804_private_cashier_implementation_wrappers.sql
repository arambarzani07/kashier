-- Keep elevated implementations out of the exposed API schema.
alter function public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint) set schema private;
alter function public.accept_store_cashier(uuid,uuid) set schema private;
alter function public.get_cashier_catalog(uuid,text,integer) set schema private;
alter function public.post_cashier_sale(uuid,uuid,jsonb,bigint,bigint,text,text) set schema private;
alter function public.get_cashier_sale(uuid,uuid) set schema private;
alter function public.list_cashier_sales(uuid) set schema private;
create function public.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint) returns jsonb language sql security invoker set search_path='' as $$select private.save_store_cashier(p_id,p_member,p_name,p_store,p_discount,p_enabled,p_expected_version);$$;
create function public.accept_store_cashier(p_id uuid,p_membership uuid) returns jsonb language sql security invoker set search_path='' as $$select private.accept_store_cashier(p_id,p_membership);$$;
create function public.get_cashier_catalog(p_owner uuid,p_query text default '',p_offset integer default 0) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_catalog(p_owner,p_query,p_offset);$$;
create function public.post_cashier_sale(p_owner uuid,p_id uuid,p_items jsonb,p_discount bigint,p_received bigint,p_customer text,p_note text) returns jsonb language sql security invoker set search_path='' as $$select private.post_cashier_sale(p_owner,p_id,p_items,p_discount,p_received,p_customer,p_note);$$;
create function public.get_cashier_sale(p_owner uuid,p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.get_cashier_sale(p_owner,p_id);$$;
create function public.list_cashier_sales(p_owner uuid) returns jsonb language sql security invoker set search_path='' as $$select private.list_cashier_sales(p_owner);$$;
revoke all on function public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint),public.accept_store_cashier(uuid,uuid),public.get_cashier_catalog(uuid,text,integer),public.post_cashier_sale(uuid,uuid,jsonb,bigint,bigint,text,text),public.get_cashier_sale(uuid,uuid),public.list_cashier_sales(uuid) from public,anon,authenticated;
grant execute on function public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint),public.accept_store_cashier(uuid,uuid),public.get_cashier_catalog(uuid,text,integer),public.post_cashier_sale(uuid,uuid,jsonb,bigint,bigint,text,text),public.get_cashier_sale(uuid,uuid),public.list_cashier_sales(uuid) to authenticated;
notify pgrst,'reload schema';
