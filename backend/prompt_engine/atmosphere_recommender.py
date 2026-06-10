"""
atmosphere_recommender.py — V1 "Surprise Me" atmosphere selection engine.

Recommends the atmosphere most likely to create emotional impact and visual
coherence for a given room context. Not random — curated scoring.

Design principle: deterministic, curated compatibility matrix + signal bonuses.
No ML, no vector search.
"""

from __future__ import annotations

# ── Compatibility matrix ───────────────────────────────────────────────────────
# Base scores per room_type → atmosphere. Range 0.0–1.0.
# Higher = better visual and emotional fit for this room type.
#
# desert_luxe removed 2026-06-03 — see _LEGACY_ALIASES["desert_luxe"] in
# atmosphere_dna/_base.py.
# nature_retreat removed 2026-06-04 — same pattern (too close to Tropical
# Escape, MVP differentiation gain).

_BASE_COMPAT: dict[str, dict[str, float]] = {
    "living_room": {
        "warm_modern": 0.90,
        "soft_luxury": 0.85,
        "japandi_calm": 0.80,
        "nordic_warmth": 0.65,
        "tropical_escape": 0.60,
    },
    "master_bedroom": {
        "soft_luxury": 0.90,
        "japandi_calm": 0.85,
        "warm_modern": 0.75,
        "nordic_warmth": 0.65,
        "tropical_escape": 0.45,
    },
    "kitchen": {
        "warm_modern": 0.90,
        "japandi_calm": 0.85,
        "nordic_warmth": 0.75,
        "soft_luxury": 0.65,
        "tropical_escape": 0.35,
    },
    "bathroom": {
        "soft_luxury": 0.90,
        "japandi_calm": 0.85,
        "warm_modern": 0.70,
        "nordic_warmth": 0.50,
        "tropical_escape": 0.45,
    },
    "home_office": {
        "japandi_calm": 0.85,
        "warm_modern": 0.80,
        "soft_luxury": 0.60,
        "nordic_warmth": 0.60,
        "tropical_escape": 0.35,
    },
    "dining_room": {
        "soft_luxury": 0.85,
        "warm_modern": 0.80,
        "japandi_calm": 0.65,
        "nordic_warmth": 0.65,
        "tropical_escape": 0.50,
    },
    "entrance_hall": {
        "soft_luxury": 0.90,
        "warm_modern": 0.80,
        "japandi_calm": 0.65,
        "nordic_warmth": 0.45,
        "tropical_escape": 0.40,
    },
    "facade": {
        "warm_modern": 0.85,
        "soft_luxury": 0.80,
        "japandi_calm": 0.65,
        "tropical_escape": 0.60,
        "nordic_warmth": 0.45,
    },
    "garden": {
        "tropical_escape": 0.80,
        "warm_modern": 0.70,
        "nordic_warmth": 0.65,
        "soft_luxury": 0.60,
        "japandi_calm": 0.55,
    },
    "pool_area": {
        "tropical_escape": 0.90,
        "soft_luxury": 0.80,
        "warm_modern": 0.65,
        "nordic_warmth": 0.40,
        "japandi_calm": 0.40,
    },
    "terrace": {
        "tropical_escape": 0.85,
        "warm_modern": 0.75,
        "soft_luxury": 0.60,
        "nordic_warmth": 0.55,
        "japandi_calm": 0.45,
    },
    "balcony": {
        "warm_modern": 0.80,
        "tropical_escape": 0.75,
        "japandi_calm": 0.75,
        "nordic_warmth": 0.60,
        "soft_luxury": 0.55,
    },
    "driveway": {
        "warm_modern": 0.85,
        "soft_luxury": 0.80,
        "japandi_calm": 0.60,
        "tropical_escape": 0.45,
        "nordic_warmth": 0.45,
    },
}

# Default matrix used when room type is unknown
_DEFAULT_COMPAT: dict[str, float] = {
    "warm_modern": 0.80,
    "soft_luxury": 0.75,
    "japandi_calm": 0.75,
    "nordic_warmth": 0.60,
    "tropical_escape": 0.55,
}

# ── Signal bonuses ─────────────────────────────────────────────────────────────
# (keyword_fragment, atmosphere_id, bonus_score)
# Applied when the keyword is found in vision_description + user_prompt.

_SIGNAL_BONUSES: list[tuple[str, str, float]] = [
    # Architectural signals
    ("high ceiling",     "soft_luxury",       0.10),
    ("vaulted",          "soft_luxury",       0.08),
    ("small",            "japandi_calm",      0.10),
    ("compact",          "japandi_calm",      0.08),
    ("compact",          "warm_modern",       0.05),
    # Material signals
    ("wood",             "nordic_warmth",     0.10),
    ("wood",             "warm_modern",       0.05),
    ("timber",           "nordic_warmth",     0.08),
    ("timber",           "warm_modern",       0.05),
    ("concrete",         "japandi_calm",      0.05),
    ("marble",           "soft_luxury",       0.10),
    ("travertine",       "warm_modern",       0.10),
    # View/location signals
    ("forest",           "nordic_warmth",     0.08),
    ("tropical",         "tropical_escape",   0.12),
    ("palm",             "tropical_escape",   0.10),
    ("beach",            "tropical_escape",   0.08),
    ("ocean view",       "tropical_escape",   0.10),
    ("urban",            "warm_modern",       0.05),
    # Light signals
    ("white",            "soft_luxury",       0.05),
    ("white",            "japandi_calm",      0.05),
    ("warm light",       "warm_modern",       0.08),
    ("warm light",       "nordic_warmth",     0.05),
    ("fireplace",        "nordic_warmth",     0.12),
    ("fireplace",        "warm_modern",       0.05),
]


def rank_atmospheres(
    room_type: str,
    vision_description: str = "",
    user_prompt: str = "",
    exclude: list[str] | None = None,
) -> list[tuple[str, float]]:
    """
    Return atmospheres ranked by suitability for the given room context.

    Args:
        room_type: canonical room type key
        vision_description: GPT-4o-mini room description
        user_prompt: user's instruction
        exclude: atmosphere IDs to exclude (e.g., current selection)

    Returns:
        List of (atmosphere_id, score) sorted descending by score.
    """
    compat = _BASE_COMPAT.get(room_type, _DEFAULT_COMPAT).copy()
    combined = (vision_description + " " + user_prompt).lower()

    # Apply signal bonuses
    for keyword, atmosphere_id, bonus in _SIGNAL_BONUSES:
        if keyword in combined and atmosphere_id in compat:
            compat[atmosphere_id] = min(1.0, compat[atmosphere_id] + bonus)

    if exclude:
        for atm in exclude:
            compat.pop(atm, None)

    return sorted(compat.items(), key=lambda x: x[1], reverse=True)


def surprise_me(
    room_type: str,
    vision_description: str = "",
    user_prompt: str = "",
    exclude: list[str] | None = None,
) -> str:
    """
    Select the single atmosphere that will create the most emotional impact.

    Picks the top-ranked atmosphere from rank_atmospheres. This is not random —
    it is the highest-confidence recommendation for visual and emotional coherence.

    Returns: atmosphere_id string
    """
    ranked = rank_atmospheres(room_type, vision_description, user_prompt, exclude)
    if ranked:
        return ranked[0][0]
    return "warm_modern"  # safe fallback
