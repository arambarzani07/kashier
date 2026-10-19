alter table public.store_cashiers add column role text not null default 'cashier' check(role in('cashier','manager'));
drop function public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint);
drop function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint);
create function private.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint,p_role text default 'cashier') returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();r public.store_cashiers%rowtype;e public.staff_actions%rowtype;payload jsonb;old jsonb;result jsonb;k text;begin
 if u is null then raise exception 'staff_auth_required';end if;
 if p_role is null or p_role not in ('cashier','manager') or p_id is null or p_member is null or p_member=u or p_discount is null or p_enabled is null or p_expected_version is null or p_expected_version<0 or char_length(btrim(coalesce(p_name,''))) not between 1 and 100 or char_length(btrim(coalesce(p_store,''))) not between 1 and 100 then raise exception 'staff_invalid_request';end if;
 payload:=jsonb_build_object('kind','save','member',p_member,'name',btrim(p_name),'store',btrim(p_store),'discount',p_discount,'enabled',p_enabled,'expected_version',p_expected_version,'role',p_role);
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff-action.'||p_id::text,0));select * into e from public.staff_actions where id=p_id;
 if found then if e.actor_id<>u or e.owner_id<>u or (e.request_payload||jsonb_build_object('role',coalesce(e.request_payload->>'role','cashier')))<>payload then raise exception 'staff_request_conflict';end if;return e.result_payload;end if;
 perform pg_advisory_xact_lock(hashtextextended('kashier.staff.'||u::text,0));
 select * into r from public.store_cashiers where owner_id=u and member_id=p_member for update;old:=case when found then to_jsonb(r) else null end;
 if old is null then
  if p_expected_version<>0 then raise exception 'staff_changed';end if;
  if not exists(select 1 from auth.users where id=p_member) then raise exception 'staff_member_unavailable';end if;
  perform pg_advisory_xact_lock(hashtextextended('kashier.staff-member.'||p_member::text,0));
  if (select count(*) from public.store_cashiers where owner_id=u)>=50 or(select count(*) from public.store_cashiers where member_id=p_member)>=50 then raise exception 'staff_limit';end if;
  insert into public.store_cashiers(owner_id,member_id,member_name,store_name,can_discount,enabled,role) values(u,p_member,btrim(p_name),btrim(p_store),p_discount,p_enabled,p_role) returning * into r;k:='invite';
 else
  if r.version<>p_expected_version then raise exception 'staff_changed';end if;
  update public.store_cashiers set role=p_role,member_name=btrim(p_name),store_name=btrim(p_store),can_discount=p_discount,enabled=p_enabled,version=version+1,updated_at=now() where id=r.id returning * into r;k:='update';
 end if;
 result:=jsonb_build_object('id',p_id,'membership_id',r.id,'version',r.version::text);
 insert into public.staff_actions(id,owner_id,member_id,actor_id,membership_id,kind,before_state,after_state,request_payload,result_payload) values(p_id,u,p_member,u,r.id,k,old,to_jsonb(r),payload,result);return result;
