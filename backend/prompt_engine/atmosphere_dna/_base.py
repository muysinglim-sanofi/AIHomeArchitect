"""
Atmosphere DNA — two-tier architectural intelligence layer.

TIER 1 — AtmosphereCoreDNA (one per atmosphere):
  Shared identity: philosophy, emotional intent, material palette, luxury level.
  Defines what makes this atmosphere distinct. Never repeated in room adaptations.

TIER 2 — RoomAdaptationDNA (13 per atmosphere, 130 total):
  Room-specific behaviour only. Inherits atmosphere identity from core.
  Contains: furniture, materials, lighting, decor, realism constraints,
  visible transition logic, and room+atmosphere-specific negative rules.

build_dna_block() combines both tiers into a ~850–1000-char prompt block.
build_secondary_space_block() renders a ~120-char visible-space line.

Prompt budget:
  Primary room block:  ~850–1000 chars  (replaces old style_block + room_context ~570 chars)
  Per secondary room:  ~120 chars       (2 secondaries max = ~240 chars)
  Total DNA cost:      ~1100–1300 chars (within 3800-char overall limit — realism layer truncates)
"""

from __future__ import annotations
from dataclasses import dataclass
from typing import Optional


# ── Data types ────────────────────────────────────────────────────────────────

@dataclass
class AtmosphereCoreDNA:
    """Shared identity layer for one atmosphere. One instance per atmosphere."""
    atmosphere_id: str
    philosophy: str              # 1 sentence: what this atmosphere fundamentally IS
    emotional_intent: str        # 3-4 comma-separated feeling words
    architectural_language: str  # 1 sentence: spatial + formal character
    material_palette: list[str]  # 4-5 signature materials shared across all rooms
    lighting_behavior: str       # 1 sentence: universal lighting character
    luxury_level: str            # benchmark reference (e.g. "boutique hotel / premium urban")
    forbidden_elements: list[str]  # 4-5 atmosphere-wide avoidances (AI failure modes)
    atmosphere_keywords: list[str] # 4-5 identity keywords


@dataclass
class RoomAdaptationDNA:
    """
    Room-specific adaptation layer. Inherits atmosphere identity from AtmosphereCoreDNA.
    Contains ONLY room-specific content — never re-explains atmosphere philosophy.
    """
    atmosphere_id: str
    room_type: str                         # canonical key e.g. "living_room"
    furniture_language: list[str]          # 3-4 key pieces/elements for this room
    material_palette: list[str]            # 3 room-specific material notes
    lighting_behavior: str                 # room-specific lighting (1 sentence)
    decor_language: list[str]              # 2-3 signature room details
    realism_constraints: list[str]         # 2-3 physical plausibility rules
    room_specific_constraints: list[str]   # 2 design rules for this room type
    visible_transition_logic: str          # how materials/tone continue into adjacent spaces
    negative_rules: list[str]              # 3-4 room+atmosphere-specific failures to avoid


# Backwards-compatible alias (code that imports RoomAtmosphereDNA still works)
RoomAtmosphereDNA = RoomAdaptationDNA


# ── Registries ────────────────────────────────────────────────────────────────

_CORE_REGISTRY: dict[str, AtmosphereCoreDNA] = {}
_ADAPTATION_REGISTRY: dict[str, dict[str, RoomAdaptationDNA]] = {}


def register_core(core: AtmosphereCoreDNA) -> None:
    _CORE_REGISTRY[core.atmosphere_id] = core


def register(dna: RoomAdaptationDNA) -> None:
    _ADAPTATION_REGISTRY.setdefault(dna.atmosphere_id, {})[dna.room_type] = dna


def get_core(atmosphere_id: str) -> Optional[AtmosphereCoreDNA]:
    return _CORE_REGISTRY.get(atmosphere_id)


# ── Room normalisation ────────────────────────────────────────────────────────

