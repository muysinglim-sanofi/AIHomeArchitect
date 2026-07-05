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


# ── Canonicalisation du type (POST-PARSE) ────────────────────────────────────
# Un élément ARCHITECTURAL sous une action add/remove/replace/open/close DOIT être
# typé STRUCTURE, quelle que soit la classification initiale du LLM. Générique : la
# décision vient de la NATURE de l'objet + l'ACTION, jamais d'une phrase exacte.
# Nom archi en TÊTE de l'objet (« right wall » oui ; « wall art »/« wall clock » NON).
_ARCH_HEAD = re.compile(
    r"\b(wall|window|opening|partition|ceiling|door\s*way|door|skylight|arch(?:way)?|"
    r"facade|mezzanine|bay\s+window|french\s+doors?|sliding\s+doors?)s?\s*$", re.I)
# Pièges : « X door » de meuble/électro n'est PAS une porte architecturale.
_ARCH_FURNITURE_TRAP = re.compile(
    r"\b(cabinet|cupboard|fridge|refrigerator|oven|wardrobe|closet|shower|car|glass\s+cabinet|"
    r"barn|patio|screen|garage|pantry)\s+door\b", re.I)
# Verbes structurels (au-delà de add/remove/replace) : open/close/knock/board/widen/lower…
_STRUCT_VERB = re.compile(
    r"\b(open|close|knock\s+(?:down|through)|demolish|break\s+through|take\s+down|tear\s+down|"
    r"wall\s+off|seal|brick\s+up|board\s+up|widen|enlarge|lower|raise)\b", re.I)
# Verbes de CONSTRUCTION non ambigus → STRUCTURE quel que soit l'objet (« wall off the
# staircase » érige un mur ; « knock through X » perce). Ne s'appliquent pas au décor/meuble.
_STRUCT_VERB_STRONG = re.compile(
    r"\b(wall\s+off|brick\s+up|board\s+up|partition\s+off|knock\s+(?:down|through)|"
    r"demolish|tear\s+down)\b", re.I)


# Un mot archi APPARAÎT dans l'objet mais n'en est pas la tête → piège (wall art, ceiling fan).
_ARCH_WORD = re.compile(r"\b(wall|window|ceiling|opening|partition|door|arch(?:way)?)\b", re.I)
# « open (up) » EN TÊTE d'une PIÈCE/ZONE = ouvrir l'espace (abattre la cloison) = structurel.
# Ancré en tête → « add a kitchen to the OPEN area » (adjectif) ne déclenche PAS ; « open the
# curtains » non plus (objet non-zone).
_OPEN_VERB_LEAD = re.compile(r"^\s*open(?:\s+up)?\b", re.I)
_ZONE_OBJECT = re.compile(
    r"\b(kitchen|kitchenette|bathroom|room|space|area|lounge|living(?:\s+room)?|"
    r"dining(?:\s+room)?|hallway|studio|loft|conservatory)\b", re.I)


def _is_arch_object(obj: str) -> bool:
    """L'objet ciblé est-il un ÉLÉMENT architectural (nom en tête, hors pièges) ?"""
    o = re.sub(r"^(the|a|an|this|that|these|those)\s+", "", (obj or "").strip(), flags=re.I)
    if not o or _ARCH_FURNITURE_TRAP.search(o):
        return False
    return bool(_ARCH_HEAD.search(o))


def _natural_type(raw: str) -> str:
    """Type naturel d'après le verbe (pour DÉMOTER un faux positif structure)."""
    low = (raw or "").lower()
    if re.search(r"\b(remove|delete|knock|demolish|take\s+(?:out|away|down)|get\s+rid|tear)\b", low):
        return "remove"
    if re.search(r"\b(replace|swap)\b", low):
        return "replace"
    if re.search(r"\b(move|rotate|reposition|shift|relocate|slide)\b", low):
        return "move"
    if re.search(r"\b(add|place|install|hang|put|mount|introduce)\b", low):
        return "add"
    return "modify"


def canonicalize_types(changes: list[Change]) -> list[Change]:
    """Canonicalise le type d'après la NATURE de l'objet + l'ACTION (générique, idempotent) :
      • PROMOTE : objet architectural + action add/remove/replace/open/close → STRUCTURE.
      • DEMOTE  : typé structure mais objet à l'air-archi-mais-tête-déco (wall art, ceiling
        fan, window seat, cabinet door) → type naturel.
    « move the TV to the right wall » reste MOVE (objet=TV) ; « paint the wall » reste MODIFY
    (hors gate) ; « open the kitchen » reste STRUCTURE (objet=kitchen, pas un piège archi)."""
    for c in changes:
        if c.type == "structure":
            if not _is_arch_object(c.object) and _ARCH_WORD.search(c.object or ""):
                c.type = _natural_type(c.raw)   # faux positif « wall art / ceiling fan »
            continue
        raw = c.raw or ""
        if _STRUCT_VERB_STRONG.search(raw):     # verbe de construction non ambigu (obj-indépendant)
            c.type = "structure"
            continue
        if _OPEN_VERB_LEAD.match(raw) and _ZONE_OBJECT.search(c.object or ""):   # « open (up) the kitchen »
            c.type = "structure"
            continue
        action_ok = c.type in ("add", "remove", "replace") or bool(_STRUCT_VERB.search(raw))
        if action_ok and _is_arch_object(c.object):
            c.type = "structure"
    return changes


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
    return canonicalize_types(out)


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
        return canonicalize_types(chs) or None
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
