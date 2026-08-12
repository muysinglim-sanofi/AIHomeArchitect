-- ============================================================================
-- AYDEN STUDIO PWA — DURABLE GENERATION LIFECYCLE
-- 0004 — additive, IDEMPOTENT.  Schema: pwa_staging.  STAGING ONLY.
-- ----------------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--   A generation costs money the moment the provider answers. Today the PWA is
--   protected by two things: a UNIQUE constraint on `pwa_visions
--   (owner_user_id, idempotency_key)`, which stops a second ROW, and an
--   in-process single-flight map in the adapter, which stops a second CALL.
--
--   Neither survives a backend restart, and neither exists across processes.
--   The vision row is only written AFTER the render, so between "request
--   accepted" and "image stored" there is a window in which a refresh, a retry
--   or a second worker can start a second paid render. This table closes that
--   window by reserving the operation BEFORE the provider is called.
--
--   It is the staging equivalent of what mobile does with
--   `public.generation_intents` + the `claim_intent` RPC. Same protocol, same
--   states; a different table because `pwa_staging` is a separate tenancy with
--   its own RLS.
--
-- WHAT IT CREATES
--   * table  pwa_staging.pwa_generation_claims
--   * unique index on (owner_user_id, idempotency_key)  ← the atomic claim
--   * RLS: a caller sees and touches ONLY its own claims
--   * function pwa_staging.claim_generation(...)        ← INSERT .. ON CONFLICT
--   * function pwa_staging.complete_generation(...)
--   * function pwa_staging.fail_generation(...)
--
-- WHAT IT NEVER DOES
--   * touch pwa_projects / pwa_visions / pwa_messages (0002 owns those)
--   * touch any production object
--   * widen an existing policy
--   * contain a secret
--
-- SAFETY
--   ONE transaction; the guard RAISEs before any DDL, so absent GUCs abort the
--   whole thing and NOTHING is written. Replayable: every object is created
--   only if missing.
--
--     set app.ayden_allow_staging_migrations = 'true';
--     set app.ayden_env = 'staging';
--
--   The operator MUST verify the connection target is project ref
--   eedcahzekpgxvvfxufbk before running — on Supabase both databases are named
--   `postgres`, so the database name cannot distinguish them.
-- ============================================================================

begin;

-- ── Guard (fail closed) ─────────────────────────────────────────────────────
do $guard$
begin
  if coalesce(current_setting('app.ayden_allow_staging_migrations', true), 'false') <> 'true' then
    raise exception
      'Refusing PWA staging migration 0004: app.ayden_allow_staging_migrations is not true (fail closed).';
  end if;
  if coalesce(current_setting('app.ayden_env', true), '') <> 'staging' then
    raise exception
      'Refusing PWA staging migration 0004: app.ayden_env is not ''staging'' (fail closed). Verify the connection target is the isolated staging project (ref eedcahzekpgxvvfxufbk).';
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'pwa_staging') then
    raise exception
      'Refusing PWA staging migration 0004: schema pwa_staging does not exist. Apply 0002 first.';
  end if;
end
$guard$;

