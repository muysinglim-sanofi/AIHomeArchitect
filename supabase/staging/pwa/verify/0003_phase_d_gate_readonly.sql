-- ============================================================================
-- AYDEN STUDIO PWA — STAGING — PHASE D GATE (SELF-ASSERTING, READ-ONLY)
-- Run in the SQL Editor of project ref eedcahzekpgxvvfxufbk AFTER 0002.
-- ----------------------------------------------------------------------------
-- Unlike 0002_verify_readonly.sql (which returns rows to eyeball), THIS script
-- ASSERTS: each gate RAISEs a descriptive exception on failure, so the run
-- either aborts on the first failing gate (you see exactly which) or ends with
-- a single 'ALL CHECKS PASSED' row. It writes NOTHING: it runs inside a
-- READ ONLY transaction (any accidental write would error) and only SELECTs
-- catalogs + RAISEs. Safe to run any number of times.
-- ============================================================================

begin;
set transaction read only;

-- Gate 1 — schema exists
do $$ begin
  if not exists (select 1 from pg_namespace where nspname = 'pwa_staging') then
    raise exception 'GATE 1 FAIL: schema pwa_staging does not exist';
  end if;
end $$;

-- Gate 2 — the 4 tenant tables exist
do $$ declare n int; begin
  select count(*) into n from information_schema.tables
  where table_schema = 'pwa_staging'
    and table_name in ('pwa_installations','pwa_projects','pwa_visions','pwa_messages');
  if n <> 4 then raise exception 'GATE 2 FAIL: expected 4 tables, found %', n; end if;
end $$;

-- Gate 3 — RLS ENABLED and FORCED on all 4
do $$ declare n int; begin
  select count(*) into n from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'pwa_staging' and c.relkind = 'r'
    and c.relrowsecurity and c.relforcerowsecurity
    and c.relname in ('pwa_installations','pwa_projects','pwa_visions','pwa_messages');
  if n <> 4 then raise exception 'GATE 3 FAIL: RLS enabled+forced on % of 4 tables', n; end if;
end $$;

-- Gate 4 — exactly 11 policies, every one to authenticated, none to anon/public
do $$ declare total int; bad int; allauth bool; begin
  select count(*) into total from pg_policies where schemaname = 'pwa_staging';
  if total <> 11 then raise exception 'GATE 4 FAIL: expected 11 policies, found %', total; end if;
  select count(*) into bad from pg_policies
  where schemaname = 'pwa_staging' and ('anon' = any(roles) or 'public' = any(roles));
  if bad <> 0 then raise exception 'GATE 4 FAIL: % policy(ies) target anon/public', bad; end if;
  select bool_and(roles = array['authenticated']::name[]) into allauth
  from pg_policies where schemaname = 'pwa_staging';
  if not coalesce(allauth, false) then raise exception 'GATE 4 FAIL: a policy is not authenticated-only'; end if;
end $$;

-- Gate 5 — no anon/public table grants; schema USAGE anon/public=false, authenticated=true
do $$ declare g int; begin
  select count(*) into g from information_schema.role_table_grants
  where table_schema = 'pwa_staging' and grantee in ('anon','public');
  if g <> 0 then raise exception 'GATE 5 FAIL: % anon/public table grant(s)', g; end if;
  if has_schema_privilege('anon','pwa_staging','USAGE')   then raise exception 'GATE 5 FAIL: anon has schema USAGE'; end if;
  if has_schema_privilege('public','pwa_staging','USAGE') then raise exception 'GATE 5 FAIL: public has schema USAGE'; end if;
  if not has_schema_privilege('authenticated','pwa_staging','USAGE') then raise exception 'GATE 5 FAIL: authenticated lacks schema USAGE'; end if;
end $$;

