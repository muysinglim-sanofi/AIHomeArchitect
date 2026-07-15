"""
Billing Engine — PR1 : OBSERVABILITÉ (ledger/wallet, SANS gate).

Spec : docs/BILLING_ENGINE_SPEC.md (§4.0 modèle d'événements, §3 idempotence).

Projette l'effet crédit des transitions d'un Intent dans le ledger append-only,
et projette le wallet — SANS rien enforcer :
  • AUCUN gate, AUCUN 402, AUCUN blocage de génération.
  • Soldes NÉGATIFS attendus (pas de GRANT d'achat en PR1 ; seul TRIAL crédite).
  • Best-effort : une écriture billing qui échoue ne casse JAMAIS /generate.

⚠️ RÈGLE D'ARCHITECTURE (1) : TOUTES les règles vivent ICI (`_decide` + apply).
Les hooks ne font que RELAYER un événement de transition — aucune logique métier.

⚠️ RÈGLE D'ARCHITECTURE (2) — PROJECTION DIRECTE, PAS DE COMPENSATION :
`_decide` ne dépend QUE de l'événement reçu. Il ne regarde JAMAIS le passé
(pas de « un RELEASE existe-t-il déjà ? », pas de COMMIT à delta conditionnel).
  RUNNING          → HOLD(-1)      hold:<intent_id>
  SUCCEEDED        → COMMIT(0)     commit:<intent_id>
  FAILED/_TERMINAL → RELEASE(+1)   release:<intent_id>
  (1re gen d'un user) → TRIAL(+TRIAL_CREDITS)  trial:<user_id>
Net : succeeded = HOLD(-1)+COMMIT(0) = -1 · failed = HOLD(-1)+RELEASE(+1) = 0.

ANOMALIE CONNUE, VOLONTAIREMENT NON COMPENSÉE EN PR1 : si un MÊME intent_id
produit FAILED puis SUCCEEDED (doublon concurrent GATE-2, ou re-tir séquentiel
du même intent), on obtient HOLD+RELEASE+COMMIT = net 0 pour une gen réussie.
C'est un SYMPTÔME de l'absence de claim atomique — que **PR2 élimine à la
SOURCE** (un Intent ne produira plus cette séquence ambiguë). En PR1 (pas de
gate, pas de paiement) c'est **inoffensif** et **observable** : la requête
net-par-intent (§ vues) le rend visible → on MESURE la fréquence réelle avant de
décider PR2. On ne traite pas le symptôme dans le moteur de billing.

Branché sur les DEUX émetteurs de transitions Intent :
  • chemin nominal /generate  → via observe_intent_start / observe_intent_end
  • réconciliation PR4        → via intent_reconciliation._finalize
"""

from __future__ import annotations

import asyncio
import logging
import os
from datetime import datetime, timezone
from dataclasses import dataclass
from typing import Optional

from free_tier_config import ANONYMOUS_FREE_GENERATIONS, PRE_FT2_ANON_FREE_GENERATIONS

log = logging.getLogger("billing")


def _free_trial_active() -> bool:
    """FT1 — MÊME flag que les endpoints signup (identity._signup_bonus_enabled)
    et que l'application de la migration 20260718_ft1b. Défaut OFF."""
    return os.environ.get("FREE_TRIAL_SIGNUP_BONUS_ENABLED", "false").strip().lower() == "true"


# TRIAL_CREDITS pilote UNIQUEMENT la PROJECTION/affichage (_free_bucket_available,
# /me/status) et grant_trial (réconciliation) — PAS l'enforcement, qui vit en SQL
# (billing_try_hold). Il DOIT rester == à ce que le SQL accorde réellement :
#   • fenêtre FT1 (flag OFF, ft1b non appliquée) → SQL accorde 3 → affichage 3 ;
#   • lancement FT2 (flag ON + ft1b appliquée)   → SQL accorde 1 → affichage 1.
# Le flag est le point de couplage unique (runbook FT2 : flag ⟺ ft1b). Défaut = 3
# → FT1 n'introduit AUCUN changement live tant que FT2 n'est pas activé (dormant).
TRIAL_CREDITS = ANONYMOUS_FREE_GENERATIONS if _free_trial_active() else PRE_FT2_ANON_FREE_GENERATIONS


def _get_supa():
    """Lazy import to avoid a circular dependency at module load (mirrors quota.py)."""
    from main import supa  # noqa: PLC0415
    return supa


# ── Décision PURE : dépend UNIQUEMENT de l'événement (testable hors DB) ──────


def _decide(new_status: str) -> Optional[tuple[str, int, str]]:
    """La SEULE fonction qui connaît le mapping transition → écriture ledger.
    Renvoie (entry_type, available_delta, key_prefix) ou None (statut inconnu).
    PURE : ne regarde ni le ledger ni le passé — juste l'événement reçu.
    (Le TRIAL est géré à part — il est par-user, pas par-transition.)
    """
    return {
        "RUNNING": ("HOLD", -1, "hold"),
        "SUCCEEDED": ("COMMIT", 0, "commit"),
        "FAILED": ("RELEASE", 1, "release"),
        "FAILED_TERMINAL": ("RELEASE", 1, "release"),
    }.get(new_status)


