-- ============================================================================
-- AYDEN STUDIO PWA — STAGING STORAGE FOR REAL GENERATION
-- 0003 — additive, IDEMPOTENT ensure of the private image bucket + policies.
-- Schema: pwa_staging (untouched here).  STAGING ONLY.  Manual SQL Editor only.
-- ----------------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--   0002 created `pwa-staging-images` and its two policies inside a single
--   transaction that FAILS CLOSED when `pwa_staging` already exists. Once 0002
--   has been applied it can never be replayed, so there is no supported way to
--   repair or extend the Storage half. 0003 is that way: it touches ONLY
--   storage.buckets / storage.policies, creates nothing that already exists,
--   and can be run any number of times.
--
--   Verified against the live staging project before writing: the bucket and
--   both 0002 policies are already present, so on today's staging this file is
--   a NO-OP that reports what it found. That is the point — it is the repair
--   and drift-check path, not a second creation path.
--
-- WHAT IT MAY DO
--   * create the private bucket `pwa-staging-images` if missing (10 MB,
--     jpeg/png/webp)
--   * align those three settings if the bucket exists but drifted
--   * create ONLY the missing scoped policies on storage.objects
--
-- WHAT IT NEVER DOES
--   * touch pwa_staging.* (tables, RLS, RPCs) — 0002 owns those
--   * touch any production object
--   * make the bucket public
--   * drop or weaken an existing policy
--   * contain a secret of any kind
--
-- SAFETY
--   * ONE transaction; the guard RAISEs before any DDL, so absent GUCs abort
--     the whole thing and NOTHING is written (self-enforcing).
--   * Two session GUCs are required (DB-name checks are unreliable on Supabase,
--     where staging and prod are both `postgres` — the connection target MUST
--     be operator-verified to be project ref eedcahzekpgxvvfxufbk):
--        set app.ayden_allow_staging_migrations = 'true';
--        set app.ayden_env = 'staging';
--   * UNLIKE 0002 it does NOT fail on an existing pwa_staging — being replayable
--     is the whole purpose. It fails closed if pwa_staging is ABSENT, because
--     that would mean this is not the PWA staging project at all.
--
-- PATH CONVENTION (unchanged from 0002, extended by use not by policy):
--     users/{authUid}/projects/{projectId}/original/{objectId}.{ext}
--     users/{authUid}/projects/{projectId}/generated/{visionId}.jpg
--   The policies key off segments 1-2 ('users' / authUid) ONLY, so the
--   generated/ subtree is already covered by the original 0002 policies. No
--   policy change is needed for real generation — only this note.
-- ============================================================================

begin;

-- ── Guard (fail closed) ─────────────────────────────────────────────────────
do $guard$
begin
  if coalesce(current_setting('app.ayden_allow_staging_migrations', true), 'false') <> 'true' then
    raise exception
      'Refusing PWA staging migration 0003: app.ayden_allow_staging_migrations is not true (fail closed).';
  end if;
  if coalesce(current_setting('app.ayden_env', true), '') <> 'staging' then
    raise exception
      'Refusing PWA staging migration 0003: app.ayden_env is not ''staging'' (fail closed). Verify the connection target is the isolated staging project (ref eedcahzekpgxvvfxufbk).';
  end if;
  -- Inverse of 0002's guard: 0003 REPAIRS an applied schema, so its absence
  -- means we are pointed at the wrong project.
  if not exists (select 1 from pg_namespace where nspname = 'pwa_staging') then
    raise exception
      'Refusing PWA staging migration 0003: schema pwa_staging does not exist. Apply 0002 first — this is not the PWA staging project.';
  end if;
end
$guard$;

-- ── The private bucket (create if missing, align if drifted) ────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pwa-staging-images', 'pwa-staging-images', false, 10485760,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public            = false,
      file_size_limit   = 10485760,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- ── Scoped policies — created ONLY if absent ────────────────────────────────
-- Owner is the {authUid} path segment, matching 0002 exactly. Re-declaring the
-- same predicate here keeps the file self-describing; the `if not exists`
-- guards mean an applied 0002 is never clobbered.
do $policies$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'pwa_staging_images_sel'
  ) then
    create policy pwa_staging_images_sel on storage.objects
      for select to authenticated using (
        bucket_id = 'pwa-staging-images'
        and (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid())::text
      );
    raise notice '0003: created policy pwa_staging_images_sel';
  else
    raise notice '0003: policy pwa_staging_images_sel already present — left untouched';
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects'
      and policyname = 'pwa_staging_images_ins'
  ) then
    create policy pwa_staging_images_ins on storage.objects
      for insert to authenticated with check (
        bucket_id = 'pwa-staging-images'
        and (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid())::text
      );
    raise notice '0003: created policy pwa_staging_images_ins';
  else
    raise notice '0003: policy pwa_staging_images_ins already present — left untouched';
  end if;
end
$policies$;

-- Still no UPDATE/DELETE policy for `authenticated`: originals and generated
-- images are immutable from the browser. The backend writes generated output
-- with the server key and is therefore not governed by these policies — it
-- enforces ownership itself before every write.

-- ── Report (read-only) ──────────────────────────────────────────────────────
do $report$
declare
  b record;
  n integer;
begin
  select id, public, file_size_limit, array_length(allowed_mime_types, 1) as mimes
    into b
  from storage.buckets where id = 'pwa-staging-images';
  select count(*) into n
  from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and policyname in ('pwa_staging_images_sel', 'pwa_staging_images_ins');
  raise notice '0003 RESULT: bucket=% public=% limit=% mime_types=% policies=%/2',
    b.id, b.public, b.file_size_limit, b.mimes, n;
  if b.public then
    raise exception '0003: bucket is PUBLIC after apply — refusing to commit.';
  end if;
  if n <> 2 then
    raise exception '0003: expected 2 scoped policies, found % — refusing to commit.', n;
  end if;
end
$report$;

commit;

-- End of 0003. Only storage.buckets / storage.objects policies were considered.
-- pwa_staging.* untouched. No production object touched. Replayable.
