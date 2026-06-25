"""
Architectural preservation rules — the structural contract.

Wave 6.3 (2026-06-04) — Temporal Continuity Preservation Rule.
Adds a preserve-mode-only sentence to MODE_CONTRACT that locks the time-of-day
and lighting context of the source photo. Users who explicitly request a
temporal transformation (via user_instruction keywords) bypass the rule.
Creative mode and architecture-flexible paths are not affected.
See [[temporal-preservation-rule]] memory entry for the full design notes.


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


# Wave 5.5.14d — Creative-mode contract.
#
# Used only when BIMODAL_ENABLED=1 AND generation_mode=="creative" (Surprise Me
# / "Create" UI path). Trades strict architectural preservation for the
# atmosphere's full architectural latitude — Bali can open the wall, Tropical
# can dissolve the boundary, Japandi can reproportion negative space.
#
# Critical NOT random-room safeguards (the user's "SANS devenir random
# unrelated room" caveat):
#   • Camera vantage explicitly PREFERRED (not forced) → the model stays
#     anchored on the same viewpoint even when reinterpreting structure.
#   • SAME SPACE language retained → identity grounding.
#   • Spatial recognizability retained as a goal → "this is MY room, reimagined".
#
# What is DROPPED vs Preserve mode:
#   • "FROZEN" hard-lock language → softened to "preferred".
#   • STRUCTURAL LOCK forbidden list → removed entirely.
#   • CHANGE ONLY restriction → removed entirely.
#   • "ATMOSPHERE BOUNDARY — geometry overrides atmosphere" → removed.
#
# Rollback: any `BIMODAL_ENABLED=0` request falls back to _SAME_APARTMENT_V2
# automatically (creative branch never fires unless flag is on).
_SAME_APARTMENT_CREATIVE = (
    "SAME SPACE REIMAGINED — apply the chosen atmosphere as a full "
    "architectural concept on THIS space. The photographed room is the "
    "starting point; openings, ceiling treatments, partition language, "
    "and material structure may evolve to express the atmosphere fully. "
    "CAMERA VANTAGE — keep the same viewpoint and approximate focal "
    "feel so the result reads as a transformation OF this space, not a "
    "different room. SPATIAL RECOGNIZABILITY — multi-zone presence and "
    "the dominant opening's relationship to the room should remain "
    "legible even when their exact form is reinterpreted."
)


def build_simplified_fv_contract(
    room_type: str,
    generation_mode: str = "preserve",
) -> str:
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

    Wave 5.5.14d — Creative-mode variant: when BIMODAL_ENABLED=1 AND
    generation_mode=="creative", returns _SAME_APARTMENT_CREATIVE (soft
    vantage + drop of STRUCTURAL LOCK / CHANGE ONLY / ATMOSPHERE BOUNDARY).
    The default path (and every Preserve-mode request) returns the original
    _SAME_APARTMENT_V2 string → byte-identical to pre-5.5.14d.
    """
    from .atmosphere_dna.bimodal_classifier import is_creative_mode_active
    if is_creative_mode_active(generation_mode):
        return _SAME_APARTMENT_CREATIVE
    return _SAME_APARTMENT_V2


# ── Wave 5.13f — single MODE_CONTRACT (FIRST_VISION) ─────────────────────────
#
# Replaces 6 overlapping structural sections (task + full_contract +
# openings_anchor + structural_negative_anchors + wow_directive +
# natural_enrichment) with ONE authoritative contract selected by mode.
#
# Preserve: architecture locked, change only surfaces/furniture/light/decor.
# Creative: architecture flexible, keep result believable + photorealistic.
# V1 ships preserve only (creative dormant — gated by frontend, but contract
# is present in the architecture for V2).

import os as _os

