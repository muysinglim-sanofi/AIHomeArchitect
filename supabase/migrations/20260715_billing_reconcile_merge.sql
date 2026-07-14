-- ─────────────────────────────────────────────────────────────────────────────
-- Unified Identity V1 — COMMIT 5a : RPC financier DORMANT billing_reconcile_merge
-- ─────────────────────────────────────────────────────────────────────────────
-- Cas AUTOMATIQUE UNIQUE et SÛR de la réconciliation billing A→B, quand un merge est
-- déjà en 'billing_reconciliation_pending'. Autorise le transfert AUTOMATIQUEMENT
-- seulement si, SOUS VERROU :
--   • A possède EXACTEMENT 1 pass actif ;
--   • B possède EXACTEMENT 0 pass actif ;
--   • net(pass de A) >= 0.
-- Sinon → 'billing_conflict_manual_review' (revue humaine), AUCUNE mutation financière.
--
-- Ce fichier NE modifie NI /generate NI /refine NI le worker NI RevenueCat NI
-- billing_grant_purchase. Il n'ajoute AUCUNE table, AUCUNE queue, AUCUN worker. Il est
-- DORMANT : aucun appelant ne l'invoque (le câblage fire-and-forget/sweep = Commit 5c).
--
-- Sûreté (calquée sur identity_claim_and_merge) : SECURITY DEFINER + search_path='' +
-- tout qualifié · EXECUTE service_role UNIQUEMENT · A/B dérivés EXCLUSIVEMENT de
-- identity_merges (jamais du caller) · verrous advisory A/B ordonnés (mêmes clés que
-- billing_try_hold) · garde status='billing_reconciliation_pending' · rejeu sur autre
-- statut = no-op idempotent. NB : pas de BEGIN/COMMIT (le runner enveloppe le fichier).
-- ─────────────────────────────────────────────────────────────────────────────


-- ══════════ 1) EXTENSION ADDITIVE du CHECK reference_type → autoriser 'MERGE' ══════════
-- Le ledger reste append-only (le trigger bloque UPDATE/DELETE de LIGNES, pas le DDL).
-- On DÉCOUVRE le vrai nom de contrainte (auto-généré inline) puis on la remplace par une
-- version étendue : toutes les valeurs actuelles + 'MERGE'. Aucune ligne n'est modifiée.
do $$
declare v_conname text;
begin
  select c.conname into v_conname
    from pg_catalog.pg_constraint c
   where c.conrelid = 'public.ledger_entries'::regclass
     and c.contype = 'c'
     and pg_catalog.pg_get_constraintdef(c.oid) ilike '%reference_type%';
  if v_conname is not null then
    execute format('alter table public.ledger_entries drop constraint %I', v_conname);
  end if;
end $$;

alter table public.ledger_entries
  add constraint ledger_entries_reference_type_check
  check (reference_type in ('ORDER', 'GENERATION_INTENT', 'ADMIN', 'PROMO', 'MERGE'));


