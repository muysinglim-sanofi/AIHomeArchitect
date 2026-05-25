"""
Wave 5.5.19 — Explicit Furniture Nouns, Zone-Grouped (architecture-safe).

EVOLUTION:

  Wave 5.5.15g — first furnishing attempt (safe_furnishing_intelligence.py),
                 living_room only, never benched standalone, abandoned.

  Wave 5.5.16 — geometry-attached rewrite, 5 rooms × creative/preserve,
                bench showed 2-3/10 wall invention in preserve (kitchen →
                sitting zone conversion). Preserve dict silenced; creative
                shipped with "restrained media presence" (not TV) wording.

  Wave 5.5.18 — DNA dormant fields revival (separate module
                build_dna_room_context). Improved sensitivity slightly but
                user observation: TV + rug still missing systematically
                because DNA mentions TV only in NEGATION and never
                mentions rug.

  Wave 5.5.19 — explicit TV + rug nouns reintegrated, but ZONE-GROUPED
                (one geometry-anchor phrase per group, not one per item)
                to keep char budget compact. Creative-only first
                (preserve dict stays {}; bench will gate preserve
                extension). Replaces Wave 5.5.16 module content; same
                file + same wiring + same gate, no composer-side changes.

PHILOSOPHY (user-locked Wave 5.5.19):

  Explicit furniture nouns (TV, rug, coffee table, side lighting,
  curtains) are NOT the danger. The danger is composition-authoritative
  semantics, focal-wall solving, media-wall solving, spatial
  optimization, symmetry cleanup, redesign behavior.

  → Each named furniture item attaches to a SPECIFIC existing geometric
    element (seating footprint, photographed bed, photographed dining
    table, existing wall geometry, existing window lines).
  → Architecture ALWAYS wins. Furniture attaches TO geometry; geometry
    NEVER changes FOR furniture.

PURPOSE
=======

Address the *furniture deficit* perception more rigorously than Wave 5.5.15g
by attaching every furnishing item to a SPECIFIC existing geometric element
in the photograph. The model thinks "where can this safely attach inside
the photographed apartment?" instead of "how should I redesign this room
to fit this furniture?".

PHILOSOPHY
==========

Furniture must attach LOCALLY to existing geometry.

NOT: force architectural redesign.

The model must NEVER, for the sake of furnishing:
  - invent walls
  - create TV walls
  - simplify layouts / enlarge spaces
  - alter topology / camera
  - create fake surfaces
  - restructure circulation
  - clean asymmetry
  - reinterpret architecture

ARCHITECTURE OF ANCHORS
=======================

Every named furnishing item ties to a structural anchor that must
already be present in the photo. If the anchor is absent, the model
typically ignores the item (safer than invention).

  Coffee table          → photographed seating footprint
  Side lighting         → existing seating geometry
  Media presence (TV)   → existing visible wall geometry
  Bedding               → photographed bed
  Bedside lighting      → existing wall geometry (adjacent to bed)
  Window treatments     → existing window lines
  Kitchen accessories   → existing counter and cabinet geometry
  Mirror / surface      → existing fixture geometry
  Tabletop styling      → photographed dining table

DESIGN CHOICES (user-locked 2026-05-24)
========================================

  - NO semantic-prior intros (no "a living room reads as socially
    inhabited" — redundant with emotional_realism + atmosphere DNA).
  - NO inline safeguard tails (no "— never altering the photographed
    layout" — already in STRUCTURAL_LOCK / OPENINGS_ANCHOR /
    STRUCTURAL_IDENTITY / STRUCTURAL_NEGATIVE_ANCHORS).
  - "restrained" + "low" + "soft" adjectives = anti-grandeur.
  - "may include" / "may appear" / listing with "or" = optional,
    non-authoritative.
  - "restrained media presence" replaces "TV" = no focal-wall keyword.
  - "along existing wall geometry" preferred over "nearby" — explicit
    geometric anchor, less spatially vague (user-locked refinement).
  - "surface continuity" preferred over "accent placement" in bathroom
    — less designer-staging semantics (user-locked refinement).

BIMODAL SPLIT
=============

  - Preserve : ultra-light, abstract, NO furniture nouns. Anchors on a
    single existing structural element per room. Architecture-first.
  - Creative : compact per-object attachment list. Still geometry-anchored.

If preserve bench shows ANY wall invention, drop preserve to "" (same
outcome Wave 5.5.15d adopted for emotional_realism).

CHAR BUDGET
===========

Per-mode sentence ranges (Wave 5.5.19 V2 — zone-grouped wording):
  Creative : 91–169 chars (TV + rug added on living/bedroom/dining; net
             lighter than Wave 5.5.16 thanks to zone-grouping)
  Preserve : `{}` — explicitly silenced pending creative bench gate

P5 priority in composer (drops first under budget pressure).

ZONE-GROUPING (Wave 5.5.19 design principle):
  Instead of 1 clause per object, group objects that share a geometry
  anchor into a single clause. living_room example:
    [seating footprint] : coffee table + area rug + side lighting
    [window lines]      : window treatments
    [existing wall]     : television
  → 5 objects in 3 clauses, not 5 clauses.

PHASE 1 SCOPE
=============

5 rooms : living_room, master_bedroom, kitchen, bathroom, dining_room.

home_office, entrance_hall, facade, garden intentionally absent —
preserves byte-identical baseline for those room types.

ROLLBACK
========

Three independent paths:
  1. `unset BIMODAL_ENABLED` — function returns "" → byte-identical baseline.
  2. Set both dicts to `{}` — signal disappears, no composer-side change.
  3. Revert this file + unwire from composer.py + composer_v2.py.
"""

