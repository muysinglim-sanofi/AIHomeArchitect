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
from datetime import datetime, timezone
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
    *, user_id: str, is_free: bool, tier: str = "free", supa=None,
) -> ReserveDecision:
    """GATE wallet, **LECTURE SEULE**. Décide si l'user peut lancer une génération.
    Appelé dans /generate (et /refine) AVANT le claim : aucune écriture (le HOLD est
    posé APRÈS le claim-won) → « aucune réservation avant ownership ».

    RC-PR3b — le rôle premium n'est PLUS l'autorité de génération illimitée :
      • free (is_free=True) → bucket free + TRIAL ; allow = effective ≥ 1. (RC-PR2b, inchangé)
      • admin / promo_unlimited / promo_limited → bypass (illimité réel, ou promo métré
        par le resolver qui a déjà garanti remaining > 0).
      • premium (rôle abonnement) → MÉTRÉ par le PASS ACTIF : allow = solde bucket pass ≥ 1,
        sinon deny (pass_exhausted). Aucune gen ne démarre à 0.
      • premium SANS pass actif (ni admin/promo) → état INCOHÉRENT : log.error + deny
        (no_active_pass) — JAMAIS unlimited silencieux (cf. docs/RC_PR3B_ENFORCEMENT.md).
    FAIL-OPEN sur erreur de lecture (fiabilité > double rare) : un hoquet DB ne bloque
    jamais ; observable via reason=fail_open / pass bucket fail-open.
    """
    supa = supa or _get_supa()
    if not is_free:
        # RC-PR3b — seuls admin & promo_unlimited sont illimités ; promo_limited est
        # déjà borné par le resolver (tier retombe à free quand épuisé).
        if tier in ("admin", "promo_unlimited", "promo_limited"):
            return ReserveDecision(allow=True, wallet_available=0, effective=0, reason="bypass")
        # tier == "premium" (rôle abonnement) → la génération vient du PASS ACTIF.
        pass_id = await _active_pass_id(supa, user_id)
        if pass_id is None:
            # Rôle premium mais aucun pass mesurable, et pas admin/promo → incohérent.
            log.error(
                "[BILLING-GATE] RC-PR3b entitled premium WITHOUT active pass (incohérent) "
                "user=%s tier=%s → DENY (jamais unlimited silencieux)", user_id[:8], tier)
            return ReserveDecision(allow=False, wallet_available=0, effective=0, reason="no_active_pass")
        available = await _pass_bucket_available(supa, user_id, pass_id)
        allow = available >= 1
        log.info("[BILLING-GATE] RC-PR3b pass gate user=%s pass=%s available=%d decision=%s",
                 user_id[:8], pass_id[:8], available, "allow" if allow else "deny")
        return ReserveDecision(
            allow=allow, wallet_available=available, effective=available,
            reason="" if allow else "pass_exhausted")
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
    ne lève jamais, AUCUN gate. Projection directe (voir _decide) — pas de
    compensation ni de lecture du passé.

    Deux régimes de consommation :
      • FREE tier (`is_free=True`) : TRIAL à la 1re gen + HOLD/COMMIT/RELEASE dans
        le bucket free (pass_id=None). Inchangé.
      • ENTITLED (`is_free=False`) — RC-PR3a : si l'user a un PASS ACTIF (mesuré),
        on débite le bucket de CE pass (HOLD/COMMIT/RELEASE scoppés au pass_id →
        net −1 par gen réussie, 0 sur échec). Sinon (admin / promo / premium-
        sans-pass = illimité) → AUCUNE écriture (comme avant). PAS de grant_trial.
    L'enforcement (blocage à 0) N'EST PAS ici : `reserve_decision` reste bypass
    pour les entitled (RC-PR3b = ticket séparé). On MESURE, on ne bloque pas.
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

    # RC-PR3a — entitled : débite le PASS ACTIF (mesuré) ; admin/promo/premium-
    # sans-pass (pas de pass actif) → illimité, aucune écriture.
    if not is_free:
        pass_id = await _active_pass_id(supa, user_id)
        if pass_id is None:
            return
        await _emit(supa, user_id=user_id, entry_type=entry_type, delta=delta,
                    key=key, intent_id=intent_id, pass_id=pass_id)
        return

    # ── FREE tier (inchangé) : TRIAL à la 1re gen du user + HOLD/COMMIT/RELEASE ──
    if new_status == "RUNNING":
        await grant_trial(user_id=user_id, supa=supa)
    await _emit(supa, user_id=user_id, entry_type=entry_type, delta=delta,
                key=key, intent_id=intent_id)


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

    log.info("[reconcile] pass reconciled user=%s product_id=%s status=%s credited=%s",
             user_id[:8], product_id, result.status, result.credited)
    return {**base, "state": "pass", "has_measurable_pass": True,
            "reason": None, "grant_status": result.status}
