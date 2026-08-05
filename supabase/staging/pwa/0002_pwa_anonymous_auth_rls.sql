-- ============================================================================
-- AYDEN STUDIO PWA — STAGING SCHEMA (Batch 3.1)
-- 0002 — anonymous-auth ownership + RLS (FORCE) + helper RPCs + private Storage.
-- Schema: pwa_staging.  STAGING ONLY.  NOT AUTO-RUN.  Manual SQL Editor only.
-- ----------------------------------------------------------------------------
-- WHY SELF-CONTAINED (supersedes 0001): 0001 (Batch 3.0) modelled tenancy on a
-- client `installation_id`. Batch 3.1 makes the anonymous `auth.uid()` the
-- canonical owner. No migration has ever run on the remote project, so this
-- file CREATES the final auth-model schema in one coherent, auditable
-- transaction instead of a fragile create-then-ALTER chain (batch §10 permits a
-- squash when nothing is deployed). 0001 is retained in the repo for history
-- and is NOT applied.
--
-- SAFETY:
--   * ONE transaction — the guard RAISEs before any DDL, so absent GUCs abort
--     the whole thing and NOTHING is created (self-enforcing).
--   * Two session GUCs are required (DB-name checks are unreliable on Supabase,
--     where staging and prod are both `postgres` — the connection target MUST be
--     operator-verified to be project ref eedcahzekpgxvvfxufbk):
--        set app.ayden_allow_staging_migrations = 'true';
--        set app.ayden_env = 'staging';
--   * Fails closed if pwa_staging already exists (never clobbers a prior apply).
--   * Touches NO production object. Only creates pwa_staging.* and one private
--     Storage bucket `pwa-staging-images` + its scoped policies.
-- ============================================================================

begin;

-- ── Guard (fail closed) ─────────────────────────────────────────────────────
do $guard$
begin
  if coalesce(current_setting('app.ayden_allow_staging_migrations', true), 'false') <> 'true' then
    raise exception
      'Refusing PWA staging migration: app.ayden_allow_staging_migrations is not true (fail closed).';
  end if;
  if coalesce(current_setting('app.ayden_env', true), '') <> 'staging' then
    raise exception
      'Refusing PWA staging migration: app.ayden_env is not ''staging'' (fail closed). Verify the connection target is the isolated staging project (ref eedcahzekpgxvvfxufbk).';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'pwa_staging') then
    raise exception
      'Refusing: schema pwa_staging already exists. Drop it explicitly before re-applying (fail closed — never clobber a prior apply).';
  end if;
end
$guard$;

create schema pwa_staging;

-- ── installations (metadata only — NOT authorization) ───────────────────────
create table pwa_staging.pwa_installations (
  id              uuid primary key default gen_random_uuid(),
  owner_user_id   uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null,
  app_version     text,
  environment     text not null default 'staging' check (environment = 'staging'),
  schema_version  integer not null default 1 check (schema_version = 1),
  created_at      timestamptz not null default now(),
  last_seen_at    timestamptz not null default now(),
  unique (owner_user_id),
  unique (installation_id)
);

-- ── projects ────────────────────────────────────────────────────────────────
create table pwa_staging.pwa_projects (
  id                        uuid primary key default gen_random_uuid(),
  owner_user_id             uuid not null references auth.users(id) on delete cascade,
  installation_id           uuid,
  title                     text not null
                              check (title = btrim(title) and title <> ''),
  status                    text not null check (status in ('draft','active')),
  room_id                   text not null,
  room_label                text not null,
  selected_atmosphere_id    text not null,
  selected_atmosphere_label text not null,
  original_image_source     text
                              check (original_image_source in ('bundle','staging_storage')),
  original_image_path       text,
  current_vision_id         uuid,
  cover_vision_id           uuid,
  revision                  integer not null default 1 check (revision >= 1),
  client_created_order      bigint,
  client_updated_order      bigint,
  schema_version            integer not null default 1 check (schema_version = 1),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  deleted_at                timestamptz,
  -- Composite tenancy anchor: lets child FKs bind (id, owner) so a child can
  -- never diverge from its project's owner (defense beyond RLS).
  unique (id, owner_user_id)
);
create index pwa_projects_owner_deleted_idx
  on pwa_staging.pwa_projects (owner_user_id, deleted_at);
create index pwa_projects_owner_updated_idx
  on pwa_staging.pwa_projects (owner_user_id, updated_at desc)
  where deleted_at is null;
