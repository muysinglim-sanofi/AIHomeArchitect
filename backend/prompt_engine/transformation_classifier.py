"""
transformation_classifier.py — Wave 3.4 transformation type understanding.

Classifies the ARCHITECTURAL DEPTH of a design request:
  STYLE_REFINEMENT      — qualitative adjustments to existing atmosphere
  OBJECT_EDIT           — add/remove/change a specific object or surface
  ATMOSPHERE_SWITCH     — change to a different named style/atmosphere
  LAYOUT_REINTERPRETATION — rethink the spatial arrangement of the room
  FUNCTIONAL_REASSIGNMENT — change the purpose of a zone/space
  STRUCTURAL_CHANGE     — modify architectural elements (walls, openings)
  UNKNOWN               — general or unclassified request

The type directly controls how much spatial preservation language is injected
into the generation prompt. More disruptive transformations get stronger
preservation constraints to prevent spatial destruction.

IMPORTANT: This classifier adds to user_instruction, not to the frozen
compose_generation_prompt internals. The frozen prompt composer is unchanged.
"""

from __future__ import annotations
import re
from enum import Enum


class TransformationType(str, Enum):
    STYLE_REFINEMENT       = "style_refinement"
    OBJECT_EDIT            = "object_edit"
    ATMOSPHERE_SWITCH      = "atmosphere_switch"
    LAYOUT_REINTERPRETATION = "layout_reinterpretation"
    FUNCTIONAL_REASSIGNMENT = "functional_reassignment"
    STRUCTURAL_CHANGE      = "structural_change"
    UNKNOWN                = "unknown"


# ── Detection patterns ────────────────────────────────────────────────────────
# Order matters: check most specific first to avoid false-positives.

_ATMOSPHERE_SWITCH_RE = re.compile(
    r"\b(switch\s+to|change\s+(the\s+)?(atmosphere|style|look|feel)|try\s+(a\s+|the\s+)?(\w+\s+)+(style|look|atmosphere|vibe)|"
    r"go\s+with|try\s+(zen|japandi|warm\s+modern|nordic|scandinavian|luxury|dark\s+contemporary|"
    r"tropical|bali|desert|organic|wabi.sabi|soft\s+luxury|nature|coastal|art\s+deco|eclectic)|"
    r"(zen|japandi|nordique|scandinave|luxe|organique|tropical|balinais|désertique|"
    r"côtier|art\s+déco)\s+(retreat|style|atmosphere|look)?|"
    r"essaie\s+le?\s+(style|atmosphère|look)|"
    # Wave 5.5.8 — frontend atmosphere-card trigger pattern. The reveal-screen
    # tap sends user_instruction='Redesign this space in the {style} style.'
    # (cf. chat_screen.dart:366 `_exploreDirection`). Pre-Wave-5.5.8 this
    # pattern was classified as UNKNOWN for 6/10 atmospheres (Nordic, Warm,
    # Bali, Soft Luxury, Dark Contemporary, Nature Retreat) because their
    # names weren't in the alternation-6 keyword list. UNKNOWN is then
    # treated as a customization (is_customization_transformation
    # conservative policy), which made all subsequent V2/V3 pure switches
    # misclassify as REBOOT_CUSTOMIZED instead of REBOOT_FRESH → no
    # Wave-5.5.6 delegation → composer_v2 5-section path used instead of
    # composer.py Path D → V1≠V2/V3 byte-identity broken. Match structure-
    # based pattern: "Redesign this/the space/room/place in the/a <X> style"
    # — handles ANY atmosphere name (1-3 words) inside the `in the/a ... style`
    # delimiter, so all 10 atmospheres now classify as ATMOSPHERE_SWITCH.
    # Strict bookends (redesign... + style) prevent false positives like
    # "Redesign the kitchen with new tiles" (no `in the X style` suffix).
    r"redesign\s+(?:this|the)\s+(?:space|room|place)\s+in\s+(?:the|a)\s+.+?\s+style)\b",
    re.IGNORECASE,
)

