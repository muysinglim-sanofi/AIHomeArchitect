"""
Wave 4.11b — Architectural Memory.

Surfaces a SINGLE short sentence that references an architectural anchor
the user previously asked the architect to preserve. Goal : make the
architect feel like it remembers the design narrative, not just the
latest instruction.

    V2 user : "Keep the windows."
    V5 user : "Make it warmer."
    V5 architect (with memory) :
        "I'll continue preserving the glazing strategy we established
         earlier. <base response>"

Design rules (Wave 4.11b) :

    1. Zero LLM, zero embeddings, zero persistence — just regex over the
       existing refinement_state.keep list that main.py already passes
       around.

    2. V3+ only. V1 has no prior session, V2 is the first refinement
       (constraint_ack covers reassurance there) — memory only adds
       value once a design narrative exists.

    3. Max ONE memory reference per response. Picks the first matching
       anchor in keep_list order ; if the user's latest message
       mentions the same anchor, the reference is suppressed (the
       latest instruction already covers it).

    4. Suppression by the orchestrator : architect_response drops the
       memory reference when the main enrichment is constraint_ack
       (redundant) or alternatives (too heavy to stack a memory
       sentence above 3 bullets).

    5. EN-only Phase 1 (Wave 4.11a Q1 architectural critique layer).

Public API :
    extract_anchor(refinement_state, user_message) -> Optional[str]
    get_memory_reference(refinement_state, iteration, user_message) -> str
"""

from __future__ import annotations

import re
from typing import Any, Optional


# ── Anchor keyword map ───────────────────────────────────────────────────────
# Each anchor_id resolves a list of vocabulary the user might have used to
# refer to that architectural element. Order matters : list the
# atmosphere-defining anchors first (windows / open kitchen / glazed
# partition) so they win when multiple anchors are kept.

_ANCHOR_KEYWORDS: dict[str, tuple[str, ...]] = {
    "windows": ("window", "windows", "glazing", "glass facade", "glass wall"),
    "open_kitchen": (
        "open kitchen", "kitchen opening", "kitchen island opening",
        "kitchen sightline",
    ),
    "glazed_partition": (
        "glazed partition", "glass partition", "internal glazing",
    ),
    "tv_wall": ("tv wall", "media wall", "tv unit wall"),
    "flooring": (
        "floor", "flooring", "herringbone", "parquet", "wood floor",
        "stone floor",
    ),
    "focal_wall": ("focal wall", "accent wall", "feature wall"),
    "terrace_opening": (
        "terrace", "balcony opening", "outdoor opening", "patio opening",
    ),
    "sliding_doors": ("sliding doors", "sliding door"),
    "ceiling": ("ceiling", "exposed ceiling", "ceiling height"),
    "partition": ("partition", "internal wall"),  # generic non-glazed partition
}


# ── Anchor → reference phrasing ──────────────────────────────────────────────
# Each anchor maps to ONE architect-voiced 1-sentence reference. Phrasing
# avoids the word "preserve" twice in a row (constraint_ack already uses
# "I'll preserve…") — we use "continue preserving / remains / still
# anchors" so the memory reference feels like a fresh narrative beat,
# not a duplicate of the V2 acknowledgment.

_ANCHOR_REFERENCES: dict[str, str] = {
    "windows": (
        "I'll continue preserving the glazing strategy we established earlier."
    ),
    "open_kitchen": (
        "The open kitchen remains one of the design anchors we've kept "
        "throughout the project."
    ),
    "glazed_partition": (
        "The glazed partition we anchored earlier still defines the spatial "
        "flow."
    ),
    "tv_wall": (
        "The TV wall we set up earlier still anchors the focal arrangement."
    ),
    "flooring": (
        "The flooring choice we settled on still grounds the composition."
    ),
    "focal_wall": (
        "The focal wall we anchored earlier still leads the composition."
    ),
    "terrace_opening": (
        "The terrace opening we kept earlier still defines the outward "
        "connection."
    ),
    "sliding_doors": (
        "The sliding doors we anchored still carry the openness across "
        "iterations."
    ),
    "ceiling": (
        "The ceiling treatment we kept still shapes the room's vertical "
        "proportions."
    ),
    "partition": (
        "The partition layout we agreed on earlier still organises the "
        "circulation."
    ),
}


