-- ============================================================================
-- pwa_prod_auth_phone_change_release_test — read-only contract check, run
-- AFTER 20260911_pwa_prod_auth_phone_change_release.sql. check + PASS/FAIL.
-- ============================================================================
with f as (
  select p.oid, p.prosecdef, p.proconfig, p.prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'pwa' and p.proname = 'auth_phone_change_release'
), checks(name, ok) as (
  values
  ('function pwa.auth_phone_change_release exists (exactly one)', (select count(*) = 1 from f)),
  ('SECURITY DEFINER', (select bool_and(prosecdef) from f)),
  ('search_path pinned to pg_catalog, public', (select bool_and(array_to_string(proconfig, ',') like '%search_path=pg_catalog, public%') from f)),
  ('service_role may execute', has_function_privilege('service_role', 'pwa.auth_phone_change_release(text, uuid, integer)', 'execute')),
  ('anon may NOT execute', not has_function_privilege('anon', 'pwa.auth_phone_change_release(text, uuid, integer)', 'execute')),
  ('authenticated may NOT execute', not has_function_privilege('authenticated', 'pwa.auth_phone_change_release(text, uuid, integer)', 'execute')),
  ('body never touches the verified phone column or public.*',
   (select bool_and(prosrc not like '%set phone %' and prosrc not like '%public.%') from f)),
  ('no staging schema reference', (select bool_and(prosrc not like '%pwa_staging%') from f)),
  ('the library and payment rail are untouched (4 tables in pwa)',
   (select count(*) = 4 from pg_tables where schemaname = 'pwa'))
)
select name as check, case when ok then 'PASS' else 'FAIL' end as result
from checks order by (case when ok then 1 else 0 end), name;
