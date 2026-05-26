"""
architect_response.py — Wave 2.5 architect personality layer.

Generates short, architect-voiced AI companion messages and chat responses.
Reads from the frozen DNA system for atmosphere-specific vocabulary.
Never modifies DNA or prompt composition.

Design principle: responses must feel considered, not generated.
The AI sounds like a senior interior architect — specific, restrained, confident.
It references actual design decisions (materials, atmosphere character, spatial logic).
It never exposes the prompt system, DNA structure, or generation mechanics.

Response length target: 2–5 sentences. Never a paragraph.
"""

from __future__ import annotations
import hashlib
from typing import Optional

from .edit_intent import EditMode
from .refinement_memory import RefinementState
from .intent_classifier import SubIntent
from .atmosphere_dna import get_core, get_room_dna


# ── Atmosphere personality layer ───────────────────────────────────────────────
# Tone modifiers per atmosphere. These shape word choice and emotional register.

_ATM_TONE: dict[str, dict] = {
    "warm_modern": {
        "adj": "warm",
        "quality": "warm and grounded",
        "direction_word": "warmth",
        "material_verb": "grounds",
        "follow_q": [
            "What element would you push further?",
            "Does the warmth feel right, or should we adjust it?",
            "What would you change next?",
        ],
    },
    "japandi_calm": {
        "adj": "considered",
        "quality": "calm and restrained",
        "direction_word": "stillness",
        "material_verb": "anchors",
        "follow_q": [
            "Does the empty space feel intentional, or does it need something?",
            "Would you reduce further, or is this the right balance?",
            "What would you remove or keep?",
        ],
    },
    "soft_luxury": {
        "adj": "refined",
        "quality": "soft and layered",
        "direction_word": "softness",
        "material_verb": "defines",
        "follow_q": [
            "Would you add more texture, or keep the palette this quiet?",
            "Does the softness feel right, or should it be more subtle?",
            "What would you adjust next?",
        ],
    },
    "nordic_warmth": {
        "adj": "cozy",
        "quality": "warm and lived-in",
        "direction_word": "coziness",
        "material_verb": "creates",
        "follow_q": [
            "Would you add more texture, or keep it this simple?",
            "Does the warmth feel right, or should we push it further?",
            "What would make this feel more like home?",
        ],
    },
    "nature_retreat": {
        "adj": "earthy",
        "quality": "natural and grounded",
        "direction_word": "organic quality",
        "material_verb": "grounds",
        "follow_q": [
            "Would you add more texture, or let the materials breathe?",
            "Does the natural quality feel right?",
            "What element would you bring closer to nature?",
        ],
    },
    "desert_luxe": {
        "adj": "sculptural",
        "quality": "mineral and quiet",
        "direction_word": "weight",
        "material_verb": "sculpts",
        "follow_q": [
            "Would you push the mineral palette further, or add a warm contrast?",
            "Does the weight feel right?",
            "What would you refine next?",
        ],
    },
    "tropical_escape": {
        "adj": "breezy",
        "quality": "open and light",
        "direction_word": "openness",
        "material_verb": "lightens",
        "follow_q": [
            "Would you open it up further, or add more warmth?",
            "Does the casual feel read right?",
            "What would make this feel more connected to the outside?",
        ],
    },
}

_DEFAULT_TONE: dict = {
    "adj": "refined",
    "quality": "considered and atmospherically coherent",
    "direction_word": "direction",
    "material_verb": "defines",
    "follow_q": ["What would you refine next?"],
}


# ── Helpers ────────────────────────────────────────────────────────────────────

def _tone(atmosphere_id: str) -> dict:
    return _ATM_TONE.get(atmosphere_id, _DEFAULT_TONE)


def _pick(options: list[str], seed: str) -> str:
    """Deterministic pick from a list using a string seed. Avoids random — keeps results reproducible."""
    idx = int(hashlib.md5(seed.encode()).hexdigest(), 16) % len(options)
    return options[idx]


def _atm_name(atmosphere_id: str) -> str:
    return atmosphere_id.replace("_", " ").title()


def _room_name(room_type: str) -> str:
    return room_type.replace("_", " ").lower()


def _material_hint(atmosphere_id: str, room_type: str) -> str:
    """Pull first material from room DNA, fall back to atmosphere core palette."""
    dna = get_room_dna(atmosphere_id, room_type)
    if dna and dna.material_palette:
        return dna.material_palette[0]
    core = get_core(atmosphere_id)
    if core and core.material_palette:
        return core.material_palette[0]
    return "natural materials"


