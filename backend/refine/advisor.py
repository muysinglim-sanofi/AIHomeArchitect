"""Refine Engine V2 — Composant 1.5 : REQUEST ADVISOR (conseille avant de générer).

Position :  Parser → **Request Advisor** → Normalizer → Conflict → Planner → Executor → Verify.

Ayden CONSEILLE avant de dépenser une génération : il juge la *plausibilité* de chaque
changement vis-à-vis de la PIÈCE (room_type), en amont. Architecte, pas générateur.
Complémentaire du Verify (a priori sémantique ≠ a posteriori post-gen). AUCUN appel image.
Moteur 2 pur : ne touche JAMAIS /generate, le composer, la DNA, la préservation.

Tiered (spec §13) :
  L1  règles déterministes  ($0, ~0 ms)  → GREEN | RED | ESCALATE
  L2  gpt-4o-mini TEXTE      (~$0.0001)   → sur ESCALATE uniquement ; PAS de Vision
  L3  Vision                (V3)          → différée (hors MVP)

Anti-paternalisme (dur) : défaut GREEN · RED rare, toujours override + alternative ·
YELLOW = heads-up (pause légère), jamais un refus · fail-open sur panne L2 → GREEN.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

from refine.parser import Change

_ADVISOR_MODEL = "gpt-4o-mini"


class Verdict(str, Enum):
    GREEN = "green"      # plausible → génération directe
    YELLOW = "yellow"    # ambitieux/incertain → pause légère « try anyway »
    RED = "red"          # absurde pour cette pièce → alternative + override


_RANK = {Verdict.GREEN: 0, Verdict.YELLOW: 1, Verdict.RED: 2}


@dataclass
class ChangeAdvice:
    change: Change
    verdict: Verdict
    reason: str = ""         # 1 phrase architecte (YELLOW/RED)
    alternative: str = ""    # proposition concrète (RED)
    source: str = "rules"    # "rules" (L1) | "llm" (L2)


@dataclass
class AdviceResult:
    advices: list[ChangeAdvice] = field(default_factory=list)

    @property
    def overall(self) -> Verdict:
        """Pire verdict (RED > YELLOW > GREEN). Vide → GREEN."""
        if not self.advices:
            return Verdict.GREEN
        return max((a.verdict for a in self.advices), key=lambda v: _RANK[v])

    @property
    def all_green(self) -> bool:
        return self.overall == Verdict.GREEN

    @property
    def green_changes(self) -> list[Change]:
        """Les changements « sensés » — sert [Do the sensible ones]."""
        return [a.change for a in self.advices if a.verdict == Verdict.GREEN]

    @property
    def flagged(self) -> list[ChangeAdvice]:
        return [a for a in self.advices if a.verdict != Verdict.GREEN]


# ── Tables L1 (déterministes) ────────────────────────────────────────────────
_INTERIOR_ROOMS = {
    "bathroom", "bedroom", "kitchen", "living room", "living", "dining room", "dining",
    "office", "hallway", "kids room", "kids", "laundry", "closet", "entryway", "study",
}
_EXTERIOR_ROOMS = {
    "terrace", "pool", "garden", "balcony", "patio", "driveway", "facade", "backyard",
}

# add d'un de ces objets → GREEN direct (décor courant, plausible partout)
_UNIVERSAL_DECOR = re.compile(
    r"\b(flowers?|plants?|potted\s+plant|lamps?|floor\s+lamp|rugs?|carpets?|cushions?|"
    r"pillows?|throws?|blankets?|art|artwork|paintings?|mirrors?|frames?|pictures?|"
    r"posters?|candles?|vases?|books?|clocks?|curtains?|drapes?|blinds?|shelf|shelves|"
    r"bookshelf|bookcase|stools?|poufs?|side\s+table|coffee\s+table|plant\s+pot|trays?|bowls?|"
    r"greenery|decor|ornaments?)\b", re.I)

# add/structure d'un de ces objets dans une pièce INTÉRIEURE → RED backstop
_ABSURD_INTERIOR = re.compile(
    r"\b(cars?|ferrari|lamborghini|porsche|trucks?|vans?|motorcycles?|motorbikes?|"
    r"boats?|yachts?|ships?|canoes?|kayaks?|airplanes?|planes?|jets?|helicopters?|tanks?|"
    r"swimming\s+pool|pool|jacuzzi\s+pool|ponds?|lakes?|waterfalls?|beach|ocean|sea|"
    r"horses?|elephants?|cows?|dinosaurs?|giraffes?|lions?|tigers?|"
    r"garages?|building|skyscraper|mountains?|forest|jungle)\b", re.I)

_EXISTING_OPS = {"move", "remove", "modify", "replace"}


def _room_is_interior(room_type: Optional[str]) -> bool:
    """Défaut prudent : pièce inconnue traitée comme INTÉRIEURE (le set absurde s'applique)."""
    if not room_type:
        return True
    r = room_type.strip().lower()
    if r in _EXTERIOR_ROOMS or any(e in r for e in _EXTERIOR_ROOMS):
        return False
    return True


def _l1_classify(change: Change, room_type: Optional[str]) -> str:
    """L1 déterministe → 'green' | 'red' | 'escalate'."""
    text = f"{change.object} {change.raw}"
    if change.type in _EXISTING_OPS:
        return "green"                                   # opère sur de l'existant
    if change.type == "add":
        if _room_is_interior(room_type) and _ABSURD_INTERIOR.search(text):
            return "red"                                 # backstop absurde
        if _UNIVERSAL_DECOR.search(text):
            return "green"                               # décor courant
        return "escalate"                                # add non-trivial → L2
    if change.type == "structure":
        if _room_is_interior(room_type) and _ABSURD_INTERIOR.search(text):
            return "red"
        return "escalate"                                # structure → jugement L2
    return "escalate"


def _red_alternative(change: Change, room_type: Optional[str]) -> str:
    """Alternative générique (L1 RED) — jamais un mur : on propose une redirection."""
    obj = change.object.strip() or "that"
    return (f"place the {obj} outside (on a terrace, driveway or garden) instead"
            if _ABSURD_INTERIOR.search(f"{change.object} {change.raw}") else
            "adapt it to something that fits this room")


# ── L2 (gpt-4o-mini TEXTE — pas de Vision) ───────────────────────────────────
_L2_SYS = (
    "You are Ayden, a pragmatic interior architect. Judge whether a requested change can "
    "plausibly be realized in the given ROOM via a photo edit. Verdict = GREEN (normal/"
    "plausible), YELLOW (possible but ambitious or spatially uncertain), or RED (physically "
    "absurd for this room). Be GENEROUS: default GREEN; reserve RED only for things that cannot "
    "sensibly exist in this room (vehicles, pools, large outdoor elements inside an interior). "
    "For YELLOW/RED give ONE short architect sentence; for RED also give a concrete alternative. "
    'JSON only: {"verdict":"GREEN|YELLOW|RED","reason":"","alternative":""}'
)


async def _l2_advise(change: Change, room_type: Optional[str], client) -> ChangeAdvice:
    """1 appel texte gpt-4o-mini pour UN changement escaladé. Fail-open → GREEN."""
    try:
        r = await client.chat.completions.create(
            model=_ADVISOR_MODEL, temperature=0, max_tokens=160,
            messages=[{"role": "system", "content": _L2_SYS},
                      {"role": "user", "content":
                          f"Room: {room_type or 'unspecified interior room'}\n"
                          f"Requested change: {change.raw}"}])
        t = (r.choices[0].message.content or "").strip().strip("`")
        data = json.loads(t[t.find("{"):t.rfind("}") + 1])
        v = str(data.get("verdict", "GREEN")).strip().lower()
        verdict = {"green": Verdict.GREEN, "yellow": Verdict.YELLOW, "red": Verdict.RED}.get(v, Verdict.GREEN)
        return ChangeAdvice(change=change, verdict=verdict,
                            reason=str(data.get("reason", "")).strip(),
                            alternative=str(data.get("alternative", "")).strip(),
                            source="llm")
    except Exception:  # noqa: BLE001 — panne de conseil → on ne bloque JAMAIS
        return ChangeAdvice(change=change, verdict=Verdict.GREEN, source="llm")


async def advise(changes: list[Change], room_type: Optional[str] = None,
                 *, client=None) -> AdviceResult:
    """Point d'entrée. L1 sur chaque changement ; escalade → L2 (si `client`), sinon GREEN
    (fail-open : sans client LLM on ne bloque que le set absurde codé en dur via L1 RED)."""
    advices: list[ChangeAdvice] = []
    for c in changes:
        verdict = _l1_classify(c, room_type)
        if verdict == "green":
            advices.append(ChangeAdvice(change=c, verdict=Verdict.GREEN, source="rules"))
        elif verdict == "red":
            advices.append(ChangeAdvice(
                change=c, verdict=Verdict.RED, source="rules",
                reason=f"a {c.object or 'this'} doesn't sensibly belong in a {room_type or 'room like this'}",
                alternative=_red_alternative(c, room_type)))
        else:  # escalate
            if client is not None:
                advices.append(await _l2_advise(c, room_type, client))
            else:
                advices.append(ChangeAdvice(change=c, verdict=Verdict.GREEN, source="rules"))
    return AdviceResult(advices=advices)


def build_advisory_message(result: AdviceResult) -> Optional[str]:
    """Message architecte (voix Ayden) si YELLOW/RED ; None si tout GREEN (aucune friction).
    D-c : on EXPLIQUE ce qui coince, mais on ne propose JAMAIS de drop partiel — l'action est
    Continue (toute la requête) ou Edit. Pas de « do the sensible ones »."""
    if result.all_green:
        return None
    reds = [a for a in result.advices if a.verdict == Verdict.RED]
    yellows = [a for a in result.advices if a.verdict == Verdict.YELLOW]
    lines: list[str] = []
    for a in reds:
        alt = f" Would you like to {a.alternative}?" if a.alternative else ""
        lines.append(f"As your architect, I don't recommend « {a.change.raw} »"
                     f"{(' — ' + a.reason) if a.reason else ''}.{alt}")
    for a in yellows:
        lines.append(f"« {a.change.raw} » may be difficult to achieve"
                     f"{(' — ' + a.reason) if a.reason else ''}. Try anyway?")
    return "\n".join(lines)
