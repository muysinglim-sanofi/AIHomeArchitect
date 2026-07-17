-- ═══════════════════════════════════════════════════════════════════════════
-- ON-mode (2026-07-17) — TRIAL flag-scopé + claim Guest atomique + signup bonus.
-- Derrière l'autorité serveur ACCOUNT_SYSTEM_ENABLED (backend). Appliquée dans le
-- déploiement ON. Dépend de : 20260710_billing_p0a_atomic_hold.sql + p0_additive_projection.
--
-- OFF-SAFE : billing_try_hold garde p_trial_credits DEFAULT 3 → un appelant 3-arg
-- (prod actuel / mode OFF) est byte-identique. Le mode ON passe p_trial_credits=1.
--
-- Rollback :
--   drop function if exists public.claim_guest_and_bonus(uuid, uuid, int, int);
--   drop function if exists public.billing_try_hold(uuid, text, text, int);
--   -- puis ré-appliquer 20260710_billing_p0a_atomic_hold.sql (billing_try_hold 3-arg).
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1) billing_try_hold PARAMÉTRÉ : le montant du TRIAL matérialisé devient un
--       paramètre (défaut 3 = OFF). Le corps est IDENTIQUE à la version 3-arg, à
--       l'unique différence de la ligne d'insert TRIAL (3 → p_trial_credits). ──────
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
      (p_user_id, 'TRIAL', p_trial_credits, null, 'PROMO', 'trial', v_trial_key)  -- ← paramétré (OFF=3 / ON=1)
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


-- ── 2) claim_guest_and_bonus — à la CRÉATION RÉELLE d'un compte (ON) : transfère le
--       Free Guest ADMISSIBLE (une fois) + accorde +2 (une fois), atomiquement, avec
--       les TROIS clés d'idempotence sous advisory locks. All-or-nothing.
--
--       Anti-abus (revue adversariale) :
--         • guest_claim:<guest_id>          → un Guest réclamé 1 seule fois ;
--         • initial_guest_claim:<account_id> → un compte réclame 1 seul Guest À VIE ;
--         • signup_bonus:<account_id>        → +2 une seule fois.
--       Idempotence FINE via metadata : retry MÊME (account,guest) → succès no-op ;
--       un AUTRE compte sur un guest déjà réclamé → refus ; un compte qui a déjà
--       réclamé un AUTRE guest → refus. Compte doit être FRAIS (0 ligne free) → pas
--       de double-trial. Comptabilité prouvée contre billing.py:_free_bucket_available :
--       compte-crédit écrit comme TRIAL (pose trial_granted → tue le +3 fantôme). ─────
create or replace function public.claim_guest_and_bonus(
  p_account_id    uuid,
  p_guest_id      uuid,
  p_trial_credits int default 1,
  p_signup_bonus  int default 2
) returns jsonb
language plpgsql
as $$
declare
  v_guest_claim_key   text := 'guest_claim:' || p_guest_id::text;
  v_initial_claim_key text := 'initial_guest_claim:' || p_account_id::text;
  v_bonus_key         text := 'signup_bonus:' || p_account_id::text;
  v_guest_trial_key   text := 'trial:' || p_guest_id::text;
  v_lo bigint; v_hi bigint;
  v_existing_acct  text;
  v_existing_guest text;
  v_remaining      int;
  v_acct_free_rows int;
begin
  -- Verrous advisory dans un ordre DÉTERMINISTE (anti-deadlock).
  v_lo := least(hashtext(p_account_id::text), hashtext(p_guest_id::text));
  v_hi := greatest(hashtext(p_account_id::text), hashtext(p_guest_id::text));
  perform pg_advisory_xact_lock(v_lo);
  if v_hi <> v_lo then perform pg_advisory_xact_lock(v_hi); end if;

  -- Idempotence + anti-abus cross-compte (les rows portent le lien en metadata).
  select metadata->>'account_id' into v_existing_acct
    from public.ledger_entries where idempotency_key = v_guest_claim_key limit 1;
  select metadata->>'guest_id'  into v_existing_guest
    from public.ledger_entries where idempotency_key = v_initial_claim_key limit 1;

  if v_existing_acct is not null then
    if v_existing_acct = p_account_id::text then
      -- Retry de la MÊME paire (account,guest) → succès idempotent (aucune écriture).
      return jsonb_build_object('status', 'already_claimed', 'claimed', 0,
        'bonus', 0, 'idempotent', true);
    else
      raise exception 'guest_claimed_by_other_account' using errcode = '23505';
    end if;
  end if;
  if v_existing_guest is not null then
    -- Le compte a déjà réclamé un AUTRE guest (ce guest-ci n'est pas réclamé) → refus.
    raise exception 'account_already_claimed_other_guest' using errcode = '23505';
  end if;

  -- Le compte doit être VRAIMENT frais (aucune ligne free-bucket) → jamais d'over-credit
  -- si le compte a déjà généré (trial:<account>) avant le claim.
  select count(*) into v_acct_free_rows
    from public.ledger_entries where user_id = p_account_id and pass_id is null;
  if v_acct_free_rows > 0 then
    raise exception 'account_not_fresh' using errcode = '23514';
  end if;

  -- Matérialiser le trial du guest s'il est absent (remaining = vrais deltas).
  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values (p_guest_id, 'TRIAL', p_trial_credits, null, 'PROMO', 'trial', v_guest_trial_key)
  on conflict (idempotency_key) do nothing;

  -- remaining = free guest admissible (pass_id NULL, planché ≥0), plafonné à p_trial_credits.
  select greatest(0, coalesce(sum(available_delta), 0)) into v_remaining
    from public.ledger_entries where user_id = p_guest_id and pass_id is null;
  v_remaining := least(v_remaining, p_trial_credits);

  -- Écritures atomiques (aucun ON CONFLICT : un conflit = anomalie → rollback total).
  --   Guest débit (transfert sortant) — clé guest_claim, metadata → account.
  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key, metadata)
  values (p_guest_id, 'ADJUSTMENT', -v_remaining, null, 'PROMO', 'guest_claim', v_guest_claim_key,
          jsonb_build_object('account_id', p_account_id::text));
  --   Compte crédit (= son trial, TUE le +N fantôme) — clé initial_guest_claim, metadata → guest.
  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key, metadata)
  values (p_account_id, 'TRIAL', v_remaining, null, 'PROMO', 'guest_claim', v_initial_claim_key,
          jsonb_build_object('guest_id', p_guest_id::text));
  --   Compte bonus +2 — clé signup_bonus.
  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values (p_account_id, 'ADJUSTMENT', p_signup_bonus, null, 'PROMO', 'signup_bonus', v_bonus_key);

  perform public.billing_reproject_wallet(p_guest_id);
  perform public.billing_reproject_wallet(p_account_id);

  return jsonb_build_object(
    'status', 'claimed', 'claimed', v_remaining, 'bonus', p_signup_bonus,
    'account_total', v_remaining + p_signup_bonus, 'guest_after', 0);
end;
$$;
grant execute on function public.claim_guest_and_bonus(uuid, uuid, int, int) to service_role;