def _furniture_hint(atmosphere_id: str, room_type: str) -> str:
    """Pull first furniture piece from room DNA."""
    dna = get_room_dna(atmosphere_id, room_type)
    if dna and dna.furniture_language:
        raw = dna.furniture_language[0]
        # Trim to essentials — first 5 words max for readability
        return " ".join(raw.split()[:5])
    return "primary furniture"


def _lighting_hint(atmosphere_id: str, room_type: str) -> str:
    """Pull lighting note from room DNA."""
    dna = get_room_dna(atmosphere_id, room_type)
    if dna:
        # Trim to first clause only
        light = dna.lighting_behavior.split(";")[0].split(".")[0].strip()
        return light.lower()
    core = get_core(atmosphere_id)
    if core:
        return core.lighting_behavior.split(".")[0].strip().lower()
    return "warm ambient lighting"


import re as _re
_LEADING_JUNK_RE = _re.compile(r"^(and|but|or|also|then|brought\s+in|added)[,\s]+", _re.IGNORECASE)


def _clean_for_caption(text: str, max_len: int = 55) -> str:
    """Clean raw instruction text so it reads naturally in a caption."""
    if not text:
        return ""
    text = text.strip()
    text = _LEADING_JUNK_RE.sub("", text)
    text = text[:max_len]
    if " " in text[max_len // 2:]:
        text = text[:text.rfind(" ", 0, max_len)]
    return text[0].upper() + text[1:] if text else ""


def _secondary_space_note(
    atmosphere_id: str,
    secondary_spaces: list[str],
) -> Optional[str]:
    """Generate a visible-space coherence note if secondary rooms are present."""
    if not secondary_spaces:
        return None
    room = secondary_spaces[0]
    room_display = room.replace("_", " ")
    return f"The {room_display} in the background should stay consistent — same tone and materials throughout."


# ── Generation response (post-render message) ─────────────────────────────────

def generate_architect_response(
    atmosphere_id: str,
    room_type: str,
    iteration: int,
    edit_mode: EditMode,
    refinement_state: RefinementState,
    sub_intent: SubIntent,
    secondary_spaces: list[str],
    user_message: str,
) -> str:
    """
    Generate the architect companion message shown after image generation.

    Replaces the generic compose_result_message(). References actual DNA vocabulary.
    Returns a short, architect-voiced response — never more than 4 sentences.
    """
    tone = _tone(atmosphere_id)
    atm = _atm_name(atmosphere_id)
    room = _room_name(room_type)
    material = _material_hint(atmosphere_id, room_type)
    furniture = _furniture_hint(atmosphere_id, room_type)
    lighting = _lighting_hint(atmosphere_id, room_type)
    seed = f"{atmosphere_id}{room_type}{iteration}{sub_intent}"

    # ── Vision 1 — first render ───────────────────────────────────────────────
    if iteration == 1 or edit_mode == EditMode.FIRST_VISION:
        follow_q = _pick(tone["follow_q"], seed)
        space_note = _secondary_space_note(atmosphere_id, secondary_spaces)

        _V1_OPTIONS = [
            f"The {atm} direction is in — {tone['quality']}.",
            f"That's the {atm} direction — warm and grounded. {follow_q}",
            f"The {atm} atmosphere is set.",
        ]
        lines = [_pick(_V1_OPTIONS[:1], seed)]  # keep first for predictability
        if space_note:
            lines.append(space_note)
        lines.append(follow_q)
        return " ".join(lines)

    # ── Local edit ────────────────────────────────────────────────────────────
    if edit_mode == EditMode.LOCAL_EDIT:
        follow_q = _pick(tone["follow_q"], seed + "local")
        return f"Done — the {atm} atmosphere is still intact. {follow_q}"

    # ── Structural transformation ─────────────────────────────────────────────
    if edit_mode == EditMode.STRUCTURAL_TRANSFORMATION:
        follow_q = _pick(tone["follow_q"], seed + "struct")
        return (
            f"The architectural change is in — the {room} reads differently now. "
            f"{follow_q}"
        )

    # ── Style refinement — with specific what-changed awareness ──────────────
    follow_q = _pick(tone["follow_q"], seed + "refine")

    if refinement_state.latest:
        # Use short cleaned summary, not raw truncation
        direction = _clean_for_caption(refinement_state.latest, 55)
        if direction:
            return f"This version feels calmer. {follow_q}"

    return (
        f"The {atm} direction is coming together. {follow_q}"
    )


# ── Chat response (no generation triggered) ───────────────────────────────────

_QUESTION_RESPONSES: dict[str, list[str]] = {
    "warm_modern": [
        "In Warm Modern, it usually comes down to the lighting. Warm indirect sources change the whole feel — overhead light tends to flatten things.",
        "The Warm Modern direction works best when the palette stays simple — oak, travertine, plaster. More materials start competing.",
        "With Warm Modern, one good material choice at a larger scale reads better than several smaller ones fighting each other.",
    ],
    "japandi_calm": [
        "In Japandi, the empty space is a design choice, not a gap. What you leave out matters as much as what you put in.",
        "This direction works best when you fully commit to restraint. One thing that doesn't fit tends to pull the whole room off.",
        "If you're wondering whether to add something, the Japandi answer is usually no.",
    ],
    "soft_luxury": [
        "In Soft Luxury, the interest comes from texture and surface depth, not colour. Ivory and bone are the palette — what changes is the feel.",
        "The direction works best with diffused, perimeter lighting. Direct overhead light kills the softness.",
        "With Soft Luxury, colour restraint is the point — the richness lives in the materials themselves.",
    ],
    "nordic_warmth": [
        "In Nordic Warmth, lighting is the main tool. The hygge feeling is mostly about warm, layered light sources.",
        "This direction works best with materials that look better with use — pine, linen, wool. Things that age well.",
        "With Nordic Warmth, the goal is a space that feels lived-in, not arranged.",
    ],
    "nature_retreat": [
        "In Nature Retreat, the material order is: stone, then timber, then textile. Natural over processed.",
        "This direction reads best when the materials are actually what they look like. No printed wood grain or imitation stone.",
        "With Nature Retreat, one or two large plants read better than a collection. The space earns the nature.",
    ],
    "desert_luxe": [
        "In Desert Luxe, the texture is the luxury. Tadelakt plaster and sandstone — the quality lives in the surface.",
        "This direction works best when one material does everything. Multiple materials competing dilutes the feeling.",
        "With Desert Luxe, the less you add, the stronger it gets.",
    ],
    "tropical_escape": [
        "In Tropical Escape, the openness is structural — the space should feel like it breathes outward.",
        "This direction works best with a restrained palette. The tropical feeling comes from the openness, not the decoration.",
        "With Tropical Escape, the goal is effortless — not designed.",
    ],
}

_GENERIC_QUESTIONS = [
    "It depends on what you're going for — visual weight, warmth, or spatial balance each point in different directions.",
    "Most of the time, removing something reads better than adding. Simpler usually feels more confident.",
    "The material itself is rarely the issue — it's usually how it relates to everything else around it.",
]

_PRAISE_RESPONSES: dict[str, list[str]] = {
    "warm_modern": [
        "Good — the warmth is coming through well. What would you change next?",
        "This feels balanced. I'd push the lighting next if you want to take it further.",
    ],
    "japandi_calm": [
        "The restraint is landing well. This is the right direction.",
        "The calm is reading. What would you adjust next?",
    ],
    "soft_luxury": [
        "The softness feels right here. What would you refine next?",
        "This is working well. What's the next move?",
    ],
    "nordic_warmth": [
        "This feels warm and lived-in — that's exactly the right quality.",
        "The coziness is there. What would make it feel even more like home?",
    ],
    "nature_retreat": [
        "The natural quality is landing well. What would you add or take out?",
        "This feels grounded. I'd look at the planting next if you want more of that feeling.",
    ],
    "desert_luxe": [
        "The mineral quality reads well — strong without being cold.",
        "The weight is right. What would you push further?",
    ],
    "tropical_escape": [
        "The openness reads well — casual but considered.",
        "This feels right. What would you change next?",
    ],
}

_GENERIC_PRAISE = [
    "Good. What would you push next?",
    "This is working. What's the next move?",
    "That's landing well. What would you change?",
]

# ── Functional / structural first responses ───────────────────────────────────
# When the user asks about a spatial/functional change, lead with spatial
# acknowledgment — not style. Function before atmosphere.

_STRUCTURAL_RESPONSES: dict[str, list[str]] = {
    "warm_modern": [
        "That changes how the zone reads — the whole spatial logic shifts with it.",
        "That's a real spatial change. The warmth can follow, but the layout moves first.",
        "Understood — the zone function changes, and the atmosphere adapts around it.",
    ],
    "japandi_calm": [
        "That's a genuine spatial shift — the restraint stays, but the zone logic changes.",
        "The functional change is clear. The Japandi calm can hold across the new zone too.",
        "Understood — the zone purpose changes. The stillness stays.",
    ],
    "soft_luxury": [
        "That changes the zone identity — the softness can follow into the new function.",
        "A real spatial transformation. The luxury quality transfers to the new zone.",
        "The zone function changes. The softness of the space follows it.",
    ],
    "nordic_warmth": [
        "That changes the zone use — the warmth can stay consistent through the shift.",
        "A real spatial change. The cozy quality transfers to the new zone arrangement.",
        "The zone function changes. The warm Nordic feel holds through it.",
    ],
    "nature_retreat": [
        "That shifts the zone use — the natural quality stays through the change.",
        "A genuine spatial change. The organic feeling transfers to the new zone.",
        "The zone function changes. The natural character holds.",
    ],
    "desert_luxe": [
        "That changes the zone logic — the mineral quality stays through the shift.",
        "A real spatial change. The sculptural weight follows the new zone function.",
        "The zone purpose shifts. The desert calm transfers.",
    ],
    "tropical_escape": [
        "That shifts how the zone reads — the openness stays through the change.",
        "A real spatial change. The breezy quality transfers to the new arrangement.",
        "The zone purpose changes. The casual feeling holds.",
    ],
}

_GENERIC_STRUCTURAL_RESPONSES = [
    "That's a genuine spatial change — the zone logic shifts with it.",
    "Understood — the zone function changes. The atmosphere follows.",
    "That changes how the space reads spatially. Everything around it adjusts.",
]


def generate_chat_response(
    user_message: str,
    atmosphere_id: str,
    room_type: str,
    sub_intent: SubIntent,
    secondary_spaces: list[str],
    refinement_state: RefinementState,
) -> str:
    """
    Generate an architect response for a chat-only message (no generation triggered).

    For QUESTION sub_intent: answer the design question from an architect perspective.
    For PRAISE sub_intent: acknowledge and redirect toward next design move.
    For MIXED/GENERAL: give a brief architectural opinion, offer a direction.
    """
    tone = _tone(atmosphere_id)
    material = _material_hint(atmosphere_id, room_type)
    seed = f"{atmosphere_id}{room_type}{sub_intent}{user_message[:20]}"

    if sub_intent == SubIntent.PRAISE:
        options = _PRAISE_RESPONSES.get(atmosphere_id, _GENERIC_PRAISE)
        response = _pick(options, seed)
        space_note = _secondary_space_note(atmosphere_id, secondary_spaces)
        if space_note:
            return f"{response} {space_note}"
        return response

    if sub_intent == SubIntent.QUESTION:
        options = _QUESTION_RESPONSES.get(atmosphere_id, _GENERIC_QUESTIONS)
        response = _pick(options, seed)
        space_note = _secondary_space_note(atmosphere_id, secondary_spaces)
        if space_note:
            return f"{response} {space_note}"
        return response

    # STRUCTURAL_CHANGE / FUNCTIONAL_REASSIGNMENT — spatial change first, style second
    if sub_intent == SubIntent.STRUCTURAL_CHANGE:
        options = _STRUCTURAL_RESPONSES.get(atmosphere_id, _GENERIC_STRUCTURAL_RESPONSES)
        response = _pick(options, seed)
        space_note = _secondary_space_note(atmosphere_id, secondary_spaces)
        if space_note:
            return f"{response} {space_note}"
        return response

    # MIXED or GENERAL — brief, natural directional comment
    follow_q = _pick(tone["follow_q"], seed)
    _GENERAL_RESPONSES = [
        f"Yeah, that direction makes sense. {follow_q}",
        f"That could work well here. {follow_q}",
        f"Worth trying. {follow_q}",
    ]
    return _pick(_GENERAL_RESPONSES, seed + "gen")


def generate_mixed_response(
    user_message: str,
    atmosphere_id: str,
    room_type: str,
    sub_intent: SubIntent,
) -> str:
    """
    For MIXED intent: architect answers the question and offers a generation direction.
    Returns the conversational part only — caller appends the suggestion chips.
    """
    tone = _tone(atmosphere_id)
    atm = _atm_name(atmosphere_id)
    material = _material_hint(atmosphere_id, room_type)
    seed = f"mixed{atmosphere_id}{room_type}{user_message[:20]}"
    follow_q = _pick(tone["follow_q"], seed)

    if sub_intent == SubIntent.REFINE_ATMOSPHERE:
        return (
            f"That direction would deepen the {atm} character — "
            f"the {tone['direction_word']} would read more clearly. "
            f"I can show you what that looks like, or we can discuss further. "
            f"{follow_q}"
        )

    if sub_intent == SubIntent.LOCAL_EDIT:
        return (
            f"That change would work well here — "
            f"the {material} provides the right context for it. "
            "Worth generating to see how it sits in the space."
        )

    return (
        f"That is a reasonable direction for the {atm} approach. "
        f"I can take it further if you want to see it — "
        "or we can refine the idea first."
    )
