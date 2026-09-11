-- ============================================================================
-- 20260911_pwa_prod_persistence_minimal — the Web app's PROJECT LIBRARY, prod.
--
-- WHAT THIS IS. The smallest set of objects the PWA persistence repository
-- (`supabase_pwa_persistence_repository.dart`) needs for navigation: the
-- library, startup restore, deep links and project history. Every definition
-- below is copied VERBATIM from `20260904_pwa_production_schema.sql` (itself a
-- reviewed `pg_dump --schema-only` of staging), nothing retyped from memory.
--
--   REQUIRED NOW (created here)
--     tables     pwa.pwa_projects, pwa.pwa_visions, pwa.pwa_messages
--                + their keys, indexes, FKs, RLS (enabled AND forced),
--                8 policies (authenticated only), SELECT/INSERT/UPDATE grants
--     functions  set_owner_user_id, touch_updated_at, guard_message_immutable
--                (the triggers), soft_delete_project, deep_duplicate_project
--                (the two library actions of My Projects)
--
--   DELIBERATELY NOT CREATED
--     pwa_installations / upsert_installation   never called by the client
--     pwa_generation_claims / claim_ / complete_ / fail_generation
--                                                generation only (closed)
--     bucket pwa-images + its policies           storage only (uploads happen
--                                                at generation time)
--     public.products rows                       shared with the native app
--
-- WHAT IT TOUCHES OUTSIDE `pwa`: nothing is altered. The owner columns
-- REFERENCE auth.users (ON DELETE CASCADE) — the same pattern as
-- pwa.payway_transactions.user_id, applied 2026-09-11. No public.*, no
-- storage.*, no RevenueCat, no native table or function.
--
-- PRECONDITION: schema `pwa` exists (20260911_pwa_prod_payment_rail_minimal).
-- FIRST-INSTALL ONLY: refuses if any object it creates already exists.
--
-- Rollback : backend/sql/rollback/20260911_pwa_prod_persistence_minimal_rollback.sql
-- Test     : backend/sql/tests/pwa_prod_persistence_minimal_test.sql
-- ============================================================================

begin;

-- plpgsql validates table references at CREATE time; the functions below are
-- created before the tables they read (same as the reviewed dump).
set local check_function_bodies = off;

do $guard$
begin
  if not exists (select 1 from pg_namespace where nspname = 'pwa') then
    raise exception 'Schema "pwa" is missing - apply 20260911_pwa_prod_payment_rail_minimal first.';
  end if;
  if to_regclass('pwa.pwa_projects') is not null
     or to_regclass('pwa.pwa_visions') is not null
     or to_regclass('pwa.pwa_messages') is not null then
    raise exception 'PWA persistence tables already exist. Roll back before re-running.';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'pwa'
                and p.proname in ('set_owner_user_id', 'touch_updated_at',
                                  'guard_message_immutable', 'soft_delete_project',
                                  'deep_duplicate_project')) then
    raise exception 'A PWA persistence function already exists. Roll back before re-running.';
  end if;
end
$guard$;

-- ── functions ───────────────────────────────────────────────────────────────

