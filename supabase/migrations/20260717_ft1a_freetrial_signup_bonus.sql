-- ============================================================================
-- FT1a — Free Trial : éligibilité + bonus de création de compte (DORMANT)
-- ============================================================================
-- Modèle produit : 3 générations gratuites max = 1 anonyme + 2 après création
-- d'un NOUVEAU compte. Cette migration est ADDITIVE et DORMANTE :
--   • billing_free_config()          → source de vérité SQL (1, 2, 3)
--   • account_state (+2 colonnes)    → marqueurs serveur d'éligibilité/octroi
--   • billing_mark_signup_eligible() → marque A éligible (SI auth.users anonyme)
--   • billing_grant_signup_bonus()   → accorde le bonus RÉELLEMENT dû, 1 fois
--
-- Aucun comportement existant n'est modifié par CETTE migration : les 2 RPC ne
-- sont appelées que par les endpoints /identity/anon-init + /claim-signup-bonus,
-- gated par FREE_TRIAL_SIGNUP_BONUS_ENABLED (défaut false). Le flip du trial
-- anonyme 3→1 vit dans 20260718_ft1b (LIVE, à appliquer au lancement FT2).
--
-- ⚠️ AUCUN NOUVEAU VERROU : le bonus est protégé par un CLAIM ATOMIQUE
-- (UPDATE ... WHERE ... RETURNING = compare-and-swap sur la ligne account_state),
-- PAS par un advisory lock. Le verrou historique de billing_try_hold reste le
-- seul advisory-lock du billing et n'est PAS touché par FT1.
--
-- ⚠️ PAS DE SUR-CRÉDIT LEGACY : le bonus est PLAFONNÉ au total gratuit (3) à
-- partir des DROITS ACCORDÉS (deltas positifs de trial:<uid> et signup:<uid>),
-- jamais des HOLD. Un utilisateur avec un ancien TRIAL +3 reçoit bonus_due=0
-- (already_entitled), jamais 5.
--
-- Sécurité : anonymat vérifié EN SQL contre auth.users.is_anonymous (SECURITY
-- DEFINER), jamais le claim JWT (périmé ~1h après conversion) ni le frontend.
-- Ledger append-only respecté (INSERT-only). Compte jamais anonyme → non
-- éligible. Le merge RPC (20260714) ne propage pas signup_bonus_* (colonnes
-- explicites) → aucune modif du merge nécessaire.
-- Pas de BEGIN/COMMIT explicite (runner / SQL Editor enveloppe le fichier) —
-- convention alignée sur 20260709/10/14/15/16.
-- ============================================================================

-- ── 1) Source de vérité SQL des nombres (miroir de backend/free_tier_config.py)
create or replace function public.billing_free_config()
returns table(anon_free int, signup_bonus int, total_free int)
language sql
immutable
as $$
  select 1, 2, 3;   -- anon_free=1 · signup_bonus=2 · total_free=3
$$;

revoke execute on function public.billing_free_config() from public, anon, authenticated;
grant  execute on function public.billing_free_config() to service_role;

-- ── 2) Marqueurs serveur d'éligibilité au bonus (additifs, fast-default)
alter table public.account_state
  add column if not exists signup_bonus_eligible   boolean     not null default false,
  add column if not exists signup_bonus_granted_at timestamptz;

comment on column public.account_state.signup_bonus_eligible is
  'FT1 — A éligible au bonus : posé true UNIQUEMENT tant que auth.users.is_anonymous=true. Un compte jamais anonyme reste false.';
comment on column public.account_state.signup_bonus_granted_at is
  'FT1 — instant de traitement du bonus (NULL = jamais traité). Idempotence du claim.';

