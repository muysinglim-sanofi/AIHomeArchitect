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
    # Wave 5.13c — LAYOUT_CHANGE separates spatial rearrangement (move TV,
    # rearrange seating, put sofa against the wall) from pure local edits
    # (change colour, add object). Rearrangement needs position freedom +
    # partial DNA (atmosphere/lighting identity preserved) ; pure local
    # edits need maximum preservation (pixel-identical surgical pass).
    LAYOUT_CHANGE = "layout_change"
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
    # Wave 5.13c — `move|shift|relocate` removed: they belong to
    # LAYOUT_CHANGE which has its own dedicated path with partial DNA
    # and position-aware preservation rules. LOCAL_EDIT is now purely
    # for substitution / addition / removal of single items + colour
    # changes.
    r"\b(add|place|put|hang|install|include|insert|remove|take\s+out|delete|"
    r"eliminate|change|replace|swap|paint|colour|color|"
    r"make\s+(the|a|an|it)|turn\s+(the|it)\s+\w+|give\s+(the|it)|"
    r"(can\s+you|could\s+you|please)\s+(add|remove|change|replace|put|make|give))\b",
    re.IGNORECASE,
)

# Wave 5.13c — LAYOUT_CHANGE signals : spatial rearrangement of existing
# furniture pieces. The user wants to MOVE / ROTATE / REPOSITION items,
# not replace or restyle them. Two-bucket detection :
#   - Rearrangement verbs : move, shift, relocate, reposition, rearrange,
#     rotate, flip.
#   - Spatial-relational prepositions following an action verb : "in front
#     of", "next to", "beside", "against", "facing", "toward", "across
#     from", "opposite", "in the corner".
# "on the wall" / "in the center" intentionally excluded — too ambiguous
# with mounting-placement local edits.
_LAYOUT_SIGNALS = re.compile(
    r"\b(move|shift|relocate|reposition|rearrange|rotate|flip)\b|"
    r"\b(in\s+front\s+of|next\s+to|beside|against|facing|toward|"
    r"across\s+from|opposite\s+(the|a|an)|in\s+the\s+corner)\b",
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

    Wave 5.13c — priority order :
      STRUCTURAL > LAYOUT > LOCAL > STYLE

    Rationale :
      - STRUCTURAL (open the wall) overrides everything — architectural
        changes always win over decor-level signals.
      - LAYOUT (move TV in front of sofa) overrides LOCAL because spatial
        rearrangement needs its own dedicated path (partial DNA, position
        freedom + identity preservation). Without this split, "move TV"
        was falling into LOCAL_EDIT and getting the pixel-identical
        preservation rules — incompatible with movement intent.
      - LOCAL (change curtains to white, add flowers) wins over STYLE only
        when strictly higher : ties go to STYLE so "make it warmer/cozier"
        stays an atmospheric refinement.
    """
    if iteration <= 1:
        return EditMode.FIRST_VISION

    text = user_instruction.strip()
    if not text:
        return EditMode.STYLE_REFINEMENT

    structural = len(_STRUCTURAL_SIGNALS.findall(text))
    layout = len(_LAYOUT_SIGNALS.findall(text))
    local = len(_LOCAL_EDIT_SIGNALS.findall(text))
    style = len(_STYLE_SIGNALS.findall(text))

    # STRUCTURAL wins when present and not dominated by LAYOUT+LOCAL combined.
    if structural > 0 and structural >= max(layout, local):
        return EditMode.STRUCTURAL_TRANSFORMATION
    # LAYOUT wins over LOCAL whenever any layout signal is present
    # (ties between layout and local go to LAYOUT — rearrangement intent
    # is the stronger signal when both verbs co-occur).
    if layout > 0 and layout >= local:
        return EditMode.LAYOUT_CHANGE
    # LOCAL wins over STYLE only when strictly higher.
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
    Wave 5.13c — strict differential edit prompt for LOCAL_EDIT mode.

    Diagnosed problem (Wave 5.13b validation cycle 2026-05-31) : the
    previous LOCAL_EDIT prompt had strong but GENERIC preservation
    language ("preserve walls, furniture, lighting..."). Combined with
    the LATEST-as-source default (V3 generates from V2 AI image) and
    input_fidelity=high, the model was faithfully re-rendering the V2
    cascade-degraded image and amplifying its artifacts.

    Fix : framing-side reinforcement.
      1. Single-element substitution framing : the model is told this
         is a PIXEL-IDENTICAL pass, not a generation.
      2. Per-element negative enumeration : DO NOT regenerate sofa,
         DO NOT alter floor, DO NOT shift colour grading, etc.
      3. Output requirement reframed : "indistinguishable from the
         input photo except for the listed change".
    """
    changes = _split_changes(user_instruction)
    if changes:
        change_list = " ".join(
            f"({i + 1}) {c[0].upper() + c[1:]}." for i, c in enumerate(changes)
        )
    else:
        instruction = user_instruction.strip()
        change_list = (
            f"(1) {instruction[0].upper() + instruction[1:]}."
            if instruction
            else "(1) Apply the requested changes."
        )

    room_ctx = f" {room_type}" if room_type else ""
    description_ctx = (
        f" Existing space context: {room_description}" if room_description else ""
    )

    return (
        f"DIFFERENTIAL IMAGE EDIT — {room_ctx.strip() or 'room'} in {style_name} style.\n"
        f"This is a single-element substitution pass. The output image must be "
        f"PIXEL-IDENTICAL to the input image, EXCEPT for the listed change.\n"
        f"REQUESTED CHANGE: {change_list}\n"
        f"PRESERVE PIXEL-IDENTICAL — every element below must remain visually identical to the input image: "
        f"the camera angle, viewing height, and perspective; "
        f"all walls, windows, doors, and ceiling — exact positions, exact character; "
        f"all window openings — fully unblocked, natural light entering from every window must remain visible; "
        f"every piece of furniture not explicitly mentioned above — same form, same materials, same colour, same position; "
        f"all objects and decorative items not explicitly mentioned above; "
        f"the lighting direction, warmth, exposure, and shadow pattern; "
        f"the floor material, colour, and finish; "
        f"the overall spatial composition and room layout; "
        f"the colour grading and atmosphere tone.\n"
        f"DO NOT regenerate, re-render, or restyle any of the preserved elements. "
        f"DO NOT recreate textures or material surfaces. "
        f"DO NOT shift any furniture position. "
        f"DO NOT alter the colour grading, exposure, or atmosphere identity. "
        f"DO NOT redesign the room.\n"
        f"STYLE CONTEXT: any new element introduced by the change should match the {style_name} aesthetic.{description_ctx}\n"
        f"OUTPUT: indistinguishable from the input photo except for the listed change. "
        f"Surgical substitution, not regeneration."
    )


def build_layout_change_prompt(
    user_instruction: str,
    style_name: str,
    room_type: str,
    room_description: str,
) -> str:
    """
    Wave 5.13c — layout rearrangement prompt.

    LAYOUT_CHANGE sits between LOCAL_EDIT (no position change allowed)
    and STYLE_REFINEMENT (full DNA, redesign permitted). The user wants
    to MOVE existing furniture — not replace it, not restyle it. The
    prompt must :
      - Permit position / orientation changes for the named pieces.
      - Forbid material / colour / model substitution.
      - Forbid atmosphere drift (same warmth, same mood, same identity).
      - Preserve the room architecture (walls, windows, ceiling).
    The composer pairs this prompt with a PARTIAL DNA block (atmosphere
    identity + lighting only ; furniture_language and material_palette
    dropped to avoid the model rerendering pieces it should just move).
    """
    changes = _split_changes(user_instruction)
    if changes:
        change_list = " ".join(
            f"({i + 1}) {c[0].upper() + c[1:]}." for i, c in enumerate(changes)
        )
    else:
        instruction = user_instruction.strip()
        change_list = (
            f"(1) {instruction[0].upper() + instruction[1:]}."
            if instruction
            else "(1) Rearrange the furniture as requested."
        )

    room_ctx = f" {room_type}" if room_type else ""
    description_ctx = (
        f" Existing space context: {room_description}" if room_description else ""
    )

    return (
        f"LAYOUT REARRANGEMENT — {room_ctx.strip() or 'room'} in {style_name} style.\n"
        f"This is a furniture-position pass. Move and rotate the named pieces only ; "
        f"do NOT replace, regenerate, or restyle any furniture.\n"
        f"REQUESTED REARRANGEMENT: {change_list}\n"
        # Wave 5.13c Plan B+ (2026-05-31) — anti-duplication cue. Empirical
        # finding : gpt-image-1 interprets "move X" as additive ("produce
        # an X here") rather than relocational ("move the existing X
        # here"), producing two Xs in the output. Explicit relocation
        # framing forces the model to treat the request as a one-to-one
        # repositioning rather than a generative addition.
        f"CRITICAL: 'move X' means relocate the existing X from its current "
        f"position to the requested new position. Do NOT add or duplicate X. "
        f"The named object must appear exactly once in the final image, at "
        f"its new location.\n"
        f"PERMITTED CHANGES — positions and orientations only: "
        f"move the requested furniture pieces to the new positions; "
        f"adjust orientation/rotation for the new placement; "
        f"re-light shadows and ambient occlusion consistent with the new placement.\n"
        f"PRESERVE IDENTICAL — every other element remains unchanged: "
        f"the camera angle, viewing height, and perspective; "
        f"all walls, windows, doors, and ceiling — exact positions and character; "
        f"all window openings — fully unblocked, natural light visible; "
        f"EVERY furniture piece — same model, same materials, same colour, same finish — ONLY the position changes; "
        f"all objects and decorative items not explicitly moved; "
        f"the overall lighting direction, warmth, exposure, and atmosphere tone; "
        f"the floor material, colour, and finish; "
        f"the {style_name} atmosphere identity — same warmth, same mood, same character.\n"
        f"DO NOT redesign the room. "
        f"DO NOT replace furniture pieces with different models. "
        f"DO NOT change materials, colours, or finishes. "
        f"DO NOT shift the colour grading or atmosphere.{description_ctx}\n"
        f"OUTPUT: same room, same atmosphere, same furniture pieces — only their positions adjusted."
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
