"""
Architectural preservation rules — the structural contract.

DESIGN PRINCIPLE: Structure first, style second.

Wave 4.2.1 COMPRESSION: Three tiers instead of one monolithic block.

  Tier 1 — build_structural_contract(room_type)
    For FIRST_VISION redesigns. Full vocabulary, compressed prose. ~1550 chars.

  Tier 2 — build_structural_evolution_contract(room_type)
    For STRUCTURAL_TRANSFORMATION. Full camera lock + window mandate + compact
    atmosphere boundary. ~650 chars.

  Tier 3 — build_continuation_contract(room_type)
    For STYLE_REFINEMENT. Ultra-compact. ~530 chars.
    Includes focal length (required by Wave 4.1 checks) and a minimal
    atmosphere boundary note so "ATMOSPHERE BOUNDARY" appears in all prompts.

All tiers preserve the Wave 4.1 optical/geometric vocabulary (vanishing points,
focal length, horizon line) that was added specifically to suppress geometric drift.

NOTE: The string constants (_CAMERA_LOCK etc.) are imported directly by
validate_wave* suites for vocabulary checks. Preserve all required terms.
"""

# ── Tier 1: Full structural contract (FIRST_VISION) ───────────────────────────

_CAMERA_LOCK = (
    "CAMERA LOCK — FROZEN: camera position, height, viewing angle, perspective, "
    "focal length, vanishing points, and horizon line. "
    "Room proportions, spatial depth, and all structural lines are fixed. "
    "This space already exists physically — DO NOT reinterpret geometry, "
    "DO NOT redesign architecture, or shift perspective. "
    "Output must look like a photograph of the SAME apartment with new surfaces, "
    "preserving its architectural identity. "
    "Any geometry or perspective change is a failure."
)

_STRUCTURAL_LOCK = (
    "STRUCTURAL LOCK — FORBIDDEN: "
    "(1) Windows — positions, sizes, frames; must remain unblocked, natural light visible. "
    "(2) Doors, balcony access, and exterior thresholds — positions locked, visually accessible. "
    "(3) Walls — layout, thickness, angles fixed. "
    "(4) Floor plan footprint — fixed. "
    "(5) Ceiling height — locked. "
    "(6) Structural columns and beams unchanged. "
    "(7) Circulation paths unchanged."
)

_TRANSFORMATION_SCOPE = (
    "CHANGE ONLY: floor/wall/ceiling finishes; "
    "furniture forms, placement, upholstery, materials; "
    "lighting fixtures and character; "
    "textiles and soft furnishings; "
    "decorative objects; colour palette; atmospheric character."
)

_ATMOSPHERE_BOUNDARY = (
    "ATMOSPHERE BOUNDARY — PRIORITY ORDER: "
    "(1) Functional zone purposes and spatial relationships. "
    "(2) Windows and openings — unblocked, natural light visible. "
    "(3) Room topology, zone count, and depth. "
    "(4) Camera. "
    "(5) Atmosphere — applied last. "
    "If any atmospheric instruction conflicts with 1–4, THE CONSTRAINT WINS ABSOLUTELY. "
    "Atmosphere changes how the space looks, not its layout or zone count."
)

_ROOM_STRUCTURAL: dict[str, str] = {
    "living room": (
        "ROOM LOCK: preserve TV wall or fireplace position, "
        "sofa zone, all window orientations, open-floor-to-furnished ratio."
    ),
    "bedroom": (
        "ROOM LOCK: preserve bed wall alignment, window orientation, "
        "ceiling height perception, wardrobe and door positions."
    ),
    "kitchen": (
        "ROOM LOCK: preserve kitchen workflow triangle (sink, stove, fridge), "
        "all countertop runs, overhead cabinet height line, island footprint."
    ),
    "bathroom": (
        "ROOM LOCK: preserve sanitary ware layout exactly — "
        "basin, toilet, shower, bath. Tile plane orientation and window placement locked."
    ),
    "dining room": (
        "ROOM LOCK: preserve dining table axis, kitchen threshold proximity, "
        "chandelier centring."
    ),
    "home office": (
        "ROOM LOCK: preserve desk position relative to window, "
        "built-in storage wall, door position."
    ),
    "house facade": (
        "ROOM LOCK: preserve building outline, roof form, window positions, "
        "entrance axis, driveway geometry. Massing and footprint non-negotiable."
    ),
    "exterior": (
        "ROOM LOCK: preserve building outline, roof form, all window positions, "
        "entrance axis. Structural massing non-negotiable."
    ),
    "balcony": (
        "ROOM LOCK: preserve railing line, structural slab edge, door threshold. "
        "Do not extend floor area."
    ),
    "terrace": (
        "ROOM LOCK: preserve terrace perimeter, structural supports, columns, "
        "overhead cover or pergola structure."
    ),
}