_FUNCTIONAL_REASSIGNMENT_RE = re.compile(
    r"\b(turn\s+(the|this|a)\s+\w+(\s+\w+)?\s+(into|to\s+a)|"
    r"convert\s+(the|this)\s+\w+|make\s+(this|the)\s+\w+(\s+\w+)?\s+(into|a\s+\w+)|"
    r"use\s+(this|the)\s+\w+\s+as\s+a|repurpose\s+the|"
    r"transform\s+(this|the)\s+\w+\s+into|"
    r"transformer\s+(le|la|cet?)\s+\w+\s+en|utiliser\s+(le|la|cet?)\s+\w+\s+comme|"
    r"convertir\s+(le|la|cet?))\b",
    re.IGNORECASE,
)

_STRUCTURAL_CHANGE_RE = re.compile(
    r"\b(open\s+up\s+the|knock\s+down\s+the\s+wall|remove\s+(the\s+)?wall|"
    r"add\s+a\s+wall|lower\s+the\s+ceiling|raise\s+the\s+ceiling|"
    r"extend\s+the\s+(room|space|kitchen|living)|(create|add)\s+(an?\s+)?opening|"
    r"add\s+(a\s+)?window|enlarge\s+the|ouvrir\s+(le|la|l')|"
    r"abattre\s+(le|la|le\s+mur)|agrandir\s+(le|la)|"
    r"créer\s+(une?\s+)?ouverture)\b",
    re.IGNORECASE,
)

_LAYOUT_REINTERPRETATION_RE = re.compile(
    r"\b(redesign\s+(the\s+)?layout|rethink\s+the|start\s+over|"
    r"completely\s+different\s+(layout|direction|approach)|new\s+layout|"
    r"rearrange\s+(everything|the\s+(whole\s+)?layout|the\s+furniture)|"
    r"different\s+arrangement|reorganize\s+the|move\s+everything|"
    r"repenser\s+(le|la)|réorganiser\s+(tout|le|la)|tout\s+réaménager)\b",
    re.IGNORECASE,
)

_STYLE_REFINEMENT_RE = re.compile(
    r"\b(warmer|cooler|darker|lighter|moodier|softer|stronger|deeper|richer|"
    r"more\s+(warm|cool|dark|light|moody|soft|dramatic|calm|cozy|minimal|luxurious)|"
    r"less\s+(harsh|cold|bright|dark|heavy|cluttered)|"
    r"push\s+(it|the|this)\s+(further|more|darker|lighter|warmer)|"
    r"plus\s+(chaud|froid|sombre|lumineux|doux|dramatique|calme)|"
    r"moins\s+(sombre|lumineux|chargé|lourd)|"
    r"pousse[rz]?\s+(encore|plus|davantage))\b",
    re.IGNORECASE,
)

_OBJECT_EDIT_RE = re.compile(
    r"\b(add\s+(a|an|the|one|some)\s+\w+|remove\s+(the|a|an)\s+\w+|"
    r"change\s+the\s+\w+|replace\s+the\s+\w+|swap\s+(the|out\s+the)\s+\w+|"
    r"put\s+(a|an|the|one)\s+\w+|move\s+the\s+\w+\s+(to|from)|"
    r"take\s+(out|away)\s+the|get\s+rid\s+of\s+the|"
    r"ajoute[rz]?\s+(un|une|le|la|les)|enl[eè]ve[rz]?\s+(le|la|les|un|une)|"
    r"retire[rz]?\s+(le|la|les)|remplace[rz]?\s+(le|la|les)|"
    r"mets?\s+(un|une|le|la)|déplace[rz]?\s+(le|la|les))\b",
    re.IGNORECASE,
)


