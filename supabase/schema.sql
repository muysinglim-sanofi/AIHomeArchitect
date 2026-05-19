-- ============================================================
-- AIHomeArchitect — Supabase MVP Schema
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ============================================================

-- ── Sessions ─────────────────────────────────────────────────
-- One session = one design project.
-- user_id comes from Supabase anonymous auth (auth.users.id).

create table if not exists sessions (
  id            uuid        primary key default gen_random_uuid(),
  user_id       uuid        not null references auth.users(id) on delete cascade,
  title         text        not null default 'New Design Session',
  room_type     text,
  atmosphere    text,
  before_image_url  text,   -- original room photo (Supabase storage URL)
  latest_preview    text,   -- most recent generated result URL
  status        text        not null default 'in_progress'
                            check (status in ('in_progress', 'completed', 'failed')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ── Messages ─────────────────────────────────────────────────

create table if not exists messages (
  id              uuid        primary key default gen_random_uuid(),
  session_id      uuid        not null references sessions(id) on delete cascade,
  role            text        not null check (role in ('user', 'ai')),
  content         text        not null,
  message_type    text        not null default 'text'
                              check (message_type in ('text', 'image_result', 'system')),
  -- populated only for image_result messages
  before_image_url  text,
  after_image_url   text,
  style_label       text,
  created_at      timestamptz not null default now()
);

-- ── Assets ───────────────────────────────────────────────────

create table if not exists assets (
  id            uuid        primary key default gen_random_uuid(),
  session_id    uuid        not null references sessions(id) on delete cascade,
  type          text        not null check (type in ('upload', 'generated')),
  url           text        not null,
  thumbnail_url text,
  created_at    timestamptz not null default now()
);

-- ── Auto-update updated_at on sessions ───────────────────────

create or replace function _set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists sessions_updated_at on sessions;
create trigger sessions_updated_at
  before update on sessions
  for each row execute function _set_updated_at();

-- ── Indexes ──────────────────────────────────────────────────

create index if not exists idx_sessions_user_id
  on sessions (user_id, updated_at desc);

create index if not exists idx_messages_session_id
  on messages (session_id, created_at asc);

create index if not exists idx_assets_session_id
  on assets (session_id, created_at desc);

-- ── Role-level grants ────────────────────────────────────────
-- Anonymous users authenticated via signInAnonymously() run as
-- the `authenticated` role, NOT `anon`. Both layers must pass:
--   1. GRANT  — object-level: can the role touch this table at all?
--   2. RLS    — row-level:    which specific rows can they see?
-- Without these GRANTs, RLS never even runs → 42501 permission denied.

grant usage on schema public to authenticated;

grant select, insert, update, delete on table public.sessions  to authenticated;
grant select, insert, update, delete on table public.messages  to authenticated;
grant select, insert, update, delete on table public.assets    to authenticated;

-- ── Row Level Security ────────────────────────────────────────
-- All access goes through Supabase anonymous auth.
-- Users can only see and modify their own data.

alter table sessions enable row level security;
alter table messages enable row level security;
alter table assets   enable row level security;

-- Sessions: full access to own rows
create policy "sessions: owner access"
  on sessions for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Messages: access via session ownership
create policy "messages: owner access"
  on messages for all
  using (
    session_id in (
      select id from sessions where user_id = auth.uid()
    )
  )
  with check (
    session_id in (
      select id from sessions where user_id = auth.uid()
    )
  );

-- Assets: access via session ownership
create policy "assets: owner access"
  on assets for all
  using (
    session_id in (
      select id from sessions where user_id = auth.uid()
    )
  )
  with check (
    session_id in (
      select id from sessions where user_id = auth.uid()
    )
  );

-- ============================================================
-- Storage buckets — create these manually in the dashboard:
--
--   uploads    private  path: {user_id}/{session_id}/{filename}
--   generated  public   path: {session_id}/{timestamp}.jpg
--   thumbnails public   path: {session_id}/{timestamp}_thumb.jpg
--
-- Storage RLS policies (add via dashboard or paste below):
-- ============================================================

-- Uploads bucket: users can only access their own folder
-- (Run after creating the bucket in Storage → uploads → Policies)
--
-- insert policy "uploads: owner insert"
--   on storage.objects for insert
--   with check (
--     bucket_id = 'uploads' and
--     (storage.foldername(name))[1] = auth.uid()::text
--   );
--
-- select policy "uploads: owner select"
--   on storage.objects for select
--   using (
--     bucket_id = 'uploads' and
--     (storage.foldername(name))[1] = auth.uid()::text
--   );