# Compact camera lock for Tier 2 — preserves all required vocabulary
# (focal length, vanishing points, horizon line, SAME apartment) in ~198 chars.
# Wave 4.2.4: replaces full _CAMERA_LOCK in build_structural_evolution_contract()
# to reduce STRUCTURAL_TRANSFORMATION prompt size by ~266 chars.
_CAMERA_LOCK_COMPACT = (
    "CAMERA LOCK — FROZEN: camera position, focal length, vanishing points, horizon line. "
    "Room proportions and all structural lines are fixed. "
    "Output: photograph of the SAME apartment, new surfaces only."
)

# Compact atmosphere boundary — used in Tier 2 and Tier 3 so that
# "ATMOSPHERE BOUNDARY" is present in ALL generated prompts.
_COMPACT_ATMOSPHERE_BOUNDARY = (
    "ATMOSPHERE BOUNDARY — geometry and openings override atmosphere. "
    "Functional zone purposes are non-negotiable. "
    "Topology > camera > atmosphere."
)


def _room_note(room_type: str) -> str:
    rt = room_type.lower()
    for key, note in _ROOM_STRUCTURAL.items():
        if key in rt:
            return note
    return ""


def build_structural_contract(room_type: str) -> str:
    """
    Tier 1 — full structural contract for FIRST_VISION redesigns.
    All four constraint layers. ~1550 chars.
    """
    parts = [_CAMERA_LOCK, _STRUCTURAL_LOCK, _TRANSFORMATION_SCOPE]
    note = _room_note(room_type)
    if note:
        parts.append(note)
    parts.append(_ATMOSPHERE_BOUNDARY)
    return " ".join(parts)


def build_structural_evolution_contract(room_type: str) -> str:
    """
    Tier 2 — medium contract for STRUCTURAL_TRANSFORMATION.
    Compact camera lock + window mandate + compact atmosphere boundary. ~650 chars.
    Wave 4.2.4: uses _CAMERA_LOCK_COMPACT instead of full _CAMERA_LOCK (~266-char saving).
    """
    window_lock = (
        "STRUCTURAL CONSTRAINTS: windows must remain unblocked, natural light visible. "
        "Walls, footprint, and ceiling height are fixed unless the architectural intent "
        "above explicitly requires modifying them. All unchanged elements preserved exactly."
    )
    parts = [_CAMERA_LOCK_COMPACT, window_lock]
    note = _room_note(room_type)
    if note:
        parts.append(note)
    parts.append(_COMPACT_ATMOSPHERE_BOUNDARY)
    return " ".join(parts)


def build_continuation_contract(room_type: str) -> str:
    """
    Tier 3 — ultra-compact contract for STYLE_REFINEMENT. ~530 chars.
    Includes focal length (Wave 4.1 regression requirement) and a compact
    atmosphere boundary note so "ATMOSPHERE BOUNDARY" appears in all prompts.
    """
    base = (
        "GEOMETRY FROZEN: same camera, same focal length, same vanishing points, "
        "same room proportions. "
        "Walls, windows, doors, ceiling — locked. "
        "WINDOWS UNBLOCKED — natural light must remain visible. "
        "Only surfaces, materials, lighting, and atmosphere evolve. "
        "Geometry change = failure."
    )
    note = _room_note(room_type)
    core = f"{base} {note}".strip() if note else base
    return f"{core} {_COMPACT_ATMOSPHERE_BOUNDARY}"