CREATE FUNCTION pwa.deep_duplicate_project(p_project_id uuid, p_new_title text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_owner       uuid := auth.uid();
  v_new_project uuid := gen_random_uuid();
  v_title       text := btrim(coalesce(p_new_title, ''));
begin
  if v_owner is null then
    raise exception 'PWA: not authenticated.';
  end if;
  if v_title = '' then
    raise exception 'PWA: new title is required.';
  end if;
  if not exists (
    select 1 from pwa.pwa_projects
    where id = p_project_id and owner_user_id = v_owner and deleted_at is null
  ) then
    raise exception 'PWA: source project not found for this owner.';
  end if;

  create temp table _vmap (old_id uuid primary key, new_id uuid not null) on commit drop;
  create temp table _mmap (old_id uuid primary key, new_id uuid not null) on commit drop;
  insert into _vmap select id, gen_random_uuid()
    from pwa.pwa_visions where project_id = p_project_id and owner_user_id = v_owner;
  insert into _mmap select id, gen_random_uuid()
    from pwa.pwa_messages where project_id = p_project_id and owner_user_id = v_owner;

  -- 1) new project — current/cover remapped up front (cyclic FKs to visions are
  --    DEFERRABLE INITIALLY DEFERRED → validated at COMMIT once visions exist).
  insert into pwa.pwa_projects
    (id, owner_user_id, installation_id, title, status, room_id, room_label,
     selected_atmosphere_id, selected_atmosphere_label, original_image_source,
     original_image_path, current_vision_id, cover_vision_id, revision,
     client_created_order, client_updated_order, schema_version)
  select v_new_project, v_owner, op.installation_id, v_title, op.status, op.room_id, op.room_label,
         op.selected_atmosphere_id, op.selected_atmosphere_label, op.original_image_source,
         op.original_image_path, cvm.new_id, ovm.new_id, 1,
         op.client_created_order, op.client_updated_order, op.schema_version
  from pwa.pwa_projects op
  left join _vmap cvm on cvm.old_id = op.current_vision_id
  left join _vmap ovm on ovm.old_id = op.cover_vision_id
  where op.id = p_project_id and op.owner_user_id = v_owner;

  -- 2) visions — parent + source_message remapped inline (both FKs deferred);
  --    ordered by vision_number so the deferred parent self-FK is coherent.
  insert into pwa.pwa_visions
    (id, project_id, owner_user_id, vision_number, parent_vision_id, action_type,
     action_summary, prompt_text, atmosphere_id, atmosphere_label, image_source,
     image_path, source_message_id, client_order, idempotency_key, schema_version)
  select vm.new_id, v_new_project, v_owner, v.vision_number, pvm.new_id, v.action_type,
         v.action_summary, v.prompt_text, v.atmosphere_id, v.atmosphere_label, v.image_source,
         v.image_path, smm.new_id, v.client_order, gen_random_uuid(), v.schema_version
  from pwa.pwa_visions v
  join _vmap vm on vm.old_id = v.id
  left join _vmap pvm on pvm.old_id = v.parent_vision_id
  left join _mmap smm on smm.old_id = v.source_message_id
  where v.project_id = p_project_id and v.owner_user_id = v_owner
  order by v.vision_number;

  -- 3) messages — referenced_vision remapped (visions now exist); new idempotency.
  insert into pwa.pwa_messages
    (id, project_id, owner_user_id, role, message_type, text_content, intent,
     referenced_vision_id, confirmation_state, client_order, idempotency_key,
     metadata_json, schema_version)
  select mm.new_id, v_new_project, v_owner, m.role, m.message_type, m.text_content, m.intent,
         rvm.new_id, m.confirmation_state, m.client_order, gen_random_uuid(),
         m.metadata_json, m.schema_version
  from pwa.pwa_messages m
  join _mmap mm on mm.old_id = m.id
  left join _vmap rvm on rvm.old_id = m.referenced_vision_id
  where m.project_id = p_project_id and m.owner_user_id = v_owner;

  return v_new_project;
end
$$;

CREATE FUNCTION pwa.guard_message_immutable() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
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
    raise exception 'PWA: only confirmation_state/metadata_json are mutable on a message.';
  end if;
  return new;
end
$$;

CREATE FUNCTION pwa.set_owner_user_id() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  new.owner_user_id := auth.uid();
  if new.owner_user_id is null then
    raise exception 'PWA: no authenticated user (auth.uid() is null).';
  end if;
  return new;
end
$$;

CREATE FUNCTION pwa.soft_delete_project(p_project_id uuid) RETURNS void
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  v_owner uuid := auth.uid();
begin
  if v_owner is null then
    raise exception 'PWA: not authenticated.';
  end if;
  update pwa.pwa_projects
     set deleted_at = now()
   where id = p_project_id and owner_user_id = v_owner and deleted_at is null;
end
$$;

CREATE FUNCTION pwa.touch_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  new.updated_at := now();
  return new;
end
$$;

-- ── tables ──────────────────────────────────────────────────────────────────

