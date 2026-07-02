-- ============================================================
-- Generation Intent v1 — PR2a : claim atomique (anti-double)
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ============================================================
--
-- Spec : docs/GENERATION_INTENT_V1_SPEC.md (§4 claim, PR2).
--
-- LOAD-BEARING : ces fonctions deviennent la source de vérité anti-double de
-- /generate. Le claim garantit qu'UN SEUL process lance OpenAI pour un même
-- intent_id (ferme GATE 2). Additif (2 fonctions) ; aucune table modifiée.
--
-- Principe : « Le frontend peut se tromper ; le backend ne doit jamais doubler. »
--
-- Rollback :
--   drop function if exists public.claim_intent(text, uuid, uuid, int, jsonb, text);
--   drop function if exists public.reclaim_intent(text, int);
-- ============================================================


-- ── claim_intent : INSERT-ou-lit-le-statut, ATOMIQUE ─────────
-- won=true  → on a inséré la ligne (RUNNING) → CE process exécute OpenAI.
-- won=false → l'intent existait déjà → on renvoie son statut + result_ref pour
--             que l'appelant branche (SUCCEEDED→cache, RUNNING→202, FAILED→re-claim).
-- L'INSERT ... ON CONFLICT DO NOTHING est atomique : deux appels concurrents du
-- même intent_id → exactement UN insère (won=true), l'autre lit (won=false).
create or replace function public.claim_intent(
  p_intent_id         text,
  p_user_id           uuid,
  p_session_id        uuid,
  p_iteration         int,
  p_intent            jsonb,
  p_client_request_id text
) returns table(won boolean, status text, result_ref jsonb, reclaim_count int)
language plpgsql
as $$
begin
  insert into public.generation_intents
    (intent_id, user_id, session_id, iteration, status, intent, client_request_id, started_at)
  values
    (p_intent_id, p_user_id, p_session_id, p_iteration, 'RUNNING', p_intent, p_client_request_id, now())
  on conflict (intent_id) do nothing;

  if found then
    -- On a inséré → on gagne le claim.
    return query select true, 'RUNNING'::text, null::jsonb, 0;
    return;
  end if;

  -- Conflit → l'intent existe : renvoyer son état pour brancher.
  return query
    select false, gi.status, gi.result_ref, gi.reclaim_count
    from public.generation_intents gi
    where gi.intent_id = p_intent_id;
end;
$$;


-- ── reclaim_intent : FAILED → RUNNING, borné ─────────────────
-- Un retry délibéré du MÊME intent (échec transient). won=true si la transition
-- FAILED→RUNNING a eu lieu (encore sous la borne). FAILED_TERMINAL n'est JAMAIS
-- re-claim. Le `and status='FAILED'` rend la transition atomique vs concurrence.
create or replace function public.reclaim_intent(
  p_intent_id text,
  p_max       int
) returns table(won boolean, reclaim_count int)
language plpgsql
as $$
declare
  v_reclaim int;
begin
  -- Alias `gi` + colonnes qualifiées : `reclaim_count` est AUSSI une colonne OUT
  -- (returns table) → sans qualification, Postgres lève 42702 (ambiguïté).
  update public.generation_intents gi
     set status        = 'RUNNING',
         reclaim_count = gi.reclaim_count + 1,
         started_at    = now(),
         completed_at  = null,
         error         = null
   where gi.intent_id     = p_intent_id
     and gi.status        = 'FAILED'        -- FAILED_TERMINAL exclu (jamais re-claim)
     and gi.reclaim_count < p_max
  returning gi.reclaim_count into v_reclaim;

  if found then
    return query select true, v_reclaim;
  else
    return query
      select false, coalesce(
        (select g2.reclaim_count from public.generation_intents g2 where g2.intent_id = p_intent_id), 0);
  end if;
end;
$$;


grant execute on function public.claim_intent(text, uuid, uuid, int, jsonb, text) to service_role;
grant execute on function public.reclaim_intent(text, int) to service_role;


-- ── Sanity-check (après application) ─────────────────────────
--   select proname from pg_proc where proname in ('claim_intent','reclaim_intent');  -- 2 lignes
--
-- Test concurrence (le claim doit sérialiser) — dans une session vide :
--   select won, status from public.claim_intent('test:concurrency', <uid>, null, 1, '{}'::jsonb, 'req1');
--     -- 1re fois : won=true, status=RUNNING
--   select won, status from public.claim_intent('test:concurrency', <uid>, null, 1, '{}'::jsonb, 'req2');
--     -- 2e fois : won=false, status=RUNNING  (aucun 2e « won »)
--   -- nettoyage : delete from public.generation_intents where intent_id='test:concurrency';


-- ============================================================
-- Fin PR2a claim. Prochain : câblage /generate (branchement won/lost).
-- ============================================================
