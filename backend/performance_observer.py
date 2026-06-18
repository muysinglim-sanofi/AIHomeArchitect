"""
Wave 4.4.2 — Pipeline Performance Observer.

Utility functions for main.py to emit structured [PERF] logs and
estimate payload sizes and API costs.

IMPORTANT: Cost estimates are for observability only — never used for billing.
Actual charges depend on exact token counts and current OpenAI pricing.

Usage in main.py:
    from performance_observer import estimate_payload_bytes, estimate_cost_usd

    # Before OpenAI call:
    _payload = estimate_payload_bytes(image_bytes, mask_bytes, design_prompt)
    log.info("[PERF] payload_estimate  total_bytes=%d", _payload)

    # At request end:
    _cost = estimate_cost_usd(profile.quality, output_size, attempts, vision_calls=1)
    log.info("[PERF SUMMARY] ... est_cost_usd=%.3f", _cost)
"""

from __future__ import annotations


# ── Payload estimation ────────────────────────────────────────────────────────

def estimate_payload_bytes(
    image_bytes: bytes,
    mask_bytes: bytes | None,
    prompt: str,
) -> int:
    """
    Estimate the multipart/form-data payload sent to OpenAI images.edit.

    Components:
      image      raw JPEG/PNG bytes
      mask       raw PNG bytes if structural mask active, else 0
      prompt     UTF-8 encoded generation prompt chars
      overhead   ~600 bytes for multipart boundary, field names, model/size/quality params

    Returns conservative upper-bound estimate in bytes.
    """
    image_sz  = len(image_bytes)
    mask_sz   = len(mask_bytes) if mask_bytes else 0
    prompt_sz = len(prompt.encode("utf-8"))
    overhead  = 600
    return image_sz + mask_sz + prompt_sz + overhead


# ── Cost estimation ───────────────────────────────────────────────────────────

# gpt-image-1 per-image cost approximations (USD) as of 2026-05.
# Source: openai.com/pricing (for observability tracking only — not billing).
# High-res output (1536×1024 or 1024×1536) at quality=high is the dominant cost.
_COST_TABLE: dict[tuple[str, str], float] = {
    ("high",   "1536x1024"): 0.190,
    ("high",   "1024x1536"): 0.190,
    ("high",   "1024x1024"): 0.080,
    ("medium", "1536x1024"): 0.070,
    ("medium", "1024x1536"): 0.070,
    ("medium", "1024x1024"): 0.040,
    ("low",    "1536x1024"): 0.020,
    ("low",    "1024x1536"): 0.020,
    ("low",    "1024x1024"): 0.020,
}

# gpt-4o-mini with detail=high vision analysis (~$0.004/call approximate)
_VISION_COST_PER_CALL: float = 0.004


def estimate_cost_usd(
    quality: str,
    size: str,
    openai_attempts: int = 1,
    vision_calls: int = 1,
) -> float:
    """
    Estimate total USD cost for one generation session.

    Args:
        quality:          profile.quality ("high", "medium", "low")
        size:             output_size ("1536x1024", "1024x1536", "1024x1024")
        openai_attempts:  number of gpt-image-1 images.edit calls made
        vision_calls:     number of gpt-4o-mini vision analysis calls (usually 1)

    Returns estimated USD cost. Actual billing may differ.
    """
    per_image = _COST_TABLE.get(
        (quality, size),
        _COST_TABLE.get(("high", "1024x1024"), 0.080),
    )
    return per_image * openai_attempts + _VISION_COST_PER_CALL * vision_calls


# ── Cost risk classification ──────────────────────────────────────────────────

def cost_risk_label(est_cost_usd: float) -> str:
    """Classify estimated cost into a risk tier for log annotation."""
    if est_cost_usd < 0.05:
        return "LOW"
    if est_cost_usd < 0.25:
        return "MEDIUM"
    if est_cost_usd < 0.50:
        return "HIGH"
    return "CRITICAL"


# ── Stage timing helper ───────────────────────────────────────────────────────

class PipelineTimer:
    """
    Lightweight stage-by-stage timing recorder for a single /generate request.

    Usage:
        timer = PipelineTimer(request_id)
        timer.record("image_fetch", duration_s, size_bytes=len(image_bytes))
        timer.record("openai_api", attempt_s, attempt=1, status="success")
        timer.log_summary(log)
    """

    __slots__ = ("request_id", "_stages")

    def __init__(self, request_id: str) -> None:
        self.request_id = request_id
        self._stages: list[dict] = []

    def record(self, stage: str, duration_s: float, **meta) -> None:
        """Record a completed stage with its duration and optional metadata."""
        self._stages.append({"stage": stage, "duration_ms": duration_s * 1000, **meta})

    def total_openai_ms(self) -> float:
        """Sum of all openai_api stage durations in milliseconds."""
        return sum(
            s["duration_ms"] for s in self._stages if s["stage"] == "openai_api"
        )

    def openai_attempt_count(self) -> int:
        return sum(1 for s in self._stages if s["stage"] == "openai_api")

    def stage_ms(self, name: str) -> float:
        """Return duration_ms for a named stage (0.0 if not recorded)."""
        for s in self._stages:
            if s["stage"] == name:
                return s["duration_ms"]
        return 0.0

    def log_summary(self, logger, total_elapsed_s: float, payload_bytes: int,
                    prompt_chars: int, est_cost_usd: float) -> None:
        """Emit a single [PERF SUMMARY] line with all stage timings.

        2026-06-18 — added the pre-image stages (history_norm, normalize, the 4
        classifiers, accumulate) so the multilingual + routing overhead is
        measured, not assumed. backend_ms = total minus the OpenAI image call =
        everything our code spends; the openai_ms / backend_ms split answers
        "our code or OpenAI?". Pure instrumentation — no behaviour change.
        """
        _total_ms = total_elapsed_s * 1000
        _openai_ms = self.total_openai_ms()
        logger.info(
            "[PERF SUMMARY] request_id=%s  total_ms=%.0f  backend_ms=%.0f"
            "  fetch_ms=%.0f  history_ms=%.0f  normalize_ms=%.0f"
            "  cls_room_ms=%.0f  cls_intent_ms=%.0f  cls_transform_ms=%.0f  cls_editmode_ms=%.0f"
            "  accumulate_ms=%.0f  struct_id_ms=%.0f  vision_ms=%.0f  prompt_ms=%.0f  mask_ms=%.0f"
            "  openai_ms=%.0f (x%d attempts)  upload_ms=%.0f"
            "  payload_bytes=%d  prompt_chars=%d"
            "  est_cost_usd=%.3f  cost_risk=%s",
            self.request_id,
            _total_ms,
            _total_ms - _openai_ms,
            self.stage_ms("image_fetch"),
            self.stage_ms("history_norm"),
            self.stage_ms("normalize"),
            self.stage_ms("classify_room"),
            self.stage_ms("classify_intent"),
            self.stage_ms("classify_transformation"),
            self.stage_ms("classify_edit_mode"),
            self.stage_ms("accumulate"),
            self.stage_ms("struct_id"),
            self.stage_ms("vision_analysis"),
            self.stage_ms("prompt_composition"),
            self.stage_ms("mask_generation"),
            _openai_ms,
            self.openai_attempt_count(),
            self.stage_ms("supabase_upload"),
            payload_bytes,
            prompt_chars,
            est_cost_usd,
            cost_risk_label(est_cost_usd),
        )
