-- ============================================================
-- Billing Engine — PR1 : vues d'observation
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ============================================================
--
-- Spec : docs/BILLING_ENGINE_SPEC.md. Aucune table (PR0 les a créées) ; juste
-- des VUES pour observer le ledger/wallet se former (PR1 = observabilité, sans
-- gate). Sûr, en lecture seule.
--
-- Rollback :
--   drop view if exists public.v_wallet_vs_ledger;
--   drop view if exists public.v_billing_daily;
-- ============================================================


-- ── Rollup quotidien du ledger ───────────────────────────────
-- Volume par type d'événement + net/jour. Permet de voir la mécanique
-- reserve/commit/release + les TRIAL se former sur du vrai trafic.
create or replace view public.v_billing_daily as
select
  (created_at at time zone 'UTC')::date               as day,
  count(*) filter (where entry_type = 'TRIAL')         as trials,
  count(*) filter (where entry_type = 'HOLD')          as holds,
  count(*) filter (where entry_type = 'COMMIT')        as commits,
  count(*) filter (where entry_type = 'RELEASE')       as releases,
  count(*) filter (where entry_type = 'REFUND')        as refunds,
  count(*) filter (where entry_type = 'EXPIRE')        as expires,
  count(*) filter (where entry_type = 'ADJUSTMENT')    as adjustments,
  sum(available_delta)                                 as net_delta,
  count(distinct user_id)                              as users
from public.ledger_entries
group by 1
order by 1 desc;


-- ── Cohérence wallet ↔ ledger (BT-6) ─────────────────────────
-- Le wallet DOIT être la projection exacte du ledger. available_ok / held_ok
-- doivent être true partout ; une ligne false = bug de projection à investiguer.
create or replace view public.v_wallet_vs_ledger as
select
  w.user_id,
  w.available_credits,
  w.held_credits,
  w.ledger_version,
  coalesce(l.available, 0)                             as ledger_available,
  coalesce(l.held, 0)                                  as ledger_held,
  coalesce(l.version, 0)                               as ledger_max_id,
  (w.available_credits = coalesce(l.available, 0))     as available_ok,
  (w.held_credits      = coalesce(l.held, 0))          as held_ok
from public.wallets w
left join lateral (
  select
    sum(available_delta)                                                    as available,
    count(*) filter (where entry_type = 'HOLD')
      - count(*) filter (where entry_type in ('RELEASE', 'COMMIT'))         as held,
    max(id)                                                                 as version
  from public.ledger_entries le
  where le.user_id = w.user_id
) l on true;


-- ── Anomalies GATE-2 (à MESURER avant PR2) ──────────────────
-- Un même intent_id ayant produit COMMIT *et* RELEASE (FAILED puis SUCCEEDED)
-- → net 0 pour une gen réussie. C'est le SYMPTÔME de l'absence de claim atomique
-- que PR2 supprime à la SOURCE (on ne le compense PAS dans le moteur de billing).
-- Cette vue mesure sa fréquence réelle : vide = aucun doublon observé.
create or replace view public.v_billing_intent_anomalies as
select
  reference_id                                         as intent_id,
  sum(available_delta)                                 as net,
  count(*) filter (where entry_type = 'HOLD')          as holds,
  count(*) filter (where entry_type = 'COMMIT')        as commits,
  count(*) filter (where entry_type = 'RELEASE')       as releases,
  string_agg(entry_type, ',' order by id)              as events,
  max(created_at)                                      as last_at
from public.ledger_entries
where reference_type = 'GENERATION_INTENT'
group by reference_id
having count(*) filter (where entry_type = 'COMMIT') > 0
   and count(*) filter (where entry_type = 'RELEASE') > 0;


-- ── Lecture ──────────────────────────────────────────────────
--   select * from public.v_billing_daily;
--   select * from public.v_wallet_vs_ledger where not available_ok or not held_ok;  -- vide = OK
--
-- Ledger brut d'un user (chronologique) :
--   select id, entry_type, available_delta, reference_type, reference_id,
--          idempotency_key, created_at
--   from public.ledger_entries where user_id = '<uid>' order by id;
--
-- BT-7 (1 Intent = 1 débit net) — net par intent_id :
--   select reference_id as intent_id, sum(available_delta) as net,
--          string_agg(entry_type, ',' order by id) as events
--   from public.ledger_entries
--   where reference_type = 'GENERATION_INTENT'
--   group by reference_id order by max(id) desc limit 50;
--   -- attendu : net = -1 (succeeded) ou 0 (failed).
--
-- Anomalies GATE-2 (doublon COMMIT+RELEASE d'un même intent → net 0 pour une
-- gen réussie) — MESURE la fréquence, NON compensée en PR1 (PR2 supprime la cause):
--   select * from public.v_billing_intent_anomalies;   -- vide = aucun doublon observé


-- ============================================================
-- Fin PR1 Billing — vues d'observation.
-- ============================================================
