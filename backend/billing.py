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
  (1re gen d'un user) → TRIAL(+3)  trial:<user_id>
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
from dataclasses import dataclass
from typing import Optional

log = logging.getLogger("billing")

TRIAL_CREDITS = 3


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
    reference_id: Optional[str] = None,
) -> bool:
    """INSERT append-only, idempotent par idempotency_key (ON CONFLICT DO NOTHING).
    Renvoie True si NOUVELLE ligne, False si déjà présente (dup) ou erreur. Ne
    fait jamais d'UPDATE (le trigger append-only l'interdirait)."""
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


async def _reproject_wallet(*, user_id: str, supa=None) -> None:
    """Recalcule le wallet DEPUIS le ledger (projection) et l'upsert. Jamais un
    `wallet += delta` aveugle → toujours cohérent avec la vérité (le ledger).

    TODO (Billing PR2/PR3, une fois l'observation validée) : PROJECTION
    INCRÉMENTALE. Ce recompute lit TOUT le ledger de l'user à chaque événement —
    acceptable en PR1 (volumes faibles, observation), mais O(ledger) par écriture
    ne passe pas à l'échelle (100k → 5M lignes). Remplacer par une mise à jour
    incrémentale (available += delta) + re-check périodique. Le ledger reste la
    source de vérité ; le wallet n'a pas besoin d'un recompute intégral à chaque HOLD.
    """
    supa = supa or _get_supa()
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("ledger_entries")
            .select("entry_type, available_delta, id").eq("user_id", user_id).execute()
        )
        rows = getattr(res, "data", None) or []
    except Exception as exc:
        log.warning("[BILLING] wallet reproject fetch failed user=%s err=%s", user_id, exc)
        return
    available = sum(int(r.get("available_delta") or 0) for r in rows)
    holds = sum(1 for r in rows if r.get("entry_type") == "HOLD")
    closed = sum(1 for r in rows if r.get("entry_type") in ("RELEASE", "COMMIT"))
    held = holds - closed  # §4.6 : #HOLD − #RELEASE − #COMMIT
    version = max((int(r.get("id") or 0) for r in rows), default=0)
    try:
        await asyncio.to_thread(
            lambda: supa.table("wallets")
            .upsert({
                "user_id": user_id,
                "available_credits": available,
                "held_credits": held,
                "ledger_version": version,
                "updated_at": "now()",
            }, on_conflict="user_id")
            .execute()
        )
    except Exception as exc:
        log.warning("[BILLING] wallet upsert failed user=%s err=%s", user_id, exc)


async def _emit(supa, *, user_id: str, entry_type: str, delta: int, key: str,
                intent_id: Optional[str]) -> None:
    """Écrit une entrée ledger (idempotente) puis reprojette le wallet si nouvelle."""
    new = await _ledger_insert(
        supa, user_id=user_id, entry_type=entry_type, available_delta=delta,
        idempotency_key=key,
        reference_type="GENERATION_INTENT" if intent_id else None,
        reference_id=intent_id,
    )
    if new:
        log.info("[BILLING] %s(%+d) key=%s user=%s", entry_type, delta, key, user_id[:8])
        await _reproject_wallet(user_id=user_id, supa=supa)


# ── Public API (les hooks n'appellent QUE ça) ────────────────────────────────


async def grant_trial(*, user_id: str, supa=None) -> None:
    """TRIAL(+3) une seule fois par user (idempotent trial:<user_id>)."""
    supa = supa or _get_supa()
    new = await _ledger_insert(
        supa, user_id=user_id, entry_type="TRIAL", available_delta=TRIAL_CREDITS,
        idempotency_key=f"trial:{user_id}", reference_type="PROMO", reference_id="trial",
    )
    if new:
        log.info("[BILLING] TRIAL(+%d) user=%s", TRIAL_CREDITS, user_id[:8])
        await _reproject_wallet(user_id=user_id, supa=supa)


@dataclass
class ReserveDecision:
    """Résultat du gate wallet (lecture seule). `wallet_available` = solde
    available AVANT tout TRIAL pending ; `effective` = ce que le gate voit."""
    allow: bool
    wallet_available: int
    effective: int
    reason: str          # "" (allow) | "bypass" | "insufficient_credits" | "fail_open"


