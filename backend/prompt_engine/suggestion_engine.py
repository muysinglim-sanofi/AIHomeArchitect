"""
suggestion_engine.py — Wave 2.5 contextual suggestion chips.

Returns curated follow-up suggestion chips for the current design context.
Chips are atmosphere-specific, room-aware, and iteration-sensitive.

Chips are data — short strings the frontend renders as tappable buttons.
They create conversational momentum and reduce friction toward refinement.

Design rules:
  - 4–8 words per chip
  - Reference actual atmosphere character (not generic design words)
  - Atmosphere-specific vocabulary from DNA — matches what the AI would say
  - No duplicates within a response set
  - Mix generation chips and conversation chips
"""

from __future__ import annotations
from .edit_intent import EditMode
from .intent_classifier import SubIntent


# ── Atmosphere chip tables ─────────────────────────────────────────────────────
# Per atmosphere: curated chips referencing actual DNA materials and character.

_ATM_CHIPS: dict[str, list[str]] = {
    "warm_modern": [
        "Push the lighting warmer",
        "Add more travertine surface",
        "Deepen the oak tones",
        "Reduce visual clutter",
        "More boucle texture",
        "Strengthen the warm plaster",
        "Add a floor lamp",
        "Try a darker evening tone",
        "Keep the existing warmth",
        "More indirect lighting",
    ],
    "japandi_calm": [
        "Increase negative space",
        "More natural ash tones",
        "Remove one element",
        "Add wabi-sabi texture",
        "Fewer decorative objects",
        "Darker floor material",
        "More diffused lighting",
        "Reduce to essentials",
        "Add a single branch detail",
        "Try a lower furniture profile",
    ],
    "soft_luxury": [
        "Layer more bouclé texture",
        "Deepen the marble palette",
        "Add a velvet accent",
        "More champagne brass detail",
        "Soften the lighting further",
        "Push the ivory palette",
        "Add silk curtain weight",
        "Reduce visual contrast",
        "More tactile layering",
        "Try a warmer stone",
    ],
    "nordic_warmth": [
        "Add a sheepskin layer",
        "More warm pine tones",
        "Add candle lighting",
        "Layer more wool texture",
        "Try a white-on-white palette",
        "Add a wood-burning stove",
        "More hygge layering",
        "Bring in more natural light",
        "Add botanical detail",
        "Soften the furniture scale",
    ],
    "dark_contemporary": [
        "Push the contrast further",
        "Add darker stone surface",
        "More bronze accent detail",
        "Increase material depth",
        "Try smoked oak flooring",
        "Add a dramatic pendant",
        "Reduce ambient lighting",
        "More architectural shadow",
        "Deepen the charcoal palette",
        "Add a sculptural object",
    ],
    "nature_retreat": [
        "Add more reclaimed timber",
        "Deepen the stone palette",
        "Add a large specimen plant",
        "More rammed earth texture",
        "Try a darker wood grain",
        "Add natural linen detail",
        "More biophilic layering",
        "Reduce to natural materials only",
        "Add a water element",
        "More organic materiality",
    ],
    "desert_luxe": [
        "Deepen the tadelakt palette",
        "Add more sandstone surface",
        "Try a darker mineral tone",
        "More hammered brass detail",
        "Increase the sculptural weight",
        "Add a carved timber element",
        "Reduce to one material",
        "Try richer terracotta tones",
        "More desert warmth",
        "Push the monolithic quality",
    ],
    "tropical_escape": [
        "Open the space visually",
        "Add more natural rattan",
        "Brighten the natural light",
        "Add tropical plant detail",
        "More whitewash texture",
        "Try louvred timber screens",
        "Add outdoor connection",
        "More casual luxury feel",
        "Bring in sea-facing light",
        "Reduce visual weight",
    ],
}

# ── Room chip tables ───────────────────────────────────────────────────────────
# Room-specific chips that complement atmosphere chips.

