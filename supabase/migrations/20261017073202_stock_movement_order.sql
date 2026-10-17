alter table public.stock_movements add column movement_no bigint generated always as identity unique;
revoke all on sequence public.stock_movements_movement_no_seq from anon,authenticated;
create index stock_movements_product_order_idx on public.stock_movements(product_id,movement_no desc);
notify pgrst,'reload schema';
