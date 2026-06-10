-- ============================================================================
-- AYDEN Studio — Sprint 1B — Promo / Influencer / Admin codes
-- Apply ONCE in the Supabase SQL editor (Dashboard → SQL → New query → Run).
-- Idempotent: safe to re-run (uses IF NOT EXISTS / CREATE OR REPLACE).
--
-- Security model:
--   • Tables are RLS-enabled with NO anon/authenticated policies → clients can
--     NEVER read/write them. The backend uses the SERVICE ROLE key (bypasses
--     RLS) and is the only authority. Frontend always goes through endpoints.
--   • redeem / consume are SECURITY DEFINER plpgsql functions = the ONLY
--     race-safe write path (row locks + atomic counters). EXECUTE is granted
--     to service_role only and revoked from anon/authenticated.
-- ============================================================================

-- ── Table: promo_codes ──────────────────────────────────────────────────────
create table if not exists public.promo_codes (
  id              uuid primary key default gen_random_uuid(),
  code            text not null,                       -- stored UPPER-normalised
  type            text not null check (type in ('limited_generations','unlimited')),
  generation_limit int,                                -- >0 for limited; null for unlimited
  max_redemptions int,                                 -- null = unlimited redemptions
  redeemed_count  int  not null default 0,
  expires_at      timestamptz,                         -- null = never; deadline to redeem + access window
  active          boolean not null default true,
  campaign        text,
  note            text,
  created_by      uuid,                                -- admin user_id
  created_at      timestamptz not null default now(),
  constraint chk_promo_limited_has_limit check (
        (type = 'limited_generations' and generation_limit is not null and generation_limit > 0)
     or (type = 'unlimited'           and generation_limit is null)
  ),
  constraint chk_promo_redeemed_nonneg check (redeemed_count >= 0),
  constraint chk_promo_maxred check (max_redemptions is null or max_redemptions > 0)
);

-- case-insensitive uniqueness on the code (we also store it upper-normalised)
create unique index if not exists uq_promo_codes_code_upper on public.promo_codes (upper(code));
create index if not exists idx_promo_codes_active on public.promo_codes (active);

-- ── Table: promo_redemptions ────────────────────────────────────────────────
-- One row per (code, user). SNAPSHOTS the code terms at redeem time so later
-- edits to the code never retro-change a granted redemption.
create table if not exists public.promo_redemptions (
  id               uuid primary key default gen_random_uuid(),
  promo_code_id    uuid not null references public.promo_codes(id) on delete cascade,
  user_id          uuid not null,
  unlimited        boolean not null default false,
  generation_limit int,                                -- snapshot (null for unlimited)
  generations_used int not null default 0,
  expires_at       timestamptz,                        -- snapshot of code.expires_at
  active           boolean not null default true,
  redeemed_at      timestamptz not null default now(),
  constraint uq_one_redemption_per_user unique (promo_code_id, user_id),
  constraint chk_redemption_used_nonneg check (generations_used >= 0)
);
create index if not exists idx_promo_redemptions_user on public.promo_redemptions (user_id, active);

-- ── RLS: lock both tables to the service role only ──────────────────────────
alter table public.promo_codes       enable row level security;
alter table public.promo_redemptions enable row level security;
-- (intentionally NO policies → anon/authenticated get zero access)

