"""
Ayden — Design Knowledge module (the "Designer Brain" as durable data).

This is the code form of AYDEN_DESIGN_PRINCIPLES.md §4 (invariants) and §5
(per-room priorities / common errors / default posture). It is the part of the
cognitive system that "survives the model": pure data + accessors, NO LLM, NO
image, NO behaviour. The Designer Voice (designer_voice.py) renders it into a
short prompt ; tomorrow's engine reuses the same brain.

Scope: conversational reasoning only. Does NOT touch the image pipeline / DNA /
STAGE / generation prompts.
"""
from __future__ import annotations

from typing import Dict, List

# §4 — global invariants Ayden defends by default (may yield to an explicit
# user constraint/taste, but never silently — name the trade-off).
INVARIANTS: List[str] = [
    "the room's focal point",
    "clear, unobstructed circulation",
    "natural light (never block a window without a strong reason)",
    "right scale (no furniture that crushes the space)",
    "sightlines from the positions of use",
    "overall visual balance",
]


# §5 — per-room briefs. `priorities` is ORDERED: the first dominates the verdict.
_ROOM_BRIEFS: Dict[str, dict] = {
    "living_room": {
        "always_think": ["focal point", "sightlines from the sofa", "circulation", "light", "symmetry"],
        "priorities": ["focal point", "light", "circulation"],
        "common_errors": [
            "a TV that kills the main axis",
            "a TV facing a window (backlight)",
            "a TV that forces a badly-placed sofa",
        ],
        "posture": "Keep one clear focal point; the TV and a fireplace/window must not fight for the main wall.",
    },
    "kitchen": {
        "always_think": ["work triangle (sink / cooktop / fridge)", "circulation", "view from the living area (open plans)", "conviviality"],
        "priorities": ["work triangle", "circulation", "view"],
        "common_errors": ["an island that blocks the triangle", "storage gained at the cost of passage"],
        "posture": "Function leads; aesthetics follow function.",
    },
    "bedroom": {
        "always_think": ["the bed as the main element", "intimacy", "light", "circulation around the bed"],
        "priorities": ["bed primacy", "circulation", "light"],
        "common_errors": ["a bed off-centre for no reason", "access blocked on one side", "too much furniture breaking the calm"],
        "posture": "A bedroom is for rest — sobriety and symmetry around the bed.",
    },
    "bathroom": {
        "always_think": ["comfort", "maintenance", "materials (humidity)", "light"],
        "priorities": ["function / maintenance", "materials", "light"],
        "common_errors": ["materials that age badly in a humid room", "cramped circulation"],
        "posture": "Durability and clarity before effect.",
    },
    "dining_room": {
        "always_think": ["the table as the centre", "circulation around the chairs", "conviviality", "light (a centred pendant)"],
        "priorities": ["table / centre", "circulation", "light"],
        "common_errors": ["a table too big for the circulation", "an off-centre pendant"],
        "posture": "The table anchors the room; everything serves gathering around it.",
    },
    "office": {
        "always_think": ["light (visual fatigue)", "ergonomics", "concentration", "storage"],
        "priorities": ["light", "ergonomics", "storage"],
        "common_errors": ["a desk facing away from the light", "screen glare from a window behind/opposite"],
        "posture": "Light and ergonomics first — the room must be comfortable to work in for hours.",
    },
    "exterior": {
        "always_think": ["usage (passage, rest, meals)", "shade", "view", "continuity with the interior"],
        "priorities": ["usage", "shade", "view"],
        "common_errors": ["furniture that blocks the main passage", "no shade where people sit"],
        "posture": "Lead with how the space is used, then protect the view and comfort.",
    },
}

# Map the app's room_type ids/labels onto a brief key.
_ROOM_ALIASES: Dict[str, str] = {
    "living_room": "living_room", "living": "living_room", "livingroom": "living_room",
    "salon": "living_room", "lounge": "living_room", "family_room": "living_room",
    "kitchen": "kitchen", "cuisine": "kitchen",
    "bedroom": "bedroom", "master_bedroom": "bedroom", "chambre": "bedroom", "guest_bedroom": "bedroom",
    "bathroom": "bathroom", "salle_de_bain": "bathroom", "ensuite": "bathroom", "powder_room": "bathroom",
    "dining_room": "dining_room", "dining": "dining_room", "salle_a_manger": "dining_room",
    "office": "office", "home_office": "office", "bureau": "office", "study": "office",
    "garden": "exterior", "terrace": "exterior", "balcony": "exterior", "patio": "exterior",
    "pool_area": "exterior", "pool": "exterior", "driveway": "exterior", "facade": "exterior",
    "outdoor": "exterior", "exterior": "exterior",
}


def _brief_key(room_type: str) -> str:
    key = (room_type or "").strip().lower().replace(" ", "_").replace("-", "_")
    return _ROOM_ALIASES.get(key, "")


def get_design_brief(room_type: str) -> dict:
    """Return the structured brief for a room, or a generic one for unknown rooms."""
    key = _brief_key(room_type)
    if key and key in _ROOM_BRIEFS:
        return {"room_key": key, **_ROOM_BRIEFS[key]}
    # generic fallback — reason on the universal invariants
    return {
        "room_key": "",
        "always_think": ["focal point", "circulation", "light", "scale", "balance"],
        "priorities": ["focal point", "circulation", "light"],
        "common_errors": ["furniture that crushes the space", "a blocked walking path"],
        "posture": "Reason from the general principles when the room type is unclear.",
    }


def render_brief_for_prompt(room_type: str) -> str:
    """Compact, prompt-ready text block of the brain for this room. English
    (internal knowledge); the Voice renders the answer in the user's language."""
    b = get_design_brief(room_type)
    lines = [
        "Invariants you protect by default (yield only to an explicit user "
        "wish, and then name the trade-off): " + "; ".join(INVARIANTS) + ".",
        "Priorities for this room (the FIRST dominates the verdict): "
        + " > ".join(b["priorities"]) + ".",
        "Watch for these common mistakes: " + "; ".join(b["common_errors"]) + ".",
        "Default posture: " + b["posture"],
    ]
    return "\n".join(lines)
