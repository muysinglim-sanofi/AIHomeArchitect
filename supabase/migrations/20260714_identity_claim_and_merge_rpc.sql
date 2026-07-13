-- ─────────────────────────────────────────────────────────────────────────────
-- Unified Identity V1 — COMMIT 2 : RPC atomique identity_claim_and_merge
-- ─────────────────────────────────────────────────────────────────────────────
-- Fusionne les données NON-financières de A (anonyme) vers B (permanent), ferme A
-- (account_state.merged_closed), classe le billing, et pilote la machine d'état.
-- NE TOUCHE NI passes NI ledger payé (Commit 5). NE fait PAS la révocation Auth (Commit 3).
--
-- Sûreté : SECURITY DEFINER + search_path='' + tout qualifié · EXECUTE service_role UNIQUEMENT.
-- Locks = mêmes clés que billing_try_hold : pg_advisory_xact_lock(hashtext(user_id::text)).
-- Résultats MÉTIER (conflict/waiting/manual_review/…) = écrits + retournés, jamais d'exception.
-- Exceptions (rollback) : ticket inexistant/expiré/consommé-incohérent/source-changée.
-- NB : pas de BEGIN/COMMIT explicite (le runner enveloppe le fichier dans une transaction).
-- ─────────────────────────────────────────────────────────────────────────────