CREATE TABLE pwa.pwa_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    owner_user_id uuid NOT NULL,
    role text NOT NULL,
    message_type text NOT NULL,
    text_content text,
    intent text,
    referenced_vision_id uuid,
    confirmation_state text,
    client_order bigint NOT NULL,
    idempotency_key uuid NOT NULL,
    metadata_json jsonb,
    schema_version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pwa_messages_confirmation_state_check CHECK ((confirmation_state = ANY (ARRAY['pending'::text, 'cancelled'::text, 'confirmed'::text, 'completed'::text]))),
    CONSTRAINT pwa_messages_role_check CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text, 'system'::text]))),
    CONSTRAINT pwa_messages_schema_version_check CHECK ((schema_version = 1))
);

ALTER TABLE ONLY pwa.pwa_messages FORCE ROW LEVEL SECURITY;

CREATE TABLE pwa.pwa_projects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_user_id uuid NOT NULL,
    installation_id uuid,
    title text NOT NULL,
    status text NOT NULL,
    room_id text NOT NULL,
    room_label text NOT NULL,
    selected_atmosphere_id text NOT NULL,
    selected_atmosphere_label text NOT NULL,
    original_image_source text,
    original_image_path text,
    current_vision_id uuid,
    cover_vision_id uuid,
    revision integer DEFAULT 1 NOT NULL,
    client_created_order bigint,
    client_updated_order bigint,
    schema_version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    resolved_room_type text,
    CONSTRAINT pwa_projects_original_image_source_check CHECK ((original_image_source = ANY (ARRAY['bundle'::text, 'staging_storage'::text]))),
    CONSTRAINT pwa_projects_revision_check CHECK ((revision >= 1)),
    CONSTRAINT pwa_projects_schema_version_check CHECK ((schema_version = 1)),
    CONSTRAINT pwa_projects_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text]))),
    CONSTRAINT pwa_projects_title_check CHECK (((title = btrim(title)) AND (title <> ''::text)))
);

ALTER TABLE ONLY pwa.pwa_projects FORCE ROW LEVEL SECURITY;

COMMENT ON COLUMN pwa.pwa_projects.resolved_room_type IS 'Canonical room id resolved by Ayden Decide (living_room, terrace, ...). Written ONLY when the person delegated the room; an explicit choice is never overridden. Mirrors mobile, where the resolved room is returned by /generate and persisted into the session.';

CREATE TABLE pwa.pwa_visions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    project_id uuid NOT NULL,
    owner_user_id uuid NOT NULL,
    vision_number integer NOT NULL,
    parent_vision_id uuid,
    action_type text NOT NULL,
    action_summary text,
    prompt_text text,
    atmosphere_id text NOT NULL,
    atmosphere_label text NOT NULL,
    image_source text NOT NULL,
    image_path text NOT NULL,
    source_message_id uuid,
    client_order bigint,
    idempotency_key uuid NOT NULL,
    schema_version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    lineage_customized boolean,
    room_label text,
    CONSTRAINT pwa_visions_action_type_check CHECK ((action_type = ANY (ARRAY['initial'::text, 'refine'::text, 'switch_atmosphere'::text]))),
    CONSTRAINT pwa_visions_image_source_check CHECK ((image_source = ANY (ARRAY['bundle'::text, 'staging_storage'::text]))),
    CONSTRAINT pwa_visions_schema_version_check CHECK ((schema_version = 1)),
    CONSTRAINT pwa_visions_vision_number_check CHECK ((vision_number > 0))
);

ALTER TABLE ONLY pwa.pwa_visions FORCE ROW LEVEL SECURITY;

COMMENT ON COLUMN pwa.pwa_visions.lineage_customized IS 'Cumulative along the BRANCH, exactly as mobile computes it: a new vision is customized when its SOURCE vision was, or when this edit is itself a spatial change. NULL = written before migration 0005 -> the adapter walks the ancestry instead of assuming false.';

COMMENT ON COLUMN pwa.pwa_visions.room_label IS 'The room the engine ACTUALLY used for this vision (after Ayden Decide resolved "Your space"). What keyed the per-room DNA, not what the browser asked for.';

