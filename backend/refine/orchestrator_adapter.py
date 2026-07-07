"""Refine ↔ Generation Orchestrator — adaptateur (Phase 1). NON branché ici.

Callbacks moteur consommés par l'orchestrateur générique, pour le refine :
  • build_execute_fn(client, frozen_prompt) → execute_fn : SEUL l'appel image, prompt FIGÉ
  • build_persist_result_fn(...)            → persist_result_fn IDEMPOTENT (get-or-create/intent_id)
  • build_response_fn(...)                  → enveloppe 'completed' + versions ledger déterministes
  • reconstruct_result_ref(row)             → reconcile : rebuild result_ref depuis image_result

Idempotence des artefacts (3 fenêtres de crash) :
  storage_path + result_version_id DÉTERMINISTES depuis intent_id ; upload upsert ;
  le result_ref durable de l'intent (generation_intents.result_ref) est la SOURCE DE
  VÉRITÉ du get-or-create → un re-run réutilise, jamais 2 objets/2 versions.
IO (upload / get-result-ref / set-result-ref / message) INJECTÉ → mock.
Moteur 2 isolé : n'importe NI main NI /generate.
"""
from __future__ import annotations

from typing import Awaitable, Callable, Optional

from refine import identity
from refine.executor import execute as _executor_execute
from version_state import VersionRecord, parse_versions, serialize_versions

_REFINE_SOURCE_MODE = "REFINE"


def build_execute_fn(client, frozen_prompt: str):
    """execute_fn(ctx) → bytes : l'appel image avec le prompt FIGÉ (préparé UNE fois
    dehors). Un retry ne recalcule NI Normalizer NI Planner NI prompt."""
    async def _execute(ctx) -> bytes:
        return await _executor_execute(client, ctx.image_bytes, ctx.mime, frozen_prompt)
    return _execute


def _result_ref(*, intent_id, operation_id, session_id, source_version_id, source_image_url,
                result_version_id, storage_path, generated_image_url, iteration,
                room_type, atmosphere, user_request, structural_permission,
                structural_identity_token, finalizable: bool = False) -> dict:
    """result_ref COMPACT & DURABLE (pas de base64, pas d'URL signée temporaire) —
    contient TOUT le nécessaire pour reconstruire le VersionRecord à l'identique (replay).
    `finalizable` = True UNIQUEMENT quand upload + message + version + métadonnées sont
    tous durables (le reconcile ne finalise que sur ce marqueur — jamais un JSON partiel)."""
    return {
        "intent_id": intent_id, "operation_id": operation_id, "session_id": session_id,
        "source_version_id": source_version_id or "", "source_image_url": source_image_url or "",
        "result_version_id": result_version_id, "storage_path": storage_path,
        "generated_image_url": generated_image_url, "iteration": int(iteration or 0),
        "room_type": room_type or "", "atmosphere": atmosphere or "",
        "user_request": (user_request or "")[:240],
        "structural_permission": bool(structural_permission),
        "structural_identity_token": structural_identity_token or "",
        "finalizable": bool(finalizable),
    }


def reconstruct_result_ref(image_result_row: dict) -> dict:
    """Reconcile : reconstruit un result_ref depuis une ligne persistée. Déterministe."""
    return _result_ref(
        intent_id=image_result_row.get("intent_id", ""),
        operation_id=image_result_row.get("operation_id", ""),
        session_id=image_result_row.get("session_id", ""),
        source_version_id=image_result_row.get("source_version_id", ""),
        source_image_url=image_result_row.get("source_image_url", ""),
        result_version_id=image_result_row.get("result_version_id", ""),
        storage_path=image_result_row.get("storage_path", ""),
        generated_image_url=image_result_row.get("generated_image_url", ""),
        iteration=image_result_row.get("iteration", 0),
        room_type=image_result_row.get("room_type", ""),
        atmosphere=image_result_row.get("atmosphere", ""),
        user_request=image_result_row.get("user_request", ""),
        structural_permission=image_result_row.get("structural_permission", False),
        structural_identity_token=image_result_row.get("structural_identity_token", ""))


def _version_record(result_ref: dict) -> VersionRecord:
    """VersionRecord DÉTERMINISTE reconstruit depuis le result_ref (source_mode=REFINE,
    version_id déterministe) → success ET replay produisent le MÊME enregistrement."""
    return VersionRecord(
        version_id=result_ref.get("result_version_id", ""),
        vision_number=int(result_ref.get("iteration") or 0),
        source_mode_used=_REFINE_SOURCE_MODE,
        source_version_id_used=result_ref.get("source_version_id", ""),
        source_image_url_used=result_ref.get("source_image_url", ""),
        generated_image_url=result_ref.get("generated_image_url", ""),
        atmosphere=result_ref.get("atmosphere", ""),
        user_request=result_ref.get("user_request", ""),
        structural_permission=bool(result_ref.get("structural_permission")),
        structural_identity_token=result_ref.get("structural_identity_token", ""),
        lineage_customized=True,   # un refine = édition explicite → lignée customisée
    )


