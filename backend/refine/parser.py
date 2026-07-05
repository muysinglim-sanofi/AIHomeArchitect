"""Refine Engine V2 — Composant 1 : PARSER.

message → Change[] typés. LLM gpt-4o-mini (primaire) + fallback DÉTERMINISTE
(réutilise `edit_intent._split_changes` — split seul, lecture seule).

AUCUN appel image. NE TOUCHE JAMAIS /generate, le composer, la DNA, la préservation.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Optional

# Read-only reuse of the compound-instruction splitter (regex split, no engine logic).
from prompt_engine.edit_intent import _split_changes

TYPES = ("move", "add", "remove", "replace", "modify", "structure")


@dataclass
class Change:
    """Un changement demandé, typé. `raw` = la clause d'origine (verbatim).
    `normalized` = instruction crisp posée par le Normalizer (Composant 2)."""
    type: str      # move | add | remove | replace | modify | structure
    object: str    # le nom principal ciblé  ("TV", "sofa", "dining table", "wall")
    detail: str    # qualificatif / cible / nouvelle valeur  ("to the right wall", "dark green")
    raw: str       # la clause d'origine
    normalized: str = ""   # rempli par refine.normalizer.normalize_changes()


# ── Classification déterministe (fallback) — ordre = priorité ────────────────
_TYPE_PATTERNS = [
    # structure = action structurelle explicite ; « wall » SEUL ne suffit pas
    # (« to the right wall » = destination d'un move, PAS un changement structurel).
    ("structure", re.compile(
        # verbe structurel + (article) + 0-2 adjectifs (right/back/new/dividing…) + nom archi.
        # Les ≤2 mots gardent « move the TV to the right wall » → MOVE (écart >2 mots = pas match).
        r"\b(partition\b|arch(?:way)?\b|door\s*way\b|"
        r"(?:add|build|create|put\s+up|open\s+up|knock\s+down|remove|break|demolish|"
        r"take\s+down|move|extend|close|seal|brick\s+up|wall\s+off)\s+(?:an?\s+|the\s+)?"
        r"(?:\w+\s+){0,2}(?:wall|window|opening|arch)\b|"
        r"open\s+(?:up\s+)?the\s+kitchen|create\s+an?\s+(?:arch|opening)|"
        r"ceiling\b|extend\s+the\s+room)\b", re.I)),
    ("replace", re.compile(
        r"\b(replace|swap|change\s+the\s+[\w\s]+?\s+(?:to|for|into|with)|"
        r"turn\s+the\s+[\w\s]+?\s+into)\b", re.I)),
    ("remove", re.compile(
        r"\b(remove|delete|get\s+rid\s+of|take\s+(?:out|away)|no\s+more)\b", re.I)),
    ("move", re.compile(
        r"\b(move|rotate|reverse|flip|turn(?!\s+the\s+[\w\s]+?\s+into)|reposition|"
        r"shift|slide|relocate|face(?:s|d)?\s+(?:the|toward|towards)|"
        r"put\s+the\s+[\w\s]+?\s+(?:on|against|in\s+front|next\s+to|to\s+the))\b", re.I)),
    ("add", re.compile(r"\b(add|place|introduce|include|hang|install|put\s+a)\b", re.I)),
    ("modify", re.compile(
        r"\b(make\s+it|make\s+the|change\s+the\s+colou?r|recolou?r|darker|lighter|"
        r"brighter|warmer|cooler|paint|repaint|material|texture|finish|more\s+\w+)\b", re.I)),
]


def _classify(clause: str) -> str:
    for t, pat in _TYPE_PATTERNS:
        if pat.search(clause):
            return t
    return "modify"  # défaut sûr : une formulation qu'on n'a pas typée (le LLM ferait mieux)


def _object_detail(clause: str) -> tuple[str, str]:
    """Heuristique bon-marché (fallback only) : « ... the X <rest> » → object=X, detail=rest."""
    m = re.search(r"\bthe\s+([a-z][a-z\s]{1,24}?)(\s+(?:to|on|with|in|into|for|near|toward|towards|"
                  r"against|next|above|below|under)\b.*)?$", clause.strip(), re.I)
    if m:
        return m.group(1).strip(), (m.group(2) or "").strip()
    return clause.strip(), ""


def parse_deterministic(message: str) -> list[Change]:
    """Fallback pur (sans LLM) : split + classification par mots-clés. Testable seul."""
    out: list[Change] = []
    for clause in _split_changes(message or ""):
        obj, det = _object_detail(clause)
        out.append(Change(type=_classify(clause), object=obj, detail=det, raw=clause))
    return out


# ── Parser LLM (primaire) ─────────────────────────────────────────────────────
_SYS = (
    "Extract the DISTINCT requested changes from an interior-design refine message. "
    "For EACH change return an object {type, object, detail, raw}. "
    "type is EXACTLY one of: "
    "move (reposition/rotate an existing object), add (introduce a NEW object), "
    "remove (delete an object), replace (swap an object for another), "
    "modify (change colour/material/style of an existing object), "
    "structure (walls/windows/openings/partitions/architecture). "
    "object = the main target noun. detail = the qualifier / target position / new value. "
    "raw = the original clause verbatim. "
    'Return ONLY JSON: {"changes":[{"type":"..","object":"..","detail":"..","raw":".."}]}.'
)


async def parse_llm(message: str, client) -> Optional[list[Change]]:
    """gpt-4o-mini → Change[]. Renvoie None sur toute erreur/vide (→ fallback). Pas d'image."""
    try:
        r = await client.chat.completions.create(
            model="gpt-4o-mini", temperature=0, max_tokens=500,
            messages=[{"role": "system", "content": _SYS},
                      {"role": "user", "content": message.strip()}])
        t = (r.choices[0].message.content or "").strip().strip("`")
        t = t[t.find("{"):t.rfind("}") + 1]
        data = json.loads(t)
        chs: list[Change] = []
        for c in data.get("changes", []):
            typ = str(c.get("type", "")).lower().strip()
            if typ not in TYPES:
                typ = "modify"
            chs.append(Change(
                type=typ,
                object=str(c.get("object", "")).strip(),
                detail=str(c.get("detail", "")).strip(),
                raw=str(c.get("raw", "")).strip() or message.strip(),
            ))
        return chs or None
    except Exception:  # noqa: BLE001 — toute panne LLM/JSON → fallback déterministe
        return None


async def parse_changes(message: str, client=None) -> list[Change]:
    """Point d'entrée. LLM si `client` fourni (sinon/à l'échec → fallback déterministe).
    JAMAIS d'appel image ; ne dépend que du split (lecture seule)."""
    if not message or not message.strip():
        return []
    if client is not None:
        chs = await parse_llm(message, client)
        if chs:
            return chs
    return parse_deterministic(message)
