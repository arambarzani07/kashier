-- Snapshot report only: no closing transaction, mutation or assumed profit.
create function public.get_daily_report(p_day date)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();v_start timestamptz;v_end timestamptz;v_result jsonb;
begin
 if v_user is null then raise exception using errcode='28000',message='sale_auth_required'; end if;
 if p_day is null then raise exception 'report_day_required'; end if;
 v_start:=p_day::timestamp at time zone 'Asia/Baghdad';
 v_end:=(p_day+1)::timestamp at time zone 'Asia/Baghdad';
 with sales as (
  select count(*) as count,count(*) filter(where payment_mode='cash') as cash_count,count(*) filter(where payment_mode='credit') as credit_count,
   coalesce(sum(subtotal),0) as subtotal,coalesce(sum(discount),0) as discounts,coalesce(sum(total),0) as total,
   coalesce(sum(total) filter(where payment_mode='cash'),0) as cash_total,coalesce(sum(total) filter(where payment_mode='credit'),0) as credit_total,
   coalesce(sum(total-debt_amount),0) as cash_received,coalesce(sum(debt_amount),0) as debt_added
  from public.sales where owner_id=v_user and created_at>=v_start and created_at<v_end
 ), cash as (
  select count(*) filter(where created_at>=v_start) as count,
   coalesce(sum(delta) filter(where created_at<v_start),0) as opening,
   coalesce(sum(delta) filter(where created_at>=v_start and delta>=0),0) as inflows,
   coalesce(-sum(delta) filter(where created_at>=v_start and delta<0),0) as outflows,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='sale'),0) as sales,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='repayment'),0) as repayments,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='deposit'),0) as deposits,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='withdrawal'),0) as withdrawals,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='expense'),0) as expenses
  from public.cash_movements where owner_id=v_user and created_at<v_end
 ), debt as (
  select count(*) filter(where created_at>=v_start) as count,
   coalesce(sum(delta) filter(where created_at<v_start),0) as opening,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='charge' and sale_id is null),0) as manual_charges,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='charge' and sale_id is not null),0) as sale_charges,
   coalesce(sum(amount) filter(where created_at>=v_start and kind='repayment'),0) as repayments
  from public.debt_entries where owner_id=v_user and created_at<v_end
 ), purchases as (
  select count(*) as count,coalesce(sum(total),0) as total from public.purchases where owner_id=v_user and created_at>=v_start and created_at<v_end
 )
 select jsonb_build_object('day',p_day,'timezone','Asia/Baghdad','currency','IQD','generated_at',statement_timestamp(),
  'sales',jsonb_build_object('count',s.count::text,'cash_count',s.cash_count::text,'credit_count',s.credit_count::text,'subtotal',s.subtotal::text,'discounts',s.discounts::text,'total',s.total::text,'cash_total',s.cash_total::text,'credit_total',s.credit_total::text,'cash_received',s.cash_received::text,'debt_added',s.debt_added::text),
  'cash',jsonb_build_object('count',c.count::text,'opening',c.opening::text,'inflows',c.inflows::text,'outflows',c.outflows::text,'closing',(c.opening+c.inflows-c.outflows)::text,'sales',c.sales::text,'repayments',c.repayments::text,'deposits',c.deposits::text,'withdrawals',c.withdrawals::text,'expenses',c.expenses::text),
  'debt',jsonb_build_object('count',d.count::text,'opening',d.opening::text,'manual_charges',d.manual_charges::text,'sale_charges',d.sale_charges::text,'repayments',d.repayments::text,'closing',(d.opening+d.manual_charges+d.sale_charges-d.repayments)::text),
  'purchases',jsonb_build_object('count',p.count::text,'total',p.total::text)
 ) into v_result from sales s cross join cash c cross join debt d cross join purchases p;
 return v_result;
end $$;
revoke all on function public.get_daily_report(date) from public,anon,authenticated;
grant execute on function public.get_daily_report(date) to authenticated;
notify pgrst,'reload schema';