# ── Low-level ledger / wallet ────────────────────────────────────────────────


async def _ledger_insert(
    supa, *, user_id: str, entry_type: str, available_delta: int,
    idempotency_key: str, reference_type: Optional[str] = None,
    reference_id: Optional[str] = None, pass_id: Optional[str] = None,
) -> bool:
    """INSERT append-only, idempotent par idempotency_key (ON CONFLICT DO NOTHING).
    Renvoie True si NOUVELLE ligne, False si déjà présente (dup) ou erreur. Ne
    fait jamais d'UPDATE (le trigger append-only l'interdirait). `pass_id` (RC-PR3a)
    scope l'entrée au bucket d'un pass (comme le GRANT) → décompte par pass."""
    row = {
        "user_id": user_id,
        "entry_type": entry_type,
        "available_delta": available_delta,
        "idempotency_key": idempotency_key,
    }
    if reference_type is not None:
        row["reference_type"] = reference_type
    if reference_id is not None:
        row["reference_id"] = reference_id
    if pass_id is not None:
        row["pass_id"] = pass_id
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("ledger_entries")
            .upsert(row, on_conflict="idempotency_key", ignore_duplicates=True)
            .execute()
        )
        return bool(getattr(res, "data", None))
    except Exception as exc:
        log.warning("[BILLING] ledger_insert failed (swallowed) key=%s err=%s: %s",
                    idempotency_key, type(exc).__name__, exc)
        return False


async def _intent_user_id(supa, intent_id: str) -> Optional[str]:
    """user_id propriétaire de l'Intent (pour les transitions terminales qui ne
    le passent pas). Aucune lecture de statut — projection directe."""
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("generation_intents")
            .select("user_id").eq("intent_id", intent_id).limit(1).execute()
        )
        rows = getattr(res, "data", None) or []
        return rows[0].get("user_id") if rows else None
    except Exception as exc:
        log.warning("[BILLING] intent_user_id failed intent=%s err=%s", intent_id, exc)
        return None


async def _active_pass_id(supa, user_id: str) -> Optional[str]:
    """RC-PR3a — id du pass ACTIF du user, ou None. MÊMES critères que
    `billing_reproject_wallet` (status=ACTIVE, now ∈ [starts_at, ends_at],
    ends_at le plus lointain) → le débit est scoppé au MÊME bucket que la
    projection somme. None (admin/promo/premium-sans-pass, ou erreur) = pas de
    débit (best-effort : jamais bloquant)."""
    try:
        now_iso = datetime.now(timezone.utc).isoformat()
        res = await asyncio.to_thread(
            lambda: supa.table("passes")
            .select("id")
            .eq("user_id", user_id).eq("status", "ACTIVE")
            .lte("starts_at", now_iso).gt("ends_at", now_iso)
            .order("ends_at", desc=True).limit(1).execute()
        )
        rows = getattr(res, "data", None) or []
        return rows[0].get("id") if rows else None
    except Exception as exc:  # noqa: BLE001 — best-effort : pas de débit plutôt qu'un crash
        log.warning("[BILLING] active_pass lookup failed user=%s err=%s", user_id[:8], exc)
        return None


async def _pass_bucket_available(supa, user_id: str, pass_id: str) -> int:
    """RC-PR3b — solde `available` du bucket d'UN pass : Σ available_delta des
    ledger_entries de CE pass_id. MÊME calcul que `billing_reproject_wallet` pour
    le bucket pass → l'enforcement lit exactement ce que le profil affiche
    (wallet.available_credits). FAIL-OPEN : sur erreur DB, renvoie 1 (autorise) —
    un payant n'est jamais bloqué par un hoquet de lecture."""
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("ledger_entries")
            .select("available_delta")
            .eq("user_id", user_id).eq("pass_id", pass_id).execute()
        )
        rows = getattr(res, "data", None) or []
        return sum(int(r.get("available_delta") or 0) for r in rows)
    except Exception as exc:  # noqa: BLE001 — FAIL-OPEN : fiabilité > double rare
        log.warning("[BILLING-GATE] pass bucket read failed user=%s pass=%s err=%s → fail-open allow",
                    user_id[:8], pass_id[:8], exc)
        return 1


