"""
Wave 4.7.5 — Localized Authorized Changes / Refinement Authority.

After Waves 4.7.1–4.7.4 the structural-protection stack (structural_identity,
negative anchors, openings anchor, topology locks) became strong enough that the
model sometimes reads "preserve architecture" as "change almost nothing" — so
explicit user refinements ("turn the rear area into a bedroom", "add flowers")
get ignored or under-applied.

This module produces a concise, high-signal AUTHORIZED USER CHANGES section that
grants LOCAL modification authority for the explicit request while the GLOBAL
structure lock stays in force:

  GLOBAL STRUCTURE LOCK  (unchanged)  +  LOCAL USER AUTHORITY  (new)

It overrides atmosphere / furniture / decor / room-function DEFAULTS only —
never the openings, bay window, facade openness, perspective, or apartment
identity (those stay fixed unless the user explicitly asked to change them,
which keeps it consistent with structural_identity's V3 clause and the negative
anchors, which forbid UNREQUESTED walls — not requested ones).

Pure prompt/state logic — NO model calls, NO provider SDK imports. Lightweight
heuristics only (Task 5: "do not build a giant parser").
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from .intent_classifier import is_confirmation, _REFINE as _ATMOS_REFINE

log = logging.getLogger("aih")

# ── Change-intent detection (lightweight) ────────────────────────────────────
# Any of these signals an explicit, actionable modification request. Pure
# atmosphere words ("warmer", "more luxurious") deliberately do NOT match — those
# stay on the existing atmosphere-refinement path (no section, zero cost).
_CHANGE = re.compile(
    r"\b("
    r"add|place|put|hang|install|insert|include|introduce|"
    r"move|relocate|shift|reposition|"
    r"remove|delete|take\s+out|get\s+rid\s+of|"
    r"enlarge|extend|expand|widen|shrink|reduce|resize|bigger|larger|smaller|wider|taller|"
    r"replace|swap|switch|"
    r"create|build|set\s+up|"
    r"turn\s+(?:the|this|it)?\s*\w+(?:\s+\w+)?\s+(?:into|to\s+a)|"
    r"convert\s+(?:the|this)?\s*\w+(?:\s+\w+)?\s+(?:into|to\s+a)|"
    r"transform\s+(?:the|this)?\s*\w+(?:\s+\w+)?\s+into|"
    r"repurpose|"
    r"make\s+(?:the|this|it)\s+\w+(?:\s+\w+)?\s+(?:a|an|into)\b"
    r")\b",
    re.IGNORECASE,
)

# ── Zone detection (first match wins; canonical short label) ──────────────────
_ZONE_RULES: list[tuple[re.Pattern, str]] = [
    (re.compile(r"behind\s+the\s+(?:glass\s+)?partition", re.I), "the area behind the partition"),
    (re.compile(r"\brear[\s-](right|left)\b", re.I), "the rear-{0} zone"),
    (re.compile(r"\b(?:rear|back)\s+(?:room|area|zone|wall|space|of\s+the\s+room|side)\b", re.I), "the rear zone"),
    (re.compile(r"\b(left|right)[\s-](?:side|area|wall|zone|corner)\b", re.I), "the {0} zone"),
    (re.compile(r"\btv[\s-]?(?:wall|area|zone|corner|stand)\b", re.I), "the TV zone"),
    (re.compile(r"\b(coffee|side|dining|console)\s+table\b", re.I), "the {0} table area"),
    (re.compile(r"\bnear\s+the\s+(sofa|couch|window|bay\s+window|fireplace|kitchen)\b", re.I), "near the {0}"),
    (re.compile(r"\b(kitchen|dining|living[\s-]?room|bedroom|bathroom|balcony|terrace)\s+(?:area|zone|wall|side)\b", re.I), "the {0} zone"),
]


def detect_refinement(user_instruction: str) -> tuple[bool, str]:
    """
    (has_change, zone_label). has_change=False for empty / pure-atmosphere input
    -> no section (Task 17). zone_label="" when no localized zone is detected.
    """
    text = (user_instruction or "").strip()
    if len(text) < 3:
        return False, ""
    if not _CHANGE.search(text):
        return False, ""
    zone = ""
    for pat, label in _ZONE_RULES:
        m = pat.search(text)
        if m:
            zone = label.format(*[g.lower() for g in m.groups()]) if "{0}" in label else label
            break
    return True, zone[:32]


# ── Section rendering ────────────────────────────────────────────────────────

_MAX_SECTION = 470          # Wave 4.7.8: room for an accumulated multi-item request
_MAX_REQUEST = 180          # Wave 4.7.8: was 64 — accumulated requests need the room
                            # (single requests are typically < 64 → unaffected)


def _trim_request(req: str) -> str:
    r = " ".join((req or "").split()).strip().strip('."“”')
    return r[:_MAX_REQUEST]


def build_authorized_changes_clause(user_instruction: str, iteration: int) -> str:
    """
    Wave 4.7.5 — AUTHORIZED USER CHANGES section (P1.5, V2+ only).

    "" for V1 (iteration <= 1 — atmosphere generation, no refinement) or when no
    explicit change is detected (Task 17). Concise, high-signal, localized.
    Grants local authority over atmosphere/furniture/decor/function defaults;
    explicitly keeps topology fixed unless the user requested changing it.
    """
    if iteration <= 1:
        return ""  # Task 1: never on V1
    has_change, zone = detect_refinement(user_instruction)
    if not has_change:
        return ""

    req = _trim_request(user_instruction)
    if not req:
        return ""
    zone_clause = f" ({zone})" if zone else ""

    # Tight high-signal wording so the localized zone qualifier survives within
    # the ceiling (Task 5 localized authority + Task 8 ≤~300).
    section = (
        f'AUTHORIZED USER CHANGES — Visibly apply the user\'s explicit request'
        f'{zone_clause}: "{req}". It overrides atmosphere/furniture/decor/'
        f'room-function defaults and must be clearly present. Keep openings, '
        f'bay window, facade and perspective fixed unless the user explicitly '
        f'changed them.'
    )
    if len(section) <= _MAX_SECTION:
        return section
    # Only an extremely long request would exceed this — drop the zone
    # qualifier last (it is high-signal), then hard-cap the request instead.
    section = (
        f'AUTHORIZED USER CHANGES — Visibly apply the user\'s explicit request'
        f'{zone_clause}: "{req[:80]}". It overrides atmosphere/furniture/decor/'
        f'room-function defaults and must be clearly present. Keep openings, '
        f'bay window, facade and perspective fixed unless explicitly changed.'
    )
    return section[:_MAX_SECTION]


# ── Wave 4.7.8: lightweight conversational refinement accumulation ───────────
#
# Root cause (4.7.7 audit + observed): /generate built AUTHORIZED USER CHANGES
# from ONLY the current `prompt`, so each new actionable message overwrote the
# prior pending one ("latest request wins"). This layer merges recent unresolved
# refinement requests into ONE ordered accumulated request, deterministically.
# No DB, no memory layer, no embeddings — reads only the passed history.

_FULL_REDIRECT = re.compile(
    r"\b(instead|actually|forget\s+(it|that|everything|the\s+whole|all)|"
    r"scrap\s+(it|that|everything)|start\s+over|never\s*mind|"
    r"on\s+second\s+thought|let'?s?\s+start\s+(over|again)|"
    r"oublie\s+(tout|[çc]a)|recommence|annule\s+tout)\b",
    re.IGNORECASE,
)
# Targeted negation/removal — kept as an ordered item so the LATER instruction
# wins the conflict ("add roses" … "remove flowers" → flowers removed).
_NEGATION = re.compile(
    r"\b(forget|remove|delete|no\s+more|without|get\s+rid\s+of|drop\s+the|"
    r"take\s+out|enl[eè]ve|retire|supprime|sans)\b",
    re.IGNORECASE,
)
_APPEND_MARK = re.compile(
    r"\b(also|and|plus|too|as\s+well|additionally|another|more|include|keep|"
    r"aussi|et\s|en\s+plus|garde|encore)\b",
    re.IGNORECASE,
)
# Task 5: a bare atmosphere/style switch ("switch to Japandi", "make it tropical")
# is NOT a modification — it flows via style_label and merely RESTYLES. It must
# neither be collected (it is not an AUTHORIZED modification) nor reset prior
# modifications (the bedroom/roses persist under the new atmosphere). Note:
# refinement_authority._CHANGE matches the bare verb "switch", so this guard is
# required to keep "switch to Japandi" out of the accumulated request.
_ATMO_SWITCH = re.compile(
    r"\b(japandi|zen\s*retreat|zen|bali\s*sanctuary|bali|tropical(\s*escape)?|"
    r"nordic(\s*warmth)?|warm\s*modern|soft\s*luxury|dark\s*contemporary|"
    r"desert(\s*luxe)?|nature\s*retreat|sanctuary|contemporary|minimalist|"
    r"scandinavian|industrial|mediterranean|boho|art\s*deco)\b"
    r"|\b(switch|change|go)\s+(to|with|for)\s+(the\s+)?"
    r"(style|atmosphere|mood|look|vibe|theme|aesthetic|direction)\b"
    r"|\bdifferent\s+(style|atmosphere|mood|look|vibe|direction)\b",
    re.IGNORECASE,
)
_WINDOW = 6  # Task 3: bounded — at most 6 prior user turns scanned


def _is_atmosphere_switch(text: str) -> bool:
    """Atmosphere/style switch with no concrete object/structural modification."""
    if not text or not _ATMO_SWITCH.search(text):
        return False
    # If it ALSO carries a concrete object/structural verb ("switch the sofa to
    # leather"), it is a real modification — let it accumulate normally.
    from .intent_classifier import _DESIGN_CONVERSION as _DC, _STRUCTURAL as _ST
    return not (_DC.search(text) or _ST.search(text)
                or _NEGATION.search(text)
                or re.search(r"\b(add|remove|move|enlarge|replace\s+the\s+\w)", text, re.I))


@dataclass(frozen=True)
class AccumulatedRefinement:
    text: str                 # merged, ordered request fed to AUTHORIZED USER CHANGES
    items: tuple[str, ...]    # ordered constituent requests (oldest → newest)
    append_count: int
    replace_detected: bool


def _is_actionable(text: str) -> bool:
    """A history/user turn that should accumulate: a concrete object/structural
    change, an atmosphere-refine adjective ("warmer"/"more …"), or a targeted
    negation/removal (so conflicts resolve by latest-wins ordering).

    Deliberately EXCLUDES bare atmosphere redirects ("switch to Japandi") — they
    carry no change/refine/negation token, flow via style_label, and so leave
    accumulated modifications intact (Task 5)."""
    if not text:
        return False
    return (bool(detect_refinement(text)[0])
            or bool(_ATMOS_REFINE.search(text))
            or bool(_NEGATION.search(text)))


def accumulate_refinements(history: list[dict], current_prompt: str) -> AccumulatedRefinement:
    """
    Merge recent unresolved refinement requests + the current one into a single
    ordered request. Boundaries (Task 3 / 7 / 8):
      - a prior CONFIRMATION ("go ahead"/"ok"/…) ⇒ that batch was already sent
        to generate → reset (no cross-generation carry-over).
      - a FULL_REDIRECT ("instead"/"actually"/"start over") ⇒ reset older
        context (replace), keep the redirecting request onward.
      - atmosphere switches ("switch to Japandi") carry no _CHANGE verb → not
        collected here; they flow via style_label, so accumulated modifications
        persist and merely restyle (Task 5).
    Falls back to the current prompt when nothing accumulates (zero regression).
    """
    collected: list[str] = []
    replace_detected = False

    # Prior user turns, newest → oldest, bounded.
    prior_user: list[str] = []
    for m in reversed(history or []):
        if not isinstance(m, dict):
            continue
        if str(m.get("role", "")).lower() != "user":
            continue
        c = str(m.get("content", "")).strip()
        if not c:
            continue
        prior_user.append(c)
        if len(prior_user) >= _WINDOW:
            break

    cur = (current_prompt or "").strip()

    # Wave 4.9.3b — confirmation-echo exemption (post-freeze critical bugfix).
    # The frontend appends the triggering confirmation ("go ahead") to the
    # history it sends to /generate, so that same confirmation ALSO appears as
    # the NEWEST prior_user turn (prior_user[0]; list is newest→oldest). That
    # single trailing echo must NOT act as a historical reset boundary — it is
    # the confirmation EXECUTING the pending batch, not a past completed one.
    # Drop exactly that one turn, and ONLY when current_prompt itself is that
    # same confirmation. Older confirmations stay reset boundaries, so
    # cross-generation anti-leak is byte-unchanged.
    _echo_exempted = (
        bool(prior_user) and bool(cur) and is_confirmation(cur)
        and is_confirmation(prior_user[0])
        and prior_user[0].strip().lower() == cur.lower()
    )
    if _echo_exempted:
        prior_user = prior_user[1:]
        log.debug("[RefinementAccumulation] confirmation_echo_exempted=True")

    # Replay oldest → newest so ordering (and latest-wins conflicts) is natural.
    for txt in reversed(prior_user):
        if is_confirmation(txt):
            collected = []           # previous batch already generated
            replace_detected = False
            continue
        if _FULL_REDIRECT.search(txt):
            collected = []           # redirect drops older context
            replace_detected = True
            if _is_actionable(txt) and not _is_atmosphere_switch(txt):
                collected.append(txt)
            continue
        if _is_atmosphere_switch(txt):
            continue                 # Task 5: restyle only — modifications persist
        if _is_actionable(txt):
            collected.append(txt)

    if cur and not is_confirmation(cur):
        if _FULL_REDIRECT.search(cur):
            collected = []
            replace_detected = True
            if _is_actionable(cur) and not _is_atmosphere_switch(cur):
                collected.append(cur)
        elif _is_atmosphere_switch(cur):
            pass                     # Task 5: atmosphere only — keep modifications
        elif _is_actionable(cur):
            collected.append(cur)

    # De-duplicate consecutive identical asks; tidy each item.
    dedup: list[str] = []
    for c in collected:
        c = " ".join(c.split()).strip().strip('."“”')
        if c and (not dedup or dedup[-1].lower() != c.lower()):
            dedup.append(c)

    text = "; ".join(dedup)
    return AccumulatedRefinement(
        text=text,
        items=tuple(dedup),
        append_count=len(dedup),
        replace_detected=replace_detected,
    )
