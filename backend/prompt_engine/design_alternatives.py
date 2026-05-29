"""
Wave 4.11a — Design Alternatives.

When the architect would otherwise close with "What would you like to do
next?", this module substitutes 2-3 meaningful, atmosphere-aware
next-step directions instead. Goal : show the user the architect has
opinions and a map of the design territory, not just an open mic.

Design rules (Wave 4.11a) :

    1. Static library, deterministic selection. 7 active atmospheres ×
       4 facets (materials, lighting, decor, atmosphere_pivot) × 5
       templates per facet = 140 phrasings. Adding a direction = adding
       one string. No generation, no LLM, no cost.

    2. V2+ only. V1 has no prior vision to alternate from — V1's
       follow-up is the existing architect_response close, untouched.

    3. Max 3 alternatives per response (user spec confirmed). Per-
       response selection picks at most 3 facets and one template each.

    4. Refinement-aware filtering. If the user already addressed a
       facet ("more wood" → materials covered), that facet is skipped
       in the same session — we don't propose what they already chose.
       atmosphere_pivot is the always-available escape hatch.

    5. Deterministic seed = MD5(atmosphere_id + str(iteration)). Same
       (atmosphere, iteration) → same 3 alternatives within a session ;
       different across iterations so subsequent turns surface new
       directions. Different across atmospheres for variation.

    6. English-only Phase 1 (Wave 4.11a Q1).

    7. Brevity. Each template is 15-25 words. Surfaced as a numbered
       list, the 3 alternatives stay well within the 120-word brevity
       target for the full architect response.

Wave 4.11a Day 5 reminder — when the orchestrator (Day 6) emits a
CONFIDENT-tone opening BEFORE these alternatives, the opening MUST use
soft architect-guidance phrasing per user review :
    YES : "I would be careful with that direction."
    YES : "One thing I'd watch carefully here…"
    YES : "There's a trade-off worth considering."
    NO  : "Honestly — I'd push back on this one."
    NO  : "I'd strongly oppose…"
Professional guidance, not contradiction.

Public API:
    get_alternative_directions(atmosphere_id, room_type, refinement_state,
                                iteration, count=3) -> list[str]
"""

from __future__ import annotations

import hashlib
import re
from typing import Any, Optional


# Facet keys
_MATERIALS = "materials"
_LIGHTING = "lighting"
_DECOR = "decor"
_ATMO_PIVOT = "atmosphere_pivot"
_FACETS = (_MATERIALS, _LIGHTING, _DECOR, _ATMO_PIVOT)


# ── Alternatives registry ────────────────────────────────────────────────────
# 7 atmospheres × 4 facets × 5 templates. The atmosphere_pivot templates
# reference 1-2 plausible neighbours (atmospheres in the active 7 that
# share material or tonal DNA). Templates are written as the architect's
# voice — short, opinionated, ready to drop into a numbered list.

