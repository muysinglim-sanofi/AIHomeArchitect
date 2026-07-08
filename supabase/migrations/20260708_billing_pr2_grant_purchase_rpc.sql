-- ═══════════════════════════════════════════════════════════════════════════
-- RC-PR2 · Étape 2 — RPC atomique billing_grant_purchase
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Spec : docs/BILLING_ENGINE_SPEC.md (§4.0 événements, R6 traitement Payment,
-- §4.3/§4.5 idempotence). Design validé (RC-PR2, 2026-07-08).
--
-- RÔLE. Transformer un achat/renouvellement RevenueCat (INITIAL_PURCHASE /
-- RENEWAL) en : Order(PAID) + Payment(SUCCESS) + Pass(ACTIVE) + ledger GRANT
-- (+crédits, scoppé au Pass) → wallet reprojeté. TOUT dans UNE transaction
-- (une fonction plpgsql via PostgREST = 1 transaction) → atomique tout-ou-rien.
--
-- POURQUOI UN RPC (pas 5 écritures Python best-effort) — ferme 2 trous :
--   1. `passes` n'avait aucune contrainte d'unicité → une redélivrance créait un
--      2e Pass. On ajoute un index unique sur source_order_id (1 order = 1 Pass).
--   2. Écritures séparées = état partiel possible (Payment ok, GRANT ko) ; au
--      retry le Payment UNIQUE bloquait → GRANT jamais rejoué = crédit perdu.
--      L'atomicité règle ça : un échec ne laisse RIEN → RC retente proprement.
--
-- IDEMPOTENCE (3 barrières DB, rejeu = no-op crédit) :
--   • orders.idempotency_key   = 'order:<provider>:<transaction_id>'
--   • payments UNIQUE(provider, provider_transaction_id)  ← ancre paiement
--   • ledger_entries.idempotency_key = 'grant:order:<order_id>'
--   • passes UNIQUE(source_order_id)  ← ajouté ici
--   Clé keyée sur le transaction_id DU CYCLE : chaque RENEWAL = nouveau tx →
--   nouveau Pass + nouveau GRANT (décision « renouvellement = nouveau cycle »).
--   original_transaction_id (stable) serait un PIÈGE (avalerait les RENEWAL).
--
-- SANDBOX. Le filtrage environment N'EST PAS fait ici (décision RC-PR2 = créditer
-- les achats SANDBOX pour tester le flow TestFlight bout-en-bout). L'environment
-- est conservé dans payment.raw_payload (passé par p_raw_payload) pour l'audit.
--
-- HORS-SCOPE (RC-PR3) : aucun impact sur le gate. Le GRANT est ÉCRIT et le wallet
-- crédité, mais reserve_decision bypasse encore les premium → NON contraignant.
--
-- Rollback :
--   drop function if exists public.billing_grant_purchase(
--     uuid, text, text, uuid, int, int, numeric, text, timestamptz, jsonb);
--   drop index if exists public.passes_source_order_uidx;
-- ═══════════════════════════════════════════════════════════════════════════


