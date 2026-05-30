"""
meta_intent.py — Wave 3.1 meta conversation intent detector.

Detects social/conversational signals BEFORE design intent routing.
These intents must never trigger image generation.

Priority order (checked top-down, first match wins):
  STOP_GENERATION  — "don't generate yet, let's discuss"
  LANGUAGE_SWITCH  — "can you speak French?" / "réponds en anglais"
  CORRECTION       — "that's not what I meant"
  FRUSTRATION      — "this is not right", "you're not listening"
  CONFUSION        — "what do you mean?"
  CLARIFICATION    — "can you explain?"
  THANKS           — "thank you" / "merci"
  GREETING         — "hello" / "bonjour"  (anchored — standalone only)
  SMALL_TALK       — "how are you?" (anchored — standalone only)
  NONE             — not a meta intent; route to design layer

Language detection is stateless: French accent characters or French marker
words → "fr", else "en". LANGUAGE_SWITCH sets target_language explicitly.
"""

from __future__ import annotations
import re
from enum import Enum
from dataclasses import dataclass


class MetaIntent(str, Enum):
    NONE              = "none"
    GREETING          = "greeting"
    LANGUAGE_SWITCH   = "language_switch"
    THANKS            = "thanks"
    CONFUSION         = "confusion"
    CORRECTION        = "correction"
    FRUSTRATION       = "frustration"
    STOP_GENERATION   = "stop_generation"
    CLARIFICATION     = "clarification"
    SMALL_TALK        = "small_talk"
    OPEN_CONVERSATION = "open_conversation"


@dataclass
class MetaClassification:
    intent:          MetaIntent
    language:        str   # detected input language: "en" | "fr"
    target_language: str   # for LANGUAGE_SWITCH: requested lang; else == language
    confidence:      float


# ── Language detection ────────────────────────────────────────────────────────

_FR_ACCENTS = re.compile(r'[àâæçéèêëîïôœùûüÿÀÂÆÇÉÈÊËÎÏÔŒÙÛÜŸ]')

_FR_MARKERS = {
    'bonjour', 'bonsoir', 'salut', 'merci', 'oui', 'parle', 'parler',
    'peux', 'pouvez', 'nous', 'vous', 'répondre', 'réponse',
    'français', 'française', 'comprends', 'comprenez', 'voudrais',
    'voulais', 'coucou', 'allô', 'allo', 'bien',
}

# Khmer Unicode range : U+1780–U+17FF (Khmer block) and U+19E0–U+19FF
# (Khmer Symbols). Two or more Khmer codepoints → KM. We require ≥2 so a
# stray punctuation symbol in an EN message can't flip the language.
_KM_CHARS = re.compile(r'[ក-៿᧠-᧿]')


def _detect_language(text: str) -> str:
    """Detect 'km' (≥2 Khmer chars), 'fr' (French markers), else 'en'."""
    if len(_KM_CHARS.findall(text)) >= 2:
        return "km"
    if _FR_ACCENTS.search(text):
        return "fr"
    words = set(re.findall(r'\b\w+\b', text.lower()))
    if words & _FR_MARKERS:
        return "fr"
    return "en"


# ── Signal patterns ───────────────────────────────────────────────────────────

# Anchored: must be the entire message (standalone greeting/thanks/small-talk)
_GREETING = re.compile(
    r"^\s*(hello|hi|hey|good\s*(morning|afternoon|evening|day)|"
    r"bonjour|bonsoir|salut|coucou|allo|allô)\s*[!.,?]?\s*$",
    re.IGNORECASE,
)

_THANKS = re.compile(
    r"^\s*(thank\s*(you|u)|thanks|cheers|ty\b|"
    r"merci(\s*(beaucoup|bien|infiniment|mille\s*fois))?|"
    r"je\s*(te|vous)\s*remercie|grand\s*merci)\s*[!.,?]?\s*$",
    re.IGNORECASE,
)