_ALTERNATIVES: dict[str, dict[str, list[str]]] = {

    # ── Warm Modern ────────────────────────────────────────────────────
    "warm_modern": {
        _MATERIALS: [
            "Deepen the wood grain — a darker walnut grounds the seating "
            "zone harder than the current oak.",
            "Pair the wood with a stone counterpoint — a worked limestone "
            "or basalt ledge anchors the room visually.",
            "Layer linen across cushions, throws and curtain — adds the "
            "tactile softness the room is asking for.",
            "Introduce a brushed-metal register — bronze or aged brass "
            "in fixtures lifts the warmth without breaking it.",
            "Bring in a leather accent piece — a worn-leather chair "
            "or ottoman adds a third material conversation.",
        ],
        _LIGHTING: [
            "Add a brass pendant over the dining or seating zone — a "
            "hospitality-grade focal point the room currently lacks.",
            "Layer a floor lamp into the corner — softens the evening "
            "ambience and breaks the overhead-only register.",
            "Replace overhead with a layered scheme — wall sconce, "
            "table lamp, picture light — pure ambient warmth.",
            "Push the colour temperature warmer — 2700K bulbs throughout "
            "match the wood register more honestly.",
            "Add a worked-glass pendant for character — Murano or "
            "blown-glass adds an artisanal note without disturbing the calm.",
        ],
        _DECOR: [
            "Edit toward fewer, larger pieces — one sculptural object "
            "lands harder than a cluster.",
            "Add one substantial textile — a heavy throw, a textured "
            "rug — to ground the seating composition.",
            "Bring in one organic specimen — a large fiddle leaf or "
            "olive tree — the room reads more alive instantly.",
            "Curate two-three framed pieces along a single wall — gallery "
            "register rather than scattered.",
            "Add a sculpted ceramic vessel on the side surface — quiet "
            "presence, no extra colour weight.",
        ],
        _ATMO_PIVOT: [
            "If you want quieter, Japandi Calm carries similar wood "
            "warmth with more restraint and negative space.",
            "For a richer evening register, Soft Luxury picks up the "
            "wood and adds tonal depth and material weight.",
            "If you want lighter overall, Nordic Warmth keeps the wood "
            "but lifts the palette and opens the light.",
            "For an organic pivot, Nature Retreat shifts toward stone, "
            "plants and earthier finishes while keeping the warmth.",
            "If you want hotel-grade restraint, Desert Luxe layers "
            "earthen tones and a calmer material rhythm.",
        ],
    },

    # ── Japandi Calm ───────────────────────────────────────────────────
    "japandi_calm": {
        _MATERIALS: [
            "Push the wood toward darker oak — a quieter, more grounded "
            "register than the lighter ash.",
            "Introduce one stone moment — a limewashed wall or worked "
            "stone counter — for tonal weight.",
            "Layer paper and rice screens — adds the Japandi register "
            "without breaking the discipline.",
            "Add a linen weave throughout textiles — natural drape "
            "carries the atmosphere's restraint forward.",
            "Bring in one ceramic surface — a worked-clay basin or "
            "vessel — for quiet artisanal texture.",
        ],
        _LIGHTING: [
            "Switch to paper-shaded pendants — Japandi's signature "
            "lighting register, soft and architectural.",
            "Add a low floor lamp at reading height — keeps the light "
            "low and human-scaled.",
            "Move toward warm 2700K throughout — matches the wood and "
            "softens the room after sunset.",
            "Introduce one Noguchi-style sculptural lamp — quiet "
            "presence as both light and object.",
            "Add a wall sconce above the seating — calmer than "
            "overhead, more grounded than a floor lamp.",
        ],
        _DECOR: [
            "Edit toward one sculptural piece — a worked-clay vessel "
            "carries more than three small objects.",
            "Add a single tonal artwork — an ink wash or "
            "monochrome — gallery register, not decoration.",
            "Bring in one ikebana arrangement — bare branch and quiet "
            "ceramic — the Japandi negative-space moment.",
            "Add a heavy linen throw across the seating — texture without "
            "visual noise.",
            "Introduce a worked-stone object — a slab, a bowl — quiet "
            "material weight, no colour.",
        ],
        _ATMO_PIVOT: [
            "For warmer hospitality feel, Warm Modern keeps the wood "
            "register but layers richer material weight.",
            "If you want lighter and brighter, Nordic Warmth carries "
            "the calm with more open palette.",
            "For an organic pivot, Nature Retreat moves toward stone, "
            "plants and earthier finishes while keeping the restraint.",
            "If you want more meditative, Wabi Sabi pushes the patina "
            "and weathered texture register further.",
            "For warmer evening atmosphere, Soft Luxury picks up the "
            "wood and adds layered tonal depth.",
        ],
    },

    # ── Soft Luxury ────────────────────────────────────────────────────
    "soft_luxury": {
        _MATERIALS: [
            "Deepen the velvet or boucle on the seating — adds the "
            "tactile richness that defines the atmosphere.",
            "Introduce a polished marble surface — counter, table, "
            "shelf — for the polished hotel register.",
            "Layer leather alongside the textile — a worn-leather chair "
            "or ottoman anchors the seating composition.",
            "Add a worked-brass detail — fixtures, frames, accents — "
            "lifts the warmth without breaking the discipline.",
            "Bring in a heavier oak or walnut — anchors the material "
            "depth across the room.",
        ],
        _LIGHTING: [
            "Add a sculptural pendant over the seating — a Murano or "
            "ribbed-glass piece carries the hotel-grade weight.",
            "Layer a tall floor lamp with a fabric shade — softens "
            "evening light and matches the textile language.",
            "Introduce picture lighting along an artwork wall — gallery "
            "register that anchors the composition.",
            "Replace overhead with table lamps throughout — Soft "
            "Luxury reads better in pooled light than flat ambience.",
            "Add a wall sconce on either side of the bed or seating — "
            "symmetrical, calming, hospitality-grade.",
        ],
        _DECOR: [
            "Add one substantial artwork — large-scale photography or "
            "abstract — Soft Luxury asks for one strong visual anchor.",
            "Bring in one worked-stone or marble object — a tray, a "
            "vessel — quiet material weight, no colour.",
            "Edit the decor cluster down — one heavy throw, one piece "
            "of art, one sculptural object, no more.",
            "Add a hide rug under the seating — anchors the zone and "
            "introduces a third material register.",
            "Introduce a tonal vase with substantial weight — terracotta, "
            "stoneware — silhouette over surface.",
        ],
        _ATMO_PIVOT: [
            "For quieter material restraint, Warm Modern keeps the "
            "wood but lifts the visual weight.",
            "If you want hotel-evening atmosphere, Desert Luxe layers "
            "earthen tones in the Soft Luxury register.",
            "For a brighter overall feel, Nordic Warmth carries the "
            "wood register with a more open palette.",
            "If you want disciplined restraint, Japandi Calm pulls the "
            "atmosphere toward negative space and quiet materials.",
            "For an organic luxury pivot, Nature Retreat keeps the "
            "material weight but shifts toward stone, plants, "
            "earthier finishes.",
        ],
    },

    # ── Nordic Warmth ──────────────────────────────────────────────────
    "nordic_warmth": {
        _MATERIALS: [
            "Push the wood toward whiter oak or birch — lifts the "
            "Nordic palette and brightens the room.",
            "Introduce wool throughout — throws, rugs, upholstery — "
            "carries the Scandinavian tactile register.",
            "Add a single stone moment — a worked limestone counter — "
            "for tonal anchor.",
            "Layer linen drapes — softens the windows and matches "
            "the natural-fibre vocabulary.",
            "Bring in one leather accent — a worn-leather sling chair "
            "anchors the wood beautifully.",
        ],
        _LIGHTING: [
            "Add a paper pendant — Nordic Warmth's signature lighting, "
            "soft and architectural.",
            "Layer a tall arched floor lamp over the seating — anchors "
            "the zone and adds evening warmth.",
            "Push toward 2700-3000K bulbs — matches the wood and softens "
            "the Nordic palette.",
            "Add wall sconces flanking the bed or seating — calming, "
            "symmetric, very Scandinavian-residential.",
            "Introduce one sculptural pendant — a PH-style or worked-"
            "metal piece — design as light.",
        ],
        _DECOR: [
            "Edit toward fewer, larger pieces — Scandinavian discipline "
            "is fewer-but-better, not more.",
            "Add one substantial textile — a heavy wool throw across "
            "the seating — instant comfort.",
            "Bring in two-three ceramics with quiet silhouettes — "
            "matte glaze, tonal palette.",
            "Add one organic specimen — fig, olive, eucalyptus — "
            "lifts the room without breaking the discipline.",
            "Introduce a gallery wall in the Scandinavian editorial "
            "register — matted prints, slim frames.",
        ],
        _ATMO_PIVOT: [
            "For more disciplined restraint, Japandi Calm carries the "
            "wood register with stricter negative space.",
            "If you want richer hospitality feel, Warm Modern picks up "
            "the wood and adds material depth.",
            "For organic / natural pivot, Nature Retreat shifts toward "
            "stone and plants while keeping the warmth.",
            "If you want layered evening atmosphere, Soft Luxury picks "
            "up the wood with richer textile weight.",
            "For sun-warm hospitality pivot, Desert Luxe trades the "
            "Nordic cool for earthen tones and woven textures.",
        ],
    },

    # ── Nature Retreat ─────────────────────────────────────────────────
    "nature_retreat": {
        _MATERIALS: [
            "Deepen the stone register — worked limestone or basalt "
            "walls carry the retreat atmosphere further.",
            "Add a worked-wood ceiling beam — anchors the natural "
            "vocabulary and gives the room weight.",
            "Layer woven natural fibres — jute, rattan, hemp — the "
            "tactile signature of the atmosphere.",
            "Introduce raw clay surfaces — a limewashed wall or "
            "earthen plaster — softens the architecture.",
            "Bring in driftwood or weathered timber accents — single "
            "object, big presence.",
        ],
        _LIGHTING: [
            "Add a woven pendant — rattan or jute shade — pure Nature "
            "Retreat lighting register.",
            "Layer warm low lamps throughout — evening atmosphere needs "
            "pools of warmth, not overhead flat.",
            "Push toward warm amber tones — matches the wood and stone "
            "and the retreat intent.",
            "Add a single hand-blown glass pendant — artisanal weight "
            "without breaking the natural language.",
            "Introduce candle-style sconces — calm, ritual-grade, very "
            "much in the retreat register.",
        ],
        _DECOR: [
            "Add one substantial plant — a fig, an olive, a giant "
            "monstera — the room breathes immediately.",
            "Bring in one piece of carved wood — a stool, a vessel, "
            "a sculpture — silent presence.",
            "Edit decor toward natural objects — a stone, a piece of "
            "driftwood, a shell collection.",
            "Add a heavy linen throw — natural drape, tactile depth, "
            "very retreat-coherent.",
            "Introduce earthen ceramics — terracotta, raw glaze — "
            "ground the composition with material weight.",
        ],
        _ATMO_PIVOT: [
            "For quieter discipline, Japandi Calm carries the natural "
            "register with stricter restraint.",
            "If you want richer warmth, Warm Modern picks up the wood "
            "and adds hospitality-grade layering.",
            "For sun-warm hospitality, Desert Luxe shifts toward "
            "earthen tones and woven texture.",
            "If you want tropical resort register, Tropical Escape "
            "deepens the vegetation and softens the architecture further.",
            "For light Nordic pivot, Nordic Warmth keeps the natural "
            "vocabulary with a brighter palette.",
        ],
    },

    # ── Desert Luxe ────────────────────────────────────────────────────
    "desert_luxe": {
        _MATERIALS: [
            "Deepen the earthen plaster — a limewashed terracotta wall "
            "anchors the desert palette.",
            "Add a worked-stone counter or hearth — travertine or "
            "limestone — carries the material weight.",
            "Layer woven textiles — flat-weave rugs, linen drapes — "
            "the desert tactile register.",
            "Introduce one leather accent piece — a sling chair or "
            "ottoman in caramel hide.",
            "Bring in raw clay objects — terracotta vessels, hand-shaped "
            "ceramics — material honesty.",
        ],
        _LIGHTING: [
            "Add a paper or pleated pendant — soft warm desert light, "
            "ritual-quiet.",
            "Layer wall sconces alongside the seating — symmetric, "
            "calming, very Desert Luxe.",
            "Push toward amber-warm bulbs — matches the earth tones "
            "and the sunset register.",
            "Introduce a sculpted iron candelabra or fixture — "
            "artisanal weight, calm presence.",
            "Add a floor lamp with woven shade — anchors the corner "
            "with the desert-textile register.",
        ],
        _DECOR: [
            "Add one substantial cactus or dracaena — sculptural plant "
            "presence in the desert register.",
            "Bring in flat-weave rugs in terracotta and ochre — anchors "
            "the seating, adds palette weight.",
            "Edit toward heavy ceramics — terracotta, stoneware — fewer "
            "and bigger.",
            "Add one large piece of natural-edge wood — a slab table, "
            "a bench — desert craft register.",
            "Introduce a single piece of woven art — Berber or "
            "tribal-inspired — anchors a wall calmly.",
        ],
        _ATMO_PIVOT: [
            "For richer hospitality register, Soft Luxury picks up the "
            "earthen tones with polished material weight.",
            "If you want tropical resort feel, Tropical Escape shifts "
            "toward dense vegetation and softer architecture.",
            "For organic / retreat pivot, Nature Retreat carries the "
            "natural register with stone and plants.",
            "If you want warmer hospitality, Warm Modern keeps the "
            "earthen warmth and layers wood depth.",
            "For Nordic-light pivot, Nordic Warmth lifts the palette "
            "and opens the visual weight.",
        ],
    },

    # ── Tropical Escape ────────────────────────────────────────────────
    "tropical_escape": {
        _MATERIALS: [
            "Deepen the wood toward teak or mahogany — anchors the "
            "tropical register with weight.",
            "Add worked stone or basalt — a worked counter or wall "
            "panel — carries the resort weight.",
            "Layer woven rattan, jute and bamboo — the tropical tactile "
            "signature.",
            "Introduce raw plaster — limewashed walls in cream — soften "
            "the architectural shell.",
            "Bring in one polished concrete or terrazzo surface — "
            "resort-grade material rhythm.",
        ],
        _LIGHTING: [
            "Add a woven rattan pendant — pure tropical resort lighting "
            "register.",
            "Layer warm low lamps throughout — evening atmosphere reads "
            "richer when pooled than overhead.",
            "Push toward warm amber bulbs — matches the wood and the "
            "sunset-resort intent.",
            "Introduce a paper or shell-shade pendant — artisanal "
            "weight in the resort vocabulary.",
            "Add candle-style sconces flanking key zones — ritual-grade "
            "warmth, very resort-honest.",
        ],
        _DECOR: [
            "Add substantial tropical plants — banana, palm, monstera, "
            "fiddle leaf — the room transforms immediately.",
            "Bring in woven baskets and vessels — natural texture, "
            "resort-coherent.",
            "Edit toward fewer, larger natural objects — driftwood, "
            "carved wood, sculpted shell.",
            "Add a heavy linen or cotton throw — natural drape, "
            "resort-tactile.",
            "Introduce a single piece of woven art or textile — "
            "tribal-inspired, anchored on one wall.",
        ],
        _ATMO_PIVOT: [
            "For drier hospitality pivot, Desert Luxe trades the "
            "tropical vegetation for earthen tones.",
            "If you want quieter restraint, Japandi Calm carries the "
            "natural materials with discipline.",
            "For organic retreat pivot, Nature Retreat layers stone "
            "and plants in a calmer register.",
            "If you want richer evening atmosphere, Soft Luxury picks "
            "up the wood and adds material weight.",
            "For warmer-modern pivot, Warm Modern keeps the wood and "
            "trades vegetation for layered lighting.",
        ],
    },
}