# PHASE 1.1 (post-build, 2026-06-13) — PROMPT_FURNITURE_FIX.
# The old closing line listed "furniture" among the things to *redesign
# through*, while every atmosphere DNA says "on the existing sofa / existing
# low table…". Two opposite signals on furniture (replace vs keep) → diffusion
# uncertainty. The fix makes the contract agree with the DNA: restyle the
# EXISTING furniture (same pieces, same footprint); decor/textiles stay free to
# enrich (richness preserved — cushions/throws/rug/plant/art are decor, not
# furniture). Flagged for A/B; PROMPT_FURNITURE_FIX=0 restores the old wording.
# Rollback = set the env var to 0 (or delete this clause).
_FURNITURE_CLAUSE = (
    "Restyle only through materials, lighting, decor, textiles, colours, and "
    "atmosphere — on the existing furniture (same pieces, same footprint)."
    if _os.environ.get("PROMPT_FURNITURE_FIX", "1") != "0"
    else "Redesign only through materials, "
    "furniture, lighting, decor, textiles, colours, and atmosphere styling."
)

_PRESERVE_MODE_CONTRACT = (
    "PRESERVE MODE — SAME APARTMENT CONTRACT:\n"
    "Preserve the exact photographed architecture and the full proportions "
    "of every photographed opening — windows, glass facades, sliding doors, "
    "glazed partitions — none may be narrowed, compressed, shortened, blocked, "
    "replaced by a wall surface, or covered by material treatments. "
    "Walls, doors, ceiling height, floor boundaries, circulation, spatial "
    "depth, camera angle, and perspective stay exact. "
    "Do not add, remove, resize, relocate, reinterpret, or redesign "
    "architectural elements. Material finishes wrap around existing openings, "
    "they never substitute for them. " + _FURNITURE_CLAUSE
)

# PHASE 1.2 (post-build, 2026-06-13) — PROMPT_CONTRACT_LIGHT.
# SINGLE SOURCE OF TRUTH for which V1 atmospheres ship fidelity=high. main.py
# imports THIS tuple for its FIRST_VISION fidelity decision, so the "is the
# image pixel-anchored?" question can NEVER desync from the contract choice.
# Why it's safety-critical: the light contract below drops the verbose opening
# lock — that is only safe when the architecture is pixel-anchored (high
# fidelity) AND already listed in structural_identity. Using it on a
# low-fidelity path (Tropical, switches) would remove the only guard.
HIGH_FIDELITY_ATMOSPHERES = (
    "soft_luxury", "japandi_calm", "nordic_warmth", "warm_modern",
    # Tropical promoted 2026-06-13 (user-validated walls=0 at high) — now in the
    # shared list so it gets fidelity=high (via main.py's `if` branch) AND the
    # light contract + trust-pixels, exactly like the others. Supersedes the
    # separate TROPICAL_V1_HIGH else-branch flag (now redundant for Tropical).
    "tropical_escape",
)

# Compact contract: at fidelity=high the 4-sentence opening lock of
# _PRESERVE_MODE_CONTRACT is redundant (pixels + structural_identity already
# anchor the architecture) → collapse to ONE anchor sentence. Keeps the
# furniture clause (PHASE 1.1); TEMPORAL is appended like the full contract.
_PRESERVE_MODE_CONTRACT_LIGHT = (
    "PRESERVE MODE — SAME APARTMENT CONTRACT:\n"
    "Reproduce the photographed architecture exactly — every wall, opening, "
    "door, window, the ceiling, proportions, circulation, camera angle and "
    "perspective stay exactly as photographed. Add nothing, remove nothing, "
    "fill nothing in: do not invent walls, doors or partitions, and never turn "
    "an existing opening into a wall. Highest priority: preserve the structure "
    "before any styling. " + _FURNITURE_CLAUSE
)

