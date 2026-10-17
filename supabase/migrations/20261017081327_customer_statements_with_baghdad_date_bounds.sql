-- One read snapshot; security invoker keeps all existing owner policies in force.
create function public.get_customer_statement(p_customer uuid,p_from date default null,p_to date default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_customer public.customers%rowtype;v_from timestamptz;v_to timestamptz;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='debt_auth_required'; end if;
 if p_from is not null and p_to is not null and p_from>p_to then raise exception 'statement_invalid_dates'; end if;
 select * into v_customer from public.customers where id=p_customer and owner_id=v_user;
 if not found then raise exception 'debt_customer_unavailable'; end if;
 v_from:=p_from::timestamp at time zone 'Asia/Baghdad';
 v_to:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 with ledger as materialized (
  select id,movement_no,created_at,kind,amount,delta,note,sale_id,cash_movement_id from public.debt_entries where customer_id=p_customer and owner_id=v_user
 ), opening as (
  select coalesce(sum(delta) filter(where v_from is not null and created_at<v_from),0) as amount from ledger
 ), period as materialized (
  select * from ledger where (v_from is null or created_at>=v_from) and (v_to is null or created_at<v_to)
 ), totals as (
  select count(*) as count,coalesce(sum(amount) filter(where kind='charge'),0) as charges,coalesce(sum(amount) filter(where kind='repayment'),0) as repayments from period
 ), ordered as (
  select *, (select amount from opening)+sum(delta) over(order by movement_no rows unbounded preceding) as statement_balance from period order by movement_no limit 5001
 )
 select jsonb_build_object(
  'customer',jsonb_build_object('id',v_customer.id,'name',v_customer.name,'phone',v_customer.phone),
  'from',p_from,'to',p_to,'timezone','Asia/Baghdad','generated_at',statement_timestamp(),'currency','IQD',
  'opening',o.amount::text,'charges',t.charges::text,'repayments',t.repayments::text,'closing',(o.amount+t.charges-t.repayments)::text,'count',t.count,
  'rows',coalesce((select jsonb_agg(jsonb_build_object('id',id,'movement_no',movement_no::text,'created_at',created_at,'kind',kind,'amount',amount::text,'delta',delta::text,'balance',statement_balance::text,'note',note,'sale_id',sale_id,'cash_movement_id',cash_movement_id) order by movement_no) from ordered),'[]'::jsonb)
 ) into v_result from opening o cross join totals t;
 if (v_result->>'count')::bigint>5000 then raise exception 'statement_too_many_rows'; end if;
 return v_result;
end $$;
revoke all on function public.get_customer_statement(uuid,date,date) from public,anon,authenticated;
grant execute on function public.get_customer_statement(uuid,date,date) to authenticated;
notify pgrst,'reload schema';