async def _free_bucket_available(supa, user_id: str, *, project_trial: bool = True) -> int:
    """P0 (2026-07-10) — bucket FREE/TRIAL = Σ available_delta des ledger_entries
    `pass_id IS NULL`, PLANCHÉ à 0, + TRIAL projeté (+TRIAL_CREDITS) si pas encore accordé ET
    `project_trial` (grant_trial est idempotent, posé au 1er RUNNING SEULEMENT quand
    aucun pass actif → on ne projette le +3 que dans ce cas, sinon un premium frais
    afficherait un free fantôme). MÊME règle que `billing_reproject_wallet` (branche
    sans pass). Exclut les GRANTs de passes (pass_id renseigné) → un pass EXPIRÉ ne
    pollue JAMAIS le free (fin des crédits fantômes 60/30). FAIL-OPEN : erreur DB →
    TRIAL_CREDITS (ne bloque jamais un user)."""
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("ledger_entries")
            .select("entry_type, available_delta, pass_id")
            .eq("user_id", user_id).is_("pass_id", "null").execute()
        )
        rows = getattr(res, "data", None) or []
    except Exception as exc:  # noqa: BLE001 — FAIL-OPEN : fiabilité > double rare
        log.warning("[BILLING-GATE] free bucket read failed user=%s err=%s → fail-open",
                    user_id[:8], exc)
        return TRIAL_CREDITS
    raw = sum(int(r.get("available_delta") or 0) for r in rows)
    trial_granted = any(r.get("entry_type") == "TRIAL" for r in rows)
    trial_bonus = TRIAL_CREDITS if (project_trial and not trial_granted) else 0
    return max(0, raw) + trial_bonus


async def _intent_hold_bucket(supa, intent_id: str):
    """P0 (2026-07-10) — (hold_exists, pass_id) du HOLD de cet intent. Sert à ce que
    COMMIT/RELEASE ciblent le MÊME bucket que le HOLD sur tout le cycle de vie
    (pass-first stable). `pass_id=None` = bucket free. Fail-safe : sur erreur →
    (False, None) → COMMIT/RELEASE no-op plutôt qu'un mauvais bucket."""
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("ledger_entries")
            .select("pass_id").eq("idempotency_key", f"hold:{intent_id}")
            .limit(1).execute()
        )
        rows = getattr(res, "data", None) or []
        if not rows:
            return (False, None)
        return (True, rows[0].get("pass_id"))
    except Exception as exc:  # noqa: BLE001
        log.warning("[BILLING] hold bucket lookup failed intent=%s err=%s", intent_id, exc)
        return (False, None)


async def _reproject_wallet(*, user_id: str, supa=None) -> None:
    """Reprojette le wallet via le RPC PASS-AWARE `billing_reproject_wallet`
    (RC-PR2b) — SOURCE DE VÉRITÉ UNIQUE de la projection, partagée avec le RPC
    d'achat. Règle : si pass actif → solde du bucket du pass (pass_id) uniquement ;
    sinon → bucket free/trial (pass_id IS NULL) planchérisé à 0. Le calcul vit en
    SQL (pas de somme globale Python qui mélangeait free pré-achat et pass acheté).

    Best-effort : un échec ne casse JAMAIS /generate (chemin conso fail-open)."""
    supa = supa or _get_supa()
    try:
        await asyncio.to_thread(
            lambda: supa.rpc("billing_reproject_wallet", {"p_user_id": user_id}).execute()
        )
    except Exception as exc:
        log.warning("[BILLING] wallet reproject (rpc) failed user=%s err=%s", user_id, exc)


async def _emit(supa, *, user_id: str, entry_type: str, delta: int, key: str,
                intent_id: Optional[str], pass_id: Optional[str] = None) -> None:
    """Écrit une entrée ledger (idempotente) puis reprojette le wallet si nouvelle.
    `pass_id` (RC-PR3a) scope la conso au bucket d'un pass mesuré."""
    new = await _ledger_insert(
        supa, user_id=user_id, entry_type=entry_type, available_delta=delta,
        idempotency_key=key,
        reference_type="GENERATION_INTENT" if intent_id else None,
        reference_id=intent_id, pass_id=pass_id,
    )
    if new:
        log.info("[BILLING] %s(%+d) key=%s user=%s pass=%s", entry_type, delta, key,
                 user_id[:8], (pass_id[:8] if pass_id else "-"))
        await _reproject_wallet(user_id=user_id, supa=supa)


# ── Public API (les hooks n'appellent QUE ça) ────────────────────────────────


async def grant_trial(*, user_id: str, supa=None) -> None:
    """TRIAL(+TRIAL_CREDITS) une seule fois par user (idempotent trial:<user_id>)."""
    supa = supa or _get_supa()
    new = await _ledger_insert(
        supa, user_id=user_id, entry_type="TRIAL", available_delta=TRIAL_CREDITS,
        idempotency_key=f"trial:{user_id}", reference_type="PROMO", reference_id="trial",
    )
    if new:
        log.info("[BILLING] TRIAL(+%d) user=%s", TRIAL_CREDITS, user_id[:8])
        await _reproject_wallet(user_id=user_id, supa=supa)


# ── FT1 — Free Trial : éligibilité + bonus de création de compte ─────────────
# Ces deux wrappers RELAIENT les RPC SQL (billing_mark_signup_eligible /
# billing_grant_signup_bonus). Toute la logique (vérif anonymat via auth.users,
# idempotence, advisory-lock, reprojection) vit EN SQL — ici on ne fait que
# passer p_user_id (= JWT côté endpoint) et remonter le dict. On NE swallow PAS
# les exceptions (contrairement à grant_trial) : un octroi ne doit jamais
# fail-open ; l'endpoint mappe l'erreur en 503 → retry sûr (RPC idempotente).

