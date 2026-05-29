"""
Wave 4.11a — Constraint Acknowledgment.

Builds the "I'll preserve : … while refining the … " phrasing that
reassures the user the architect understands what stays untouched.

Design rules (Wave 4.11a Q2 — option (a) confirmed by user) :

    Emit ONLY on :
      (1) iteration == 2 — the first V2+ message, where reassurance
          matters most (user's first refinement, wants confidence the
          space won't be rebuilt from scratch)
      (2) transformation_type == ATMOSPHERE_SWITCH — scope changed,
          re-affirm what carries across
      (3) NEW KEEP entries appear in refinement_state vs prior turn —
          the user just named a new constraint, surface that we heard it

    NEVER emit on :
      - V1 (iteration <= 1) — no prior context to acknowledge against
      - V3+ with no scope change — repetition is noise, not reassurance
      - When structural_identity has zero facts — nothing to preserve
        (the architect's silence here is correct)

Goal : confidence, not noise. The user said it explicitly :
    "Repeating preservation acknowledgements on every single generation"
    is bad — "the goal is confidence, not noise."

Brevity contract :
    - 3-4 bullet items max (top facts only)
    - 1 closing line stating what WILL be reworked
    - Total target ≤ 35 words

English-only Phase 1 (per Wave 4.11a Q1 — architectural critique layer
defers Khmer translation to a later wave).

Public API:
    should_emit_acknowledgment(iteration, transformation_type,
                                refinement_state, history_messages) -> bool
    build_acknowledgment(structural_identity, refinement_state,
                          atmosphere_id, transformation_type) -> str
"""

from __future__ import annotations

import re
from typing import Any, Optional


# Imperative verbs that signal a NEW directive coming AFTER a "and" / "but" —
# used to split a compound user keep statement like
#     "Keep the windows and make it warmer"
# so only the actual preservation part ("the windows") survives.
_KEEP_TRUNCATORS = re.compile(
    r"\s+(?:and|but|while|but\s+also|also)\s+"
    r"(?:make|add|remove|change|swap|replace|move|put|edit|render|"
    r"generate|try|show|i\s+want|let'?s|please)\b.*$",
    re.IGNORECASE,
)


# ── Trigger gate ─────────────────────────────────────────────────────────────

def should_emit_acknowledgment(
    iteration: int,
    transformation_type: Optional[str],
    refinement_state: Optional[Any] = None,
    history_messages: Optional[list[dict]] = None,
) -> bool:
    """
    Return True only when one of the 3 trigger conditions fires :
      (1) iteration == 2                    — first V2+ refinement
      (2) transformation == atmosphere_switch — scope change
      (3) refinement_state.keep gained a new entry vs prior turn

    Backend is stateless, so condition (3) compares the current keep
    list against keep-entries the model could derive from the history's
    earlier user messages. The cheap heuristic is : count keep entries.
    If count > 0 AND iteration > 2, suppress UNLESS the latest user
    message just introduced a new keep verb. main.py's
    parse_history() drives this — we trust its `keep` list as the
    source of truth.

    Designed to be defensive : when in doubt about whether keep-scope
    changed, default to NOT emitting (silence > noise).
    """
    if iteration <= 1:
        return False
    if iteration == 2:
        return True
    if transformation_type == "atmosphere_switch":
        return True

    if refinement_state is None:
        return False
    # Condition (3) — new KEEP entry on this turn.
    # We look at refinement_state.latest : if the latest user message
    # is itself a keep statement and there's at least one keep entry,
    # treat as a fresh scope landmark.
    latest = getattr(refinement_state, "latest", "") or ""
    keep_list = getattr(refinement_state, "keep", None) or []
    if not keep_list:
        return False
    latest_lower = latest.lower()
    keep_verbs = (
        "keep ", "preserve ", "leave the ", "don't change ",
        "do not change ", "must stay", "must remain",
    )
    if any(v in latest_lower for v in keep_verbs):
        return True
    return False


# ── Facts extractor ──────────────────────────────────────────────────────────

# Display order for structural identity facts. Matches the priority
# already used by structural_identity.render_clause() so the
# acknowledgment lists the same anchors the prompt engine actually
# protects in the generation prompt.
_RENDER_ORDER = (
    "dominant_opening",
    "glass_partition",
    "room_depth_type",
    "opening_layout",
    "kitchen_visibility",
    "anchor_relationships",
)

# Friendlier labels for the acknowledgment bullets. Each maps a
# structural identity field to the noun phrase a user will recognise.
_FACT_LABELS = {
    "dominant_opening": "the main opening",
    "glass_partition": "the glazed partition",
    "room_depth_type": "the room's depth",
    "opening_layout": "the opening layout",
    "kitchen_visibility": "the kitchen sightline",
    "anchor_relationships": "the spatial anchors",
}

# Max bullets emitted in a single acknowledgment.
_MAX_BULLETS = 3


