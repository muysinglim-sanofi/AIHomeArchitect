"""
PR-Router (Ayden Companion) — TurnIntent facade.

This module does NOT create a second intent system. `ConversationIntent`,
`SubIntent` and `MetaIntent` stay intact and authoritative for their layers.
`TurnIntent` is the *higher-level* companion intent for a single turn ; the
router CONSOLIDATES the existing classifiers and maps their output to one
TurnIntent, adding only the genuinely-missing high-value categories:

  - RESULT_EXPLANATION : "why did it put a kitchen / no TV / change the wall".
    Not a static FAQ topic, not design advice — "explain THIS generation".
    (Needs the PR0 situational context to answer ; handler lands with Support.)
  - PREFERENCE         : "I prefer version 2 / the previous one was better".
    Not design, not support, not a command — information to remember.

Strangler-fig : the router is thin and additive. /chat keeps its existing,
tested routing ; the router only resolves the single TurnIntent label (and is
the home of the deterministic Out-of-Scope detector). No LLM. No image touch.
"""
import re
from enum import Enum
from typing import Optional

from prompt_engine.intent_classifier import ConversationIntent
# Out-of-Scope lives in its own module ; the router re-exports it so callers
# have a single conversational-routing entry point.
from prompt_engine.out_of_scope import detect_out_of_scope, get_out_of_scope_reply

__all__ = [
    "TurnIntent",
    "detect_result_explanation",
    "detect_preference",
    "detect_design_opinion_question",
    "detect_out_of_scope",
    "get_out_of_scope_reply",
    "resolve_turn_intent",
]


class TurnIntent(str, Enum):
    META = "meta"
    ACTION_REFINE = "action_refine"
    PRODUCT_HELP = "product_help"
    DESIGN_ADVICE = "design_advice"
    RESULT_EXPLANATION = "result_explanation"
    PREFERENCE = "preference"
    AMBIGUOUS = "ambiguous"
    OUT_OF_SCOPE = "out_of_scope"
    UNKNOWN = "unknown"


# ── New detector : RESULT_EXPLANATION ─────────────────────────────────────────
# "Explain what the system DID" — the subject is the system (il / it / you /
# ayden), not the user. That subject test is what separates it from design
# advice ("pourquoi je devrais mettre du bois" stays DESIGN_ADVICE).
_RESULT_EXPLANATION_PATTERNS = [
    r"\bpourquoi\s+(il|elle|[çc]a|on|l'?ia|ayden|le\s+syst[èe]me|t'?as|tu\s+as)\b",
    r"\bpourquoi\s+(pas\s+de|aucun|il\s+n'?a\s+pas|il\s+n'?y\s+a\s+pas|il\s+manque)\b",
    r"\bpourquoi\s+avoir\s+(mis|chang|ajout|enlev|retir|fait|suppr|remplac)",
    r"\bwhy\s+(did|does|do|is|are|isn'?t|aren'?t|has|have)\s+(it|you|there|the\s+\w+)\b",
    r"\bwhy\s+(no|not|isn'?t\s+there|is\s+there\s+no)\b",
    # Negative / preservation-complaint forms ("why didn't you preserve my room",
    # "why isn't my architecture kept", "why did my room change") — these explain
    # what the system DID (or failed to keep) → dynamic Designer voice, not a
    # static FAQ. Excludes opinion-advice ("why should I…").
    r"\bwhy\s+(did\s*n'?t|do\s*n'?t|does\s*n'?t|was\s*n'?t|were\s*n'?t)\s+(you|it|ayden)\b",
    r"\bwhy\s+(is|are|isn'?t|aren'?t)\s+(my|the)\s+\w+\s+(not\s+)?(preserved|kept|the\s+same|changed|different|gone|missing)\b",
    r"\bwhy\s+did\s+(my|the)\s+\w+\s+(change|move|disappear|go|shift)\b",
    r"\bpourquoi\s+(tu\s+n'?as\s+pas|il\s+n'?a\s+pas|ce\s+n'?est\s+pas|ce\s+n'?a\s+pas)\b",
    r"\bpourquoi\s+(ma|mon|mes)\s+\w+\s+(a\s+chang|n'?(est|a)\s+pas)\b",
]
_RESULT_EXPLANATION_COMPILED = [re.compile(p, re.IGNORECASE) for p in _RESULT_EXPLANATION_PATTERNS]


def detect_result_explanation(message: str) -> bool:
    """True when the user asks the system to explain what IT did to the result."""
    if not message or not message.strip():
        return False
    return any(p.search(message) for p in _RESULT_EXPLANATION_COMPILED)


