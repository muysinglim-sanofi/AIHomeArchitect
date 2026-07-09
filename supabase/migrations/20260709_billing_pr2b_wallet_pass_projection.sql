-- ═══════════════════════════════════════════════════════════════════════════
-- RC-PR2b · Projection wallet PASS-AWARE (bucket du pass actif / free floor 0)
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ═══════════════════════════════════════════════════════════════════════════
--
-- BUG (révélé par le 1er achat réel, user 1ba1c0f9) : wallet.available_credits
-- = 29 au lieu de 60. Cause : la projection somme TOUT le ledger du user, donc
-- elle mélange le bucket free/trial pré-achat (34 gens free-tier + TRIAL, tous
-- pass_id IS NULL, Σ = −31) avec le GRANT du pass acheté (+60, pass_id du pass).
-- −31 + 60 = 29. Métier faux : un pass acheté doit démarrer à 60 ; les conso
-- free/trial d'AVANT l'achat ne doivent jamais réduire le pass.
--
-- RÈGLE MÉTIER (décisions validées 2026-07-09) :
--   • Si PASS ACTIF  → available = Σ des mouvements du PASS ACTIF uniquement
--                      (pass_id = active_pass_id). Le bucket free n'entame pas le pass.
--   • Sinon (no pass)→ available = Σ du bucket free/trial (pass_id IS NULL),
--                      PLANCHER à 0 (le free/trial/coupon n'est JAMAIS une dette).
--   • Le schéma a déjà ledger_entries.pass_id — on l'exploite, rien à ajouter au ledger.
--
-- SOURCE DE VÉRITÉ UNIQUE : `billing_reproject_wallet(user_id)` porte la règle.
-- Appelée par le RPC d'achat (billing_grant_purchase) ET par le chemin conso
-- (billing._reproject_wallet Python → rpc). Plus de double projection divergente.
--
-- HORS-SCOPE RC-PR3 : aucun enforcement. reserve_decision bypasse encore les
-- premium ; le pass n'est pas débité (les conso restent pass_id IS NULL tant que
-- RC-PR3 ne tague pas les HOLD au pass actif). La projection est juste PRÊTE.
--
-- Rollback :
--   drop function if exists public.billing_reproject_wallet(uuid);
--   -- (billing_grant_purchase : re-appliquer 20260708_billing_pr2_grant_purchase_rpc.sql)
-- ═══════════════════════════════════════════════════════════════════════════


-- ── 1) La règle de projection, centralisée ───────────────────────────────────
create or replace function public.billing_reproject_wallet(p_user_id uuid)
returns void
language plpgsql
as $$
declare
  v_active_pass    uuid;
  v_active_expires timestamptz;
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

  if v_active_pass is not null then
    -- Bucket du PASS ACTIF uniquement (les entrées pass_id IS NULL — free/trial
    -- pré-achat — n'entament JAMAIS le pass acheté).
    select coalesce(sum(available_delta), 0),
           count(*) filter (where entry_type = 'HOLD')
             - count(*) filter (where entry_type in ('RELEASE', 'COMMIT'))
      into v_available, v_held
      from public.ledger_entries
     where user_id = p_user_id
       and pass_id = v_active_pass;
  else
    -- Aucun pass actif → bucket free/trial/coupon (pass_id IS NULL), PLANCHER 0.
    select coalesce(sum(available_delta), 0),
           count(*) filter (where entry_type = 'HOLD')
             - count(*) filter (where entry_type in ('RELEASE', 'COMMIT'))
      into v_available, v_held
      from public.ledger_entries
     where user_id = p_user_id
       and pass_id is null;
    v_available := greatest(v_available, 0);   -- le free/trial n'est pas une dette
  end if;

  -- Watermark = dernier id ledger appliqué (global, tous buckets confondus).
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


-- ── 2) RPC d'achat recâblé sur la projection centralisée ─────────────────────
-- Identique à 20260708 SAUF l'étape 5 : au lieu de sommer tout le ledger, elle
-- délègue à billing_reproject_wallet (pass-aware) puis relit available_credits.
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

  -- 1) ORDER (idempotent par idempotency_key déterministe)
  insert into public.orders
    (user_id, product_id, status, provider, amount, currency, idempotency_key)
  values
    (p_user_id, p_product_id, 'PAID', p_provider, p_amount, coalesce(p_currency, 'USD'), v_order_key)
  on conflict (idempotency_key) do update
    set status = 'PAID', updated_at = now()
  returning id into v_order_id;

  v_grant_key := 'grant:order:' || v_order_id::text;

  -- 2) PAYMENT (ancre UNIQUE(provider, provider_transaction_id))
  insert into public.payments
    (order_id, provider, provider_transaction_id, status, amount, currency, raw_payload)
  values
    (v_order_id, p_provider, p_provider_transaction_id, 'SUCCESS', p_amount, p_currency, p_raw_payload)
  on conflict (provider, provider_transaction_id) do nothing;
  v_payment_new := found;

  -- 3) PASS (idempotent par UNIQUE(source_order_id))
  insert into public.passes
    (user_id, product_id, source_order_id, starts_at, ends_at, status)
  values
    (p_user_id, p_product_id, v_order_id, now(), v_ends_at, 'ACTIVE')
  on conflict (source_order_id) do nothing;
  select id into v_pass_id from public.passes where source_order_id = v_order_id;

  -- 4) LEDGER GRANT (idempotent par idempotency_key ; scoppé au Pass)
  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values
    (p_user_id, 'GRANT', p_credits, v_pass_id, 'ORDER', v_order_id::text, v_grant_key)
  on conflict (idempotency_key) do nothing;
  v_grant_new := found;

  -- 5) WALLET — projection PASS-AWARE centralisée (bucket du pass actif).
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


-- ── 3) Backfill : re-projeter TOUS les wallets existants avec la nouvelle règle
-- Idempotent (recompute depuis le ledger). Corrige le wallet de 1ba1c0f9
-- (29 → 60 si le pass est encore actif ; → 0 si le pass a expiré = crédits
-- expirés avec le pass, conforme spec). Snapshot des ids AVANT la boucle
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
--   select proname from pg_proc where proname in ('billing_reproject_wallet','billing_grant_purchase'); -- 2
--   -- Le wallet du user du 1er achat :
--   select available_credits, active_pass_id, pass_expires_at
--     from public.wallets where user_id = '1ba1c0f9-2385-47a8-9bd8-b0a4e1082d9d';
--   -- Attendu : 60 si le pass 0dc70442 est encore ACTIVE/non expiré ; 0 sinon
--   --           (bucket free −31 planchérisé à 0, le pass expiré ne compte plus).