-- Gate 6 — authenticated table privileges: append-only visions = SELECT,INSERT;
-- installations/projects/messages = SELECT,INSERT,UPDATE; none have DELETE
do $$ declare v text; p text; begin
  select string_agg(privilege_type, ',' order by privilege_type) into v
  from information_schema.role_table_grants
  where table_schema='pwa_staging' and table_name='pwa_visions' and grantee='authenticated';
  if coalesce(v,'') <> 'INSERT,SELECT' then raise exception 'GATE 6 FAIL: visions authed privs = % (want INSERT,SELECT)', v; end if;
  for p in select unnest(array['pwa_installations','pwa_projects','pwa_messages']) loop
    if (select string_agg(privilege_type, ',' order by privilege_type)
        from information_schema.role_table_grants
        where table_schema='pwa_staging' and table_name=p and grantee='authenticated')
       <> 'INSERT,SELECT,UPDATE'
      then raise exception 'GATE 6 FAIL: % authed privs are not INSERT,SELECT,UPDATE', p; end if;
  end loop;
  if exists (select 1 from information_schema.role_table_grants
             where table_schema='pwa_staging' and grantee='authenticated' and privilege_type='DELETE')
    then raise exception 'GATE 6 FAIL: a DELETE grant exists for authenticated'; end if;
end $$;

-- Gate 7 — the 7 named composite FKs exist with expected deferrable/deferred
do $$
declare
  rec record;
  expect constant text[][] := array[
    ['pwa_visions_project_owner_fk','f','f'],
    ['pwa_visions_parent_owner_fk','t','t'],
    ['pwa_visions_srcmsg_owner_fk','t','t'],
    ['pwa_messages_project_owner_fk','f','f'],
    ['pwa_messages_refvision_owner_fk','f','f'],
    ['pwa_projects_current_vision_fk','t','t'],
    ['pwa_projects_cover_vision_fk','t','t']
  ];
  i int;
begin
  for i in 1 .. array_length(expect,1) loop
    select condeferrable, condeferred into rec
    from pg_constraint
    where connamespace = 'pwa_staging'::regnamespace and contype='f' and conname = expect[i][1];
    if not found then raise exception 'GATE 7 FAIL: FK % missing', expect[i][1]; end if;
    if (case when rec.condeferrable then 't' else 'f' end) <> expect[i][2]
       or (case when rec.condeferred then 't' else 'f' end) <> expect[i][3]
      then raise exception 'GATE 7 FAIL: FK % deferrable/deferred mismatch (got %/%, want %/%)',
        expect[i][1], rec.condeferrable, rec.condeferred, expect[i][2], expect[i][3]; end if;
  end loop;
end $$;

-- Gate 8 — 4 owner FKs to auth.users
do $$ declare n int; begin
  select count(*) into n from pg_constraint
  where connamespace = 'pwa_staging'::regnamespace and contype='f'
    and confrelid = 'auth.users'::regclass;
  if n <> 4 then raise exception 'GATE 8 FAIL: expected 4 owner->auth.users FKs, found %', n; end if;
end $$;

-- Gate 9 — expected UNIQUE constraints present
do $$
declare want text[] := array[
  'pwa_projects','pwa_visions','pwa_messages','pwa_installations'];
  need_projects int; need_visions int; need_messages int; need_inst int;
begin
  -- projects: unique(id, owner_user_id)
  select count(*) into need_projects from pg_constraint
   where connamespace='pwa_staging'::regnamespace and conrelid='pwa_staging.pwa_projects'::regclass and contype='u';
  select count(*) into need_visions from pg_constraint
   where connamespace='pwa_staging'::regnamespace and conrelid='pwa_staging.pwa_visions'::regclass and contype='u';
  select count(*) into need_messages from pg_constraint
   where connamespace='pwa_staging'::regnamespace and conrelid='pwa_staging.pwa_messages'::regclass and contype='u';
  select count(*) into need_inst from pg_constraint
   where connamespace='pwa_staging'::regnamespace and conrelid='pwa_staging.pwa_installations'::regclass and contype='u';
  if need_projects < 1 or need_visions < 3 or need_messages < 2 or need_inst < 2 then
    raise exception 'GATE 9 FAIL: unique counts proj=% vis=% msg=% inst=% (want >=1/3/2/2)',
      need_projects, need_visions, need_messages, need_inst;
  end if;
end $$;

-- Gate 10 — explicit indexes present
do $$ declare miss text; begin
  for miss in select unnest(array[
    'pwa_projects_owner_deleted_idx','pwa_projects_owner_updated_idx','pwa_projects_owner_status_idx',
    'pwa_visions_project_idx','pwa_messages_project_idx']) loop
    if not exists (select 1 from pg_indexes where schemaname='pwa_staging' and indexname=miss) then
      raise exception 'GATE 10 FAIL: index % missing', miss; end if;
  end loop;
end $$;

