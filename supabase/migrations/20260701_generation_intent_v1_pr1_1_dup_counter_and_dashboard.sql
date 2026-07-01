-- ============================================================
-- Generation Intent v1 — PR1.1 : compteur de DUP + dashboard d'observation
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ============================================================
--
-- Spec : docs/GENERATION_INTENT_V1_SPEC.md.
--
-- Objectif : rendre « %NEW / %DUP » et les taux de réussite/échec des
-- métriques SQL de premier ordre, pour décider OBJECTIVEMENT quand PR2 est
-- sûr (au lieu de quelques tests manuels).
--
-- ADDITIF + observation pure. Rien n'enforce, rien ne change dans /generate.
--
-- ⚠️ ORDRE DE DÉPLOIEMENT : appliquer CETTE migration AVANT (ou avec) le
-- redéploiement du backend PR1.1. Le code appelle la RPC increment_intent_fire
-- sur chaque DUP ; si la RPC n'existe pas encore, l'appel échoue (avalé,
-- best-effort) et fire_count reste à 1 jusqu'à application. Sans risque.
--
-- Rollback :
--   drop view if exists public.v_generation_jobs_daily;
--   drop view if exists public.v_generation_intent_daily;
--   drop function if exists public.increment_intent_fire(text);
--   alter table public.generation_intents drop column if exists fire_count;
-- ============================================================


-- ── fire_count ───────────────────────────────────────────────
-- Nombre de fois qu'un intent_id a été « firé » (NEW = 1 ; chaque DUP +1).
-- Permet : total_fires = sum(fire_count) ; NEW = count(*) ;
--          DUP = sum(fire_count) - count(*).

alter table public.generation_intents
  add column if not exists fire_count int not null default 1;


-- ── increment_intent_fire (RPC) ──────────────────────────────
-- UPDATE SET x = x + 1 n'est pas exprimable via PostgREST (.update() ne pose
-- que des valeurs littérales) → petite fonction. L'incrément est atomique
-- (verrou de ligne) : deux DUP concurrents comptent tous les deux.
-- SECURITY INVOKER (défaut) : le service_role a déjà les droits UPDATE.

create or replace function public.increment_intent_fire(p_intent_id text)
returns void
language sql
as $$
  update public.generation_intents
     set fire_count = fire_count + 1
   where intent_id = p_intent_id;
$$;

grant execute on function public.increment_intent_fire(text) to service_role;


-- ── Dashboard : rollup quotidien des Intents ─────────────────
-- Une ligne par jour : volume, %NEW/%DUP (GATE 2), issues des Intents.

create or replace view public.v_generation_intent_daily as
select
  (created_at at time zone 'UTC')::date              as day,
  count(*)                                            as intents,          -- lignes NEW
  sum(fire_count)                                     as fires,            -- tirs totaux (NEW + DUP)
  sum(fire_count) - count(*)                          as dup_fires,        -- duplicatas (GATE 2)
  round(100.0 * count(*) / nullif(sum(fire_count), 0), 1)                 as new_pct,
  round(100.0 * (sum(fire_count) - count(*)) / nullif(sum(fire_count), 0), 1) as dup_pct,
  count(*) filter (where status = 'SUCCEEDED')        as succeeded,
  count(*) filter (where status = 'FAILED')           as failed_transient, -- retries épuisés
  count(*) filter (where status = 'FAILED_TERMINAL')  as failed_terminal,  -- non-transient
  count(*) filter (where status = 'RUNNING')          as still_running,    -- (orphelins potentiels)
  round(100.0 * count(*) filter (where status = 'SUCCEEDED')
        / nullif(count(*), 0), 1)                     as success_pct,
  count(*) filter (where reclaim_count > 0)           as reclaimed         -- (PR2 ; 0 en PR1)
from public.generation_intents
group by 1
order by 1 desc;


-- ── Dashboard : rollup quotidien des Jobs (exécutions) ───────
-- Prouve « 1 Intent / N Jobs » + répartition transient / non_transient.

create or replace view public.v_generation_jobs_daily as
select
  (j.created_at at time zone 'UTC')::date             as day,
  count(*)                                            as jobs,
  count(distinct j.intent_id)                         as intents_with_jobs,
  round(count(*)::numeric / nullif(count(distinct j.intent_id), 0), 2)    as jobs_per_intent,
  count(*) filter (where j.status = 'SUCCEEDED')      as jobs_succeeded,
  count(*) filter (where j.status = 'FAILED' and j.error_type = 'transient')     as jobs_failed_transient,
  count(*) filter (where j.status = 'FAILED' and j.error_type = 'non_transient') as jobs_failed_terminal,
  count(*) filter (where j.status = 'RUNNING')        as jobs_still_running
from public.generation_jobs j
group by 1
order by 1 desc;


-- ── Sanity-check / lecture ───────────────────────────────────
-- Dashboard quotidien :
--   select * from public.v_generation_intent_daily;
--   select * from public.v_generation_jobs_daily;
--
-- Détail des 50 derniers Intents (gate-of-proof + N jobs) :
--   select intent_id, status, fire_count, reclaim_count,
--          (select count(*) from public.generation_jobs j
--             where j.intent_id = i.intent_id) as jobs
--   from public.generation_intents i
--   order by created_at desc
--   limit 50;
--
-- Vérifier fire_count + RPC :
--   select column_name from information_schema.columns
--     where table_name = 'generation_intents' and column_name = 'fire_count';
--   select proname from pg_proc where proname = 'increment_intent_fire';


-- ============================================================
-- Fin PR1.1 — compteur DUP + dashboard (observation pure).
-- ============================================================
