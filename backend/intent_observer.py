"""
Generation Intent v1 — PR1 : observation pure.

Spec : docs/GENERATION_INTENT_V1_SPEC.md (§2 identité, §5 tables, §13 plan PR1).

Ce module donne une existence PERSISTÉE à l'intention de génération, en
OBSERVATION uniquement. Il n'enforce rien :

  • AUCUN claim, AUCUN court-circuit — le garde d'idempotence actuel
    (client_request_id, main.py) reste la clé active.
  • Toutes les fonctions observe_* sont BEST-EFFORT : elles avalent leurs
    erreurs (comme confirm/fail_generation dans quota.py) et ne peuvent
    JAMAIS faire échouer /generate.
  • Zéro impact DNA / preservation / fidelity / openai.images.edit.

Objectif : mesurer en prod, sur des lignes persistées, la gate-of-proof
(§2.2) et « 1 Intent / N Jobs » AVANT de basculer le claim en source de
vérité (PR2).

API
───
compute_intent_id(...)                 → IntentIdentity  (fonction PURE)
observe_intent_start(intent_id, ...)   → "NEW" | "DUP" | None
observe_job_start(intent_id, attempt)  → job_id (str) | None
observe_job_end(job_id, status, ...)   → None
observe_intent_end(intent_id, status)  → None
"""

from __future__ import annotations

import asyncio
import hashlib
import logging
import uuid
from dataclasses import dataclass
from typing import Any, Optional

log = logging.getLogger("generation_intent.observer")


def _get_supa():
    """Lazy import to avoid a circular dependency at module load (mirrors quota.py)."""
    from main import supa  # noqa: PLC0415
    return supa


# ── Identité de l'Intent (fonction pure) ─────────────────────────────────────


@dataclass(frozen=True)
class IntentIdentity:
    """Résultat de compute_intent_id. `id` = l'intent_id déterministe.

    Les autres champs sont les composantes normalisées (utiles pour le log
    [INTENT-ID] existant et pour la colonne jsonb `intent`).
    """
    id: str
    src_sha1: str
    room: str
    atmosphere: str
    mode: str
    source_mode: str
    prompt_dir: str
    revision: str

    @property
    def action(self) -> str:
        # Format historique : "{mode}|{source_mode}|{prompt_dir}"
        return f"{self.mode}|{self.source_mode}|{self.prompt_dir}"

    @property
    def intent_dict(self) -> dict:
        # Colonne jsonb `intent` de generation_intents (§5.1).
        return {
            "room": self.room,
            "atmosphere": self.atmosphere,
            "mode": self.mode,
            "source_mode": self.source_mode,
            "src_sha1": self.src_sha1,
            "revision": self.revision,
        }


def compute_intent_id(
    *,
    user_id: str,
    session_id: str,
    source_version_id: str,
    original_image_url: str,
    before_image_url: str,
    iteration: int,
    room_type_id: str,
    room_type: str,
    atmosphere_id: str,
    style_label: str,
    prompt: str,
    generation_mode: str,
    source_mode: str,
    generation_attempt: str,
    let_ai_decide: bool,
    surprise_me_flag: bool,
) -> IntentIdentity:
    """Calcule l'intent_id déterministe (backend-authoritative, spec §3).

    ⚠️ Réplique À L'IDENTIQUE l'ancien calcul [INTENT-ID] de main.py
    (composition, ordre des champs, défauts, troncatures) — le hash DOIT
    rester byte-identique pour préserver la gate-of-proof (§2.2). Ne PAS
    « améliorer » la recette ici sans re-valider la gate-of-proof en prod.
    """
    src_ref = (source_version_id or original_image_url or before_image_url or "").strip()
    src_sha1 = hashlib.sha1(src_ref.encode("utf-8")).hexdigest()[:12] if src_ref else "(nosrc)"

    atmosphere = (
        "let-decide" if let_ai_decide
        else "surprise" if surprise_me_flag
        else (atmosphere_id or style_label or "(none)").strip()
    )
    room = "let-decide" if let_ai_decide else (room_type_id or room_type or "(none)").strip()

    prompt_dir = (
        hashlib.sha1(prompt.encode("utf-8")).hexdigest()[:8]
        if (prompt or "").strip() else "noprompt"
    )
    mode = generation_mode or "preserve"
    src_mode = source_mode or "default"
    revision = (generation_attempt or "0").strip()

    raw = (
        f"{user_id}:{session_id}:{src_sha1}:{iteration}:"
        f"{room}:{mode}|{src_mode}|{prompt_dir}:{atmosphere}:{revision}"
    )
    intent_id = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12]

    return IntentIdentity(
        id=intent_id,
        src_sha1=src_sha1,
        room=room,
        atmosphere=atmosphere,
        mode=mode,
        source_mode=src_mode,
        prompt_dir=prompt_dir,
        revision=revision,
    )