-- ── The claim table ─────────────────────────────────────────────────────────
create table if not exists pwa_staging.pwa_generation_claims (
  id                uuid primary key default gen_random_uuid(),
  owner_user_id     uuid not null default auth.uid(),
  idempotency_key   text not null,
  project_id        uuid not null,
  parent_vision_id  uuid,
  action_type       text not null,
  -- PROCESSING → the provider may be called by the winner, and by nobody else.
  -- COMPLETED  → `result_vision_id` is the answer; never render again.
  -- FAILED     → a controlled retry may re-claim it.
  state             text not null default 'PROCESSING'
                      check (state in ('PROCESSING', 'COMPLETED', 'FAILED')),
  result_vision_id  uuid,
  error_code        text,
  -- Whether the PAID call had begun when this failed. It is the only honest
  -- basis for telling a user nothing was charged.
  render_started    boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- THE atomic claim. Two concurrent inserts, one winner — decided by Postgres,
-- not by a read-then-write race in the application.
create unique index if not exists pwa_generation_claims_identity
  on pwa_staging.pwa_generation_claims (owner_user_id, idempotency_key);

create index if not exists pwa_generation_claims_project
  on pwa_staging.pwa_generation_claims (project_id);

alter table pwa_staging.pwa_generation_claims enable row level security;

-- ── RLS: a caller only ever sees its own claims ─────────────────────────────
do $policies$
begin
  if not exists (select 1 from pg_policies
                 where schemaname = 'pwa_staging'
                   and tablename = 'pwa_generation_claims'
                   and policyname = 'pwa_claims_own_select') then
    create policy pwa_claims_own_select on pwa_staging.pwa_generation_claims
      for select to authenticated using (owner_user_id = (select auth.uid()));
  end if;

  if not exists (select 1 from pg_policies
                 where schemaname = 'pwa_staging'
                   and tablename = 'pwa_generation_claims'
                   and policyname = 'pwa_claims_own_insert') then
    create policy pwa_claims_own_insert on pwa_staging.pwa_generation_claims
      for insert to authenticated with check (owner_user_id = (select auth.uid()));
  end if;

  if not exists (select 1 from pg_policies
                 where schemaname = 'pwa_staging'
                   and tablename = 'pwa_generation_claims'
                   and policyname = 'pwa_claims_own_update') then
    create policy pwa_claims_own_update on pwa_staging.pwa_generation_claims
      for update to authenticated
      using (owner_user_id = (select auth.uid()))
      with check (owner_user_id = (select auth.uid()));
  end if;
end
$policies$;

-- ── claim_generation: the whole protocol in one atomic statement ────────────
-- Returns exactly one row:
--   won = true   → this caller reserved it and MAY call the provider
--   won = false  → `state` says what the other caller is doing / has done
--
-- A FAILED claim is re-claimable: the retry takes it back to PROCESSING in the
-- same statement, so a retry cannot race a second retry either.
create or replace function pwa_staging.claim_generation(
  p_idempotency_key  text,
  p_project_id       uuid,
  p_action_type      text,
  p_parent_vision_id uuid default null
)
returns table (won boolean, state text, result_vision_id uuid, error_code text)
language plpgsql
security invoker            -- RLS still applies: a caller cannot claim for another
set search_path = pwa_staging, public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'claim_generation requires an authenticated caller';
  end if;

  -- 1) The common case: nobody has claimed this yet. ON CONFLICT DO NOTHING
  --    makes the race harmless — exactly one concurrent caller inserts.
  insert into pwa_staging.pwa_generation_claims
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
    from pwa_staging.pwa_generation_claims c
   where c.owner_user_id = v_uid
     and c.idempotency_key = p_idempotency_key
     for update;

  -- A PROCESSING claim whose owner died never settles, and would block its own
  -- retry for ever. A render takes ~2 minutes; well past that, the holder is
  -- gone and the claim is stale. Long enough never to race a live render,
  -- short enough that a user is not stuck.
  if state = 'PROCESSING'
     and (select c.updated_at from pwa_staging.pwa_generation_claims c
           where c.owner_user_id = v_uid
             and c.idempotency_key = p_idempotency_key) < now() - interval '15 minutes'
  then
    state := 'FAILED';
  end if;

  if state = 'FAILED' then
    -- A failed attempt may be retried; this caller takes it over.
    update pwa_staging.pwa_generation_claims c
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

create or replace function pwa_staging.complete_generation(
  p_idempotency_key text,
  p_vision_id       uuid
) returns void
language sql security invoker set search_path = pwa_staging, public as $$
  update pwa_staging.pwa_generation_claims
     set state = 'COMPLETED', result_vision_id = p_vision_id,
         error_code = null, render_started = true, updated_at = now()
   where owner_user_id = auth.uid() and idempotency_key = p_idempotency_key;
$$;

create or replace function pwa_staging.fail_generation(
  p_idempotency_key text,
  p_error_code      text,
  p_render_started  boolean
) returns void
language sql security invoker set search_path = pwa_staging, public as $$
  update pwa_staging.pwa_generation_claims
     set state = 'FAILED', error_code = p_error_code,
         render_started = p_render_started, updated_at = now()
   where owner_user_id = auth.uid() and idempotency_key = p_idempotency_key;
$$;

grant usage on schema pwa_staging to authenticated;
grant select, insert, update on pwa_staging.pwa_generation_claims to authenticated;
grant execute on function pwa_staging.claim_generation(text, uuid, text, uuid) to authenticated;
grant execute on function pwa_staging.complete_generation(text, uuid) to authenticated;
grant execute on function pwa_staging.fail_generation(text, text, boolean) to authenticated;

-- ── Report (read-only) ──────────────────────────────────────────────────────
do $report$
declare
  n_policies integer;
  n_index    integer;
begin
  select count(*) into n_policies from pg_policies
   where schemaname = 'pwa_staging' and tablename = 'pwa_generation_claims';
  select count(*) into n_index from pg_indexes
   where schemaname = 'pwa_staging' and indexname = 'pwa_generation_claims_identity';
  raise notice '0004 RESULT: policies=%/3  identity_index=%/1', n_policies, n_index;
  if n_index <> 1 then
    raise exception '0004: the atomic claim index is missing — refusing to commit.';
  end if;
  if n_policies < 3 then
    raise exception '0004: expected 3 RLS policies, found % — refusing to commit.', n_policies;
  end if;
end
$report$;

commit;

-- End of 0004. Additive and replayable. pwa_projects / pwa_visions /
-- pwa_messages untouched. No production object considered.