-- ── 3) Marquer A éligible — anonymat AUTORITAIRE (auth.users), sans verrou
--    Idempotent. Ne RÉ-ARME JAMAIS après octroi ni sur compte fermé (UPSERT
--    gardé). N'accorde AUCUN crédit. Codes : marked | already_eligible |
--    already_granted | merged_closed | not_anonymous | user_not_found.
create or replace function public.billing_mark_signup_eligible(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_is_anon    boolean;
  v_eligible   boolean;
  v_granted_at timestamptz;
  v_closed     boolean;
  v_found      boolean;
  v_marked     boolean;
begin
  select is_anonymous into v_is_anon from auth.users where id = p_user_id;
  if v_is_anon is null then
    return jsonb_build_object('eligible', false, 'reason', 'user_not_found');
  end if;
  if not v_is_anon then
    return jsonb_build_object('eligible', false, 'reason', 'not_anonymous');
  end if;

  select signup_bonus_eligible, signup_bonus_granted_at, merged_closed
    into v_eligible, v_granted_at, v_closed
    from public.account_state where user_id = p_user_id;
  v_found := found;

  if v_found and coalesce(v_closed, false) then
    return jsonb_build_object('eligible', false, 'reason', 'merged_closed');
  end if;
  if v_found and v_granted_at is not null then
    return jsonb_build_object('eligible', false, 'reason', 'already_granted');
  end if;
  if v_found and coalesce(v_eligible, false) then
    return jsonb_build_object('eligible', true, 'reason', 'already_eligible');
  end if;

  -- UPSERT gardé : n'arme l'éligibilité que si NI accordé NI fermé (protège
  -- contre une course avec le claim du grant, sans verrou). RETURNING → si rien
  -- n'a été écrit (course : granted_at/merged_closed posé entre le SELECT et
  -- l'UPSERT), on renvoie le code RÉEL au lieu d'un 'marked' trompeur.
  insert into public.account_state (user_id, signup_bonus_eligible)
  values (p_user_id, true)
  on conflict (user_id) do update
    set signup_bonus_eligible = true,
        updated_at            = now()
    where public.account_state.signup_bonus_granted_at is null
      and public.account_state.merged_closed = false
  returning signup_bonus_eligible into v_marked;

  if v_marked is null then
    select signup_bonus_granted_at, merged_closed into v_granted_at, v_closed
      from public.account_state where user_id = p_user_id;
    if coalesce(v_closed, false) then
      return jsonb_build_object('eligible', false, 'reason', 'merged_closed');
    end if;
    return jsonb_build_object('eligible', false, 'reason', 'already_granted');
  end if;

  return jsonb_build_object('eligible', true, 'reason', 'marked');
end;
$$;

revoke execute on function public.billing_mark_signup_eligible(uuid) from public, anon, authenticated;
grant  execute on function public.billing_mark_signup_eligible(uuid) to service_role;

-- ── 4) Accorder le bonus — CLAIM ATOMIQUE SANS VERROU + bonus PLAFONNÉ
--    (a) auth.users non-anonyme MAINTENANT ; (b) compare-and-swap sur
--    account_state (un seul concurrent gagne) ; (c) garantir trial(+1) si absent ;
--    (d) bonus_due = greatest(0, least(signup_bonus, total_free - trial_ent -
--        signup_ent)) à partir des DROITS ACCORDÉS (jamais les HOLD) ; un ancien
--        TRIAL +3 ⇒ 0. Codes : granted | already_entitled | already_processed |
--        merged_closed | not_eligible.
create or replace function public.billing_grant_signup_bonus(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_is_anon    boolean;
  v_anon_free  int;
  v_signup     int;
  v_total      int;
  v_trial_key  text := 'trial:'  || p_user_id::text;
  v_signup_key text := 'signup:' || p_user_id::text;
  v_claimed    uuid;
  v_eligible   boolean;
  v_granted_at timestamptz;
  v_closed     boolean;
  v_trial_ent  int;
  v_signup_ent int;
  v_bonus_due  int;
begin
  select anon_free, signup_bonus, total_free
    into v_anon_free, v_signup, v_total
    from public.billing_free_config();

  -- (a) L'utilisateur doit être PERMANENT maintenant (conversion réussie).
  select is_anonymous into v_is_anon from auth.users where id = p_user_id;
  if v_is_anon is null then
    return jsonb_build_object('decision', 'not_eligible', 'reason', 'user_not_found', 'bonus_granted', 0);
  end if;
  if v_is_anon then
    return jsonb_build_object('decision', 'not_eligible', 'reason', 'still_anonymous', 'bonus_granted', 0);
  end if;

  -- (b) CLAIM ATOMIQUE SANS VERROU — compare-and-swap sur la ligne account_state.
  --     Le row-lock de l'UPDATE + le re-check du prédicat (READ COMMITTED) font
  --     qu'UN SEUL appel concurrent flippe eligible true→false. AUCUN advisory
  --     lock, AUCUN SELECT FOR UPDATE explicite.
  update public.account_state
     set signup_bonus_eligible   = false,
         signup_bonus_granted_at = now(),
         updated_at              = now()
   where user_id                 = p_user_id
     and signup_bonus_eligible   = true
     and signup_bonus_granted_at is null
     and merged_closed           = false
  returning user_id into v_claimed;

  if v_claimed is null then
    -- Perdu / non éligible : relire l'état pour la raison exacte.
    select signup_bonus_eligible, signup_bonus_granted_at, merged_closed
      into v_eligible, v_granted_at, v_closed
      from public.account_state where user_id = p_user_id;
    if coalesce(v_closed, false) then
      return jsonb_build_object('decision', 'merged_closed', 'reason', 'merged_closed', 'bonus_granted', 0);
    end if;
    if v_granted_at is not null then
      return jsonb_build_object('decision', 'already_processed', 'reason', 'already_granted', 'bonus_granted', 0);
    end if;
    return jsonb_build_object('decision', 'not_eligible', 'reason', 'not_marked_eligible', 'bonus_granted', 0);
  end if;

  -- (c) Claim gagné (eligible consommé, granted_at posé). Garantir trial(+1)
  --     UNIQUEMENT s'il est absent — ne touche PAS un TRIAL historique +3.
  insert into public.ledger_entries
    (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
  values
    (p_user_id, 'TRIAL', v_anon_free, null, 'PROMO', 'trial', v_trial_key)
  on conflict (idempotency_key) do nothing;

  -- (d) Bonus RÉELLEMENT dû, plafonné au total gratuit, à partir des DROITS
  --     ACCORDÉS (deltas positifs de trial:<uid> et signup:<uid>). Les HOLD
  --     (clés hold:<intent> distinctes) ne sont JAMAIS comptés.
  select coalesce(sum(available_delta), 0) into v_trial_ent
    from public.ledger_entries where idempotency_key = v_trial_key;
  select coalesce(sum(available_delta), 0) into v_signup_ent
    from public.ledger_entries where idempotency_key = v_signup_key;

  v_bonus_due := greatest(0, least(v_signup, v_total - v_trial_ent - v_signup_ent));

  if v_bonus_due > 0 then
    insert into public.ledger_entries
      (user_id, entry_type, available_delta, pass_id, reference_type, reference_id, idempotency_key)
    values
      (p_user_id, 'GRANT', v_bonus_due, null, 'PROMO', 'signup', v_signup_key)
    on conflict (idempotency_key) do nothing;
    perform public.billing_reproject_wallet(p_user_id);
    return jsonb_build_object('decision', 'granted', 'reason', '', 'bonus_granted', v_bonus_due);
  end if;

  -- (e) Rien de dû (déjà ≥ total_free d'entitlement, ex : ancien TRIAL +3) :
  --     éligibilité consommée, AUCUNE entrée GRANT de montant zéro.
  perform public.billing_reproject_wallet(p_user_id);
  return jsonb_build_object('decision', 'already_entitled', 'reason', 'already_entitled', 'bonus_granted', 0);
end;
$$;

revoke execute on function public.billing_grant_signup_bonus(uuid) from public, anon, authenticated;
grant  execute on function public.billing_grant_signup_bonus(uuid) to service_role;
