"""
intent_classifier.py — Wave 2.5 conversational intent classifier.

Classifies user messages into conversation vs generation intent.
Deterministic keyword/pattern scoring. No LLM calls.

Architecture:
  ConversationIntent  — top-level routing: CONVERSATION | GENERATE | MIXED
  SubIntent           — fine-grained intent for response generation

Iteration 1 is always GENERATE + REDESIGN regardless of message content.
The first Vision always renders.
"""

from __future__ import annotations
import re
from enum import Enum
from dataclasses import dataclass


class ConversationIntent(str, Enum):
    CONVERSATION = "conversation"   # answer only — no image generation
    GENERATE = "generate"           # trigger image generation
    MIXED = "mixed"                 # architect answers first, then offers generation direction


class SubIntent(str, Enum):
    REDESIGN = "redesign"                     # Vision 1 — first render
    REFINE_ATMOSPHERE = "refine_atmosphere"   # deepen the existing atmosphere
    LOCAL_EDIT = "local_edit"                 # surgical object/colour/placement change
    STRUCTURAL_CHANGE = "structural_change"   # architectural evolution
    REDIRECT = "redirect"                     # switch atmosphere or direction entirely
    QUESTION = "question"                     # user asking a design question
    PRAISE = "praise"                         # user expressing satisfaction
    GENERAL = "general"                       # unclassified fallback


@dataclass
class IntentClassification:
    intent: ConversationIntent
    sub_intent: SubIntent
    confidence: float
    reasoning: str  # for logging only — never exposed to user


# ── Signal patterns ────────────────────────────────────────────────────────────

_PRAISE = re.compile(
    r"\b(love\s*(it|this|that|the)?|perfect|great\s*(job|result|work)?|amazing|beautiful|"
    r"stunning|gorgeous|looks?\s*(so\s*)?(good|great|amazing|beautiful)|"
    r"like\s*(it|this|that)|that'?s?\s*(it|nice|good|perfect)|yes\s*please|exactly|"
    r"well\s*done|nailed\s*it|spot\s*on|"
    # French
    r"j'adore|j'aime\s*(beaucoup|bien|vraiment|[çc]a)?|parfait|magnifique|superbe|"
    r"g[eé]nial(e)?|bravo|incroyable|trop\s*bien|c'est\s*(beau|bien|parfait|super|g[eé]nial|[çc]a))\b",
    re.IGNORECASE,
)

_QUESTION = re.compile(
    r"\b(what\s*(if|do|would|about|are|does|should)|would\s*(it|this|that|a|an|the)|"
    r"should\s*(i|we|it)|is\s*(this|it|that)\s*(too|right|good|ok)|does\s+(this|it|that)|"
    r"do\s*you\s*(think|feel|see|recommend|suggest)|how\s*(would|does|about|do|can)|"
    r"can\s*(we|i|you)|which\s*(one|is|would|do)|thoughts?\s*(on)?|"
    r"opinion|any\s*(suggestions?|ideas?|thoughts?|recommendations?)|"
    # French
    r"qu'?en\s*penses-tu|que\s*penses-tu|penses-tu|crois-tu|selon\s*toi|"
    r"est-ce\s*qu[e']|est-ce\s*que|marcherait|[çc]a\s*march|[çc]a\s*irait|"
    r"qu'est-ce|comment\s*(tu\s*(vois|penses|dirais)|[çc]a|on\s*pourrait)|"
    r"[àa]\s*ton\s*avis|tu\s*(penses|crois|vois|dirais)|non\s*\?)\b",
    re.IGNORECASE,
)

_REDIRECT = re.compile(
    r"\b(switch\s*(to|this|it)|try\s+(japandi|tropical|nordic|warm\s*modern|"
    r"soft\s*luxury|dark|desert|nature|contemporary)|"
    r"change\s*(to|the\s*(style|atmosphere|direction|look))|go\s+(for|with)|"
    r"different\s*(style|atmosphere|direction|feel|look|vibe)|instead|"
    r"something\s*else|another\s*(style|direction|atmosphere|look|vibe|option)|"
    r"completely\s*different|start\s*over|fresh\s*(direction|start)|"
    # French
    r"essaie\s+(japandi|tropical|nordique|chaleureux|sombre|d[eé]sert|nature)|"
    r"change\s+de\s+(style|direction|atmosph[eè]re|ambiance)|"
    r"passe\s+(en|au|[aà])\s+\w|quelque\s*chose\s*de\s*(diff[eé]rent|autre)|"
    r"compl[eè]tement\s*diff[eé]rent|repartir\s*([aà]\s*z[eé]ro)?|"
    r"nouvelle\s*direction|tout\s*(diff[eé]rent|changer))\b",
    re.IGNORECASE,
)

