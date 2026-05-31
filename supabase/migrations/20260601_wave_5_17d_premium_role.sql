-- ============================================================
-- Wave 5.17d — Premium role write privileges
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ============================================================
--
-- Wave 5.17b's migration granted `SELECT` on user_roles to the
-- service_role because the backend only READ the table (admin bypass
-- lookup). Wave 5.17d's RevenueCat webhook needs to WRITE premium
-- grants on every subscription lifecycle event, so this migration
-- adds INSERT/UPDATE/DELETE.
--
-- Idempotent + additive — safe to re-apply.
-- Rollback : REVOKE INSERT, UPDATE, DELETE ON public.user_roles FROM
--            service_role.
-- ============================================================

grant insert, update, delete on public.user_roles to service_role;

-- Sanity check — paste in SQL Editor after applying :
--
--   select grantee, privilege_type
--   from information_schema.role_table_grants
--   where table_schema = 'public' and table_name = 'user_roles'
--   order by grantee, privilege_type;
--
-- Expected (at minimum) :
--   authenticated  | SELECT
--   service_role   | DELETE
--   service_role   | INSERT
--   service_role   | SELECT
--   service_role   | UPDATE

-- ============================================================
-- End Wave 5.17d migration.
-- ============================================================