# ── New detector : PREFERENCE ─────────────────────────────────────────────────
_PREFERENCE_PATTERNS = [
    r"\bje\s+pr[ée]f[èe]re\b",
    r"\bi\s+prefer\b",
    r"\bje\s+n'?aime\s+pas\s+(celle|cette|[çc]a|cell)",
    r"\b(la\s+)?(version\s+)?(pr[ée]c[ée]dente?|d'?avant|celle\s+d'?avant)\b.*\b(mieux|meilleur|pr[ée]f)",
    r"\b(était|est)\s+(mieux|meilleur)\b",
    r"\b(previous|last)\s+(one|version)\b.*\b(better|nicer|prefer)",
    r"\bgard(e|er|ez)\s+plut[ôo]t\b",
    r"\bkeep\s+(the\s+)?(previous|that\s+one|this\s+style)\b",
]
_PREFERENCE_COMPILED = [re.compile(p, re.IGNORECASE) for p in _PREFERENCE_PATTERNS]


def detect_preference(message: str) -> bool:
    """True when the user expresses a preference between versions/styles."""
    if not message or not message.strip():
        return False
    return any(p.search(message) for p in _PREFERENCE_COMPILED)


# ── New detector : DESIGN_OPINION_QUESTION ────────────────────────────────────
# The user ASKS for a design opinion rather than commanding a change. The base
# classifier reads an elliptical proposal like "I put the TV in front of the
# window?" as an imperative → GENERATE, ignoring the "?" + opinion framing. This
# detector lets /chat downgrade that GENERATE to a DESIGN_ADVICE turn so the
# Designer voice answers with a recommendation instead of silently generating.
# High precision (validated 10/10 opinions, 0 false-positives on commands):
# explicit opinion frames + choice questions ("A or B?") + a first-person
# tentative proposal ENDING in "?". Plain imperatives ("make it warmer", "add a
# lamp", "can you make it warmer?") do NOT match.
_DESIGN_OPINION_PATTERNS = [
    r"\bshould\s+i\b",
    r"\bdo\s+you\s+think\b",
    r"\bwhat\s+do\s+you\s+think\b",
    r"\byour\s+opinion\b",
    r"\bdo\s+you\s+(recommend|suggest)\b",
    r"\bwould\s+you\s+(recommend|suggest|go)\b",
    r"\bis\s+it\s+(a\s+)?(good|bad|better|wise|smart|ok|okay|fine)\b",
    r"\b(good|bad)\s+idea\b",
    r"\bbetter\s+to\b",
    r"\b\w+\s+or\s+\w+\s*\?",                      # choice question: "round or rectangular?"
    r"\bdois-je\b",
    r"\bdevrais-je\b",
    r"\bqu'en\s+(penses|dis)-tu\b",
    r"\bton\s+avis\b",
    r"\b(bonne|mauvaise)\s+id[ée]e\b",
    r"\bvaut-il\s+mieux\b",
    r"\btu\s+(en\s+)?penses\b",
    r"^\s*(i|je)\s+\w+.*\?\s*$",                   # 1st-person tentative proposal ending in "?"
]
_DESIGN_OPINION_COMPILED = [re.compile(p, re.IGNORECASE) for p in _DESIGN_OPINION_PATTERNS]


def detect_design_opinion_question(message: str) -> bool:
    """True when the user asks for a design opinion (vs commanding a change)."""
    if not message or not message.strip():
        return False
    return any(p.search(message) for p in _DESIGN_OPINION_COMPILED)


# ── Facade : resolve one TurnIntent from existing + new signals ────────────────
def resolve_turn_intent(
    message: str,
    *,
    meta: bool = False,
    oos: bool = False,
    ambiguity: bool = False,
    product: bool = False,
    intent_class=None,
) -> TurnIntent:
    """
    Map the already-computed classifier signals (+ the two new detectors) onto a
    single TurnIntent. Pure and cheap : it does NOT re-run the expensive
    classifiers — the caller passes what it already resolved.

    Priority (first match wins):
      META > OUT_OF_SCOPE > AMBIGUOUS > PREFERENCE > RESULT_EXPLANATION >
      PRODUCT_HELP > ACTION_REFINE > DESIGN_ADVICE > UNKNOWN
    """
    if meta:
        return TurnIntent.META
    if oos:
        return TurnIntent.OUT_OF_SCOPE
    if ambiguity:
        return TurnIntent.AMBIGUOUS
    if detect_preference(message):
        return TurnIntent.PREFERENCE
    if detect_result_explanation(message):
        return TurnIntent.RESULT_EXPLANATION
    if product:
        return TurnIntent.PRODUCT_HELP
    if intent_class is not None:
        ci = intent_class.intent
        if ci in (ConversationIntent.PRODUCT_HELP, ConversationIntent.SUPPORT):
            return TurnIntent.PRODUCT_HELP
        if ci == ConversationIntent.GENERATE:
            return TurnIntent.ACTION_REFINE
        if ci in (
            ConversationIntent.CONVERSATION,
            ConversationIntent.MIXED,
            ConversationIntent.DESIGN_DISCUSSION,
        ):
            return TurnIntent.DESIGN_ADVICE
    return TurnIntent.UNKNOWN
