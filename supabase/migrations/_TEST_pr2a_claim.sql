-- ============================================================
-- PR2a — TEST self-vérifiant du claim (NON une migration)
-- Paste into: Supabase Dashboard → SQL Editor → Run.
-- Le préfixe `_TEST_` sort de l'ordre lexical des vraies migrations.
-- Tout est nettoyé à la fin ; ré-exécutable à volonté.
-- ============================================================
-- Prérequis : la migration 20260701_generation_intent_pr2_claim.sql est appliquée.
-- Prouve les invariants anti-double SANS concurrence réelle (un DO block est
-- séquentiel) — mais ces invariants TIENNENT sous concurrence grâce aux
-- primitives DB (voir la note en bas). RAISE EXCEPTION au premier échec.
-- ============================================================
do $$
declare
  v_uid    uuid;
  v_won    boolean;
  v_status text;
  v_reclaim int;
begin
  -- user_id réel (respecte un éventuel FK) ; sinon un uuid aléatoire.
  select user_id into v_uid from public.generation_intents limit 1;
  if v_uid is null then v_uid := gen_random_uuid(); end if;
  delete from public.generation_intents where intent_id = 'pr2a_test';

  -- T1 — claim initial → won=true, RUNNING (le process gagnant).
  select won, status into v_won, v_status
    from public.claim_intent('pr2a_test', v_uid, null, 1, '{}'::jsonb, 'r1');
  raise notice 'T1 claim#1        won=% status=%   (attendu t / RUNNING)', v_won, v_status;
  if not (v_won and v_status = 'RUNNING') then raise exception 'T1 FAIL'; end if;

  -- T2 — 2e claim du MÊME intent (2e device / retry) → won=false. JAMAIS 2 won.
  select won, status into v_won, v_status
    from public.claim_intent('pr2a_test', v_uid, null, 1, '{}'::jsonb, 'r2');
  raise notice 'T2 claim#2        won=% status=%   (attendu f / RUNNING)', v_won, v_status;
  if v_won then raise exception 'T2 FAIL: un 2e claim a gagné → DOUBLE'; end if;

  -- T3 — l'exécution échoue (FAILED) puis retry délibéré → re-claim gagné.
  update public.generation_intents set status = 'FAILED' where intent_id = 'pr2a_test';
  select won, reclaim_count into v_won, v_reclaim from public.reclaim_intent('pr2a_test', 3);
  raise notice 'T3 reclaim FAILED won=% reclaim=%   (attendu t / 1)', v_won, v_reclaim;
  if not (v_won and v_reclaim = 1) then raise exception 'T3 FAIL'; end if;

  -- T4 — PREUVE ANTI-DOUBLE (❷) : après re-claim, l'intent est RUNNING. Un 2e
  -- worker qui tenterait de re-claim ce RUNNING est REFUSÉ (and status='FAILED').
  select won into v_won from public.reclaim_intent('pr2a_test', 3);
  raise notice 'T4 reclaim RUNNING won=%             (attendu f — pas de 2 workers)', v_won;
  if v_won then raise exception 'T4 FAIL: re-claim d''un RUNNING a gagné → DOUBLE'; end if;

  -- T5 — borne : reclaim_count au max → refusé (pas de retry infini).
  update public.generation_intents set status = 'FAILED', reclaim_count = 3 where intent_id = 'pr2a_test';
  select won into v_won from public.reclaim_intent('pr2a_test', 3);
  raise notice 'T5 reclaim borné   won=%             (attendu f — borne 3/3)', v_won;
  if v_won then raise exception 'T5 FAIL: reclaim au-delà de la borne'; end if;

  -- T6 — FAILED_TERMINAL : jamais re-claim.
  update public.generation_intents set status = 'FAILED_TERMINAL', reclaim_count = 0 where intent_id = 'pr2a_test';
  select won into v_won from public.reclaim_intent('pr2a_test', 3);
  raise notice 'T6 reclaim TERMINAL won=%            (attendu f — terminal)', v_won;
  if v_won then raise exception 'T6 FAIL: FAILED_TERMINAL re-claimé'; end if;

  -- T7 — replay : claim sur un intent SUCCEEDED → won=false + result_ref renvoyé.
  update public.generation_intents
     set status = 'SUCCEEDED', result_ref = '{"after_image_url":"http://x/y.jpg"}'::jsonb
   where intent_id = 'pr2a_test';
  select won, status into v_won, v_status
    from public.claim_intent('pr2a_test', v_uid, null, 1, '{}'::jsonb, 'r3');
  raise notice 'T7 claim SUCCEEDED won=% status=%   (attendu f / SUCCEEDED)', v_won, v_status;
  if not (not v_won and v_status = 'SUCCEEDED') then raise exception 'T7 FAIL'; end if;

  delete from public.generation_intents where intent_id = 'pr2a_test';
  raise notice '===============================================';
  raise notice '  PR2a SQL — T1..T7 : TOUS LES ASSERTS PASSENT';
  raise notice '===============================================';
end $$;

-- ============================================================
-- POURQUOI ÇA TIENT SOUS CONCURRENCE RÉELLE (❷) :
--
--  • claim_intent : deux INSERT concurrents du même intent_id → l'index UNIQUE
--    sur intent_id sérialise ; exactement UN insère (ON CONFLICT côté perdant →
--    0 ligne → FOUND=false → il lit le statut). Impossible d'avoir deux won.
--
--  • reclaim_intent : l'UPDATE ... WHERE status='FAILED' pose un ROW-LOCK. Deux
--    reclaim concurrents se sérialisent sur ce verrou ; Postgres RE-ÉVALUE le
--    prédicat (EvalPlanQual) sur la ligne mise à jour : le 2e voit status='RUNNING'
--    (≠ 'FAILED') → 0 ligne → FOUND=false → won=false. Un seul reclaim gagne.
--
-- VISIBILITÉ TRANSACTIONNELLE (❺) : chaque appel RPC PostgREST s'exécute dans SA
-- transaction, COMMITÉE au retour de la fonction, AVANT la réponse HTTP. Donc
-- quand claim_generation_intent renvoie won=true, la ligne RUNNING est DÉJÀ
-- committée et visible — même si le process Python crashe juste après. C'est
-- précisément ce sur quoi repose la reprise/réconciliation (PR4).
-- Test manuel de la sérialisation vraie : ouvrir 2 sessions SQL, `begin;` dans
-- chacune, lancer claim_intent(même id) → la 2e bloque jusqu'au commit de la 1re,
-- puis renvoie won=false.
-- ============================================================
