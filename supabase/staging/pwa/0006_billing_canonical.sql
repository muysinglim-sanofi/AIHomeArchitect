-- ============================================================================
-- AYDEN STUDIO PWA — CANONICAL BILLING ENGINE (staging install)
-- 0006 — additive, IDEMPOTENT.  Schema: public.  STAGING ONLY.
-- ----------------------------------------------------------------------------
-- WHY THIS FILE EXISTS
--
--   The PWA staging project had an EMPTY `public` schema (0 tables, 0 RPCs —
--   measured, PWA_MONETIZATION_AUDIT §8.1), so `/pwa/staging/generate` had no
--   entitlement to consult and every generation was free and unlimited.
--
--   This installs the CANONICAL Billing Engine — the same objects, the same
--   names, the same business semantics as production. It is NOT a PWA billing
--   schema. There is exactly one billing brain and the browser is a caller of
--   it, never an owner of a second one.
--
-- WHERE EACH BLOCK COMES FROM (canonical source → block below)
--
--   §1  public.sessions            NEW — minimal shell, see "THE SESSIONS SHELL"
--   §2  user_roles                 supabase/migrations/20260530_wave_5_17b_usage_quota.sql
--                                  + 20260601_wave_5_17d_premium_role.sql (write grants)
--   §3  promo_codes / promo_redemptions / redeem_promo_code /
--       consume_promo_generation / get_promo_access
--                                  backend/sql/sprint_1b_promo.sql
--   §4  generation_intents         20260630_generation_intent_v1_pr0_schema.sql
--   §5  products/orders/payments/passes/ledger_entries/wallets + append-only
--                                  20260701_billing_engine_pr0_schema.sql
--   §6  passes_source_order_uidx   20260708_billing_pr2_grant_purchase_rpc.sql
--   §7  billing_reproject_wallet   20260710_billing_p0_additive_projection.sql  (FINAL)
--   §8  billing_grant_purchase     20260709_billing_pr2b_wallet_pass_projection.sql (FINAL)
--   §9  billing_try_hold           20260717_account_mode_trial_and_claim.sql §1 (FINAL, 4-arg)
--   §10 product store mapping      20260708_billing_pr2_ticket0_product_id_mapping.sql
--                                  + 20260709_billing_weekly_pass_30_spaces.sql
--
--   "FINAL" means: the canonical object was redefined by a later migration and
--   THAT is the version installed. Replaying the whole history would install an
--   intermediate `billing_reproject_wallet` (XOR projection) and an intermediate
--   `billing_try_hold` (TRIAL hard-coded to 3) — both superseded. This file
--   installs the end state, which is what production runs.
--
-- WHAT IS DELIBERATELY *NOT* INSTALLED, and why
--
--   * `usage_log` (+ its `intent_id` column)  — legacy Wave 5.17b free counter.
--     `BILLING_ENGINE_SPEC` supersedes it: the truth of the free quota is the
--     free bucket of `ledger_entries` (`billing._free_bucket_available` /
--     `billing_try_hold`). `resolve_generation_access` is used for the TIER
--     only. Installing it would create a second, divergent counter. (§8.4)
--   * `generation_jobs` — per-attempt OpenAI audit written only by the mobile
--     handler (`observe_job_start`). The adapter never writes one.
--   * `fire_count` / `increment_intent_fire` / the `v_*` observability views —
--     mobile dashboards; nothing in the PWA path reads them.
--   * `claim_intent` / `reclaim_intent` — mobile's DURABLE JOB claim. The PWA
--     already has its own (`pwa_staging.claim_generation`, migration 0004) and
--     the two are the SAME concept, not two billing models: Intent ≠ Job.
--     `generation_intents` here carries the idempotence of the BILLING; the
--     claim carries the single-flight of the RENDER.
--   * `rc_pass_transfers` / `billing_reparent_pass` / `claim_guest_and_bonus` /
--     `is_user_anonymous` / `account_state` — account-mode + RevenueCat identity
--     divergence repair. Not reachable from the Web path at this stage.
--   * `20260707_grants_hardening` — it revokes on objects this project does not
--     have (usage_log, generation_jobs, the five views) and would abort. It is
--     also not applied to production yet. Tracked as a follow-up.
--
--   These four exclusions are ALSO what `pwa_staging_db.prove_target()` now
--   uses as its "this is not production" marker, so the exclusion is enforced
--   by tooling and not only by intent.
--
-- THE SESSIONS SHELL
--
--   `public.sessions` is a MOBILE CHAT session. It is created by no migration
--   in this repository (it predates them) and its concept does not transpose to
--   the Web, where the equivalent object is `pwa_staging.pwa_projects`.
--
--   The dependency was measured, not assumed. Across the entire selected
--   canonical scope (§2..§10 above) the string `sessions` appears exactly ONCE:
--
--       generation_intents.session_id uuid references public.sessions(id)
--                                     on delete set null
--
--   No RPC, trigger, policy or view in this scope reads it. The column is
--   NULLABLE, so the Web writes `session_id = NULL` and replicates no mobile
--   session semantics whatsoever. Only the DDL needs the table to exist, and
--   only `id uuid` is needed for the constraint — so that, plus a `created_at`
--   for forensics, is all this creates. It is never written from the Web.
--
--   The alternative (drop the FK in staging) was rejected: it would produce two
--   schema truths for one engine, which is the exact thing this whole phase
--   exists to avoid.
--
-- WHAT IT NEVER DOES
--   * touch any production object (the guard + the operator tooling both refuse)
--   * create a PWA-specific wallet / pass / ledger
--   * modify the canonical business semantics of any object it installs
--   * contain a secret
--
-- SAFETY
--   ONE transaction; the guard RAISEs before any DDL, so absent GUCs abort the
--   whole thing and NOTHING is written. Replayable: every statement is
--   `if not exists` / `or replace` / `on conflict`.
--
--     set app.ayden_allow_staging_migrations = 'true';
--     set app.ayden_env = 'staging';
--
--   Apply with:  python pwa_staging_migrate.py <this file>
--   then:        notify pgrst, 'reload schema';
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
      'Refusing PWA staging migration 0006: app.ayden_allow_staging_migrations is not true (fail closed).';
  end if;
  if coalesce(current_setting('app.ayden_env', true), '') <> 'staging' then
    raise exception
      'Refusing PWA staging migration 0006: app.ayden_env is not ''staging'' (fail closed). Verify the connection target is the isolated staging project (ref eedcahzekpgxvvfxufbk).';
  end if;
  if not exists (select 1 from pg_namespace where nspname = 'pwa_staging') then
    raise exception
      'Refusing PWA staging migration 0006: schema pwa_staging does not exist. Apply 0002 first.';
  end if;
  -- Fail CLOSED on the legacy counter: if `usage_log` is present, this is either
  -- production or a project that has been given the superseded free-quota model.
  -- Either way §8.4 says stop rather than end up with two counters.
  if exists (select 1 from information_schema.tables
              where table_schema = 'public' and table_name = 'usage_log') then
    raise exception
      'Refusing PWA staging migration 0006: public.usage_log exists. The Web free quota is the ledger free bucket, never usage_log (PWA_MONETIZATION_AUDIT §8.4) — and usage_log is a PRODUCTION marker.';
  end if;
  if exists (select 1 from information_schema.tables
              where table_schema = 'public'
                and table_name in ('messages', 'account_state', 'device_tokens')) then
    raise exception
      'Refusing PWA staging migration 0006: a production-only table (messages / account_state / device_tokens) is present. This does not look like the isolated staging project.';
  end if;
