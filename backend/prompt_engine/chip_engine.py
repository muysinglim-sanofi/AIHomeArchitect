"""
chip_engine.py — Wave 3.4 contextual suggestion chip engine.

Generates suggestion chips that are spatially aware, transformation-specific,
and architecturally grounded. Builds on top of the Wave 2.5 suggestion engine
without replacing it.

Chip design rules (extended from Wave 2.5):
  - 4–8 words per chip
  - Reflect what just happened and what naturally comes next
  - Transformation-type-aware: after an atmosphere switch, offer spatial chips
  - Secondary-space-aware: offer chips to protect or refine visible zones
  - Never duplicate within a set
  - Mix spatial, atmospheric, and conversational directions

Wave 2.5 chips remain as fallback when contextual pools don't provide enough.
"""

from __future__ import annotations
from .transformation_classifier import TransformationType
from .suggestion_engine import _ATM_CHIPS, _ROOM_CHIPS, _UNIVERSAL_CHIPS, get_suggestion_chips
from .edit_intent import EditMode
from .intent_classifier import SubIntent


# ── Transformation-type chip pools ────────────────────────────────────────────

_TRANSFORMATION_CHIPS: dict[TransformationType, list[str]] = {
    TransformationType.ATMOSPHERE_SWITCH: [
        "Keep the spatial openness",
        "Soften the atmosphere slightly",
        "Preserve the natural light",
        "Keep the furniture layout intact",
        "Adjust the lighting temperature",
        "Keep the windows visible and open",
        "Push the mood further",
        "Maintain the depth between zones",
    ],
    TransformationType.OBJECT_EDIT: [
        "Try a different material for that",
        "Adjust the scale of this element",
        "Add a complementary piece nearby",
        "Fine-tune the placement",
        "Balance with the opposite side",
    ],
    TransformationType.STYLE_REFINEMENT: [
        "Push this direction further",
        "Balance with a lighter element",
        "Shift the lighting tone",
        "Add one textural layer",
        "Reduce one element to strengthen the rest",
    ],
    TransformationType.LAYOUT_REINTERPRETATION: [
        "Refine the zone boundaries",
        "Adjust the focal point",
        "Open or close the flow",
        "Strengthen the layout logic",
        "Add a circulation anchor",
    ],
    TransformationType.FUNCTIONAL_REASSIGNMENT: [
        "Strengthen the zone identity",
        "Add privacy to the new zone",
        "Adjust the lighting for the new use",
        "Make the zone feel more defined",
        "Fine-tune the material balance",
        "Soften the boundary between spaces",
    ],
    TransformationType.STRUCTURAL_CHANGE: [
        "Define the new space relationship",
        "Add material continuity across zones",
        "Adjust the flow between areas",
        "Strengthen the structural reveal",
        "Balance the new proportions",
    ],
    TransformationType.UNKNOWN: [
        "Push this direction further",
        "Try a different material angle",
        "Simplify one element",
        "Adjust the lighting character",
    ],
}

# ── Secondary space chips ─────────────────────────────────────────────────────
# Used when visible secondary spaces are present.

_SECONDARY_SPACE_CHIPS: dict[str, list[str]] = {
    "bedroom":      [
        "Keep the rear bedroom visible",
        "Add privacy near the sleeping area",
        "Keep the bedroom zone soft",
        "Make the bedroom area quieter",
    ],
    "living_room":  [
        "Keep the living zone visible",
        "Preserve the open relationship",
        "Keep the rear room readable",
        "Maintain the depth between zones",
    ],
    "kitchen":      [
        "Keep the kitchen connection open",
        "Keep the cooking zone readable",
        "Maintain the kitchen visibility",
        "Preserve the kitchen zone framing",
    ],
    "dining_room":  [
        "Keep the dining area in view",
        "Preserve the dining zone scale",
        "Keep the dining connection visible",
    ],
    "bathroom":     [
        "Keep the bathroom threshold clear",
        "Preserve the wet zone boundary",
    ],
    "home_office":  [
        "Keep the work zone defined",
        "Preserve the desk area light",
    ],
    "entrance_hall": [
        "Keep the entrance sequence open",
        "Preserve the arrival depth",
    ],
}

_GENERIC_SECONDARY_CHIP = "Maintain the open spatial relationship"

# ── Iteration-aware chips ─────────────────────────────────────────────────────

_EARLY_ITERATION_CHIPS = [   # iter 1-2: exploring
    "Try a completely different direction",
    "Push this atmosphere further",
    "Keep this as a base",
]

_MID_ITERATION_CHIPS = [     # iter 3-5: refining
    "Fine-tune the material balance",
    "Keep this version as reference",
    "Show me a variation on this",
]

_LATE_ITERATION_CHIPS = [    # iter 6+: finalising
    "Keep this as my final version",
    "Make one small adjustment",
    "Restore the previous version",
]


def _iter_band_chips(iteration: int) -> list[str]:
    if iteration <= 2:
        return _EARLY_ITERATION_CHIPS
    elif iteration <= 5:
        return _MID_ITERATION_CHIPS
    return _LATE_ITERATION_CHIPS


# ── Engine ─────────────────────────────────────────────────────────────────────

def get_contextual_chips(
    atmosphere_id: str,
    room_type: str,
    iteration: int,
    transformation_type: TransformationType = TransformationType.UNKNOWN,
    secondary_spaces: list[str] | None = None,
    count: int = 4,
) -> list[str]:
    """
    Return contextually-aware suggestion chips for the current design state.

    Selection strategy:
      1. 1–2 transformation-type chips (most spatially relevant)
      2. 1 secondary-space chip if visible spaces exist
      3. 1–2 atmosphere-specific chips
      4. 1 iteration-band chip
      5. Fill remainder from room chips → universal fallback

    Returns `count` chips, deduplicated.
    """
    result: list[str] = []
    seen: set[str] = set()

    def _add(chip: str) -> None:
        if chip not in seen and len(result) < count:
            seen.add(chip)
            result.append(chip)

    # 1. Transformation-type chips (1–2, most contextual)
    tx_pool = _TRANSFORMATION_CHIPS.get(transformation_type, _TRANSFORMATION_CHIPS[TransformationType.UNKNOWN])
    for chip in tx_pool[:2]:
        _add(chip)

    # 2. Secondary space chip (1, if present)
    if secondary_spaces:
        for space in secondary_spaces[:2]:
            space_chips = _SECONDARY_SPACE_CHIPS.get(space, [])
            if space_chips:
                _add(space_chips[0])
                break
        if len(result) < 2:
            _add(_GENERIC_SECONDARY_CHIP)

    # 3. Iteration-band chip (added before atm to guarantee it appears)
    for chip in _iter_band_chips(iteration):
        _add(chip)
        break

    # 4. Atmosphere-specific chips
    atm_pool = _ATM_CHIPS.get(atmosphere_id, [])
    for chip in atm_pool[:2]:
        _add(chip)

    # 5. Fill remainder with room and universal chips
    room_pool = _ROOM_CHIPS.get(room_type, [])
    for chip in room_pool:
        if len(result) >= count:
            break
        _add(chip)

    for chip in atm_pool:
        if len(result) >= count:
            break
        _add(chip)

    for chip in _UNIVERSAL_CHIPS:
        if len(result) >= count:
            break
        _add(chip)

    # Fallback: if still not enough, pull from more transformation chips
    for chip in tx_pool[2:]:
        if len(result) >= count:
            break
        _add(chip)

    return result[:count]