-- ══════════ 2) RPC billing_reconcile_merge(p_merge_id) ══════════
create or replace function public.billing_reconcile_merge(p_merge_id uuid)
returns table (
  merge_id     uuid,
  from_user_id uuid,
  to_user_id   uuid,
  status       text,
  failure_code text,
  metadata     jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
-- Les colonnes de RETURNS TABLE deviennent des OUT homonymes ; le corps n'y accède
-- jamais par nom (il passe par v_*), donc « la colonne gagne » partout (returning/where).
#variable_conflict use_column
declare
  v_m       public.identity_merges%rowtype;
  v_a       uuid;
  v_b       uuid;
  v_first   uuid;
  v_second  uuid;
  v_cnt_a   int;
  v_cnt_b   int;
  v_pass    uuid;
  v_ends    timestamptz;
  v_net     int;
  v_fail    text;
begin
  -- 1. Charger la ligne par merge_id. A/B dérivés EXCLUSIVEMENT d'ici (jamais du caller).
  select * into v_m from public.identity_merges m where m.merge_id = p_merge_id;
  if not found then
    -- Erreur d'appel (merge inexistant) → rollback (comme identity_claim_and_merge).
    raise exception 'merge_not_found' using errcode = 'P0001';
  end if;
  v_a := v_m.from_user_id;
  v_b := v_m.to_user_id;

  -- 2. Verrous advisory A et B, ordre déterministe (mêmes clés que billing_try_hold).
  v_first  := least(v_a, v_b);
  v_second := greatest(v_a, v_b);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_first::text));
  if pg_catalog.hashtext(v_second::text) <> pg_catalog.hashtext(v_first::text) then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_second::text));
  end if;

  -- 3. Relire SOUS VERROU + garde de statut. Rejeu sur un autre statut = no-op idempotent.
  select * into v_m from public.identity_merges m where m.merge_id = p_merge_id;
  if v_m.status <> 'billing_reconciliation_pending' then
    return query
      select m.merge_id, m.from_user_id, m.to_user_id, m.status, m.failure_code, m.metadata
        from public.identity_merges m where m.merge_id = p_merge_id;
    return;
  end if;

  -- 4. Compter les passes ACTIFS (JAMAIS de LIMIT 1 : on veut détecter la multiplicité).
  select count(*) into v_cnt_a
    from public.passes p
   where p.user_id = v_a and p.status = 'ACTIVE' and now() between p.starts_at and p.ends_at;
  select count(*) into v_cnt_b
    from public.passes p
   where p.user_id = v_b and p.status = 'ACTIVE' and now() between p.starts_at and p.ends_at;

  -- 5+6. Multiplicité valide → identifier l'unique pass P de A et calculer le net.
  if v_cnt_b <> 0 then
    v_fail := 'TARGET_ALREADY_PREMIUM';
  elsif v_cnt_a <> 1 then
    v_fail := 'SOURCE_PASS_COUNT_INVALID';
  else
    select p.id, p.ends_at into v_pass, v_ends
      from public.passes p
     where p.user_id = v_a and p.status = 'ACTIVE' and now() between p.starts_at and p.ends_at;
    -- net = solde NET du bucket du pass P chez A (GRANT − HOLDs déjà consommés). >= 0 attendu.
    select coalesce(sum(l.available_delta), 0) into v_net
      from public.ledger_entries l
     where l.user_id = v_a and l.pass_id = v_pass;
    if v_net < 0 then
      v_fail := 'NET_NEGATIVE';
    end if;
  end if;

  -- 7+8. Toute situation invalide → manual_review, AUCUNE mutation financière.
  if v_fail is not null then
    update public.identity_merges m
       set status = 'billing_conflict_manual_review',
           failure_code = v_fail,
           metadata = coalesce(m.metadata, '{}'::jsonb)
                      || pg_catalog.jsonb_build_object('billing_manual_review_at', now(),
                                                       'billing_last_error_code', v_fail)
     where m.merge_id = p_merge_id;
    return query
      select m.merge_id, m.from_user_id, m.to_user_id, m.status, m.failure_code, m.metadata
        from public.identity_merges m where m.merge_id = p_merge_id;
    return;
  end if;

  -- ══════════ CAS VALIDE (v_pass, v_ends, v_net renseignés ; v_net >= 0) ══════════

  -- 9. Déplacer le PASS A→B. orders / payments / anciennes lignes ledger : INCHANGÉS.
  update public.passes set user_id = v_b, updated_at = now() where id = v_pass;

  -- Ledger CONSERVATIF : couple équilibré −net (A) / +net (B), même transaction. net=0 → aucune écriture.
  -- Aucune ligne existante mutée (INSERT only, trigger append-only respecté). ON CONFLICT = filet de rejeu.
  if v_net > 0 then
    insert into public.ledger_entries
      (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key, metadata)
    values
      (v_a, 'ADJUSTMENT', -v_net, v_pass, 'MERGE', p_merge_id::text,
       'merge:' || p_merge_id::text || ':debit',
       pg_catalog.jsonb_build_object('kind', 'merge_reconcile', 'merge_id', p_merge_id))
    on conflict (idempotency_key) do nothing;

    insert into public.ledger_entries
      (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key, metadata)
    values
      (v_b, 'ADJUSTMENT', v_net, v_pass, 'MERGE', p_merge_id::text,
       'merge:' || p_merge_id::text || ':credit',
       pg_catalog.jsonb_build_object('kind', 'merge_reconcile', 'merge_id', p_merge_id))
    on conflict (idempotency_key) do nothing;
  end if;

  -- 10. Reprojeter les wallets A et B (primitive existante, source unique = ledger).
  perform public.billing_reproject_wallet(v_a);
  perform public.billing_reproject_wallet(v_b);

  -- 11. PREMIUM LOCAL (user_roles) — sémantique existante, même transaction.
  --   B : obtient/prolonge premium borné à la fenêtre du pass. GARDE-FOU #1 — ne JAMAIS
  --       raccourcir un premium existant : si expires_at IS NULL (illimité) → rester NULL ;
  --       sinon garder la date la plus tardive (GREATEST(existant, P.ends_at)).
  insert into public.user_roles (user_id, role, granted_by, expires_at, notes)
  values (v_b, 'premium', v_b, v_ends, 'merge_reconcile:' || p_merge_id::text)
  on conflict (user_id, role) do update
    set expires_at = case
          when public.user_roles.expires_at is null then null
          else greatest(public.user_roles.expires_at, excluded.expires_at)
        end,
        notes = 'merge_reconcile:' || p_merge_id::text;

  --   A : ne doit plus conserver un premium UTILISABLE. Parité STRICTE avec _expire_premium,
  --       qui est un UPSERT (INSERT ... ON CONFLICT DO UPDATE ; crée la ligne si absente pour
  --       garder une trace lifecycle). expires_at = now() → ligne IMMÉDIATEMENT INACTIVE :
  --       _role_active exige expires_at > now(), donc now() (jamais > now() à la relecture)
  --       est inactif. Aucune autre différence de conception.
  insert into public.user_roles (user_id, role, granted_by, expires_at, notes)
  values (v_a, 'premium', v_a, now(), 'merged_out:' || p_merge_id::text)
  on conflict (user_id, role) do update
    set expires_at = now(),
        notes = 'merged_out:' || p_merge_id::text;

  -- 12. Succès : billing_reconciliation_pending → revocation_pending + métadonnées sûres.
  update public.identity_merges m
     set status = 'revocation_pending',
         failure_code = null,
         metadata = coalesce(m.metadata, '{}'::jsonb)
                    || pg_catalog.jsonb_build_object('billing_reconciled_at', now(),
                                                     'billing_transferred_net', v_net)
   where m.merge_id = p_merge_id;

  return query
    select m.merge_id, m.from_user_id, m.to_user_id, m.status, m.failure_code, m.metadata
      from public.identity_merges m where m.merge_id = p_merge_id;
  return;
end;
$$;

revoke execute on function public.billing_reconcile_merge(uuid) from public, anon, authenticated;
grant  execute on function public.billing_reconcile_merge(uuid) to service_role;
