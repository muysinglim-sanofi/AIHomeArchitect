-- ============================================================================
-- FT1b — Trial anonyme 3 → 1 (MIGRATION LIVE) ⚠️ NE PAS APPLIQUER AVANT FT2
-- ============================================================================
-- Recrée billing_try_hold à l'IDENTIQUE de 20260710_billing_p0a_atomic_hold.sql,
-- avec un SEUL changement : le crédit TRIAL free-tier passe du littéral 3 à
-- billing_free_config().anon_free (= 1). Dépend de 20260717_ft1a (billing_free_config).
--
-- ⚠️ IMPACT LIVE À L'APPLY : tout nouvel utilisateur anonyme reçoit 1 génération
-- gratuite au lieu de 3. Couplé au bonus de création (+2) : sans l'auth gate
-- frontend (FT2) qui propose la création de compte après la génération #1, un
-- anonyme n'aurait aucun moyen d'obtenir les +2 → régression 3→1. APPLIQUER
-- CETTE MIGRATION UNIQUEMENT au lancement coordonné FT2 (auth gate live +
-- FREE_TRIAL_SIGNUP_BONUS_ENABLED=true). Rollback = ré-appliquer 20260710.
--
-- Aucune autre logique (idempotence, advisory-lock, pass-first/free/floor,
-- HOLD -1, reprojection wallet) n'est modifiée. Ne touche NI /generate NI
-- /refine côté Python.
-- Pas de BEGIN/COMMIT explicite (runner / SQL Editor enveloppe le fichier).
-- ============================================================================

-- Garde d'ordre d'apply : ft1b DÉPEND de billing_free_config() (créée par ft1a).
-- Appliquer ft1b sans ft1a échoue ICI (à l'apply, visible) plutôt qu'en 503
-- runtime sur la 1re génération free.
do $$
begin
  if to_regprocedure('public.billing_free_config()') is null then
    raise exception 'FT1b requires 20260717_ft1a first (public.billing_free_config() is missing)';
  end if;
end $$;

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
  v_anon_free     int := 1;   -- FT1 : crédit trial free-tier, lu depuis billing_free_config()
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
    -- FT1 : montant du trial anonyme centralisé (1), plus le littéral 3.
    select anon_free into v_anon_free from public.billing_free_config();
    insert into public.ledger_entries
      (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values
      (p_user_id, 'TRIAL', v_anon_free, null, 'PROMO', 'trial', v_trial_key)
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