# Material / lighting / decor keywords used to detect which facets the
# user has already addressed in this session. When a facet is "covered",
# we skip it in the alternatives so we don't propose what they just
# chose. atmosphere_pivot is never excluded — it's always an option.

_FACET_KEYWORDS = {
    _MATERIALS: (
        "wood", "wooden", "oak", "walnut", "teak", "mahogany", "birch",
        "ash", "stone", "marble", "granite", "limestone", "basalt",
        "travertine", "concrete", "terrazzo", "brass", "metal",
        "metallic", "bronze", "fabric", "linen", "wool", "velvet",
        "boucle", "leather", "rattan", "jute", "bamboo", "plaster",
        "ceramic", "porcelain", "tile", "texture", "material",
    ),
    _LIGHTING: (
        "light", "lighting", "lamp", "pendant", "sconce", "chandelier",
        "fixture", "ambient", "warm", "warmer", "bright", "brighter",
        "softer light", "illuminate", "candle",
    ),
    _DECOR: (
        "decor", "decoration", "art", "artwork", "plant", "plants",
        "greenery", "vase", "vessel", "object", "objects", "piece",
        "pieces", "ornament", "sculpture", "sculptural", "throw",
        "cushion", "rug", "carpet", "painting", "frame", "gallery",
    ),
}