_ROOM_ALIASES: dict[str, str] = {
    "living": "living_room",
    "living room": "living_room",
    "lounge": "living_room",
    "sitting room": "living_room",
    "reception": "living_room",
    "bedroom": "master_bedroom",
    "master bedroom": "master_bedroom",
    "master_bedroom": "master_bedroom",
    "bed": "master_bedroom",
    "kitchen": "kitchen",
    "bathroom": "bathroom",
    "bath": "bathroom",
    "toilet": "bathroom",
    "shower room": "bathroom",
    "ensuite": "bathroom",
    "home office": "home_office",
    "office": "home_office",
    "study": "home_office",
    "workspace": "home_office",
    "dining": "dining_room",
    "dining room": "dining_room",
    "dining_room": "dining_room",
    "entrance": "entrance_hall",
    "entrance hall": "entrance_hall",
    "hallway": "entrance_hall",
    "foyer": "entrance_hall",
    "hall": "entrance_hall",
    "corridor": "entrance_hall",
    "facade": "facade",
    "house facade": "facade",
    "exterior": "facade",
    "front": "facade",
    "garden": "garden",
    "yard": "garden",
    "lawn": "garden",
    "backyard": "garden",
    "pool": "pool_area",
    "pool area": "pool_area",
    "swimming pool": "pool_area",
    "terrace": "terrace",
    "patio": "terrace",
    "courtyard": "terrace",
    "balcony": "balcony",
    "driveway": "driveway",
    "drive": "driveway",
    "entrance drive": "driveway",
}


def _normalise_room(room_type: str) -> str:
    key = room_type.lower().strip().replace("-", "_")
    if key in _ROOM_ALIASES:
        return _ROOM_ALIASES[key]
    for word in key.replace("_", " ").split():
        for alias_key, canonical_key in _ROOM_ALIASES.items():
            if word in alias_key:
                return canonical_key
    return key


def get_room_dna(atmosphere_id: str, room_type: str) -> Optional[RoomAdaptationDNA]:
    """Return room adaptation DNA, or None if not registered."""
    norm = _normalise_room(room_type)
    return _ADAPTATION_REGISTRY.get(atmosphere_id, {}).get(norm)


def _norm_id(s: str) -> str:
    """Lowercase, '·'/'-'/whitespace → single underscores."""
    return "_".join(s.lower().replace("·", " ").replace("-", " ").split())


def label_to_atmosphere_id(style_label: str) -> str:
    """
    Resolve a display label to a registered atmosphere id.

    Wave 4.8.1b — correctness fix. The old logic only kept the part before
    '·', so 'Japandi · Calm' → 'japandi' while the DNA is registered as
    'japandi_calm' → silent registry miss → leaner non-DNA path.

    Deterministic, registry-aware, ZERO regression (every label that resolved
    correctly before resolves byte-identically — it hits the same 'base' tier):

      1. full label normalized, '·'→' '  ('Japandi · Calm' → 'japandi_calm')
         → if it is a registered atmosphere id, use it.            [FIX]
      2. else part-before-'·' normalized ('Soft Luxury · Gold' →
         'soft_luxury') → if registered, use it.                   [legacy hits]
      3. else the unique registered id whose first token equals the base
         (bare 'Japandi' → 'japandi_calm') — only when exactly one.  [safety]
      4. else the legacy normalized base (unknown labels: unchanged → non-DNA).

    Examples:
      'Japandi · Calm'        → japandi_calm   (was: japandi  — FIXED)
      'Soft Luxury · Gold'    → soft_luxury    (unchanged)
      'Warm Modern · Oat'     → warm_modern    (unchanged)
      'Zen Retreat · Serenity'→ zen_retreat    (unchanged)
      'Warm Modern · Vision 2'→ warm_modern    (unchanged)
      'soft_luxury'           → soft_luxury    (unchanged)
      'japandi_calm'          → japandi_calm   (unchanged)
    """
    raw = (style_label or "").strip()
    full = _norm_id(raw)
    base = _norm_id(raw.split("·")[0])
    ids = _CORE_REGISTRY  # keys = registered atmosphere ids (populated at import)

    if full in ids:
        return full
    if base in ids:
        return base
    prefix_matches = [
        k for k in ids
        if k == base or k.startswith(base + "_") or k.split("_")[0] == base
    ]
    if len(prefix_matches) == 1:
        return prefix_matches[0]
    return base  # legacy fallback — unknown labels behave exactly as before


# ── Prompt rendering ──────────────────────────────────────────────────────────

