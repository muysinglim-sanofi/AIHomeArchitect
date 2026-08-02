-- ============================================================================
-- AYDEN STUDIO PWA — STAGING PERSISTENCE FOUNDATION (Batch 3.0)
-- Isolated schema: pwa_staging.  STAGING ONLY.  NOT AUTO-RUN.
-- ----------------------------------------------------------------------------
-- SAFETY (see supabase/staging/pwa/README.md):
--   * Targets an ISOLATED staging project/schema only; touches NO production
--     object (it creates its own schema). Never apply to the iOS production DB.
--   * The whole migration runs inside ONE transaction, and the guard RAISEs
--     before any DDL — so if the confirmation GUCs are absent the transaction
--     aborts and NOTHING is created, regardless of the caller's error handling
--     (i.e. self-enforcing even without psql -v ON_ERROR_STOP=1).
--   * Two explicit session GUCs are required (DB-name checks are unreliable on
--     Supabase, where staging and production databases are both named
--     `postgres` — the connection target MUST be operator-verified):
--       SET app.ayden_allow_staging_migrations = 'true';
--       SET app.ayden_env = 'staging';
-- ============================================================================

begin;

do $guard$
begin
  if coalesce(current_setting('app.ayden_allow_staging_migrations', true), 'false') <> 'true' then
    raise exception
      'Refusing PWA staging migration: app.ayden_allow_staging_migrations is not true (fail closed).';
  end if;
  if coalesce(current_setting('app.ayden_env', true), '') <> 'staging' then
    raise exception
      'Refusing PWA staging migration: app.ayden_env is not ''staging'' (fail closed). Verify the connection target is the isolated staging project.';
  end if;
end
$guard$;

create schema if not exists pwa_staging;

-- ── installations (staging tenancy only — NOT authentication) ───────────────
create table if not exists pwa_staging.pwa_installations (
  id              uuid primary key default gen_random_uuid(),
  installation_id uuid not null unique,
  environment     text not null default 'staging'
                    check (environment = 'staging'),
  app_version     text,
  created_at      timestamptz not null default now(),
  last_seen_at    timestamptz not null default now()
);

-- ── projects ────────────────────────────────────────────────────────────────
create table if not exists pwa_staging.pwa_projects (
  id                        uuid primary key default gen_random_uuid(),
  installation_id           uuid not null
                              references pwa_staging.pwa_installations(installation_id)
                              on delete cascade,
  title                     text not null check (length(btrim(title)) > 0),
  status                    text not null check (status in ('draft','active')),
  room_id                   text,
  room_label                text not null default '',
  selected_atmosphere_id    text,
  selected_atmosphere_label text not null default '',
  original_image_path       text,
  original_image_source     text not null default 'bundle'
                              check (original_image_source in ('bundle','staging_storage')),
  current_vision_id         uuid,
  cover_vision_id           uuid,
  updated_label             text,
  client_created_order      bigint,
  client_updated_order      bigint,
  revision                  integer not null default 1,
  schema_version            integer not null default 1,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  deleted_at                timestamptz,
  -- Enables the composite tenancy FKs below so a child's installation_id can
  -- never diverge from its project's owner.
  unique (id, installation_id)
);
create index if not exists pwa_projects_installation_idx
  on pwa_staging.pwa_projects (installation_id, updated_at desc)
  where deleted_at is null;

-- ── visions (append-only lineage) ───────────────────────────────────────────
create table if not exists pwa_staging.pwa_visions (
  id                uuid primary key default gen_random_uuid(),
  project_id        uuid not null,
  installation_id   uuid not null,
  vision_number     integer not null check (vision_number > 0),
  parent_vision_id  uuid references pwa_staging.pwa_visions(id) on delete set null,
  action_type       text not null
                      check (action_type in ('initial','refine','switch_atmosphere')),
  action_summary    text,
  prompt_text       text,
  atmosphere_id     text not null,
  atmosphere_label  text not null default '',
  image_path        text not null,
  image_source      text not null default 'bundle'
                      check (image_source in ('bundle','staging_storage')),
  source_message_id uuid,
  client_order      bigint,
  schema_version    integer not null default 1,
  created_at        timestamptz not null default now(),
  unique (project_id, vision_number),
  -- Composite FK ties installation_id to the owning project's installation_id
  -- (closes a cross-installation write gap before RLS is wired).
  foreign key (project_id, installation_id)
    references pwa_staging.pwa_projects (id, installation_id) on delete cascade
);
create index if not exists pwa_visions_project_idx
  on pwa_staging.pwa_visions (project_id, vision_number);

-- ── messages (append-only chronology) ───────────────────────────────────────
create table if not exists pwa_staging.pwa_messages (
  id                   uuid primary key default gen_random_uuid(),
  project_id           uuid not null,
  installation_id      uuid not null,
  role                 text not null check (role in ('user','assistant','system')),
  message_type         text not null,
  text_content         text,
  intent               text,
  referenced_vision_id uuid references pwa_staging.pwa_visions(id) on delete set null,
  confirmation_state   text check (confirmation_state in
                          ('pending','cancelled','confirmed','completed')),
  client_order         bigint not null,
  metadata_json        jsonb,
  schema_version       integer not null default 1,
  created_at           timestamptz not null default now(),
  foreign key (project_id, installation_id)
    references pwa_staging.pwa_projects (id, installation_id) on delete cascade
);
create index if not exists pwa_messages_project_idx
  on pwa_staging.pwa_messages (project_id, client_order, created_at);

-- ── Row Level Security — DENY BY DEFAULT ────────────────────────────────────
-- Enabling RLS with no permissive policy blocks all client access. Choose ONE
-- access model at activation and add scoped policies (see README):
--   Option A (preferred): a staging API facade holds the service role
--     server-side; the browser never gets a privileged key. RLS stays deny-all
--     for the anon role; the API validates a signed installation token.
--   Option B: staging-only anonymous Supabase auth; policies below key off a
--     verified installation claim. Templates are provided COMMENTED — do not
--     enable a permissive policy without the intended tenancy check.
alter table pwa_staging.pwa_installations enable row level security;
alter table pwa_staging.pwa_projects      enable row level security;
alter table pwa_staging.pwa_visions       enable row level security;
alter table pwa_staging.pwa_messages      enable row level security;

-- Example scoped SELECT policy (Option B) — enable ONLY after wiring auth:
-- create policy pwa_projects_tenant_read on pwa_staging.pwa_projects
--   for select using (
--     installation_id = (current_setting('request.jwt.claims', true)::jsonb ->> 'installation_id')::uuid
--   );
-- Mirror scoped policies for insert/update and for visions/messages before use.
-- With the composite FK above, an insert that stamps a foreign installation_id
-- is rejected even if a naive insert policy only checks the JWT claim.

commit;

-- End of foundation migration. No production object was touched.
