"""Generation Orchestrator (Phase 1) — shell mince, réutilisable, ISOLÉ.

Séquence commune à toute génération d'image :
  claim(operation_id) → idempotency → HOLD → boucle retry AUTOUR de l'appel image
  SEUL → persist idempotent PROTÉGÉE → terminal STRICT (SUCCEEDED persisté) →
  COMMIT/RELEASE → result_ref compact.

Le CŒUR CRÉATIF (composer/DNA pour V1 ; parser/advisor/normalizer/planner pour
refine) reste DEHORS, fourni par des callbacks :
  • execute_fn(ctx)               → bytes      — l'appel image, la SEULE chose retentée
  • persist_result_fn(ctx, bytes) → result_ref — upload+version+message, IDEMPOTENT (get-or-create)
  • build_response_fn(result_ref) → dict       — l'enveloppe de réponse du moteur

GÉNÉRIQUE : ne connaît AUCUN moteur en particulier — les codes d'erreur sont
dérivés de `kind` (REFINE_FAILED, GENERATE_FAILED, …). N'importe NI main, NI
/generate, NI aucun moteur créatif → aucun cycle. Réutilise l'infra déjà extraite
(intent_observer, billing, retry_classifier). Phase 1 : destiné à /refine ; V1
migrera en Phase 2 (bench-gated). NON branché ici.
"""
from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from typing import Awaitable, Callable, Optional

import billing
import intent_observer
from retry_classifier import classify_for_retry

log = logging.getLogger("aih")

_DEFAULT_BACKOFF_S = 2.0
_DEFAULT_PERSIST_ATTEMPTS = 3


def _code(kind: str, suffix: str) -> str:
    """Code d'erreur GÉNÉRIQUE dérivé du moteur (pas de 'refine' codé en dur)."""
    return f"{(kind or 'generation').strip().upper()}_{suffix}"


class OrchestratorError(Exception):
    """Échec STRUCTURÉ (l'endpoint le mappe vers la GenerationError HTTP 502/503 —
    jamais un traceback 500 brut vers le frontend)."""

    def __init__(self, *, error_code: str, user_message: str, retryable: bool,
                 status_code: int, request_id: str = "", session_id: str = "",
                 intent_id: str = ""):
        super().__init__(error_code)
        self.error_code = error_code
        self.user_message = user_message
        self.retryable = retryable
        self.status_code = status_code
        self.request_id = request_id
        self.session_id = session_id
        self.intent_id = intent_id


@dataclass
class GenContext:
    """Contexte transporté vers les callbacks moteur (opaque pour l'orchestrateur)."""
    kind: str
    intent_id: str
    operation_id: str
    user_id: str
    session_id: str
    iteration: int
    source_image_url: str
    image_bytes: bytes = b""
    mime: str = ""
    attempt: int = 0
    meta: dict = field(default_factory=dict)


# ── helpers best-effort (observabilité — ne bloquent JAMAIS) ─────────────────
async def _job_start(intent_id: str, attempt: int) -> Optional[str]:
    try:
        return await intent_observer.observe_job_start(intent_id, attempt)
    except Exception:  # noqa: BLE001
        return None


async def _job_end(job_id: Optional[str], status: str, error_type: Optional[str] = None) -> None:
    try:
        await intent_observer.observe_job_end(job_id, status, error_type=error_type)
    except Exception:  # noqa: BLE001
        pass


async def _fail_terminal(intent_id: str, status: str, is_free: bool, exc: Exception) -> None:
    """Marque l'intent terminal FAILED/FAILED_TERMINAL (best-effort ; s'il échoue,
    le reconcile le retirera par timeout → aucun RUNNING éternel). observe_intent_end
    fait aussi le RELEASE billing en interne (idempotent, keyé intent_id)."""
    try:
        await intent_observer.observe_intent_end(
            intent_id, status, error={"type": type(exc).__name__, "message": str(exc)[:200]},
            is_free=is_free)
    except Exception as e:  # noqa: BLE001
        log.warning("[ORCH] terminal %s swallowed intent=%s err=%s", status, intent_id, e)