-- Index UNIQUE partiel : un ticket ⇒ au plus une ligne identity_merges (Correction 2.1 #1).
-- (Porte sur une table du Commit 1 ; ajouté ici pour garder Commit 1 figé.)
create unique index if not exists identity_merges_ticket_hash_unique
  on public.identity_merges(ticket_hash)
  where ticket_hash is not null;

-- ── Helper : code de précondition (ou NULL si tout est valide) ────────────────
-- Réutilisé au PREMIER claim (p_current_merge=NULL) et à la REPRISE (p_current_merge=merge courant).
create or replace function public.identity_merge_precondition_code(
  p_a uuid, p_b uuid, p_current_merge uuid
) returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_blocking     text[] := array['running','waiting_for_settlement','data_merged',
    'billing_reconciliation_pending','billing_conflict_manual_review','revocation_pending','completed'];
  v_non_terminal text[] := array['running','waiting_for_settlement','data_merged',
    'billing_reconciliation_pending','billing_conflict_manual_review','revocation_pending'];
  v_a_anon boolean;
  v_b_anon boolean;
begin
  if not exists (select 1 from auth.users u where u.id = p_a) then return 'a_not_found'; end if;
  if not exists (select 1 from auth.users u where u.id = p_b) then return 'b_not_found'; end if;
  if p_a = p_b then return 'same_user'; end if;

  select u.is_anonymous into v_a_anon from auth.users u where u.id = p_a;
  select u.is_anonymous into v_b_anon from auth.users u where u.id = p_b;
  if v_a_anon is not true then return 'a_not_anonymous'; end if;   -- A doit être anonyme
  if v_b_anon is true      then return 'b_anonymous';    end if;   -- B doit être permanent

  if exists (select 1 from public.account_state s where s.user_id = p_a and s.merged_closed) then
    return 'a_merged_closed'; end if;
  if exists (select 1 from public.account_state s where s.user_id = p_b and s.merged_closed) then
    return 'b_merged_closed'; end if;

  -- cycle : B→A déjà bloquant (le plus spécifique)
  if exists (select 1 from public.identity_merges m
              where m.from_user_id = p_b and m.to_user_id = p_a and m.status = any(v_blocking)) then
    return 'cycle'; end if;
  -- B est SOURCE d'un merge bloquant
  if exists (select 1 from public.identity_merges m
              where m.from_user_id = p_b and m.status = any(v_blocking)) then
    return 'b_has_blocking_merge'; end if;
  -- A ou B est DESTINATION d'un autre merge NON terminal (hors merge courant)
  if exists (select 1 from public.identity_merges m
              where m.merge_id is distinct from p_current_merge
                and m.to_user_id in (p_a, p_b) and m.status = any(v_non_terminal)) then
    return 'unresolved_chain'; end if;

  return null;
end;
$$;

revoke execute on function public.identity_merge_precondition_code(uuid, uuid, uuid) from public, anon, authenticated;
grant  execute on function public.identity_merge_precondition_code(uuid, uuid, uuid) to service_role;

-- ── RPC principal ─────────────────────────────────────────────────────────────
create or replace function public.identity_claim_and_merge(
  p_ticket_hash text, p_to_user uuid
) returns table (
  merge_id     uuid,
  from_user_id uuid,
  to_user_id   uuid,
  status       text,
  started_at   timestamptz,
  completed_at timestamptz,
  failure_code text,
  metadata     jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
-- Les colonnes de RETURNS TABLE (merge_id, status, from_user_id…) deviennent des variables
-- OUT qui masqueraient les colonnes homonymes. Le corps ne lit/écrit jamais ces OUT par leur
-- nom (il passe par v_*) → « colonne gagne » est exact partout (returning/where sur identity_merges).
#variable_conflict use_column
declare
  v_blocking  text[] := array['running','waiting_for_settlement','data_merged',
    'billing_reconciliation_pending','billing_conflict_manual_review','revocation_pending','completed'];
  v_a         uuid;
  v_a2        uuid;
  v_consumed  timestamptz;
  v_expires   timestamptz;
  v_m         public.identity_merges%rowtype;
  v_ex        public.identity_merges%rowtype;
  v_found     boolean;
  v_merge_id  uuid;
  v_resume    boolean := false;
  v_first     uuid;
  v_second    uuid;
  v_settle    boolean;
  v_prem_a    boolean;
  v_prem_b    boolean;
  v_trial_a   boolean;
  v_code      text;
  v_final     text;
begin
  -- 1. Lecture initiale du ticket (sans lock) → dérive A
  select t.from_user_id into v_a
    from public.identity_merge_tickets t where t.ticket_hash = p_ticket_hash;
  if not found then
    raise exception 'ticket_not_found' using errcode = 'P0001';
  end if;

  -- 2. Locks individuels ordonnés (identiques à billing_try_hold)
  v_first  := least(v_a, p_to_user);
  v_second := greatest(v_a, p_to_user);
  perform pg_advisory_xact_lock(hashtext(v_first::text));
  if hashtext(v_second::text) <> hashtext(v_first::text) then
    perform pg_advisory_xact_lock(hashtext(v_second::text));
  end if;

  -- 3. Relecture du ticket FOR UPDATE + garde TOCTOU (invariant #2)
  select t.from_user_id, t.consumed_at, t.expires_at
    into v_a2, v_consumed, v_expires
    from public.identity_merge_tickets t
   where t.ticket_hash = p_ticket_hash
   for update;
  if not found then
    raise exception 'ticket_source_changed' using errcode = 'P0001';
  end if;
  if v_a2 <> v_a then
    raise exception 'ticket_source_changed' using errcode = 'P0001';
  end if;

  -- 4. Lookup merge par ticket_hash (AVANT le contrôle expires_at)
  select * into v_m from public.identity_merges m where m.ticket_hash = p_ticket_hash;
  v_found := found;
  if v_found then
    if v_m.to_user_id <> p_to_user then
      raise exception 'ticket_consumed_mismatch' using errcode = 'P0001';
    end if;
    if v_m.status in ('running','waiting_for_settlement') then
      -- Reprise : normaliser consumed_at à NULL (invariant #4) et rejouer TOUT (invariant #1)
      update public.identity_merge_tickets
         set consumed_at = null
       where ticket_hash = p_ticket_hash and consumed_at is not null;
      v_merge_id := v_m.merge_id;
      v_resume   := true;
      -- (chute vers EXECUTE)
    else
      -- Terminal / pending-final : retour idempotent + auto-réparation consumed_at (invariant #3)
      update public.identity_merge_tickets
         set consumed_at = coalesce(consumed_at, now())
       where ticket_hash = p_ticket_hash;
      return query
        select m.merge_id, m.from_user_id, m.to_user_id, m.status,
               m.started_at, m.completed_at, m.failure_code, m.metadata
          from public.identity_merges m where m.merge_id = v_m.merge_id;
      return;
    end if;
  else
    -- 5. Aucun merge pour ce ticket → premier claim
    if v_consumed is not null then
      raise exception 'ticket_consumed_without_merge' using errcode = 'P0001';
    end if;
    if v_expires <= now() then
      raise exception 'ticket_expired' using errcode = 'P0001';
    end if;

    -- 6. Ligne BLOCKING existante pour A (autre ticket) → NOUVELLE conflict (jamais de mutation)
    select * into v_ex
      from public.identity_merges m
     where m.from_user_id = v_a
       and m.status = any(v_blocking)
       and m.ticket_hash is distinct from p_ticket_hash   -- invariant #3 (nullable-safe)
     limit 1;
    if found then
      v_code := case when v_ex.to_user_id = p_to_user then 'duplicate_merge_attempt' else 'target_mismatch' end;
      insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash, failure_code, completed_at, metadata)
      values (v_a, p_to_user, 'conflict', p_ticket_hash, v_code, now(),
              jsonb_build_object('existing_merge_id', v_ex.merge_id))
      returning merge_id into v_merge_id;
      update public.identity_merge_tickets set consumed_at = now() where ticket_hash = p_ticket_hash;
      return query
        select m.merge_id, m.from_user_id, m.to_user_id, m.status,
               m.started_at, m.completed_at, m.failure_code, m.metadata
          from public.identity_merges m where m.merge_id = v_merge_id;
      return;
    end if;

    -- 7. Préconditions → NOUVELLE conflict si violation
    v_code := public.identity_merge_precondition_code(v_a, p_to_user, null);
    if v_code is not null then
      insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash, failure_code, completed_at, metadata)
      values (v_a, p_to_user, 'conflict', p_ticket_hash, v_code, now(), '{}'::jsonb)
      returning merge_id into v_merge_id;
      update public.identity_merge_tickets set consumed_at = now() where ticket_hash = p_ticket_hash;
      return query
        select m.merge_id, m.from_user_id, m.to_user_id, m.status,
               m.started_at, m.completed_at, m.failure_code, m.metadata
          from public.identity_merges m where m.merge_id = v_merge_id;
      return;
    end if;

    -- 8. INSERT running (l'index partiel from_user_id sérialise la concurrence)
    insert into public.identity_merges(from_user_id, to_user_id, status, ticket_hash)
    values (v_a, p_to_user, 'running', p_ticket_hash)
    returning merge_id into v_merge_id;
    v_resume := false;
  end if;

  -- ═══════════ EXECUTE (étapes 9-14) — atteint par : reprise running/waiting OU premier claim ══════════

  -- (invariant #1) Reprise : REFAIRE toutes les préconditions ; échec ⇒ la ligne courante → conflict
  if v_resume then
    v_code := public.identity_merge_precondition_code(v_a, p_to_user, v_merge_id);
    if v_code is not null then
      update public.identity_merges
         set status = 'conflict', failure_code = v_code, completed_at = now()
       where merge_id = v_merge_id;
      update public.identity_merge_tickets set consumed_at = now() where ticket_hash = p_ticket_hash;
      return query
        select m.merge_id, m.from_user_id, m.to_user_id, m.status,
               m.started_at, m.completed_at, m.failure_code, m.metadata
          from public.identity_merges m where m.merge_id = v_merge_id;
      return;
    end if;
  end if;

  -- 9. Gate settlement : intent RUNNING OU HOLD non soldé (même user + même intent) sur A ou B
  select
    exists (select 1 from public.generation_intents gi
              where gi.user_id in (v_a, p_to_user) and gi.status = 'RUNNING')
    or exists (
      select 1 from public.ledger_entries h
       where h.user_id in (v_a, p_to_user)
         and h.entry_type = 'HOLD' and h.reference_type = 'GENERATION_INTENT'
         and not exists (
           select 1 from public.ledger_entries s
            where s.user_id = h.user_id
              and s.reference_type = 'GENERATION_INTENT'
              and s.reference_id = h.reference_id
              and s.entry_type in ('COMMIT','RELEASE')
              and s.idempotency_key in ('commit:'||h.reference_id, 'release:'||h.reference_id)))
    into v_settle;
  if v_settle then
    update public.identity_merges
       set status = 'waiting_for_settlement', failure_code = 'settlement_active'
     where merge_id = v_merge_id;
    -- ticket NON consommé (rejouable)
    return query
      select m.merge_id, m.from_user_id, m.to_user_id, m.status,
             m.started_at, m.completed_at, m.failure_code, m.metadata
        from public.identity_merges m where m.merge_id = v_merge_id;
    return;
  end if;

  -- 10. Classification premium (pass actif)
  select exists (select 1 from public.passes p
                  where p.user_id = v_a and p.status = 'ACTIVE' and now() between p.starts_at and p.ends_at)
    into v_prem_a;
  select exists (select 1 from public.passes p
                  where p.user_id = p_to_user and p.status = 'ACTIVE' and now() between p.starts_at and p.ends_at)
    into v_prem_b;
  if v_prem_a and v_prem_b then
    update public.identity_merges
       set status = 'billing_conflict_manual_review', failure_code = 'both_users_premium'
     where merge_id = v_merge_id;
    update public.identity_merge_tickets set consumed_at = now() where ticket_hash = p_ticket_hash;
    -- AUCUN déplacement ; A reste actif
    return query
      select m.merge_id, m.from_user_id, m.to_user_id, m.status,
             m.started_at, m.completed_at, m.failure_code, m.metadata
        from public.identity_merges m where m.merge_id = v_merge_id;
    return;
  end if;

  -- 11. Déplacement NON-financier (jamais user_roles/orders/passes/ledger_entries)
  update public.sessions            set user_id = p_to_user where user_id = v_a;
  update public.usage_log           set user_id = p_to_user where user_id = v_a;
  update public.generation_intents  set user_id = p_to_user where user_id = v_a;
  update public.device_tokens       set user_id = p_to_user, updated_at = now() where user_id = v_a;
  update public.promo_redemptions pr set user_id = p_to_user
   where pr.user_id = v_a
     and not exists (select 1 from public.promo_redemptions r2
                      where r2.user_id = p_to_user and r2.promo_code_id = pr.promo_code_id);

  -- 12. Propager l'inéligibilité trial (jamais additionner de crédits)
  select coalesce(s.trial_ever_granted, false) into v_trial_a
    from public.account_state s where s.user_id = v_a;
  insert into public.account_state(user_id, trial_ever_granted)
  values (p_to_user, coalesce(v_trial_a, false))
  on conflict (user_id) do update
    set trial_ever_granted = public.account_state.trial_ever_granted or excluded.trial_ever_granted,
        updated_at = now();

  -- 13. Fermer A (ne touche PAS trial_ever_granted(A))
  insert into public.account_state(user_id, merged_closed, merged_into)
  values (v_a, true, p_to_user)
  on conflict (user_id) do update
    set merged_closed = true, merged_into = p_to_user, updated_at = now();

  -- 14. Statut final + consommation ticket
  v_final := case when v_prem_a then 'billing_reconciliation_pending' else 'revocation_pending' end;
  update public.identity_merges set status = v_final, failure_code = null where merge_id = v_merge_id;
  update public.identity_merge_tickets set consumed_at = now() where ticket_hash = p_ticket_hash;
  return query
    select m.merge_id, m.from_user_id, m.to_user_id, m.status,
           m.started_at, m.completed_at, m.failure_code, m.metadata
      from public.identity_merges m where m.merge_id = v_merge_id;
  return;
end;
$$;

revoke execute on function public.identity_claim_and_merge(text, uuid) from public, anon, authenticated;
grant  execute on function public.identity_claim_and_merge(text, uuid) to service_role;
