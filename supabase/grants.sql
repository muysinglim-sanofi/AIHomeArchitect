-- ============================================================
-- AIHomeArchitect — Permissions patch
-- Run this in: Supabase Dashboard → SQL Editor → Run
--
-- Why this is needed:
--   signInAnonymously() gives users the `authenticated` role.
--   Without explicit GRANTs, Postgres blocks access before RLS
--   even runs — producing "permission denied for table sessions"
--   (code 42501). The GRANTs unlock object-level access; the RLS
--   policies (already in schema.sql) then enforce row ownership.
-- ============================================================

grant usage on schema public to authenticated;

grant select, insert, update, delete on table public.sessions  to authenticated;
grant select, insert, update, delete on table public.messages  to authenticated;
grant select, insert, update, delete on table public.assets    to authenticated;