async def mark_signup_eligible(*, user_id: str, supa=None) -> dict:
    """Marque A éligible au bonus de création SI auth.users confirme l'anonymat
    (vérif SQL, pas le claim JWT périmé). Idempotent. Ne crédite RIEN.
    Renvoie {eligible: bool, reason: str}."""
    supa = supa or _get_supa()
    res = await asyncio.to_thread(
        lambda: supa.rpc("billing_mark_signup_eligible", {"p_user_id": user_id}).execute()
    )
    data = getattr(res, "data", None)
    if isinstance(data, list):
        data = data[0] if data else None
    data = data or {}
    log.info("[BILLING] signup_eligible user=%s eligible=%s reason=%s",
             user_id[:8], data.get("eligible"), data.get("reason"))
    return data


async def grant_signup_bonus(*, user_id: str, supa=None) -> dict:
    """Accorde le bonus de création RÉELLEMENT dû (plafonné au total gratuit) et
    garantit le trial (+1 si absent), via billing_grant_signup_bonus (SECURITY
    DEFINER). Idempotence par CLAIM ATOMIQUE sur account_state (compare-and-swap,
    AUCUN advisory lock) : auth.users non-anonyme MAINTENANT ∧ signup_bonus_eligible
    ∧ NOT merged_closed ∧ granted_at NULL. Bonus calculé sur les DROITS ACCORDÉS
    (jamais les HOLD) → un ancien TRIAL +3 ⇒ 0 (already_entitled), jamais 5.
    Renvoie {decision: granted|already_entitled|already_processed|merged_closed|
    not_eligible, bonus_granted, reason}."""
    supa = supa or _get_supa()
    res = await asyncio.to_thread(
        lambda: supa.rpc("billing_grant_signup_bonus", {"p_user_id": user_id}).execute()
    )
    data = getattr(res, "data", None)
    if isinstance(data, list):
        data = data[0] if data else None
    data = data or {}
    log.info("[BILLING] signup_bonus user=%s decision=%s reason=%s",
             user_id[:8], data.get("decision"), data.get("reason"))
    return data


@dataclass
class ReserveDecision:
    """Résultat du gate wallet (lecture seule). `wallet_available` = solde
    available AVANT tout TRIAL pending ; `effective` = ce que le gate voit."""
    allow: bool
    wallet_available: int
    effective: int
    reason: str          # "" (allow) | "bypass" | "insufficient_credits" | "pass_exhausted" | "no_active_pass" | "fail_open"
    # P0 (2026-07-10) — SOURCE UNIQUE : buckets additifs exposés tels quels à /me/status.
    free_credits: int = 0      # bucket free/trial (pass_id IS NULL) planché + TRIAL projeté
    pass_credits: int = 0      # bucket du pass ACTIF (0 si aucun / expiré)
    total_credits: int = 0     # free_credits + pass_credits (promo hors ledger, cf. resolver)
    has_active_pass: bool = False
    bypass: bool = False       # admin / promo_unlimited / promo_limited (illimité ou borné resolver)