# ── Internals ────────────────────────────────────────────────────────────────

def _covered_facets(refinement_state: Any) -> set[str]:
    """
    Return the set of facets the user has already addressed in the
    session (per refinement_state.add / .enhance / .directions).

    Uses word-boundary regex (not substring) so "more wood for warmth"
    matches "wood" without also matching "warm" inside "warmth" — the
    earlier substring approach over-flagged the lighting facet on any
    "warm"-stem token.
    """
    if refinement_state is None:
        return set()
    text_chunks: list[str] = []
    for attr in ("add", "enhance", "directions"):
        items = getattr(refinement_state, attr, None) or []
        for it in items:
            if isinstance(it, str):
                text_chunks.append(it.lower())
    if not text_chunks:
        return set()
    blob = " ".join(text_chunks)

    covered: set[str] = set()
    for facet, keywords in _FACET_KEYWORDS.items():
        for kw in keywords:
            # Word-boundary match : "warm" no longer matches "warmth", "lamp"
            # doesn't match "ambulamp", etc. Multi-word phrases like
            # "softer light" still work because spaces are word boundaries.
            if re.search(rf"\b{re.escape(kw)}\b", blob):
                covered.add(facet)
                break
    return covered


def _seed_index(atmosphere_id: str, iteration: int, salt: str = "") -> int:
    """
    Deterministic non-negative integer derived from (atmosphere, iteration,
    salt). Used as the modulo index when picking a template inside a facet.
    The salt distinguishes selections across facets so we don't always pick
    the same array position in materials/lighting/decor.
    """
    raw = f"{atmosphere_id}|{iteration}|{salt}".encode("utf-8")
    h = hashlib.md5(raw).digest()
    # First 4 bytes → 32-bit unsigned int.
    return int.from_bytes(h[:4], "big")


