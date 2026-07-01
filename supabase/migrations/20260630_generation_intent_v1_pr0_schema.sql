-- ============================================================
-- Generation Intent v1 — PR0 : schéma dormant
-- Paste into: Supabase Dashboard → SQL Editor → Run
-- ============================================================
--
-- Spec : docs/GENERATION_INTENT_V1_SPEC.md (§5 data model, §13 plan PR0).
--
-- ADDITIVE ONLY + DORMANT. Crée deux nouvelles tables
-- (generation_intents, generation_jobs) et ajoute UNE colonne
-- nullable (intent_id) à usage_log. AUCUN code applicatif ne lit ni
-- n'écrit ces objets à ce stade (PR0). Zéro impact runtime : le
-- chemin /generate est INCHANGÉ tant que PR1 n'est pas déployé.
--
-- Ontologie (spec §1) :
--   INTENT = ce que veut l'utilisateur — durable, déterministe,
--            FACTURABLE. Clé = intent_id (hash déterministe, calculé
--            backend, voir spec §2.1). 1 Intent = au plus 1 débit.
--   JOB    = une exécution technique (une tentative, 1 appel OpenAI).
--            1..N Jobs par Intent. Observabilité / audit coût.
--
-- Sûr à appliquer sur données live ; sûr à révoquer via DROP TABLE
-- sans affecter aucun autre état.
--
-- Rollback :
--   alter table public.usage_log drop column if exists intent_id;
--   drop table if exists public.generation_jobs;
--   drop trigger if exists trg_generation_intents_updated_at on public.generation_intents;
--   drop function if exists public.generation_intents_set_updated_at();
--   drop table if exists public.generation_intents;
-- ============================================================


-- ── generation_intents ───────────────────────────────────────
-- Source de vérité de l'intention. Le claim atomique de PR2 fera :
--   INSERT INTO generation_intents (intent_id, ...) ON CONFLICT DO NOTHING
-- ce qui ferme GATE 2 (course concurrente / re-acceptation backend).
-- PR0 ne crée que la structure ; rien n'écrit encore.
--
-- session_id est NULLABLE : lors de la 1re génération le client passe
-- session_id='new' (non-uuid) ; au write (PR1) on mappera 'new' → NULL
-- jusqu'à ce que la session ait un uuid réel.