create index pwa_projects_owner_status_idx
  on pwa_staging.pwa_projects (owner_user_id, status);

-- ── visions (append-only lineage) ───────────────────────────────────────────
create table pwa_staging.pwa_visions (
  id                uuid primary key default gen_random_uuid(),
  project_id        uuid not null,
  owner_user_id     uuid not null references auth.users(id) on delete cascade,
  vision_number     integer not null check (vision_number > 0),
  parent_vision_id  uuid,
  action_type       text not null
                      check (action_type in ('initial','refine','switch_atmosphere')),
  action_summary    text,
  prompt_text       text,
  atmosphere_id     text not null,
  atmosphere_label  text not null,
  image_source      text not null check (image_source in ('bundle','staging_storage')),
  image_path        text not null,
  source_message_id uuid,
  client_order      bigint,
  idempotency_key   uuid not null,
  schema_version    integer not null default 1 check (schema_version = 1),
  created_at        timestamptz not null default now(),
  unique (project_id, vision_number),
  unique (owner_user_id, idempotency_key),
  -- FK targets for owner-aware child references (id is already unique; these
  -- supersets let composite (…, project_id, owner_user_id) FKs bind).
  unique (id, project_id, owner_user_id)
);
create index pwa_visions_project_idx
  on pwa_staging.pwa_visions (owner_user_id, project_id, vision_number);

-- ── messages (append-only chronology; confirmation_state may transition) ─────
create table pwa_staging.pwa_messages (
  id                   uuid primary key default gen_random_uuid(),
  project_id           uuid not null,
  owner_user_id        uuid not null references auth.users(id) on delete cascade,
  role                 text not null check (role in ('user','assistant','system')),
  message_type         text not null,
  text_content         text,
  intent               text,
  referenced_vision_id uuid,
  confirmation_state   text check (confirmation_state in
                          ('pending','cancelled','confirmed','completed')),
  client_order         bigint not null,
  idempotency_key      uuid not null,
  metadata_json        jsonb,
  schema_version       integer not null default 1 check (schema_version = 1),
  created_at           timestamptz not null default now(),
  unique (owner_user_id, idempotency_key),
  unique (id, project_id, owner_user_id)
);
create index pwa_messages_project_idx
  on pwa_staging.pwa_messages (owner_user_id, project_id, client_order, created_at);

-- ── Cross-table ownership-aware FKs (added after all tables exist) ──────────
-- Children bind to (project_id, owner_user_id) → a foreign owner is impossible
-- even beyond RLS. parent/source/referenced binds also pin the same owner.
alter table pwa_staging.pwa_visions
  add constraint pwa_visions_project_owner_fk
    foreign key (project_id, owner_user_id)
    references pwa_staging.pwa_projects (id, owner_user_id) on delete cascade,
  -- Parent must be in the SAME project + SAME owner. Deferrable so a single
  -- multi-row lineage insert (parent + children) validates at commit.
  add constraint pwa_visions_parent_owner_fk
    foreign key (parent_vision_id, project_id, owner_user_id)
    references pwa_staging.pwa_visions (id, project_id, owner_user_id)
    on delete set null
    deferrable initially deferred;

alter table pwa_staging.pwa_messages
  add constraint pwa_messages_project_owner_fk
    foreign key (project_id, owner_user_id)
    references pwa_staging.pwa_projects (id, owner_user_id) on delete cascade,
  -- Referenced vision must be in the SAME project + SAME owner.
  add constraint pwa_messages_refvision_owner_fk
    foreign key (referenced_vision_id, project_id, owner_user_id)
    references pwa_staging.pwa_visions (id, project_id, owner_user_id)
    on delete set null;

-- vision.source_message_id → the SAME project + owner message. DEFERRABLE so a
-- deep copy can set it in the vision INSERT before the copied messages exist
-- (validated at commit) — no post-hoc UPDATE on the append-only table.
alter table pwa_staging.pwa_visions
  add constraint pwa_visions_srcmsg_owner_fk
    foreign key (source_message_id, project_id, owner_user_id)
    references pwa_staging.pwa_messages (id, project_id, owner_user_id)
    on delete set null
    deferrable initially deferred;

-- project.current/cover vision → the SAME project + owner vision.
alter table pwa_staging.pwa_projects
  add constraint pwa_projects_current_vision_fk
    foreign key (current_vision_id, id, owner_user_id)
    references pwa_staging.pwa_visions (id, project_id, owner_user_id)
    on delete set null
    deferrable initially deferred,
  add constraint pwa_projects_cover_vision_fk
    foreign key (cover_vision_id, id, owner_user_id)
    references pwa_staging.pwa_visions (id, project_id, owner_user_id)
    on delete set null
    deferrable initially deferred;

