"""
tone_calibration.py — Wave 3.2 tone mode selection and HUMAN_SOFT response generation.

Three tone modes:
  HUMAN_SOFT      — exploratory / open conversation / low-stakes chat
                    Warm, personal, minimal architecture references
  ARCHITECT_LIGHT — design conversation without immediate generation
                    Engaged, thoughtful, asks clarifying questions
  ARCHITECT_ACTIVE — generation-intent confirmed
                    Directive, specific, confident — this is the Wave 2.5 path

HUMAN_SOFT is the only mode with its own response generator here.
ARCHITECT_LIGHT and ARCHITECT_ACTIVE continue to the existing Wave 2.5 path.

Bilingual: English and French.
Deterministic pick via MD5 hash (same pattern as meta_response.py).
"""

from __future__ import annotations
import hashlib
from enum import Enum

from .meta_intent import MetaIntent
from .intent_classifier import ConversationIntent, SubIntent
from .conversation_memory import SessionMemory
from .response_quality import EmotionalContext


class ToneMode(str, Enum):
    HUMAN_SOFT      = "human_soft"
    ARCHITECT_LIGHT = "architect_light"
    ARCHITECT_ACTIVE = "architect_active"


def _pick(options: list[str], seed: str) -> str:
    idx = int(hashlib.md5(seed.encode()).hexdigest(), 16) % len(options)
    return options[idx]


def select_tone_mode(
    meta_intent: MetaIntent,
    sub_intent: SubIntent,
    confidence: float,
    session_memory: SessionMemory,
    emotional_context: EmotionalContext = EmotionalContext.NEUTRAL,
) -> ToneMode:
    """
    Select the appropriate tone mode for a design-layer message.

    Called ONLY when meta_intent is NONE (meta layer already handled social signals).
    OPEN_CONVERSATION is a meta intent and reaches this layer only as NONE
    if the classifier doesn't catch it — treat low-confidence GENERAL the same way.
    """
    # Low-confidence GENERAL → exploratory, no design direction detected
    if sub_intent == SubIntent.GENERAL and confidence < 0.4:
        return ToneMode.HUMAN_SOFT

    # Brief reactions ("interesting", "hmm", "ok") → short ARCHITECT_LIGHT response
    if emotional_context == EmotionalContext.ACKNOWLEDGMENT:
        return ToneMode.ARCHITECT_LIGHT

    # Hesitation in generic context → gentle ARCHITECT_LIGHT (not full generation path)
    if emotional_context == EmotionalContext.HESITATION and sub_intent == SubIntent.GENERAL:
        return ToneMode.ARCHITECT_LIGHT

    # Explicit question or praise intent → ARCHITECT_LIGHT
    if sub_intent in (SubIntent.QUESTION, SubIntent.PRAISE):
        return ToneMode.ARCHITECT_LIGHT

    # Generation path → ARCHITECT_ACTIVE
    return ToneMode.ARCHITECT_ACTIVE


# ── HUMAN_SOFT response pools ─────────────────────────────────────────────────
# These responses are warm and personal. They do NOT reference atmospheres,
# DNA vocabulary, or design mechanics. They feel like a thoughtful person, not a system.

_OPEN_ENDED_EN = [
    "Take your time — I'm here whenever you're ready to start exploring.",
    "No rush at all. What's on your mind?",
    "We can go at whatever pace feels right. What are you thinking about?",
    "Happy to just talk through ideas before we get into anything visual.",
    "That's completely fine — what would you like to explore?",
]

_OPEN_ENDED_FR = [
    "Prenez votre temps — je suis là quand vous êtes prêt à explorer.",
    "Pas de précipitation. À quoi pensez-vous ?",
    "On peut avancer au rythme qui vous convient. Qu'avez-vous en tête ?",
    "On peut simplement discuter avant de passer au visuel.",
    "Pas de problème — qu'aimeriez-vous explorer ?",
]

_GENERAL_SOFT_EN = [
    "Tell me more — what's the feeling you're going for?",
    "I'm listening. What's drawing you toward this space?",
    "What matters most to you in this room?",
]

_GENERAL_SOFT_FR = [
    "Dites-moi en plus — quelle atmosphère recherchez-vous ?",
    "Je vous écoute. Qu'est-ce qui vous attire dans cet espace ?",
    "Qu'est-ce qui compte le plus pour vous dans cette pièce ?",
]

_WITH_CONTEXT_EN = [
    "Noted — what direction are you leaning, even loosely?",
    "That's a good starting point. What would make this space feel right?",
    "Understood. What's the one thing you'd want this room to feel like?",
]

_WITH_CONTEXT_FR = [
    "D'accord — quelle direction envisagez-vous, même à grands traits ?",
    "C'est un bon point de départ. Qu'est-ce qui rendrait cet espace juste ?",
    "Compris. Quelle serait la chose essentielle que vous voulez ressentir dans cette pièce ?",
]


def generate_human_soft_response(
    session_memory: SessionMemory,
    sub_intent: SubIntent,
    seed_extra: str = "",
) -> str:
    """
    Generate a warm, conversational response for HUMAN_SOFT tone mode.

    Does NOT reference atmosphere DNA, materials, or generation mechanics.
    Responds in session_memory.session_language.
    """
    lang = session_memory.session_language
    seed = f"human_soft{sub_intent.value}{lang}{seed_extra}"

    # Choose pool based on context
    if session_memory.is_exploring or session_memory.message_count <= 1:
        pool_en = _OPEN_ENDED_EN
        pool_fr = _OPEN_ENDED_FR
    elif session_memory.atmosphere_mentioned or session_memory.room_type_mentioned:
        pool_en = _WITH_CONTEXT_EN
        pool_fr = _WITH_CONTEXT_FR
    else:
        pool_en = _GENERAL_SOFT_EN
        pool_fr = _GENERAL_SOFT_FR

    options = pool_fr if lang == "fr" else pool_en
    return _pick(options, seed)
