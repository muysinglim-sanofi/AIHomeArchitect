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