# ── Ayden Decide STAGE MODE (flag AYDEN_DECIDE_FURNISH_EMPTY, default off) ────
# An empty / unfurnished interior delegated to Ayden Decide is ambiguous under
# the preserve contract ("Add nothing, fill nothing in … on the existing
# furniture") → gpt-image-1 sometimes leaves the room bare, sometimes furnishes
# it (run-to-run coin flip). STAGE MODE keeps the architecture lock VERBATIM but
# swaps the furniture-preservation clause for a furnishing instruction, so empty
# rooms are reliably staged. Architecture preservation is unchanged → the walls=0
# guard is intact. Applied post-composition by apply_stage_mode(); fully
# reversible (flag off ⇒ never called ⇒ byte-identical).
# Room-appropriate staging pieces. An entrance/hallway must NOT receive a sofa
# or living-room set — it gets entry pieces (console, mirror, bench, hooks).
_STAGE_ITEMS = {
    "entrance": "a console table or slim cabinet, a mirror, a bench or stool, "
    "coat hooks or a coat rack, a runner rug, a small tray or catch-all, and a "
    "plant or framed art — NO sofa or living-room seating",
    "hallway": "a console table or slim cabinet, a mirror, coat hooks, a runner "
    "rug, framed wall art and a plant — NO sofa or living-room seating",
    "living_room": "a sofa and armchairs, a coffee table, a low media console / "
    "TV unit with a flat-screen TV on it placed against a wall facing the "
    "seating, side tables, layered lighting, a rug, cushions and throws, art and "
    "greenery; and if the room is large or open-plan, also stage a dining area "
    "with a dining table and chairs (and a pendant above it)",
    "bedroom": "a bed dressed with linens, two nightstands with lamps, a wardrobe "
    "or dresser, a bench or reading chair, a rug and art",
    "dining_room": "a dining table with chairs, a statement pendant over the "
    "table, a sideboard or buffet, a rug and art",
    "kitchen": "counter or bar stools, pendant lighting, styled open shelving, "
    "plants and considered countertop styling (keep the fitted kitchen layout)",
    "office": "a desk and chair, shelving or a bookcase, a task lamp, a rug and art",
    "bathroom": "styled towels, a vanity stool or ladder, a mirror, plants and "
    "considered decor (keep the fitted sanitary layout)",
}
_STAGE_ITEMS_DEFAULT = (
    "the seating, tables, storage, lighting, rugs, textiles, greenery, art and "
    "decor that a real, finished room of this kind would have"
)

# Window treatment per room — curtains read odd in wet/utility rooms, so kitchen
# and bathroom get blinds/shades instead. All "open" so the glass stays visible
# (keeps the architecture-lock happy).
_WINDOW_TREATMENT = {
    "kitchen": "a neat roller or Roman blind, raised and open at the top",
    "bathroom": "a neat roller or Roman blind, raised and open at the top",
}
_WINDOW_TREATMENT_DEFAULT = (
    "curtains or drapes hung at the sides and drawn fully open"
)

# Per-atmosphere FURNITURE LANGUAGE — the materials/forms every staged piece must
# take, so an atmosphere reads unmistakably (a Japandi living ≠ a Soft Luxury
# living, not the same sofa in a different tint). This is what restores identity.
_ATMO_FURNITURE_STYLE = {
    "warm_modern": "rich American walnut and warm-toned oak, a caramel / ochre / "
    "terracotta and warm-white palette, natural-linen and tan-leather upholstery, "
    "travertine and warm stone, brass accents — deep, cosy, contrasted "
    "residential warmth; deliberately NOT pale, cool or Scandinavian",
    "japandi_calm": "distinctly JAPANDI (Japanese × Scandinavian), NOT plain "
    "Nordic: VERY LOW, floor-hugging forms (a low platform sofa, a low oak table "
    "— keep everything low and grounded); light oak mixed with SPARING CHARCOAL / "
    "black contrast accents (black-framed screens, black metal, dark wabi-sabi "
    "ceramics) — this black contrast is what separates it from Nordic; natural "
    "linen in warm greige, a jute rug, muted sage-green, ikebana-style sculptural "
    "bare branches, handcrafted imperfect (wabi-sabi) pottery, paper-lantern / "
    "rice-paper lighting, sheer linen; soft natural light; deeply MINIMAL, zen and "
    "uncluttered with intentional, generous negative space",
    "soft_luxury": "velvet and bouclé upholstery, honed-marble tops, polished "
    "brass legs and accents, deep plush rugs, sculptural lighting — refined, "
    "tactile, quietly opulent",
    "nordic_warmth": "pale birch / ash wood, wool, sheepskin and chunky-knit "
    "textiles, soft muted tones, simple clean forms — cosy, light, hygge",
    "tropical_escape": "rattan, cane and teak, woven natural fibres, linen, "
    "abundant lush greenery, breezy organic forms — resort-like",
}


