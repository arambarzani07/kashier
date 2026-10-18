begin;
select set_config('lh.owner',gen_random_uuid()::text,true),set_config('lh.product',gen_random_uuid()::text,true),set_config('lh.adjustment',gen_random_uuid()::text,true);
insert into auth.users(id,email) values(current_setting('lh.owner')::uuid,'loss-history@example.invalid');
select set_config('request.jwt.claims',json_build_object('sub',current_setting('lh.owner'),'role','authenticated')::text,true);set local role authenticated;
insert into public.products(id,name,sale_price) values(current_setting('lh.product')::uuid,'Loss history fixture',1000);
do $$declare p uuid:=current_setting('lh.product')::uuid;v bigint;begin
 perform public.post_purchase(gen_random_uuid(),jsonb_build_array(jsonb_build_object('product_id',p,'quantity_units',2000,'unit_cost',500)),'','','');
 select max(movement_no) into v from public.stock_movements where product_id=p;
 perform public.post_stock_waste(current_setting('lh.adjustment')::uuid,p,2000,v,1000,'history fixture');
end $$;
reset role;
-- Fixture-only timestamp placement around Baghdad midnight; all changes roll back.
update public.stock_adjustments set created_at='2026-01-01T21:00:00Z' where id=current_setting('lh.adjustment')::uuid;
update public.stock_movements set created_at='2026-01-01T21:00:00Z' where adjustment_id=current_setting('lh.adjustment')::uuid;
update public.inventory_cost_movements set created_at='2026-01-01T21:00:00Z' where id=(select id from public.stock_movements where adjustment_id=current_setting('lh.adjustment')::uuid);
set local role authenticated;
do $$begin if public.get_inventory_loss_report('2026-01-01','2026-01-01')->>'count'<>'0' or public.get_inventory_loss_report('2026-01-02','2026-01-02')->>'count'<>'1' then raise exception 'Baghdad date bound';end if;end $$;
reset role;
-- Simulate a legacy stock movement without a saved cost snapshot.
delete from public.inventory_cost_movements where id=(select id from public.stock_movements where adjustment_id=current_setting('lh.adjustment')::uuid);
set local role authenticated;
do $$declare x jsonb;begin x:=public.get_inventory_loss_report('2026-01-02','2026-01-02');if x->>'count'<>'1' or x->>'known_count'<>'0' or x->>'complete'<>'false' or x->'rows'->0->>'coverage'<>'legacy-no-cost-snapshot' or x->'rows'->0->'cost_iqd'<>'null'::jsonb then raise exception 'legacy cost invented or omitted';end if;end $$;
reset role;
-- Corrupt only this rollback fixture to verify history refusal.
update public.stock_movements set balance_after=1001 where adjustment_id=current_setting('lh.adjustment')::uuid;
set local role authenticated;
do $$begin begin perform public.get_inventory_loss_report('2026-01-02','2026-01-02');raise exception 'mismatch accepted';exception when raise_exception then if sqlerrm<>'loss_incomplete_stock_history' then raise;end if;end;end $$;
reset role;
select 'PASS: Baghdad midnight, missing legacy cost coverage and physical-history mismatch refusal' as verification;
rollback;
