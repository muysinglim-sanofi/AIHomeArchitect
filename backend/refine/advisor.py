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
    confidence: float = 0.9  # [0,1] — pour logger + apprendre (GREEN ratés / YELLOW faciles)


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

    @property
    def min_confidence(self) -> float:
        """Confiance la plus basse du lot (pour logging / seuils futurs)."""
        return min((a.confidence for a in self.advices), default=1.0)


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

# Réutilise la MÊME catégorie « installation fonctionnelle » que le Normalizer (pas une
# nouvelle catégorie) : une zone fonctionnelle explicite et plausible est GREEN.
from refine.normalizer import _FUNCTIONAL_INSTALL, _FUNC_INSTALL_VERB
# Wave 4.9.5 — taxonomie PARTAGÉE des pièces/zones (source unique = intent_classifier).
# Import unidirectionnel refine→prompt_engine (aucun cycle : intent_classifier n'importe
# jamais refine). Réutilisée pour la calibration L1 des conversions de zone.
from prompt_engine.intent_classifier import _FUNCTIONAL_ROOM_RE

# STRUCTURE — ajout/ouverture/conversion d'un NOUVEL élément ou zone (pas d'ambiguïté de cible).
_STRUCT_ADDITION = re.compile(r"^\s*(add|create|build|put|install|make|convert|open|fit|set\s+up)\b", re.I)
# Cible IDENTIFIABLE d'un remove/close/replace structurel : qualificatif spatial ou pièce nommée.
# Générique (mot-qualificatif), pas de phrase exacte. Absent → demande ambiguë (« quelle cloison ? »).
_TARGET_QUALIFIER = re.compile(
    r"\b(right|left|back|front|rear|north|south|east|west|side|dividing|partition|main|middle|"
    r"central|first|second|third|between|load-bearing|far|near|entrance|corner|nook|alcove|"
    r"kitchen|bedroom|"
    r"bathroom|living|dining|hallway|corridor|garden|patio|terrace|street|window\s+side)\b", re.I)


def _is_targeted(change: Change) -> bool:
    return bool(_TARGET_QUALIFIER.search(f"{change.object} {change.raw}"))


def _room_is_interior(room_type: Optional[str]) -> bool:
    """Défaut prudent : pièce inconnue traitée comme INTÉRIEURE (le set absurde s'applique)."""
    if not room_type:
        return True
    r = room_type.strip().lower()
    if r in _EXTERIOR_ROOMS or any(e in r for e in _EXTERIOR_ROOMS):
        return False
    return True


# Wave 4.9.5 — cible de conversion EXPLICITE : un qualificatif spatial dans le detail,
# OU une redirection "into / instead of" dans la clause (la destination EST la cible).
_REPLACE_TARGET = re.compile(
    r"\b(instead\s+of|in\s+place\s+of|in\s+the\s+place\s+of|into|replacing)\b", re.I)
# Garde-fou anti-meuble : un MEUBLE nommé d'après une pièce ("dining table",
# "bedroom lamp", "office chair", "kitchen island") n'est PAS une installation de zone.
_FURNISH_TAIL = re.compile(
    r"\b(table|desk|chair|island|counter|counters|cabinet|cabinets|lamp|light|sink|unit|"
    r"units|set|rug|sofa|couch|bed|shelf|shelves|stool|bench|mirror|rack|stand|pouf|"
    r"ottoman|armoire|wardrobe|door|window)\b", re.I)


def _has_explicit_target(change: Change) -> bool:
    """Une cible spatiale (detail) ou une redirection into/instead-of (clause) est présente."""
    return bool(_TARGET_QUALIFIER.search(change.detail or "")
                or _REPLACE_TARGET.search(change.raw or ""))


