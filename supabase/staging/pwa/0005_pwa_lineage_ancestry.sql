-- ============================================================================
-- AYDEN STUDIO PWA — LINEAGE ANCESTRY + RESOLVED ROOM
-- 0005 — additive, IDEMPOTENT.  Schema: pwa_staging.  STAGING ONLY.
-- ----------------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--
--   Two facts mobile keeps PER VISION had nowhere to live in `pwa_visions`, so
--   the adapter had to guess them from the project as a whole. Both guesses are
--   wrong in exactly the same situation — a branch taken from a vision made
--   BEFORE the user customised anything.
--
--   1. `lineage_customized`
--      Mobile stores this on every version record and derives a new one from
--      the SOURCE record only:
--          /generate : new = source.lineage_customized OR this_edit_is_spatial
--                      (main.py, "β (2026-06-22): cumulative lineage_customized")
--          /refine   : new = true
--                      (refine/orchestrator_adapter.py:90)
--      The read at generation time is the SOURCE record's flag — never a scan
--      of the whole session (main.py `_src_record` / `_explicit_customized`).
--
--      The adapter had no column, so it answered the question by asking "does
--      this PROJECT contain any refine anywhere?". On
--          V1 → V2 refine → V3 refine,  then a NEW branch from V1
--      that returns true, and the new branch is composed REBOOT_CUSTOMIZED with
--      the previous vision as its source. Mobile composes it REBOOT_FRESH from
--      V1, because V1's own flag is false. One column removes the guess.
--
--   2. `room_label`
--      "Ayden Decide" is resolved to a real room by ONE gpt-4o look at the
--      photo, and that answer is what keys the per-room DNA. Mobile returns it
--      (`"room_type": room_type`) and the client persists it, so every later
--      turn — advisor, refine, switch — sees the room that was actually used.
--      With nowhere to store it the adapter re-sent "Your space" forever and
--      the advisor judged a refine without knowing the room.
--
-- WHAT IT CREATES
--   * pwa_visions.lineage_customized  boolean  (null = pre-0005 row)
--   * pwa_visions.room_label          text     (the room actually used)
--   * pwa_projects.resolved_room_type text     (canonical id, e.g. living_room)
--
--   NULL is meaningful on `lineage_customized`: it means "written before this
--   migration", and the adapter falls back to an ANCESTRY walk for those rows
--   rather than assuming false. Never a silent loss of the user's work.
--
-- WHAT IT NEVER DOES
--   * drop or rewrite an existing column
--   * touch any production object
--   * widen an existing policy (column-level grants follow the table's)
--   * contain a secret
--
-- SAFETY
--   ONE transaction; the guard RAISEs before any DDL, so absent GUCs abort the
--   whole thing and NOTHING is written. Replayable: `add column if not exists`.
--
--     set app.ayden_allow_staging_migrations = 'true';
--     set app.ayden_env = 'staging';
--
--   The operator MUST verify the connection target is project ref
--   eedcahzekpgxvvfxufbk before running.
-- ============================================================================

begin;

-- ── Guard (fail closed) ─────────────────────────────────────────────────────
do $guard$
begin
  if coalesce(current_setting('app.ayden_allow_staging_migrations', true), 'false') <> 'true' then
    raise exception
      'Refusing PWA staging migration 0005: app.ayden_allow_staging_migrations is not true (fail closed).';
  end if;
  if coalesce(current_setting('app.ayden_env', true), '') <> 'staging' then
    raise exception
      'Refusing PWA staging migration 0005: app.ayden_env is not ''staging'' (fail closed). Verify the connection target is the isolated staging project (ref eedcahzekpgxvvfxufbk).';
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'pwa_staging') then
    raise exception
      'Refusing PWA staging migration 0005: schema pwa_staging does not exist. Apply 0002 first.';
  end if;
end
$guard$;

-- ── The two per-vision facts ────────────────────────────────────────────────
alter table pwa_staging.pwa_visions
  add column if not exists lineage_customized boolean;

comment on column pwa_staging.pwa_visions.lineage_customized is
  'Cumulative along the BRANCH, exactly as mobile computes it: a new vision is '
  'customized when its SOURCE vision was, or when this edit is itself a spatial '
  'change. NULL = written before migration 0005 -> the adapter walks the '
  'ancestry instead of assuming false.';

alter table pwa_staging.pwa_visions
  add column if not exists room_label text;

comment on column pwa_staging.pwa_visions.room_label is
  'The room the engine ACTUALLY used for this vision (after Ayden Decide '
  'resolved "Your space"). What keyed the per-room DNA, not what the browser '
  'asked for.';

-- ── The project-level resolved room ─────────────────────────────────────────
-- `room_label` already exists on pwa_projects and carries the DISPLAY label the
-- client shows. The canonical id is a separate fact (living_room, pool_area)
-- and is what the engine keys on, so it gets its own column rather than
-- overloading a display string.
alter table pwa_staging.pwa_projects
  add column if not exists resolved_room_type text;

comment on column pwa_staging.pwa_projects.resolved_room_type is
  'Canonical room id resolved by Ayden Decide (living_room, terrace, ...). '
  'Written ONLY when the person delegated the room; an explicit choice is never '
  'overridden. Mirrors mobile, where the resolved room is returned by /generate '
  'and persisted into the session.';

-- ── Report (read-only) ──────────────────────────────────────────────────────
do $report$
declare
  n_cols integer;
begin
  select count(*) into n_cols
    from information_schema.columns
   where table_schema = 'pwa_staging'
     and (   (table_name = 'pwa_visions'  and column_name in ('lineage_customized', 'room_label'))
          or (table_name = 'pwa_projects' and column_name = 'resolved_room_type'));
  raise notice '0005 RESULT: columns=%/3', n_cols;
  if n_cols <> 3 then
    raise exception '0005: expected 3 columns, found % — refusing to commit.', n_cols;
  end if;
end
$report$;

commit;

-- End of 0005. Additive and replayable. No column dropped, no policy widened,
-- no production object considered.