-- ── keys ────────────────────────────────────────────────────────────────────

ALTER TABLE ONLY pwa.pwa_messages
    ADD CONSTRAINT pwa_messages_id_project_id_owner_user_id_key UNIQUE (id, project_id, owner_user_id);
ALTER TABLE ONLY pwa.pwa_messages
    ADD CONSTRAINT pwa_messages_owner_user_id_idempotency_key_key UNIQUE (owner_user_id, idempotency_key);
ALTER TABLE ONLY pwa.pwa_messages
    ADD CONSTRAINT pwa_messages_pkey PRIMARY KEY (id);
ALTER TABLE ONLY pwa.pwa_projects
    ADD CONSTRAINT pwa_projects_id_owner_user_id_key UNIQUE (id, owner_user_id);
ALTER TABLE ONLY pwa.pwa_projects
    ADD CONSTRAINT pwa_projects_pkey PRIMARY KEY (id);
ALTER TABLE ONLY pwa.pwa_visions
    ADD CONSTRAINT pwa_visions_id_project_id_owner_user_id_key UNIQUE (id, project_id, owner_user_id);
ALTER TABLE ONLY pwa.pwa_visions
    ADD CONSTRAINT pwa_visions_owner_user_id_idempotency_key_key UNIQUE (owner_user_id, idempotency_key);
ALTER TABLE ONLY pwa.pwa_visions
    ADD CONSTRAINT pwa_visions_pkey PRIMARY KEY (id);
ALTER TABLE ONLY pwa.pwa_visions
    ADD CONSTRAINT pwa_visions_project_id_vision_number_key UNIQUE (project_id, vision_number);

-- ── indexes ─────────────────────────────────────────────────────────────────

CREATE INDEX pwa_messages_project_idx ON pwa.pwa_messages USING btree (owner_user_id, project_id, client_order, created_at);
CREATE INDEX pwa_projects_owner_deleted_idx ON pwa.pwa_projects USING btree (owner_user_id, deleted_at);
CREATE INDEX pwa_projects_owner_status_idx ON pwa.pwa_projects USING btree (owner_user_id, status);
CREATE INDEX pwa_projects_owner_updated_idx ON pwa.pwa_projects USING btree (owner_user_id, updated_at DESC) WHERE (deleted_at IS NULL);
CREATE INDEX pwa_visions_project_idx ON pwa.pwa_visions USING btree (owner_user_id, project_id, vision_number);

-- ── triggers ────────────────────────────────────────────────────────────────

CREATE TRIGGER pwa_messages_immutable BEFORE UPDATE ON pwa.pwa_messages FOR EACH ROW EXECUTE FUNCTION pwa.guard_message_immutable();
CREATE TRIGGER pwa_messages_set_owner BEFORE INSERT ON pwa.pwa_messages FOR EACH ROW EXECUTE FUNCTION pwa.set_owner_user_id();
CREATE TRIGGER pwa_projects_set_owner BEFORE INSERT ON pwa.pwa_projects FOR EACH ROW EXECUTE FUNCTION pwa.set_owner_user_id();
CREATE TRIGGER pwa_projects_touch BEFORE UPDATE ON pwa.pwa_projects FOR EACH ROW EXECUTE FUNCTION pwa.touch_updated_at();
CREATE TRIGGER pwa_visions_set_owner BEFORE INSERT ON pwa.pwa_visions FOR EACH ROW EXECUTE FUNCTION pwa.set_owner_user_id();

-- ── foreign keys ────────────────────────────────────────────────────────────

ALTER TABLE ONLY pwa.pwa_messages
    ADD CONSTRAINT pwa_messages_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE ONLY pwa.pwa_messages
    ADD CONSTRAINT pwa_messages_project_owner_fk FOREIGN KEY (project_id, owner_user_id) REFERENCES pwa.pwa_projects(id, owner_user_id) ON DELETE CASCADE;
ALTER TABLE ONLY pwa.pwa_messages
    ADD CONSTRAINT pwa_messages_refvision_owner_fk FOREIGN KEY (referenced_vision_id, project_id, owner_user_id) REFERENCES pwa.pwa_visions(id, project_id, owner_user_id) ON DELETE SET NULL;