def _pick_template(
    atmosphere_id: str, facet: str, iteration: int
) -> Optional[str]:
    """
    Deterministic single-template pick from a facet's list. Returns None
    if the atmosphere is unknown or the facet is empty.
    """
    facets = _ALTERNATIVES.get(atmosphere_id)
    if not facets:
        return None
    templates = facets.get(facet)
    if not templates:
        return None
    idx = _seed_index(atmosphere_id, iteration, salt=facet) % len(templates)
    return templates[idx]


# Default facet order — atmosphere_pivot listed LAST so it only surfaces
# when other facets are covered. Atmospheres still preserve the materials
# / lighting / decor primacy that users naturally explore first.
_DEFAULT_FACET_ORDER = (_MATERIALS, _LIGHTING, _DECOR, _ATMO_PIVOT)


# ── Public API ───────────────────────────────────────────────────────────────

def get_alternative_directions(
    atmosphere_id: Optional[str],
    room_type: Optional[str] = None,  # reserved for future room-aware variants
    refinement_state: Any = None,
    iteration: int = 0,
    count: int = 3,
) -> list[str]:
    """
    Return 2-3 architect-voice next-direction suggestions for the
    current atmosphere, filtered against facets the user already
    touched in the session.

    Returns an empty list when :
      - atmosphere_id is unknown
      - iteration <= 1 (V1 uses the architect's existing follow-up)
      - count <= 0
      - every facet is covered by prior refinements (extremely rare ;
        atmosphere_pivot is always available so this only happens if
        the caller has explicitly excluded the pivot)

    Picking strategy :
      1. Walk _DEFAULT_FACET_ORDER (materials → lighting → decor →
         atmosphere_pivot)
      2. Skip facets already covered by refinement_state
      3. From each remaining facet, deterministically pick 1 template
         (seed = MD5(atmosphere_id + iteration + facet))
      4. Stop when we've collected `count` directions
    """
    if not atmosphere_id or atmosphere_id not in _ALTERNATIVES:
        return []
    if iteration <= 1 or count <= 0:
        return []

    covered = _covered_facets(refinement_state)
    picks: list[str] = []
    for facet in _DEFAULT_FACET_ORDER:
        if facet in covered:
            continue
        template = _pick_template(atmosphere_id, facet, iteration)
        if not template:
            continue
        picks.append(template)
        if len(picks) >= count:
            break

    # Edge case : all facets covered. Fall back to atmosphere_pivot so the
    # caller always has at least one direction to offer when V2+.
    if not picks:
        pivot = _pick_template(atmosphere_id, _ATMO_PIVOT, iteration)
        if pivot:
            picks.append(pivot)
    return picks


def list_atmospheres() -> list[str]:
    """Return all atmospheres covered by the library."""
    return list(_ALTERNATIVES.keys())


def template_count() -> int:
    """Total template count across the library (for tests / reports)."""
    return sum(
        len(facets)
        for atm in _ALTERNATIVES.values()
        for facets in atm.values()
    )


def facets() -> tuple[str, ...]:
    """The four facet keys."""
    return _FACETS