async def reserve_decision(
    *, user_id: str, is_free: bool, tier: str = "free", supa=None,
) -> ReserveDecision:
    """GATE wallet, **LECTURE SEULE**. Décide si l'user peut lancer une génération.
    Appelé dans /generate (et /refine) AVANT le claim : aucune écriture (le HOLD est
    posé APRÈS le claim-won) → « aucune réservation avant ownership ».

    P0 (2026-07-10) — PASS-FIRST ADDITIF, source unique = ledger (= wallet) :
      • admin / promo_unlimited / promo_limited → bypass (illimité réel, ou promo borné
        par le resolver qui a déjà garanti remaining > 0).
      • sinon → total = pass_credits + free_credits (buckets DISJOINTS, additifs) :
          - pass_credits = solde du PASS ACTIF (0 si aucun/expiré), scoppé pass_id ;
          - free_credits = bucket free/trial (pass_id IS NULL, planché à 0, + TRIAL projeté).
        allow = total ≥ 1. Le PASS décide l'éligibilité INDÉPENDAMMENT du rôle (un abonné
        au webhook manqué génère via son pass). Un pass EXPIRÉ ne contribue pas (fin des
        crédits fantômes). Reason de deny : pass_exhausted (pass présent, total 0) /
        no_active_pass (rôle premium sans pass ni free) / insufficient_credits (free 0).
    FAIL-OPEN sur erreur de lecture (fiabilité > double rare), porté par les helpers
    (_free_bucket_available → TRIAL_CREDITS ; _pass_bucket_available → 1).
    cf. docs/RC_PR3B_ENFORCEMENT.md + docs/P0_BILLING_INTEGRITY_TEST_MATRIX.md.
    """
    supa = supa or _get_supa()
    # ── BYPASS — illimité RÉEL (admin, promo_unlimited) ou borné-par-resolver
    #    (promo_limited : le tier retombe à free quand épuisé). Aucune lecture DB.
    if tier in ("admin", "promo_unlimited", "promo_limited"):
        return ReserveDecision(allow=True, wallet_available=0, effective=0,
                               reason="bypass", bypass=True)

    # ── P0 (2026-07-10) — PASS-FIRST ADDITIF. Autorité = ledger (SOURCE UNIQUE, =
    #    wallet). Le PASS ACTIF (mesuré) décide la disponibilité INDÉPENDAMMENT du
    #    rôle : un abonné dont le webhook a manqué le rôle (tier=free) mais qui a un
    #    pass actif génère quand même. Le total ADDITIONNE le bucket pass (crédits
    #    payés, expirent avec le pass) + le bucket free (pass_id IS NULL, planché à 0,
    #    + TRIAL projeté). Un pass EXPIRÉ ne contribue pas (GRANT scoppé à un pass_id
    #    inactif → hors des deux buckets lus ici) → plus de crédits fantômes.
    pass_id = await _active_pass_id(supa, user_id)
    # Trial projeté (+3) UNIQUEMENT pour le FREE tier sans pass actif (cohérent avec
    # apply_billing qui ne grant_trial que si is_free ET active is None) → pas de free
    # fantôme ni pour un pass-holder frais, ni pour un premium au pass expiré.
    free_credits = await _free_bucket_available(
        supa, user_id, project_trial=(is_free and pass_id is None))
    pass_credits = await _pass_bucket_available(supa, user_id, pass_id) if pass_id else 0
    total = free_credits + pass_credits
    allow = total >= 1
    if allow:
        reason = ""
    elif pass_id is not None:
        reason = "pass_exhausted"      # un pass existe mais pass+free = 0
    elif not is_free:
        # rôle premium (abo signalé) mais aucun pass actif ET aucun free → incohérent :
        # l'user doit restaurer/synchroniser. JAMAIS unlimited silencieux.
        reason = "no_active_pass"
    else:
        reason = "insufficient_credits"
    log.info(
        "[BILLING-GATE] P0 user=%s pass=%s pass_credits=%d free_credits=%d total=%d decision=%s reason=%s",
        user_id[:8], (pass_id[:8] if pass_id else "-"), pass_credits, free_credits,
        total, "allow" if allow else "deny", reason or "-",
    )
    return ReserveDecision(
        allow=allow, wallet_available=total, effective=total, reason=reason,
        free_credits=free_credits, pass_credits=pass_credits, total_credits=total,
        has_active_pass=pass_id is not None)


async def apply_billing_for_intent_transition(
    *, intent_id: str, new_status: str, user_id: Optional[str] = None,
    is_free: bool = True, tier: Optional[str] = None, supa=None,
) -> None:
    """Projette l'effet ledger d'une transition d'Intent (RUNNING/terminal).
    Point d'entrée UNIQUE appelé par les émetteurs. Idempotent, best-effort,
    ne lève jamais, AUCUN gate. Projection directe (voir _decide) — pas de
    compensation ni de lecture du passé.

    P0 (2026-07-10) — PASS-FIRST (bucket choisi au HOLD, stable jusqu'au COMMIT/RELEASE) :
      • pass ACTIF avec solde ≥ 1 → débite le bucket du PASS (crédit payé) ;
      • sinon free/trial (pass_id=None) : TRIAL une fois si aucun pass, HOLD/COMMIT/
        RELEASE dans le bucket free — couvre le pass épuisé qui retombe sur le free
        résiduel (pass-first PUIS free) ;
      • entitled SANS pass actif (admin/promo/premium-sans-pass = illimité) → AUCUNE
        écriture. COMMIT/RELEASE retrouvent le bucket du HOLD (hold:<intent>) → jamais
        un HOLD-pass suivi d'un RELEASE-free. Idempotent (clés déterministes), best-effort.
    L'enforcement (blocage à 0) vit dans `reserve_decision` (gate). Ici on PROJETTE.
    """
    supa = supa or _get_supa()
    decision = _decide(new_status)
    if decision is None:
        return
    if user_id is None:
        user_id = await _intent_user_id(supa, intent_id)
        if user_id is None:
            log.warning("[BILLING] no user for intent=%s status=%s — skip", intent_id, new_status)
            return
    entry_type, delta, prefix = decision
    key = f"{prefix}:{intent_id}"

    # P0 (2026-07-10) — PASS-FIRST STABLE. Le bucket est choisi UNE fois au HOLD et
    # COMMIT/RELEASE le retrouvent (via hold:<intent>) → HOLD/COMMIT/RELEASE d'un même
    # intent frappent TOUJOURS le même bucket (jamais HOLD-pass / RELEASE-free bancal).
    if new_status == "RUNNING":
        active = await _active_pass_id(supa, user_id)
        target_pass = None
        if active is not None and await _pass_bucket_available(supa, user_id, active) >= 1:
            target_pass = active                      # pass-first : débite le crédit payé
        if target_pass is None:
            # Aucun pass utilisable → soit BYPASS (illimité), soit débit du bucket FREE.
            if tier in ("admin", "promo_unlimited", "promo_limited"):
                return                                # illimité RÉEL → aucune mesure
            if tier is None and not is_free:
                return                                # compat : caller sans tier + entitled (refine billing-OFF)
            if is_free:
                await grant_trial(user_id=user_id, supa=supa)   # free identity, une fois (idempotent)
            # premium metered SANS pass (pass expiré) → débite le free RÉSIDUEL, PAS de
            # nouveau trial (le gate n'a autorisé que si free_residuel ≥ 1).
        await _emit(supa, user_id=user_id, entry_type=entry_type, delta=delta,
                    key=key, intent_id=intent_id, pass_id=target_pass)
        return

    # COMMIT / RELEASE → MÊME bucket que le HOLD (stabilité lifecycle).
    hold_exists, hold_pass = await _intent_hold_bucket(supa, intent_id)
    if not hold_exists:
        return                                        # aucun HOLD (entitled illimité) → no-op
    await _emit(supa, user_id=user_id, entry_type=entry_type, delta=delta,
                key=key, intent_id=intent_id, pass_id=hold_pass)


