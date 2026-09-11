-- ============================================================================
-- ROLLBACK of 20260911_pwa_prod_auth_phone_change_release.
-- Drops ONLY pwa.auth_phone_change_release. Rows it already released are not
-- restored (they were expired attempts that could never verify). After this,
-- POST /pwa/auth/phone/prepare answers 503 again (fail closed).
-- ============================================================================
begin;
drop function if exists pwa.auth_phone_change_release(text, uuid, integer);
commit;
notify pgrst, 'reload schema';