_SMALL_TALK = re.compile(
    r"^\s*(how\s*are\s*(you|things|we)\s*\??|you\s*ok\s*\??|all\s*good\s*\??|"
    r"[çc]a\s*va\s*\??|comment\s*[çc]a\s*va\s*\??|"
    r"comment\s*(tu\s*vas|vous\s*allez)\s*\??)\s*$",
    re.IGNORECASE,
)

# Unanchored: can appear anywhere in the message
_LANGUAGE_SWITCH_FR = re.compile(
    r"(speak\s*french|in\s*french|switch.*?french|"
    r"answer.*?french|respond.*?french|"
    r"r[eé]ponds?\s*en\s*fran[çc]ais|parle[rz]?\s*(en\s*)?fran[çc]ais|"
    r"en\s*fran[çc]ais|tu\s*parles?\s*fran[çc]ais|"
    r"peux.tu\s*(r[eé]pondre|parler|[eé]crire)\s*en\s*fran[çc]ais)",
    re.IGNORECASE,
)

_LANGUAGE_SWITCH_EN = re.compile(
    r"(speak\s*english|in\s*english|switch.*?english|"
    r"answer.*?english|respond.*?english|back\s*to\s*english|"
    r"continue.*?english|r[eé]ponds?\s*en\s*anglais|"
    r"parle[rz]?\s*(en\s*)?anglais|en\s*anglais)",
    re.IGNORECASE,
)

_STOP_GENERATION = re.compile(
    r"\b(don'?t\s*(generate|create|make|produce|render|show\s*me)|"
    r"no\s*(image|generation|picture|photo)(\s*yet)?|"
    r"(let'?s?\s*)?(discuss|talk|chat)\s*(first|before\s*generat\w*)|"
    r"before\s*generat\w+|"
    r"just\s*(talk|chat|discuss|have\s*a\s*conversation)|"
    r"ne\s*g[eé]n[eè]re?\s*(pas|rien)|"
    r"pas\s*(encore\s*)?(de\s*)?g[eé]n[eé]ration|"
    r"discutons?\s*d'?abord|(on\s*)?parle\s*d'?abord|"
    r"juste\s*(discuter|parler|[eé]changer)|"
    r"pas\s*d'?image(\s*pour\s*l'instant)?)\b",
    re.IGNORECASE,
)

# Wave 4.11d.1 — interrogative generation-demand anti-pattern.
#
# Real production log (backend.log 2026-05-30 09:07:02) caught a French-
# influenced phrasing : "why you don't generate?". The substring
# "don't generate" matches _STOP_GENERATION above, so the system replied
# "let's discuss first" — the OPPOSITE of what the user meant (frustrated
# demand for generation).
#
# This anti-pattern recognises interrogative shapes that contain the
# stop-generation tokens but actually MEAN "why aren't you generating?".
# When this matches, _STOP_GENERATION is suppressed and the chain
# continues to Wave 4.11d's detect_generation_demand which routes to
# GENERATE.
#
# Anchored to message-initial position with ^\s* so a real stop-generation
# instruction that happens to mention "why" elsewhere ("the reason I
# don't generate yet is why I keep asking") is not affected.
#
# Covers EN word orders : "why don't you", "why you don't" (FR/KM-
# influenced), "why aren't you", "why won't you", "why can't you",
# "how come you don't", "are you not going to", and FR : "pourquoi tu
# (ne) génères pas", "pourquoi tu génères pas".
_INTERROGATIVE_GENERATION_DEMAND = re.compile(
    r"^\s*("
    # EN — "why [you] don't/aren't/won't/can't [you] generate/generating/render/..."
    # Verbs use \w* tail to catch gerunds : "why aren't you generating?"
    r"why\s+(you\s+)?(don'?t|aren'?t|won'?t|can'?t|cannot|will\s+(you\s+)?not)\s+"
    r"(you\s+)?(generat\w*|render\w*|show\w*|creat\w*|mak\w*|"
    r"produc\w*|build\w*|do\s+it)|"
    # EN — "how come you don't/aren't generate/render..."
    r"how\s+come\s+(you\s+)?(don'?t|aren'?t|won'?t|cannot|can'?t)\s+"
    r"(you\s+)?(generat\w*|render\w*|show\w*|creat\w*|mak\w*|produc\w*|build\w*|do\s+it)|"
    # EN — "are/aren't/were you not going to generate..."
    r"(are|were|weren'?t|aren'?t)\s+you\s+(not\s+)?(going\s+to\s+)?"
    r"(generat\w*|render\w*|show\w*|creat\w*|mak\w*|produc\w*|build\w*)|"
    # FR — "pourquoi (tu) (ne) génères/rends/crées (pas)"
    r"pourquoi\s+(tu\s+)?(ne\s+)?(g[eé]n[eè]res?|rends?|cr[eé]es?|fais)\s*(pas)?|"
    r"pourquoi\s+(tu\s+)?(ne\s+)?(g[eé]n[eè]res|rends|cr[eé]es|fais)\s+pas"
    r")\b",
    re.IGNORECASE,
)

