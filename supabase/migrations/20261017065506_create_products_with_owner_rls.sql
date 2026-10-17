create table public.products (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
 name text not null check (char_length(btrim(name)) between 1 and 150 and name=btrim(name)),
 barcode text check (barcode is null or (char_length(barcode) between 1 and 64 and barcode=btrim(barcode))),
 sale_price bigint not null check (sale_price between 1 and 1000000000),
 created_at timestamptz not null default now(),
 constraint products_owner_barcode_key unique (owner_id, barcode)
);
create index products_owner_created_idx on public.products(owner_id, created_at desc, id);
alter table public.products enable row level security;
revoke all on public.products from anon, authenticated;
grant select on public.products to authenticated;
grant insert (id,name,barcode,sale_price) on public.products to authenticated;
grant update (name,barcode,sale_price) on public.products to authenticated;
create policy products_read_own on public.products for select to authenticated using ((select auth.uid())=owner_id);
create policy products_insert_own on public.products for insert to authenticated with check ((select auth.uid())=owner_id);
create policy products_update_own on public.products for update to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
notify pgrst, 'reload schema';