# ── Observation (best-effort — ne lève jamais) ───────────────────────────────


def _session_uuid_or_none(session_id: Optional[str]) -> Optional[str]:
    # Comme quota.reserve_generation : 'new'/'' (non-uuid) → NULL en base.
    return session_id if session_id and session_id not in ("new", "") else None


async def observe_intent_start(
    *,
    intent_id: str,
    user_id: str,
    session_id: Optional[str],
    iteration: int,
    intent: dict,
    client_request_id: str,
    supa=None,
) -> Optional[str]:
    """Upsert generation_intents (status=RUNNING) en ON CONFLICT DO NOTHING.

    Renvoie "NEW" (première observation de cet intent_id) ou "DUP" (déjà vu
    — c'est la PREUVE directe de GATE 2 : un duplicata qui, aujourd'hui,
    serait masqué par le garde d'idempotence). Best-effort → None si erreur.

    N'ENFORCE RIEN : l'appelant continue exactement comme aujourd'hui,
    qu'on renvoie NEW ou DUP.
    """
    supa = supa or _get_supa()
    row = {
        "intent_id": intent_id,
        "user_id": user_id,
        "session_id": _session_uuid_or_none(session_id),
        "iteration": iteration,
        "status": "RUNNING",
        "intent": intent,
        "client_request_id": client_request_id,
        "started_at": "now()",
    }
    try:
        result = await asyncio.to_thread(
            lambda: supa.table("generation_intents")
            .upsert(row, on_conflict="intent_id", ignore_duplicates=True)
            .execute()
        )
        # ignore_duplicates : data non-vide = ligne insérée (NEW) ;
        # data vide = conflit ignoré (DUP).
        is_new = bool(getattr(result, "data", None))
        verdict = "NEW" if is_new else "DUP"
        if not is_new:
            # DUP — la MÊME intention est refirée (preuve GATE 2). Incrément
            # ATOMIQUE de fire_count sur la ligne existante (RPC — un simple
            # UPDATE SET x=x+1, non exprimable via PostgREST) pour que %DUP soit
            # une métrique SQL de premier ordre. Best-effort : n'affecte rien.
            try:
                await asyncio.to_thread(
                    lambda: supa.rpc(
                        "increment_intent_fire", {"p_intent_id": intent_id}
                    ).execute()
                )
            except Exception as inc_exc:
                log.warning(
                    "[INTENT-OBS] fire_count increment failed (swallowed) "
                    "intent_id=%s err=%s: %s",
                    intent_id, type(inc_exc).__name__, inc_exc,
                )
        log.info(
            "[INTENT-OBS] intent_start intent_id=%s result=%s user=%s session=%s iter=%s",
            intent_id, verdict, user_id[:8], session_id or "(none)", iteration,
        )
        return verdict
    except Exception as exc:
        log.warning(
            "[INTENT-OBS] intent_start FAILED (swallowed) intent_id=%s err=%s: %s",
            intent_id, type(exc).__name__, exc,
        )
        return None