create table if not exists public.generation_intents (
  intent_id          text        primary key,
  user_id            uuid        not null references auth.users(id) on delete cascade,
  session_id         uuid        references public.sessions(id) on delete set null,
  iteration          int,
  status             text        not null
                                 check (status in ('RUNNING', 'SUCCEEDED', 'FAILED', 'FAILED_TERMINAL'))
                                 default 'RUNNING',
  intent             jsonb,      -- {room, atmosphere, mode, source_mode, src_sha1, revision}
  result_ref         jsonb,      -- à SUCCEEDED : {message_id, after_image_url, versions, structural_identity}
  error              jsonb,      -- à FAILED : {type, message}
  reclaim_count      int         not null default 0
                                 check (reclaim_count >= 0),   -- borne anti-boucle (GJ-OD-2 : MAX=3 en logique métier)
  client_request_id  text,       -- corrélation log (ancienne clé d'idempotence)
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  started_at         timestamptz,
  completed_at       timestamptz
);

-- Indexes
-- generation_intents_user_idx        — "intents de cet utilisateur"
-- generation_intents_session_idx     — réconciliation par session
-- generation_intents_status_idx      — worker stuck-intents (RUNNING > JOB_TIMEOUT)

create index if not exists generation_intents_user_idx
  on public.generation_intents(user_id);

create index if not exists generation_intents_session_idx
  on public.generation_intents(session_id);

create index if not exists generation_intents_status_idx
  on public.generation_intents(status, started_at)
  where status = 'RUNNING';

-- RLS — l'utilisateur lit SES intents (PR3 : endpoint statut + UI).
-- INSERT/UPDATE/DELETE = service-role uniquement (le backend écrit ;
-- le client Flutter n'écrit jamais).

alter table public.generation_intents enable row level security;

drop policy if exists "generation_intents: owner read" on public.generation_intents;
create policy "generation_intents: owner read"
  on public.generation_intents
  for select
  using (auth.uid() = user_id);

-- updated_at automatique sur chaque UPDATE (transitions RUNNING→SUCCEEDED,
-- re-claim, réparation…). Simplifie debug + workers de réconciliation :
-- l'âge d'une transition est toujours lisible sans dépendre du writer.

create or replace function public.generation_intents_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_generation_intents_updated_at on public.generation_intents;
create trigger trg_generation_intents_updated_at
  before update on public.generation_intents
  for each row
  execute function public.generation_intents_set_updated_at();


-- ── generation_jobs ──────────────────────────────────────────
-- Journal des exécutions techniques. Une ligne par tentative
-- (la boucle de retry interne max(profile.max_attempts, 2) en crée
-- plusieurs sous le même Intent). Porte le coût OpenAI RÉEL pour
-- l'audit — ce n'est PAS la facturation (la facturation = le ledger
-- Billing keyé sur intent_id). Prouve « 1 Intent / N Jobs / 1 débit ».

create table if not exists public.generation_jobs (
  job_id             uuid        primary key default gen_random_uuid(),
  intent_id          text        not null references public.generation_intents(intent_id) on delete cascade,
  attempt_no         int         not null,
  status             text        not null
                                 check (status in ('RUNNING', 'SUCCEEDED', 'FAILED'))
                                 default 'RUNNING',
  openai_request_id  text,
  cost_usd_estimate  numeric(10, 4),   -- coût réel de CETTE tentative (audit, ≠ facturation)
  error_type         text        check (error_type in ('transient', 'non_transient')),
  started_at         timestamptz,
  ended_at           timestamptz,
  created_at         timestamptz not null default now(),
  -- une seule ligne par (Intent, numéro de tentative) : empêche qu'un
  -- retry crée deux Jobs identiques (attempt_no NOT NULL → la contrainte
  -- mord vraiment, les NULL étant distincts en Postgres).
  unique (intent_id, attempt_no)
);

create index if not exists generation_jobs_intent_idx
  on public.generation_jobs(intent_id);

-- RLS — lecture via le parent Intent (l'utilisateur ne voit que les
-- jobs de ses propres intents). Écritures service-role uniquement.

alter table public.generation_jobs enable row level security;

drop policy if exists "generation_jobs: owner read" on public.generation_jobs;
create policy "generation_jobs: owner read"
  on public.generation_jobs
  for select
  using (
    exists (
      select 1 from public.generation_intents gi
      where gi.intent_id = generation_jobs.intent_id
        and gi.user_id = auth.uid()
    )
  );


-- ── usage_log.intent_id (GJ-OD-5) ────────────────────────────
-- Aligne le ledger free-tier/quota existant (reserve/confirm/fail)
-- sur l'identité durable. Nullable + dormant en PR0 ; l'étape Billing
-- branchera reserve/commit/release dessus. Pas de FK dur ici (les
-- lignes usage_log historiques n'ont pas d'intent_id).

alter table public.usage_log
  add column if not exists intent_id text;

create index if not exists usage_log_intent_idx
  on public.usage_log(intent_id)
  where intent_id is not null;


-- ── Table-level privilege grants ─────────────────────────────
-- Comme pour Wave 5.17b : RLS filtre les lignes mais NE donne PAS le
-- privilège table-level. On accorde explicitement.
--
-- - service_role (backend) : SELECT/INSERT/UPDATE pour gérer le
--   lifecycle Intent + Job (claim, transitions, réconciliation).
-- - authenticated (client, filtré RLS) : SELECT pour lire ses intents
--   (PR3 : ré-attachement + endpoint statut).
-- - anon : RIEN.

grant select, insert, update on public.generation_intents to service_role;
grant select, insert, update on public.generation_jobs    to service_role;

grant select on public.generation_intents to authenticated;
grant select on public.generation_jobs    to authenticated;


-- ── Sanity-check queries ─────────────────────────────────────
-- À coller après application pour vérifier la forme :
--
--   select count(*) as intents from public.generation_intents;   -- attendu : 0
--   select count(*) as jobs    from public.generation_jobs;       -- attendu : 0
--   select column_name from information_schema.columns
--     where table_name = 'usage_log' and column_name = 'intent_id'; -- attendu : 1 ligne
--
-- Vérifier RLS activé :
--   select relname, relrowsecurity from pg_class
--     where relname in ('generation_intents', 'generation_jobs');  -- relrowsecurity = true
--
-- Vérifier le trigger updated_at + la contrainte d'unicité :
--   select tgname from pg_trigger
--     where tgrelid = 'public.generation_intents'::regclass
--       and not tgisinternal;                                       -- trg_generation_intents_updated_at
--   select conname from pg_constraint
--     where conrelid = 'public.generation_jobs'::regclass
--       and contype = 'u';                                          -- unique (intent_id, attempt_no)


-- ============================================================
-- Fin PR0 — Generation Intent v1 (schéma dormant).
-- Prochain : PR1 (intent_id en observation pure, aucun changement
-- de comportement — voir docs/GENERATION_INTENT_V1_SPEC.md §13).
-- ============================================================