def build_stage_contract(room_label: str = "", atmosphere_label: str = "",
                         atmosphere_id: str = "") -> str:
    room_key = (room_label or "").strip().lower()
    room = room_key.replace("_", " ") or "room"
    atmo = (atmosphere_label or "").split("·")[0].strip()
    atmo_phrase = f" in the {atmo} style" if atmo else ""
    items = _STAGE_ITEMS.get(room_key, _STAGE_ITEMS_DEFAULT)
    # Soft Luxury living-room ONLY — STAGE-scoped polish (preserve/switch/V2+ are
    # byte-identical: build_stage_contract runs ONLY on the STAGE V1 path via
    # apply_stage_mode, and the guard below restricts to SL + living_room).
    #   (1) Silhouette: the generic "a sofa and armchairs" + SL's material-only DNA
    #       (no sofa form) read too close to Warm Modern (both living DNAs use
    #       bouclé, WM's is even "curved"). Inject the SL silhouette — SHAPE ONLY,
    #       materials already in the DNA → no duplication.
    #   (2) Pendant + warmth nudge (validated 2026-06-23): the SL DNA LIGHT calls
    #       for no ceiling fixture and a pale ivory/cream palette → the V1 STAGE
    #       render reads flat/cold. Add a luxury pendant (DNA forbids crystal →
    #       alabaster/brass) + a warm-tone nudge. STAGE-only by design: kept out of
    #       the DNA so the validated switch SL (V4) and its budget stay untouched.
    _sl_stage_extra = ""
    if (atmosphere_id or "").strip().lower() == "soft_luxury" and room_key == "living_room":
        items = items.replace(
            "a sofa and armchairs",
            "a deep, curved, channel-tufted sofa with rounded plush volumes "
            "and curved armchairs",
            1,
        )
        _sl_stage_extra = (
            "Include a LARGE sculptural statement chandelier as the ceiling "
            "centrepiece over the main seating — oversized and multi-tier in "
            "alabaster, opaline glass or sculptural brass, a true 5-star-hotel-"
            "grade focal fixture (refined and elegant, never a sparkly crystal "
            "cliché). Lean the palette warm and layered — deeper champagne, taupe "
            "and greige over pure ivory; avoid stark cool white. Render with a "
            "warm, golden white balance and a soft warm lamplight glow layered "
            "into the existing daylight — inviting and warm, never a cool or "
            "blue-white daylight cast (keep the time-of-day unchanged). "
            # Wave (2026-06-24) — authoritative seating tonal hierarchy (STAGE-only).
            # The shared DNA taupe tokens proved too optional → V1 still rendered an
            # all-cream seating package. This MANDATORY directive lives in the STAGE
            # contract (NOT the DNA), so switch/preserve prompt sizes + the TV anchor
            # (dna_room_context) stay byte-identical — STAGE runs only via apply_stage_mode.
            "CRITICAL seating tonal hierarchy — the seating package MUST NOT be "
            "entirely cream or ivory: the sofa MUST be the dominant warm-taupe "
            "anchor, a clearly visible mid-tone noticeably deeper than the pale "
            "walls, marble and rug; the armchairs are a secondary warm-champagne "
            "anchor; cushions and throw stay lighter as layered accents that "
            "contrast with — never erase — the sofa's deeper taupe. At least the "
            "sofa MUST read as a warm taupe mid-tone, never pale ivory. "
        )
    treatment = _WINDOW_TREATMENT.get(room_key, _WINDOW_TREATMENT_DEFAULT)
    atmo_style = _ATMO_FURNITURE_STYLE.get((atmosphere_id or "").strip().lower(), "")
    atmo_furniture_clause = (
        f"Every single piece is designed in the {atmo} furniture language — "
        f"{atmo_style}. " if atmo_style else ""
    )
    # Ceiling-architecture protection (SL living STAGE only — A/B isolation 2026-06-25).
    # SL is the sole atmosphere with a mandatory oversized chandelier; this clarifies
    # that "lighting design" = the FIXTURE, not the ceiling structure. Conditional so
    # Warm Modern / Japandi / Nordic / Tropical keep the original shared closing
    # byte-identical. Deliberately does NOT touch the shared "You MAY add CEILING and
    # LIGHTING design" line above — single-variable A/B by design.
    _sl_living_close = (
        (atmosphere_id or "").strip().lower() == "soft_luxury"
        and room_key == "living_room"
    )
    # Lever #1 (SL living STAGE only — 2026-06-25): the shared permission invited
    # "recessed cove lighting + CEILING design", contradicting the SL ceiling-fixed
    # closing → mixed signal (2/4 still reconstructed). For SL only, keep the
    # chandelier + lamps + warm light but forbid ceiling-structure changes. Other
    # atmospheres keep the original permission byte-identical (else branch).
    ceiling_perm = (
        "You MAY, however, add atmosphere-appropriate LIGHTING — a hanging "
        "statement chandelier and freestanding floor/table lamps — plus freestanding "
        "furniture and decor placed on the existing floor; do not add or alter any "
        "ceiling structure, recesses, coves, trays, coffers or dropped ceilings. "
        if _sl_living_close else
        "You MAY, however, add atmosphere-appropriate CEILING and LIGHTING design "
        "— recessed and indirect cove lighting, statement pendants, sculptural and "
        "modern fixtures, layered ambient glow — plus freestanding furniture and "
        "decor placed on the existing floor. "
    )
    closing = (
        "Furniture and decor are yours to compose. Existing ceiling architecture "
        "must remain unchanged. Only replace the light fixture. The chandelier must "
        "be integrated into the existing ceiling without creating or modifying "
        "ceiling recesses, coffers, domes, moldings or any architectural ceiling "
        "elements."
        if _sl_living_close else
        "Furniture, lighting and decor are yours to compose; the structural shell "
        "is not."
    )
    return (
        "STAGE MODE — FURNISH EMPTY SPACE CONTRACT:\n"
        "CRITICAL — the structural shell is FIXED and must be reproduced "
        "pixel-for-pixel: every wall, doorway, opening, passage, archway, window, "
        "glass/sliding door, the ceiling shape and height, columns, niches, "
        "proportions, circulation, camera angle and perspective stay EXACTLY as "
        "photographed. Never close, fill in, wall up, narrow, shorten, cover or add "
        "any opening, doorway, passage or wall; never turn an existing opening or "
        "passage into a solid wall. "
        + ceiling_perm +
        "Any existing FITTED elements are part of the room and MUST be kept in "
        "place — an open / American kitchen (units, island, worktops, appliances), "
        "fitted wardrobes, built-in shelving or storage: keep them exactly where "
        "they are and restyle them to match the atmosphere; never remove, shrink, "
        "relocate or wall them off. "
        f"Furnish and stage this as a complete, fully resolved, "
        f"lived-in {room}{atmo_phrase}: add {items}, arranged in the density that "
        "suits the atmosphere — richly layered for warm or opulent styles, "
        "restrained and airy with generous empty space for minimal styles — within "
        "the existing floor area, keeping circulation clear. "
        + atmo_furniture_clause + _sl_stage_extra +
        f"At EVERY window and glass door, add {treatment} — leaving the glass "
        "fully visible and the opening clear; never cover, block, tint or narrow "
        "it (the view stays visible). "
        f"CRITICAL identity — the furniture, materials, palette, textiles AND the "
        f"ceiling/lighting design MUST express the {atmo or 'chosen'} atmosphere "
        "(see STYLE below), so the room reads unmistakably as that atmosphere — "
        "never a generic interior. "
        + closing
    )


