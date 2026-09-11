-- ============================================================================
-- ROLLBACK of 20260911_pwa_prod_persistence_minimal.
--
-- Drops the three library tables and the five functions that migration created.
-- KEEPS the payment rail (pwa.payway_transactions, pwa.payway_claim) and the
-- schema itself. Touches nothing in public.*, auth.* or storage.*.
--
-- REFUSES if a live (not soft-deleted) project exists: those rows are people's
-- work. Delete or export them deliberately first; this script never guesses.
-- ============================================================================
begin;

do $guard$
begin
  if to_regclass('pwa.pwa_projects') is not null
     and exists (select 1 from pwa.pwa_projects where deleted_at is null) then
    raise exception 'pwa.pwa_projects holds live projects - NOT dropping the library.';
  end if;
end
$guard$;

drop table if exists pwa.pwa_messages, pwa.pwa_visions, pwa.pwa_projects cascade;

drop function if exists pwa.deep_duplicate_project(uuid, text);
drop function if exists pwa.soft_delete_project(uuid);
drop function if exists pwa.guard_message_immutable();
drop function if exists pwa.set_owner_user_id();
drop function if exists pwa.touch_updated_at();

commit;

notify pgrst, 'reload schema';