def _extract_facts(structural_identity: Any) -> list[str]:
    """
    Pull the top ≤ 3 user-readable preservation facts from the
    structural identity. Returns an empty list when nothing usable is
    present — caller then suppresses the acknowledgment.
    """
    if structural_identity is None:
        return []
    if not getattr(structural_identity, "is_present", False):
        return []

    facts: list[str] = []
    for attr in _RENDER_ORDER:
        value = getattr(structural_identity, attr, None)
        if not value:
            continue
        label = _FACT_LABELS.get(attr, attr.replace("_", " "))
        facts.append(label)
        if len(facts) >= _MAX_BULLETS:
            break
    return facts


def _user_keep_facts(refinement_state: Any, max_extra: int = 2) -> list[str]:
    """
    Pull explicit user-named preservation items from the refinement
    state's keep list. Lightly cleans them (strips leading verbs,
    trailing punctuation) so they sit nicely as bullets next to the
    structural facts.
    """
    if refinement_state is None:
        return []
    keep_list = getattr(refinement_state, "keep", None) or []
    cleaned: list[str] = []
    for raw in keep_list:
        if not raw:
            continue
        item = raw.strip().rstrip(".,;:!?")
        # Strip common leading verbs the user might write
        for verb in ("keep the ", "keep ", "preserve the ", "preserve "):
            if item.lower().startswith(verb):
                item = item[len(verb):]
                break
        # Wave 4.11a — truncate at compound directives. A user message like
        # "Keep the windows and make it warmer" puts the whole phrase into
        # the keep bucket ; we slice off the "and make it warmer" tail so
        # only the actual preservation ("the windows") survives.
        item = _KEEP_TRUNCATORS.sub("", item).strip().rstrip(".,;:!?")
        if item:
            cleaned.append(item)
        if len(cleaned) >= max_extra:
            break
    return cleaned


# ── Closing line by transformation ───────────────────────────────────────────
# What gets reworked depends on the transformation type. The closing line
# echoes the user's intent without committing to specifics — the actual
# render shows the result.

# Wave 4.11a — closing lines rewritten in a more conversational,
# architect-authored voice (per user review of Day 3). The earlier
# wording — "rotates", "anchors", "captures", semicolons — read as
# system-generated. The replacements use natural connectors ("but",
# "while"), drop jargon, and refer to "the room itself" so the
# sentence feels spoken rather than rendered. Same 6 transformation
# branches, same logic ; only the phrasing changed.

_CLOSING_BY_TRANSFORMATION = {
    "style_refinement": (
        "Materials, lighting and decor are where the refinement plays — "
        "everything structural stays."
    ),
    "atmosphere_switch": (
        "The atmosphere changes, but the room itself stays exactly as "
        "it is."
    ),
    "object_edit": (
        "Only the element you mentioned changes — the rest of the room "
        "stays as is."
    ),
    "structural_change": (
        "Only the change you described moves — every other part of the "
        "architecture holds."
    ),
    "layout_reinterpretation": (
        "The layout reshapes, but the architectural bones of the room "
        "stay as they are."
    ),
    "functional_reassignment": (
        "The room's function shifts — the architecture itself stays "
        "in place."
    ),
}

_FALLBACK_CLOSING = "Everything else stays as it is."


# ── Public API ───────────────────────────────────────────────────────────────

def build_acknowledgment(
    structural_identity: Any,
    refinement_state: Any = None,
    atmosphere_id: Optional[str] = None,
    transformation_type: Optional[str] = None,
) -> str:
    """
    Compose the "I'll preserve : … while refining the … " block.

    Returns the formatted multi-line string, or "" when there's nothing
    meaningful to acknowledge (no structural facts AND no explicit user
    keeps).

    Format :
        I'll preserve what's already working :
        • <fact 1>
        • <fact 2>
        • <fact 3>

        <closing line per transformation>

    The closing line is intentionally short — the user just needs to
    hear "and the rest changes" without prescriptive specifics. The
    architect's main response (composed elsewhere) speaks to the
    refinement itself.
    """
    facts = _extract_facts(structural_identity)
    user_keeps = _user_keep_facts(refinement_state, max_extra=2)

    # Merge — user-stated keeps come first (they're the most fresh signal),
    # then structural facts that haven't already been said.
    combined: list[str] = []
    seen_lower: set[str] = set()
    for item in user_keeps + facts:
        low = item.lower().strip()
        if low and low not in seen_lower:
            combined.append(item)
            seen_lower.add(low)
        if len(combined) >= _MAX_BULLETS:
            break

    if not combined:
        return ""

    bullets = "\n".join(f"• {item}" for item in combined)
    closing = _CLOSING_BY_TRANSFORMATION.get(
        transformation_type or "", _FALLBACK_CLOSING
    )

    return (
        "I'll preserve what's already working :\n"
        f"{bullets}\n\n"
        f"{closing}"
    )


def acknowledgment_max_bullets() -> int:
    """Expose for tests + future tuning waves."""
    return _MAX_BULLETS
