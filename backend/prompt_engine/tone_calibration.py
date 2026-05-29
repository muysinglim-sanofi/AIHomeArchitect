"""
tone_calibration.py — Wave 3.2 + Wave 4.11a tone mode selection.

Four tone modes (Wave 4.11a adds CONFIDENT_RECOMMENDATION):
  HUMAN_SOFT             — exploratory / open conversation / low-stakes chat
                           Warm, personal, minimal architecture references
  ARCHITECT_LIGHT        — design conversation without immediate generation
                           Engaged, thoughtful, asks clarifying questions
  ARCHITECT_ACTIVE       — generation-intent confirmed
                           Directive, specific, confident — the Wave 2.5 path
  CONFIDENT_RECOMMENDATION — Wave 4.11a — architect takes a clearer position
                           when (V2+ AND confidence ≥ 0.7 AND no hesitation
                           AND no recent CORRECTION / FRUSTRATION). The
                           opening phrase is intentionally professional,
                           never confrontational — per user review of Day 4 :
                             YES : "I would be careful with that direction."
                             YES : "One thing I'd watch carefully here…"
                             YES : "There's a trade-off worth considering."
                             NO  : "Honestly — I'd push back on this one."
                             NO  : "I'd strongly oppose…"
                           Professional guidance, not contradiction.

HUMAN_SOFT and CONFIDENT_RECOMMENDATION are the two modes with their own
opening / response generators here. ARCHITECT_LIGHT and ARCHITECT_ACTIVE
continue to the existing Wave 2.5 path inside architect_response.py.

Bilingual: English and French ; CONFIDENT_RECOMMENDATION openings are
EN-only Phase 1 per Wave 4.11a Q1 (architectural critique layer).

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
    # Wave 4.11a — escalation of ARCHITECT_ACTIVE when the conditions for
    # genuine professional confidence are met. Never fires on a V1 brief
    # (the architect is still listening, not yet recommending).
    CONFIDENT_RECOMMENDATION = "confident_recommendation"


# Wave 4.11a — confidence threshold for escalating to
# CONFIDENT_RECOMMENDATION. Tuned conservative (0.7) so the mode fires
# only when the design signal is unambiguous.
_CONFIDENT_THRESHOLD = 0.7


# Wave 4.11a — meta intents that, if present in the last 3 user turns,
# suppress the CONFIDENT escalation. Correction means the user disagreed
# with the architect's previous take ; frustration means the architect's
# tone needs to soften, not strengthen. Both block confidence.
def _has_recent_blocker(recent: list) -> bool:
    """Return True if recent meta intents include CORRECTION or FRUSTRATION."""
    if not recent:
        return False
    blockers = {MetaIntent.CORRECTION, MetaIntent.FRUSTRATION}
    return any(m in blockers for m in recent if m is not None)


def _pick(options: list[str], seed: str) -> str:
    idx = int(hashlib.md5(seed.encode()).hexdigest(), 16) % len(options)
    return options[idx]


def select_tone_mode(
    meta_intent: MetaIntent,
    sub_intent: SubIntent,
    confidence: float,
    session_memory: SessionMemory,
    emotional_context: EmotionalContext = EmotionalContext.NEUTRAL,
    iteration: int = 0,                       # Wave 4.11a
    recent_meta_intents: list | None = None,  # Wave 4.11a — last 3 turns
) -> ToneMode:
    """
    Select the appropriate tone mode for a design-layer message.

    Called ONLY when meta_intent is NONE (meta layer already handled social signals).
    OPEN_CONVERSATION is a meta intent and reaches this layer only as NONE
    if the classifier doesn't catch it — treat low-confidence GENERAL the same way.

    Wave 4.11a additions :
      • New ToneMode.CONFIDENT_RECOMMENDATION escalates above ARCHITECT_ACTIVE
        when the architect can genuinely take a clearer position.
      • `iteration` and `recent_meta_intents` are new parameters used only by
        the CONFIDENT escalation. They default such that omitting them
        preserves the pre-4.11a behaviour byte-for-byte.
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

    # Generation path → ARCHITECT_ACTIVE (with Wave 4.11a CONFIDENT escalation)
    base = ToneMode.ARCHITECT_ACTIVE

    # Wave 4.11a — CONFIDENT_RECOMMENDATION escalation. Conservative gate :
    # V2+ AND confidence ≥ 0.7 AND no hesitation in the current message AND
    # no CORRECTION/FRUSTRATION in the last 3 turns. The user explicitly
    # asked for "professional guidance, not contradiction" — these
    # conditions ensure the mode only activates when the conversation has
    # actually earned that level of architect voice.
    if (
        iteration >= 2
        and confidence >= _CONFIDENT_THRESHOLD
        and emotional_context != EmotionalContext.HESITATION
        and not _has_recent_blocker(recent_meta_intents or [])
    ):
        return ToneMode.CONFIDENT_RECOMMENDATION

    return base


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


# ── Wave 4.11a — CONFIDENT_RECOMMENDATION openings ──────────────────────────
#
# Per user review (Day 4) : these openings must read as professional
# guidance, never as contradiction. The pool was curated to avoid any
# pushback / argument vocabulary ("honestly", "I'd push back", "I'd
# strongly oppose", "no offence but…") and to favour cautious-but-
# committed phrasing.
#
# The orchestrator in architect_response.py (Day 6) prepends ONE of
# these phrases to the architect's main response when tone_mode ==
# CONFIDENT_RECOMMENDATION. The rest of the response (trade-off,
# alternatives, etc.) stays composed as in ARCHITECT_ACTIVE — the
# opening is the only mode-specific element.
#
# EN-only Phase 1 (Wave 4.11a Q1 — architectural critique layer).

_CONFIDENT_OPENINGS_EN = [
    "I would be careful with that direction.",
    "One thing I'd watch carefully here —",
    "There's a trade-off worth considering.",
    "If I may guide here —",
    "In this room I would lean differently.",
    "Worth pausing on this one for a moment.",
    "Let me flag a consideration on this direction.",
    "I would recommend a small pivot here.",
]


def generate_confident_opening(seed_extra: str = "") -> str:
    """
    Return one architect-voice opening phrase suitable to prepend before
    a CONFIDENT_RECOMMENDATION-mode response.

    Pure phrase only — no trailing punctuation beyond what the phrase
    already carries. Callers compose the rest of the response and rely
    on the natural sentence flow to integrate.

    Deterministic pick (MD5 seed) so the same conversation context
    surfaces the same opening within a single turn ; varies across
    turns thanks to the seed_extra.

    Phase 1 EN-only ; if a future wave adds KM, switch the pool here
    based on session_memory.session_language.
    """
    return _pick(_CONFIDENT_OPENINGS_EN, f"confident_open_{seed_extra}")


def confident_opening_pool() -> list[str]:
    """Expose the pool for tests / introspection."""
    return list(_CONFIDENT_OPENINGS_EN)


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