def apply_stage_mode(prompt: str, room_label: str = "",
                     atmosphere_label: str = "",
                     atmosphere_id: str = "") -> tuple[str, bool]:
    """Swap whichever preserve contract is present for the STAGE (furnish)
    contract. Returns (new_prompt, applied). No-op (applied=False) if no preserve
    contract is found (creative mode / unexpected prompt) — safe by construction."""
    stage = build_stage_contract(room_label, atmosphere_label, atmosphere_id)
    for _contract in (_PRESERVE_MODE_CONTRACT_LIGHT, _PRESERVE_MODE_CONTRACT):
        if _contract in prompt:
            return prompt.replace(_contract, stage), True
    return prompt, False


_CREATIVE_MODE_CONTRACT = (
    "CREATIVE MODE — ARCHITECTURAL REDESIGN CONTRACT:\n"
    "You may reinterpret the architecture, including walls, openings, "
    "windows, layout, and spatial organization. Keep the result believable, "
    "structurally plausible, photorealistic, and coherent with the original "
    "camera perspective."
)


# Wave 6.3 — Temporal Continuity Preservation Rule (preserve-mode only).
# User-locked wording, do not paraphrase. Appended to _PRESERVE_MODE_CONTRACT
# at runtime unless the user explicitly requests a temporal transformation.
_TEMPORAL_CONTINUITY = (
    "TEMPORAL CONTINUITY — Preserve the time-of-day and lighting context "
    "visible in the source photo. Daylight scenes remain daylight, evening "
    "scenes remain evening, and night scenes remain night. Do not transform "
    "the photographed moment unless the user explicitly requests a different "
    "lighting or time-of-day ambience."
)

