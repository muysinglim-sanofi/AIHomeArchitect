"""
room_classifier.py — V1 room-type inference engine.

Classifies the primary room type from vision description + user prompt.
Also infers secondary visible spaces for multi-space scene intelligence.

Design principle: deterministic, curated keyword scoring. No ML.
Falls back safely to "living_room" when uncertain.
"""

from __future__ import annotations
from dataclasses import dataclass, field


# ── Signal tables ──────────────────────────────────────────────────────────────
# Maps room-type keys to (primary signal keywords, secondary/supporting signals)
# Primary signals: high-confidence indicators
# Secondary signals: weaker indicators, still contribute to score

_ROOM_SIGNALS: dict[str, tuple[list[str], list[str]]] = {
    "living_room": (
        ["sofa", "couch", "armchair", "coffee table", "tv unit", "fireplace", "living room", "lounge"],
        ["open plan", "seating area", "carpet", "curtains", "reception"],
    ),
    "master_bedroom": (
        ["bed ", "bedroom", "headboard", "nightstand", "bedside", "duvet", "mattress", "sleeping", "wardrobe", "closet"],
        ["pillows", "sheets", "ensuite", "dressing table"],
    ),
    "kitchen": (
        ["kitchen", "countertop", "counter top", "cabinet", "island", "stove", "oven", "sink", "fridge", "refrigerator", "hob", "cooker"],
        ["cooking", "dining area", "open plan kitchen", "kitchen island", "cupboards"],
    ),
    "bathroom": (
        ["bathroom", "toilet", "shower", "bathtub", "bath tub", "vanity", "basin", "tiles", "wet room", "ensuite"],
        ["mirror", "towel rail", "taps", "sanitary"],
    ),
    "home_office": (
        ["desk", "office", "study", "workspace", "computer", "monitor", "bookshelf", "work from home"],
        ["shelving", "books", "chair", "work space"],
    ),
    "dining_room": (
        ["dining table", "dining room", "dining chairs", "table and chairs", "dinner table"],
        ["sideboard", "buffet", "wine rack", "dining"],
    ),
    "entrance_hall": (
        ["entrance", "hallway", "foyer", "corridor", "entrance hall", "front door", "vestibule"],
        ["console", "coat", "hooks", "hall"],
    ),
    "facade": (
        ["facade", "exterior", "front of house", "house front", "building front", "outside", "street view", "front elevation"],
        ["render", "cladding", "roof", "windows from outside", "front garden", "driveway view"],
    ),
    "garden": (
        ["garden", "yard", "lawn", "backyard", "front yard", "landscape", "planting", "outdoor space"],
        ["grass", "trees", "shrubs", "flower bed", "patio area"],
    ),
    "pool_area": (
        ["pool", "swimming pool", "infinity pool", "pool deck", "pool area"],
        ["sun lounger", "pool side", "sunbeds"],
    ),
    "terrace": (
        ["terrace", "patio", "outdoor dining", "courtyard", "outdoor living"],
        ["outdoor furniture", "outdoor sofa", "al fresco", "decking"],
    ),
    "balcony": (
        ["balcony", "balconie"],
        ["railing", "outdoor space small", "apartment balcony"],
    ),
    "driveway": (
        ["driveway", "drive", "garage", "car port", "approach"],
        ["gate", "entrance drive", "parking"],
    ),
}

# Visibility indicators — used for secondary space detection
_VISIBILITY_TRIGGERS = [
    "visible", "behind", "through", "in background", "in the background",
    "glimpse", "adjacent", "open to", "connects to", "overlooking",
    "through the glass", "glass door to", "open plan with",
]


# ── Output type ───────────────────────────────────────────────────────────────

@dataclass
class RoomClassification:
    primary_room: str               # canonical room type key
    confidence: float               # 0.0–1.0
    secondary_spaces: list[str]     # other rooms visibly present
    reasoning: str                  # brief explanation for logging


# ── Classifier ────────────────────────────────────────────────────────────────

def classify_room(
    vision_description: str,
    user_prompt: str = "",
    room_type_hint: str = "",
) -> RoomClassification:
    """
    Infer primary room type and secondary visible spaces.

    Args:
        vision_description: GPT-4o-mini description of the source image
        user_prompt: user's natural language instruction (optional)
        room_type_hint: explicit room_type from frontend (if user selected one)

    Returns:
        RoomClassification with primary_room, confidence, secondary_spaces
    """
    # If frontend explicitly provided a room type, trust it — but still infer secondaries
    if room_type_hint.strip():
        from .atmosphere_dna._base import _normalise_room
        primary = _normalise_room(room_type_hint)
        secondaries = _detect_secondary_spaces(vision_description + " " + user_prompt, primary)
        return RoomClassification(
            primary_room=primary,
            confidence=1.0,
            secondary_spaces=secondaries,
            reasoning=f"Explicit user selection: {room_type_hint}",
        )

    combined = (vision_description + " " + user_prompt).lower()
    scores: dict[str, float] = {}

    for room_key, (primary_signals, secondary_signals) in _ROOM_SIGNALS.items():
        score = 0.0
        for sig in primary_signals:
            if sig in combined:
                score += 1.0
        for sig in secondary_signals:
            if sig in combined:
                score += 0.3
        scores[room_key] = score

    if not scores or max(scores.values()) == 0.0:
        return RoomClassification(
            primary_room="living_room",
            confidence=0.2,
            secondary_spaces=[],
            reasoning="No signals detected; defaulting to living_room",
        )

    best_room = max(scores, key=lambda k: scores[k])
    best_score = scores[best_room]
    # Normalise confidence: cap at 1.0, floor at 0.3 for any detection
    confidence = min(1.0, best_score / 3.0) if best_score > 0 else 0.2
    confidence = max(0.3, confidence)

    secondaries = _detect_secondary_spaces(combined, best_room)

    return RoomClassification(
        primary_room=best_room,
        confidence=round(confidence, 2),
        secondary_spaces=secondaries,
        reasoning=f"Top score {best_score:.1f} for '{best_room}'",
    )


def _detect_secondary_spaces(text: str, primary_room: str) -> list[str]:
    """
    Detect rooms that are visibly present in the scene but are not the primary room.
    Returns at most 2 secondary rooms (to control prompt size).
    """
    lower = text.lower()

    # Check whether the text contains any visibility trigger
    has_visibility_trigger = any(t in lower for t in _VISIBILITY_TRIGGERS)
    # Also allow for open-plan descriptions which imply visible secondary spaces
    is_open_plan = any(p in lower for p in ["open plan", "open-plan", "open concept"])

    secondaries: list[str] = []

    for room_key, (primary_signals, _) in _ROOM_SIGNALS.items():
        if room_key == primary_room:
            continue
        for sig in primary_signals:
            if sig in lower:
                # Require visibility indicator unless open plan
                if has_visibility_trigger or is_open_plan:
                    secondaries.append(room_key)
                    break
                # Even without trigger, some signals are strong enough
                # (e.g., "kitchen island in background" doesn't always use "visible")
                elif any(loc in lower for loc in ["background", "back of", "far end", "rear"]):
                    secondaries.append(room_key)
                    break

    # Deduplicate, remove primary, cap at 2
    seen = set()
    result = []
    for r in secondaries:
        if r not in seen and r != primary_room:
            seen.add(r)
            result.append(r)
        if len(result) >= 2:
            break

    return result
