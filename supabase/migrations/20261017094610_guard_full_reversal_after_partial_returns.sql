create or replace function public.post_sale_reversal(p_id uuid,p_sale uuid,p_reason text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null then raise exception using errcode='28000',message='reversal_auth_required'; end if;
 if exists(select 1 from public.sale_returns where sale_id=p_sale and owner_id=auth.uid()) then
  raise exception 'reversal_partial_returns_exist';
 end if;
 return private.post_sale_reversal(p_id,p_sale,p_reason);
end $$;
revoke all on function public.post_sale_reversal(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.post_sale_reversal(uuid,uuid,text) to authenticated;
notify pgrst,'reload schema';