-- ── Ownership hardening: BEFORE INSERT stamps owner_user_id = auth.uid() ─────
-- The client is NEVER trusted to choose an owner; the trigger overwrites it and
-- RLS WITH CHECK still enforces equality. search_path='' (no injection surface).
create function pwa_staging.set_owner_user_id() returns trigger
  language plpgsql security invoker set search_path = '' as $fn$
begin
  new.owner_user_id := auth.uid();
  if new.owner_user_id is null then
    raise exception 'PWA staging: no authenticated user (auth.uid() is null).';
  end if;
  return new;
end
$fn$;

create function pwa_staging.touch_updated_at() returns trigger
  language plpgsql security invoker set search_path = '' as $fn$
begin
  new.updated_at := now();
  return new;
end
$fn$;

-- messages are append-only EXCEPT confirmation_state / metadata_json (§17).
create function pwa_staging.guard_message_immutable() returns trigger
  language plpgsql security invoker set search_path = '' as $fn$
begin
  if new.id <> old.id
     or new.project_id <> old.project_id
     or new.owner_user_id <> old.owner_user_id
     or new.role <> old.role
     or new.message_type <> old.message_type
     or new.text_content is distinct from old.text_content
     or new.intent is distinct from old.intent
     or new.referenced_vision_id is distinct from old.referenced_vision_id
     or new.client_order <> old.client_order
     or new.idempotency_key <> old.idempotency_key
     or new.created_at <> old.created_at
     or new.schema_version <> old.schema_version then
    raise exception 'PWA staging: only confirmation_state/metadata_json are mutable on a message.';
  end if;
  return new;
end
$fn$;

create trigger pwa_installations_set_owner before insert
  on pwa_staging.pwa_installations for each row
  execute function pwa_staging.set_owner_user_id();
create trigger pwa_projects_set_owner before insert
  on pwa_staging.pwa_projects for each row
  execute function pwa_staging.set_owner_user_id();
create trigger pwa_visions_set_owner before insert
  on pwa_staging.pwa_visions for each row
  execute function pwa_staging.set_owner_user_id();
create trigger pwa_messages_set_owner before insert
  on pwa_staging.pwa_messages for each row
  execute function pwa_staging.set_owner_user_id();

create trigger pwa_projects_touch before update
  on pwa_staging.pwa_projects for each row
  execute function pwa_staging.touch_updated_at();
create trigger pwa_messages_immutable before update
  on pwa_staging.pwa_messages for each row
  execute function pwa_staging.guard_message_immutable();

-- ── Row Level Security — ENABLE + FORCE, scoped to auth.uid() ────────────────
alter table pwa_staging.pwa_installations enable row level security;
alter table pwa_staging.pwa_installations force row level security;
alter table pwa_staging.pwa_projects      enable row level security;
alter table pwa_staging.pwa_projects      force row level security;
alter table pwa_staging.pwa_visions       enable row level security;
alter table pwa_staging.pwa_visions       force row level security;
alter table pwa_staging.pwa_messages      enable row level security;
alter table pwa_staging.pwa_messages      force row level security;

-- installations
create policy pwa_installations_sel on pwa_staging.pwa_installations
  for select to authenticated using (owner_user_id = (select auth.uid()));
create policy pwa_installations_ins on pwa_staging.pwa_installations
  for insert to authenticated with check (owner_user_id = (select auth.uid()));
create policy pwa_installations_upd on pwa_staging.pwa_installations
  for update to authenticated
  using (owner_user_id = (select auth.uid()))
  with check (owner_user_id = (select auth.uid()));

-- projects (soft delete is an UPDATE)
create policy pwa_projects_sel on pwa_staging.pwa_projects
  for select to authenticated using (owner_user_id = (select auth.uid()));
create policy pwa_projects_ins on pwa_staging.pwa_projects
  for insert to authenticated with check (owner_user_id = (select auth.uid()));
create policy pwa_projects_upd on pwa_staging.pwa_projects
  for update to authenticated
  using (owner_user_id = (select auth.uid()))
  with check (owner_user_id = (select auth.uid()));

-- visions (append-only: SELECT + INSERT only; no update/delete policy)
create policy pwa_visions_sel on pwa_staging.pwa_visions
  for select to authenticated using (owner_user_id = (select auth.uid()));
