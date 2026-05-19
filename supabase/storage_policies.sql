-- ============================================================
-- AIHomeArchitect — Storage RLS for the `uploads` bucket
--
-- Paste the entire file into:
--   Supabase Dashboard → SQL Editor → Run
--
-- Prerequisites:
--   1. Bucket named exactly "uploads" must exist (Storage → New bucket).
--   2. Bucket must be set to PRIVATE (do NOT toggle "Public bucket").
--   3. Run this AFTER the bucket exists — policies reference the bucket by name.
--
-- Path convention used by uploadSourceImage():
--   {user_id}/{session_id}/{filename}
--   e.g. f9b13abc.../05b479d1.../source_1778526771365.jpg
--
-- split_part(name, '/', 1) extracts the first path segment = user_id.
-- auth.uid() returns the anonymous user's UUID from the JWT.
-- Both are cast to text for comparison.
-- ============================================================

-- ── Clean up any previous policy attempts ────────────────────────────────────
-- Idempotent: IF EXISTS means this is safe to re-run.

drop policy if exists "uploads: owner insert" on storage.objects;
drop policy if exists "uploads: owner select" on storage.objects;
drop policy if exists "uploads: owner update" on storage.objects;
drop policy if exists "uploads: owner delete" on storage.objects;
drop policy if exists "uploads_insert"        on storage.objects;
drop policy if exists "uploads_select"        on storage.objects;
drop policy if exists "uploads_update"        on storage.objects;
drop policy if exists "uploads_delete"        on storage.objects;

-- ── INSERT — allow upload into own folder ─────────────────────────────────────
-- WITH CHECK runs against the row being inserted.
-- Rejects any path whose first segment is not the caller's user_id.

create policy "uploads_insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'uploads'
    and split_part(name, '/', 1) = auth.uid()::text
  );

-- ── SELECT — allow reading own uploads (required for createSignedUrl) ─────────

create policy "uploads_select"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'uploads'
    and split_part(name, '/', 1) = auth.uid()::text
  );

-- ── UPDATE — allow upsert (uploadBinary uses upsert: true) ───────────────────

create policy "uploads_update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'uploads'
    and split_part(name, '/', 1) = auth.uid()::text
  );

-- ── DELETE — allow removing own uploads ──────────────────────────────────────

create policy "uploads_delete"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'uploads'
    and split_part(name, '/', 1) = auth.uid()::text
  );

-- ============================================================
-- Verify: after running, check policies exist:
--
--   select policyname, cmd, roles, qual, with_check
--   from pg_policies
--   where tablename = 'objects'
--     and schemaname = 'storage';
--
-- You should see 4 rows for uploads_insert / select / update / delete.
-- ============================================================