_STRUCTURAL = re.compile(
    r"\b(open\s*up|open\s*the|knock\s*(down|out|through)|remove\s*(the\s*)?wall|"
    r"add\s+(a\s+|an\s+)?(window|door|skylight|opening|arch|partition)|"
    r"extend|expand|widen|raise\s*(the\s*)?ceiling|lower\s*(the\s*)?ceiling|"
    r"demolish|structural|"
    # French
    r"abattre|casser\s*(le\s*|un\s*)?mur|ouvrir\s*(le\s*|la\s*|l'|[çc]a)?|"
    r"agrandir|[eé]largir|sur[eé]lever|rehausser|d[eé]molir|"
    r"ajouter\s+une?\s*(fen[eê]tre|porte|velux|lucarne|ouverture|arcade))\b",
    re.IGNORECASE,
)

_REFINE = re.compile(
    r"\b(more|less|darker|lighter|warmer|cooler|softer|harder|bolder|subtler|"
    r"minimal(ist)?|maximalist|luxurious|hotel(-like)?|push\s*(it|further|more)?|"
    r"deepen|increase|reduce|intensif|tone\s*(it|down|up)|"
    r"stronger|richer|quieter|calmer|even\s*more|a\s*bit\s*more|"
    # French — intensity/degree adverbs and their imperative forms
    r"plus\b|moins\b|davantage|encore\s+plus|beaucoup\s+plus|un\s+peu\s+plus|"
    r"fais.?le\s+plus|rends.?le\s+(plus|plus\s+\w+)|pousse\s*(encore|plus|davantage)?|"
    r"intensifie|renforce|att[eé]nue|approfondi|enrichi)\b",
    re.IGNORECASE,
)

_LOCAL_EDIT = re.compile(
    r"\b(add\s+(a|an|the|some)?|remove\s+(the|a)?|change\s+(the|a)?|replace\s+(the|a)?|"
    r"swap\s+(the|a)?|move\s+(the|a)?|put\s+(a|an|the)?|take\s+(out|away)|"
    r"get\s+rid\s+of|use\s+(a|an|different)|try\s+(a|an|the)|"
    r"different\s+(colour|color|material|fabric|finish|texture)|"
    # French — local edit verbs and show-me generation triggers
    r"ajoute|ajouter|enl[eè]ve|enlever|retire|retirer|remplace|remplacer|"
    r"d[eé]place|d[eé]placer|pose\s+(un|une)|mets\s+(un|une)|"
    r"montre-moi\s+(avec|sans|un|une|le|la|les)|essaie\s+(un|une|avec|le|la)|"
    r"utilise\s+(un|une)|diff[eé]rent(e)?\s+(canap[eé]|tapis|tissu|mati[eè]re|finition|texture))\b",
    re.IGNORECASE,
)

# Explicit generation commands and short approval phrases after an assistant proposal.
# Matched BEFORE the word_count fallback so they reliably trigger GENERATE.
# Deliberately narrow: must be a direct command/approval, not a question or advice-request.
_EXPLICIT_GENERATE = re.compile(
    r"^(yes\s+)?(ok\s+)?(please\s+)?"
    r"(generate|render|show(\s+me)?(\s+(it|that|this|the\s+result))?|"
    r"do\s+it|try\s+it|can\s+try|go\s+ahead|let'?s?\s+(see|go|try)|"
    r"go\s+for\s+it|make\s+it|just\s+do\s+it|proceed|"
    r"ok\s+try|ok\s*,?\s*go|sounds?\s+good,?\s*(let'?s?\s*(go|try|see))?|"
    r"yes\s+(let'?s?|please)|sure\s*(,\s*go\s*ahead)?|alright\s*(,?\s*let'?s?\s*(go|try|see))?|"
    # French approval phrases
    r"g[eé]n[eè]re|affiche(-le|-moi)?|montre(-le|-moi)?|vas-y|allez|lance(-toi)?|"
    r"oui\s*(vas-y|allons-y|s'?il\s*te\s*pla[iî]t)?|allons-y|d'accord\s*(vas-y)?|"
    r"ok\s*(vas-y|[çc]a\s*marche)|[çc]a\s*marche\s*(,?\s*vas-y)?"
    r")[\s!.]*$",
    re.IGNORECASE,
)


