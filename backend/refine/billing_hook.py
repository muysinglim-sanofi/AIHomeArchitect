"""Refine Engine V2 — Composant 7 : BILLING HOOK (CÂBLÉ mais DÉSACTIVÉ).

Contrat (R1) : **1 étape de refine = 1 génération = 1 crédit** (reserve→commit).
Retry = +1 crédit, consenti d'avance. Comme CHAQUE génération est affichée, le
crédit est TOUJOURS committé — pas de refund auto (le modèle auto-retry avec
remboursement a été REJETÉ). Pas de crédit caché : 1 crédit ↔ 1 image montrée.

Activé UNIQUEMENT quand le Billing enforce sera branché sur /refine
(flag `AYDEN_REFINE_BILLING`, défaut OFF). D'ici là : **NO-OP** (allow, ne débite pas).
Point d'entrée figé pour brancher `billing.reserve/commit` (cf. billing_engine_v1_direction)
sans re-toucher l'orchestrateur ni l'endpoint.
"""
from __future__ import annotations

import os


def refine_billing_enabled() -> bool:
    """Défaut OFF. Passera à ON quand le Billing Engine sera branché sur le refine."""
    return os.environ.get("AYDEN_REFINE_BILLING", "0").strip().lower() in ("1", "true", "yes", "on")


async def reserve(user_id: str, refine_intent_id: str, *, supa=None) -> bool:
    """Réserve 1 crédit pour cette étape de refine. NO-OP (allow) tant que désactivé.
    Renvoie True = autorisé à générer. (Quand activé : billing.reserve_decision/HOLD.)"""
    if not refine_billing_enabled():
        return True
    # TODO (Billing enforce refine) : brancher billing.reserve(user_id, refine_intent_id)
    #   deny → renvoyer False → l'endpoint lève 402 vers le paywall.
    return True


async def commit(user_id: str, refine_intent_id: str, *, supa=None) -> None:
    """Committe le crédit (la génération a eu lieu et l'image est montrée). NO-OP si désactivé."""
    if not refine_billing_enabled():
        return
    # TODO (Billing enforce refine) : brancher billing.apply_billing(... SUCCEEDED) sur refine_intent_id.
    return