def _l1_classify(change: Change, room_type: Optional[str]) -> str:
    """L1 déterministe → 'green' | 'yellow' | 'red' | 'escalate'. Décision fondée sur les
    Change[] CANONICALISÉS (type + object), jamais sur des phrases exactes."""
    text = f"{change.object} {change.raw}"
    raw_low = (change.raw or "").lower()

    # 1) Absurde/irréalisable en intérieur (véhicule/piscine/outdoor) → RED, quel que soit le type.
    #    → la structure ne devient JAMAIS auto-GREEN juste parce qu'elle est typée structure.
    if _room_is_interior(room_type) and _ABSURD_INTERIOR.search(text):
        return "red"

    # 2) Installation fonctionnelle majeure EXPLICITE et plausible → GREEN
    #    (add an open kitchen · create a dressing area · convert this side into a bathroom).
    if _FUNCTIONAL_INSTALL.search(text) and _FUNC_INSTALL_VERB.search(raw_low):
        return "green"

    # 2.5) Wave 4.9.5 — conversion de ZONE fonctionnelle hors _FUNCTIONAL_INSTALL
    #      (bedroom/office/sleeping area/lounge/…), via la taxonomie PARTAGÉE _FUNCTIONAL_ROOM_RE.
    #      Rend le verdict COHÉRENT quel que soit le type posé par le Parser (add vs structure) —
    #      supprime l'incohérence prouvée (« add a bedroom » → RED L2 vs « I would like a
    #      bedroom » → GREEN). Contrat : cible explicite → GREEN ; cible absente/ambiguë → YELLOW.
    #      Garde-fou anti-meuble (« dining table ») via _FURNISH_TAIL sur l'objet.
    if (_FUNC_INSTALL_VERB.search(raw_low)
            and _FUNCTIONAL_ROOM_RE.search(text)
            and not _FURNISH_TAIL.search(change.object or "")):
        return "green" if _has_explicit_target(change) else "yellow"

    # 3) STRUCTURE explicite (canonicalisée) :
    if change.type == "structure":
        if _STRUCT_ADDITION.match(raw_low):
            return "green"                               # ajouter/ouvrir/convertir un élément → plausible
        if _is_targeted(change):
            return "green"                               # remove/close/replace d'une cible IDENTIFIABLE
        return "yellow"                                  # ambiguë : « quelle cloison / fenêtre ? »

    # 4) Opérations sur du mobilier existant → GREEN.
    if change.type in _EXISTING_OPS:
        return "green"

    # 5) ADD : décor courant → GREEN ; sinon jugement L2.
    if change.type == "add":
        if _UNIVERSAL_DECOR.search(text):
            return "green"
        return "escalate"
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
    "confidence = how sure you are of the verdict, a number in [0,1]. "
    "For YELLOW/RED give ONE short architect sentence; for RED also give a concrete alternative. "
    'JSON only: {"verdict":"GREEN|YELLOW|RED","confidence":0.0,"reason":"","alternative":""}'
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
        try:
            conf = max(0.0, min(1.0, float(data.get("confidence", 0.7))))
        except (TypeError, ValueError):
            conf = 0.7
        return ChangeAdvice(change=change, verdict=verdict,
                            reason=str(data.get("reason", "")).strip(),
                            alternative=str(data.get("alternative", "")).strip(),
                            source="llm", confidence=conf)
    except Exception:  # noqa: BLE001 — panne de conseil → on ne bloque JAMAIS
        return ChangeAdvice(change=change, verdict=Verdict.GREEN, source="llm", confidence=0.3)


async def advise(changes: list[Change], room_type: Optional[str] = None,
                 *, client=None) -> AdviceResult:
    """Point d'entrée. L1 sur chaque changement ; escalade → L2 (si `client`), sinon GREEN
    (fail-open : sans client LLM on ne bloque que le set absurde codé en dur via L1 RED)."""
    advices: list[ChangeAdvice] = []
    for c in changes:
        verdict = _l1_classify(c, room_type)
        if verdict == "green":
            advices.append(ChangeAdvice(change=c, verdict=Verdict.GREEN, source="rules", confidence=0.97))
        elif verdict == "red":
            advices.append(ChangeAdvice(
                change=c, verdict=Verdict.RED, source="rules", confidence=0.90,
                reason=f"a {c.object or 'this'} doesn't sensibly belong in a {room_type or 'room like this'}",
                alternative=_red_alternative(c, room_type)))
        elif verdict == "yellow":
            # structure ambiguë : cible non identifiable (« quelle cloison ? »)
            advices.append(ChangeAdvice(
                change=c, verdict=Verdict.YELLOW, source="rules", confidence=0.60,
                reason=f"I can't tell exactly which {c.object or 'element'} you mean — "
                       "which side or which one should I change?"))
        else:  # escalate
            if client is not None:
                advices.append(await _l2_advise(c, room_type, client))
            else:
                # pas de client : fail-open GREEN mais confiance BASSE (non jugé) — utile au logging
                advices.append(ChangeAdvice(change=c, verdict=Verdict.GREEN, source="rules", confidence=0.5))
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
