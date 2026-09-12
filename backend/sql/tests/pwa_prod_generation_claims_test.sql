-- ============================================================================
-- pwa_prod_generation_claims_test — read-only contract check, run AFTER
-- 20260912_pwa_prod_generation_claims.sql. Every row: check + PASS/FAIL.
--
-- Behaviour (claim once, no double debit, settle, retry) is proved by the
-- functional harness in the apply script, which runs inside a rolled-back
-- transaction with a real auth.uid(). This file checks the SHAPE.
-- ============================================================================
with checks(name, ok) as (
  values
  ('table pwa.pwa_generation_claims exists',
   to_regclass('pwa.pwa_generation_claims') is not null),
  ('the identity index is UNIQUE on (owner_user_id, idempotency_key)',
   exists (select 1 from pg_indexes where schemaname = 'pwa'
            and indexname = 'pwa_generation_claims_identity'
            and indexdef like '%UNIQUE%owner_user_id, idempotency_key%')),
  ('state is constrained to PROCESSING / COMPLETED / FAILED',
   exists (select 1 from pg_constraint
            where conname = 'pwa_generation_claims_state_check'
              and connamespace = 'pwa'::regnamespace)),
  ('RLS is enabled on the claims table',
   (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'pwa' and c.relname = 'pwa_generation_claims')),
  ('3 claim policies, authenticated only',
   (select count(*) = 3 from pg_policies where schemaname = 'pwa'
     and tablename = 'pwa_generation_claims' and roles::text = '{authenticated}')),
  ('anon has no privilege on the claims table',
   not exists (select 1 from information_schema.role_table_grants
                where table_schema = 'pwa' and table_name = 'pwa_generation_claims'
                  and grantee = 'anon')),
  ('authenticated cannot DELETE a claim',
   not exists (select 1 from information_schema.role_table_grants
                where table_schema = 'pwa' and table_name = 'pwa_generation_claims'
                  and grantee = 'authenticated' and privilege_type = 'DELETE')),
  ('the three functions exist',
   (select count(*) = 3 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'pwa'
       and p.proname in ('claim_generation','complete_generation','fail_generation'))),
  ('no function searches the staging schema',
   not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'pwa'
                  and (array_to_string(p.proconfig, ',') like '%pwa_staging%'
                       or p.prosrc like '%pwa_staging%'))),
  ('no claim function reads or writes public.* (billing is untouched)',
   not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'pwa'
                  and p.proname in ('claim_generation','complete_generation','fail_generation')
                  and p.prosrc like '%public.%')),
  ('the library and the rail are still there (5 tables in pwa)',
   (select count(*) = 5 from pg_tables where schemaname = 'pwa')),
  ('no new object in public',
   not exists (select 1 from pg_tables where schemaname = 'public'
                and tablename like 'pwa%'))
)
select name as check, case when ok then 'PASS' else 'FAIL' end as result
from checks order by (case when ok then 1 else 0 end), name;
