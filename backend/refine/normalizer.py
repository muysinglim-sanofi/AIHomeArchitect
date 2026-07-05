"""Refine Engine V2 — Composant 2 : NORMALIZER (100% déterministe, N1).

`Change → change.normalized` : une instruction single-edit **crisp**, avec une
CIBLE/SCOPE concret (N2 move · N3 remove/replace). AUCUN LLM, AUCUN appel image.
Ne touche JAMAIS /generate, le composer, la DNA, la préservation.
"""
from __future__ import annotations

import re

from refine.parser import Change

# Une cible de move déjà présente dans la clause ?
_MOVE_TARGET = re.compile(
    r"\b(to|onto|against|facing|toward|towards|in\s+front\s+of|next\s+to|beside|"
    r"opposite|other\s+side|left\s+wall|right\s+wall|corner|centre|center|middle)\b", re.I)

# Un lieu d'add déjà présent ?
_ADD_LOCATION = re.compile(
    r"\b(on|onto|in|into|above|below|under|beneath|next\s+to|beside|near|by\s+the|"
    r"against|in\s+the\s+corner|on\s+the\s+wall|on\s+the\s+floor|over\s+the)\b", re.I)

# Placement par objet (ADD sans lieu). Défaut = surface visible principale.
_ADD_PLACEMENT = [
    (re.compile(r"\b(rug|carpet)\b", re.I),                "on the floor under the main seating area"),
    (re.compile(r"\bfloor\s+lamp\b", re.I),                "in a corner of the room"),
    (re.compile(r"\blamp\b", re.I),                        "on a side surface or in a corner"),
    (re.compile(r"\b(plant|tree|palm|greenery)\b", re.I),  "in a corner of the room"),
    (re.compile(r"\b(art|artwork|painting|mirror|frame|picture|poster)\b", re.I), "on the main wall"),
    (re.compile(r"\b(curtain|drape|blind|sheer)\b", re.I), "on the window"),
    (re.compile(r"\b(shelf|shelves|bookshelf|bookcase)\b", re.I), "on a wall"),
    (re.compile(r"\bfireplace\b", re.I),                   "on the main wall"),
]
_ADD_DEFAULT = "on the coffee table or main visible surface"

# Expansions MODIFY courantes (sinon la clause est conservée).
_MODIFY_EXPAND = [
    (re.compile(r"\bwarm(?:er)?\b", re.I),  "shift the overall palette to warmer tones (deeper woods, amber lighting, warm textiles)"),
    (re.compile(r"\bcool(?:er)?\b", re.I),  "shift the overall palette to cooler tones (greys, blues, crisp light)"),
    (re.compile(r"\bbright(?:er)?\b", re.I), "brighten the overall lighting and lighten the palette"),
    (re.compile(r"\bdark(?:er)?\b", re.I),  "deepen the overall palette to a darker, moodier tone"),
    (re.compile(r"\b(?:cosy|cozy|cozier|cosier)\b", re.I), "make the space feel cosier with warmer textiles and softer lighting"),
]

# STRUCTURE — classes de VERBE (générique, piloté par l'action, PAS par des phrases
# particulières). Chaque classe → un mandat architectural explicite bâti avec `change.object`.
_STRUCT_REMOVE = re.compile(r"\b(remove|knock\s+down|take\s+down|demolish|break|tear\s+down|delete|get\s+rid\s+of)\b", re.I)
_STRUCT_CLOSE = re.compile(r"\b(close|wall\s+off|block(?:\s+off)?|seal|fill\s+in|brick\s+up)\b", re.I)
_STRUCT_OPEN = re.compile(r"\bopen(?:\s+up)?\b", re.I)
_STRUCT_ADD = re.compile(r"\b(add|create|build|put\s+in|install|make)\b", re.I)


def _clean(s: str) -> str:
    return (s or "").strip().rstrip(". ").strip()


def _cap(s: str) -> str:
    s = _clean(s)
    return (s[0].upper() + s[1:]) if s else s


