"""
PR0 — Situational Context (Ayden Companion).

Two clearly separated layers — facts vs interpretation:

  (1) SituationalFacts   — objective facts only: "what do the frontend and the
      backend know right now". NO interpretation. Stable across routing changes.

  (2) ConversationState  — the resolved interpretation: "what does the router
      make of this turn" (mode, is_about_image). Depends on the routing, which
      WILL evolve (Designer / Support / Coach / Image Editor / OOS ...). Keeping
      it out of the facts type means tomorrow's richer router never touches the
      facts layer.

The wire `context` envelope returned by /chat is the *merge* of the two, built
by build_context(). Each downstream concern (memory, analytics, designer_state…)
should get its OWN attach_* function rather than bloating a single wrapper.

Deterministic — NO LLM, NO image fetch, NO behaviour change. `current_image_url`
is the vision-input hook for Ayden Voice (PR2): carried through, never opened.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

# Conversational mode — the TurnIntent value resolved by conversation_router.
# Kept as a string set here so this module stays decoupled from the router.
SITCTX_MODES = (
    "meta", "action_refine", "product_help", "design_advice",
    "result_explanation", "preference", "ambiguous", "out_of_scope", "unknown",
)

# Modes whose turn is "about the rendered image/result" (when a vision exists).
_IMAGE_MODES = ("design_advice", "result_explanation")


# ── Layer 1 : facts (no interpretation) ───────────────────────────────────────
@dataclass
class SituationalFacts:
    room_type: str = ""
    atmosphere_id: str = ""
    iteration: int = 1
    has_vision: bool = False
    generation_in_progress: bool = False
    displayed_version_id: Optional[str] = None
    current_image_url: Optional[str] = None   # vision-input hook (PR2) — unused here
    original_image_url: Optional[str] = None
    session_language: str = "en"

    def to_dict(self) -> dict:
        return {
            "room_type": self.room_type,
            "atmosphere_id": self.atmosphere_id,
            "iteration": self.iteration,
            "has_vision": self.has_vision,
            "generation_in_progress": self.generation_in_progress,
            "displayed_version_id": self.displayed_version_id,
            "current_image_url": self.current_image_url,
            "original_image_url": self.original_image_url,
            "session_language": self.session_language,
        }


def _coerce_bool(raw: str, default: bool = False) -> bool:
    """Parse an optional form string ('1'/'true'/'0'/'') into a bool."""
    if raw is None:
        return default
    v = raw.strip().lower()
    if v in ("1", "true", "yes"):
        return True
    if v in ("0", "false", "no"):
        return False
    return default


def build_situational_facts(
    *,
    room_type: str,
    atmosphere_id: str,
    iteration: int,
    session_language: str,
    has_vision_raw: str = "",
    generation_in_progress_raw: str = "",
    current_image_url: str = "",
    displayed_version_id: str = "",
    original_image_url: str = "",
) -> SituationalFacts:
    """
    Assemble the facts layer from /chat inputs.

    All frontend-sourced fields are optional: an older client that omits them
    yields safe defaults (has_vision <- iteration > 1, generation off, no urls).
    No interpretation happens here.
    """
    # has_vision: trust the explicit frontend signal when present; otherwise
    # fall back to the iteration heuristic (V2+ implies a prior vision exists).
    if has_vision_raw and has_vision_raw.strip():
        has_vision = _coerce_bool(has_vision_raw)
    else:
        has_vision = iteration > 1

    return SituationalFacts(
        room_type=room_type or "",
        atmosphere_id=atmosphere_id or "",
        iteration=iteration,
        has_vision=has_vision,
        generation_in_progress=_coerce_bool(generation_in_progress_raw),
        displayed_version_id=(displayed_version_id or "").strip() or None,
        current_image_url=(current_image_url or "").strip() or None,
        original_image_url=(original_image_url or "").strip() or None,
        session_language=session_language or "en",
    )


# ── Layer 2 : resolved interpretation ─────────────────────────────────────────
@dataclass
class ConversationState:
    mode: str = "unknown"
    is_about_image: bool = False

    def to_dict(self) -> dict:
        return {"mode": self.mode, "is_about_image": self.is_about_image}


def resolve_conversation_state(facts: SituationalFacts, mode) -> ConversationState:
    """
    Interpret the turn: tag the mode and derive is_about_image.

    `mode` accepts a TurnIntent (str Enum) or a raw string ; both coerce to the
    TurnIntent value. A turn is "about the image" only when it concerns the
    design/result AND a vision actually exists to talk about. Pure function of
    the facts plus the routing-resolved TurnIntent.
    """
    mode_str = getattr(mode, "value", mode)
    mode_str = mode_str if mode_str in SITCTX_MODES else "unknown"
    return ConversationState(
        mode=mode_str,
        is_about_image=(mode_str in _IMAGE_MODES and facts.has_vision),
    )


# ── Wire envelope : merge of the two layers ───────────────────────────────────
def build_context(facts: SituationalFacts, mode: str) -> dict:
    """Resolve the interpretation layer for this turn and merge it with the
    facts into the wire `context` envelope. Single responsibility: produce the
    context data (no logging, no response mutation)."""
    state = resolve_conversation_state(facts, mode)
    return {**facts.to_dict(), **state.to_dict()}


def context_log_line(ctx: dict) -> str:
    """Single responsibility: format the [SITCTX] observability line."""
    return (
        "mode=%s is_about_image=%s has_vision=%s gen_in_progress=%s "
        "room=%s atmo=%s version=%s displayed=%s img=%s"
        % (
            ctx.get("mode"),
            ctx.get("is_about_image"),
            ctx.get("has_vision"),
            ctx.get("generation_in_progress"),
            ctx.get("room_type") or "(none)",
            ctx.get("atmosphere_id") or "(none)",
            ctx.get("iteration"),
            ctx.get("displayed_version_id") or "(none)",
            "present" if ctx.get("current_image_url") else "absent",
        )
    )


def attach_context(payload: dict, ctx: dict) -> dict:
    """Single responsibility: attach the context envelope to a /chat response.
    Future envelopes (memory, designer_state…) get their own attach_* siblings
    rather than growing this one."""
    payload["context"] = ctx
    return payload
