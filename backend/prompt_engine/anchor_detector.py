"""
Architectural anchor detection — Wave 4.3.0: Preservation Intelligence.

Scans a room description (from GPT-4o-mini vision analysis) for signals that
identify preservable architectural anchors: glass partitions, multi-zone
layouts, spatial depth cues, distinctive openings, and structural features.

Returns an AnchorProfile. When no anchors are found, clause is empty string
— zero prompt cost in a generic single-zone room.

Detection is deterministic text matching — no ML calls, no latency.

Design constraint: clause is hard-capped at ~180 chars so the
atmosphere-switch contract stays within the STYLE_REFINEMENT budget.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class AnchorProfile:
    anchors: tuple[str, ...]  # detected labels (for logging)
    clause: str               # compact preservation clause for prompt injection


# ── Signal patterns ───────────────────────────────────────────────────────────

_PARTITION = re.compile(
    r"\b(glass\s+(partition|wall|panel|screen|divider|separator)|"
    r"(black|smoked|frosted|tinted|dark)\s+glass|"
    r"(steel|metal|iron)[\s-]frame[d]?\s+(glass|panel|screen|partition)|"
    r"glass\s+rail(ing)?|partition)\b",
    re.IGNORECASE,
)

_MULTI_ZONE = re.compile(
    r"\b(open[\s-]plan|open\s+concept|multi[\s-]zone|"
    r"(living|kitchen|dining)[\s-](dining|kitchen|living)|"
    r"connected\s+(kitchen|dining|living\s+room|space)|"
    r"visible\s+(kitchen|dining\s+(area|room)|staircase|terrace|balcony)|"
    r"through[\s-]room|flow(ing)?\s+between\s+(rooms?|zones?|spaces?)|"
    r"double[\s-]height|mezzanine|loft\s+(level|area|floor)|gallery\s+(level|floor))\b",
    re.IGNORECASE,
)

_DEPTH = re.compile(
    r"\b(diagonal\s+(view|depth|perspective|line|axis|composition)|"
    r"spatial\s+depth|long\s+(perspective|view|axis|corridor)|"
    r"deep\s+(perspective|spatial\s+depth)|layered\s+(depth|space|zones?)|"
    r"receding\s+(lines?|perspective|plane))\b",
    re.IGNORECASE,
)

_OPENING = re.compile(
    r"\b((large\s+)?(sliding|bi[\s-]fold|French|pivot|double)\s+door|"
    r"floor[\s-]to[\s-]ceiling\s+window|panoramic\s+window|"
    r"corner\s+window|bay\s+window|clerestory|rooflight|"
    r"balcony\s+(door|opening|access|threshold|connection)|"
    r"terrace\s+(door|opening|access|connection)|"
    r"glazed\s+(wall|facade|opening|door|front))\b",
    re.IGNORECASE,
)

_STRUCTURAL = re.compile(
    r"\b((structural\s+)?(column|pillar|post)|"
    r"exposed\s+(brick|concrete|steel\s+beam|timber\s+beam|beam|structure)|"
    r"(steel|timber|concrete|wooden)\s+beam|"
    r"archway|arch\s+(opening|doorway)|vaulted\s+ceiling|barrel\s+vault|"
    r"(spiral|floating|cantilevered|open)\s+stair(case|well)?|"
    r"skylight|rooflight)\b",
    re.IGNORECASE,
)

_ALL_PATTERNS = [_PARTITION, _MULTI_ZONE, _DEPTH, _OPENING, _STRUCTURAL]

# Hard budget limits
_MAX_ANCHORS = 4        # kept labels
_MAX_LABEL_CHARS = 24   # per label
_MAX_CLAUSE_CHARS = 185 # total clause budget

_CLAUSE_SUFFIX = ". Preserve these unchanged in the output."


def _extract(pattern: re.Pattern, text: str) -> list[str]:
    """De-duplicated, normalised matches from one pattern."""
    seen: set[str] = set()
    out: list[str] = []
    for m in pattern.finditer(text):
        label = " ".join(m.group().lower().split())[:_MAX_LABEL_CHARS]
        if label not in seen:
            seen.add(label)
            out.append(label)
    return out


def detect_anchors(room_description: str) -> AnchorProfile:
    """
    Detect architectural anchors in a room description.

    Returns AnchorProfile with empty clause when no anchors are found.
    Clause is always <= _MAX_CLAUSE_CHARS to stay within prompt budget.
    """
    if not room_description:
        return AnchorProfile(anchors=(), clause="")

    anchors: list[str] = []
    for pattern in _ALL_PATTERNS:
        anchors.extend(_extract(pattern, room_description))
        if len(anchors) >= _MAX_ANCHORS:
            anchors = anchors[:_MAX_ANCHORS]
            break

    if not anchors:
        return AnchorProfile(anchors=(), clause="")

    prefix = "ARCHITECTURAL ANCHORS — LOCKED: "
    anchor_list = "; ".join(anchors)
    clause = prefix + anchor_list + _CLAUSE_SUFFIX

    # Hard cap: trim to fewer anchors if still over budget
    while len(clause) > _MAX_CLAUSE_CHARS and len(anchors) > 1:
        anchors = anchors[:-1]
        anchor_list = "; ".join(anchors)
        clause = prefix + anchor_list + _CLAUSE_SUFFIX

    if len(clause) > _MAX_CLAUSE_CHARS:
        return AnchorProfile(anchors=(), clause="")  # fail-safe: no clause

    return AnchorProfile(anchors=tuple(anchors), clause=clause)