async def try_hold(*, user_id: str, intent_id: str, tier: str, supa=None) -> dict:
    """P0a-bis (2026-07-10) — RÉSERVATION ATOMIQUE : le VRAI droit de générer.

    Délègue au RPC `billing_try_hold` (advisory-lock par user + HOLD conditionnel
    solde≥1, en UNE transaction). Contrairement à `reserve_decision` (LECTURE SEULE,
    indicatif pour /me/status + fast-fail), ceci POSE la réservation atomiquement :
    /generate n'appelle OpenAI QUE si granted=true → ferme la course de concurrence
    (N /generate concurrents à intents distincts ≤ solde). Idempotent (hold:<intent>).

    Renvoie {granted, reason, bucket, total_before, total_after, idempotent}.
    FAIL-OPEN : hoquet DB → granted=True (parité avec reserve_decision : la fiabilité
    prime ; un payant n'est jamais bloqué par un hoquet)."""
    supa = supa or _get_supa()
    try:
        res = await asyncio.to_thread(
            lambda: supa.rpc(
                "billing_try_hold",
                {"p_user_id": user_id, "p_intent_id": intent_id, "p_tier": tier},
            ).execute()
        )
        data = getattr(res, "data", None)
        if isinstance(data, list):
            data = data[0] if data else None
        data = data or {}
        granted = bool(data.get("granted"))
        log.info("[BILLING-ATOMIC] try_hold user=%s intent=%s tier=%s granted=%s bucket=%s reason=%s total_after=%s",
                 user_id[:8], intent_id, tier, granted, data.get("bucket"),
                 data.get("reason") or "-", data.get("total_after"))
        return {
            "granted": granted, "reason": data.get("reason") or "",
            "bucket": data.get("bucket"), "total_before": data.get("total_before"),
            "total_after": data.get("total_after"), "idempotent": bool(data.get("idempotent")),
        }
    except Exception as exc:  # noqa: BLE001
        _msg = str(exc).lower()
        # RPC ABSENTE (SQL 20260710_p0a pas encore appliqué) → FAIL-CLOSED. On refuse
        # AVANT OpenAI : jamais de génération sans réservation atomique pendant la
        # fenêtre commit→deploy→apply-SQL. (PGRST202 = fonction introuvable côté PostgREST.)
        if ("pgrst202" in _msg or "could not find the function" in _msg
                or "does not exist" in _msg or "schema cache" in _msg):
            log.error("[BILLING-ATOMIC] try_hold RPC ABSENTE (SQL non appliqué ?) user=%s intent=%s "
                      "→ FAIL-CLOSED (402 avant OpenAI)", user_id[:8], intent_id)
            return {"granted": False, "reason": "atomic_hold_missing", "bucket": None,
                    "total_before": None, "total_after": None, "idempotent": False}
        # Erreur DB TRANSITOIRE → FAIL-OPEN (parité reserve_decision : un payant n'est
        # jamais bloqué par un hoquet). Observable via reason=fail_open.
        log.warning("[BILLING-ATOMIC] try_hold RPC transient error user=%s intent=%s err=%s → fail-open granted",
                    user_id[:8], intent_id, exc)
        return {"granted": True, "reason": "fail_open", "bucket": None,
                "total_before": None, "total_after": None, "idempotent": False}


# ── RC-PR2 — ACQUISITION (achat/renouvellement → Payment/Order/Pass/GRANT) ────
#
# Chemin ARGENT, distinct de la consommation ci-dessus. Règles propres :
#   • PAS de fail-open : un échec DOIT remonter (l'appelant renvoie non-2xx →
#     RevenueCat retente). Un crédit payé silencieusement perdu est inacceptable.
#   • PAS de skip muet : un produit non mappé lève ProductNotMapped (l'appelant
#     répond non-2xx pour retry — un achat payé ne doit jamais être avalé).
#   • Idempotence + atomicité vivent dans le RPC billing_grant_purchase (1 txn).
# Frontière RC-PR3 : ce chemin CRÉDITE/OBSERVE, il n'enforce rien (reserve_decision
# bypasse encore les premium). Le débit wallet des payants = RC-PR3.


