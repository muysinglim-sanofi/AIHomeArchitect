"""
Generation Intent v1 — PR4 : réconciliation (lifecycle only).

Spec : docs/GENERATION_INTENT_V1_SPEC.md (§9 échecs/timeout, §11.1 workers).

Ferme le dernier trou du lifecycle Intent AVANT de brancher le Billing :
  • REPAIR : une image existe en DB mais l'Intent est resté RUNNING (client tué
    → requête abandonnée avant observe_intent_end) → on le passe SUCCEEDED.
  • TIMEOUT-FAIL : Intent RUNNING depuis > JOB_TIMEOUT sans image → FAILED.
  • DRIFT : log d'un résumé + warnings sur les anomalies.

Contraintes (PR4) :
  • backend-only, AUCUN changement dans /generate, AUCUN pipeline image.
  • AUCUN hook Billing / AUCUNE écriture ledger — uniquement le statut Intent.
  • Best-effort : n'interrompt jamais l'app ; tout est loggué.

Le repair corrèle par TIMESTAMP (un image_result de la session créé APRÈS le
started_at de l'Intent) plutôt que par iteration — robuste au re-upload (où
l'iteration repart à 1). Les transitions sont gardées par `.eq(status,RUNNING)`
→ on ne clobber jamais un Intent déjà terminal (course avec un observe_intent_end
tardif).
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

log = logging.getLogger("generation_intent.reconciliation")

# ── Constantes (GJ-OD-3) ─────────────────────────────────────────────────────
JOB_TIMEOUT_MINUTES = 12          # RUNNING au-delà → FAILED (si pas d'image)
RECONCILE_INTERVAL_SECONDS = 300  # sweep toutes les 5 min
_MAX_SCAN = 500                   # borne défensive par passe


def _get_supa():
    """Lazy import to avoid a circular dependency at module load (mirrors quota.py)."""
    from main import supa  # noqa: PLC0415
    return supa


def _parse_ts(value) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except Exception:
        return None


async def _finalize(supa, intent_id: str, status: str, *, error: Optional[dict] = None) -> bool:
    """UPDATE generation_intents vers un terminal, UNIQUEMENT si encore RUNNING
    (garde anti-clobber). Renvoie True si une ligne a effectivement transité."""
    patch = {"status": status, "completed_at": "now()"}
    if error is not None:
        patch["error"] = error
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("generation_intents")
            .update(patch)
            .eq("intent_id", intent_id)
            .eq("status", "RUNNING")
            .execute()
        )
        return bool(getattr(res, "data", None))
    except Exception as exc:
        log.warning(
            "[RECONCILE] finalize failed intent=%s status=%s err=%s: %s",
            intent_id, status, type(exc).__name__, exc,
        )
        return False


async def reconcile_once(*, supa=None) -> dict:
    """Une passe de réconciliation. Best-effort ; renvoie les compteurs."""
    supa = supa or _get_supa()
    counts = {
        "scanned": 0, "repaired": 0, "timeout_failed": 0,
        "still_running": 0, "warnings": 0,
    }
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(minutes=JOB_TIMEOUT_MINUTES)

    try:
        res = await asyncio.to_thread(
            lambda: supa.table("generation_intents")
            .select("intent_id, session_id, iteration, started_at, created_at")
            .eq("status", "RUNNING")
            .limit(_MAX_SCAN)
            .execute()
        )
        rows = getattr(res, "data", None) or []
    except Exception as exc:
        log.warning("[RECONCILE] fetch RUNNING failed (skipping pass) err=%s: %s",
                    type(exc).__name__, exc)
        return counts

    counts["scanned"] = len(rows)
    for r in rows:
        intent_id = r.get("intent_id")
        sid = r.get("session_id")
        started_raw = r.get("started_at") or r.get("created_at")

        # Landed? An image_result for this session created AT/AFTER this Intent
        # started (timestamp correlation → robust to re-upload iteration resets).
        landed = False
        if sid and started_raw:
            try:
                cres = await asyncio.to_thread(
                    lambda s=sid, ts=started_raw: supa.table("messages")
                    .select("id", count="exact")
                    .eq("session_id", s)
                    .eq("message_type", "image_result")
                    .gte("created_at", ts)
                    .execute()
                )
                landed = (getattr(cres, "count", None) or 0) >= 1
            except Exception as exc:
                log.warning("[RECONCILE] msg count failed intent=%s err=%s: %s",
                            intent_id, type(exc).__name__, exc)
                counts["warnings"] += 1
                continue
        elif not sid:
            # Malformed: RUNNING intent with no session → can't correlate; only
            # the timeout path can retire it. Flag it.
            counts["warnings"] += 1

        if landed:
            if await _finalize(supa, intent_id, "SUCCEEDED"):
                counts["repaired"] += 1
                log.info("[RECONCILE] repaired intent=%s → SUCCEEDED (image present)", intent_id)
            continue

        started_dt = _parse_ts(started_raw)
        if started_dt is not None and started_dt < cutoff:
            if await _finalize(
                supa, intent_id, "FAILED",
                error={"type": "reconciled_timeout",
                       "message": f"RUNNING > {JOB_TIMEOUT_MINUTES}min, no image"},
            ):
                counts["timeout_failed"] += 1
                log.info("[RECONCILE] timeout-failed intent=%s (age > %dmin, no image)",
                         intent_id, JOB_TIMEOUT_MINUTES)
        else:
            counts["still_running"] += 1

    log.info(
        "[RECONCILE] pass done scanned=%d repaired=%d timeout_failed=%d "
        "still_running=%d warnings=%d",
        counts["scanned"], counts["repaired"], counts["timeout_failed"],
        counts["still_running"], counts["warnings"],
    )
    return counts
