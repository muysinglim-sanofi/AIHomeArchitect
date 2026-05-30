"""
Conversational refinement memory — stateless reconstruction from history.

The design conversation accumulates intent over multiple iterations.
This module parses the message history into typed refinement categories
so the prompt can be intelligently constructed for each subsequent vision.

Architecture decision: fully stateless — rebuilt from the history JSON on
every request. No backend session state needed. Works with the existing
Supabase message persistence.

Refinement categories:
  KEEP      — user said to preserve something ("keep the wood", "maintain that lighting")
  ADD       — user wants more of something ("more warmth", "add plants")
  REMOVE    — user wants less of something ("less clutter", "remove the rug")
  DIRECTION — general aesthetic direction ("more modern", "hotel feeling")
"""

import re
from dataclasses import dataclass, field


@dataclass
class RefinementState:
    keep: list[str] = field(default_factory=list)       # things to preserve
    add: list[str] = field(default_factory=list)         # things to increase/add
    enhance: list[str] = field(default_factory=list)     # qualitative intensification
    remove: list[str] = field(default_factory=list)      # things to eliminate
    directions: list[str] = field(default_factory=list)  # general design directions
    latest: str = ""                                     # most recent user instruction


# ── Keyword classifiers ───────────────────────────────────────────────────────

_KEEP_PATTERNS = re.compile(
    r"\b(keep|preserve|maintain|retain|leave|stay|same|don'?t change|unchanged|like that|love that|good)\b",
    re.IGNORECASE,
)
# ENHANCE: qualitative intensification — the thing already exists, make it MORE of what it is.
# Distinct from ADD (physical addition of objects). "Warmer" enhances warmth; "add plants" adds objects.
_ENHANCE_PATTERNS = re.compile(
    r"\b(warmer|cozier|cosier|cooler|calmer|brighter|darker|moodier|more luxurious|more premium|"
    r"more elegant|more dramatic|more serene|more inviting|more refined|more sophisticated|"
    r"more intense|more vibrant|more organic|more natural|more textural|more layered|"
    r"richer|deeper|bolder|stronger|softer|heavier|lighter|more|premium|luxurious|elegant|"
    r"sophisticated|dramatic|serene|inviting|refined|intense|vibrant|organic|textural|layered)\b",
    re.IGNORECASE,
)
_ADD_PATTERNS = re.compile(
    r"\b(add|include|bring in|introduce|place|put|insert|extra|extend|more of)\b",
    re.IGNORECASE,
)
_REMOVE_PATTERNS = re.compile(
    r"\b(less|fewer|reduce|remove|eliminate|take out|without|no |simpler|cleaner|"
    r"smaller|plainer|minimal|minimal[ie]se|strip|de-clutter|declutter)\b",
    re.IGNORECASE,
)

# Wave 4.11e (sanity-check follow-up) — negative-feedback guard.
#
# `_KEEP_PATTERNS` includes the word `good`, which causes complaints like
# "the colors are not good" to score as a keep signal — the "good" token
# matches, and `_classify` returns "keep", and the bullet "Preserve: The
# colors are not good" surfaces in the design brief summary (Scenario 4
# turn 5 of the pre-commit sanity check : 2026-05-30).
#
# A user complaint must never be reformulated as something to preserve.
# This guard runs FIRST in `_classify` ; when it matches, the clause is
# returned as "skip" and `parse_history` drops it from every bucket.
#
# Minimal redundancy with `intent_classifier._NEGATIVE_FEEDBACK_PATTERNS`
# is intentional (avoids a circular import) ; both must stay aligned in
# any future wave that touches negative-feedback detection.
_NEGATIVE_FEEDBACK_GUARD = re.compile(
    r"\b("
    # "I don't like / dislike / hate"
    r"i\s+don'?t\s+(like|love|want|enjoy)|"
    r"i\s+do\s+not\s+(like|love|want|enjoy)|"
    r"i\s+(dislike|hate)|i\s+can'?t\s+stand|"
    r"i'?m\s+not\s+(happy|sold|loving|convinced)|"
    # Singular and plural negation : "the X is not good", "the X are not good",
    # "these aren't good", "this doesn't work"
    r"(this|it|that|these|those|the\s+\w+)(\s+\w+){0,3}\s+"
    r"(doesn'?t|does\s+not|isn'?t|is\s+not|aren'?t|are\s+not|"
    r"weren'?t|were\s+not|don'?t|do\s+not)\s+"
    r"(work|working|right|good|great|landing|coming\s+together|"
    r"fit|fitting|read\s+well|enough)|"
    # "feels wrong / off / bad / worse"
    r"(feels|reads|looks)\s+(wrong|off|bad|flat|forced|worse|sterile)|"
    # "this is worse" / "worse than"
    r"(this|it|that)\s+is\s+worse|worse\s+than|"
    # "preferred / liked the previous"
    r"preferred\s+(the\s+)?(previous|older|earlier|first|last|old)|"
    r"liked\s+(the\s+)?(previous|older|earlier|first|last|old)"
    r")\b",
    re.IGNORECASE,
)

