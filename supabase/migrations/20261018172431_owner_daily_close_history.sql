-- Read-only owner history. No financial or closing records change.
create function private.daily_close_history(p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid();items jsonb;s jsonb;begin
 if u is null then raise exception 'close_auth_required';end if;
 if p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to) or p_from<'0001-01-01'::date or p_to>'9999-12-31'::date or p_to<p_from or p_to-p_from>30 then raise exception 'close_invalid_range';end if;
 select coalesce(jsonb_agg(private.daily_close_json(c) order by c.day desc,c.id desc),'[]'::jsonb),jsonb_build_object('count',count(*)::text,'balanced',count(*) filter(where difference=0)::text,'surplus',count(*) filter(where difference>0)::text,'shortage',count(*) filter(where difference<0)::text) into items,s from public.daily_cash_closes c where owner_id=u and day between p_from and p_to;
 return jsonb_build_object('scope','daily-close-history-v1','owner_id',u,'from',p_from,'to',p_to,'currency','IQD','timezone','Asia/Baghdad','generated_at',statement_timestamp(),'summary',s,'rows',items);
end $$;
revoke all on function private.daily_close_history(date,date) from public,anon,authenticated;
grant execute on function private.daily_close_history(date,date) to authenticated;
create function public.get_daily_close_history(p_from date,p_to date) returns jsonb language sql security invoker set search_path='' as $$select private.daily_close_history(p_from,p_to)$$;
revoke all on function public.get_daily_close_history(date,date) from public,anon,authenticated;
grant execute on function public.get_daily_close_history(date,date) to authenticated;
notify pgrst,'reload schema';
