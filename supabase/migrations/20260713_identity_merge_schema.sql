-- ─────────────────────────────────────────────────────────────────────────────
-- Unified Identity V1 — COMMIT 1 : schéma de sécurité de fusion (DORMANT)
-- ─────────────────────────────────────────────────────────────────────────────
-- Crée :
--   • public.account_state            — autorité durable merged_closed + trial_ever_granted
--   • public.identity_merge_tickets   — tickets de fusion (éphémères, usage unique)
--   • public.identity_merges          — audit + machine d'état reprenable
--   • public.is_current_identity_active() — gate d'identité (sans paramètre, auth.uid() interne)
--   • RLS RESTRICTIVE additive sur sessions/messages/assets (gate merged_closed)
--   • backfill de trial_ever_granted pour les bénéficiaires historiques du trial (19 attendus)
--
-- DORMANT — ce commit NE crée AUCUN : RPC de fusion, endpoint, flag, ni écriture destructive.
--   L'enforcement merged_closed est PERMANENT mais INERTE tant qu'aucune fusion n'existe
--   (aucune ligne merged_closed=true → is_current_identity_active() renvoie true partout).
--
-- Sûreté : transactionnel · aucune donnée supprimée · ledger_entries en LECTURE SEULE (backfill)
--   · auth.users NON modifié (seul identity_merge_tickets y référence) · idempotent sur re-apply
--   (create ... if not exists / or replace / drop policy if exists / on conflict).
-- NB : PAS de BEGIN/COMMIT explicite — le runner de migration (Supabase CLI) enveloppe déjà
--   chaque fichier dans sa propre transaction. Ce fichier ne contient que du DDL/DML.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. account_state — table de sécurité durable ────────────────────────────
-- user_id = UUID PRIMARY KEY, AUCUNE FK vers auth.users : cette autorité doit SURVIVRE à toute
-- opération Auth (une suppression auth.users ne doit jamais faire disparaître l'état merged_closed).
-- Ligne ABSENTE ⇒ utilisateur ACTIF + trial jamais accordé (défauts).
create table if not exists public.account_state (
  user_id            uuid        primary key,
  merged_closed      boolean     not null default false,
  merged_into        uuid,
  trial_ever_granted boolean     not null default false,
  updated_at         timestamptz not null default now()
);

-- ── 2. identity_merge_tickets — éphémère (≈15 min), usage unique ─────────────
-- FK ON DELETE CASCADE tolérée : le ticket est jetable et aucune fusion n'a encore eu lieu.
-- ticket_hash = sha256(brut) ; le ticket brut n'est JAMAIS stocké.
create table if not exists public.identity_merge_tickets (
  ticket_hash   text        primary key,
  from_user_id  uuid        not null references auth.users(id) on delete cascade,
  expires_at    timestamptz not null,
  consumed_at   timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists identity_merge_tickets_from_user_idx
  on public.identity_merge_tickets(from_user_id);

-- ── 3. identity_merges — audit + machine d'état (doit SURVIVRE) ──────────────
-- from_user_id / to_user_id = UUID NUS, AUCUNE FK vers auth.users (l'audit ne doit jamais
-- être effacé par une opération Auth). Pas de contrainte UNIQUE globale sur from_user_id
-- (voir l'index unique PARTIEL plus bas).
create table if not exists public.identity_merges (
  merge_id      uuid        primary key default gen_random_uuid(),
  from_user_id  uuid        not null,
  to_user_id    uuid        not null,
  status        text        not null
                 check (status in (
                   'running',
                   'waiting_for_settlement',
                   'data_merged',
                   'billing_reconciliation_pending',
                   'billing_conflict_manual_review',
                   'revocation_pending',
                   'completed',
                   'failed',
                   'conflict',
                   'abandoned'
                 )),
  ticket_hash   text,
  started_at    timestamptz not null default now(),
  completed_at  timestamptz,
  failure_code  text,
  metadata      jsonb       not null default '{}'
);

-- UNE seule tentative BLOQUANTE par source. conflict/failed/abandoned sont HORS de l'index
-- → une nouvelle tentative pour A est permise après eux (nouveau merge_id, audit conservé).
-- 'completed' reste DANS l'index → une identité déjà fusionnée ne pourra JAMAIS redémarrer
-- une fusion, même en cas de bug applicatif.
create unique index if not exists identity_merges_one_blocking_attempt_per_source
  on public.identity_merges(from_user_id)
  where status in (
    'running',
    'waiting_for_settlement',
    'data_merged',
    'billing_reconciliation_pending',
    'billing_conflict_manual_review',
    'revocation_pending',
    'completed'
  );

create index if not exists identity_merges_to_user_idx
  on public.identity_merges(to_user_id);

-- Index partiel de REPRISE (reconcile idempotent des opérations non terminées).
create index if not exists identity_merges_resume_idx
  on public.identity_merges(status)
  where status in (
    'revocation_pending',
    'billing_reconciliation_pending',
    'billing_conflict_manual_review'
  );

-- ── 4. RLS des 3 nouvelles tables — service_role uniquement ──────────────────
alter table public.account_state          enable row level security;
alter table public.identity_merge_tickets enable row level security;
alter table public.identity_merges        enable row level security;

-- Aucune policy client → anon/authenticated n'ont AUCUN accès. On retire aussi les GRANTs.
revoke all on table public.account_state          from anon, authenticated;
revoke all on table public.identity_merge_tickets from anon, authenticated;
revoke all on table public.identity_merges        from anon, authenticated;

-- Le backend agit en service_role (bypass RLS) ; grants explicites (moindre privilège, pas de DELETE).
grant select, insert, update on table public.account_state          to service_role;
grant select, insert, update on table public.identity_merge_tickets to service_role;
grant select, insert, update on table public.identity_merges        to service_role;

-- ── 5. is_current_identity_active() — gate d'identité ────────────────────────
-- SANS paramètre (empêche un authenticated d'interroger l'état d'un autre UUID) : lit auth.uid()
-- en interne. SECURITY DEFINER + search_path='' + références entièrement qualifiées.
-- Ligne account_state absente ⇒ true (actif). false UNIQUEMENT si merged_closed=true.
create or replace function public.is_current_identity_active()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (
    select 1
      from public.account_state
     where user_id = auth.uid()
       and merged_closed = true
  );
$$;

revoke execute on function public.is_current_identity_active() from public;
revoke execute on function public.is_current_identity_active() from anon;
grant  execute on function public.is_current_identity_active() to authenticated, service_role;

-- ── 6. RLS additive sur sessions/messages/assets — gate merged_closed ────────
-- Policies RESTRICTIVE : AND-combinées aux policies PERMISSIVE "owner access" existantes.
-- On n'écrit NULLE PART la condition auth.uid()=user_id (jamais restatée/regressée) — la
-- restrictive n'ajoute QUE le conjoint is_current_identity_active(), en USING ET WITH CHECK.
-- Effet : accès accordé ssi (owner access existant) AND (identité active). service_role bypass RLS.
drop policy if exists "sessions: active identity only" on public.sessions;
create policy "sessions: active identity only"
  on public.sessions as restrictive for all
  using       (public.is_current_identity_active())
  with check  (public.is_current_identity_active());

drop policy if exists "messages: active identity only" on public.messages;
create policy "messages: active identity only"
  on public.messages as restrictive for all
  using       (public.is_current_identity_active())
  with check  (public.is_current_identity_active());

drop policy if exists "assets: active identity only" on public.assets;
create policy "assets: active identity only"
  on public.assets as restrictive for all
  using       (public.is_current_identity_active())
  with check  (public.is_current_identity_active());

-- ── 7. Backfill trial_ever_granted (bénéficiaires historiques du trial) ──────
-- Marqueur AUTORITAIRE = idempotency_key LIKE 'trial:%' (JAMAIS entry_type). Lecture seule de
-- ledger_entries. Aucun crédit gratuit transféré : on ne propage que l'INÉLIGIBILITÉ historique.
-- Attendu : 19 lignes trial_ever_granted=true.
insert into public.account_state (user_id, trial_ever_granted)
select distinct user_id, true
  from public.ledger_entries
 where idempotency_key like 'trial:%'
   and available_delta > 0
on conflict (user_id) do update
  set trial_ever_granted = public.account_state.trial_ever_granted or excluded.trial_ever_granted,
      updated_at         = now();