def build_dna_block(dna: RoomAdaptationDNA) -> str:
    """
    Combine atmosphere core + room adaptation into a ~500-char prompt block.

    Two-line format:
      ATMOSPHERE ({name}): {philosophy} — {emotional_intent}. [{luxury_level}]
      ROOM ({room}): {materials}. LIGHT: {lighting}. STYLE: {furniture+decor}.
                     REALISM: {constraints}. AVOID: {room_rules + core_forbidden}.
    """
    core = get_core(dna.atmosphere_id)
    atm_name = dna.atmosphere_id.replace("_", " ").title()
    room_name = dna.room_type.replace("_", " ").title()

    mat = ", ".join(dna.material_palette[:3])
    style_items = (dna.furniture_language[:3] + dna.decor_language[:2])
    style = "; ".join(style_items)
    real = "; ".join(dna.realism_constraints[:2])
    room_avoid = dna.negative_rules[:3]

    if core:
        core_forbidden = [x for x in core.forbidden_elements[:2] if x not in room_avoid]
        avoid = ", ".join(room_avoid + core_forbidden)
        atm_line = (
            f"ATMOSPHERE ({atm_name}): {core.philosophy} — {core.emotional_intent}. "
            f"[{core.luxury_level}]"
        )
    else:
        avoid = ", ".join(room_avoid)
        atm_line = f"ATMOSPHERE ({atm_name}): {atm_name} design intelligence."

    room_line = (
        f"ROOM ({room_name}): {mat}. "
        f"LIGHT: {dna.lighting_behavior} "
        f"ATMOSPHERE STYLE (restyle existing elements): {style}. "
        f"REALISM: {real}. "
        f"AVOID: {avoid}."
    )
    return atm_line + "\n" + room_line


def build_secondary_space_block(dna: RoomAdaptationDNA) -> str:
    """
    ~90-char compact secondary visible space line.
    Uses visible_transition_logic for atmospheric continuity.
    """
    room_name = dna.room_type.replace("_", " ").upper()
    mat_hint = ", ".join(dna.material_palette[:2])
    return f"VISIBLE {room_name}: {mat_hint}; {dna.visible_transition_logic}."


# ── Wave 5.5.18 — Dormant DNA fields revival ─────────────────────────────────
#
# `room_specific_constraints` and `visible_transition_logic` are defined in
# all 130 RoomAdaptationDNA entries but were NEVER emitted by build_dna_block.
# They contain concrete room semantics (TV, fireplace, kitchen continuity,
# conversation seating, etc.) that the model needs to populate rooms beyond
# the abstract material vocabulary of furniture_language (which Wave 4.6.0
# stripped of named pieces).
#
# This function ONLY emits existing DNA content — no new wording added.
# Returns "" when both fields are absent (e.g. unmapped atmosphere/room).
#
# Audit reference: docs/WAVE_5_5_17a_DNA_RESTORATION_AUDIT.md sections 2.2 + 4.

def build_dna_room_context(dna: RoomAdaptationDNA) -> str:
    """Emit previously-dormant DNA fields: room_specific_constraints +
    visible_transition_logic. Pure data emission — no new wording."""
    parts: list[str] = []
    if dna.room_specific_constraints:
        ctx = "; ".join(dna.room_specific_constraints[:2])
        parts.append(f"ROOM CONTEXT: {ctx}.")
    if dna.visible_transition_logic:
        parts.append(f"VISIBLE CONTINUITY: {dna.visible_transition_logic}.")
    return " ".join(parts)


def build_dna_room_context_signal(
    dna: Optional[RoomAdaptationDNA],
    generation_mode: str = "preserve",
) -> str:
    """Wave 5.5.18 bimodal-gated wrapper.

    Returns the dormant-fields context block only when:
      - BIMODAL_ENABLED env var is truthy (production safety invariant)
      - generation_mode is "preserve" or "creative" (Wave 5.5.18 Phase 2:
        the bench-gate that originally restricted to creative-only was
        explicitly skipped by user decision 2026-05-24. Preserve now fires
        the same signal as creative; watch carefully for wall invention
        regression — historical pattern Wave 5.5.15b/c/16 showed preserve
        is ultra-sensitive to surface/density signals).
      - DNA is registered for this atmosphere×room

    Returns "" for unknown modes or unmapped rooms.

    Rollback paths:
      1. `unset BIMODAL_ENABLED` → byte-identical baseline
      2. Re-add a `if generation_mode != "creative": return ""` line to
         restrict back to creative-only (Phase 1 state)
      3. Edit this function to `return ""` unconditionally
      4. Remove the section from composer.py + composer_v2.py raw_sections
    """
    from .bimodal_classifier import is_bimodal_enabled
    if not is_bimodal_enabled():
        return ""
    if generation_mode not in ("preserve", "creative"):
        return ""
    if dna is None:
        return ""
    return build_dna_room_context(dna)