-- ── Prérequis : 1 order → au plus 1 Pass (rend l'insert Pass idempotent) ─────
-- Unique sur source_order_id. En Postgres les NULL sont distincts → les Pass
-- sans order (promo/admin futurs) ne sont PAS contraints ; seuls les Pass issus
-- d'un order le sont. Permet le ON CONFLICT (source_order_id) ci-dessous.
create unique index if not exists passes_source_order_uidx
  on public.passes(source_order_id);


create or replace function public.billing_grant_purchase(
  p_user_id                 uuid,
  p_provider                text,          -- 'revenuecat'
  p_provider_transaction_id text,          -- transaction_id DU CYCLE (pas original_)
  p_product_id              uuid,          -- product résolu côté appelant
  p_credits                 int,           -- products.credits_granted
  p_duration_days           int,           -- products.duration_days (fallback ends_at)
  p_amount                  numeric,       -- prix (indicatif, audit)
  p_currency                text,
  p_ends_at                 timestamptz,   -- AUTORITÉ = RC expiration_at_ms
  p_raw_payload             jsonb          -- event complet (contient environment)
) returns jsonb
language plpgsql
as $$
declare
  v_order_id        uuid;
  v_pass_id         uuid;
  v_payment_new     boolean := false;
  v_grant_new       boolean := false;
  v_order_key       text := 'order:' || p_provider || ':' || p_provider_transaction_id;
  v_grant_key       text;
  v_ends_at         timestamptz;
  v_available       int;
  v_held            int;
  v_version         bigint;
  v_active_pass     uuid;
  v_active_expires  timestamptz;
begin
  -- Fenêtre du Pass : autorité RC (p_ends_at) ; repli sur la durée produit.
  v_ends_at := coalesce(p_ends_at, now() + make_interval(days => p_duration_days));

  -- 1) ORDER — idempotent par idempotency_key déterministe. DO UPDATE (touch)
  --    pour que RETURNING renvoie toujours l'id, création OU redélivrance.
  insert into public.orders
    (user_id, product_id, status, provider, amount, currency, idempotency_key)
  values
    (p_user_id, p_product_id, 'PAID', p_provider, p_amount, coalesce(p_currency, 'USD'), v_order_key)
  on conflict (idempotency_key) do update
    set status = 'PAID', updated_at = now()
  returning id into v_order_id;

  v_grant_key := 'grant:order:' || v_order_id::text;

  -- 2) PAYMENT — ANCRE d'idempotence UNIQUE(provider, provider_transaction_id).
  --    environment conservé dans raw_payload (audit).
  insert into public.payments
    (order_id, provider, provider_transaction_id, status, amount, currency, raw_payload)
  values
    (v_order_id, p_provider, p_provider_transaction_id, 'SUCCESS', p_amount, p_currency, p_raw_payload)
  on conflict (provider, provider_transaction_id) do nothing;
  v_payment_new := found;

  -- 3) PASS — idempotent par UNIQUE(source_order_id). Race-safe : 2 livraisons
  --    concurrentes → une insère, l'autre conflit → les 2 relisent le même Pass.
  insert into public.passes
    (user_id, product_id, source_order_id, starts_at, ends_at, status)
  values
    (p_user_id, p_product_id, v_order_id, now(), v_ends_at, 'ACTIVE')
  on conflict (source_order_id) do nothing;
  select id into v_pass_id from public.passes where source_order_id = v_order_id;

  -- 4) LEDGER GRANT — idempotent par idempotency_key UNIQUE ; crédit scoppé au
  --    Pass (expirera avec lui). ON CONFLICT DO NOTHING ne déclenche PAS le
  --    trigger append-only (aucun UPDATE). C'est la SEULE écriture qui crédite.
  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values
    (p_user_id, 'GRANT', p_credits, v_pass_id, 'ORDER', v_order_id::text, v_grant_key)
  on conflict (idempotency_key) do nothing;
  v_grant_new := found;

  -- 5) WALLET — reprojection DEPUIS le ledger (source de vérité), même formule
  --    que billing._reproject_wallet, + Pass actif (que le Python n'écrit pas).
  select coalesce(sum(available_delta), 0),
         count(*) filter (where entry_type = 'HOLD')
           - count(*) filter (where entry_type in ('RELEASE', 'COMMIT')),
         coalesce(max(id), 0)
    into v_available, v_held, v_version
    from public.ledger_entries
   where user_id = p_user_id;

  -- Pass actif courant : ACTIVE, couvre now(), ends_at le plus lointain.
  select id, ends_at
    into v_active_pass, v_active_expires
    from public.passes
   where user_id = p_user_id
     and status = 'ACTIVE'
     and now() between starts_at and ends_at
   order by ends_at desc
   limit 1;

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


-- ── Sanity-check (après application — utiliser un user JETABLE : le ledger est
--    APPEND-ONLY, un GRANT de test ne se supprime pas) ─────────────────────────
--   -- 1er appel = granted, 2e appel (même tx) = already_processed, credited=false
--   select public.billing_grant_purchase(
--     '<test_user_uuid>', 'revenuecat', 'tx_sandbox_001',
--     (select id from public.products where sku='weekly_pass'),
--     60, 7, 7.99, 'USD', now() + interval '7 days',
--     '{"environment":"SANDBOX"}'::jsonb);
--   -- Vérifs : 1 payment, 1 pass, 1 GRANT, wallet.available_credits = 60.
--   select (select count(*) from public.payments where provider_transaction_id='tx_sandbox_001'),
--          (select count(*) from public.ledger_entries where idempotency_key like 'grant:order:%'
--             and reference_type='ORDER' and user_id='<test_user_uuid>');
