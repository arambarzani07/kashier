-- Catalog-only import. Every request commits in full or rolls back in full.
create function public.import_products(p_rows jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare v_user uuid:=auth.uid();r jsonb;p public.products%rowtype;n int;added int:=0;existing int:=0;v_id uuid;v_name text;v_barcode text;v_price bigint;
begin
 if v_user is null then raise exception 'import_auth_required';end if;
 if jsonb_typeof(p_rows) is distinct from 'array' then raise exception 'import_invalid_rows';end if;
 n:=jsonb_array_length(p_rows);if n<1 or n>500 or octet_length(p_rows::text)>1048576 then raise exception 'import_invalid_rows';end if;
 -- Validate the whole payload before any writes; no stock, owner or timestamp fields accepted.
 for r in select value from jsonb_array_elements(p_rows) loop
  if jsonb_typeof(r) is distinct from 'object' then raise exception 'import_invalid_rows';end if;
  if (select count(*) from jsonb_object_keys(r))<>4 or not (r ?& array['id','name','barcode','sale_price'])
   or jsonb_typeof(r->'id') is distinct from 'string' or (r->>'id')!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   or jsonb_typeof(r->'name') is distinct from 'string' or char_length(btrim(r->>'name')) not between 1 and 150 or r->>'name'<>btrim(r->>'name')
   or jsonb_typeof(r->'barcode') not in ('null','string')
   or ((r->>'barcode') is not null and (char_length(r->>'barcode') not between 1 and 64 or r->>'barcode'<>btrim(r->>'barcode')))
   or jsonb_typeof(r->'sale_price') is distinct from 'number' or (r->>'sale_price')!~'^[0-9]{1,10}$'
  then raise exception 'import_invalid_rows';end if;
  if (r->>'sale_price')::bigint not between 1 and 1000000000 then raise exception 'import_invalid_rows';end if;
 end loop;
 if (select count(distinct (value->>'id')::uuid) from jsonb_array_elements(p_rows))<>n
  or exists(select 1 from jsonb_array_elements(p_rows) where value->>'barcode' is not null group by value->>'barcode' having count(*)>1)
 then raise exception 'import_duplicate_rows';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||':product-import',0));
 for r in select value from jsonb_array_elements(p_rows) order by value->>'id' loop
  v_id:=(r->>'id')::uuid;v_name:=r->>'name';v_barcode:=r->>'barcode';v_price:=(r->>'sale_price')::bigint;
  select * into p from public.products where id=v_id and owner_id=v_user for update;
  if found then
   if p.name is distinct from v_name or p.barcode is distinct from v_barcode or p.sale_price is distinct from v_price then raise exception 'import_request_conflict';end if;
   existing:=existing+1;
  else
   insert into public.products(id,name,barcode,sale_price) values(v_id,v_name,v_barcode,v_price);
   added:=added+1;
  end if;
 end loop;
 return jsonb_build_object('total',n,'inserted',added,'already_present',existing);
end $$;
revoke all on function public.import_products(jsonb) from public,anon,authenticated;
grant execute on function public.import_products(jsonb) to authenticated;
notify pgrst,'reload schema';