# Bare plural-noun complaints anchored at clause start ("colors are not
# good", "materials aren't right"). Separate from the main guard so the
# anchor is enforced per clause not per message — `parse_history` splits
# on punctuation BEFORE calling `_classify`, so each clause stands alone.
_NEGATIVE_FEEDBACK_GUARD_BARE = re.compile(
    r"^\s*\w+s\s+(aren'?t|are\s+not|isn'?t|is\s+not|"
    r"weren'?t|were\s+not|don'?t|do\s+not)\s+"
    r"(good|right|working|enough|fitting|great)\b",
    re.IGNORECASE,
)


def _is_negative_feedback(text: str) -> bool:
    """Wave 4.11e (sanity-check follow-up) — True if the clause expresses
    a user complaint that must NOT be reformulated as a refinement."""
    return bool(_NEGATIVE_FEEDBACK_GUARD.search(text)
                or _NEGATIVE_FEEDBACK_GUARD_BARE.match(text.lstrip()))


def _classify(text: str) -> str:
    """Return the dominant refinement category for a user message."""
    # Wave 4.11e (sanity-check follow-up) — short-circuit on complaints
    # so the `good` token in _KEEP_PATTERNS can't reformulate "the colors
    # are not good" as a preservation directive.
    if _is_negative_feedback(text):
        return "skip"

    keep_score = len(_KEEP_PATTERNS.findall(text))
    enhance_score = len(_ENHANCE_PATTERNS.findall(text))
    add_score = len(_ADD_PATTERNS.findall(text))
    remove_score = len(_REMOVE_PATTERNS.findall(text))

    if keep_score == 0 and enhance_score == 0 and add_score == 0 and remove_score == 0:
        return "direction"
    if keep_score >= enhance_score and keep_score >= add_score and keep_score >= remove_score:
        return "keep"
    if enhance_score >= add_score and enhance_score >= remove_score:
        return "enhance"
    if add_score >= remove_score:
        return "add"
    return "remove"


def parse_history(history: list[dict], iteration: int) -> RefinementState:
    """
    Build a RefinementState from raw message history.

    history: list of {role: "user"|"ai", content: str}
    iteration: current vision number (1-based)

    Only user messages contribute to refinements; AI messages are ignored
    because they describe results, not intentions.
    Only messages from Vision 2 onward are parsed as refinements — the
    very first user message is treated as the initial design brief.
    """
    state = RefinementState()

    if iteration <= 1 or not history:
        return state

    user_messages = [
        m["content"].strip()
        for m in history
        if m.get("role") == "user" and m.get("content", "").strip()
    ]

    # Skip the first user message (initial brief — not a refinement)
    refinement_messages = user_messages[1:] if len(user_messages) > 1 else user_messages

    if not refinement_messages:
        return state

    # Latest instruction is always the most recent user message
    state.latest = user_messages[-1]

    # Classify each refinement message at clause level so that compound
    # messages ("more warmth, keep the wood, less clutter") are parsed correctly.
    for msg in refinement_messages:
        clauses = [c.strip() for c in re.split(r"[.,;!\n]", msg) if len(c.strip()) >= 4]
        if not clauses:
            clauses = [msg]

        for clause in clauses:
            category = _classify(clause)
            # Wave 4.11e (sanity-check follow-up) — negative feedback
            # must NOT pollute any refinement bucket. The complaint is a
            # signal to the architect ("user is unhappy") but it does NOT
            # describe what to preserve, push, add, remove, or pursue.
            if category == "skip":
                continue
            truncated = clause[:100]

            if category == "keep" and truncated not in state.keep:
                state.keep.append(truncated)
            elif category == "enhance" and truncated not in state.enhance:
                state.enhance.append(truncated)
            elif category == "add" and truncated not in state.add:
                state.add.append(truncated)
            elif category == "remove" and truncated not in state.remove:
                state.remove.append(truncated)
            elif truncated not in state.directions:
                state.directions.append(truncated)

    # Deduplicate and cap list lengths to keep prompt concise
    state.keep = state.keep[-3:]
    state.enhance = state.enhance[-3:]
    state.add = state.add[-3:]
    state.remove = state.remove[-3:]
    state.directions = state.directions[-2:]

    return state


def build_refinement_block(state: RefinementState, iteration: int) -> str:
    """
    Convert a RefinementState into a prompt fragment.
    Returns empty string for Vision 1 (no refinements yet).
    """
    if iteration <= 1:
        return ""

    parts = [f"REFINEMENT MEMORY (Vision {iteration}):"]

    if state.keep:
        parts.append(f"Preserve from previous vision: {'; '.join(state.keep)}.")

    if state.enhance:
        parts.append(f"Enhance quality of (push further, not add more objects): {'; '.join(state.enhance)}.")

    if state.add:
        parts.append(f"Add or introduce: {'; '.join(state.add)}.")

    if state.remove:
        parts.append(f"Reduce or eliminate: {'; '.join(state.remove)}.")

    if state.directions:
        parts.append(f"Design direction evolution: {'; '.join(state.directions)}.")

    if state.latest:
        latest_short = state.latest[:200]
        parts.append(f"Primary instruction for this vision: {latest_short}.")

    if len(parts) == 1:
        # Only header, no content — return empty
        return ""

    return " ".join(parts)