class ProductNotMapped(Exception):
    """Aucun product actif ne matche le store product_id de l'achat. Erreur
    PERMANENTE (retry ne corrige pas) mais on la remonte quand même : l'appelant
    répond non-2xx pour la rendre VISIBLE (dashboard RC + logs), jamais un skip."""

    def __init__(self, store_product_id: str):
        self.store_product_id = store_product_id
        super().__init__(f"no active product mapped for store id {store_product_id!r}")


@dataclass
class GrantResult:
    """Retour de grant_purchase. `status` = 'granted' (1er traitement) |
    'already_processed' (redélivrance idempotente). `credited` = True seulement
    si une NOUVELLE ligne GRANT a été écrite ce coup-ci."""
    ok: bool
    status: str
    credited: bool
    credits: int
    order_id: Optional[str]
    pass_id: Optional[str]


async def _resolve_product(supa, store_product_id: str) -> Optional[dict]:
    """products actif dont revenuecat_product_id OU apple_product_id == l'id store.
    Le mapping est figé en base (migration ticket 0). Renvoie la ligne ou None."""
    res = await asyncio.to_thread(
        lambda: supa.table("products")
        .select("id, type, credits_granted, duration_days")
        .or_(
            f"revenuecat_product_id.eq.{store_product_id},"
            f"apple_product_id.eq.{store_product_id}"
        )
        .eq("active", True)
        .limit(1)
        .execute()
    )
    rows = getattr(res, "data", None) or []
    return rows[0] if rows else None


async def grant_purchase(
    *,
    user_id: str,
    provider: str,
    provider_transaction_id: str,
    store_product_id: str,
    amount=None,
    currency: Optional[str] = None,
    ends_at_iso: Optional[str] = None,
    raw_payload: Optional[dict] = None,
    supa=None,
) -> GrantResult:
    """Achat/renouvellement → Payment + Order + Pass + ledger GRANT → wallet
    crédité, via le RPC atomique billing_grant_purchase. NE swallow AUCUNE erreur
    (≠ chemin conso) : mapping absent → ProductNotMapped ; échec RPC → propagé.

    `provider_transaction_id` DOIT être le transaction_id du CYCLE (chaque RENEWAL
    = nouveau → nouveau Pass+GRANT), jamais original_transaction_id.
    """
    supa = supa or _get_supa()
    product = await _resolve_product(supa, store_product_id)
    if product is None:
        raise ProductNotMapped(store_product_id)

    res = await asyncio.to_thread(
        lambda: supa.rpc(
            "billing_grant_purchase",
            {
                "p_user_id": user_id,
                "p_provider": provider,
                "p_provider_transaction_id": provider_transaction_id,
                "p_product_id": product["id"],
                "p_credits": int(product["credits_granted"]),
                "p_duration_days": product.get("duration_days"),
                "p_amount": amount,
                "p_currency": currency,
                "p_ends_at": ends_at_iso,
                "p_raw_payload": raw_payload or {},
            },
        ).execute()
    )
    data = getattr(res, "data", None)
    if isinstance(data, list):
        data = data[0] if data else None
    data = data or {}
    result = GrantResult(
        ok=bool(data.get("ok")),
        status=data.get("status") or "unknown",
        credited=bool(data.get("credited")),
        credits=int(data.get("credits") or 0),
        order_id=data.get("order_id"),
        pass_id=data.get("pass_id"),
    )
    log.info(
        "[BILLING] grant_purchase user=%s tx=%s status=%s credited=%s credits=%d",
        user_id[:8], provider_transaction_id, result.status, result.credited, result.credits,
    )
    return result


def _iso_in_future(iso) -> bool:
    """True si l'ISO-8601 est dans le futur (best-effort)."""
    try:
        return datetime.fromisoformat(str(iso).replace("Z", "+00:00")) > datetime.now(timezone.utc)
    except (TypeError, ValueError):
        return False


async def _repair_pass_window(supa, *, pass_id: str, ends_at_iso: str) -> bool:
    """P0 (2026-07-10) — aligne un pass sur l'autorité RC : ends_at=expires, status
    ACTIVE. Sert quand RC dit l'abonnement actif mais que le pass local a un ends_at
    périmé (cycle précédent ; le RPC grant fait ON CONFLICT DO NOTHING → l'ancienne
    fenêtre n'est jamais prolongée). N'AJOUTE AUCUN crédit (le GRANT reste idempotent) :
    le bucket = GRANT − HOLDs déjà consommés → pas de double-crédit. Idempotent,
    best-effort (ne lève jamais). Renvoie True si une ligne a été modifiée."""
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("passes")
            .update({"ends_at": ends_at_iso, "status": "ACTIVE"})
            .eq("id", pass_id).execute()
        )
        rows = getattr(res, "data", None) or []
        if rows:
            log.info("[reconcile] pass window repaired pass=%s ends_at=%s", pass_id[:8], ends_at_iso)
        return bool(rows)
    except Exception as exc:  # noqa: BLE001 — best-effort
        log.warning("[reconcile] pass repair failed pass=%s err=%s", pass_id[:8], exc)
        return False