-- Table privileges: the backend service_role bypasses RLS but still needs
-- table GRANTs (new tables don't inherit them automatically). The admin CRUD
-- uses these directly; the redeem/consume RPCs are SECURITY DEFINER so they
-- work regardless, but granting keeps everything consistent. anon/authenticated
-- get NOTHING (RLS + no grant).
grant select, insert, update, delete on public.promo_codes       to service_role;
grant select, insert, update, delete on public.promo_redemptions to service_role;

-- ============================================================================
-- FUNCTION: redeem_promo_code(p_user, p_code) → jsonb
--   Atomic. Locks the code row (FOR UPDATE) so concurrent redemptions of the
--   same code cannot oversell max_redemptions. The UNIQUE(promo_code_id,user_id)
--   constraint + exception handler make "once per user" race-proof.
--   Returns {ok:true, ...redemption state} OR {ok:false, error:'<code>'}.
--   error ∈ invalid_code | inactive_code | expired_code | already_redeemed |
--           max_redemptions_reached
-- ============================================================================
create or replace function public.redeem_promo_code(p_user uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code public.promo_codes%rowtype;
  v_red  public.promo_redemptions%rowtype;
  v_norm text := upper(trim(p_code));
begin
  select * into v_code from public.promo_codes
   where upper(code) = v_norm
   for update;                                          -- serialise same-code redemptions

  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_code');
  end if;
  if not v_code.active then
    return jsonb_build_object('ok', false, 'error', 'inactive_code');
  end if;
  if v_code.expires_at is not null and v_code.expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'expired_code');
  end if;

  if exists (select 1 from public.promo_redemptions
              where promo_code_id = v_code.id and user_id = p_user) then
    return jsonb_build_object('ok', false, 'error', 'already_redeemed');
  end if;

  if v_code.max_redemptions is not null
     and v_code.redeemed_count >= v_code.max_redemptions then
    return jsonb_build_object('ok', false, 'error', 'max_redemptions_reached');
  end if;

  insert into public.promo_redemptions
        (promo_code_id, user_id, unlimited, generation_limit, expires_at, active)
  values (v_code.id, p_user,
          (v_code.type = 'unlimited'),
          case when v_code.type = 'limited_generations' then v_code.generation_limit else null end,
          v_code.expires_at, true)
  returning * into v_red;

  update public.promo_codes
     set redeemed_count = redeemed_count + 1
   where id = v_code.id;

  return jsonb_build_object(
    'ok', true,
    'type', v_code.type,
    'unlimited', v_red.unlimited,
    'generation_limit', v_red.generation_limit,
    'generations_used', v_red.generations_used,
    'expires_at', v_red.expires_at,
    'campaign', v_code.campaign
  );
exception
  when unique_violation then                             -- concurrent double-redeem
    return jsonb_build_object('ok', false, 'error', 'already_redeemed');
end;
$$;

-- ============================================================================
-- FUNCTION: consume_promo_generation(p_user) → jsonb
--   Atomic single-decrement on the user's active, non-expired, LIMITED
--   redemption with remaining generations (oldest first). Row-locked → no
--   double-consume. Called by the backend ONLY on a successful generation
--   when the access resolver picked tier='promo_limited'.
--   Returns {ok:true, remaining:int} OR {ok:false, error:'no_promo_generations'}.
-- ============================================================================
create or replace function public.consume_promo_generation(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_red public.promo_redemptions%rowtype;
begin
  select * into v_red from public.promo_redemptions
   where user_id = p_user
     and active = true
     and unlimited = false
     and generation_limit is not null
     and generations_used < generation_limit
     and (expires_at is null or expires_at > now())
   order by redeemed_at asc
   for update
   limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'error', 'no_promo_generations');
  end if;

  update public.promo_redemptions
     set generations_used = generations_used + 1
   where id = v_red.id;

  return jsonb_build_object('ok', true,
                            'remaining', v_red.generation_limit - (v_red.generations_used + 1));
end;
$$;

-- ============================================================================
-- FUNCTION: get_promo_access(p_user) → jsonb   (READ-ONLY, time-aware)
--   Single source of truth for the access resolver + /me/status.
--   Returns {unlimited_active:bool, limited_remaining:int, active_campaign:text}.
-- ============================================================================
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

-- ── Grants: backend (service_role) only ─────────────────────────────────────
revoke execute on function public.redeem_promo_code(uuid, text)        from anon, authenticated;
revoke execute on function public.consume_promo_generation(uuid)       from anon, authenticated;
revoke execute on function public.get_promo_access(uuid)               from anon, authenticated;
grant  execute on function public.redeem_promo_code(uuid, text)        to service_role;
grant  execute on function public.consume_promo_generation(uuid)       to service_role;
grant  execute on function public.get_promo_access(uuid)               to service_role;

-- ============================================================================
-- DONE. Tables: promo_codes, promo_redemptions. Functions: redeem_promo_code,
-- consume_promo_generation, get_promo_access. All backend-authoritative.
-- ============================================================================