def classify_transformation(message: str, iteration: int = 1) -> TransformationType:
    """
    Classify the architectural depth of a design request.

    Priority order: most disruptive/specific first to avoid false-positives.
    FUNCTIONAL_REASSIGNMENT > STRUCTURAL_CHANGE > ATMOSPHERE_SWITCH >
    LAYOUT_REINTERPRETATION > OBJECT_EDIT > STYLE_REFINEMENT > UNKNOWN
    """
    if not message.strip():
        return TransformationType.UNKNOWN

    if _FUNCTIONAL_REASSIGNMENT_RE.search(message):
        return TransformationType.FUNCTIONAL_REASSIGNMENT

    if _STRUCTURAL_CHANGE_RE.search(message):
        return TransformationType.STRUCTURAL_CHANGE

    if _ATMOSPHERE_SWITCH_RE.search(message):
        return TransformationType.ATMOSPHERE_SWITCH

    if _LAYOUT_REINTERPRETATION_RE.search(message):
        return TransformationType.LAYOUT_REINTERPRETATION

    if _OBJECT_EDIT_RE.search(message):
        return TransformationType.OBJECT_EDIT

    if _STYLE_REFINEMENT_RE.search(message):
        return TransformationType.STYLE_REFINEMENT

    return TransformationType.UNKNOWN


# ── Spatial preservation addenda ──────────────────────────────────────────────
# These are APPENDED to user_instruction before passing to the frozen
# compose_generation_prompt(). They add spatial coherence language without
# touching the frozen prompt system.

_ATMOSPHERE_SWITCH_ADDENDUM = (
    "ATMOSPHERE SWITCH — MATERIAL AND MOOD TRANSFORMATION ONLY: "
    "The room's spatial layout, furniture arrangement, zoning, and all openings are PRESERVED EXACTLY. "
    "Apply the new atmosphere through: material surfaces, lighting temperature, colour palette, textiles. "
    "Windows must remain unblocked and natural light must remain visible — "
    "the atmosphere is expressed through HOW light reads off materials, not by eliminating windows. "
    "DO NOT: rearrange furniture zones, place objects in front of windows, alter the sense of "
    "openness or enclosure, remove visible secondary spaces, or flatten the depth between zones."
)

_FUNCTIONAL_REASSIGNMENT_ADDENDUM = (
    "FUNCTIONAL REASSIGNMENT — Turn this zone into its designated new functional role: "
    "A specific zone adopts a new primary use — this is a genuine zone-level transformation, "
    "not merely furniture rearrangement. "
    "VISUAL CLARITY REQUIREMENT: each reassigned zone must VISUALLY READ as its new function. "
    "A zone reassigned to sleeping must look like a genuine sleeping space — "
    "the furniture arrangement, spatial density, and lighting must communicate rest and privacy. "
    "A zone reassigned to living/viewing must look like a real space for relaxed habitation — "
    "furniture must face the viewing direction, seating must address the screen or focal point. "
    "If the instruction specifies a directional relationship between zones "
    "(e.g., screen faces seating, desk faces window), that spatial relationship must be "
    "clearly and correctly visible in the generated image — elements must face each other "
    "across the correct zone axis. "
    "All architectural elements (walls, windows, openings) remain fixed in position — "
    "the spatial footprint and floor plan geometry are frozen. "
    "Preserve all visible room relationships and the established spatial logic. "
    "The transformation is functional — the viewer must immediately understand "
    "which zone does what and why. "
    "ERGONOMIC PLAUSIBILITY: furniture must be at correct human scale and height, "
    "circulation paths must remain clear and believable, "
    "and the spatial logic must read as a real, usable space — not a staged composition."
)

_STRUCTURAL_CHANGE_ADDENDUM = (
    "STRUCTURAL CHANGE: "
    "This is a precise architectural edit. "
    "Apply only the specific structural modification described. "
    "Preserve all other elements exactly — atmosphere character, "
    "material palette, furniture, lighting, and all non-mentioned zones. "
    "The overall spatial logic outside the modified area does not change."
)

_LAYOUT_REINTERPRETATION_ADDENDUM = (
    "LAYOUT REINTERPRETATION: "
    "The spatial arrangement may evolve, but the architectural shell is locked. "
    "Windows, walls, and room proportions are non-negotiable. "
    "Reinterpret furniture placement and zone logic within the same footprint. "
    "Maintain atmosphere character and livability throughout."
)

