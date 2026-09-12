-- ============================================================================
-- ROLLBACK of 20260912_pwa_prod_generation_claims.
--
-- Drops the reservation table and its three functions. Keeps the library
-- (projects/visions/messages), the payment rail and the phone-change release.
-- Touches nothing in public.*, auth.* or storage.*.
--
-- REFUSES while a claim is still PROCESSING: that row is a render someone may
-- still be waiting on, and dropping it would let a retry call the provider a
-- second time. Settle or wait, then roll back.
-- ============================================================================
begin;

do $guard$
begin
  if to_regclass('pwa.pwa_generation_claims') is not null
     and exists (select 1 from pwa.pwa_generation_claims where state = 'PROCESSING') then
    raise exception 'pwa.pwa_generation_claims holds PROCESSING claims - NOT dropping it.';
  end if;
end
$guard$;

drop table if exists pwa.pwa_generation_claims cascade;

drop function if exists pwa.claim_generation(text, uuid, text, uuid);
drop function if exists pwa.complete_generation(text, uuid);
drop function if exists pwa.fail_generation(text, text, boolean);

commit;

notify pgrst, 'reload schema';