# ── Wave 4.7.7: gated conversational generate confirmations ──────────────────
#
# Two audit-proven issues (Wave 4.7.7a): (A) common confirmation phrases
# ("continue", bare "ok"/"yes", "let's do it") are not recognized; (B) the tone
# layer vetoes a valid GENERATE. The fix is ADDITIVE and strictly GATED: a short
# confirmation only promotes to GENERATE when a concrete design request is
# genuinely PENDING (expressed earlier, assistant has responded, not yet
# generated). classify_intent() itself is unchanged — no existing path is
# downgraded; this only adds a promotion when pending intent exists.

# Anchored: the WHOLE message must be a bare confirmation. "ok but change the
# sofa" is NOT a confirmation (it carries a new edit) and routes normally.
_CONFIRMATION = re.compile(
    r"^\s*(yes|yeah|yep|yup|ya|ok|okay|k|sure|alright|all\s*right|right|"
    r"continue|go\s+ahead|go\s+on|do\s+it|just\s+do\s+it|"
    r"let'?s?\s+(do\s+it|go|see|try|continue)|go\s+for\s+it|make\s+it|"
    r"proceed|generate|render|show(\s+me)?(\s+(it|that|the\s+result))?|"
    r"try\s+it|please\s+do|do\s+that|sounds?\s+good|that\s+works|perfect\s+go|"
    # French
    r"oui|ouais|ok\s+vas-y|d'accord|vas-y|allons-y|on\s+y\s+va|continue[zr]?|"
    r"g[eé]n[eè]re|affiche(-le|-moi)?|fais(-le)?|c'est\s+bon|parfait\s+vas-y"
    r")[\s!.]*$",
    re.IGNORECASE,
)

# Concrete "convert/turn this space into a <room>" — intent_classifier's
# _STRUCTURAL does not catch functional reassignment ("turn the rear room into
# a bedroom"), the flagship pending case.
_DESIGN_CONVERSION = re.compile(
    r"\b(turn|convert|transform|make|change|repurpose|use)\s+(the\s+|this\s+|it\s+|that\s+)?"
    r"\w+(\s+\w+){0,3}?\s+(into\s+a|to\s+a|as\s+a|a)\s+"
    r"(bed\s*room|bedroom|office|studio|kitchen|lounge|nursery|gym|library|"
    r"closet|dressing|dining|guest\s+room|play\s*room|workspace)",
    re.IGNORECASE,
)


def is_confirmation(message: str) -> bool:
    """True if the whole message is a bare go-ahead confirmation (Task 2)."""
    return bool(_CONFIRMATION.match((message or "").strip()))


def _has_design_request(text: str) -> bool:
    """A prior user turn carrying a concrete design / edit / refine / redirect /
    functional-conversion request (reuses existing compiled patterns)."""
    if not text:
        return False
    return bool(
        _DESIGN_CONVERSION.search(text) or _STRUCTURAL.search(text)
        or _REDIRECT.search(text) or _LOCAL_EDIT.search(text)
        or _REFINE.search(text)
    )


def pending_design_sub_intent(history: list[dict]) -> SubIntent | None:
    """
    Lightweight pending-design-intent detector (Task 1). NO new state — reads
    only the already-passed conversation history.

    Pending == the last turn is the ASSISTANT's reply (it responded to / proposed
    a change) AND the most recent prior USER turn carried a concrete design
    request. Returns that request's SubIntent, else None.
    """
    if not history:
        return None
    last = history[-1] if isinstance(history[-1], dict) else {}
    if str(last.get("role", "")).lower() not in ("ai", "assistant"):
        return None  # not in an 'assistant proposed, awaiting confirmation' shape
    scanned = 0
    for msg in reversed(history[:-1]):
        if not isinstance(msg, dict) or str(msg.get("role", "")).lower() != "user":
            continue
        text = str(msg.get("content", "")).strip()
        if not text:
            continue
        scanned += 1
        if _DESIGN_CONVERSION.search(text) or _STRUCTURAL.search(text):
            return SubIntent.STRUCTURAL_CHANGE
        if _REDIRECT.search(text):
            return SubIntent.REDIRECT
        if _LOCAL_EDIT.search(text) and not _REFINE.search(text):
            return SubIntent.LOCAL_EDIT
        if _REFINE.search(text):
            return SubIntent.REFINE_ATMOSPHERE
        if scanned >= 3:  # only the recent window; avoid stale matches
            break
    return None


def resolve_confirmation(message: str, history: list[dict]) -> IntentClassification | None:
    """
    Wave 4.7.7 single entry point. Returns a GENERATE classification ONLY when
    the message is a bare confirmation AND a concrete design request is pending;
    otherwise None (caller keeps the normal classify_intent result).
    """
    if not is_confirmation(message):
        return None
    sub = pending_design_sub_intent(history)
    if sub is None:
        return None
    return IntentClassification(
        intent=ConversationIntent.GENERATE,
        sub_intent=sub,
        confidence=0.92,
        reasoning="Confirmation with pending design intent (Wave 4.7.7)",
    )