end
$guard$;


-- ════════════════════════════════════════════════════════════════════════════
-- §1 — public.sessions : MINIMAL SHELL (see "THE SESSIONS SHELL" above)
-- ════════════════════════════════════════════════════════════════════════════
-- Exists so the canonical `generation_intents` FK can be created verbatim.
-- NEVER written from the Web. RLS on, no policy, no grant: unreachable from a
-- browser token, which is exactly right for a table with no Web meaning.

create table if not exists public.sessions (
  id          uuid        primary key default gen_random_uuid(),
  created_at  timestamptz not null default now()
);

comment on table public.sessions is
  'MINIMAL SHELL (PWA staging). Mobile chat sessions do not exist on the Web; '
  'this table exists ONLY so generation_intents.session_id can carry the '
  'canonical FK verbatim. The Web always writes session_id = NULL. Never insert '
  'into this table from the PWA path.';

alter table public.sessions enable row level security;
-- Deliberately NO policy and NO grant to anon/authenticated.


-- ════════════════════════════════════════════════════════════════════════════
-- §2 — user_roles  (20260530_wave_5_17b_usage_quota.sql + 20260601 grants)
-- ════════════════════════════════════════════════════════════════════════════
-- Read by quota.fetch_roles_flags → the admin/premium TIER of
-- resolve_generation_access. Verbatim canonical shape.

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

alter table public.user_roles enable row level security;

drop policy if exists "user_roles: owner read" on public.user_roles;
create policy "user_roles: owner read"
  on public.user_roles
  for select
  using (auth.uid() = user_id);

grant select, insert, update, delete on public.user_roles to service_role;
grant select                        on public.user_roles to authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- §3 — promo (backend/sql/sprint_1b_promo.sql)
-- ════════════════════════════════════════════════════════════════════════════
-- `resolve_generation_access` calls get_promo_access on EVERY access decision.
-- redeem/consume are installed too: promo.py is one module and a half-installed
-- promo system is a silent divergence waiting for the first promo tier.

create table if not exists public.promo_codes (
  id               uuid primary key default gen_random_uuid(),
  code             text not null,
  type             text not null check (type in ('limited_generations','unlimited')),
  generation_limit int,
  max_redemptions  int,
  redeemed_count   int  not null default 0,
  expires_at       timestamptz,
  active           boolean not null default true,
  campaign         text,
  note             text,
  created_by       uuid,
  created_at       timestamptz not null default now(),
  constraint chk_promo_limited_has_limit check (
        (type = 'limited_generations' and generation_limit is not null and generation_limit > 0)
     or (type = 'unlimited'           and generation_limit is null)
  ),
  constraint chk_promo_redeemed_nonneg check (redeemed_count >= 0),
  constraint chk_promo_maxred check (max_redemptions is null or max_redemptions > 0)
);

create unique index if not exists uq_promo_codes_code_upper on public.promo_codes (upper(code));
create index if not exists idx_promo_codes_active on public.promo_codes (active);

create table if not exists public.promo_redemptions (
  id               uuid primary key default gen_random_uuid(),
  promo_code_id    uuid not null references public.promo_codes(id) on delete cascade,
  user_id          uuid not null,
  unlimited        boolean not null default false,
  generation_limit int,
  generations_used int not null default 0,
  expires_at       timestamptz,
  active           boolean not null default true,
  redeemed_at      timestamptz not null default now(),
  constraint uq_one_redemption_per_user unique (promo_code_id, user_id),
  constraint chk_redemption_used_nonneg check (generations_used >= 0)
);
create index if not exists idx_promo_redemptions_user on public.promo_redemptions (user_id, active);

