"""Refine Engine V2 — Identité d'opération (Phase 1 : Generation Orchestrator).

Une SOUMISSION utilisateur = un `operation_id` (frappé côté frontend, stable sur
retry technique/timeout, neuf par nouvelle commande volontaire). Le backend en
dérive une identité 100 % DÉTERMINISTE : `intent_id`, `result_version_id`,
`storage_path` — tous keyés sur l'intent_id → un re-run reproduit EXACTEMENT les
mêmes artefacts (idempotence par id déterministe, SANS table serveur `versions`).

RÈGLE VERROUILLÉE (contrainte A) : le message / les `changes` ne sont JAMAIS dans
la clé d'idempotence — uniquement dans `intent_meta` (observabilité). Deux
commandes différentes sur la même source partagent un `operation_id` DIFFÉRENT
(frappé par soumission), donc un intent_id différent.

Moteur 2 isolé : n'importe NI main, NI le composer, NI la DNA/préservation.
"""
from __future__ import annotations

import hashlib
from typing import Optional


def _h16(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()[:16]


def refine_intent_id(user_id: str, session_id: str, operation_id: str) -> str:
    """Déterministe depuis (user, session, operation_id). Même operation_id → même
    intent_id → `claim_intent` dédupe (double-tap/timeout/retry technique). Nouvelle
    soumission volontaire → nouvel operation_id → nouvel intent_id. Message HORS clé."""
    return "refine:" + _h16(f"{user_id}|{session_id}|{operation_id}")


def refine_result_version_id(intent_id: str) -> str:
    """version_id LOGIQUE déterministe depuis l'intent_id. Le frontend déduplique/adopte
    par cet id → une SEULE version visible, même si la persistance est rejouée après
    un crash entre upload et SUCCEEDED."""
    return "vrf_" + _h16(intent_id)


def refine_storage_path(session_id: str, intent_id: str) -> str:
    """Chemin storage DÉTERMINISTE (upload upsert=True) → UN SEUL objet logique par
    intent, quel que soit le nombre de re-runs. Pas de `uuid4()` par appel."""
    return f"{session_id or 'refine'}/refine_{_h16(intent_id)}.jpg"


def build_intent_meta(
    *,
    operation_id: str,
    source_version_id: str = "",
    changes_sig: str = "",
    edit_mode: str = "",
    iteration: int = 0,
    room_type: str = "",
    atmosphere: str = "",
    retry_of_intent_id: Optional[str] = None,
) -> dict:
    """Le blob `intent` jsonb (trace/observabilité) — PAS la clé d'idempotence.
    `changes_sig` = sha1 des changes (trace seulement). `retry_of_intent_id` relie un
    Retry-après-FAILED volontaire à l'intent terminal précédent (on ne le rouvre pas)."""
    meta = {
        "engine": "refine",
        "operation_id": operation_id,
        "source_version_id": source_version_id or "",
        "changes_sig": changes_sig or "",
        "edit_mode": edit_mode or "",
        "iteration": int(iteration or 0),
        "room": room_type or "",
        "atmosphere": atmosphere or "",
    }
    if retry_of_intent_id:
        meta["retry_of_intent_id"] = retry_of_intent_id
    return meta


def changes_signature(changes) -> str:
    """sha1 des clauses `raw` ordonnées — TRACE seulement, jamais la clé."""
    joined = "|".join((getattr(c, "raw", "") or "") for c in (changes or []))
    return hashlib.sha1(joined.encode("utf-8")).hexdigest()[:12]