end $$;
create function public.save_store_cashier(p_id uuid,p_member uuid,p_name text,p_store text,p_discount boolean,p_enabled boolean,p_expected_version bigint,p_role text default 'cashier') returns jsonb language sql security invoker set search_path='' as $$select private.save_store_cashier(p_id,p_member,p_name,p_store,p_discount,p_enabled,p_expected_version,p_role);$$;
revoke all on function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text),public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text) from public,anon,authenticated;
grant execute on function private.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text),public.save_store_cashier(uuid,uuid,text,text,boolean,boolean,bigint,text) to authenticated;
create function private.get_manager_sales_report(p_owner uuid,p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;v_start timestamptz;v_end timestamptz;v_rows jsonb;v_count bigint;v_sales numeric;v_returns numeric;v_cash numeric;v_debt numeric;v_discount numeric;begin
 r:=private.cashier_membership(p_owner);if r.role<>'manager' then raise exception 'staff_manager_required';end if;
 if p_from is null or p_to is null or p_from>p_to or p_to-p_from>365 or p_from<date '2000-01-01' or p_to>date '2100-12-31' then raise exception 'manager_invalid_range';end if;
 v_start:=p_from::timestamp at time zone 'Asia/Baghdad';v_end:=(p_to+1)::timestamp at time zone 'Asia/Baghdad';
 if (select count(*) from public.sales where owner_id=p_owner and created_at>=v_start and created_at<v_end)+(select count(*) from public.sale_reversals where owner_id=p_owner and created_at>=v_start and created_at<v_end)+(select count(*) from public.sale_returns where owner_id=p_owner and created_at>=v_start and created_at<v_end)>5000 then raise exception 'manager_too_many_rows';end if;
 with events as(
  select s.id,'sale'::text kind,s.id sale_id,s.receipt_no,s.receipt_no reference_no,s.created_at,s.payment_mode mode,s.total::numeric amount,(s.total-s.debt_amount)::numeric cash,s.debt_amount::numeric debt,s.discount::numeric discount,s.customer_name,s.actor_id,s.actor_name
  from public.sales s where s.owner_id=p_owner and s.created_at>=v_start and s.created_at<v_end
  union all select z.id,'full_return',z.sale_id,s.receipt_no,z.reversal_no,z.created_at,s.payment_mode,-z.total::numeric,-z.cash_refund::numeric,-z.debt_reversed::numeric,0,s.customer_name,null::uuid,null::text
  from public.sale_reversals z join public.sales s on s.id=z.sale_id and s.owner_id=p_owner where z.owner_id=p_owner and z.created_at>=v_start and z.created_at<v_end
  union all select z.id,'partial_return',z.sale_id,s.receipt_no,z.return_no,z.created_at,s.payment_mode,-z.total::numeric,-z.cash_refund::numeric,0,0,s.customer_name,null::uuid,null::text
  from public.sale_returns z join public.sales s on s.id=z.sale_id and s.owner_id=p_owner where z.owner_id=p_owner and z.created_at>=v_start and z.created_at<v_end
 ) select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'sale_id',sale_id,'receipt_no',receipt_no::text,'reference_no',reference_no::text,'created_at',created_at,'day',(created_at at time zone 'Asia/Baghdad')::date::text,'mode',mode,'amount',amount::text,'cash',cash::text,'debt',debt::text,'discount',discount::text,'customer_name',customer_name,'actor_id',actor_id,'actor_name',actor_name) order by created_at,kind,id),'[]'::jsonb),count(*),coalesce(sum(amount) filter(where kind='sale'),0),coalesce(-sum(amount) filter(where kind<>'sale'),0),coalesce(sum(cash),0),coalesce(sum(debt),0),coalesce(sum(discount),0)
 into v_rows,v_count,v_sales,v_returns,v_cash,v_debt,v_discount from events;
 return jsonb_build_object('scope','store-manager-sales-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'from',p_from::text,'to',p_to::text,'currency','IQD','timezone','Asia/Baghdad','generated_at',statement_timestamp(),'count',v_count,'sales_total',v_sales::text,'returns_total',v_returns::text,'net_total',(v_sales-v_returns)::text,'cash_net',v_cash::text,'debt_net',v_debt::text,'discounts',v_discount::text,'rows',v_rows);
end $$;
create function private.get_manager_receipt(p_owner uuid,p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.store_cashiers%rowtype;s public.sales%rowtype;v_returns jsonb;begin
 r:=private.cashier_membership(p_owner);if r.role<>'manager' then raise exception 'staff_manager_required';end if;
 select * into s from public.sales where id=p_id and owner_id=p_owner;if not found then raise exception 'staff_sale_unavailable';end if;
 with events as(select total,cash_refund,debt_reversed,true full_return from public.sale_reversals where owner_id=p_owner and sale_id=p_id union all select total,cash_refund,0,false from public.sale_returns where owner_id=p_owner and sale_id=p_id)
 select jsonb_build_object('count',count(*)::text,'total',coalesce(sum(total),0)::text,'cash_refund',coalesce(sum(cash_refund),0)::text,'debt_reversed',coalesce(sum(debt_reversed),0)::text,'full',coalesce(bool_or(full_return),false)) into v_returns from events;
 return jsonb_build_object('scope','store-manager-receipt-v1','owner_id',p_owner,'actor_id',auth.uid(),'store_name',r.store_name,'sale',to_jsonb(s)-'owner_id'-'request_payload','returns',v_returns);
end $$;
revoke all on function private.get_manager_sales_report(uuid,date,date),private.get_manager_receipt(uuid,uuid) from public,anon,authenticated;
grant execute on function private.get_manager_sales_report(uuid,date,date),private.get_manager_receipt(uuid,uuid) to authenticated;
create function public.get_manager_sales_report(p_owner uuid,p_from date,p_to date) returns jsonb language sql security invoker set search_path='' as $$select private.get_manager_sales_report(p_owner,p_from,p_to);$$;
create function public.get_manager_receipt(p_owner uuid,p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.get_manager_receipt(p_owner,p_id);$$;
revoke all on function public.get_manager_sales_report(uuid,date,date),public.get_manager_receipt(uuid,uuid) from public,anon,authenticated;
grant execute on function public.get_manager_sales_report(uuid,date,date),public.get_manager_receipt(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
