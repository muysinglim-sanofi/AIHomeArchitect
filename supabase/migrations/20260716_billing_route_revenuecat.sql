-- ─────────────────────────────────────────────────────────────────────────────
-- Unified Identity V1 — COMMIT 5b : routage RevenueCat SÛR et DORMANT
-- ─────────────────────────────────────────────────────────────────────────────
-- Empêche qu'un événement RevenueCat TARDIF crédite/modifie l'ancien compte A après un
-- merge A→B. La décision « A ou B » est prise EXCLUSIVEMENT en SQL, SOUS VERROU, dans la
-- MÊME transaction que l'écriture (jamais décidée en Python puis rejouée après attente).
--
-- 3 fonctions, toutes SECURITY DEFINER + search_path='' + service_role UNIQUEMENT :
--   • billing_route_target(original)        — prélecture hint, verrous advisory {A,B}
--       ordonnés, RELECTURE SOUS VERROU, décision (autorité). V1 = UN SEUL saut A→B.
--   • billing_grant_purchase_routed(...)    — événements de CRÉDIT (INITIAL_PURCHASE/RENEWAL) :
--       route → billing_grant_purchase(cible) + rôle premium, MÊME transaction.
--   • billing_route_role_apply(...)         — grant de rôle seul / expiration : route → user_roles.
--
-- Réutilise les MÊMES clés de verrou que billing_try_hold / identity_claim_and_merge /
-- billing_reconcile_merge : pg_advisory_xact_lock(hashtext(user_id::text)).
-- Ne touche NI les anciennes lignes ledger, NI auth.users, NI le webhook (ça = Python).
-- DORMANT : aucun appelant SQL ; le webhook Python les appellera (câblage séparé).
-- NB : pas de BEGIN/COMMIT (le runner enveloppe le fichier dans une transaction).
-- ─────────────────────────────────────────────────────────────────────────────


-- ══════════ 1) Résolveur de cible sous verrou (autorité) ══════════
-- Codes retournés :
--   active               → cible=original (non fusionné : ligne absente OU merged_closed=false)
--   pending_stay_a       → cible=A (merge en billing_reconciliation_pending ; 5a transférera)
--   routed_to_b          → cible=B (merge revocation_pending/completed, B valide, single-hop)
--   manual_no_target     → A fermé mais merged_into NULL
--   manual_no_merge      → A fermé mais aucune ligne merge (from=A → merged_into)
--   manual_target_missing→ B absent de auth.users
--   manual_target_closed → B lui-même merged_closed (chaîne A→B→C ou B fermé) — V1 ne suit pas
--   manual_merge_status  → statut conflict/manual_review/running/autre
create or replace function public.billing_route_target(p_original uuid)
returns table (target uuid, routing_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hint_closed boolean;
  v_hint_into   uuid;
  v_closed      boolean;
  v_into        uuid;
  v_first       uuid;
  v_second      uuid;
  v_status      text;
  v_b_closed    boolean;
begin
  -- Prélecture (HINT de verrouillage) — JAMAIS l'autorité. Sert UNIQUEMENT à choisir
  -- l'ensemble d'identités à verrouiller.
  select s.merged_closed, s.merged_into into v_hint_closed, v_hint_into
    from public.account_state s where s.user_id = p_original;

  -- Verrous advisory sur l'ensemble déterminé par le HINT : {original} + {hint_into si fusionné}.
  if v_hint_closed is true and v_hint_into is not null then
    v_first  := least(p_original, v_hint_into);
    v_second := greatest(p_original, v_hint_into);
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_first::text));
    if pg_catalog.hashtext(v_second::text) <> pg_catalog.hashtext(v_first::text) then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(v_second::text));
    end if;
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_original::text));
  end if;

  -- RELECTURE SOUS VERROU = AUTORITÉ.
  select s.merged_closed, s.merged_into into v_closed, v_into
    from public.account_state s where s.user_id = p_original;

  -- ── GARDE DE RACE : si l'état (merged_closed / merged_into) a CHANGÉ entre la prélecture
  --    et l'acquisition des verrous (ex. le merge s'est terminé entre-temps), l'ensemble
  --    verrouillé ne couvre peut-être pas la vraie cible B → on ne route JAMAIS vers une
  --    identité non verrouillée. AUCUNE écriture ; erreur transitoire 40001 → le webhook
  --    renvoie 503 → RevenueCat réessaie ; au nouvel essai la prélecture verra B et
  --    verrouillera A+B. Ce n'est PAS un manual_review (course temporaire, pas ambiguïté).
  if v_closed is distinct from v_hint_closed or v_into is distinct from v_hint_into then
    raise exception 'ROUTING_CHANGED_RETRY' using errcode = '40001';
  end if;

  if v_closed is not true then
    return query select p_original, 'active'::text; return;
  end if;
  if v_into is null then
    return query select null::uuid, 'manual_no_target'::text; return;
  end if;

  -- Tentative A→B LA PLUS RÉCENTE (TOUS statuts), PUIS interprétation. « Le statut le plus
  -- récent gagne » : on n'ignore JAMAIS une ligne récente billing_conflict_manual_review /
  -- conflict au profit d'une ANCIENNE revocation_pending/completed. Tie-break déterministe
  -- par merge_id. Interprétation ci-dessous : pending→A, revocation/completed→B, TOUT le
  -- reste (conflict / billing_conflict_manual_review / failed / abandoned / running /
  -- waiting_for_settlement / data_merged) → manual_review (aucun crédit auto sur ambiguïté).
  -- NB : l'index unique partiel identity_merges_one_blocking_attempt_per_source garantit AU
  -- PLUS UNE ligne à statut BLOQUANT par source (donc completed et billing_conflict_manual_
  -- review ne coexistent jamais) ; les lignes terminales conflict/failed/abandoned peuvent
  -- s'ajouter, et « le plus récent gagne » les traite en manual_review si elles sont en tête.
  select m.status into v_status
    from public.identity_merges m
   where m.from_user_id = p_original and m.to_user_id = v_into
   order by m.started_at desc, m.merge_id desc
   limit 1;

  if v_status is null then
    return query select null::uuid, 'manual_no_merge'::text; return;
  end if;
  if v_status = 'billing_reconciliation_pending' then
    return query select p_original, 'pending_stay_a'::text; return;   -- grant reste sur A
  end if;
  if v_status in ('revocation_pending', 'completed') then
    if not exists (select 1 from auth.users u where u.id = v_into) then
      return query select null::uuid, 'manual_target_missing'::text; return;
    end if;
    select s2.merged_closed into v_b_closed
      from public.account_state s2 where s2.user_id = v_into;
    if v_b_closed is true then
      return query select null::uuid, 'manual_target_closed'::text; return;  -- chaîne/B fermé
    end if;
    return query select v_into, 'routed_to_b'::text; return;
  end if;

  return query select null::uuid, 'manual_merge_status'::text; return;