async def observe_job_start(intent_id: str, attempt_no: int, *, supa=None) -> Optional[str]:
    """Insert une ligne generation_jobs (status=RUNNING) pour cette tentative.

    Renvoie le job_id (uuid) pour clôture ultérieure, ou None si erreur /
    conflit (ex. duplicata sur (intent_id, attempt_no) — évidence, avalée).
    """
    supa = supa or _get_supa()
    job_id = str(uuid.uuid4())
    try:
        await asyncio.to_thread(
            lambda: supa.table("generation_jobs")
            .insert({
                "job_id": job_id,
                "intent_id": intent_id,
                "attempt_no": attempt_no,
                "status": "RUNNING",
                "started_at": "now()",
            })
            .execute()
        )
        log.info(
            "[INTENT-OBS] job_start intent_id=%s attempt=%d job=%s",
            intent_id, attempt_no, job_id,
        )
        return job_id
    except Exception as exc:
        log.warning(
            "[INTENT-OBS] job_start FAILED (swallowed) intent_id=%s attempt=%d err=%s: %s",
            intent_id, attempt_no, type(exc).__name__, exc,
        )
        return None


async def observe_job_end(
    job_id: Optional[str],
    status: str,
    *,
    error_type: Optional[str] = None,
    cost_usd_estimate: Optional[float] = None,
    openai_request_id: Optional[str] = None,
    supa=None,
) -> None:
    """UPDATE generation_jobs (status terminal SUCCEEDED|FAILED). Best-effort."""
    if not job_id:
        return
    supa = supa or _get_supa()
    patch: dict[str, Any] = {"status": status, "ended_at": "now()"}
    if error_type is not None:
        patch["error_type"] = error_type
    if cost_usd_estimate is not None:
        patch["cost_usd_estimate"] = cost_usd_estimate
    if openai_request_id is not None:
        patch["openai_request_id"] = openai_request_id
    try:
        await asyncio.to_thread(
            lambda: supa.table("generation_jobs")
            .update(patch).eq("job_id", job_id).execute()
        )
        log.info("[INTENT-OBS] job_end job=%s status=%s error_type=%s", job_id, status, error_type)
    except Exception as exc:
        log.warning(
            "[INTENT-OBS] job_end FAILED (swallowed) job=%s err=%s: %s",
            job_id, type(exc).__name__, exc,
        )


async def observe_intent_end(
    intent_id: str,
    status: str,
    *,
    result_ref: Optional[dict] = None,
    error: Optional[dict] = None,
    supa=None,
) -> None:
    """UPDATE generation_intents vers un état terminal
    (SUCCEEDED | FAILED | FAILED_TERMINAL). `updated_at` est posé par le
    trigger DB. Best-effort — ne bloque jamais /generate.
    """
    supa = supa or _get_supa()
    patch: dict[str, Any] = {"status": status, "completed_at": "now()"}
    if result_ref is not None:
        patch["result_ref"] = result_ref
    if error is not None:
        patch["error"] = error

    def _run():
        q = supa.table("generation_intents").update(patch).eq("intent_id", intent_id)
        # Transition idempotente / safe-race : SUCCEEDED GAGNE toujours. Un
        # statut d'échec (FAILED / FAILED_TERMINAL) ne doit JAMAIS écraser un
        # SUCCEEDED qui aurait gagné une course de duplicata concurrent (le
        # user a bien eu son image). SUCCEEDED lui-même n'a pas de garde (un
        # succès ultérieur gagne légitimement sur un FAILED antérieur).
        if status != "SUCCEEDED":
            q = q.neq("status", "SUCCEEDED")
        return q.execute()

    try:
        await asyncio.to_thread(_run)
        log.info("[INTENT-OBS] intent_end intent_id=%s status=%s", intent_id, status)
    except Exception as exc:
        log.warning(
            "[INTENT-OBS] intent_end FAILED (swallowed) intent_id=%s err=%s: %s",
            intent_id, type(exc).__name__, exc,
        )