# ── Classifier ────────────────────────────────────────────────────────────────

def classify_intent(user_message: str, iteration: int) -> IntentClassification:
    """
    Classify user message into conversation/generation intent.

    Returns IntentClassification with top-level intent and finer sub_intent.
    """
    # Iteration 1 always triggers generation — there is nothing to chat about yet
    if iteration == 1:
        return IntentClassification(
            intent=ConversationIntent.GENERATE,
            sub_intent=SubIntent.REDESIGN,
            confidence=1.0,
            reasoning="Vision 1 always generates",
        )

    msg = user_message.strip()

    if not msg:
        return IntentClassification(
            intent=ConversationIntent.GENERATE,
            sub_intent=SubIntent.GENERAL,
            confidence=0.7,
            reasoning="Empty message on iteration 2+",
        )

    has_praise      = bool(_PRAISE.search(msg))
    has_question    = bool(_QUESTION.search(msg))
    has_redirect    = bool(_REDIRECT.search(msg))
    has_structural  = bool(_STRUCTURAL.search(msg))
    has_refine      = bool(_REFINE.search(msg))
    has_local       = bool(_LOCAL_EDIT.search(msg))
    has_explicit_gen = bool(_EXPLICIT_GENERATE.match(msg))
    word_count      = len(msg.split())

    # Structural always generates — it maps to STRUCTURAL_TRANSFORMATION path
    if has_structural:
        return IntentClassification(
            intent=ConversationIntent.GENERATE,
            sub_intent=SubIntent.STRUCTURAL_CHANGE,
            confidence=0.90,
            reasoning="Structural signal detected",
        )

    # Explicit atmosphere redirect always generates
    if has_redirect:
        return IntentClassification(
            intent=ConversationIntent.GENERATE,
            sub_intent=SubIntent.REDIRECT,
            confidence=0.85,
            reasoning="Atmosphere redirect signal",
        )

    # Pure praise with no change intent → conversation
    if has_praise and not has_refine and not has_local:
        return IntentClassification(
            intent=ConversationIntent.CONVERSATION,
            sub_intent=SubIntent.PRAISE,
            confidence=0.80,
            reasoning="Praise without change request",
        )

    # Pure design question with no change intent → conversation
    if has_question and not has_refine and not has_local:
        return IntentClassification(
            intent=ConversationIntent.CONVERSATION,
            sub_intent=SubIntent.QUESTION,
            confidence=0.75,
            reasoning="Design question without generation trigger",
        )

    # Question + change intent → mixed (architect answers, then offers generation)
    if has_question and (has_refine or has_local):
        sub = SubIntent.LOCAL_EDIT if has_local and not has_refine else SubIntent.REFINE_ATMOSPHERE
        return IntentClassification(
            intent=ConversationIntent.MIXED,
            sub_intent=sub,
            confidence=0.70,
            reasoning="Question with embedded change intent",
        )

    # Clear refinement signal → generate (maps to STYLE_REFINEMENT path)
    if has_refine:
        return IntentClassification(
            intent=ConversationIntent.GENERATE,
            sub_intent=SubIntent.REFINE_ATMOSPHERE,
            confidence=0.80,
            reasoning="Atmosphere refinement signal",
        )

    # Clear local edit signal → generate (maps to LOCAL_EDIT path)
    if has_local:
        return IntentClassification(
            intent=ConversationIntent.GENERATE,
            sub_intent=SubIntent.LOCAL_EDIT,
            confidence=0.75,
            reasoning="Local edit signal",
        )

    # Explicit generation command / short approval phrase after a proposal
    if has_explicit_gen:
        return IntentClassification(
            intent=ConversationIntent.GENERATE,
            sub_intent=SubIntent.REFINE_ATMOSPHERE,
            confidence=0.90,
            reasoning="Explicit generation command or approval phrase",
        )

    # Short unclassified messages lean conversation; longer lean mixed
    if word_count <= 5:
        return IntentClassification(
            intent=ConversationIntent.CONVERSATION,
            sub_intent=SubIntent.GENERAL,
            confidence=0.50,
            reasoning="Short unclassified message",
        )

    return IntentClassification(
        intent=ConversationIntent.MIXED,
        sub_intent=SubIntent.GENERAL,
        confidence=0.40,
        reasoning="Unclassified longer message",
    )
