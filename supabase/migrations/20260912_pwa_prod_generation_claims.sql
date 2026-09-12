-- ============================================================================
-- 20260912_pwa_prod_generation_claims — the generation RESERVATION, production.
--
-- WHAT THIS IS. The smallest set of objects the validated Web generation path
-- needs to run once and only once: one claim per idempotency key, and the two
-- settlements (completed / failed). Every definition is copied VERBATIM from
-- `20260904_pwa_production_schema.sql` (itself a reviewed pg_dump of staging);
-- nothing is retyped and nothing else from that file is created here.
--
--   CREATED
--     table      pwa.pwa_generation_claims (+ pkey, the UNIQUE identity index,
--                the project index, RLS enabled, 3 authenticated-only policies,
--                SELECT/INSERT/UPDATE grants)
--     functions  claim_generation, complete_generation, fail_generation
--
--   NOT CREATED (unchanged from the persistence migration)
--     pwa_installations, the storage bucket (its own reviewed script), any
--     public.* row, any product.
--
-- BILLING IS NOT TOUCHED. A claim decides whether the PROVIDER is called; the
-- debit stays where it is (`billing_try_hold` / the ledger). No function here
-- reads or writes public.*.
--
-- Outside `pwa` it only REFERENCES nothing at all: the table's owner column
-- defaults to auth.uid() and carries no foreign key, exactly as staging.
--
-- FIRST-INSTALL ONLY: refuses if the table or any of the three functions exist.
--
-- Rollback : backend/sql/rollback/20260912_pwa_prod_generation_claims_rollback.sql
-- Test     : backend/sql/tests/pwa_prod_generation_claims_test.sql
-- ============================================================================

begin;

do $guard$
begin
  if not exists (select 1 from pg_namespace where nspname = 'pwa') then
    raise exception 'Schema "pwa" is missing - this is not the PWA production project.';
  end if;
  if exists (select 1 from pg_namespace where nspname = 'pwa_staging') then
    raise exception 'Schema "pwa_staging" exists here - refusing: this looks like STAGING.';
  end if;
  if to_regclass('pwa.pwa_generation_claims') is not null then
    raise exception 'pwa.pwa_generation_claims already exists. Roll back before re-running.';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'pwa'
                and p.proname in ('claim_generation', 'complete_generation', 'fail_generation')) then
    raise exception 'A generation function already exists. Roll back before re-running.';
  end if;
end
$guard$;

-- ── the table ───────────────────────────────────────────────────────────────

CREATE TABLE pwa.pwa_generation_claims (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_user_id uuid DEFAULT auth.uid() NOT NULL,
    idempotency_key text NOT NULL,
    project_id uuid NOT NULL,
    parent_vision_id uuid,
    action_type text NOT NULL,
    state text DEFAULT 'PROCESSING'::text NOT NULL,
    result_vision_id uuid,
    error_code text,
    render_started boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pwa_generation_claims_state_check CHECK ((state = ANY (ARRAY['PROCESSING'::text, 'COMPLETED'::text, 'FAILED'::text])))
);

ALTER TABLE ONLY pwa.pwa_generation_claims
    ADD CONSTRAINT pwa_generation_claims_pkey PRIMARY KEY (id);

-- THE key of the whole contract: one claim per (owner, idempotency key).
CREATE UNIQUE INDEX pwa_generation_claims_identity ON pwa.pwa_generation_claims USING btree (owner_user_id, idempotency_key);
CREATE INDEX pwa_generation_claims_project ON pwa.pwa_generation_claims USING btree (project_id);

-- ── the three functions ─────────────────────────────────────────────────────