ALTER TABLE ONLY pwa.pwa_projects
    ADD CONSTRAINT pwa_projects_cover_vision_fk FOREIGN KEY (cover_vision_id, id, owner_user_id) REFERENCES pwa.pwa_visions(id, project_id, owner_user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY pwa.pwa_projects
    ADD CONSTRAINT pwa_projects_current_vision_fk FOREIGN KEY (current_vision_id, id, owner_user_id) REFERENCES pwa.pwa_visions(id, project_id, owner_user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY pwa.pwa_projects
    ADD CONSTRAINT pwa_projects_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE ONLY pwa.pwa_visions
    ADD CONSTRAINT pwa_visions_owner_user_id_fkey FOREIGN KEY (owner_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE ONLY pwa.pwa_visions
    ADD CONSTRAINT pwa_visions_parent_owner_fk FOREIGN KEY (parent_vision_id, project_id, owner_user_id) REFERENCES pwa.pwa_visions(id, project_id, owner_user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
ALTER TABLE ONLY pwa.pwa_visions
    ADD CONSTRAINT pwa_visions_project_owner_fk FOREIGN KEY (project_id, owner_user_id) REFERENCES pwa.pwa_projects(id, owner_user_id) ON DELETE CASCADE;
ALTER TABLE ONLY pwa.pwa_visions
    ADD CONSTRAINT pwa_visions_srcmsg_owner_fk FOREIGN KEY (source_message_id, project_id, owner_user_id) REFERENCES pwa.pwa_messages(id, project_id, owner_user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- ── row level security ──────────────────────────────────────────────────────

ALTER TABLE pwa.pwa_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY pwa_messages_ins ON pwa.pwa_messages FOR INSERT TO authenticated WITH CHECK ((owner_user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY pwa_messages_sel ON pwa.pwa_messages FOR SELECT TO authenticated USING ((owner_user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY pwa_messages_upd ON pwa.pwa_messages FOR UPDATE TO authenticated USING ((owner_user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((owner_user_id = ( SELECT auth.uid() AS uid)));

ALTER TABLE pwa.pwa_projects ENABLE ROW LEVEL SECURITY;
CREATE POLICY pwa_projects_ins ON pwa.pwa_projects FOR INSERT TO authenticated WITH CHECK ((owner_user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY pwa_projects_sel ON pwa.pwa_projects FOR SELECT TO authenticated USING ((owner_user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY pwa_projects_upd ON pwa.pwa_projects FOR UPDATE TO authenticated USING ((owner_user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((owner_user_id = ( SELECT auth.uid() AS uid)));

ALTER TABLE pwa.pwa_visions ENABLE ROW LEVEL SECURITY;
CREATE POLICY pwa_visions_ins ON pwa.pwa_visions FOR INSERT TO authenticated WITH CHECK ((owner_user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY pwa_visions_sel ON pwa.pwa_visions FOR SELECT TO authenticated USING ((owner_user_id = ( SELECT auth.uid() AS uid)));

-- ── grants (authenticated only; never anon, never DELETE) ───────────────────

REVOKE ALL ON FUNCTION pwa.deep_duplicate_project(p_project_id uuid, p_new_title text) FROM PUBLIC;
GRANT ALL ON FUNCTION pwa.deep_duplicate_project(p_project_id uuid, p_new_title text) TO authenticated;
REVOKE ALL ON FUNCTION pwa.soft_delete_project(p_project_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION pwa.soft_delete_project(p_project_id uuid) TO authenticated;

GRANT SELECT,INSERT,UPDATE ON TABLE pwa.pwa_messages TO authenticated;
GRANT SELECT,INSERT,UPDATE ON TABLE pwa.pwa_projects TO authenticated;
GRANT SELECT,INSERT ON TABLE pwa.pwa_visions TO authenticated;

commit;

-- PostgREST learns the new tables from its schema cache.
notify pgrst, 'reload schema';
