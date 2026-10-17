create index if not exists purchase_returns_supplier_owner_created_idx on public.purchase_returns(supplier_id,owner_id,created_at desc) where supplier_id is not null;
create index if not exists purchase_reversals_supplier_owner_created_idx on public.purchase_reversals(supplier_id,owner_id,created_at desc) where supplier_id is not null;
