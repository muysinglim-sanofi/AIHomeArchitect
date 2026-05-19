"""
Edit intent classifier and mode-specific prompt builder.

Converts raw user refinement instructions into one of three edit modes,
then builds a mode-appropriate prompt for that mode.

THREE MODES:
  LOCAL_EDIT               — object/color/placement changes
                             "add TV", "make sofa grey", "move plant near window"
  STYLE_REFINEMENT         — atmospheric/quality shifts
                             "more warm", "more luxury", "explore Japandi direction"
  STRUCTURAL_TRANSFORMATION — architectural changes
                             "open the facade", "add large window", "extend the terrace"

WHY THIS MATTERS:
The current full-redesign prompt ("Redesign this room as X...") triggers complete
scene regeneration on every call. For LOCAL_EDIT, that means a request like
"add a TV" causes the entire room to be reimagined from scratch. The local-edit
prompt strategy bypasses style DNA and redesign language entirely, instructing
the model to treat the task as surgical image editing rather than generation.

Only applies to iteration > 1. Vision 1 always uses the full redesign path.
"""

import re
from enum import Enum


class EditMode(str, Enum):
    FIRST_VISION = "first_vision"
    LOCAL_EDIT = "local_edit"
    STYLE_REFINEMENT = "style_refinement"
    STRUCTURAL_TRANSFORMATION = "structural_transformation"


# ── Classifiers ───────────────────────────────────────────────────────────────

_STRUCTURAL_SIGNALS = re.compile(
    r"\b(open\s+up|open\s+the\s+\w+|knock\s+(down|out|through)|remove\s+(the\s+)?wall|"
    r"add\s+(a\s+|an\s+)?(window|door|skylight|opening|arch)|extend|expand|demolish|"
    r"change\s+(the\s+)?layout|new\s+floor\s+plan|add\s+(a\s+)?room|larger\s+space|"
    r"move\s+the\s+(kitchen|bathroom|bedroom|living\s+room)|raise\s+the\s+ceiling|"
    # Functional reassignment: zone purpose changes are structural, not object edits
    r"turn\s+(the|this)\s+\w+(\s+\w+)?\s+(into|to\s+a)|"
    r"convert\s+(the|this)\s+\w+(\s+\w+)?\s+(into|to\s+a)|"
    r"make\s+(this|the)\s+\w+(\s+\w+)?\s+a\s+\w+(\s+(room|space|zone|area|nook|studio))?|"
    r"repurpose\s+(the|this)\s+\w+|"
    r"use\s+(this|the)\s+\w+(\s+\w+)?\s+as\s+a|"
    r"transform\s+(this|the)\s+\w+(\s+\w+)?\s+into)\b",
    re.IGNORECASE,
)

_LOCAL_EDIT_SIGNALS = re.compile(
    r"\b(add|place|put|hang|install|include|insert|remove|take\s+out|delete|"
    r"eliminate|move|shift|relocate|change|replace|swap|paint|colour|color|"
    r"make\s+(the|a|an|it)|turn\s+(the|it)\s+\w+|give\s+(the|it)|"
    r"(can\s+you|could\s+you|please)\s+(add|remove|change|replace|move|put|make|give))\b",
    re.IGNORECASE,
)

_STYLE_SIGNALS = re.compile(
    r"\b(warmer|cozier|cosier|cooler|calmer|brighter|darker|moodier|"
    r"more\s+(luxurious|premium|elegant|dramatic|serene|inviting|refined|"
    r"sophisticated|intense|vibrant|organic|natural|textural|layered|minimal|"
    r"warm|cozy|cosy|tropical|japandi|modern|luxury)|"
    r"feel\s+(more|less)|atmosphere|vibe|mood|tone|direction|aesthetic|"
    r"explore\s+.+\s+direction|try\s+.+\s+style|push\s+.+\s+further|"
    r"less\s+clutter|simpler|cleaner|bolder|softer|richer|deeper|"
    r"more\s+.+\s+(feeling|look|vibe|style))\b",
    re.IGNORECASE,
)


def classify_edit_mode(user_instruction: str, iteration: int) -> EditMode:
    """
    Classify user instruction into the appropriate edit mode.

    Scoring: each classifier is scored independently; the highest scorer wins.
    Structural signals take priority when tied with local (larger structural changes
    subsume any local edits mentioned alongside them).
    """
    if iteration <= 1:
        return EditMode.FIRST_VISION

    text = user_instruction.strip()
    if not text:
        return EditMode.STYLE_REFINEMENT

    structural = len(_STRUCTURAL_SIGNALS.findall(text))
    local = len(_LOCAL_EDIT_SIGNALS.findall(text))
    style = len(_STYLE_SIGNALS.findall(text))

    # Structural overrides local when it scores equally or higher
    if structural > 0 and structural >= local:
        return EditMode.STRUCTURAL_TRANSFORMATION
    # Local overrides style only when it scores strictly higher
    # Ties go to STYLE_REFINEMENT: "make it warmer/cozier" has equal local+style signals
    # but is an atmospheric shift, not a targeted object edit.
    if local > 0 and local > style:
        return EditMode.LOCAL_EDIT
    return EditMode.STYLE_REFINEMENT


# ── Change list parser ────────────────────────────────────────────────────────