def build_persist_result_fn(
    *,
    upload_fn: Callable[[str, bytes], Awaitable[str]],                    # (path, bytes) -> durable url (UPSERT)
    get_result_ref_fn: Callable[[str], Awaitable[Optional[dict]]],        # (intent_id) -> result_ref|None
    set_result_ref_fn: Callable[[str, dict], Awaitable[bool]],            # (intent_id, ref) -> bool (strict)
    persist_message_fn: Callable[..., Awaitable[None]],                   # IDEMPOTENT par intent_id
    source_image_url: str = "", atmosphere: str = "", room_type: str = "",
    style_label: str = "", user_request: str = "", structural_permission: bool = False,
    structural_identity_token: str = "",
):
    """persist_result_fn(ctx, bytes) — GET-OR-CREATE idempotent, PERSISTANCE COMPLÈTE.
    ORDRE (le marqueur finalizable est écrit EN DERNIER, après TOUS les artefacts durables) :
      1. upload upsert (storage_path déterministe → 1 objet)
      2. message image_result IDEMPOTENT par intent_id (jamais rejoué en double, jamais manquant)
      3. result_ref COMPLET (finalizable=True) écrit via set_result_ref (dernier)
    Source de vérité du get-or-create = generation_intents.result_ref (présent ⟺ finalizable).
    Un re-run après crash rejoue upload(upsert) + message(idempotent) + set_result_ref → jamais
    de doublon, jamais de message manquant. Couvre les 3 fenêtres de crash (cf. tests)."""
    async def _persist(ctx, generated_bytes: bytes) -> dict:
        existing = await get_result_ref_fn(ctx.intent_id)
        if existing and existing.get("finalizable") is True:   # COMPLET → réutiliser
            return existing
        version_id = identity.refine_result_version_id(ctx.intent_id)
        storage_path = identity.refine_storage_path(ctx.session_id, ctx.intent_id)   # déterministe
        url = await upload_fn(storage_path, generated_bytes)                          # 1. upsert → 1 objet
        await persist_message_fn(                                                     # 2. message IDEMPOTENT
            session_id=ctx.session_id, before_url=source_image_url, after_url=url,
            style_label=style_label, intent_id=ctx.intent_id, result_version_id=version_id)
        ref = _result_ref(                                                            # 3. tout durable → finalizable
            intent_id=ctx.intent_id, operation_id=ctx.operation_id, session_id=ctx.session_id,
            source_version_id=ctx.meta.get("source_version_id", ""), source_image_url=source_image_url,
            result_version_id=version_id, storage_path=storage_path, generated_image_url=url,
            iteration=ctx.iteration, room_type=room_type, atmosphere=atmosphere,
            user_request=user_request, structural_permission=structural_permission,
            structural_identity_token=structural_identity_token, finalizable=True)
        await set_result_ref_fn(ctx.intent_id, ref)          # 4. result_ref FINAL (marqueur) — EN DERNIER
        return ref
    return _persist


def build_response_fn(*, prior_versions_json: str = "", conflicts=None, changes=None,
                      estimated_success: float = 0.0):
    """Enveloppe 'completed' du contrat /refine. Reconstruit `versions` de façon
    DÉTERMINISTE (prior + VersionRecord refine), DÉDUP par version_id → un replay
    SUCCEEDED restitue EXACTEMENT la même version (aucune duplication)."""
    def _resp(result_ref: dict) -> dict:
        prior = parse_versions(prior_versions_json)
        rec = _version_record(result_ref)
        versions = prior if any(v.version_id == rec.version_id for v in prior) else prior + [rec]
        return {
            "status": "completed",
            "after_image_url": result_ref.get("generated_image_url", ""),
            "image_url": result_ref.get("generated_image_url", ""),
            "intent_id": result_ref.get("intent_id", ""),
            "result_version_id": rec.version_id,
            "version_id": rec.version_id,
            "version_record": {"version_id": rec.version_id, "source_mode_used": rec.source_mode_used,
                               "source_version_id_used": rec.source_version_id_used},
            "source_version_id": rec.source_version_id_used,
            "source_mode": _REFINE_SOURCE_MODE,
            "room_type": result_ref.get("room_type", ""),
            "ai_message": "",                        # refine : la voix vient du verify (§14)
            "verification": "deferred",
            "estimated_success": estimated_success,
            "conflicts": conflicts or [],
            "changes": changes or [],
            "versions": serialize_versions(versions),
        }
    return _resp