async def reserve_decision(
    *, user_id: str, is_free: bool, supa=None,
) -> ReserveDecision:
    """Billing PR2b (voie a) — GATE wallet (§2.3), **LECTURE SEULE**. Décide si
    l'user peut lancer une génération. Appelé dans /generate AVANT le claim :
    aucune écriture (le HOLD est posé APRÈS le claim-won) → respecte « aucune
    réservation avant ownership ».
      • entitled (is_free=False) → allow (bypass R8), AUCUNE lecture.
      • free → effective = available + (TRIAL si pas encore accordé) ; allow = effective ≥ 1.
    FAIL-OPEN sur erreur de lecture (fiabilité > double rare, cf. philosophie du
    claim) : un hoquet DB ne bloque jamais un user ; observable via reason=fail_open.
    """
    supa = supa or _get_supa()
    if not is_free:
        # admin / premium / promo → bypass (R8 + tiers entitled) : pas de gate wallet.
        return ReserveDecision(allow=True, wallet_available=0, effective=0, reason="bypass")
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("ledger_entries")
            .select("entry_type, available_delta")
            .eq("user_id", user_id).execute()
        )
        rows = getattr(res, "data", None) or []
    except Exception as exc:  # noqa: BLE001 — FAIL-OPEN : ne bloque jamais sur hoquet DB
        log.warning("[BILLING-GATE] enforce read failed user=%s err=%s → fail-open allow",
                    user_id[:8], exc)
        return ReserveDecision(allow=True, wallet_available=0, effective=0, reason="fail_open")
    available = sum(int(r.get("available_delta") or 0) for r in rows)
    trial_granted = any(r.get("entry_type") == "TRIAL" for r in rows)
    # Solde PRÉ-HOLD : le HOLD sera posé après le claim. On ajoute le +3 « qui
    # serait accordé » (grant_trial idempotent) si le TRIAL n'est pas déjà là.
    effective = available + (0 if trial_granted else TRIAL_CREDITS)
    allow = effective >= 1
    reason = "" if allow else "insufficient_credits"
    log.info(
        "[BILLING-GATE] enforce user=%s available=%d trial=%s effective=%d decision=%s reason=%s",
        user_id[:8], available, "granted" if trial_granted else "pending",
        effective, "allow" if allow else "deny", reason or "-",
    )
    return ReserveDecision(
        allow=allow, wallet_available=available, effective=effective, reason=reason)


async def apply_billing_for_intent_transition(
    *, intent_id: str, new_status: str, user_id: Optional[str] = None,
    is_free: bool = True, supa=None,
) -> None:
    """Projette l'effet ledger d'une transition d'Intent (RUNNING/terminal).
    Point d'entrée UNIQUE appelé par les émetteurs. Idempotent, best-effort,

    Billing PR2b (D-e) — `is_free=False` (entitled admin/premium/promo) → **AUCUNE
    écriture** (ni TRIAL, ni HOLD/COMMIT/RELEASE) : le ledger reste propre pour
    les tiers non facturables (ils bypass le gate wallet). Défaut True → un
    appelant non mis à jour facture (jamais un skip silencieux).
    Suite du docstring d'origine :
    ne lève jamais, AUCUN gate. Projection directe (voir _decide) — pas de
    compensation ni de lecture du passé.
    """
    supa = supa or _get_supa()
    # D-e — entitled : aucune écriture ledger (bypass le gate wallet).
    if not is_free:
        return
    decision = _decide(new_status)
    if decision is None:
        return
    if user_id is None:
        user_id = await _intent_user_id(supa, intent_id)
        if user_id is None:
            log.warning("[BILLING] no user for intent=%s status=%s — skip", intent_id, new_status)
            return

    # Règle « TRIAL à la 1re génération du user » — décidée ICI (pas dans le hook).
    if new_status == "RUNNING":
        await grant_trial(user_id=user_id, supa=supa)

    entry_type, delta, prefix = decision
    await _emit(supa, user_id=user_id, entry_type=entry_type, delta=delta,
                key=f"{prefix}:{intent_id}", intent_id=intent_id)