_CONJUNCTIONS = re.compile(
    r"\s*;\s*|\s*,\s+(?:and\s+)?|\s+and\s+|\s+also\s+|\s+plus\s+|\s+then\s+",
    re.IGNORECASE,
)


def _split_changes(instruction: str) -> list[str]:
    """Split a compound instruction into individual, actionable change items."""
    parts = _CONJUNCTIONS.split(instruction)
    cleaned = [p.strip().rstrip(".,").strip() for p in parts]
    return [c for c in cleaned if len(c) >= 4]


# ── Prompt builders ───────────────────────────────────────────────────────────

def build_local_edit_prompt(
    user_instruction: str,
    style_name: str,
    room_type: str,
    room_description: str,
) -> str:
    """
    Targeted edit prompt for LOCAL_EDIT mode.

    Deliberately omits full style-DNA and redesign language — those tokens
    cause the model to regenerate the entire scene. Instead, this prompt:
    1. Frames the task as image editing, not image generation
    2. Lists required changes as an explicit numbered checklist
    3. Enumerates everything that must be preserved
    4. Ends with a strong visual-continuity instruction
    """
    changes = _split_changes(user_instruction)
    if changes:
        change_list = " ".join(
            f"({i + 1}) {c[0].upper() + c[1:]}." for i, c in enumerate(changes)
        )
    else:
        instruction = user_instruction.strip()
        change_list = f"(1) {instruction[0].upper() + instruction[1:]}." if instruction else "(1) Apply the requested changes."

    room_ctx = f" {room_type}" if room_type else ""
    description_ctx = f" Existing space: {room_description}" if room_description else ""

    return (
        f"TARGETED IMAGE EDIT — {room_ctx.strip() or 'room'} in {style_name} style.\n"
        f"MAKE ONLY THESE CHANGES (each must be clearly visible in the output): "
        f"{change_list}\n"
        f"PRESERVE EXACTLY — do not alter any of the following under any circumstances: "
        f"the camera angle, viewing height, and perspective; "
        f"all walls, windows, doors, and ceiling — their exact positions and character; "
        f"CRITICAL: all window openings must remain fully unblocked — "
        f"no furniture, object, or surface may overlap or cover a window; "
        f"natural light entering from every window must remain visible; "
        f"all furniture not explicitly mentioned above — positions, forms, and materials unchanged; "
        f"all objects and decorative items not explicitly mentioned above; "
        f"the lighting direction, warmth, and shadow pattern; "
        f"the floor material, color, and finish; "
        f"the overall spatial composition and room layout.\n"
        f"STYLE CONTEXT: new or changed elements should match the {style_name} aesthetic.{description_ctx}\n"
        f"OUTPUT REQUIREMENT: the result must look nearly identical to the input image "
        f"except for the listed changes. Furniture must not move. "
        f"The room must not be redesigned. The perspective must not shift. "
        f"This is surgical editing, not a new generation."
    )


def build_style_refinement_header(
    user_instruction: str,
    style_name: str,
    room_type: str,
) -> str:
    """
    Header block for STYLE_REFINEMENT mode.

    Wave 4.2.1: compressed from ~934 chars to ~300 chars.
    The full structural contract has been replaced by build_continuation_contract()
    (~375 chars) in the composer, so this header must NOT duplicate geometry
    preservation language — it only frames the evolution intent.
    """
    # Wave 4.8.2: de-duplicated. The frozen-geometry / spatial-anchors-locked /
    # PRESERVE-furniture prose was redundant with structural_identity +
    # atmosphere_contract (FROZEN camera/walls/windows + TOPOLOGY LOCKED) +
    # negative_anchors. Removing the duplication (this section is P1 and was
    # evicting design_intel/realism — see 4.8.1a) while keeping the canonical
    # SAME APARTMENT CONTINUATION + incremental-evolution + Direction tokens.
    room_ctx = f" {room_type}" if room_type else ""
    direction = f" Direction: {user_instruction.strip()[:160]}." if user_instruction.strip() else ""
    return (
        f"SAME APARTMENT CONTINUATION — REFINE this{room_ctx} — {style_name}. "
        f"Incremental evolution only: evolve materials, lighting, colour and "
        f"textiles; do not reimagine or replace the design.{direction}"
    )


def build_structural_transformation_header(
    user_instruction: str,
    style_name: str,
    room_type: str,
) -> str:
    """
    Header block for STRUCTURAL_TRANSFORMATION mode.

    Camera lock is still enforced. Architectural elements may evolve.
    The composer appends style DNA and structural contract after this header.
    """
    # Wave 4.8.2: de-duplicated. CAMERA LOCK / ALL VISIBLE ZONES / "refined
    # iteration" prose duplicated build_structural_evolution_contract +
    # structural_identity + negative_anchors. Kept the canonical
    # SAME APARTMENT CONTINUATION + ARCHITECTURAL EVOLUTION + ARCHITECTURAL
    # INTENT tokens (ARCHITECTURAL INTENT is validator-asserted).
    room_ctx = f" {room_type}" if room_type else ""
    return (
        f"SAME APARTMENT CONTINUATION — ARCHITECTURAL EVOLUTION — {style_name}{room_ctx}. "
        f"Only the explicitly requested architectural change applies; all else preserved. "
        f"ARCHITECTURAL INTENT: {user_instruction.strip()[:250]}."
    )