alter table public.promo_codes       enable row level security;
alter table public.promo_redemptions enable row level security;
-- (intentionally NO policies → anon/authenticated get zero access)

grant select, insert, update, delete on public.promo_codes       to service_role;
grant select, insert, update, delete on public.promo_redemptions to service_role;

create or replace function public.redeem_promo_code(p_user uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code   public.promo_codes%rowtype;
  v_norm   text := upper(trim(p_code));
  v_exists int;
begin
  select * into v_code from public.promo_codes
   where upper(code) = v_norm
   for update;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;
  if not v_code.active then
    return jsonb_build_object('ok', false, 'error', 'inactive_code');
  end if;
  if v_code.expires_at is not null and v_code.expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'expired_code');
  end if;

  select count(*) into v_exists from public.promo_redemptions
   where promo_code_id = v_code.id and user_id = p_user;
  if v_exists > 0 then
    return jsonb_build_object('ok', false, 'error', 'already_redeemed');
  end if;

  if v_code.max_redemptions is not null
     and v_code.redeemed_count >= v_code.max_redemptions then
    return jsonb_build_object('ok', false, 'error', 'max_redemptions_reached');
  end if;

  insert into public.promo_redemptions
    (promo_code_id, user_id, unlimited, generation_limit, expires_at)
  values
    (v_code.id, p_user, v_code.type = 'unlimited',
     case when v_code.type = 'unlimited' then null else v_code.generation_limit end,
     v_code.expires_at);

  update public.promo_codes
     set redeemed_count = redeemed_count + 1
   where id = v_code.id;

  return jsonb_build_object(
    'ok', true,
    'type', v_code.type,
    'unlimited', v_code.type = 'unlimited',
    'generation_limit', case when v_code.type = 'unlimited' then null else v_code.generation_limit end,
    'expires_at', v_code.expires_at,
    'campaign', v_code.campaign);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'already_redeemed');
end;
$$;