# Iteration gate — memory references only fire from V3 onward. On V2 the
# constraint_acknowledgment block already carries the "I'll preserve …"
# message, so a separate memory line would feel redundant. By V3+ the
# acknowledgment is silent and the memory reference can take over the
# narrative-continuity role.
_MIN_ITERATION = 3


# Patterns compiled at module load.
_ANCHOR_PATTERNS: dict[str, re.Pattern] = {
    aid: re.compile(
        r"\b(?:" + "|".join(re.escape(kw) for kw in kws) + r")\b",
        re.IGNORECASE,
    )
    for aid, kws in _ANCHOR_KEYWORDS.items()
}


# ── Helpers ─────────────────────────────────────────────────────────────────

def _scan_text_for_anchors(text: str) -> list[str]:
    """Return list of anchor_ids present in `text` (insertion order)."""
    if not text:
        return []
    matched: list[str] = []
    for aid, pattern in _ANCHOR_PATTERNS.items():
        if pattern.search(text):
            matched.append(aid)
    return matched


def _collect_keep_text(refinement_state: Any) -> str:
    """
    Concatenate everything in refinement_state.keep into a single lowercased
    blob ready to scan for anchor keywords.
    """
    if refinement_state is None:
        return ""
    keep_list = getattr(refinement_state, "keep", None) or []
    parts: list[str] = []
    for raw in keep_list:
        if isinstance(raw, str) and raw.strip():
            parts.append(raw.strip())
    return " ".join(parts).lower()


# ── Public API ───────────────────────────────────────────────────────────────

def extract_anchor(
    refinement_state: Any,
    user_message: str = "",
) -> Optional[str]:
    """
    Return the anchor_id of the most prominent architectural anchor the user
    has previously preserved AND has NOT mentioned in the latest message.

    Logic :
      1. Build a single text blob from refinement_state.keep
      2. Find the FIRST anchor_id that matches the blob (registry order)
      3. If the user's latest message also mentions that anchor, return
         None — the user just spoke about it, no memory beat needed.

    Returns None when refinement_state has nothing to anchor on, or when
    the only kept anchor was just mentioned.
    """
    keep_blob = _collect_keep_text(refinement_state)
    if not keep_blob:
        return None
    keep_anchors = _scan_text_for_anchors(keep_blob)
    if not keep_anchors:
        return None

    user_anchors = set(_scan_text_for_anchors(user_message or ""))
    for anchor_id in keep_anchors:
        if anchor_id not in user_anchors:
            return anchor_id
    return None


def get_memory_reference(
    refinement_state: Any,
    iteration: int,
    user_message: str = "",
) -> str:
    """
    Return a single architect-voice memory sentence ready to prepend to the
    architect response, or "" when no reference would add value.

    Gate :
      - iteration < 3      → "" (V1/V2 covered by other layers)
      - no anchor extracted → ""
      - user just mentioned the anchor → ""

    Caller (architect_response orchestrator) applies its own secondary
    suppression for constraint_ack / alternatives main enrichments.
    """
    if iteration < _MIN_ITERATION:
        return ""
    anchor_id = extract_anchor(refinement_state, user_message)
    if anchor_id is None:
        return ""
    return _ANCHOR_REFERENCES.get(anchor_id, "")


def list_anchors() -> list[str]:
    """Return all known anchor IDs — for tests / introspection."""
    return list(_ANCHOR_KEYWORDS.keys())


def min_iteration() -> int:
    """Expose the iteration gate for tests."""
    return _MIN_ITERATION
