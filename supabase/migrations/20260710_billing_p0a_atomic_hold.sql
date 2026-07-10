-- ═══════════════════════════════════════════════════════════════════════════
-- P0a-bis (2026-07-10) — RÉSERVATION ATOMIQUE gate+HOLD (billing_try_hold)
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- Dépend de : 20260710_billing_p0_additive_projection.sql (billing_reproject_wallet additif)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- FAILLE FERMÉE (revue adversariale P0, HIGH exploitable, pré-existante) :
--   reserve_decision est LECTURE SEULE et le HOLD était posé APRÈS le claim, en
--   check-then-act NON atomique. → N /generate concurrents (intents distincts,
--   prompts variant d'1 char) lisent tous le même solde B, passent tous le gate,
--   lancent tous OpenAI → (N−B) générations payées non couvertes (fuite $).
--
-- FIX : le VRAI droit de générer devient un HOLD ATOMIQUE conditionnel, sérialisé
--   par user via pg_advisory_xact_lock. /generate n'appelle OpenAI que si granted.
--   Deux requêtes concurrentes du même user ne peuvent PLUS autoriser 2× le même
--   crédit : la seconde, sous verrou, relit le solde déjà décrémenté.
--
-- GARANTIES :
--   • granted == true seulement si le bucket choisi (pass-first PUIS free) a ≥ 1 ;
--     sinon granted=false + reason (pass_exhausted | no_active_pass | insufficient_credits).
--   • pass-first : débite le pass actif d'abord, puis le free résiduel planché.
--   • free tier 1er passage : matérialise le TRIAL (+3) atomiquement (idempotent trial:<uid>).
--   • IDEMPOTENT : un hold:<intent> déjà présent → granted (aucun double débit) — couvre
--     reclaim/retry/replay. Le HOLD écrit ici est repris par COMMIT/RELEASE (même bucket,
--     via _intent_hold_bucket) → cycle de vie cohérent.
--   • bypass (admin/promo_unlimited/promo_limited) → granted, AUCUN HOLD (illimité réel).
--   • Sous verrou → wallet reprojeté (source unique). N=200 concurrents sur B=60 → 60 granted.
--
-- Rollback : drop function if exists public.billing_try_hold(uuid, text, text);
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.billing_try_hold(
  p_user_id   uuid,
  p_intent_id text,
  p_tier      text
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
  -- 0) IDEMPOTENCE — HOLD déjà posé pour cet intent → granted (aucun double débit).
  --    Couvre reclaim (FAILED→RUNNING), replay, double-fire même intent.
  if exists (select 1 from public.ledger_entries where idempotency_key = v_hold_key) then
    return jsonb_build_object('granted', true, 'reason', '', 'idempotent', true, 'bucket', 'existing');
  end if;

  -- 1) BYPASS réel (admin / promo) → illimité, aucun HOLD, aucun verrou.
  if p_tier in ('admin', 'promo_unlimited', 'promo_limited') then
    return jsonb_build_object('granted', true, 'reason', 'bypass', 'bucket', 'none');
  end if;

  -- 2) SÉRIALISATION par user — toutes les tentatives concurrentes passent en FILE.
  --    Libéré en fin de transaction (chaque RPC PostgREST = 1 transaction).
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));

  -- 3) Recalcul SOUS verrou (voit les HOLD des tentatives déjà sérialisées).
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

  -- 4) PASS-FIRST puis FREE ; sinon TRIAL free-tier 1er passage ; sinon DENY.
  if v_pass >= 1 then
    v_bucket := 'pass'; v_target_pass := v_active_pass;
  elsif v_free >= 1 then
    v_bucket := 'free'; v_target_pass := null;
  elsif p_tier = 'free' and v_active_pass is null and not v_trial_granted then
    insert into public.ledger_entries
      (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values
      (p_user_id, 'TRIAL', 3, null, 'PROMO', 'trial', v_trial_key)
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

  -- 5) HOLD(-1) sur le bucket choisi, idempotent (hold:<intent>).
  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values
    (p_user_id, 'HOLD', -1, v_target_pass, 'GENERATION_INTENT', p_intent_id, v_hold_key)
  on conflict (idempotency_key) do nothing;

  -- 6) Reprojection wallet (source unique) + solde après.
  perform public.billing_reproject_wallet(p_user_id);
  select available_credits into v_total_after from public.wallets where user_id = p_user_id;

  return jsonb_build_object(
    'granted', true, 'reason', '', 'bucket', v_bucket, 'pass_id', v_target_pass,
    'total_before', v_total_before, 'total_after', coalesce(v_total_after, v_total_before - 1));
end;
$$;

grant execute on function public.billing_try_hold(uuid, text, text) to service_role;


-- ── Sanity-check (après application, user JETABLE — ledger append-only) ───────
--   -- pass=5, 3 appels séquentiels d'intents distincts → 3 granted, solde 2 :
--   select public.billing_try_hold('<uid>', 'i1', 'premium');  -- granted, bucket=pass
--   select public.billing_try_hold('<uid>', 'i2', 'premium');
--   select public.billing_try_hold('<uid>', 'i3', 'premium');
--   -- 6e appel sur solde 0 → granted=false, reason=pass_exhausted.
--   -- Concurrence réelle (advisory lock) : cf. e2e_p0_atomic_hold.py (N concurrents → min(N,B)).
