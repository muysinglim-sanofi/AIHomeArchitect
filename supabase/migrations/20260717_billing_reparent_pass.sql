-- PATCH 3 (2026-07-17) — RE-PARENT d'un pass entre identités Supabase de la MÊME personne.
--
-- Contexte (RCA prod) : la clé d'idempotence de grant_purchase est `order:provider:tx`
-- (USER-AGNOSTIQUE) et ne re-parente jamais. Après une divergence d'identité (sign-out →
-- nouvel anon / reinstall du MÊME utilisateur, RC-transféré), le pass de l'abonnement reste
-- collé à l'ancienne identité ; PATCH 2 refuse (à raison) qu'une autre identité l'utilise →
-- abo Apple actif mais wallet 0. Ce RPC permet au reconcile — UNIQUEMENT quand RevenueCat
-- prouve l'entitlement premium ACTIF sur l'identité courante — de faire suivre le pass.
--
-- Sûreté :
--   • Idempotent : pass déjà possédé par p_to_user → no-op (now_owned=true).
--   • Concurrence : ne bouge que si le pass est ENCORE possédé par p_from_user attendu.
--   • Anti-double-grant : DÉPLACE le pass + son ledger de pass ; n'insère AUCUN GRANT/crédit.
--   • Anti-merge : ne touche QUE `passes` + `ledger_entries` de CE pass_id. Jamais le bucket
--     free (pass_id IS NULL), jamais l'identité/chat/images.
--   • Reprojette les DEUX wallets (ancien perd le pass, nouveau le gagne).
--   • Le garde-fou « même personne » vit CÔTÉ APPELANT (reconcile n'appelle ce RPC que si le
--     subscriber RC du user courant montre l'entitlement ACTIF + derrière le flag
--     BILLING_REPARENT_ENABLED). Ce RPC ne crée jamais d'entitlement : il ne fait que déplacer
--     un pass EXISTANT.
--
-- Déploiement : SÛR à appliquer à tout moment (n'est jamais appelé tant que le flag est OFF).

create or replace function public.billing_reparent_pass(
    p_pass_id  uuid,
    p_from_user uuid,
    p_to_user  uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_owner  uuid;
    v_moved  int := 0;
    v_ledger int := 0;
begin
    if p_pass_id is null or p_to_user is null then
        return jsonb_build_object('ok', false, 'reason', 'null_arg', 'now_owned', false);
    end if;

    select user_id into v_owner from passes where id = p_pass_id;
    if v_owner is null then
        return jsonb_build_object('ok', true, 'reason', 'pass_not_found', 'now_owned', false);
    end if;

    -- Déjà chez le destinataire → idempotent no-op.
    if v_owner = p_to_user then
        return jsonb_build_object('ok', true, 'reason', 'already_owned',
                                  'now_owned', true, 'moved_pass', 0);
    end if;

    -- Concurrence : le propriétaire a changé sous nos pieds (≠ celui attendu) → ne pas déplacer
    -- à l'aveugle (le reconcile relira / retombera sur restore_required).
    if p_from_user is not null and v_owner <> p_from_user then
        return jsonb_build_object('ok', true, 'reason', 'owner_changed',
                                  'now_owned', false, 'moved_pass', 0);
    end if;

    -- Déplacement atomique : le pass…
    update passes
       set user_id = p_to_user, updated_at = now()
     where id = p_pass_id and user_id = v_owner;
    get diagnostics v_moved = row_count;

    -- …et SON ledger de pass (GRANT/HOLD/COMMIT/RELEASE de ce pass_id) → le solde restant suit
    -- le pass. Le bucket free (pass_id IS NULL) de l'ancien user reste chez lui.
    update ledger_entries
       set user_id = p_to_user
     where pass_id = p_pass_id and user_id = v_owner;
    get diagnostics v_ledger = row_count;

    -- Reprojection PASS-AWARE des deux côtés (source unique de vérité du wallet).
    perform billing_reproject_wallet(v_owner);
    perform billing_reproject_wallet(p_to_user);

    return jsonb_build_object('ok', true, 'moved_pass', v_moved, 'moved_ledger', v_ledger,
                              'now_owned', v_moved > 0, 'from', v_owner, 'to', p_to_user);
end;
$$;

comment on function public.billing_reparent_pass(uuid, uuid, uuid) is
    'PATCH 3 — déplace atomiquement un pass + son ledger de pass vers l''identité courante '
    '(divergence d''identité, même personne prouvée RC côté appelant). Idempotent, anti-double-'
    'grant (déplace, ne crédite pas), anti-merge (pass seul), reprojette les 2 wallets.';


-- ── REDESIGN (2026-07-17) — signaux d'AUTORISATION du re-parent (le RPC ci-dessus ne DÉCIDE pas ;
--    il exécute. La décision `reparent_authorized` vit côté Python et exige ces deux signaux). ──────

-- (1) Type d'identité : Guest anonyme (true) vs Account (false). Le re-parent n'est autorisé
--     qu'entre deux Guests. Lit auth.users (non exposé via PostgREST) → RPC security definer.
create or replace function public.is_user_anonymous(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public, auth
as $$
    select is_anonymous from auth.users where id = p_user_id;
$$;

comment on function public.is_user_anonymous(uuid) is
    'PATCH 3 redesign — type d''identité (Guest anonyme=true / Account=false / NULL=inconnu) pour '
    'gater le re-parent en Guest→Guest uniquement (aucun transfert Guest↔Account = pas de merge).';

-- (2) Preuve serveur explicite d'un transfert RevenueCat (event type TRANSFER : old→new App User ID).
--     Un entitlement actif NE SUFFIT PAS : le re-parent exige une ligne ici, alimentée par le webhook
--     RC. NOTE : la forme EXACTE des champs (aliases / original_app_user_id / store_transaction_id)
--     sera figée APRÈS la capture device du TRANSFER event (protocole en cours). Table créée vide →
--     tant qu'aucun webhook n'écrit, `_has_authorized_rc_transfer` renvoie false → re-parent refusé.
create table if not exists public.rc_pass_transfers (
    id                  uuid primary key default gen_random_uuid(),
    from_app_user_id    uuid not null,
    to_app_user_id      uuid not null,
    store_transaction_id text,
    rc_event_id         text unique,          -- idempotence webhook (un TRANSFER RC = une ligne)
    raw_event           jsonb not null default '{}'::jsonb,
    created_at          timestamptz not null default now()
);
create index if not exists rc_pass_transfers_pair_idx
    on public.rc_pass_transfers (from_app_user_id, to_app_user_id);

comment on table public.rc_pass_transfers is
    'PATCH 3 redesign — journal des events RevenueCat TRANSFER (old→new App User ID). Preuve serveur '
    'EXIGÉE avant tout re-parent (un entitlement actif ne suffit pas). Alimentée par le webhook RC.';