_CORRECTION = re.compile(
    r"\b(that'?s?\s*not\s*what\s*i\s*(meant|asked|wanted|said)|"
    r"not\s*what\s*i\s*(asked|wanted|meant)|"
    r"you\s*misunderstood|i\s*didn'?t\s*mean\s*that|"
    r"c'est\s*pas\s*ce\s*(que|qu')|ce\s*n'est\s*pas\s*ce\s*(que|qu')|"
    r"tu\s*(m'as\s*)?mal\s*compris|c'est\s*pas\s*du\s*tout\s*[çc]a)\b",
    re.IGNORECASE,
)

_FRUSTRATION = re.compile(
    r"\b((this|that|it)\s*(is\s*)?(not\s*right|wrong|not\s*good|awful|terrible)|"
    r"(this|that)'?s?\s*(not\s*right|wrong|not\s*good|awful|terrible)|"
    r"you'?re?\s*not\s*listening|i\s*said\s*(already|that\s*already|before)|"
    r"no\s*no\s*no|non\s*non\s*non|"
    r"still\s*(not\s*right|wrong|the\s*same)|"
    r"c'est\s*vraiment\s*pas\s*[çc]a|"
    r"tu\s*(ne\s*)?comprends?\s*(pas\s*du\s*tout|rien|vraiment\s*pas)|"
    r"encore\s*(une\s*fois|le\s*même\s*problème|la\s*même\s*chose))\b",
    re.IGNORECASE,
)

_CONFUSION = re.compile(
    r"\b(what\s*do\s*you\s*mean(\s*by)?|what\s*does\s*that\s*mean|"
    r"i\s*don'?t\s*understand|i'?m\s*(not\s*sure|confused|lost)|"
    r"what\s*\?|huh\s*\?|"
    r"je\s*(ne\s*)?comprends?\s*(pas)?|"
    r"qu'?est.ce\s*que\s*(tu|vous)\s*veu[tx]\s*dire|"
    r"[çc]a\s*veut\s*dire\s*quoi|j'?\s*comprends\s*pas)\b",
    re.IGNORECASE,
)

_CLARIFICATION = re.compile(
    r"\b(can\s*you\s*(explain|clarify|elaborate)|"
    r"(please\s*)?(explain|clarify|elaborate)\b|"
    r"tell\s*me\s*more\b|what\s*do\s*you\s*mean\s*by|"
    r"i\s*need\s*(more\s*)?(detail|clarification|explanation)|"
    r"peux.tu\s*(expliquer|pr[eé]ciser|d[eé]tailler)|"
    r"explique.moi|dis.moi\s*(plus|en\s*plus)|"
    r"plus\s*de\s*d[eé]tails)\b",
    re.IGNORECASE,
)