async def run_generation(
    *,
    kind: str,
    user_id: str,
    session_id: str,
    operation_id: str,
    intent_id: str,
    intent_meta: dict,
    iteration: int,
    is_free: bool,
    source_image_url: str,
    max_attempts: int,
    fetch_source_fn: Callable[[str], Awaitable[tuple[bytes, str]]],
    execute_fn: Callable[["GenContext"], Awaitable[bytes]],
    persist_result_fn: Callable[["GenContext", bytes], Awaitable[dict]],
    build_response_fn: Callable[[dict], dict],
    request_id: str = "",
    backoff_s: float = _DEFAULT_BACKOFF_S,
    persist_max_attempts: int = _DEFAULT_PERSIST_ATTEMPTS,
) -> dict:
    """Exécute une génération sous le lifecycle persistant partagé. Lève
    OrchestratorError (structuré) sur échec terminal. Idempotent par operation_id."""
    ctx = GenContext(
        kind=kind, intent_id=intent_id, operation_id=operation_id, user_id=user_id,
        session_id=session_id, iteration=iteration, source_image_url=source_image_url,
        meta=dict(intent_meta or {}),
    )
    attempts = max(int(max_attempts or 1), 1)

    # ── 1) CLAIM atomique (dédupe sur operation_id → intent_id déterministe) ───
    claim = await intent_observer.claim_generation_intent(
        intent_id=intent_id, user_id=user_id, session_id=session_id,
        iteration=iteration, intent=intent_meta, client_request_id=operation_id)

    if not claim.won:
        st = (claim.status or "").upper()
        if st == "SUCCEEDED" and claim.result_ref:
            log.info("[ORCH:%s] replay intent=%s (SUCCEEDED, no re-exec)", kind, intent_id)
            return build_response_fn(claim.result_ref)          # ← replay, 0 exec, 0 bill
        if st in ("FAILED", "FAILED_TERMINAL"):
            # Opération TERMINALE : on ne rouvre PAS (contrainte 3). Un Retry
            # utilisateur volontaire crée un NOUVEL operation_id → nouvel intent.
            raise OrchestratorError(
                error_code=_code(kind, "FAILED_TERMINAL" if st == "FAILED_TERMINAL" else "FAILED"),
                user_message="This edit didn't complete. Tap Retry to try again.",
                retryable=(st == "FAILED"), status_code=502,
                request_id=request_id, session_id=session_id, intent_id=intent_id)
        # RUNNING (ou SUCCEEDED sans payload = réconcilié) → ré-attache sans ré-exécuter
        log.info("[ORCH:%s] lost-claim intent=%s status=%s → running", kind, intent_id, st or "unknown")
        return {"status": "running", "intent_id": intent_id, "iteration": iteration}

    # ── 2) HOLD (billing). is_free=False (entitled / refine-OFF) ⇒ 0 écriture ledger ──
    try:
        await billing.apply_billing_for_intent_transition(
            intent_id=intent_id, new_status="RUNNING", is_free=is_free)
    except Exception as exc:  # noqa: BLE001
        log.warning("[ORCH:%s] HOLD swallowed intent=%s err=%s", kind, intent_id, exc)

    # ── 3) fetch de la source (input de execute_fn) ───────────────────────────
    try:
        ctx.image_bytes, ctx.mime = await fetch_source_fn(source_image_url)
    except Exception as exc:  # noqa: BLE001
        await _fail_terminal(intent_id, "FAILED_TERMINAL", is_free, exc)
        raise OrchestratorError(
            error_code=_code(kind, "SOURCE_FETCH_FAILED"),
            user_message="Couldn't load the image to edit.",
            retryable=False, status_code=502, request_id=request_id,
            session_id=session_id, intent_id=intent_id) from exc

    # ── 4) BOUCLE RETRY autour de execute_fn SEUL (plan/prompt déjà figés dehors) ──
    generated: Optional[bytes] = None
    for attempt in range(1, attempts + 1):
        ctx.attempt = attempt
        job = await _job_start(intent_id, attempt)
        try:
            generated = await execute_fn(ctx)
            if not generated:
                raise ValueError("empty image from execute_fn")
            await _job_end(job, "SUCCEEDED")
            break
        except Exception as exc:  # noqa: BLE001
            decision = classify_for_retry(exc)
            await _job_end(job, "FAILED",
                           error_type=("transient" if decision.should_retry else "non_transient"))
            if not decision.should_retry:
                await _fail_terminal(intent_id, "FAILED_TERMINAL", is_free, exc)   # 4xx → terminal
                raise OrchestratorError(
                    error_code=_code(kind, "REJECTED"),
                    user_message="This edit couldn't be applied. Try rephrasing.",
                    retryable=False, status_code=502, request_id=request_id,
                    session_id=session_id, intent_id=intent_id) from exc
            if attempt < attempts:
                log.warning("[ORCH:%s] transient attempt=%d/%d intent=%s reason=%s → retry",
                            kind, attempt, attempts, intent_id, decision.reason)
                await asyncio.sleep(backoff_s)
                continue
            await _fail_terminal(intent_id, "FAILED", is_free, exc)                 # épuisé → FAILED
            raise OrchestratorError(
                error_code=_code(kind, "UNAVAILABLE"),
                user_message="The service is busy. Please try again.",
                retryable=True, status_code=503, request_id=request_id,
                session_id=session_id, intent_id=intent_id) from exc

    # ── 5) PERSIST idempotent, PROTÉGÉE (retry STORAGE transitoire, JAMAIS OpenAI) ──
    p_attempts = max(int(persist_max_attempts or 1), 1)
    result_ref: Optional[dict] = None
    for p in range(1, p_attempts + 1):
        try:
            result_ref = await persist_result_fn(ctx, generated)   # get-or-create idempotent
            break
        except Exception as exc:  # noqa: BLE001
            decision = classify_for_retry(exc)
            if decision.should_retry and p < p_attempts:
                log.warning("[ORCH:%s] persist transient attempt=%d/%d intent=%s → retry (MÊMES bytes, 0 OpenAI)",
                            kind, p, p_attempts, intent_id)
                await asyncio.sleep(backoff_s)
                continue
            await _fail_terminal(intent_id, "FAILED", is_free, exc)   # aucun RUNNING abandonné
            raise OrchestratorError(
                error_code=_code(kind, "PERSIST_FAILED"),
                user_message="We couldn't save your result. Please try again.",
                retryable=True, status_code=503, request_id=request_id,
                session_id=session_id, intent_id=intent_id) from exc

    # ── 6) TERMINAL STRICT : on ne répond 'completed' QUE si SUCCEEDED est persisté ──
    #    (les jobs sont best-effort, le lifecycle terminal ne l'est PAS). Si l'UPDATE
    #    échoue, l'image + le result_ref sont déjà durables (§5) → le reconcile finalise ;
    #    on renvoie une erreur RÉCUPÉRABLE au lieu d'un 'completed' sur un intent RUNNING.
    ok = await intent_observer.observe_intent_end(
        intent_id, "SUCCEEDED", result_ref=result_ref, is_free=is_free)
    if not ok:
        log.error("[ORCH:%s] SUCCEEDED NOT persisted intent=%s → erreur récupérable (reconcile finalisera)",
                  kind, intent_id)
        raise OrchestratorError(
            error_code=_code(kind, "FINALIZE_PENDING"),
            user_message="Your edit is finishing up — it'll appear shortly.",
            retryable=True, status_code=503, request_id=request_id,
            session_id=session_id, intent_id=intent_id)
    return build_response_fn(result_ref)