end;
$$;

revoke execute on function public.billing_route_target(uuid) from public, anon, authenticated;
grant  execute on function public.billing_route_target(uuid) to service_role;


-- ══════════ 1bis) Helper user_roles — GARDE anti-événement-ancien ══════════
-- Applique le rôle premium à p_user SANS JAMAIS raccourcir un droit plus récent :
--   • expires_at existant NULL (illimité) → reste NULL ;
--   • sinon → date la plus tardive entre l'existant et l'événement (GREATEST) ;
--   → un EXPIRATION/RENEWAL ANCIEN ne peut ni désactiver ni raccourcir un premium plus récent.
-- granted_by/notes ne sont mis à jour QUE si l'événement gagne (expires strictement plus
-- tardif que l'existant) — sinon on préserve l'info du droit le plus récent.
create or replace function public.billing_upsert_premium_role(
  p_user uuid, p_expires_at timestamptz, p_notes text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_roles (user_id, role, granted_by, expires_at, notes)
  values (p_user, 'premium', p_user, p_expires_at, p_notes)
  on conflict (user_id, role) do update
    set expires_at = case when public.user_roles.expires_at is null then null
                          else greatest(public.user_roles.expires_at, excluded.expires_at) end,
        granted_by = case when public.user_roles.expires_at is not null
                           and excluded.expires_at > public.user_roles.expires_at
                          then excluded.granted_by else public.user_roles.granted_by end,
        notes      = case when public.user_roles.expires_at is not null
                           and excluded.expires_at > public.user_roles.expires_at
                          then excluded.notes else public.user_roles.notes end;
end;
$$;

-- PRIVÉ : aucun rôle client ne peut fournir un user cible arbitraire (contournement du
-- routage). service_role INCLUS dans le revoke, AUCUN grant. Les fonctions SECURITY DEFINER
-- propriétaires (billing_grant_purchase_routed / billing_route_role_apply) l'appellent en
-- tant que propriétaire → l'appel interne fonctionne sans grant à service_role.
revoke execute on function public.billing_upsert_premium_role(uuid, timestamptz, text)
  from public, anon, authenticated, service_role;


-- ══════════ 2) Événements de CRÉDIT (INITIAL_PURCHASE / RENEWAL) ══════════
-- Route la cible SOUS VERROU puis délègue à billing_grant_purchase (idempotent, MÊME
-- transaction) + écrit le rôle premium sur la MÊME cible (sémantique _upsert_premium :
-- remplace expires_at/notes). manual_* → aucune écriture. p_product_id/p_credits/
-- p_duration_days sont RÉSOLUS côté Python (billing._resolve_product) avant l'appel.
create or replace function public.billing_grant_purchase_routed(
  p_original_user_id        uuid,
  p_provider                text,
  p_provider_transaction_id text,
  p_product_id              uuid,
  p_credits                 int,
  p_duration_days           int,
  p_amount                  numeric,
  p_currency                text,
  p_ends_at                 timestamptz,
  p_raw_payload             jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target uuid;
  v_code   text;
  v_grant  jsonb;
  v_dec    text;
begin
  -- Résolution SOUS VERROU (la fonction prend les verrous et relit l'autorité).
  select t.target, t.routing_code into v_target, v_code
    from public.billing_route_target(p_original_user_id) t;

  -- Situation ambiguë → aucune écriture, code sûr de manual review.
  if v_target is null then
    return pg_catalog.jsonb_build_object(
      'effective_user_id', null, 'routing_code', v_code,
      'decision', 'manual_review', 'granted', false);
  end if;

  -- Grant sur la cible, MÊME transaction. Idempotence héritée (order/tx/pass/grant_key).
  v_grant := public.billing_grant_purchase(
    v_target, p_provider, p_provider_transaction_id, p_product_id,
    p_credits, p_duration_days, p_amount, p_currency, p_ends_at, p_raw_payload);

  -- Rôle premium sur la MÊME cible, via le helper NULL-safe GREATEST (garde anti-ancien).
  perform public.billing_upsert_premium_role(
    v_target, p_ends_at, 'RevenueCat routed grant tx=' || p_provider_transaction_id);

  v_dec := case v_grant->>'status'
             when 'granted' then 'granted'
             when 'already_processed' then 'duplicate'
             else coalesce(v_grant->>'status', 'unknown') end;

  return pg_catalog.jsonb_build_object(
    'effective_user_id', v_target,
    'routing_code', v_code,
    'decision', v_dec,
    'granted', coalesce((v_grant->>'credited')::boolean, false),
    'grant', v_grant);
end;
$$;

revoke execute on function public.billing_grant_purchase_routed(uuid, text, text, uuid, int, int, numeric, text, timestamptz, jsonb)
  from public, anon, authenticated;
grant  execute on function public.billing_grant_purchase_routed(uuid, text, text, uuid, int, int, numeric, text, timestamptz, jsonb)
  to service_role;


-- ══════════ 3) Grant de rôle SEUL / EXPIRATION ══════════
-- Route la cible SOUS VERROU puis applique user_roles (upsert, parité _upsert_premium /
-- _expire_premium selon p_expires_at : futur=actif, passé=inactif). manual_* → aucune écriture.
create or replace function public.billing_route_role_apply(
  p_original_user_id uuid,
  p_expires_at       timestamptz,
  p_event_type       text,
  p_event_id         text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_target uuid;
  v_code   text;
begin
  select t.target, t.routing_code into v_target, v_code
    from public.billing_route_target(p_original_user_id) t;

  if v_target is null then
    return pg_catalog.jsonb_build_object(
      'effective_user_id', null, 'routing_code', v_code, 'decision', 'manual_review');
  end if;

  -- Rôle via le helper NULL-safe GREATEST : un EXPIRATION/grant ANCIEN ne raccourcit jamais
  -- un premium plus récent (rule anti-événement-ancien). L'accès est retiré à l'échéance réelle.
  perform public.billing_upsert_premium_role(
    v_target, p_expires_at,
    'RevenueCat ' || coalesce(p_event_type, '') || ' event_id=' || coalesce(p_event_id, ''));

  return pg_catalog.jsonb_build_object(
    'effective_user_id', v_target, 'routing_code', v_code, 'decision', 'applied');
end;
$$;

revoke execute on function public.billing_route_role_apply(uuid, timestamptz, text, text)
  from public, anon, authenticated;
grant  execute on function public.billing_route_role_apply(uuid, timestamptz, text, text)
  to service_role;