create policy pwa_visions_ins on pwa_staging.pwa_visions
  for insert to authenticated with check (owner_user_id = (select auth.uid()));

-- messages (SELECT + INSERT + narrow UPDATE for confirmation transitions)
create policy pwa_messages_sel on pwa_staging.pwa_messages
  for select to authenticated using (owner_user_id = (select auth.uid()));
create policy pwa_messages_ins on pwa_staging.pwa_messages
  for insert to authenticated with check (owner_user_id = (select auth.uid()));
create policy pwa_messages_upd on pwa_staging.pwa_messages
  for update to authenticated
  using (owner_user_id = (select auth.uid()))
  with check (owner_user_id = (select auth.uid()));

-- ── Helper RPCs ─────────────────────────────────────────────────────────────
-- upsert_installation: metadata only; owner derived from auth.uid().
create function pwa_staging.upsert_installation(p_installation_id uuid, p_app_version text default null)
  returns pwa_staging.pwa_installations
  language plpgsql security invoker set search_path = '' as $fn$
declare
  v_owner uuid := auth.uid();
  v_row   pwa_staging.pwa_installations;
begin
  if v_owner is null then
    raise exception 'PWA staging: not authenticated.';
  end if;
  insert into pwa_staging.pwa_installations (owner_user_id, installation_id, app_version)
  values (v_owner, p_installation_id, p_app_version)
  on conflict (owner_user_id) do update
    set installation_id = excluded.installation_id,
        app_version     = excluded.app_version,
        last_seen_at    = now()
  returning * into v_row;
  return v_row;
end
$fn$;

-- soft_delete_project: owner-scoped UPDATE (RLS also enforces).
create function pwa_staging.soft_delete_project(p_project_id uuid)
  returns void
  language plpgsql security invoker set search_path = '' as $fn$
declare
  v_owner uuid := auth.uid();
begin
  if v_owner is null then
    raise exception 'PWA staging: not authenticated.';
  end if;
  update pwa_staging.pwa_projects
     set deleted_at = now()
   where id = p_project_id and owner_user_id = v_owner and deleted_at is null;
end
$fn$;

-- deep_duplicate_project: one transactional deep copy. SECURITY DEFINER runs it
-- in a trusted context so it can create the temp id-maps and insert across the
-- cyclic project/vision/message FKs. It performs NO update on the append-only
-- tables — every remapped reference (parent, source_message, referenced_vision,
-- current/cover) is set in the INSERTs, with the cyclic FKs DEFERRED to commit.
-- Defense-in-depth: EVERY statement carries an explicit owner_user_id = v_owner
-- predicate (auth.uid()), so no foreign owner's row is ever read or written even
-- though DEFINER bypasses RLS. search_path='' — no injection surface.
create function pwa_staging.deep_duplicate_project(p_project_id uuid, p_new_title text)
  returns uuid
  language plpgsql security definer set search_path = '' as $fn$
declare
  v_owner       uuid := auth.uid();
  v_new_project uuid := gen_random_uuid();
  v_title       text := btrim(coalesce(p_new_title, ''));
