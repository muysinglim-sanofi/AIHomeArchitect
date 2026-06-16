"""SWITCH_REDESIGN_PILOT — per-atmosphere HERO furnishing signatures (R3).

SWITCH-PATH ONLY. This block is injected into the atmosphere-SWITCH prompt
(REBOOT_FRESH, iteration>1) when the SWITCH_REDESIGN_PILOT flag is on. It is
NEVER part of FIRST_VISION / V1 or the shared atmosphere DNA — so V1 stays
byte-identical. Its job: tell the model WHAT to replace each existing furniture
piece with, so an atmosphere switch reads as a distinct STYLE (not a recolor),
while keeping every piece in its original position (the contract handles the
layout/architecture lock).

Unknown atmosphere id -> "" (no hero block injected -> safe no-op).
"""

# Concise, deliberately DISTINCT hero kits per atmosphere (sofa / table /
# lighting / rug / accents). The pairs that previously looked alike
# (warm_modern vs japandi_calm) are intentionally pulled apart.
_SWITCH_HERO_SIGNATURES: dict[str, str] = {
    "warm_modern": (
        "HERO FURNISHING — Warm Modern: replace the seating with a low-profile "
        "boucle or tan-leather sofa with soft rounded arms; the table with a "
        "sculptural travertine or warm-oak coffee table; the lighting with a "
        "slim arched floor lamp + warm dimmable spots; the rug with a thick "
        "wool-blend rug in caramel; brass and warm-wood accents."
    ),
    "japandi_calm": (
        "HERO FURNISHING — Japandi: replace the seating with a low oak-frame "
        "sofa with natural-linen cushions; the table with a minimalist solid-"
        "wood low table; the lighting with a rice-paper / washi pendant + a "
        "slim wooden floor lamp; the rug with a flat-weave jute / tatami-tone "
        "mat; ceramic, bamboo and paper accents. Restrained, handcrafted, calm."
    ),
    "soft_luxury": (
        "HERO FURNISHING — Soft Luxury: replace the seating with a deep velvet "
        "or cashmere-wool sofa; the table with a marble or smoked-glass coffee "
        "table; the lighting with a sculptural alabaster/brass lamp + concealed "
        "warm cove light; the rug with a high-pile silk-blend rug; polished "
        "metal and stone accents. Plush, refined, hushed."
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


def build_switch_hero_block(atmosphere_id: str) -> str:
    """Return the hero-furnishing signature for an atmosphere, or "" if unknown."""
    return _SWITCH_HERO_SIGNATURES.get((atmosphere_id or "").strip().lower(), "")