-- Gate 11 — functions: security mode, search_path set, RPC execute scoping
do $$
declare rid oid; tid oid; begin
  -- deep_duplicate is DEFINER
  if not (select prosecdef from pg_proc where pronamespace='pwa_staging'::regnamespace and proname='deep_duplicate_project')
    then raise exception 'GATE 11 FAIL: deep_duplicate_project is not SECURITY DEFINER'; end if;
  -- the other five are INVOKER
  if exists (select 1 from pg_proc where pronamespace='pwa_staging'::regnamespace
             and proname in ('set_owner_user_id','touch_updated_at','guard_message_immutable',
                             'upsert_installation','soft_delete_project') and prosecdef)
    then raise exception 'GATE 11 FAIL: a non-deep_duplicate function is DEFINER'; end if;
  -- every function pins search_path
  if exists (select 1 from pg_proc p where p.pronamespace='pwa_staging'::regnamespace
             and not exists (select 1 from unnest(coalesce(p.proconfig,array[]::text[])) c where c like 'search_path=%'))
    then raise exception 'GATE 11 FAIL: a function has no fixed search_path'; end if;
  -- the 3 business RPCs: authenticated can execute; anon/public cannot
  for rid in select oid from pg_proc where pronamespace='pwa_staging'::regnamespace
             and proname in ('upsert_installation','soft_delete_project','deep_duplicate_project') loop
    if not has_function_privilege('authenticated', rid, 'EXECUTE') then raise exception 'GATE 11 FAIL: an RPC is not executable by authenticated'; end if;
    if has_function_privilege('anon', rid, 'EXECUTE')   then raise exception 'GATE 11 FAIL: an RPC is executable by anon'; end if;
    if has_function_privilege('public', rid, 'EXECUTE') then raise exception 'GATE 11 FAIL: an RPC is executable by public'; end if;
  end loop;
end $$;

-- Gate 12 — private bucket with exact size + MIME
do $$ declare b record; begin
  select public, file_size_limit, allowed_mime_types into b
  from storage.buckets where id = 'pwa-staging-images';
  if not found then raise exception 'GATE 12 FAIL: bucket pwa-staging-images missing'; end if;
  if b.public then raise exception 'GATE 12 FAIL: bucket is public'; end if;
  if b.file_size_limit <> 10485760 then raise exception 'GATE 12 FAIL: size limit = % (want 10485760)', b.file_size_limit; end if;
  if b.allowed_mime_types <> array['image/jpeg','image/png','image/webp']::text[]
    then raise exception 'GATE 12 FAIL: MIME allowlist = %', b.allowed_mime_types; end if;
end $$;

-- Gate 13 — exactly 2 Storage policies (SELECT+INSERT), authenticated, uid-scoped,
-- and NO update/delete policy on the bucket
do $$ declare n int; cmds text; scoped int; begin
  select count(*) into n from pg_policies
  where schemaname='storage' and tablename='objects' and policyname like 'pwa_staging_images_%';
  if n <> 2 then raise exception 'GATE 13 FAIL: expected 2 storage policies, found %', n; end if;
  if exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
             and policyname like 'pwa_staging_images_%' and cmd in ('UPDATE','DELETE'))
    then raise exception 'GATE 13 FAIL: an UPDATE/DELETE storage policy exists'; end if;
  if exists (select 1 from pg_policies where schemaname='storage' and tablename='objects'
             and policyname like 'pwa_staging_images_%' and not (roles = array['authenticated']::name[]))
    then raise exception 'GATE 13 FAIL: a storage policy is not authenticated-only'; end if;
  select count(*) into scoped from pg_policies where schemaname='storage' and tablename='objects'
    and policyname like 'pwa_staging_images_%'
    and coalesce(qual,'') || coalesce(with_check,'') like '%foldername%'
    and coalesce(qual,'') || coalesce(with_check,'') like '%uid%';
  if scoped <> 2 then raise exception 'GATE 13 FAIL: storage policies are not uid/foldername-scoped (%/2)', scoped; end if;
end $$;

-- Gate 14 — no PWA table leaked into public
do $$ declare n int; begin
  select count(*) into n from information_schema.tables
  where table_schema='public' and table_name like 'pwa\_%';
  if n <> 0 then raise exception 'GATE 14 FAIL: % public.pwa_* table(s) present', n; end if;
end $$;

select 'PHASE D GATE: ALL CHECKS PASSED' as result;

commit;
