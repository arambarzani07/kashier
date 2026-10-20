-- Access X: read-only one-primary-manager cutover preflight; not a role-enforcement migration.
-- Fails if any existing delegated manager membership must first be migrated.
begin transaction read only;
do $ax$
declare managers integer;invalid integer;dup integer;u integer;
begin
 select count(*) into managers from public.store_cashiers where role='manager';
 select count(*) into invalid from public.store_cashiers where role<>'cashier';
 select count(*) into dup from (select owner_id,member_id from public.store_cashiers group by owner_id,member_id having count(*)>1) x;
 select count(*) into u from public.store_cashiers s
 where not exists(select 1 from auth.users a where a.id=s.owner_id)
    or not exists(select 1 from auth.users a where a.id=s.member_id);
 if managers>0 or invalid>0 then raise exception 'access_x_delegated_manager_migration_required';end if;
 if dup>0 or u>0 then raise exception 'access_x_membership_integrity_failed';end if;
end $ax$;
select 'PASS: no delegated managers; membership records compatible with single primary owner + cashier-only future model (no enforcement change)' as access_x_two_role_preflight;
rollback;