from __future__ import annotations

from .atmosphere_dna.bimodal_classifier import is_bimodal_enabled


# ── CREATIVE mode (full attachment menu per room) ───────────────────────────
# Pattern: FURNISHING — [item 1 + anchor], [item 2 + anchor], or [item 3 + anchor].
# Each item ties to a structural anchor that must already exist in the photo.

_FURNISHING_CREATIVE_BY_ROOM: dict[str, str] = {
    # Wave 5.5.19 — explicit TV + rug nouns via zone-grouping. 3 anchor
    # phrases ([seating footprint] / [window lines] / [existing wall]),
    # not 5 separate clauses.
    #
    # Wave 5.5.20 fix #1 — replaced "or a television" with "and a television"
    # at the tail of the sentence. The "or" connector was reading as
    # "optional alternative" → model picked the easier 4 items (coffee
    # table/rug/lighting/curtains) and skipped TV systematically.
    # "and" implies inclusion at the same level as the other items.
    # 173 chars.
    "living_room": (
        "FURNISHING — a low coffee table, area rug, and side lighting "
        "within the seating footprint, window treatments along window "
        "lines, and a television on existing wall geometry."
    ),
    # Wave 5.5.19 — explicit rug at bedside. TV intentionally absent
    # (warm_modern bedroom DNA explicitly says "no TV directly facing
    # bed" — adding TV here would contradict DNA). 149 chars.
    "master_bedroom": (
        "FURNISHING — soft bedding on the photographed bed, an area rug "
        "at bedside, bedside lighting along the wall, or window "
        "treatments along window lines."
    ),
    "kitchen": (
        "FURNISHING — restrained countertop and shelf accessories "
        "attached to existing counter and cabinet geometry."
    ),
    "bathroom": (
        "FURNISHING — restrained mirror or surface continuity attached "
        "to existing fixture geometry."
    ),
    # Wave 5.5.19 — explicit rug beneath the dining table. 131 chars.
    "dining_room": (
        "FURNISHING — tabletop styling on the photographed dining table, "
        "an area rug beneath, or side lighting near existing seating "
        "geometry."
    ),
}


# ── PRESERVE mode — TEMPORARILY SILENCED (2026-05-24, pending Audit A) ─
#
# Bench Wave 5.5.16 preserve showed 2-3/10 wall invention (kitchen behind
# partition replaced by sitting zone requiring new walls to anchor consoles/
# art/lamps). Same failure mode as Wave 5.5.15b/c — any non-empty preserve-
# mode signal touching surface/density costs walls.
#
# Decision (user-locked 2026-05-24): keep the module + creative dict alive
# while Audit A (DNA Decoration Restoration Audit) evaluates whether Wave
# 4.6.0 furniture restrictions can be safely relaxed. If Audit A unlocks
# DNA furniture vocabulary, the geometry-attached wording below may become
# the SAFETY RAIL that lets DNA furniture ship without drift → restore the
# preserve dict at that point. If Audit A concludes DNA cannot be relaxed,
# delete the entire module.
#
# Saved sentences (for fast restore post-audit) — currently INACTIVE:
#
#   "living_room"   : "FURNISHING — read the photographed living room as
#                     subtly inhabited; furnishing attaches to existing
#                     geometry."
#   "master_bedroom": "FURNISHING — read the photographed bedroom as
#                     subtly inhabited; furnishing attaches to the existing
#                     bed and wall geometry."
#   "kitchen"       : "FURNISHING — read the photographed kitchen as
#                     subtly inhabited; furnishing attaches to existing
#                     counter and surface geometry."
#   "bathroom"      : "FURNISHING — read the photographed bathroom as
#                     subtly inhabited; furnishing attaches to existing
#                     fixture geometry."
#   "dining_room"   : "FURNISHING — read the photographed dining room as
#                     subtly inhabited; furnishing attaches to the existing
#                     dining table and seating geometry."

_FURNISHING_PRESERVE_BY_ROOM: dict[str, str] = {}


def build_furnishing_signal(
    generation_mode: str = "preserve",
    room_type: str = "",
) -> str:
    """Wave 5.5.16 — per-mode, per-room geometry-attached furnishing signal.

    Returns "" (no-op) when:
      - BIMODAL_ENABLED env var is unset / falsy
      - room_type is missing or not in the per-mode dict
      - generation_mode is unknown

    Returns the per-room preserve sentence when mode == "preserve" + flag
    ON + room_type mapped.

    Returns the per-room creative sentence when mode == "creative" + flag
    ON + room_type mapped.

    Composer wiring: P5 priority (drops first under budget pressure on
    tight atmospheres).
    """
    if not is_bimodal_enabled():
        return ""
    if not room_type:
        return ""
    if generation_mode == "preserve":
        return _FURNISHING_PRESERVE_BY_ROOM.get(room_type, "")
    if generation_mode == "creative":
        return _FURNISHING_CREATIVE_BY_ROOM.get(room_type, "")
    return ""