create or replace function public.consume_promo_generation(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id        uuid;
  v_remaining int;
begin
  select id into v_id
    from public.promo_redemptions
   where user_id = p_user
     and active
     and not unlimited
     and generation_limit is not null
     and generations_used < generation_limit
     and (expires_at is null or expires_at > now())
   order by redeemed_at asc
   for update
   limit 1;

  if v_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_promo_generations');
  end if;

  update public.promo_redemptions
     set generations_used = generations_used + 1
   where id = v_id
  returning greatest(generation_limit - generations_used, 0) into v_remaining;

  return jsonb_build_object('ok', true, 'remaining', v_remaining);
end;
$$;

create or replace function public.get_promo_access(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'unlimited_active', coalesce(bool_or(
        active and unlimited and (expires_at is null or expires_at > now())), false),
    'limited_remaining', coalesce(sum(
        case when active and not unlimited and generation_limit is not null
                  and (expires_at is null or expires_at > now())
             then greatest(generation_limit - generations_used, 0) else 0 end), 0),
    'active_campaign', (
        select pc.campaign
          from public.promo_redemptions r2
          join public.promo_codes pc on pc.id = r2.promo_code_id
         where r2.user_id = p_user and r2.active
           and (r2.expires_at is null or r2.expires_at > now())
           and (r2.unlimited
                or (r2.generation_limit is not null and r2.generations_used < r2.generation_limit))
         order by r2.redeemed_at desc
         limit 1)
  )
  from public.promo_redemptions
  where user_id = p_user;
$$;

revoke execute on function public.redeem_promo_code(uuid, text)        from anon, authenticated;
revoke execute on function public.consume_promo_generation(uuid)       from anon, authenticated;
revoke execute on function public.get_promo_access(uuid)               from anon, authenticated;
grant  execute on function public.redeem_promo_code(uuid, text)        to service_role;
grant  execute on function public.consume_promo_generation(uuid)       to service_role;
grant  execute on function public.get_promo_access(uuid)               to service_role;


-- ════════════════════════════════════════════════════════════════════════════
-- §4 — generation_intents  (20260630_generation_intent_v1_pr0_schema.sql)
-- ════════════════════════════════════════════════════════════════════════════
-- ONE canonical row per LOGICAL user generation. Carries the idempotence of the
-- BILLING (`hold:<intent_id>` / `commit:` / `release:`), not of the render.
-- `session_id` is always NULL on the Web.

create table if not exists public.generation_intents (
  intent_id          text        primary key,
  user_id            uuid        not null references auth.users(id) on delete cascade,
  session_id         uuid        references public.sessions(id) on delete set null,
  iteration          int,
  status             text        not null
                                 check (status in ('RUNNING', 'SUCCEEDED', 'FAILED', 'FAILED_TERMINAL'))
                                 default 'RUNNING',
  intent             jsonb,
  result_ref         jsonb,
  error              jsonb,
  reclaim_count      int         not null default 0
                                 check (reclaim_count >= 0),
  client_request_id  text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  started_at         timestamptz,
  completed_at       timestamptz
);

create index if not exists generation_intents_user_idx
  on public.generation_intents(user_id);

create index if not exists generation_intents_session_idx
  on public.generation_intents(session_id);

create index if not exists generation_intents_status_idx
  on public.generation_intents(status, started_at)
  where status = 'RUNNING';

alter table public.generation_intents enable row level security;

drop policy if exists "generation_intents: owner read" on public.generation_intents;
create policy "generation_intents: owner read"
  on public.generation_intents
  for select
  using (auth.uid() = user_id);

create or replace function public.generation_intents_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_generation_intents_updated_at on public.generation_intents;
create trigger trg_generation_intents_updated_at
  before update on public.generation_intents
  for each row
  execute function public.generation_intents_set_updated_at();

grant select, insert, update on public.generation_intents to service_role;
grant select                 on public.generation_intents to authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- §5 — Billing PR0 vault  (20260701_billing_engine_pr0_schema.sql)
-- ════════════════════════════════════════════════════════════════════════════

create or replace function public.billing_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- products ───────────────────────────────────────────────────────────────────
create table if not exists public.products (
  id                     uuid        primary key default gen_random_uuid(),
  sku                    text        not null unique,
  type                   text        not null check (type in ('PASS', 'CREDIT_PACK')),
  credits_granted        int         not null check (credits_granted >= 0),
  duration_days          int         check (duration_days is null or duration_days > 0),
  price_usd              numeric(10, 2),
  currency               text        not null default 'USD',
  revenuecat_product_id  text,
  apple_product_id       text,
  google_product_id      text,
  khqr_enabled           boolean     not null default false,
  metadata               jsonb       not null default '{}'::jsonb,
  active                 boolean     not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at before update on public.products
  for each row execute function public.billing_set_updated_at();

alter table public.products enable row level security;
drop policy if exists "products: active read" on public.products;
create policy "products: active read" on public.products
  for select using (active);

-- orders ─────────────────────────────────────────────────────────────────────
create table if not exists public.orders (
  id                uuid        primary key default gen_random_uuid(),
  user_id           uuid        not null references auth.users(id) on delete cascade,
  product_id        uuid        not null references public.products(id),
  status            text        not null
                                check (status in ('PENDING', 'PAID', 'FAILED', 'CANCELLED', 'REFUNDED'))
                                default 'PENDING',
  provider          text        not null check (provider in ('revenuecat', 'khqr')),
  amount            numeric(10, 2),
  currency          text        not null default 'USD',
  idempotency_key   text        unique,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists orders_user_idx on public.orders(user_id);
create index if not exists orders_status_idx on public.orders(status) where status = 'PENDING';

drop trigger if exists trg_orders_updated_at on public.orders;
create trigger trg_orders_updated_at before update on public.orders
  for each row execute function public.billing_set_updated_at();

alter table public.orders enable row level security;
drop policy if exists "orders: owner read" on public.orders;
create policy "orders: owner read" on public.orders
  for select using (auth.uid() = user_id);

-- payments ───────────────────────────────────────────────────────────────────
create table if not exists public.payments (
  id                       uuid        primary key default gen_random_uuid(),
  order_id                 uuid        references public.orders(id) on delete set null,
  provider                 text        not null check (provider in ('revenuecat', 'khqr')),
  provider_transaction_id  text        not null,
  status                   text        not null
                                       check (status in ('SUCCESS', 'FAILED', 'PENDING', 'REFUNDED')),
  amount                   numeric(10, 2),
  currency                 text,
  raw_payload              jsonb,
  received_at              timestamptz not null default now(),
  unique (provider, provider_transaction_id)
);

create index if not exists payments_order_idx on public.payments(order_id);

alter table public.payments enable row level security;
-- No authenticated policy → client read forbidden ; service_role bypasses RLS.

-- passes ─────────────────────────────────────────────────────────────────────
create table if not exists public.passes (
  id               uuid        primary key default gen_random_uuid(),
  user_id          uuid        not null references auth.users(id) on delete cascade,
  product_id       uuid        not null references public.products(id),
  source_order_id  uuid        references public.orders(id) on delete set null,
  starts_at        timestamptz not null,
  ends_at          timestamptz not null,
  status           text        not null
                               check (status in ('ACTIVE', 'EXPIRED', 'CANCELLED'))
                               default 'ACTIVE',
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists passes_user_idx on public.passes(user_id);
create index if not exists passes_active_expiry_idx
  on public.passes(status, ends_at) where status = 'ACTIVE';

drop trigger if exists trg_passes_updated_at on public.passes;
create trigger trg_passes_updated_at before update on public.passes
  for each row execute function public.billing_set_updated_at();

alter table public.passes enable row level security;
drop policy if exists "passes: owner read" on public.passes;
create policy "passes: owner read" on public.passes
  for select using (auth.uid() = user_id);

-- ledger_entries — THE event journal, append-only ────────────────────────────
create table if not exists public.ledger_entries (
  id                bigint      generated always as identity primary key,
  user_id           uuid        not null references auth.users(id) on delete cascade,
  entry_type        text        not null
                                check (entry_type in
                                  ('GRANT', 'HOLD', 'COMMIT', 'RELEASE',
                                   'REFUND', 'ADJUSTMENT', 'EXPIRE', 'TRIAL')),
  available_delta   int         not null,
  pass_id           uuid        references public.passes(id) on delete set null,
  reference_type    text        check (reference_type in ('ORDER', 'GENERATION_INTENT', 'ADMIN', 'PROMO')),
  reference_id      text,
  idempotency_key   text        not null unique,
  metadata          jsonb       not null default '{}'::jsonb,
  created_at        timestamptz not null default now()
);

create index if not exists ledger_user_idx on public.ledger_entries(user_id);
create index if not exists ledger_user_created_idx on public.ledger_entries(user_id, id);
create index if not exists ledger_reference_idx on public.ledger_entries(reference_type, reference_id);

alter table public.ledger_entries enable row level security;
drop policy if exists "ledger: owner read" on public.ledger_entries;
create policy "ledger: owner read" on public.ledger_entries
  for select using (auth.uid() = user_id);

create or replace function public.ledger_entries_block_mutation()
returns trigger language plpgsql as $$
begin
  raise exception 'ledger_entries is append-only — % is not allowed', tg_op;
end;
$$;

drop trigger if exists trg_ledger_no_row_mutation on public.ledger_entries;
create trigger trg_ledger_no_row_mutation
  before update or delete on public.ledger_entries
  for each row execute function public.ledger_entries_block_mutation();

drop trigger if exists trg_ledger_no_truncate on public.ledger_entries;
create trigger trg_ledger_no_truncate
  before truncate on public.ledger_entries
  for each statement execute function public.ledger_entries_block_mutation();

-- wallets — recomputable projection of the ledger ────────────────────────────
create table if not exists public.wallets (
  user_id           uuid        primary key references auth.users(id) on delete cascade,
  available_credits int         not null default 0,
  held_credits      int         not null default 0,
  active_pass_id    uuid        references public.passes(id) on delete set null,
  pass_expires_at   timestamptz,
  ledger_version    bigint      not null default 0,
  updated_at        timestamptz not null default now()
);

drop trigger if exists trg_wallets_updated_at on public.wallets;
create trigger trg_wallets_updated_at before update on public.wallets
  for each row execute function public.billing_set_updated_at();

alter table public.wallets enable row level security;
drop policy if exists "wallets: owner read" on public.wallets;
create policy "wallets: owner read" on public.wallets
  for select using (auth.uid() = user_id);

-- Table-level grants (RLS filters rows; it does not grant the privilege) ─────
grant select, insert, update on public.products       to service_role;
grant select, insert, update on public.orders         to service_role;
grant select, insert, update on public.payments       to service_role;
grant select, insert, update on public.passes         to service_role;
grant select, insert         on public.ledger_entries to service_role;
grant select, insert, update on public.wallets        to service_role;

-- Defense in depth — the append-only guarantee is the TRIGGER above; this
-- removes the mutation privileges Supabase adds by default.
revoke update, delete, truncate on public.ledger_entries from service_role;

grant select on public.products       to authenticated;
grant select on public.orders         to authenticated;
grant select on public.passes         to authenticated;
grant select on public.ledger_entries to authenticated;
grant select on public.wallets        to authenticated;
-- payments : NO authenticated grant (sensitive).


-- ════════════════════════════════════════════════════════════════════════════
-- §6 — 1 order → at most 1 Pass  (20260708)
-- ════════════════════════════════════════════════════════════════════════════
create unique index if not exists passes_source_order_uidx
  on public.passes(source_order_id);


-- ════════════════════════════════════════════════════════════════════════════
-- §7 — billing_reproject_wallet  (FINAL: 20260710_billing_p0_additive_projection)
-- ════════════════════════════════════════════════════════════════════════════
-- available_credits = pass_bucket + greatest(free_bucket, 0). Mirror of the
-- Python gate (_free_bucket_available + _pass_bucket_available). ONE truth.

create or replace function public.billing_reproject_wallet(p_user_id uuid)
returns void
language plpgsql
as $$
declare
  v_active_pass    uuid;
  v_active_expires timestamptz;
  v_pass           int := 0;
  v_free           int := 0;
  v_available      int;
  v_held           int;
  v_version        bigint;
begin
  select id, ends_at
    into v_active_pass, v_active_expires
    from public.passes
   where user_id = p_user_id
     and status = 'ACTIVE'
     and now() between starts_at and ends_at
   order by ends_at desc
   limit 1;

  select greatest(coalesce(sum(available_delta), 0), 0)
    into v_free
    from public.ledger_entries
   where user_id = p_user_id
     and pass_id is null;

  if v_active_pass is not null then
    select coalesce(sum(available_delta), 0)
      into v_pass
      from public.ledger_entries
     where user_id = p_user_id
       and pass_id = v_active_pass;
  end if;

  v_available := v_pass + v_free;

  select count(*) filter (where entry_type = 'HOLD')
       - count(*) filter (where entry_type in ('RELEASE', 'COMMIT'))
    into v_held
    from public.ledger_entries
   where user_id = p_user_id;

  select coalesce(max(id), 0)
    into v_version
    from public.ledger_entries
   where user_id = p_user_id;

  insert into public.wallets
    (user_id, available_credits, held_credits, active_pass_id, pass_expires_at, ledger_version, updated_at)
  values
    (p_user_id, v_available, v_held, v_active_pass, v_active_expires, v_version, now())
  on conflict (user_id) do update
    set available_credits = excluded.available_credits,
        held_credits      = excluded.held_credits,
        active_pass_id    = excluded.active_pass_id,
        pass_expires_at   = excluded.pass_expires_at,
        ledger_version    = excluded.ledger_version,
        updated_at        = now();
end;
$$;

grant execute on function public.billing_reproject_wallet(uuid) to service_role;


-- ════════════════════════════════════════════════════════════════════════════
-- §8 — billing_grant_purchase  (FINAL: 20260709_billing_pr2b, projection-aware)
-- ════════════════════════════════════════════════════════════════════════════
-- The ACQUISITION path. `p_provider` is already generic — an ABA/KHQR adapter
-- will call this same function with provider='khqr' and tran_id as the cycle
-- transaction id. Nothing here needs to change for that.

create or replace function public.billing_grant_purchase(
  p_user_id                 uuid,
  p_provider                text,
  p_provider_transaction_id text,
  p_product_id              uuid,
  p_credits                 int,
  p_duration_days           int,
  p_amount                  numeric,
  p_currency                text,
  p_ends_at                 timestamptz,
  p_raw_payload             jsonb
) returns jsonb
language plpgsql
as $$
declare
  v_order_id     uuid;
  v_pass_id      uuid;
  v_payment_new  boolean := false;
  v_grant_new    boolean := false;
  v_order_key    text := 'order:' || p_provider || ':' || p_provider_transaction_id;
  v_grant_key    text;
  v_ends_at      timestamptz;
  v_available    int;
begin
  v_ends_at := coalesce(p_ends_at, now() + make_interval(days => p_duration_days));

  insert into public.orders
    (user_id, product_id, status, provider, amount, currency, idempotency_key)
  values
    (p_user_id, p_product_id, 'PAID', p_provider, p_amount, coalesce(p_currency, 'USD'), v_order_key)
  on conflict (idempotency_key) do update
    set status = 'PAID', updated_at = now()
  returning id into v_order_id;

  v_grant_key := 'grant:order:' || v_order_id::text;

  insert into public.payments
    (order_id, provider, provider_transaction_id, status, amount, currency, raw_payload)
  values
    (v_order_id, p_provider, p_provider_transaction_id, 'SUCCESS', p_amount, p_currency, p_raw_payload)
  on conflict (provider, provider_transaction_id) do nothing;
  v_payment_new := found;

  insert into public.passes
    (user_id, product_id, source_order_id, starts_at, ends_at, status)
  values
    (p_user_id, p_product_id, v_order_id, now(), v_ends_at, 'ACTIVE')
  on conflict (source_order_id) do nothing;
  select id into v_pass_id from public.passes where source_order_id = v_order_id;

  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values
    (p_user_id, 'GRANT', p_credits, v_pass_id, 'ORDER', v_order_id::text, v_grant_key)
  on conflict (idempotency_key) do nothing;
  v_grant_new := found;

  perform public.billing_reproject_wallet(p_user_id);
  select available_credits into v_available
    from public.wallets where user_id = p_user_id;

  return jsonb_build_object(
    'ok', true,
    'status', case when v_grant_new then 'granted' else 'already_processed' end,
    'order_id', v_order_id,
    'pass_id', v_pass_id,
    'payment_new', v_payment_new,
    'credited', v_grant_new,
    'credits', case when v_grant_new then p_credits else 0 end,
    'available_credits', v_available
  );
end;
$$;

grant execute on function public.billing_grant_purchase(
  uuid, text, text, uuid, int, int, numeric, text, timestamptz, jsonb
) to service_role;


-- ════════════════════════════════════════════════════════════════════════════
-- §9 — billing_try_hold  (FINAL: 20260717 §1 — 4-arg, p_trial_credits)
-- ════════════════════════════════════════════════════════════════════════════
-- THE right to generate. Atomic gate+HOLD serialised per user by
-- pg_advisory_xact_lock: N concurrent calls on a balance of B grant min(N, B).
-- `p_trial_credits` DEFAULT 3 keeps a 3-arg caller byte-identical; the Web
-- passes 1 (D1: one free WOW per anonymous Web guest) via
-- billing.effective_trial_credits() under ACCOUNT_SYSTEM_ENABLED=true.

drop function if exists public.billing_try_hold(uuid, text, text);
create or replace function public.billing_try_hold(
  p_user_id       uuid,
  p_intent_id     text,
  p_tier          text,
  p_trial_credits int default 3
) returns jsonb
language plpgsql
as $$
declare
  v_hold_key      text := 'hold:' || p_intent_id;
  v_trial_key     text := 'trial:' || p_user_id::text;
  v_active_pass   uuid;
  v_pass          int := 0;
  v_free_raw      int := 0;
  v_free          int := 0;
  v_trial_granted boolean := false;
  v_target_pass   uuid;
  v_bucket        text;
  v_total_before  int;
  v_total_after   int;
begin
  if exists (select 1 from public.ledger_entries where idempotency_key = v_hold_key) then
    return jsonb_build_object('granted', true, 'reason', '', 'idempotent', true, 'bucket', 'existing');
  end if;

  if p_tier in ('admin', 'promo_unlimited', 'promo_limited') then
    return jsonb_build_object('granted', true, 'reason', 'bypass', 'bucket', 'none');
  end if;

  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  select id into v_active_pass
    from public.passes
   where user_id = p_user_id and status = 'ACTIVE'
     and now() between starts_at and ends_at
   order by ends_at desc
   limit 1;

  if v_active_pass is not null then
    select coalesce(sum(available_delta), 0) into v_pass
      from public.ledger_entries
     where user_id = p_user_id and pass_id = v_active_pass;
  end if;

  select coalesce(sum(available_delta), 0), coalesce(bool_or(entry_type = 'TRIAL'), false)
    into v_free_raw, v_trial_granted
    from public.ledger_entries
   where user_id = p_user_id and pass_id is null;
  v_free := greatest(v_free_raw, 0);
  v_total_before := v_pass + v_free;

  if v_pass >= 1 then
    v_bucket := 'pass'; v_target_pass := v_active_pass;
  elsif v_free >= 1 then
    v_bucket := 'free'; v_target_pass := null;
  elsif p_tier = 'free' and v_active_pass is null and not v_trial_granted then
    insert into public.ledger_entries
      (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values
      (p_user_id, 'TRIAL', p_trial_credits, null, 'PROMO', 'trial', v_trial_key)
    on conflict (idempotency_key) do nothing;
    v_bucket := 'free'; v_target_pass := null;
  else
    return jsonb_build_object(
      'granted', false,
      'reason', case
        when v_active_pass is not null then 'pass_exhausted'
        when p_tier <> 'free'         then 'no_active_pass'
        else 'insufficient_credits' end,
      'total_before', v_total_before, 'total_after', v_total_before);
  end if;

  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values
    (p_user_id, 'HOLD', -1, v_target_pass, 'GENERATION_INTENT', p_intent_id, v_hold_key)
  on conflict (idempotency_key) do nothing;

  perform public.billing_reproject_wallet(p_user_id);
  select available_credits into v_total_after from public.wallets where user_id = p_user_id;

  return jsonb_build_object(
    'granted', true, 'reason', '', 'bucket', v_bucket, 'pass_id', v_target_pass,
    'total_before', v_total_before, 'total_after', coalesce(v_total_after, v_total_before - 1));
end;
$$;

grant execute on function public.billing_try_hold(uuid, text, text, int) to service_role;


-- ════════════════════════════════════════════════════════════════════════════
-- §10 — Catalogue seed + store mapping + weekly = 30 spaces
--        (20260701 §seed · 20260708 ticket0 · 20260709 weekly_pass_30_spaces)
-- ════════════════════════════════════════════════════════════════════════════
insert into public.products (sku, type, credits_granted, duration_days, price_usd, khqr_enabled) values
  ('weekly_pass', 'PASS',        60,  7,   7.99,  true),
  ('annual_pass', 'PASS',        300, 365, 79.99, true),
  ('pack_10',     'CREDIT_PACK', 10,  null, 1.99, true),
  ('pack_25',     'CREDIT_PACK', 25,  null, 3.99, true),
  ('pack_50',     'CREDIT_PACK', 50,  null, 6.99, true),
  ('pack_100',    'CREDIT_PACK', 100, null, 11.99, true)
on conflict (sku) do nothing;

update public.products
   set apple_product_id      = 'com.aydenstudio.app.weekly',
       revenuecat_product_id = 'com.aydenstudio.app.weekly'
 where sku = 'weekly_pass'
   and (apple_product_id      is distinct from 'com.aydenstudio.app.weekly'
     or revenuecat_product_id is distinct from 'com.aydenstudio.app.weekly');

update public.products
   set apple_product_id      = 'com.aydenstudio.app.annual',
       revenuecat_product_id = 'com.aydenstudio.app.annual'
 where sku = 'annual_pass'
   and (apple_product_id      is distinct from 'com.aydenstudio.app.annual'
     or revenuecat_product_id is distinct from 'com.aydenstudio.app.annual');

-- Product decision 2026-07-09 : weekly = 30 spaces (annual stays 300).
update public.products
   set credits_granted = 30
 where sku = 'weekly_pass'
   and credits_granted is distinct from 30;


-- ════════════════════════════════════════════════════════════════════════════
-- §11 — LEAST PRIVILEGE  (20260707_grants_hardening.sql, scoped to what exists)
-- ════════════════════════════════════════════════════════════════════════════
-- MEASURED, not assumed (pwa_staging_billing_contract_test.py, first run):
-- Supabase's default privileges hand `anon` and `authenticated` TRUNCATE,
-- REFERENCES and TRIGGER on every new table in `public`, and PostgreSQL hands
-- PUBLIC — i.e. everyone — EXECUTE on every new function. Neither is filtered
-- by RLS. Two concrete consequences, both reachable from a browser token:
--
--   * TRUNCATE on `wallets` / `passes` / `promo_codes` would let any anonymous
--     visitor wipe the entitlement state. RLS does not apply to TRUNCATE.
--   * `redeem_promo_code` and `consume_promo_generation` are SECURITY DEFINER,
--     so PUBLIC's default EXECUTE means a browser could redeem promo codes and
--     grant itself unlimited generations, bypassing the server entirely.
--
-- The two `revoke ... from anon, authenticated` lines the canonical promo SQL
-- already carries do NOT close the second one: revoking from a role does not
-- remove PUBLIC's grant. Migration 20260707 calls this out in as many words
-- ("⚠️ FERME LE P0") and is the source of this block; it is not applied here
-- verbatim because it also revokes on `usage_log`, `generation_jobs` and five
-- views that this project deliberately does not have (it would abort).
--
-- Shape follows 20260707's rule: NEVER `revoke all` on service_role — targeted
-- revokes, then an explicit re-grant of what is needed, so the end state is
-- deterministic and independent of how the project was provisioned.

-- 11.1 — anon + authenticated: nothing but the canonical owner-read SELECT.
revoke all on table
  public.sessions, public.user_roles, public.promo_codes, public.promo_redemptions,
  public.generation_intents, public.products, public.orders, public.payments,
  public.passes, public.ledger_entries, public.wallets
  from anon, authenticated;

grant select on public.user_roles         to authenticated;
grant select on public.generation_intents to authenticated;
grant select on public.products           to authenticated;
grant select on public.orders             to authenticated;
grant select on public.passes             to authenticated;
grant select on public.ledger_entries     to authenticated;
grant select on public.wallets            to authenticated;
-- payments / promo_codes / promo_redemptions / sessions: NOTHING (canonical).
-- anon: NOTHING at all — a PWA visitor is always an authenticated (anonymous)
-- Supabase user, never the `anon` role.

-- 11.2 — service_role: re-assert exactly what the backend needs, and strip the
--        rest. `revoke all` is forbidden here (20260707 rule).
revoke delete, truncate, references, trigger, maintain
  on table public.generation_intents, public.wallets, public.sessions
  from service_role;
revoke update, delete, truncate, references, trigger, maintain
  on table public.ledger_entries
  from service_role;

grant select, insert, update on public.generation_intents to service_role;
grant select, insert, update on public.wallets            to service_role;
grant select, insert         on public.ledger_entries     to service_role;

-- 11.3 — RPCs: EXECUTE for service_role ONLY. `from public` is the line that
--        actually closes it; `anon, authenticated` alone never did.
grant execute on function
  public.get_promo_access(uuid),
  public.consume_promo_generation(uuid),
  public.redeem_promo_code(uuid, text),
  public.billing_reproject_wallet(uuid),
  public.billing_try_hold(uuid, text, text, int),
  public.billing_grant_purchase(uuid, text, text, uuid, int, int, numeric, text, timestamptz, jsonb)
  to service_role;

revoke execute on function
  public.get_promo_access(uuid),
  public.consume_promo_generation(uuid),
  public.redeem_promo_code(uuid, text),
  public.billing_reproject_wallet(uuid),
  public.billing_try_hold(uuid, text, text, int),
  public.billing_grant_purchase(uuid, text, text, uuid, int, int, numeric, text, timestamptz, jsonb)
  from public, anon, authenticated;

-- Trigger functions are deliberately left alone: PostgreSQL checks EXECUTE at
-- CREATE TRIGGER time, not at fire time, and calling one directly raises
-- ("can only be called as a trigger"). Revoking would risk the triggers for no
-- gain.

-- 11.4 — no CREATE in `public` for a browser role (hardens the DEFINER
--        functions' `set search_path = public`).
revoke create on schema public from anon, authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- REPORT — fails the whole transaction if anything is missing
-- ════════════════════════════════════════════════════════════════════════════
do $report$
declare
  v_tables   int;
  v_funcs    int;
  v_weekly   int;
  v_annual   int;
  v_hold_arg int;
  v_missing  text;
begin
  select count(*) into v_tables
    from information_schema.tables
   where table_schema = 'public'
     and table_name in ('sessions', 'user_roles', 'promo_codes', 'promo_redemptions',
                        'generation_intents', 'products', 'orders', 'payments',
                        'passes', 'ledger_entries', 'wallets');

  select count(*) into v_funcs
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('get_promo_access', 'redeem_promo_code', 'consume_promo_generation',
                       'billing_reproject_wallet', 'billing_grant_purchase', 'billing_try_hold',
                       'billing_set_updated_at', 'generation_intents_set_updated_at',
                       'ledger_entries_block_mutation');

  -- billing_try_hold MUST be the 4-arg version (the 3-arg one hard-codes TRIAL=3).
  select count(*) into v_hold_arg
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'billing_try_hold' and p.pronargs = 4;

  select credits_granted into v_weekly from public.products where sku = 'weekly_pass';
  select credits_granted into v_annual from public.products where sku = 'annual_pass';

  raise notice '0006 RESULT: tables=%/11 functions=%/9 try_hold_4arg=% weekly=% annual=%',
    v_tables, v_funcs, v_hold_arg, v_weekly, v_annual;

  if v_tables <> 11 then
    select string_agg(t, ', ') into v_missing
      from unnest(array['sessions','user_roles','promo_codes','promo_redemptions',
                        'generation_intents','products','orders','payments',
                        'passes','ledger_entries','wallets']) t
     where not exists (select 1 from information_schema.tables
                        where table_schema = 'public' and table_name = t);
    raise exception '0006: missing tables (%) — refusing to commit.', v_missing;
  end if;
  if v_funcs <> 9 then
    raise exception '0006: expected 9 functions, found % — refusing to commit.', v_funcs;
  end if;
  if v_hold_arg <> 1 then
    raise exception '0006: billing_try_hold is not the 4-arg (p_trial_credits) version — refusing to commit.';
  end if;
  if v_weekly <> 30 or v_annual <> 300 then
    raise exception '0006: catalogue wrong (weekly=% annual=%) — refusing to commit.', v_weekly, v_annual;
  end if;
  if exists (select 1 from information_schema.tables
              where table_schema = 'public'
                and table_name in ('usage_log', 'generation_jobs')) then
    raise exception '0006: an EXCLUDED legacy object was created (usage_log / generation_jobs) — refusing to commit.';
  end if;

  -- §11 — the least-privilege end state, asserted rather than hoped for.
  if exists (
    select 1 from information_schema.role_table_grants
     where table_schema = 'public' and grantee = 'anon'
       and table_name = any(array['sessions','user_roles','promo_codes','promo_redemptions',
                                  'generation_intents','products','orders','payments',
                                  'passes','ledger_entries','wallets'])
  ) then
    raise exception '0006: anon still holds a grant in public — refusing to commit.';
  end if;
  if exists (
    select 1 from information_schema.role_table_grants
     where table_schema = 'public' and grantee = 'authenticated'
       and privilege_type <> 'SELECT'
  ) then
    raise exception '0006: authenticated holds a non-SELECT grant in public — refusing to commit.';
  end if;
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('get_promo_access','consume_promo_generation','redeem_promo_code',
                         'billing_reproject_wallet','billing_try_hold','billing_grant_purchase')
       and (has_function_privilege('anon', p.oid, 'EXECUTE')
         or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  ) then
    raise exception '0006: a business RPC is still executable by a browser role — refusing to commit.';
  end if;
end
$report$;

commit;

-- End of 0006. Additive and replayable. No production object considered, no
-- second billing model created, no canonical semantics altered.
