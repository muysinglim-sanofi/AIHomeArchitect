"""
conversation_memory.py — Wave 3.2 session memory snapshot.

Extracts a lightweight session context from conversation history.
Stateless: rebuilt on every request. No DB or cache required.

Captures only what is observable from the message stream:
  - session_language: last detected language (from meta or design messages)
  - atmosphere_mentioned: most recent atmosphere/style user named
  - room_type_mentioned: most recent room type user named
  - keep_constraints: things user explicitly wants to preserve
  - avoid_constraints: things user explicitly does not want
  - current_direction: latest design direction stated
  - last_topic: topic of the most recent user message
  - message_count: total user messages so far
  - is_exploring: True if session shows no committed direction yet
"""

from __future__ import annotations
import re
from dataclasses import dataclass, field


@dataclass
class SessionMemory:
    session_language: str = "en"
    atmosphere_mentioned: str = ""
    room_type_mentioned: str = ""
    keep_constraints: list[str] = field(default_factory=list)
    avoid_constraints: list[str] = field(default_factory=list)
    current_direction: str = ""
    last_topic: str = ""
    message_count: int = 0
    is_exploring: bool = False


# ── Lightweight extractors ────────────────────────────────────────────────────

_ATMOSPHERE_KEYWORDS = {
    "warm modern": "warm_modern",
    "warm_modern": "warm_modern",
    "japandi": "japandi_calm",
    "calm": "japandi_calm",
    "soft luxury": "soft_luxury",
    "soft_luxury": "soft_luxury",
    "organic": "organic_warmth",
    "organic warmth": "organic_warmth",
    "scandinavian": "scandinavian_light",
    "scandi": "scandinavian_light",
    "nordic": "scandinavian_light",
    "urban": "urban_edge",
    "industrial": "urban_edge",
    "coastal": "coastal_fresh",
    "mediterranean": "mediterranean_sun",
    "art deco": "art_deco_revival",
    "deco": "art_deco_revival",
    "wabi sabi": "wabi_sabi",
    "wabi-sabi": "wabi_sabi",
    "maximalist": "eclectic_maximalism",
    "eclectic": "eclectic_maximalism",
}

_ROOM_KEYWORDS = {
    "living room": "living_room", "salon": "living_room", "lounge": "living_room",
    "bedroom": "bedroom", "chambre": "bedroom",
    "kitchen": "kitchen", "cuisine": "kitchen",
    "bathroom": "bathroom", "salle de bain": "bathroom",
    "dining room": "dining_room", "salle à manger": "dining_room",
    "office": "home_office", "bureau": "home_office", "workspace": "home_office",
    "entrance": "entrance_hall", "hallway": "entrance_hall", "entrée": "entrance_hall",
}

_KEEP_RE = re.compile(
    r"\b(keep|preserve|maintain|retain|leave|love\s+the|like\s+the|garde[rz]?|conserver)\b",
    re.IGNORECASE,
)

_AVOID_RE = re.compile(
    r"\b(no\s+\w+|without|remove|avoid|don'?t\s+\w+|pas\s+de|sans|éviter|retirer)\b",
    re.IGNORECASE,
)

_EXPLORE_SIGNALS = re.compile(
    r"\b(not\s+sure|don'?t\s+know|just\s+(looking|exploring|browsing)|"
    r"ideas?|inspiration|what\s+(if|do\s+you\s+think)|pas\s+encore|"
    r"just\s+want\s+to\s+(talk|chat|think)|let\s+me\s+think|"
    r"je\s+ne\s+sais\s+pas|juste\s+(regarder|explorer))\b",
    re.IGNORECASE,
)

_FR_ACCENTS = re.compile(r'[àâæçéèêëîïôœùûüÿÀÂÆÇÉÈÊËÎÏÔŒÙÛÜŸ]')
_FR_MARKERS = {
    'bonjour', 'bonsoir', 'salut', 'merci', 'oui', 'parle', 'parler',
    'peux', 'pouvez', 'nous', 'vous', 'répondre', 'français',
    'comprends', 'voudrais', 'voulais',
}


def _detect_language(text: str) -> str:
    if _FR_ACCENTS.search(text):
        return "fr"
    words = set(re.findall(r'\b\w+\b', text.lower()))
    if words & _FR_MARKERS:
        return "fr"
    return "en"


def _extract_atmosphere(text: str) -> str:
    lower = text.lower()
    for keyword, atm_id in _ATMOSPHERE_KEYWORDS.items():
        if keyword in lower:
            return atm_id
    return ""


def _extract_room(text: str) -> str:
    lower = text.lower()
    for keyword, room_id in _ROOM_KEYWORDS.items():
        if keyword in lower:
            return room_id
    return ""


def build_session_memory(
    history: list[dict],
    detected_language: str = "en",
    session_language_override: str = "",
    atmosphere_id_hint: str = "",
    room_type_hint: str = "",
) -> SessionMemory:
    """
    Build a lightweight SessionMemory from message history.

    history: list of {role: "user"|"ai", content: str}
    detected_language: language detected from the current message
    session_language_override: if LANGUAGE_SWITCH was detected, use this
    atmosphere_id_hint: atmosphere_id from the current request (UI state)
    room_type_hint: room_type from the current request (UI state)

    Hints are used when history doesn't mention the atmosphere or room,
    ensuring greetings are always project-aware when context is active.
    """
    mem = SessionMemory()
    mem.session_language = session_language_override or detected_language

    user_messages = [
        m["content"].strip()
        for m in history
        if m.get("role") == "user" and m.get("content", "").strip()
    ]
    mem.message_count = len(user_messages)

    explore_signals = 0
    for msg in user_messages:
        # Track language drift
        lang = _detect_language(msg)
        if lang == "fr":
            mem.session_language = "fr"

        # Atmosphere and room tracking (last one wins)
        atm = _extract_atmosphere(msg)
        if atm:
            mem.atmosphere_mentioned = atm
        room = _extract_room(msg)
        if room:
            mem.room_type_mentioned = room

        # Keep constraints
        if _KEEP_RE.search(msg):
            short = msg[:80]
            if short not in mem.keep_constraints:
                mem.keep_constraints.append(short)

        # Avoid constraints
        if _AVOID_RE.search(msg):
            short = msg[:80]
            if short not in mem.avoid_constraints:
                mem.avoid_constraints.append(short)

        # Exploration signals
        if _EXPLORE_SIGNALS.search(msg):
            explore_signals += 1

    # Cap constraint lists
    mem.keep_constraints = mem.keep_constraints[-3:]
    mem.avoid_constraints = mem.avoid_constraints[-3:]

    # Last topic = latest user message (truncated)
    if user_messages:
        mem.last_topic = user_messages[-1][:120]

    # Current direction = last message if it has directional content
    if user_messages:
        mem.current_direction = user_messages[-1][:100]

    # Exploring = no committed direction after multiple messages, or explicit signals
    mem.is_exploring = (
        explore_signals > 0
        or (mem.message_count <= 1 and not mem.atmosphere_mentioned)
    )

    # Apply hints from UI state (fills gaps when history doesn't mention them)
    # Hint only applies when history extraction found nothing — history wins.
    if atmosphere_id_hint and not mem.atmosphere_mentioned:
        mem.atmosphere_mentioned = atmosphere_id_hint
    if room_type_hint and not mem.room_type_mentioned:
        mem.room_type_mentioned = room_type_hint

    # Apply language override last (LANGUAGE_SWITCH takes precedence)
    if session_language_override:
        mem.session_language = session_language_override

    return mem
