"""
Wave 4.11a — Trade-Off Library.

Static knowledge of common architectural / material / lighting trade-offs.
When the user requests a direction that carries a known consequence, the
architect surfaces it as a single concise clause before generating —
"we can move darker, but it tends to compress this room's openness".

Design rules (Wave 4.11a North Star : "I'm talking to an architect" —
this is the module that earns that perception by flagging consequences
the user wouldn't have considered):

    1. Single source of truth in this file. ~35 curated entries. Adding
       a trade-off = adding ONE TradeOffEntry to the list.
    2. V2+ only — V1 has no prior vision to weigh against.
    3. Max ONE trade-off per response. Priority resolves ties (lower
       priority value = more specific = wins).
    4. Silent by default. When no entry matches, return "" — the
       architect's response stays unchanged.
    5. English-only Phase 1 (per Wave 4.11a Q1). Khmer translation of
       the architectural critique layer is deferred to a later wave.
    6. Brevity-friendly clauses — typically 1-2 sentences, 25-40 words,
       always offering mitigation when possible ("we can compensate
       with X if you'd like to keep both").

Public API:
    get_trade_off(user_message, transformation_type, atmosphere_id,
                   room_type, structural_identity=None) -> str
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Optional


# ── Data shape ───────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class TradeOffEntry:
    """
    One trade-off : the architect's "yes, but…" for a user direction.

    Matching :
      • direction_keywords — at least one must appear in user message
      • atmosphere_filter — if set, ONE of these atmospheres must be active
      • room_filter — if set, ONE of these rooms must be active
      • transformation_filter — if set, ONE of these transformations matches

    Priority (lower wins) :
      0   — room AND atmosphere specific (most surgical)
      10  — atmosphere specific (room agnostic)
      20  — room specific (atmosphere agnostic)
      30  — generic (applies broadly)
    """
    direction_keywords: tuple[str, ...]
    clause: str
    priority: int = 30
    atmosphere_filter: tuple[str, ...] = field(default_factory=tuple)
    room_filter: tuple[str, ...] = field(default_factory=tuple)
    transformation_filter: tuple[str, ...] = field(default_factory=tuple)


# ── Trade-off entries ────────────────────────────────────────────────────────
# Organised by direction family. Each entry's clause is what the architect
# says when the rule fires. Mitigation phrases are included where the
# trade-off can be softened.

_TRADE_OFFS: tuple[TradeOffEntry, ...] = (

    # ── Darker palette / heavier tones ─────────────────────────────────
    TradeOffEntry(
        direction_keywords=("darker", "darken", "deeper palette", "moodier"),
        atmosphere_filter=("warm_modern", "japandi_calm", "nordic_warmth"),
        clause=(
            "We can shift toward a deeper palette. One trade-off — this "
            "atmosphere reads on quiet brightness, and going darker tends "
            "to drop the airiness that's currently working. A focal lamp "
            "can keep some of the openness back."
        ),
        priority=10,
    ),
    TradeOffEntry(
        direction_keywords=("darker", "darken", "deeper palette"),
        room_filter=("living_room", "bedroom", "dining_room"),
        clause=(
            "Darker walls or floor here will compress the sense of space, "
            "especially against the current openings. We can compensate "
            "with a stronger lighting layer if you'd like to keep both."
        ),
        priority=20,
    ),
    TradeOffEntry(
        direction_keywords=("darker", "darken", "moodier"),
        clause=(
            "A darker direction reads more intimate but trades off some "
            "perceived volume — worth keeping the lighting plan generous "
            "so it doesn't feel closed in."
        ),
        priority=30,
    ),

    # ── Brighter palette / lighter tones ──────────────────────────────
    TradeOffEntry(
        direction_keywords=("brighter", "lighter palette", "more luminous"),
        atmosphere_filter=("dark_contemporary", "penthouse_contemporary"),
        clause=(
            "Pushing brighter undoes some of the cinematic depth this "
            "atmosphere builds with shadow. We can keep the moody base "
            "and just open a few accent surfaces if you want both."
        ),
        priority=10,
    ),
    TradeOffEntry(
        direction_keywords=("brighter", "lighter palette"),
        atmosphere_filter=("soft_luxury",),
        clause=(
            "Soft Luxury leans on layered tonal depth — going much "
            "brighter risks flattening the richness. Keeping the wall "
            "neutral and lightening just the textiles preserves the "
            "atmospheric weight."
        ),
        priority=10,
    ),

    # ── Heavier materials in compact rooms ─────────────────────────────
    TradeOffEntry(
        direction_keywords=("more wood", "darker wood", "heavy wood"),
        atmosphere_filter=("warm_modern", "tropical_escape"),
        clause=(
            "More wood will deepen the warmth nicely — though stacked on "
            "an already-warm atmosphere, it tips toward cabin-dense. A "
            "calmer stone counterpoint can keep the rhythm balanced."
        ),
        priority=10,
    ),
    TradeOffEntry(
        direction_keywords=("more wood", "wooden", "wood paneling"),
        room_filter=("bathroom",),
        clause=(
            "Wood in a bathroom reads warm and spa-like but carries a real "
            "humidity exposure. Worth committing only on accent zones "
            "(vanity, ceiling) and keeping the wet zone in ceramic or "
            "stone."
        ),
        priority=20,
    ),

    # ── Luxury materials in compact spaces ─────────────────────────────
    TradeOffEntry(
        direction_keywords=("luxury", "marble", "brass", "premium materials"),
        room_filter=("studio", "small_living_room", "compact"),
        clause=(
            "Heavy luxe materials read denser in a compact room. To avoid "
            "crowding, I'd anchor them to one focal area — the kitchen "
            "island or a wall feature — and keep the rest restrained."
        ),
        priority=20,
    ),
    TradeOffEntry(
        direction_keywords=("more brass", "brass accents", "metallic"),
        atmosphere_filter=("japandi_calm", "nordic_warmth", "wabi_sabi"),
        clause=(
            "Brass against this atmosphere's calm tonal weight can over-"
            "announce itself. Limiting it to a single fixture (a pendant "
            "or a tap) keeps the warmth without breaking the restraint."
        ),
        priority=10,
    ),
    TradeOffEntry(
        direction_keywords=("more marble", "marble"),
        atmosphere_filter=("japandi_calm", "wabi_sabi", "nordic_warmth"),
        clause=(
            "Marble carries a polished formality that pulls against this "
            "atmosphere's quieter intent. A single calm slab — counter, "
            "shelf — usually lands ; full surfaces start a different "
            "conversation."
        ),
        priority=10,
    ),

    # ── More decor against restraint atmospheres ───────────────────────
    TradeOffEntry(
        direction_keywords=("more decor", "more decoration", "more objects",
                             "more accessories"),
        atmosphere_filter=("japandi_calm", "wabi_sabi"),
        clause=(
            "More decor against this atmosphere's restraint flattens the "
            "intent. If you want presence, I'd recommend one sculptural "
            "piece rather than a cluster — the negative space is the "
            "design here."
        ),
        priority=10,
    ),
    TradeOffEntry(
        direction_keywords=("more decor", "more decoration", "more art",
                             "more objects"),
        atmosphere_filter=("nordic_warmth", "warm_modern"),
        clause=(
            "Quietly more decor works in this atmosphere — though stacking "
            "many small pieces shifts it toward eclectic. I'd cap the "
            "addition at two-three intentional pieces rather than "
            "scattering them."
        ),
        priority=10,
    ),
    TradeOffEntry(
        direction_keywords=("maximalist", "more layered"),
        atmosphere_filter=("nordic_warmth", "japandi_calm", "wabi_sabi"),
        clause=(
            "Maximalism pulls hard against this atmosphere's quiet "
            "discipline — it's a different design language. We can layer "
            "more inside the current restraint, or we can pivot to a "
            "different atmosphere entirely."
        ),
        priority=10,
    ),

    # ── More plants / nature additions ─────────────────────────────────
    TradeOffEntry(
        direction_keywords=("more plants", "more greenery", "more vegetation"),
        atmosphere_filter=("dark_contemporary", "penthouse_contemporary",
                            "soft_luxury"),
        clause=(
            "Plants soften this atmosphere nicely — though the moody / "
            "polished register can pull against organic density. I'd stay "
            "to two-three sculptural specimens rather than a fuller "
            "vegetative layer."
        ),
        priority=10,
    ),
    TradeOffEntry(
        direction_keywords=("more plants", "more greenery"),
        room_filter=("bathroom",),
        clause=(
            "Plants in a bathroom work when humidity and light are right. "
            "Worth picking species that thrive in steam (ferns, pothos) "
            "rather than committing to a full vegetative wall."
        ),
        priority=20,
    ),

    # ── Removing furniture / opening up ────────────────────────────────
    TradeOffEntry(
        direction_keywords=("remove the partition", "open the wall",
                             "remove the wall", "open the kitchen"),
        room_filter=("kitchen", "living_room"),
        clause=(
            "Opening this wall reads more spacious but trades the "
            "current kitchen privacy — cooking smells and noise carry "
            "across. A glazed partition keeps the visual continuity "
            "without losing the separation."
        ),
        priority=20,
        transformation_filter=("structural_change", "layout_reinterpretation"),
    ),
    TradeOffEntry(
        direction_keywords=("remove the partition", "open the wall",
                             "remove the wall"),
        room_filter=("bedroom",),
        clause=(
            "Opening the bedroom into the adjacent space gains light but "
            "loses sleep intimacy — bedrooms benefit from acoustic and "
            "visual seclusion. A sliding panel preserves both options."
        ),
        priority=20,
        transformation_filter=("structural_change", "layout_reinterpretation"),
    ),

    # ── Bigger furniture / circulation ─────────────────────────────────
    TradeOffEntry(
        direction_keywords=("bigger sofa", "bigger sectional", "bigger seating"),
        room_filter=("studio", "small_living_room"),
        clause=(
            "A larger sofa crowds the circulation here. If the seating "
            "feels short, a deeper (not wider) piece often reads more "
            "generous without sacrificing the walk-around."
        ),
        priority=20,
    ),
    TradeOffEntry(
        direction_keywords=("bigger kitchen island", "wider island",
                             "larger island"),
        room_filter=("kitchen", "small_kitchen"),
        clause=(
            "A larger island anchors the kitchen but constrains the "
            "perimeter walk. Worth keeping at least 110 cm clearance on "
            "the working sides to stay comfortable."
        ),
        priority=20,
    ),

    # ── More contrast / drama against calm atmospheres ─────────────────
    TradeOffEntry(
        direction_keywords=("more contrast", "stronger contrast",
                             "high contrast"),
        atmosphere_filter=("japandi_calm", "wabi_sabi", "nordic_warmth"),
        clause=(
            "Strong contrast competes with this atmosphere's layered "
            "subtlety. We can keep the tonal interest by deepening one "
            "material (a darker oak, an iron grey stone) without pushing "
            "the full contrast spread."
        ),
        priority=10,
    ),
    TradeOffEntry(
        direction_keywords=("dramatic lighting", "more dramatic",
                             "theatrical lighting"),
        atmosphere_filter=("japandi_calm", "wabi_sabi", "nordic_warmth",
                            "warm_modern"),
        clause=(
            "Dramatic lighting reads beautifully in moody contexts but "
            "fights this atmosphere's quiet light register. A layered "
            "warm setup gets you depth without the theatricality."
        ),
        priority=10,
    ),

    # ── Texture / industrial in sleep rooms ────────────────────────────
    TradeOffEntry(
        direction_keywords=("industrial", "raw concrete", "exposed brick"),
        room_filter=("bedroom",),
        clause=(
            "Industrial language in a bedroom can read uninviting — "
            "concrete and metal carry an acoustic and tactile coldness. "
            "Softening with linen, wool and a deep rug usually rescues it."
        ),
        priority=20,
    ),
    TradeOffEntry(
        direction_keywords=("more texture", "heavy texture", "rougher texture"),
        atmosphere_filter=("japandi_calm",),
        clause=(
            "Japandi tolerates calm texture, not visual noise. Heavy "
            "weave or rough stone tips it toward rustic, which is a "
            "different family — worth picking one textural moment and "
            "letting the rest stay smooth."
        ),
        priority=10,
    ),

    # ── Cool palette against warm atmospheres ──────────────────────────
    TradeOffEntry(
        direction_keywords=("cool palette", "cooler tones", "blue palette",
                             "grey palette"),
        atmosphere_filter=("warm_modern", "tropical_escape"),
        clause=(
            "Cooling this atmosphere down works against its core "
            "register. We can introduce cool accent (a metal, a deep "
            "green plant) without flipping the temperature of the base."
        ),
        priority=10,
    ),

    # ── Adding a TV against minimal intent ─────────────────────────────
    TradeOffEntry(
        direction_keywords=("add a tv", "bigger tv", "wall-mounted tv"),
        atmosphere_filter=("japandi_calm", "wabi_sabi"),
        clause=(
            "A TV against this atmosphere's calm intent often becomes "
            "the visual centre. Recessing it behind a wood panel or "
            "framing it as art turns the necessity into a design moment."
        ),
        priority=10,
    ),

    # ── Stone / concrete in tropical / warm contexts ───────────────────
    TradeOffEntry(
        direction_keywords=("more stone", "stone walls", "concrete walls"),
        atmosphere_filter=("tropical_escape",),
        clause=(
            "Heavy stone reads cold against tropical warmth and the "
            "organic vocabulary you're building. A textured plaster or "
            "limewash usually carries the structural feel without the "
            "thermal coldness."
        ),
        priority=10,
    ),

    # ── Atmosphere pivots ──────────────────────────────────────────────
    TradeOffEntry(
        direction_keywords=("more minimalist", "more minimal"),
        atmosphere_filter=("soft_luxury", "tropical_escape"),
        clause=(
            "Pushing minimalist erases the depth this atmosphere is "
            "built on. If you want quieter, I'd rather thin out the "
            "decor than strip the material layering — the second one "
            "loses the identity entirely."
        ),
        priority=10,
    ),
    # (Nature Retreat / Wabi Sabi "more modern" entry removed 2026-06-04 with
    # Nature Retreat deregistration. Both atmosphere_filter entries refer to
    # deregistered / non-existent atmospheres — entry is now defunct.)

    # ── More furniture / clutter ───────────────────────────────────────
    TradeOffEntry(
        direction_keywords=("more furniture", "more pieces", "fuller room"),
        room_filter=("studio", "compact", "small_living_room"),
        clause=(
            "More furniture in this footprint risks crowding the "
            "circulation. If the room feels empty, swapping for "
            "bigger-but-fewer pieces (one deep sofa, one wide cabinet) "
            "usually anchors better than adding count."
        ),
        priority=20,
    ),

    # ── Heavy curtains in airy rooms ───────────────────────────────────
    TradeOffEntry(
        direction_keywords=("heavy curtains", "thick drapes", "blackout drapes"),
        atmosphere_filter=("japandi_calm", "nordic_warmth"),
        clause=(
            "Heavy drapery against this atmosphere's airy light register "
            "reads incongruous. A linen sheer carries the privacy "
            "function without the visual weight."
        ),
        priority=10,
    ),

    # ── Generic catch-all fallbacks (priority 30) ──────────────────────
    TradeOffEntry(
        direction_keywords=("more luxury", "more premium"),
        clause=(
            "Pushing the luxury register works — though it accumulates "
            "fast in materials and decor. One restrained focal moment "
            "(a marble counter, a brass pendant) usually lands harder "
            "than a layered set."
        ),
        priority=30,
    ),
    TradeOffEntry(
        direction_keywords=("bigger windows", "larger windows",
                             "wider windows"),
        clause=(
            "Larger windows transform the light, but they're structural "
            "changes — they need to fit the facade rhythm and the "
            "building's load. I'll flag this as a structural request "
            "rather than a styling refinement."
        ),
        priority=30,
        transformation_filter=("structural_change",),
    ),
)


# ── Lookup ───────────────────────────────────────────────────────────────────

def _matches_keyword(message_lower: str, keywords: tuple[str, ...]) -> bool:
    """True if any keyword appears as a substring (case-insensitive)."""
    return any(kw in message_lower for kw in keywords)


def _matches_filter(value: Optional[str], filter_set: tuple[str, ...]) -> bool:
    """
    Filter-pass logic :
      empty filter set → match everything (rule is generic for this axis)
      non-empty + value in set → match
      non-empty + value not in set → no match
    """
    if not filter_set:
        return True
    if value is None:
        return False
    return value in filter_set


# ── Public API ───────────────────────────────────────────────────────────────

def get_trade_off(
    user_message: str,
    transformation_type: Optional[str] = None,
    atmosphere_id: Optional[str] = None,
    room_type: Optional[str] = None,
    iteration: int = 0,
) -> str:
    """
    Look up the most specific trade-off matching the user's request.

    Returns the architect-voice clause (1-2 sentences) or "" when no
    entry applies. V1 (iteration <= 1) always returns "" — there's no
    prior vision to weigh trade-offs against.

    Priority resolution : multiple entries can match a single request ;
    the lowest priority value wins (lower = more specific). On ties,
    the earlier entry in the registry wins (stable, deterministic).

    Caller is responsible for emitting at most ONE trade-off per
    response — this function returns the best single match.
    """
    if not user_message or iteration <= 1:
        return ""

    message_lower = user_message.lower()
    candidates: list[tuple[int, str]] = []

    for entry in _TRADE_OFFS:
        if not _matches_keyword(message_lower, entry.direction_keywords):
            continue
        if not _matches_filter(atmosphere_id, entry.atmosphere_filter):
            continue
        if not _matches_filter(room_type, entry.room_filter):
            continue
        if not _matches_filter(transformation_type, entry.transformation_filter):
            continue
        candidates.append((entry.priority, entry.clause))

    if not candidates:
        return ""

    # Sort by priority ascending — lower = more specific = wins.
    candidates.sort(key=lambda pair: pair[0])
    return candidates[0][1]


def list_entries() -> tuple[TradeOffEntry, ...]:
    """Return the full registry — for tests / introspection."""
    return _TRADE_OFFS


def entry_count() -> int:
    """Convenience for tests / wave reports."""
    return len(_TRADE_OFFS)
