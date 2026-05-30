-- ============================================================
-- Wave 5.17b — Usage tracking + quota enforcement + admin role
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ============================================================
--
-- This migration is ADDITIVE ONLY. It creates two new tables
-- (usage_log, user_roles) and inserts ONE admin grant row for the
-- founder. Zero modifications to existing tables (sessions, messages,
-- assets, auth.users, storage buckets). Safe to apply on live data ;
-- safe to revert via DROP TABLE without affecting any other state.
--
-- Apply after deploying Wave 5.17b backend + frontend ; the order
-- is documented in docs/wave_5_17b_implementation_plan.md §"Deployment
-- order".
--
-- Rollback : DROP TABLE usage_log ; DROP TABLE user_roles ;
--            DELETE matching row from any third-party tables.
-- ============================================================


-- ── usage_log ────────────────────────────────────────────────
-- Tracks every paid /generate call. The status column drives the
-- reserve-then-confirm quota pattern :
--   - INSERT with status='in_progress' BEFORE openai.images.edit
--   - UPDATE to 'success' after the call returns successfully
--   - UPDATE to 'failed' if the call errored OUT (and we believe
--     no OpenAI cost was incurred — partial-content cases stay
--     as 'success' to be conservative on billing)
--
-- The quota check counts rows where status != 'failed', so :
--   - 'in_progress' rows count (closes parallel-request race)
--   - 'success' rows count (the normal path)
--   - 'failed' rows do NOT count (no cost = no quota consumed)

create table if not exists public.usage_log (
  id                 uuid        primary key default gen_random_uuid(),
  user_id            uuid        not null references auth.users(id) on delete cascade,
  session_id         uuid        references public.sessions(id) on delete set null,
  call_type          text        not null check (call_type in ('generate')),
  status             text        not null
                                 check (status in ('in_progress', 'success', 'failed'))
                                 default 'in_progress',
  cost_usd_estimate  numeric(10, 4),
  request_id         text,
  created_at         timestamptz not null default now(),
  completed_at       timestamptz
);

-- Indexes
-- usage_log_user_id_idx     — cheap "rows for this user" lookup
-- usage_log_user_status_idx — partial index optimised for the quota
--                              count query (status != 'failed')
-- usage_log_created_at_idx  — supports future analytics / cleanup jobs

create index if not exists usage_log_user_id_idx
  on public.usage_log(user_id);

create index if not exists usage_log_user_status_idx
  on public.usage_log(user_id, status)
  where status != 'failed';

create index if not exists usage_log_created_at_idx
  on public.usage_log(created_at desc);

-- RLS — users can SELECT their own rows. INSERT/UPDATE/DELETE
-- are service-role only (the FastAPI backend writes ; the Flutter
-- client never does).

alter table public.usage_log enable row level security;

drop policy if exists "usage_log: owner read" on public.usage_log;
create policy "usage_log: owner read"
  on public.usage_log
  for select
  using (auth.uid() = user_id);


-- ── user_roles ───────────────────────────────────────────────
-- Per-user role assignments. Drives admin bypass + future
-- premium / promo / beta_tester grants. The CHECK constraint
-- includes 'premium' now so Wave 5.17c's RevenueCat webhook
-- can INSERT premium rows without a follow-up migration. Wave
-- 5.17b only checks for 'admin'.

create table if not exists public.user_roles (
  user_id     uuid        not null references auth.users(id) on delete cascade,
  role        text        not null check (role in ('admin', 'beta_tester', 'support', 'premium')),
  granted_at  timestamptz not null default now(),
  granted_by  uuid        references auth.users(id),
  expires_at  timestamptz,
  notes       text,
  primary key (user_id, role)
);

create index if not exists user_roles_user_id_idx
  on public.user_roles(user_id);

-- RLS — users can SELECT their own roles (useful for client-side
-- "show admin badge" / "show premium tier" affordances). Writes are
-- service-role only.

alter table public.user_roles enable row level security;

drop policy if exists "user_roles: owner read" on public.user_roles;
create policy "user_roles: owner read"
  on public.user_roles
  for select
  using (auth.uid() = user_id);


-- ── Table-level privilege grants ─────────────────────────────
--
-- Supabase's RLS policies filter rows but they do NOT grant the
-- table-level privilege required for any access at all. New tables
-- in `public` schema default to NO privileges for the `service_role`,
-- `authenticated`, and `anon` roles unless explicitly granted.
--
-- - service_role (backend, FastAPI) — needs SELECT/INSERT/UPDATE on
--   usage_log to enforce the reserve-then-confirm quota pattern, and
--   SELECT on user_roles for the admin-bypass check.
-- - authenticated (client, RLS-filtered) — needs SELECT to read
--   "owner-read" rows scoped by `auth.uid() = user_id`.
--
-- We do NOT grant anything to the `anon` role : unauthenticated
-- callers must not see usage data or role assignments.

grant select, insert, update on public.usage_log  to service_role;
grant select                  on public.user_roles to service_role;

grant select on public.usage_log  to authenticated;
grant select on public.user_roles to authenticated;


-- ── Founder admin grant ──────────────────────────────────────
--
-- IMPORTANT — manual step required.
--
-- Replace <FOUNDER_USER_ID> below with the founder's Supabase user
-- UUID (find via Supabase Dashboard → Authentication → Users →
-- click the founder's row → copy the User UID), then re-run this
-- migration OR run the INSERT statement standalone.
--
-- This grants the founder the 'admin' role, which the Wave 5.17b
-- backend uses to bypass the quota check (so founder testing
-- doesn't burn quota or trigger the paywall).
--
-- Leaving the placeholder in place is safe : the INSERT just fails
-- with a foreign-key violation. It will NOT corrupt other tables.

-- insert into public.user_roles (user_id, role, granted_by, notes)
-- values (
--   '<FOUNDER_USER_ID>',
--   'admin',
--   '<FOUNDER_USER_ID>',
--   'Self-grant for founder testing — Wave 5.17b launch'
-- )
-- on conflict (user_id, role) do nothing;


-- ── Sanity-check queries ─────────────────────────────────────
-- Paste these into the SQL editor after applying the migration to
-- verify the tables exist + have the expected shape :
--
--   select count(*) as usage_log_rows from public.usage_log;
--   select count(*) as user_roles_rows from public.user_roles;
--   select role, count(*) as n from public.user_roles group by role;
--
-- Expected just after apply :
--   usage_log_rows  = 0
--   user_roles_rows = 0  (or 1 if the founder grant was un-commented)


-- ============================================================
-- End Wave 5.17b migration.
-- ============================================================