# Anchored: standalone opinion/reflection questions that must never trigger generation.
# "what do you think?", "does this work?", "is this the right direction?" etc.
# These are caught here (meta layer) before design routing as a safety net.
# Note: design routing also handles these via SubIntent.QUESTION, but meta catches
# them first to guarantee no generation path is entered.
_REFLECTION_QUESTION = re.compile(
    r"^\s*("
    r"what\s+do\s+you\s+think(\s+(about|of)\s+(this|it|that))?|"
    r"do\s+you\s+think\s+(this|it)\s+work[s]?|"
    r"does\s+(this|it)\s+(work|look\s+(right|good|ok)|make\s+sense)|"
    r"is\s+this\s+(right|ok|working|the\s+right\s+(direction|approach|choice))|"
    r"is\s+this\s+(good|looking\s+good)|"
    r"should\s+we\s+(do|go\s+with|keep|use)\s+this|"
    r"qu'?\s*en\s+penses.tu\s*(\?)?"
    r")\s*[.!?]?\s*$",
    re.IGNORECASE,
)

# Anchored: off-topic social questions about language capability or AI identity.
# "can you speak Khmer?", "what languages do you support?", "do you remember me?"
# These must never trigger architecture commentary or image generation.
_SOCIAL_QUESTION = re.compile(
    r"^\s*("
    r"(can|do)\s+you\s+speak\s+\w+(\s+\w+)?\s*\??|"
    r"do\s+you\s+(know|understand)\s+\w+(\s+\w+)?\s*\??|"
    r"what\s+languages?\s+(do\s+you\s+(support|speak|understand|know)|can\s+you\s+speak)\s*\??|"
    r"which\s+languages?\s+(do\s+you\s+(support|speak|understand)|can\s+you\s+(speak|use))\s*\??|"
    r"do\s+you\s+remember\s+(me|us|our\s+(last\s+)?conversation)\s*\??|"
    r"you'?re?\s+(getting\s+(better|smarter)|improving|learning)\s*[.!]?\s*|"
    r"are\s+you\s+(an?\s+)?(ai|robot|bot|machine|program|computer|virtual\s+assistant)\s*\??|"
    r"who\s+(are|made|created|built|trained)\s+you\s*\??|"
    r"how\s+(smart|intelligent|advanced|capable)\s+are\s+you\s*\??"
    r")\s*$",
    re.IGNORECASE,
)

_OPEN_CONVERSATION = re.compile(
    r"^\s*("
    # English — explicit exploration / no-direction signals
    r"i\s*(just\s*)?(want\s+to\s*(talk|chat|think|discuss)|'?m\s+just\s+(looking|exploring|browsing))|"
    r"(just\s+)?(exploring|browsing|looking\s+for\s+ideas?)|"
    r"i\s+don'?t\s+know\s+(yet|where\s+to\s+start|what\s+i\s+want)|"
    r"not\s+sure\s+(yet|where\s+to\s+start|what\s+i\s+want)|"
    r"let\s+me\s+(think|see|look)|"
    r"just\s+(thinking|browsing|looking)|"
    r"give\s+me\s+(a\s+moment|some\s+time)|"
    r"i'?m\s+(thinking|just\s+browsing)|"
    r"no\s+idea\s*(yet)?|"
    # French equivalents
    r"je\s+(veux\s+juste\s+(parler|discuter|r[eé]fl[eé]chir|explorer|regarder)|ne\s+sais\s+pas\s+(encore|par\s+o[uù]\s+commencer))|"
    r"(juste\s+)?(explorer|regarder|chercher\s+des?\s+id[eé]es?)|"
    r"pas\s+encore\s+(d[eé]cid[eé]|s[uû]r)|"
    r"laisse[rz]?(-moi)?\s+(r[eé]fl[eé]chir|voir)|"
    r"je\s+r[eé]fl[eé]chis(\s+encore)?|"
    r"pas\s+d'id[eé]e\s+(encore|pour\s+l'instant)?"
    r")\s*[.!?]?\s*$",
    re.IGNORECASE,
)


