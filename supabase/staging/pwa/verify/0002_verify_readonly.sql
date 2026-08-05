-- ============================================================================
-- AYDEN STUDIO PWA — STAGING 0002 — READ-ONLY VERIFICATION (§40)
-- Safe to run any number of times. Reads catalogs only; writes NOTHING.
-- Run in the SQL Editor of project ref eedcahzekpgxvvfxufbk AFTER 0002.
-- ============================================================================

-- 1. Schema + tables exist (expect 4 tables).
select table_name
from information_schema.tables
where table_schema = 'pwa_staging'
order by table_name;

-- 2. RLS enabled AND forced on every tenant table (expect rls=t, force=t x4).
select c.relname as table_name, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'pwa_staging' and c.relkind = 'r'
order by c.relname;

-- 3. Policies: name, command, roles, USING + WITH CHECK. No role should be
--    anon/public; every expression must reference auth.uid().
select tablename, policyname, cmd, roles,
       qual        as using_expr,
       with_check  as with_check_expr
from pg_policies
where schemaname = 'pwa_staging'
order by tablename, policyname;

-- 4. Table privileges granted to anon/public MUST be empty.
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'pwa_staging' and grantee in ('anon','public')
order by table_name, grantee;

-- 4b. Schema-level USAGE for anon/public MUST be false (defense-in-depth).
select nspname,
       has_schema_privilege('anon', oid, 'USAGE')   as anon_usage,
       has_schema_privilege('public', oid, 'USAGE')  as public_usage,
       has_schema_privilege('authenticated', oid, 'USAGE') as authed_usage
from pg_namespace where nspname = 'pwa_staging';

-- 5. Table privileges granted to authenticated (expected per table).
select table_name, grantee, string_agg(privilege_type, ',' order by privilege_type) as privs
from information_schema.role_table_grants
where table_schema = 'pwa_staging' and grantee = 'authenticated'
group by table_name, grantee
order by table_name;

-- 6. Functions: security type + search_path + execute grants.
select p.proname,
       case when p.prosecdef then 'DEFINER' else 'INVOKER' end as security,
       coalesce(array_to_string(p.proconfig, ','), '(none)') as config,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authed_exec,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'pwa_staging'
order by p.proname;

-- 7. Foreign keys (ownership-aware composites) + constraints.
select conrelid::regclass as child, conname,
       pg_get_constraintdef(oid) as definition
from pg_constraint
where connamespace = 'pwa_staging'::regnamespace and contype in ('f','u','c')
order by child, contype, conname;

-- 8. Indexes.
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'pwa_staging'
order by tablename, indexname;

-- 9. Storage bucket is PRIVATE with size/MIME limits (expect public=false).
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id = 'pwa-staging-images';

-- 10. Storage policies on storage.objects for the bucket (no anon/public read).
select policyname, cmd, roles, qual as using_expr, with_check as with_check_expr
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
  and policyname like 'pwa_staging_images_%'
order by policyname;

-- 11. Sanity: NO production/other object was touched — pwa_staging is the only
--     new schema and no public.* PWA table leaked.
select nspname from pg_namespace where nspname = 'pwa_staging';
select count(*) as public_pwa_tables
from information_schema.tables
where table_schema = 'public' and table_name like 'pwa\_%';