# Wave 6.3 — keywords that release the temporal lock. Detected on
# user_instruction case-insensitively, word boundaries (so "morningstar"
# does not trigger). User-locked list ; expansion requires its own wave.
import re as _re
_TEMPORAL_OVERRIDE_RE = _re.compile(
    r"\b("
    r"evening|night(?:time)?|sunset|sunrise|morning|daylight|"
    r"golden\s+hour|cinematic|moody\s+lighting"
    r")\b",
    _re.IGNORECASE,
)


def _temporal_override_requested(user_instruction: str) -> bool:
    """Return True iff user_instruction contains a temporal-transformation
    keyword. Used to suppress the TEMPORAL CONTINUITY sentence on requests
    like 'make it evening' or 'cinematic night ambience'."""
    return bool(_TEMPORAL_OVERRIDE_RE.search(user_instruction or ""))


def build_mode_contract(
    generation_mode: str = "preserve",
    user_instruction: str = "",
    pixel_anchored: bool = False,
) -> str:
    """
    Wave 5.13f — single authoritative MODE_CONTRACT for FIRST_VISION.

    Returns the preserve contract by default. Returns the creative contract
    only when BIMODAL_ENABLED=1 AND generation_mode == "creative". Frontend
    V1 exposes preserve only; the creative branch is dormant infrastructure
    prepared for V2.

    Wave 6.3 (2026-06-04) — preserve mode now appends a TEMPORAL CONTINUITY
    sentence that locks the photographed time-of-day. The sentence is
    suppressed when `user_instruction` contains a temporal-transformation
    keyword (see _TEMPORAL_OVERRIDE_RE) so explicit user intent ("make it
    evening", "cinematic night") wins over the default preservation guard.
    Creative mode is unaffected.
    """
    from .atmosphere_dna.bimodal_classifier import is_creative_mode_active
    if is_creative_mode_active(generation_mode):
        return _CREATIVE_MODE_CONTRACT
    # PHASE 1.2 — use the compact contract ONLY when the caller says the image
    # is pixel-anchored (V1 high-fidelity atmospheres; the caller passes the
    # shared HIGH_FIDELITY_ATMOSPHERES membership). Flag PROMPT_CONTRACT_LIGHT=0
    # forces the full contract everywhere (A/B + rollback).
    _use_light = (
        pixel_anchored
        and _os.environ.get("PROMPT_CONTRACT_LIGHT", "1") != "0"
    )
    _base = _PRESERVE_MODE_CONTRACT_LIGHT if _use_light else _PRESERVE_MODE_CONTRACT
    if _temporal_override_requested(user_instruction):
        # User explicitly asked for a temporal transformation : MODE_CONTRACT
        # stays minimal (architecture preservation only), the model is free
        # to follow the user's lighting/time-of-day intent.
        return _base
    # Default preserve mode : append the temporal continuity guardrail.
    return _base + "\n" + _TEMPORAL_CONTINUITY