CREATE FUNCTION pwa.claim_generation(p_idempotency_key text, p_project_id uuid, p_action_type text, p_parent_vision_id uuid DEFAULT NULL::uuid) RETURNS TABLE(won boolean, state text, result_vision_id uuid, error_code text)
    LANGUAGE plpgsql
    SET search_path TO 'pwa', 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'claim_generation requires an authenticated caller';
  end if;

  -- 1) The common case: nobody has claimed this yet. ON CONFLICT DO NOTHING
  --    makes the race harmless — exactly one concurrent caller inserts.
  insert into pwa.pwa_generation_claims
    (owner_user_id, idempotency_key, project_id, action_type, parent_vision_id)
  values (v_uid, p_idempotency_key, p_project_id, p_action_type, p_parent_vision_id)
  on conflict (owner_user_id, idempotency_key) do nothing
  returning true, pwa_generation_claims.state, null::uuid, null::text
  into won, state, result_vision_id, error_code;

  if won then
    return next;
    return;
  end if;

  -- 2) Someone already holds it. Take the ROW LOCK before deciding, so two
  --    retries of the same FAILED claim cannot both conclude they may render.
  select c.state, c.result_vision_id, c.error_code
    into state, result_vision_id, error_code
    from pwa.pwa_generation_claims c
   where c.owner_user_id = v_uid
     and c.idempotency_key = p_idempotency_key
     for update;

  -- A PROCESSING claim whose owner died never settles, and would block its own
  -- retry for ever. A render takes ~2 minutes; well past that, the holder is
  -- gone and the claim is stale. Long enough never to race a live render,
  -- short enough that a user is not stuck.
  if state = 'PROCESSING'
     and (select c.updated_at from pwa.pwa_generation_claims c
           where c.owner_user_id = v_uid
             and c.idempotency_key = p_idempotency_key) < now() - interval '15 minutes'
  then
    state := 'FAILED';
  end if;

  if state = 'FAILED' then
    -- A failed attempt may be retried; this caller takes it over.
    update pwa.pwa_generation_claims c
       set state = 'PROCESSING', error_code = null, updated_at = now()
     where c.owner_user_id = v_uid
       and c.idempotency_key = p_idempotency_key;
    won := true;
    state := 'PROCESSING';
    error_code := null;
  else
    -- PROCESSING or COMPLETED: this caller must NOT call the provider.
    won := false;
  end if;

  return next;
end
$$;

CREATE FUNCTION pwa.complete_generation(p_idempotency_key text, p_vision_id uuid) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pwa', 'public'
    AS $$
  update pwa.pwa_generation_claims
     set state = 'COMPLETED', result_vision_id = p_vision_id,
         error_code = null, render_started = true, updated_at = now()
   where owner_user_id = auth.uid() and idempotency_key = p_idempotency_key;
$$;

CREATE FUNCTION pwa.fail_generation(p_idempotency_key text, p_error_code text, p_render_started boolean) RETURNS void
    LANGUAGE sql
    SET search_path TO 'pwa', 'public'
    AS $$
  update pwa.pwa_generation_claims
     set state = 'FAILED', error_code = p_error_code,
         render_started = p_render_started, updated_at = now()
   where owner_user_id = auth.uid() and idempotency_key = p_idempotency_key;
$$;

-- ── row level security + grants (authenticated only, never anon) ────────────

ALTER TABLE pwa.pwa_generation_claims ENABLE ROW LEVEL SECURITY;

CREATE POLICY pwa_claims_own_insert ON pwa.pwa_generation_claims FOR INSERT TO authenticated WITH CHECK ((owner_user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY pwa_claims_own_select ON pwa.pwa_generation_claims FOR SELECT TO authenticated USING ((owner_user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY pwa_claims_own_update ON pwa.pwa_generation_claims FOR UPDATE TO authenticated USING ((owner_user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((owner_user_id = ( SELECT auth.uid() AS uid)));

GRANT SELECT,INSERT,UPDATE ON TABLE pwa.pwa_generation_claims TO authenticated;
GRANT ALL ON FUNCTION pwa.claim_generation(p_idempotency_key text, p_project_id uuid, p_action_type text, p_parent_vision_id uuid) TO authenticated;
GRANT ALL ON FUNCTION pwa.complete_generation(p_idempotency_key text, p_vision_id uuid) TO authenticated;
GRANT ALL ON FUNCTION pwa.fail_generation(p_idempotency_key text, p_error_code text, p_render_started boolean) TO authenticated;

commit;

notify pgrst, 'reload schema';
