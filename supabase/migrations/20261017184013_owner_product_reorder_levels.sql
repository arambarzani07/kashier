-- Optional minimum quantity in thousandths; no stock or ledger mutation.
alter table public.products add column reorder_units bigint check(reorder_units between 0 and 1000000000000);
grant insert(reorder_units),update(reorder_units) on public.products to authenticated;
create index products_owner_reorder_idx on public.products(owner_id,id) where reorder_units is not null;
create view public.low_stock_catalog with(security_invoker=true,security_barrier=true) as
 select p.id,p.name,p.barcode,p.sale_price,p.created_at,p.reorder_units,coalesce(s.quantity_units,0)::bigint as quantity_units
 from public.products p left join public.product_stock s on s.product_id=p.id and s.owner_id=p.owner_id
 where p.owner_id=(select auth.uid()) and p.reorder_units is not null and coalesce(s.quantity_units,0)<=p.reorder_units;
revoke all on public.low_stock_catalog from public,anon,authenticated;
grant select on public.low_stock_catalog to authenticated;
notify pgrst,'reload schema';
