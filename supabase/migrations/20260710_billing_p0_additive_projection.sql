-- ═══════════════════════════════════════════════════════════════════════════
-- P0 Billing Integrity (2026-07-10) — projection wallet ADDITIVE (free + pass)
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ═══════════════════════════════════════════════════════════════════════════
--
-- BUG corrigé (audit DB réel user 1ba1c0f9) : la projection RC-PR2b était un XOR
-- (pass actif → bucket pass SEUL ; sinon free planché 0). Effet de bord : un free
-- résiduel POSITIF était masqué dès qu'un pass était actif → total ≠ free + pass.
-- Et le gate Python (reserve_decision, chemin free) sommait TOUT le ledger sans
-- filtrer pass_id → les GRANTs de passes EXPIRÉS (+60, +30) devenaient des crédits
-- FANTÔMES (gate=93 vs wallet=3). Décision produit figée (2026-07-10) : total ADDITIF.
--
-- RÈGLE MÉTIER P0 :
--   available_credits = pass_bucket + greatest(free_bucket, 0)
--     • pass_bucket = Σ available_delta du PASS ACTIF (pass_id = active), 0 si aucun.
--     • free_bucket = Σ available_delta des entrées pass_id IS NULL, PLANCHÉ à 0 AVANT
--       l'addition (une dette free/conso pré-achat n'entame JAMAIS le pass → pas de
--       retour du bug 60→29). Un pass EXPIRÉ ne compte pas (pas dans les 2 buckets).
--   → miroir EXACT du gate Python (billing._free_bucket_available + _pass_bucket_available).
--     SOURCE DE VÉRITÉ UNIQUE : profil, paywall, /generate, /refine lisent la même figure.
--
-- Le RPC d'achat billing_grant_purchase délègue déjà à cette fonction (étape 5,
-- migration 20260709_pr2b) → il hérite automatiquement de la règle additive.
--
-- Rollback : ré-appliquer 20260709_billing_pr2b_wallet_pass_projection.sql.
-- ═══════════════════════════════════════════════════════════════════════════


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
  -- Pass actif courant : ACTIVE, couvre now(), ends_at le plus lointain.
  select id, ends_at
    into v_active_pass, v_active_expires
    from public.passes
   where user_id = p_user_id
     and status = 'ACTIVE'
     and now() between starts_at and ends_at
   order by ends_at desc
   limit 1;

  -- Bucket free/trial/coupon (pass_id IS NULL), PLANCHÉ à 0 (jamais une dette).
  select greatest(coalesce(sum(available_delta), 0), 0)
    into v_free
    from public.ledger_entries
   where user_id = p_user_id
     and pass_id is null;

  -- Bucket du PASS ACTIF uniquement (un pass EXPIRÉ n'a pas d'id ici → 0).
  if v_active_pass is not null then
    select coalesce(sum(available_delta), 0)
      into v_pass
      from public.ledger_entries
     where user_id = p_user_id
       and pass_id = v_active_pass;
  end if;

  -- P0 ADDITIF : total = bucket pass + bucket free planché.
  v_available := v_pass + v_free;

  -- held (global, tous buckets) : informatif.
  select count(*) filter (where entry_type = 'HOLD')
       - count(*) filter (where entry_type in ('RELEASE', 'COMMIT'))
    into v_held
    from public.ledger_entries
   where user_id = p_user_id;

  -- Watermark = dernier id ledger appliqué (global).
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


-- ── Backfill : re-projeter TOUS les wallets avec la règle additive ────────────
-- Idempotent (recompute depuis le ledger). Snapshot des ids AVANT la boucle
-- (la fonction upserte wallets pendant l'itération).
do $$
declare
  v_uids uuid[];
  v_u    uuid;
begin
  select array_agg(user_id) into v_uids from public.wallets;
  if v_uids is not null then
    foreach v_u in array v_uids loop
      perform public.billing_reproject_wallet(v_u);
    end loop;
  end if;
end $$;


-- ── Sanity-check (après application) ─────────────────────────────────────────
--   select proname from pg_proc where proname = 'billing_reproject_wallet'; -- 1
--   -- User 1ba1c0f9 (2 passes EXPIRED, free bucket +3) doit rester 3 (pas 93) :
--   select available_credits, active_pass_id
--     from public.wallets where user_id = '1ba1c0f9-2385-47a8-9bd8-b0a4e1082d9d';
--   -- Attendu : available_credits = 3 (free planché), active_pass_id = NULL.