_MULTI_SPACE_LOCK = (
    "MULTI-SPACE TOPOLOGY LOCK: "
    "The following visible spaces are STRUCTURALLY PROTECTED: {zones}. "
    "They must remain visible, recognisable, and in their established spatial positions. "
    "The depth relationship between foreground and background zones is LOCKED — "
    "preserve the sense of spatial depth, the front-to-back perspective reading, "
    "and all visible openings, glass dividers, or transitions between zones. "
    "Do NOT compress the background, merge zones, or flatten the spatial topology. "
    "The apartment must read as multi-space — the same number of visible areas, "
    "in the same spatial relationship, as in the source image."
)

_REALISM_ADDENDUM = (
    "LIVABILITY CONSTRAINT: "
    "The result must be a space a real person could actually inhabit. "
    "Maintain: adequate natural light, furniture at correct human scale, "
    "clear circulation paths, and believable spatial proportions. "
    "Avoid: impossible darkness, oversized or floating furniture, "
    "inaccessible zones, or spatially incoherent geometry."
)

_ZEN_LIGHTING_DISCIPLINE = (
    "ZEN LIGHTING DISCIPLINE — CRITICAL: "
    "Zen calm = breathable and naturally lit, NOT dark. "
    "Preserve daylight from all windows, maintain visual readability, "
    "keep the space soft and balanced. "
    "DO NOT darken the apartment, suppress windows, or create cinematic heavy shadow. "
    "Zen calm is achieved through MATERIAL RESTRAINT and SPATIAL EMPTINESS — not darkness. "
    "The apartment must remain visually open and naturally lit throughout."
)


def build_spatial_preservation_addendum(
    transformation_type: TransformationType,
    secondary_spaces: list[str],
    room_type: str = "",
    atmosphere_id: str = "",
) -> str:
    """
    Build a spatial preservation addendum to append to user_instruction.

    Returns empty string for OBJECT_EDIT and STYLE_REFINEMENT — those
    transformation types don't need extra spatial protection beyond what
    the frozen structural contract already provides.
    """
    parts: list[str] = []

    # Zen Retreat lighting discipline MUST appear first — prompt budget truncation
    # cuts late content, and this constraint must override the DNA lighting_behavior
    # ("near-darkness punctuated by warm shafts") which causes cinematic darkness.
    # Position 0 guarantees it survives even when the full addendum exceeds budget.
    if atmosphere_id == "zen_retreat":
        parts.append(_ZEN_LIGHTING_DISCIPLINE)

    # Transformation-specific addendum
    if transformation_type == TransformationType.ATMOSPHERE_SWITCH:
        parts.append(_ATMOSPHERE_SWITCH_ADDENDUM)
    elif transformation_type == TransformationType.FUNCTIONAL_REASSIGNMENT:
        parts.append(_FUNCTIONAL_REASSIGNMENT_ADDENDUM)
    elif transformation_type == TransformationType.STRUCTURAL_CHANGE:
        parts.append(_STRUCTURAL_CHANGE_ADDENDUM)
    elif transformation_type == TransformationType.LAYOUT_REINTERPRETATION:
        parts.append(_LAYOUT_REINTERPRETATION_ADDENDUM)
    # OBJECT_EDIT and STYLE_REFINEMENT: no addendum needed, existing structural
    # contract handles these fine

    # Multi-space lock for any transformation when secondary spaces are visible.
    # OBJECT_EDIT is the only exclusion — surgical edits don't need topology language.
    # STYLE_REFINEMENT and UNKNOWN both need the lock because atmosphere changes
    # are exactly when the model tends to flatten background zones.
    if secondary_spaces and transformation_type not in (
        TransformationType.OBJECT_EDIT,
    ):
        zone_list = ", ".join(s.replace("_", " ") for s in secondary_spaces[:3])
        parts.append(_MULTI_SPACE_LOCK.format(zones=zone_list))

    # Livability constraint for high-risk transformations
    if transformation_type in (
        TransformationType.ATMOSPHERE_SWITCH,
        TransformationType.LAYOUT_REINTERPRETATION,
        TransformationType.FUNCTIONAL_REASSIGNMENT,
    ):
        parts.append(_REALISM_ADDENDUM)

    return " ".join(parts)