async def reconcile_pass_from_subscriber(*, user_id: str, subscriber: dict, supa=None) -> dict:
    """P0 (2026-07-10) — reconstruit un PASS MESURÉ depuis le subscriber RevenueCat
    (restore / reinstall / device-change / RC transfer / webhook manqué / App Review
    restore). RÉEMPRUNTE le chemin idempotent du webhook (grant_purchase) — ce N'EST
    PAS un pansement : c'est le comportement attendu quand Apple/RC ont un abo actif
    mais que la DB n'a pas (encore) Order/Payment/Pass/GRANT.

    Règles STRICTES :
      • entitlement premium ACTIF requis (sinon 'free') ;
      • product_id mappé (weekly/annual) requis (ProductNotMapped → restore_required) ;
      • store_transaction_id du CYCLE courant requis (JAMAIS original_transaction_id) ;
      • expires_date requis ;
      • data insuffisante → AUCUN pass créé → restore_required + log clair ;
      • JAMAIS unlimited, JAMAIS rôle-seul.
    Idempotent : même appel N fois = 1 seul Order/Payment/Pass/GRANT (grant_purchase
    ON CONFLICT). Même cycle que le webhook (même store_transaction_id) → aucun double.

    Renvoie {state:'pass'|'restore_required'|'free', has_measurable_pass, reason,
             grant_status, product_id, store_tx_present, expires_present, expires_at}.
    """
    supa = supa or _get_supa()
    ent = (((subscriber or {}).get("entitlements") or {}).get("premium")) or {}
    expires = ent.get("expires_date")  # None = lifetime = actif
    active = bool(ent) and (expires is None or _iso_in_future(expires))
    if not active:
        return {"state": "free", "has_measurable_pass": False,
                "reason": "no_active_entitlement", "product_id": None,
                "store_tx_present": False, "expires_present": bool(expires),
                "expires_at": expires}

    product_id = ent.get("product_identifier") or ""
    subs = (subscriber or {}).get("subscriptions") or {}
    sub = (subs.get(product_id) or {}) if product_id else {}
    store_tx = sub.get("store_transaction_id") or ""
    base = {"product_id": product_id or None, "store_tx_present": bool(store_tx),
            "expires_present": bool(expires), "expires_at": expires, "grant_status": None}

    # Data RC insuffisante → PAS de pass arbitraire → restore_required.
    if not product_id or not store_tx or not expires:
        log.warning("[reconcile] insufficient RC data user=%s product_id=%r store_tx=%s "
                    "expires=%s → restore_required", user_id[:8], product_id or None,
                    bool(store_tx), bool(expires))
        return {**base, "state": "restore_required", "has_measurable_pass": False,
                "reason": "insufficient_rc_data"}

    # Grant idempotent — store_transaction_id (cycle courant), JAMAIS original.
    try:
        result = await grant_purchase(
            user_id=user_id, provider="revenuecat",
            provider_transaction_id=store_tx, store_product_id=product_id,
            amount=None, currency=None, ends_at_iso=expires,
            raw_payload={"source": "purchases_sync", "product_id": product_id,
                         "store_transaction_id": store_tx, "expires_date": expires},
            supa=supa,
        )
    except ProductNotMapped:
        log.warning("[reconcile] product NOT mapped user=%s product_id=%s → restore_required",
                    user_id[:8], product_id)
        return {**base, "state": "restore_required", "has_measurable_pass": False,
                "reason": "product_not_mapped"}
    except Exception as exc:  # noqa: BLE001 — sync = best-effort (≠ voie webhook stricte)
        log.error("[reconcile] grant failed user=%s tx=%s err=%s: %s",
                  user_id[:8], store_tx, type(exc).__name__, exc)
        return {**base, "state": "restore_required", "has_measurable_pass": False,
                "reason": "grant_error"}

    # RÉPARATION (B′) — RC dit l'abonnement ACTIF (expires futur) : garantir que le pass
    # est ACTIF jusqu'à l'autorité RC, même si grant a fait already_processed sur un pass
    # au ends_at périmé. Sinon : entitlement actif ↔ aucun pass actif chez nous = deny.
    repaired = False
    if result.pass_id and _iso_in_future(expires):
        repaired = await _repair_pass_window(supa, pass_id=result.pass_id, ends_at_iso=expires)
        if repaired:
            await _reproject_wallet(user_id=user_id, supa=supa)
    log.info("[reconcile] pass reconciled user=%s product_id=%s status=%s credited=%s repaired=%s",
             user_id[:8], product_id, result.status, result.credited, repaired)
    return {**base, "state": "pass", "has_measurable_pass": True,
            "reason": None, "grant_status": result.status, "repaired": repaired}