begin
  if v_owner is null then
    raise exception 'PWA staging: not authenticated.';
  end if;
  if v_title = '' then
    raise exception 'PWA staging: new title is required.';
  end if;
  if not exists (
    select 1 from pwa_staging.pwa_projects
    where id = p_project_id and owner_user_id = v_owner and deleted_at is null
  ) then
    raise exception 'PWA staging: source project not found for this owner.';
  end if;

  create temp table _vmap (old_id uuid primary key, new_id uuid not null) on commit drop;
  create temp table _mmap (old_id uuid primary key, new_id uuid not null) on commit drop;
  insert into _vmap select id, gen_random_uuid()
    from pwa_staging.pwa_visions where project_id = p_project_id and owner_user_id = v_owner;
  insert into _mmap select id, gen_random_uuid()
    from pwa_staging.pwa_messages where project_id = p_project_id and owner_user_id = v_owner;

  -- 1) new project — current/cover remapped up front (cyclic FKs to visions are
  --    DEFERRABLE INITIALLY DEFERRED → validated at COMMIT once visions exist).
  insert into pwa_staging.pwa_projects
    (id, owner_user_id, installation_id, title, status, room_id, room_label,
     selected_atmosphere_id, selected_atmosphere_label, original_image_source,
     original_image_path, current_vision_id, cover_vision_id, revision,
     client_created_order, client_updated_order, schema_version)
  select v_new_project, v_owner, op.installation_id, v_title, op.status, op.room_id, op.room_label,
         op.selected_atmosphere_id, op.selected_atmosphere_label, op.original_image_source,
         op.original_image_path, cvm.new_id, ovm.new_id, 1,
         op.client_created_order, op.client_updated_order, op.schema_version
  from pwa_staging.pwa_projects op
  left join _vmap cvm on cvm.old_id = op.current_vision_id
  left join _vmap ovm on ovm.old_id = op.cover_vision_id
  where op.id = p_project_id and op.owner_user_id = v_owner;

  -- 2) visions — parent + source_message remapped inline (both FKs deferred);
  --    ordered by vision_number so the deferred parent self-FK is coherent.
  insert into pwa_staging.pwa_visions
    (id, project_id, owner_user_id, vision_number, parent_vision_id, action_type,
     action_summary, prompt_text, atmosphere_id, atmosphere_label, image_source,
     image_path, source_message_id, client_order, idempotency_key, schema_version)
  select vm.new_id, v_new_project, v_owner, v.vision_number, pvm.new_id, v.action_type,
         v.action_summary, v.prompt_text, v.atmosphere_id, v.atmosphere_label, v.image_source,
         v.image_path, smm.new_id, v.client_order, gen_random_uuid(), v.schema_version
  from pwa_staging.pwa_visions v
  join _vmap vm on vm.old_id = v.id
  left join _vmap pvm on pvm.old_id = v.parent_vision_id
  left join _mmap smm on smm.old_id = v.source_message_id
  where v.project_id = p_project_id and v.owner_user_id = v_owner
  order by v.vision_number;

  -- 3) messages — referenced_vision remapped (visions now exist); new idempotency.
  insert into pwa_staging.pwa_messages
    (id, project_id, owner_user_id, role, message_type, text_content, intent,
     referenced_vision_id, confirmation_state, client_order, idempotency_key,
     metadata_json, schema_version)
  select mm.new_id, v_new_project, v_owner, m.role, m.message_type, m.text_content, m.intent,
         rvm.new_id, m.confirmation_state, m.client_order, gen_random_uuid(),
         m.metadata_json, m.schema_version
  from pwa_staging.pwa_messages m
  join _mmap mm on mm.old_id = m.id
  left join _vmap rvm on rvm.old_id = m.referenced_vision_id
  where m.project_id = p_project_id and m.owner_user_id = v_owner;

  return v_new_project;
end
$fn$;

-- ── Grants: authenticated only; anon/public get nothing ─────────────────────
grant usage on schema pwa_staging to authenticated;
grant select, insert, update on pwa_staging.pwa_installations to authenticated;
grant select, insert, update on pwa_staging.pwa_projects      to authenticated;
grant select, insert          on pwa_staging.pwa_visions       to authenticated;
grant select, insert, update on pwa_staging.pwa_messages      to authenticated;

revoke all on schema pwa_staging from anon, public;
revoke all on all tables in schema pwa_staging from anon, public;

revoke all on function pwa_staging.upsert_installation(uuid, text)   from public;
revoke all on function pwa_staging.soft_delete_project(uuid)         from public;
revoke all on function pwa_staging.deep_duplicate_project(uuid, text) from public;
grant execute on function pwa_staging.upsert_installation(uuid, text)   to authenticated;
grant execute on function pwa_staging.soft_delete_project(uuid)         to authenticated;
grant execute on function pwa_staging.deep_duplicate_project(uuid, text) to authenticated;

-- ── Private Storage bucket + scoped policies ────────────────────────────────
-- Path convention: users/{authUid}/projects/{projectId}/original/{objectId}.{ext}
-- RLS keys off the {authUid} segment (folder index 2, under the 'users' root).
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pwa-staging-images', 'pwa-staging-images', false, 10485760,
        array['image/jpeg','image/png','image/webp']);

create policy pwa_staging_images_sel on storage.objects
  for select to authenticated using (
    bucket_id = 'pwa-staging-images'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );
create policy pwa_staging_images_ins on storage.objects
  for insert to authenticated with check (
    bucket_id = 'pwa-staging-images'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = (select auth.uid())::text
  );
-- No UPDATE/DELETE policy: objects are immutable; soft-delete keeps them (§22).

commit;

-- End of 0002. No production object was touched. Only pwa_staging.* and the
-- private bucket pwa-staging-images (+ its scoped policies) were created.