def _period(s: str) -> str:
    s = _clean(s)
    return (s + ".") if s else s


def _struct_object(change: Change, raw: str) -> str:
    """Nom de l'élément architectural ciblé, avec article (générique)."""
    o = _clean(change.object)
    if not o or len(o) < 2:
        # fallback : la clause après le verbe, sinon le raw
        m = re.search(r"\b(?:the|a|an|this|that)\s+([a-z][a-z\s]{1,28})", raw, re.I)
        o = (m.group(1).strip() if m else _clean(raw))
    if not re.match(r"(?i)^(the|a|an|this|that|these|those)\b", o):
        o = "the " + o
    return o


def _normalize_structure(change: Change, raw: str, low: str) -> str:
    """Mandat architectural EXPLICITE, bâti par CLASSE DE VERBE + object (générique).
    Une structure explicitement demandée est prioritaire : on n'atténue jamais."""
    obj = _struct_object(change, raw)
    # « open the kitchen » (sans mur nommé) → mandat d'ouverture concret
    if re.search(r"\bopen\s+(?:up\s+)?the\s+kitchen\b", low) and "wall" not in low:
        return _period(f"{_cap(raw)} by removing the dividing wall as a REAL architectural change, "
                       "keeping the kitchen units in place")
    if _STRUCT_REMOVE.search(low):
        return _period(f"Entirely remove {obj} as a REAL architectural change — {obj} is genuinely "
                       "gone, opening up the space where it was")
    if _STRUCT_CLOSE.search(low):
        return _period(f"Close {obj} and replace it with a solid wall matching the surrounding wall "
                       "finish and colour, leaving no opening there")
    if _STRUCT_OPEN.search(low):
        return _period(f"Open up {obj} as a REAL architectural change, removing the wall or partition "
                       "that closes it")
    if _STRUCT_ADD.search(low):
        return _period(f"{_cap(raw)} — add it as a REAL new architectural element, matching the size, "
                       "style and proportions of the existing ones")
    return _period(f"{_cap(raw)} — realize this as a REAL architectural change to the room")


def normalize(change: Change) -> str:
    """Renvoie l'instruction crisp pour UN changement (déterministe, idempotent)."""
    raw = _clean(change.raw)
    low = raw.lower()
    t = change.type

    if t == "move":
        if re.search(r"\brotate\b", low) and not _MOVE_TARGET.search(low):
            return _period(f"{_cap(raw)} to face the opposite direction")
        if _MOVE_TARGET.search(low):
            return _period(_cap(raw))                       # cible déjà là → conservée
        return _period(f"{_cap(raw)} onto a different wall, clearly away from its current spot")  # N2

    if t == "remove":
        if "leaving" in low or "empty" in low:              # idempotence
            return _period(_cap(raw))
        base = re.sub(r"^(remove|delete)\b", "completely remove", raw, flags=re.I)
        return _period(f"{_cap(base)}, leaving that floor area empty")  # N3

    if t == "replace":
        if "same position" in low:                          # idempotence
            return _period(_cap(raw))
        return _period(f"{_cap(raw)}, in the same position")  # N3

    if t == "add":
        if _ADD_LOCATION.search(low):
            return _period(_cap(raw))                       # lieu déjà là → conservé
        placement = _ADD_DEFAULT
        for pat, pl in _ADD_PLACEMENT:
            if pat.search(low):
                placement = pl
                break
        return _period(f"{_cap(raw)} {placement}")

    if t == "structure":
        return _normalize_structure(change, raw, low)

    # modify
    for pat, exp in _MODIFY_EXPAND:
        if pat.search(low):
            return _period(_cap(exp))
    return _period(_cap(raw))


def normalize_changes(changes: list[Change]) -> list[Change]:
    """Pose `change.normalized` sur chaque changement (mutation en place) et les renvoie."""
    for c in changes:
        c.normalized = normalize(c)
    return changes
