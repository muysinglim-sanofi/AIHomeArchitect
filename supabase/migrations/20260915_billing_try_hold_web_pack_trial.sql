-- ============================================================================
-- 20260915_billing_try_hold_web_pack_trial — le droit gratuit survit a un PACK
-- achete sur le web (ABA/KHQR), jamais a un ABONNEMENT store (RevenueCat).
--
-- BUG P0 CORRIGE. Les 3 generations gratuites ne sont pas des lignes : elles
-- etaient PROJETEES, et la projection etait coupee des qu'un pass actif
-- existait. Le TRIAL n'etait par ailleurs materialise que dans la branche de
-- dernier recours, atteinte seulement quand le pass est vide. Avec un pack de
-- credits perpetuel, cette branche n'etait JAMAIS atteinte : les 3 gratuits
-- etaient perdus pour toujours (constate en production le 2026-09-15 : un
-- acheteur de pack_10 voyait 10 au lieu de 13).
--
-- CE QUI CHANGE : le TRIAL est materialise AVANT le choix du bucket, et la
-- garde « aucun pass actif » devient « aucun pass d'ABONNEMENT actif », via un
-- discriminateur AUTORITAIRE : orders.provider = 'khqr' ET products.type =
-- 'CREDIT_PACK'. Jamais ends_at : la date perpetuelle est une consequence.
--
-- CE QUI NE CHANGE PAS : l'ordre de debit (pass d'abord), le JSON de retour
-- (total_before est fige avant materialisation), billing_grant_purchase, le
-- rail PayWay, RevenueCat, iOS.
--
-- PREUVE (2026-09-15) : essai a blanc sur les 136 comptes de production, dans
-- des transactions ANNULEES, ancienne definition contre nouvelle. Resultat :
-- une seule difference, sur le compte acheteur KHQR ; 7 comptes a pass
-- RevenueCat et 128 comptes sans pass strictement invariants. Matrice
-- (3-k)+10-1 verte pour k=0,1,2,3.
--
-- md5 avant : a1aa52c0b152295c8828cb46451be2ba
-- md5 apres : 3c8c2f035c615087f71b7914222b026d
-- Rollback  : backend/sql/rollback/20260915_billing_try_hold_web_pack_trial_rollback.sql
-- APPLIQUEE EN PRODUCTION le 2026-09-15.
-- ============================================================================
begin;
CREATE OR REPLACE FUNCTION public.billing_try_hold(p_user_id uuid, p_intent_id text, p_tier text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_hold_key text := 'hold:' || p_intent_id;
  v_trial_key text := 'trial:' || p_user_id::text;
  v_active_pass uuid; v_pass int := 0; v_free_raw int := 0; v_free int := 0;
  v_trial_granted boolean := false; v_target_pass uuid; v_bucket text;
  v_total_before int; v_total_after int;
  -- 2026-09-15 — le pass ACTIF provient-il du rail WEB (ABA/KHQR) sur un pack de
  -- credits ? Discriminateur AUTORITAIRE : la commande qui a cree le pass
  -- (orders.provider) ET le type du produit (products.type). Jamais ends_at :
  -- la date perpetuelle est une consequence, pas une identite.
  v_pass_is_web_pack boolean := false;
begin
  if exists (select 1 from public.ledger_entries where idempotency_key = v_hold_key) then
    return jsonb_build_object('granted', true, 'reason', '', 'idempotent', true, 'bucket', 'existing');
  end if;
  if p_tier in ('admin', 'promo_unlimited', 'promo_limited') then
    return jsonb_build_object('granted', true, 'reason', 'bypass', 'bucket', 'none');
  end if;
  perform pg_advisory_xact_lock(hashtext(p_user_id::text));
  select id into v_active_pass from public.passes
   where user_id = p_user_id and status = 'ACTIVE' and now() between starts_at and ends_at
   order by ends_at desc limit 1;
  if v_active_pass is not null then
    select coalesce(sum(available_delta), 0) into v_pass
      from public.ledger_entries where user_id = p_user_id and pass_id = v_active_pass;
    select coalesce(o.provider = 'khqr' and pr.type = 'CREDIT_PACK', false)
      into v_pass_is_web_pack
      from public.passes pa
      join public.orders o on o.id = pa.source_order_id
      join public.products pr on pr.id = pa.product_id
     where pa.id = v_active_pass;
    v_pass_is_web_pack := coalesce(v_pass_is_web_pack, false);
  end if;
  select coalesce(sum(available_delta), 0), coalesce(bool_or(entry_type = 'TRIAL'), false)
    into v_free_raw, v_trial_granted
    from public.ledger_entries where user_id = p_user_id and pass_id is null;
  v_free := greatest(v_free_raw, 0);
  -- total_before est fige ICI, AVANT toute materialisation, pour que le JSON de
  -- retour reste bit-a-bit celui de l'ancienne definition sur tous les comptes
  -- existants (l'essai a blanc du 2026-09-15 a montre que le calculer apres
  -- faisait varier ce champ chez 3 comptes RevenueCat expires et 80 comptes
  -- sans pass, sans aucun effet sur le solde).
  v_total_before := v_pass + v_free;

  -- 2026-09-15 — LE CORRECTIF. Le droit gratuit est MATERIALISE ici, avant le choix
  -- du bucket, et non plus dans la branche de dernier recours : avec un pack de
  -- credits non epuise, cette branche n'etait jamais atteinte et les 3 gratuits
  -- etaient perdus pour toujours (le pass web ne perime pas).
  -- Un abonnement store (RevenueCat) garde EXACTEMENT l'ancien comportement :
  -- v_pass_is_web_pack est faux, donc aucune insertion tant que le pass est actif.
  if p_tier = 'free' and not v_trial_granted
     and (v_active_pass is null or v_pass_is_web_pack) then
    insert into public.ledger_entries
      (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values (p_user_id, 'TRIAL', 3, null, 'PROMO', 'trial', v_trial_key)
    on conflict (idempotency_key) do nothing;
    select coalesce(sum(available_delta), 0), coalesce(bool_or(entry_type = 'TRIAL'), false)
      into v_free_raw, v_trial_granted
      from public.ledger_entries where user_id = p_user_id and pass_id is null;
  end if;

  v_free := greatest(v_free_raw, 0);
  -- ORDRE DE DEBIT INCHANGE : le pass d'abord, le bucket gratuit ensuite.
  if v_pass >= 1 then
    v_bucket := 'pass'; v_target_pass := v_active_pass;
  elsif v_free >= 1 then
    v_bucket := 'free'; v_target_pass := null;
  else
    return jsonb_build_object('granted', false,
      'reason', case when v_active_pass is not null then 'pass_exhausted'
                     when p_tier <> 'free' then 'no_active_pass'
                     else 'insufficient_credits' end,
      'total_before', v_total_before, 'total_after', v_total_before);
  end if;
  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values (p_user_id, 'HOLD', -1, v_target_pass, 'GENERATION_INTENT', p_intent_id, v_hold_key)
  on conflict (idempotency_key) do nothing;
  perform public.billing_reproject_wallet(p_user_id);
  select available_credits into v_total_after from public.wallets where user_id = p_user_id;
  return jsonb_build_object('granted', true, 'reason', '', 'bucket', v_bucket, 'pass_id', v_target_pass,
    'total_before', v_total_before, 'total_after', coalesce(v_total_after, v_total_before - 1));
end; $function$
;
commit;
