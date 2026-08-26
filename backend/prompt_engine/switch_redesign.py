"""SWITCH_REDESIGN_PILOT — per-atmosphere HERO furnishing signatures (R3).

SWITCH-PATH ONLY. Injected into the FIRST_VISION prompt (composer.py Path D)
ONLY when composer_v2's REBOOT_FRESH delegation forwards switch_redesign=True
(i.e. an atmosphere switch with SWITCH_REDESIGN_PILOT on). NEVER part of a real
V1 (FIRST_VISION direct) or the shared atmosphere DNA → real V1 stays
byte-identical. Job: tell the model WHAT to replace each existing furniture piece
with, so an atmosphere switch reads as a distinct STYLE (not a recolor), while
keeping every piece in its original position (the contract handles layout +
architecture lock; the structural mask protects the openings).

Unknown atmosphere id -> "" (no hero block injected -> safe no-op).
"""

_SWITCH_HERO_SIGNATURES: dict[str, str] = {
    "warm_modern": (
        "HERO FURNISHING — Warm Modern: replace the seating with a LOW, MODULAR "
        "sofa, clean straight lines and a light oatmeal boucle, on slim wood "
        "legs (relaxed, casual); the table with a chunky warm-oak or travertine "
        "block coffee table; the lighting with a slim arched floor lamp + warm "
        "dimmable spots; the rug with a flat caramel wool-blend rug; brass and "
        "warm-wood accents. Understated, grounded, daytime-warm."
    ),
    "japandi_calm": (
        # Deliberately identical to the COMPACT entry below. This signature is
        # already telegraphic — it carries no verbose parenthetical or duplicate
        # mood adjective for a compact variant to strip. Writing it out in the
        # longer "replace the X with Y" style of its siblings costs ~110 chars,
        # which pushes the SWITCH_BLOCK_COMPACT=0 prompt past the FIRST_VISION
        # budget (4300) and evicts dna_room_context — i.e. the living-room TV
        # anchors. Measured: 615-char variant -> 4481 -> TV block dropped. One
        # grammar, both variants, no footgun.
        "HERO FURNISHING — Japandi: FRAME-FIRST — exposed squared timber frames, "
        "thin flat inset cushions, nothing plump or rolled: post-and-rail sofa "
        "frame outlining slim pads; open-frame armchairs, cane or paper-cord "
        "backs, no tubs; slab low table on a recessed plinth; trestle dining "
        "slab, spindle-back chairs; low console, flush or slatted fronts; washi "
        "pendant, slim floor lamp."
    ),
    "soft_luxury": (
        "HERO FURNISHING — Soft Luxury: replace the seating with a DEEP, CURVED "
        "sofa, plush rounded volumes and channel tufting in rich taupe velvet, "
        "on a recessed or polished-metal base (enveloping, generous depth); the "
        "table with a rounded marble or smoked-glass coffee table; the lighting "
        "with a sculptural alabaster/brass lamp + concealed warm cove light; the "
        "rug with a high-pile silk-blend rug; polished metal and stone accents. "
        "Plush, opulent, hushed — clearly richer and curvier than Warm Modern."
    ),
    "nordic_warmth": (
        "HERO FURNISHING — Nordic Warmth: replace the seating with a light-oak "
        "and pale-wool sofa with clean lines; the table with a round birch "
        "coffee table; the lighting with a paper globe or matte-black arc lamp; "
        "the rug with a chunky off-white wool rug; sheepskin throw and light-"
        "wood accents. Bright, airy, cosy."
    ),
    "tropical_escape": (
        "HERO FURNISHING — Tropical: replace the seating with a rattan / cane-"
        "frame sofa with natural-linen cushions; the table with a teak or live-"
        "edge coffee table; the lighting with a woven seagrass pendant + rattan "
        "floor lamp; the rug with a natural jute rug; large leafy plants and "
        "teak accents. Lush, breezy, organic."
    ),
}


# SWITCH_BLOCK_COMPACT (2026-06-23) — compact hero signatures. Used ONLY when
# composer.py reads SWITCH_BLOCK_COMPACT=1 (switch path / switch_redesign=True).
# Same intent (REPLACE) + same signature FORMS + signature MATERIALS + the
# prev-atmosphere contrast, with verbose parentheticals and duplicate mood
# adjectives removed (~30-200 chars lighter per atmosphere). Goal: stop the
# REBOOT_FRESH prompt from overflowing the FIRST_VISION budget (4300), which was
# forcing the budget assembler to drop dna_room_context — the section that
# carries the TV / room-specific anchors (proven on WM→Soft Luxury). Nordic keeps
# an explicit Japandi contrast so the two stay visually distinct. The default
# (full) signatures above are untouched → switch output is byte-identical when
# the flag is OFF.
_SWITCH_HERO_SIGNATURES_COMPACT: dict[str, str] = {
    "warm_modern": (
        "HERO FURNISHING — Warm Modern: low modular oatmeal-boucle sofa on slim "
        "wood legs; chunky warm-oak or travertine coffee table; slim arched floor "
        "lamp + warm dimmable spots; flat caramel wool-blend rug; brass and "
        "warm-wood accents — understated, grounded, daytime-warm."
    ),
    "japandi_calm": (
        "HERO FURNISHING — Japandi: FRAME-FIRST — exposed squared timber frames, "
        "thin flat inset cushions, nothing plump or rolled: post-and-rail sofa "
        "frame outlining slim pads; open-frame armchairs, cane or paper-cord "
        "backs, no tubs; slab low table on a recessed plinth; trestle dining "
        "slab, spindle-back chairs; low console, flush or slatted fronts; washi "
        "pendant, slim floor lamp."
    ),
    "soft_luxury": (
        "HERO FURNISHING — Soft Luxury: deep curved channel-tufted taupe-velvet "
        "sofa; rounded marble or smoked-glass coffee table; large sculptural "
        "alabaster chandelier + warm cove light; high-pile silk-blend rug; "
        "polished metal and stone accents — plush and opulent, richer and "
        "curvier than Warm Modern."
    ),
    "nordic_warmth": (
        "HERO FURNISHING — Nordic Warmth: light-oak and pale-wool sofa with clean "
        "lines; round birch coffee table; paper-globe or matte-black arc lamp; "
        "chunky off-white wool rug + sheepskin throw; light-wood accents — bright, "
        "airy, cosy, lighter than Japandi's wood-and-paper restraint."
    ),
    "tropical_escape": (
        "HERO FURNISHING — Tropical: rattan/cane-frame sofa with natural-linen "
        "cushions; teak or live-edge coffee table; woven-seagrass pendant + rattan "
        "floor lamp; natural jute rug; large leafy plants and teak accents — lush, "
        "breezy, organic."
    ),
}


def build_switch_hero_block(atmosphere_id: str, compact: bool = False) -> str:
    """Return the hero-furnishing signature for an atmosphere, or "" if unknown.

    compact=False (default) → the full signature, byte-identical to the shipped
    switch block. compact=True → the lighter SWITCH_BLOCK_COMPACT variant,
    forwarded ONLY by composer.py when SWITCH_BLOCK_COMPACT=1. Switch-path only;
    a real V1 never reaches this (switch_redesign=False).
    """
    key = (atmosphere_id or "").strip().lower()
    table = _SWITCH_HERO_SIGNATURES_COMPACT if compact else _SWITCH_HERO_SIGNATURES
    return table.get(key, "")