# ── Classifier ────────────────────────────────────────────────────────────────

def classify_meta_intent(user_message: str) -> MetaClassification:
    """
    Detect meta-conversational intent before design routing.
    Returns MetaIntent.NONE if the message should route to the design layer.

    Priority order ensures more specific patterns win over general ones.
    All meta intents set should_generate=False — none must trigger image generation.
    """
    msg = user_message.strip()
    lang = _detect_language(msg)

    if not msg:
        return MetaClassification(MetaIntent.NONE, lang, lang, 0.0)

    # STOP_GENERATION — highest safety priority.
    # Wave 4.11d.1 — but never fire on an interrogative form that contains
    # the stop-generation tokens while meaning the OPPOSITE intent
    # ("why you don't generate?" = frustrated demand, NOT a stop request).
    # When the anti-pattern matches, the rest of meta classification
    # continues — if no other meta intent fires, control falls to Wave
    # 4.11d detect_generation_demand which correctly routes to GENERATE.
    if (_STOP_GENERATION.search(msg)
            and not _INTERROGATIVE_GENERATION_DEMAND.search(msg)):
        return MetaClassification(MetaIntent.STOP_GENERATION, lang, lang, 0.90)

    # LANGUAGE_SWITCH — before greeting so "bonjour, parle en français" classifies correctly
    if _LANGUAGE_SWITCH_FR.search(msg):
        return MetaClassification(MetaIntent.LANGUAGE_SWITCH, lang, "fr", 0.95)
    if _LANGUAGE_SWITCH_EN.search(msg):
        return MetaClassification(MetaIntent.LANGUAGE_SWITCH, lang, "en", 0.95)

    # CORRECTION — before frustration (more specific signal)
    if _CORRECTION.search(msg):
        return MetaClassification(MetaIntent.CORRECTION, lang, lang, 0.85)

    # FRUSTRATION
    if _FRUSTRATION.search(msg):
        return MetaClassification(MetaIntent.FRUSTRATION, lang, lang, 0.80)

    # CONFUSION — before clarification (more specific signal)
    if _CONFUSION.search(msg):
        return MetaClassification(MetaIntent.CONFUSION, lang, lang, 0.80)

    # CLARIFICATION
    if _CLARIFICATION.search(msg):
        return MetaClassification(MetaIntent.CLARIFICATION, lang, lang, 0.75)

    # REFLECTION QUESTION — standalone opinion-seeking questions must never generate.
    # Anchored pattern catches "what do you think?", "does this work?", etc.
    if _REFLECTION_QUESTION.search(msg):
        return MetaClassification(MetaIntent.CLARIFICATION, lang, lang, 0.70)

    # THANKS — anchored, checked after content-bearing signals
    if _THANKS.search(msg):
        return MetaClassification(MetaIntent.THANKS, lang, lang, 0.85)

    # GREETING — anchored, standalone only
    if _GREETING.search(msg):
        return MetaClassification(MetaIntent.GREETING, lang, lang, 0.90)

    # SMALL_TALK — anchored, standalone only
    if _SMALL_TALK.search(msg):
        return MetaClassification(MetaIntent.SMALL_TALK, lang, lang, 0.75)

    # SOCIAL_QUESTION — language capability / AI identity questions.
    # Must never generate architecture commentary or trigger image generation.
    if _SOCIAL_QUESTION.search(msg):
        return MetaClassification(MetaIntent.SMALL_TALK, lang, lang, 0.80)

    # OPEN_CONVERSATION — anchored, standalone only (exploration / no-direction signals)
    if _OPEN_CONVERSATION.search(msg):
        return MetaClassification(MetaIntent.OPEN_CONVERSATION, lang, lang, 0.80)

    return MetaClassification(MetaIntent.NONE, lang, lang, 0.0)
