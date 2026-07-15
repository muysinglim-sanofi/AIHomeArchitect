-- ============================================================================
-- _TEST_ft1b_flip_rollback.sql — test ENTIÈREMENT RÉVERSIBLE du flip trial 3→1
-- ============================================================================
-- Prouve DEUX choses :
--   1) FT1b fonctionne (billing_try_hold accorde TRIAL +1, HOLD -1, wallet
--      cohérent, verrou historique présent exactement une fois) ;
--   2) FT1b n'est JAMAIS conservée dans le Sandbox après le test — billing_try_hold
--      revient à l'IDENTIQUE (pg_get_functiondef + md5 comparés avant/après).
--
-- Mécanique : le CREATE OR REPLACE de FT1b est appliqué DANS UN SAVEPOINT puis
-- annulé par ROLLBACK TO SAVEPOINT (le DDL est transactionnel sous savepoint).
-- La baseline (définition + md5) est capturée AVANT le savepoint → elle survit à
-- l'annulation. On NE COMMIT JAMAIS. Aucune migration n'est appliquée durablement.
--
-- PRÉREQUIS : (a) 20260710_billing_p0a_atomic_hold appliquée — billing_try_hold
-- doit exister (la baseline le lit via pg_get_functiondef) ; (b) 20260717_ft1a
-- appliquée — billing_free_config() est appelée par le corps FT1b. NE REQUIERT
-- PAS 20260718_ft1b (le flip est appliqué temporairement puis annulé). Fixtures
-- sous session_replication_role=replica (saute triggers + FK). Aucun compte réel
-- touché. NB : à lancer dans une transaction (SQL Editor / psql) — un runner
-- autocommit ferait échouer le `savepoint` AVANT tout CREATE OR REPLACE.
-- ============================================================================

begin;
set local session_replication_role = replica;

-- ── A) BASELINE, capturée AVANT le savepoint (survit au rollback to savepoint) ──
create temp table _ft1b_baseline as
  select pg_get_functiondef('public.billing_try_hold(uuid, text, text)'::regprocedure) as def;

-- ── B) SAVEPOINT → flip FT1b TEMPORAIRE → test ─────────────────────────────────
savepoint sp_flip;

-- Copie EXACTE de 20260718_ft1b (billing_try_hold, trial 3→billing_free_config().anon_free).
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

-- Test du flip : anonyme frais → TRIAL +1, HOLD -1, wallet 0, 1 verrou historique.
do $$
declare v jsonb; n int;
begin
  v := public.billing_try_hold('f1b00000-0000-0000-0000-000000000000', 'i-flip', 'free');
  if (v->>'granted')::boolean is not true then raise exception 'FLIP: non accordé (%)', v; end if;

  select available_delta into n from public.ledger_entries
    where user_id='f1b00000-0000-0000-0000-000000000000' and entry_type='TRIAL';
  if n is distinct from 1 then raise exception 'FLIP: TRIAL=% (attendu 1)', n; end if;

  select available_delta into n from public.ledger_entries
    where user_id='f1b00000-0000-0000-0000-000000000000' and entry_type='HOLD';
  if n is distinct from -1 then raise exception 'FLIP: HOLD=% (attendu -1)', n; end if;

  select available_credits into n from public.wallets
    where user_id='f1b00000-0000-0000-0000-000000000000';
  if n is distinct from 0 then raise exception 'FLIP: wallet=% (attendu 0)', n; end if;

  -- verrou HISTORIQUE de billing_try_hold : présent exactement UNE fois
  select count(*) into n from regexp_matches(
    pg_get_functiondef('public.billing_try_hold(uuid, text, text)'::regprocedure),
    'pg_advisory_xact_lock', 'g');
  if n is distinct from 1 then raise exception 'FLIP: verrou historique count=% (attendu 1)', n; end if;

  raise notice 'PASS flip : TRIAL+1, HOLD-1, wallet 0, 1 verrou historique conservé';
end $$;

-- ── C) ANNULER le flip + les fixtures (le DDL du savepoint est reverté) ─────────
rollback to savepoint sp_flip;

-- ── D) APRÈS le rollback : billing_try_hold DOIT être identique à la baseline ───
do $$
declare v_now text; v_base text;
begin
  v_now := pg_get_functiondef('public.billing_try_hold(uuid, text, text)'::regprocedure);
  select def into v_base from _ft1b_baseline;
  if md5(v_now) <> md5(v_base) then
    raise exception 'FT1b NON restaurée : billing_try_hold diverge du baseline (md5 % vs %)',
      substr(md5(v_now), 1, 8), substr(md5(v_base), 1, 8);
  end if;
  raise notice 'PASS restore : billing_try_hold IDENTIQUE avant/après rollback (md5 %) — ft1b non conservée',
    substr(md5(v_now), 1, 8);
end $$;

drop table if exists _ft1b_baseline;

-- Filet final : rien n'est jamais commité. Aucune modification durable du Sandbox.
rollback;