def build_atmosphere_switch_contract(room_type: str, anchor_clause: str = "") -> str:
    """
    Tier 3.5 — strengthened preservation contract for STYLE_REFINEMENT.
    Wave 4.3.0: Preservation Intelligence.

    Replaces build_continuation_contract() on the atmosphere-switch path.
    Adds explicit topology lock, multi-zone protection, and named anchor
    preservation on top of the standard geometry freeze.

    anchor_clause: from detect_anchors().clause — empty string adds zero cost.

    Budget target:
      ~515 chars base (no room note, no anchor)
      ~780 chars with living-room note + compact boundary
      ~870 chars with living-room note + anchor clause + compact boundary
      Always within STYLE_REFINEMENT budget (2400 chars) when combined with
      header (~300), source (~100), DNA (~850), compact_realism (~133).
    """
    base = (
        "SAME APARTMENT — ATMOSPHERE SWITCH: apply this atmosphere to THIS exact apartment. "
        "DO NOT generate a new apartment in this style. "
        "FROZEN: camera, focal length, vanishing points, proportions, "
        "walls, windows, doors, ceiling — locked. "
        "TOPOLOGY LOCKED: zone count, spatial openness, multi-zone visibility, "
        "depth relationships — non-negotiable. "
        "Do not collapse multi-zone layouts. Do not flatten spatial depth. "
        "CHANGE ONLY: materials, surfaces, lighting, colours, textiles, styling. "
        "Simplification of topology or geometry = failure."
    )
    note = _room_note(room_type)
    parts = [base]
    if note:
        parts.append(note)
    if anchor_clause:
        parts.append(anchor_clause)
    parts.append(_COMPACT_ATMOSPHERE_BOUNDARY)
    return " ".join(parts)


# Legacy alias
def build_preservation_block(room_type: str) -> str:
    return build_structural_contract(room_type)


# ── Tier 1.5: Simplified FIRST_VISION contract (Wave 4.5.0) ──────────────────

_SAME_APARTMENT_V2 = (
    "CAMERA LOCK — FROZEN: camera position, focal length, vanishing points, horizon line. "
    "Room proportions, spatial depth, and all structural lines are fixed. "
    "Output must look like a photograph of the SAME apartment, preserving its architectural identity. "
    "DO NOT reinterpret geometry. DO NOT redesign architecture. "
    "STRUCTURAL LOCK — FORBIDDEN: windows (positions, frames, unblocked, natural light visible), "
    "doors, walls, ceiling height, floor plan, structural columns. "
    "CHANGE ONLY: surfaces, materials, furniture, lighting, textiles, colours, atmosphere. "
    "ATMOSPHERE BOUNDARY — geometry, openings, and topology override atmosphere. "
    "Atmosphere is applied last. Any perspective or geometry change is a failure."
)


def build_simplified_fv_contract(room_type: str) -> str:
    """
    Tier 1.5 — simplified FIRST_VISION contract (Wave 4.5.0). ~693 chars.

    Replaces Tier 1 (~1550 chars) in the FIRST_VISION path. Contains all required
    vocabulary (CAMERA LOCK, STRUCTURAL LOCK, focal length, vanishing points, horizon
    line, structural lines, proportions, architectural identity, DO NOT reinterpret,
    DO NOT redesign, SAME apartment, ATMOSPHERE BOUNDARY, applied last) in ~47% fewer
    characters. Redundant defensive prose removed; core constraints preserved.

    Rationale: input_fidelity=high + structural mask + SAME APARTMENT task framing
    do heavy architectural preservation work. The contract provides vocabulary
    alignment, not defensive repetition. Clearer = more trustworthy to the model.

    Wave 4.6.0: removed _room_note() (ROOM LOCK phrases). Those phrases assumed
    specific furniture positions not grounded in the uploaded photo ("preserve TV
    wall or fireplace position, sofa zone..."). Photo-first philosophy: the uploaded
    photo IS the truth — do not instruct based on furniture that may not exist.
    """
    return _SAME_APARTMENT_V2
