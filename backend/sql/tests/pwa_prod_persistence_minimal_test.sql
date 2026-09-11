-- ============================================================================
-- pwa_prod_persistence_minimal_test — read-only contract check, run AFTER
-- 20260911_pwa_prod_persistence_minimal.sql. Every row: check + PASS/FAIL.
-- ============================================================================
with checks(name, ok) as (
  values
  ('the three library tables exist',
   to_regclass('pwa.pwa_projects') is not null
   and to_regclass('pwa.pwa_visions') is not null
   and to_regclass('pwa.pwa_messages') is not null),
  ('exactly 4 tables in pwa (rail + library, nothing else)',
   (select count(*) = 4 from pg_tables where schemaname = 'pwa')),
  ('generation / installation / storage objects NOT created',
   to_regclass('pwa.pwa_generation_claims') is null
   and to_regclass('pwa.pwa_installations') is null
   and not exists (select 1 from storage.buckets where id = 'pwa-images')),
  ('RLS enabled AND forced on the library tables',
   (select bool_and(c.relrowsecurity and c.relforcerowsecurity) from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'pwa' and c.relname in ('pwa_projects','pwa_visions','pwa_messages'))),
  ('8 library policies, all for role authenticated',
   (select count(*) = 8 from pg_policies
     where schemaname = 'pwa' and tablename in ('pwa_projects','pwa_visions','pwa_messages')
       and roles::text = '{authenticated}')),
  ('anon has no privilege on any pwa table',
   not exists (select 1 from information_schema.role_table_grants
                where table_schema = 'pwa' and grantee = 'anon')),
  ('authenticated cannot DELETE anywhere in pwa',
   not exists (select 1 from information_schema.role_table_grants
                where table_schema = 'pwa' and grantee = 'authenticated'
                  and privilege_type = 'DELETE')),
  ('6 functions in pwa (payway_claim + 5 library)',
   (select count(*) = 6 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pwa')),
  ('no function searches the staging schema',
   not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'pwa'
                  and (array_to_string(p.proconfig, ',') like '%pwa_staging%'
                       or p.prosrc like '%pwa_staging%'))),
  ('5 triggers on the library tables',
   (select count(*) = 5 from pg_trigger t join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'pwa' and not t.tgisinternal
       and c.relname in ('pwa_projects','pwa_visions','pwa_messages'))),
  ('the payment rail is untouched (table + claim function present)',
   to_regclass('pwa.payway_transactions') is not null
   and exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'pwa' and p.proname = 'payway_claim')),
  ('no new object in public',
   not exists (select 1 from pg_tables where schemaname = 'public'
                and tablename like 'pwa%'))
)
select name as check, case when ok then 'PASS' else 'FAIL' end as result
from checks
order by (case when ok then 1 else 0 end), name;
