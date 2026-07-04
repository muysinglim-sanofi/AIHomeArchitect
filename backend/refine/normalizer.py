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


def _clean(s: str) -> str:
    return (s or "").strip().rstrip(". ").strip()


def _cap(s: str) -> str:
    s = _clean(s)
    return (s[0].upper() + s[1:]) if s else s


def _period(s: str) -> str:
    s = _clean(s)
    return (s + ".") if s else s


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
        if re.search(r"\bopen\s+(?:up\s+)?the\s+kitchen\b", low) and "wall" not in low:
            return _period(f"{_cap(raw)} by removing the dividing wall, keeping the kitchen units in place")
        return _period(_cap(raw))

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