_ROOM_CHIPS: dict[str, list[str]] = {
    "living_room": [
        "Rearrange the seating zone",
        "Change the focal wall",
        "Add an artwork layer",
        "Try a different rug",
        "Adjust the curtain height",
    ],
    "master_bedroom": [
        "Change the bedding palette",
        "Adjust the headboard profile",
        "Try softer window treatment",
        "Add a reading corner",
        "Strengthen the bedside lighting",
    ],
    "kitchen": [
        "Change the countertop material",
        "Adjust the cabinet colour",
        "Try open shelf display",
        "Add pendant over island",
        "Change the hardware finish",
    ],
    "bathroom": [
        "Add a freestanding tub",
        "Change the stone palette",
        "Try a different fixture finish",
        "Open the shower area",
        "Add a warming element",
    ],
    "terrace": [
        "Add shade structure",
        "Try outdoor dining layout",
        "Add statement planting",
        "Change the paving material",
        "Add evening lighting layer",
    ],
    "facade": [
        "Adjust the render tone",
        "Change the entrance door",
        "Add facade planting",
        "Try different window framing",
        "Adjust the exterior lighting",
    ],
    "dining_room": [
        "Change the pendant height",
        "Try a different table shape",
        "Adjust the chair upholstery",
        "Add a sideboard element",
        "Change the centrepiece",
    ],
    "entrance_hall": [
        "Change the console detail",
        "Try a different mirror scale",
        "Adjust the arrival lighting",
        "Add a botanical accent",
        "Change the floor material",
    ],
    "home_office": [
        "Adjust the desk material",
        "Try a different chair",
        "Add bookshelf detail",
        "Change the task lighting",
        "Improve cable management",
    ],
    "garden": [
        "Add specimen planting",
        "Change the path material",
        "Add evening uplighting",
        "Try a water feature",
        "Adjust the boundary treatment",
    ],
    "pool_area": [
        "Change the deck material",
        "Adjust the lounger arrangement",
        "Try darker pool liner",
        "Add poolside planting",
        "Change the shade structure",
    ],
    "balcony": [
        "Add a compact seating piece",
        "Change the planting accent",
        "Try a different floor material",
        "Add evening lantern",
        "Adjust the balustrade treatment",
    ],
    "driveway": [
        "Change the paving material",
        "Adjust the gate design",
        "Add arrival planting",
        "Try different boundary treatment",
        "Add entrance lighting",
    ],
}

# ── Universal follow-up chips ──────────────────────────────────────────────────
# These work for any atmosphere × room and provide conversational alternatives.

_UNIVERSAL_CHIPS = [
    "Try a completely different atmosphere",
    "Show me a different lighting approach",
    "Keep everything as is",
    "Push this direction further",
    "Show me the space at evening light",
]

# ── Iteration-specific chips ───────────────────────────────────────────────────

_FIRST_VISION_EXTRAS = [
    "Push this direction further",
    "Try a completely different atmosphere",
    "Make it more minimal",
    "Make it more luxurious",
]

_LATER_ITERATION_EXTRAS = [
    "Keep this as my final version",
    "Undo the last change",
    "Show me a different direction",
]


# ── Engine ─────────────────────────────────────────────────────────────────────

def get_suggestion_chips(
    atmosphere_id: str,
    room_type: str,
    iteration: int,
    edit_mode: EditMode,
    sub_intent: SubIntent = SubIntent.GENERAL,
    count: int = 4,
) -> list[str]:
    """
    Return curated suggestion chips for the current design context.

    Selection strategy:
      - 2 atmosphere-specific chips (most relevant to current DNA character)
      - 1 room-specific chip (specific to room type)
      - 1 universal or iteration chip

    Returns `count` chips, deduplicated.
    """
    result: list[str] = []
    seen: set[str] = set()

    def _add(chip: str) -> None:
        if chip not in seen and len(result) < count:
            seen.add(chip)
            result.append(chip)

    atm_pool = _ATM_CHIPS.get(atmosphere_id, [])
    room_pool = _ROOM_CHIPS.get(room_type, [])

    # Iteration and mode influence which chips surface first
    if iteration == 1:
        # After first vision: explore and push are the natural next moves
        for chip in _FIRST_VISION_EXTRAS[:2]:
            _add(chip)
        for chip in atm_pool[:2]:
            _add(chip)
        for chip in room_pool[:1]:
            _add(chip)
    elif edit_mode == EditMode.LOCAL_EDIT:
        # After a local edit: offer more specific edits + refinement
        for chip in atm_pool[2:4]:
            _add(chip)
        for chip in room_pool[:2]:
            _add(chip)
        _add(_LATER_ITERATION_EXTRAS[2])
    elif edit_mode == EditMode.STYLE_REFINEMENT:
        # After refinement: deeper refinement + contrast option
        for chip in atm_pool[:3]:
            _add(chip)
        for chip in room_pool[:1]:
            _add(chip)
    else:
        # General: balanced mix
        for chip in atm_pool[:2]:
            _add(chip)
        for chip in room_pool[:1]:
            _add(chip)
        _add(_UNIVERSAL_CHIPS[0])

    # Fill remaining slots if not at count yet
    for chip in atm_pool:
        if len(result) >= count:
            break
        _add(chip)
    for chip in room_pool:
        if len(result) >= count:
            break
        _add(chip)
    for chip in _UNIVERSAL_CHIPS:
        if len(result) >= count:
            break
        _add(chip)

    return result[:count]
