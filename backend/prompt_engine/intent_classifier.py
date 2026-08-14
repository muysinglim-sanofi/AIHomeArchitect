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
    # Wave 4.11a additions — surfaced when the pre-filter matches BEFORE
    # the design-routing logic runs. Each carries should_generate=False
    # downstream in main.py so the product / support / discussion paths
    # never accidentally trigger an image generation.
    PRODUCT_HELP = "product_help"           # user asks about a feature ("how do I…")
    DESIGN_DISCUSSION = "design_discussion" # open-ended design question, V2+
    SUPPORT = "support"                     # error / bug / help request


class SubIntent(str, Enum):
    REDESIGN = "redesign"                     # Vision 1 — first render
    REFINE_ATMOSPHERE = "refine_atmosphere"   # deepen the existing atmosphere
    LOCAL_EDIT = "local_edit"                 # surgical object/colour/placement change
    STRUCTURAL_CHANGE = "structural_change"   # architectural evolution
    REDIRECT = "redirect"                     # switch atmosphere or direction entirely
    QUESTION = "question"                     # user asking a design question
    PRAISE = "praise"                         # user expressing satisfaction
    GENERAL = "general"                       # unclassified fallback
    # Wave 4.11a SubIntent variants — paired with the new top-level intents.
    PRODUCT_HELP = "product_help"
    DESIGN_DISCUSSION = "design_discussion"
    SUPPORT = "support"
    # Wave 4.11b — negative feedback is a special case of DESIGN_DISCUSSION
    # (top-level intent stays DESIGN_DISCUSSION, should_generate=False). The
    # dedicated sub_intent lets generate_chat_response surface a calm,
    # diagnostic-oriented response pool instead of falling through to the
    # generic chat templates.
    NEGATIVE_FEEDBACK = "negative_feedback"
    # Wave 4.11e — design brief summarization. User asks "summarize what
    # I want" / "recap" / "what do you understand?". Routes to a dedicated
    # handler in main.py that emits a bulleted summary derived from
    # refinement_state, NEVER triggers generation. The user follows up
    # with "yes / generate" → Wave 4.11d generation_demand catches it.
    SUMMARIZE_DESIGN_BRIEF = "summarize_design_brief"


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
    # Wave 4.11c — added brighter / daylight / airier (validation gap : a bare
    # "Make it brighter." fell through to CONVERSATION because the brightness
    # axis wasn't in the refinement vocabulary, even though darker/lighter were.
    # Wave 4.11d — added cozy / elegant / modern / premium / sleek /
    # sophisticated / spacious — single-adjective design directives that
    # should bias toward GENERATE rather than fall through to discussion.
    r"\b(more|less|darker|lighter|brighter|warmer|cooler|softer|harder|bolder|subtler|"
    r"more\s+daylight|brighter\s+lighting|lighter\s+feeling|airier|"
    r"cozy|elegant|modern|premium|sleek|sophisticated|spacious|"
    r"minimal(ist)?|maximalist|luxurious|hotel(-like)?|push\s*(it|further|more)?|"
    r"deepen|increase|reduce|intensif|tone\s*(it|down|up)|"
    r"stronger|richer|quieter|calmer|even\s*more|a\s*bit\s*more|"
    # French — intensity/degree adverbs and their imperative forms
    r"plus\b|moins\b|davantage|encore\s+plus|beaucoup\s+plus|un\s+peu\s+plus|"
    r"fais.?le\s+plus|rends.?le\s+(plus|plus\s+\w+)|pousse\s*(encore|plus|davantage)?|"
    r"intensifie|renforce|att[eé]nue|approfondi|enrichi)\b",
    re.IGNORECASE,
)

# Correction Pass 2026-08-13 — lexique COULEUR / FINITION, taxonomie PARTAGÉE
# (source UNIQUE, même convention que _FUNCTIONAL_ROOM plus bas). Trois consommateurs,
# un seul vocabulaire — sinon les trois divergent au premier ajout de teinte :
#   • _LOCAL_EDIT ci-dessous  — « Make the walls forest green. » est une ÉDITION
#     exécutable, pas une conversation (A3) ;
#   • refine.advisor          — « forest green » est une COULEUR, pas une forêt : le
#     terme du set absurde suivi d'une couleur est un QUALIFICATIF, jamais un objet (A1) ;
#   • refine.parser           — « change the walls to ivory white » est une FINITION,
#     pas une opération structurelle (A4).
# Alternation NUE (ni \b ni groupe capturant) pour rester interpolable.
# Volontairement bornée aux COULEURS de base (+ formes FR) : y verser des MATÉRIAUX
# ferait basculer « replace the partition with a glass one » du côté finition alors que
# c'est bien du gros œuvre (assertion _refine_canonicalize_validation.py:39).
COLOUR_TERM = (
    r"white|off-white|black|grey|gray|beige|cream|ivory|taupe|charcoal|anthracite|"
    r"green|blue|red|yellow|orange|pink|purple|violet|brown|"
    r"navy|teal|turquoise|olive|sage|burgundy|maroon|terracotta|ochre|mustard|"
    r"gold|golden|silver|bronze|copper|sand|ecru|"
    # FR (le message brut peut arriver non normalisé si MULTILINGUAL_NORMALIZE est OFF)
    r"blanc|blanche|noir|noire|gris|grise|cr[eè]me|ivoire|vert|verte|bleu|bleue|"
    r"rouge|jaune|rose|violette|marron|brun|brune|dor[eé]e?|argent[eé]e?|bordeaux|sable"
)
COLOUR_TERM_RE = re.compile(rf"\b(?:{COLOUR_TERM})\b", re.IGNORECASE)

_LOCAL_EDIT = re.compile(
    r"\b(add\s+(a|an|the|some)?|remove\s+(the|a)?|change\s+(the|a)?|replace\s+(the|a)?|"
    r"swap\s+(the|a)?|move\s+(the|a)?|put\s+(a|an|the)?|take\s+(out|away)|"
    r"get\s+rid\s+of|use\s+(a|an|different)|try\s+(a|an|the)|"
    # PR-A — spatial-manipulation verbs + brighten/darken (interrogative or imperative).
    # "turn" is scoped to spatial forms so "turn X into a bedroom" (design conversion) is untouched.
    r"reverse\s+(the|a|it)?|rotate\s+(the|a|it)?|flip\s+(the|a|it)?|"
    r"turn\s+(the|a|it)\s+(around|to\s*face|toward|towards)|"
    r"face\s+(the|it|toward|towards)|brighten(\s+(the|a|it|up))?|darken(\s+(the|a|it))?|"
    r"different\s+(colour|color|material|fabric|finish|texture)|"
    # Correction Pass 2026-08-13 (A3) — famille COULEUR / FINITION. Sans elle,
    # « Paint the walls ivory white. » (5 mots) retombait sur le repli par comptage de
    # mots (→ CONVERSATION/GENERAL) et « Peins les murs en blanc ivoire. » sur MIXED :
    # dans les deux cas should_generate=False (main.py:2643/2653), donc une commande
    # d'édition parfaitement exécutable ne produisait AUCUNE image.
    # Vocabulaire repris de edit_intent.py:59-69 (_LOCAL_EDIT_SIGNALS contient déjà
    # paint|colour|color, validé côté prompt image) — on ne crée pas de lexique concurrent.
    # Déterminant EXIGÉ après le verbe : « I like the paint » (nom) ne matche pas.
    r"(?:re)?paint(?:s|ed|ing)?\s+(the|a|an|it|this|that|my|our|over)|"
    # « make <cible> <couleur> » : c'est le nom de COULEUR qui fait le signal d'édition,
    # pas le verbe (« make it warmer » reste du ressort de _REFINE). `keep`/`leave` sont
    # volontairement EXCLUS : « keep the walls white » est une CONTRAINTE de préservation
    # (constraint_ack), pas un ordre de générer — l'ouvrir ici dépasserait le correctif.
    rf"make\s+(the|a|an|it|this|that|my|our)\s+[\w\s'-]{{0,24}}?(?:{COLOUR_TERM})|"
    # French — local edit verbs and show-me generation triggers
    r"ajoute|ajouter|enl[eè]ve|enlever|retire|retirer|remplace|remplacer|"
    # FR peinture : IMPÉRATIF uniquement. L'infinitif « peindre » est volontairement
    # EXCLU — il n'apparaît presque que dans une demande d'avis (« est-ce que je devrais
    # peindre… »), déjà protégée par _DESIGN_OPINION_PATTERNS, autant ne pas l'armer.
    r"(?:re)?peins\b|repeindre\b|"
    # « mets/mettre + le|la|les|l' » : seul « mets un|une » était couvert, donc
    # « Mets les murs en blanc ivoire. » n'était pas reconnu comme une édition.
    r"d[eé]place|d[eé]placer|pose\s+(un|une)|mets\s+(un|une|le|la|les|l')|"
    r"mettre\s+(un|une|le|la|les|l')|"
    r"montre-moi\s+(avec|sans|un|une|le|la|les)|essaie\s+(un|une|avec|le|la)|"
    r"utilise\s+(un|une)|diff[eé]rent(e)?\s+(canap[eé]|tapis|tissu|mati[eè]re|finition|texture))\b",
    re.IGNORECASE,
)

# Wave 4.11c — object-scoped size requests bypass ambiguity detection.
# "Make the sofa bigger" carries an explicit target (sofa) so it's NOT
# unscoped — the ambiguity detector correctly stays silent. But without
# this signal it falls through to CONVERSATION/general because "bigger"
# was deliberately excluded from _REFINE (reserved for the unscoped form).
# The pattern requires : a size verb OR "make/keep X (bigger|smaller|...)"
# applied to a definite/possessive object phrase. No bare "bigger" matches.
_SCOPED_SIZE = re.compile(
    r"\b("
    # "make / leave / keep the X bigger/smaller/wider/..."
    r"(make|leave|keep|render|let'?s?\s+make)\s+(the|a|an|that|this|my|our)\s+\w+(\s+\w+){0,2}"
    r"\s+(bigger|smaller|larger|wider|taller|shorter|narrower|deeper|"
    r"higher|lower|longer|broader)"
    r"|"
    # "enlarge / shrink / widen / raise the X"
    r"(enlarge|shrink|widen|narrow|raise|lower(?!\s+the\s+temperature)|deepen|"
    r"extend|shorten|elongate)\s+(the|a|an|that|this|my|our)\s+\w+"
    r")\b",
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
# Wave 4.9.4 (PR-1) — compound confirmations ("ok go ahead", "yes do it") and the
# "anyway"/"now" suffix ("do it anyway", "go ahead anyway") were NOT recognized:
# the old whole-string anchor only matched ONE token. A go-ahead is now an optional
# affirmation prefix + a go-ahead core (either alone), with an optional trailing
# anyway/now/please. A negation/deferral veto (below) keeps "do not go ahead",
# "yes maybe later", "ok but don't do it", "ok explain first" OUT.
_CONF_AFF = (
    r"yes|yeah|yep|yup|ya|ok|okay|k|sure|alright|all\s*right|right|perfect|"
    r"oui|ouais|d'accord|parfait"
)
_CONF_CORE = (
    r"continue|go\s+ahead|go\s+on|do\s+it|do\s+that|just\s+do\s+it|go\s+for\s+it|"
    r"make\s+it|proceed|generate|render|show(?:\s+me)?(?:\s+(?:it|that|the\s+result))?|"
    r"try\s+it|please\s+do|sounds?\s+good|that\s+works|perfect\s+go|"
    r"let'?s?\s+(?:do\s+it|go|see|try|continue)|"
    r"vas-y|allons-y|on\s+y\s+va|continue[zr]?|g[eé]n[eè]re|affiche(?:-le|-moi)?|"
    r"fais(?:-le)?|c'est\s+bon"
)
_CONFIRMATION = re.compile(
    rf"^\s*(?:please\s+)?"
    rf"(?:(?:{_CONF_AFF})[\s,]*(?:{_CONF_CORE})?|(?:{_CONF_CORE}))"
    rf"(?:\s+(?:anyway|now|please))?[\s!.]*$",
    re.IGNORECASE,
)
# Negation / deferral veto — a message carrying any of these is NEVER a bare
# go-ahead, even if it also contains a confirmation word ("ok but don't do it").
_CONFIRMATION_VETO = re.compile(
    r"\b(?:don'?t|do\s+not|doesn'?t|won'?t|can'?t|cannot|not|never|"
    r"maybe|later|wait|first|explain|but|however|instead|"
    r"no|non|pas|jamais|attends?|d'abord|plut[oô]t)\b",
    re.IGNORECASE,
)

# Concrete "convert/turn this space into a <room>" — intent_classifier's
# _STRUCTURAL does not catch functional reassignment ("turn the rear room into
# a bedroom"), the flagship pending case.
# Wave 4.9.5 — taxonomie PARTAGÉE des pièces/zones fonctionnelles (source UNIQUE).
# Extraite verbatim de l'ancienne alternation de _DESIGN_CONVERSION (+ sleeping/reading
# nook), réutilisée par _DESIGN_CONVERSION, par _WISH (restreint) et importée par
# refine.advisor pour la calibration L1 — pas de liste concurrente.
_FUNCTIONAL_ROOM = (
    r"bed\s*room|bedroom|office|studio|kitchen(?:ette)?|lounge|nursery|gym|library|"
    r"closet|dressing(?:\s+(?:room|area))?|dining(?:\s+room|\s+area)?|guest\s+room|play\s*room|"
    r"workspace|bathroom|en-?suite|shower\s+room|powder\s+room|laundry(?:\s+room)?|pantry|"
    r"home\s+office|home\s+bar|wet\s+bar|walk-in|home\s+cinema|home\s+thea(?:tre|ter)|"
    r"sleeping\s+(?:area|nook|zone|space)|sleep\s+area|reading\s+nook"
)
_FUNCTIONAL_ROOM_RE = re.compile(rf"\b(?:{_FUNCTIONAL_ROOM})\b", re.IGNORECASE)

_DESIGN_CONVERSION = re.compile(
    r"\b(turn|convert|transform|make|change|repurpose|use|redesign)\s+"
    r"(the\s+|this\s+|it\s+|that\s+)?\w+(\s+\w+){0,6}?\s+(into|to|as)\s+"
    rf"(an?\s+|the\s+)?(open\s+)?(?:{_FUNCTIONAL_ROOM})",
    re.IGNORECASE,
)


def is_confirmation(message: str) -> bool:
    """True if the whole message is a bare go-ahead confirmation (Task 2).

    Wave 4.9.4 (PR-1): recognizes compound forms ("ok go ahead", "yes do it") and
    the "anyway"/"now" suffix ("do it anyway"), while a negation/deferral veto keeps
    "do not go ahead", "yes maybe later", "ok but don't do it", "ok explain first" out.
    """
    s = (message or "").strip()
    if not s or _CONFIRMATION_VETO.search(s):
        return False
    return bool(_CONFIRMATION.match(s))


# Wave 4.9.4 (PR-1) + 4.9.5 — "wish"-phrased design requests ("I would like a bedroom
# in the rear space", "I want a kitchen on the right", "I'd like a dressing area in that
# corner"). No imperative verb → the edit/convert patterns above miss them, yet they ARE
# concrete pending requests. RESTREINT (4.9.5) à la taxonomie partagée _FUNCTIONAL_ROOM :
# un désir doit porter sur une PIÈCE/ZONE fonctionnelle, sinon "I want a refund /
# subscription / explanation" créerait un faux pending design.
_WISH = re.compile(
    r"\b(?:i\s+(?:would\s+like|want|wish\s+for|need|would\s+love)|i'?d\s+like|"
    r"je\s+(?:voudrais|veux|aimerais|souhaite))\s+"
    r"(?:a|an|the|some|another|un|une|des)\s+"
    rf"(?:[\w-]+\s+){{0,3}}(?:{_FUNCTIONAL_ROOM})\b",
    re.IGNORECASE,
)


def _has_design_request(text: str) -> bool:
    """A prior user turn carrying a concrete design / edit / refine / redirect /
    functional-conversion / wish request (reuses existing compiled patterns)."""
    if not text:
        return False
    return bool(
        _DESIGN_CONVERSION.search(text) or _STRUCTURAL.search(text)
        or _REDIRECT.search(text) or _LOCAL_EDIT.search(text)
        or _REFINE.search(text) or _WISH.search(text)
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
        if _WISH.search(text):                    # PR-1 — wish-phrased pending request
            return SubIntent.LOCAL_EDIT
        if scanned >= 3:  # only the recent window; avoid stale matches
            break
    return None


# ── Wave 4.11a — Product Help / Support / Design Discussion pre-filters ─────
#
# These run BEFORE the existing design-routing logic in classify_intent().
# Patterns are deliberately conservative — when there is ambiguity between
# "how do I X" (design verb) and "how do I X" (product feature), the
# anti-pattern guard pushes the decision back to the standard classifier
# so legitimate design intents still reach generation.
#
# Each pattern set carries an `_ANTI` guard whose match suppresses the
# pre-filter route (design verbs and atmosphere DNA keywords that always
# belong to the generation path).

_PRODUCT_HELP_PATTERNS = re.compile(
    r"\b("
    # "how do I X" / "how can I X" / "how do you X"
    r"how\s+(do|can|would|should)\s+i\s+(continue|share|save|export|"
    r"delete|rename|restore|find|see|compare|undo|revert|switch)|"
    r"how\s+do(es)?\s+(branching|preserve|atmosphere|the\s+reveal|"
    r"voice|the\s+app|session\s+restore)|"
    # "what is/does X" + product feature
    r"what\s+(is|does|do)\s+(preserve\s+mode|the\s+atmosphere\s+system|"
    r"branching|the\s+reveal|continue\s+this\s+vision|the\s+vision)|"
    # "explain X" / "tell me about X"
    r"(explain|tell\s+me\s+about|what\s+about)\s+(preserve|atmosphere|"
    r"branching|reveal|voice|session)|"
    # Direct product nouns / verbs
    r"\bcontinue\s+this\s+vision|preserve\s+mode|how\s+(does\s+)?branching|"
    r"reveal\s+screen|share\s+(a|the|my|this)\s+(design|vision|image)|"
    r"save\s+(a|the|my|this)\s+(image|vision|design)|"
    r"delete\s+(this\s+|a\s+|my\s+)?(session|project|design)|"
    r"rename\s+(this\s+|a\s+|my\s+)?(project|session)"
    r")\b",
    re.IGNORECASE,
)

# Khmer PRODUCT_HELP patterns — separate regex without \b anchors
# (Python's \b only recognises ASCII word chars, so it never matches at
# the boundary of a Khmer-script run).
# Wave 4.11c — broadened to cover the reveal-compare verb ប្រៀបធៀប
# and bare KM interrogatives that don't open with "តើ ខ្ញុំ".
_PRODUCT_HELP_PATTERNS_KM = re.compile(
    r"តើ\s*ខ្ញុំ.*(បន្ត|ចែករំលែក|លុប|ប្តូរ\s*ឈ្មោះ|រក្សា|ប្រៀបធៀប)"
    r"|តើ.*ដំណើរ\s*ការ"
    r"|អ្វី\s*ទៅ\s*ជា\s*(បរិយាកាស|preserve)"
    r"|ប្រៀបធៀប.*(មុន|បន្ទាប់|ក្រោយ)"
    r"|តើ\s*អាច\s*(បន្ត|ចែករំលែក|ប្រៀបធៀប|លុប|ប្តូរ)",
)

# Anti-patterns : if these design verbs/nouns are present anywhere in the
# message, the PRODUCT_HELP route is suppressed. Catches "how do I make
# it warmer" — that's a generation request, not a product question.
_PRODUCT_HELP_ANTI = re.compile(
    r"\b("
    r"warmer|cooler|darker|lighter|brighter|bigger|smaller|softer|"
    r"more\s+(luxury|wood|stone|marble|brass|texture|plants|decor)|"
    r"add\s+(a|the|some)|remove\s+(a|the)|change\s+(the\s+)?(sofa|wall|"
    r"window|color|colour|material)|open\s+(the\s+)?(wall|partition)|"
    r"japandi|warm\s*modern|soft\s*luxury|nordic|tropical|desert|nature"
    r")\b",
    re.IGNORECASE,
)

_SUPPORT_PATTERNS = re.compile(
    r"\b("
    r"(generation|render|image|photo|app)\s+(failed|fail|"
    r"didn'?t\s+(work|load|generate))|"
    r"failed\s+to\s+(generate|load|render|open)|"
    r"(not|isn'?t)\s+(loading|working|responding|generating)|"
    r"can'?t\s+(see|open|find|load|generate|render)\s+(the\s+|my\s+|a\s+)?(image|"
    r"vision|design|render|photo)|"
    r"(crash|crashed|frozen|froze|hang|hangs|stuck)|"
    r"report\s+(a\s+)?(bug|issue|problem)|found\s+(a\s+)?bug|"
    r"something\s+is\s+(wrong|broken|off)|"
    r"contact\s+(support|the\s+team|customer\s+service)|"
    r"send\s+feedback|leave\s+feedback|give\s+feedback"
    r")\b",
    re.IGNORECASE,
)

# Khmer SUPPORT patterns — separate regex (no \b for Khmer scripts).
# Wave 4.11c — broadened to cover "image / Generate / Share not working"
# in both pure-KM and mixed EN+KM forms. The មិន (not) particle followed
# by a verb-of-state is the strongest KM signal for "broken / missing".
_SUPPORT_PATTERNS_KM = re.compile(
    r"បរាជ័យ|កំហុស|បញ្ហា|គាំទ្រ|កម្មវិធី.*គាំង"
    r"|មិន\s*(បង្ហាញ|ដំណើរការ|ផ្ទុក|ដំណើរ|ដើរ|ឃើញ)"
    r"|(រូបភាព|រូប|បង្ហាញ|ផ្ទុក|ការបង្កើត).*(មិន|បរាជ័យ)"
    # Mixed EN+KM : English noun/verb + KM មិនដំណើរការ etc.
    r"|(generate|render|share|continue|upload|chat|app|image|photo|"
    r"design|vision)\s*មិន\s*(ដំណើរការ|បង្ហាញ|ផ្ទុក|ដំណើរ)",
)

_DESIGN_DISCUSSION_PATTERNS = re.compile(
    r"\b("
    r"what\s+do\s+you\s+think|what'?s?\s+your\s+(take|opinion|view)|"
    r"your\s+opinion|how\s+do\s+you\s+see\s+(this|it|the\s+room)|"
    r"should\s+i\s+(keep|change|remove|add|consider|go)|"
    # "would X work" / "would X read" / "would X fit" / "would X look better"
    # — broadened to catch "Would darker floors work?", "Would a stone wall fit?",
    # not just the narrow "would it/that/this" pronouns.
    r"would\s+(?:\w+\s+){0,5}(work|look\s+better|be\s+better|fit|read)|"
    r"is\s+it\s+better\s+to|is\s+this\s+(too\s+much|too\s+little|right)|"
    # Wave 4.11c — "Is this/it/the atmosphere too dark/bright/luxurious/...?".
    # Architectural opinion-seeking, not generation. Restricted to "is/are this/
    # it/that/the X too ADJ" so a constraint statement ("it's too dark in here
    # at night") doesn't accidentally route here. The (?:\w+\s+)? optional
    # noun slot covers "is this atmosphere too dark", "is the room too bright".
    r"is\s+(this|it|that|the)\s+(?:\w+\s+)?too\s+\w+|"
    r"are\s+(these|those|the)\s+(?:\w+\s+)?too\s+\w+|"
    # Wave 4.11d — "Compare these two designs / atmospheres / options" is
    # architectural analysis, not an edit instruction. Also matches the
    # "can you compare X vs Y" question form.
    r"compare\s+(these|those|the|both)\s+(?:\w+\s+){0,2}"
    r"(designs?|atmospheres?|versions?|visions?|options?|directions?|"
    r"approaches?|renders?|generations?)|"
    r"(can|could|would|will)\s+you\s+compare\b|"
    r"compare\s+(?:the\s+|these\s+|those\s+)?\w+(\s+\w+){0,3}\s+"
    r"(vs\.?|versus|and|against|or)\s+\w+|"
    # Wave 4.11d — "pros and cons", "what are the trade-offs" — architectural
    # weighing without an edit imperative.
    r"(pros\s+and\s+cons|trade[-\s]?offs?|advantages?\s+and\s+disadvantages)|"
    r"would\s+you\s+(recommend|suggest|prefer|advise)|"
    r"do\s+you\s+(think|see|recommend|suggest)"
    r")\b",
    re.IGNORECASE,
)

# Khmer DESIGN_DISCUSSION patterns — separate regex (no \b for Khmer).
_DESIGN_DISCUSSION_PATTERNS_KM = re.compile(
    r"តើ\s*អ្នក\s*គិត|ជ្រើស\s*យក|អ្នក\s*យល់\s*ដូច\s*ម្តេច"
)


# ── Wave 4.11b — Negative-sentiment patterns ─────────────────────────────────
# Catches explicit user dissatisfaction. Routes to DESIGN_DISCUSSION with the
# new NEGATIVE_FEEDBACK sub-intent so generate_chat_response can surface a
# calm, diagnostic response instead of accidentally classifying the message
# as PRAISE (the legacy _PRAISE regex doesn't handle negation and matches
# "like this" inside "I don't like this" — see Wave 4.11a validation report).
#
# Conservative on purpose : only fires on explicit negative phrasings.
# "Too dark" or "too bright" are ambiguous (could be design intent) and
# are NOT included here ; they continue to flow through the existing
# refinement / classifier paths.
_NEGATIVE_FEEDBACK_PATTERNS = re.compile(
    r"\b("
    # "I don't like X" / "I do not like X" / "I dislike X" / "I hate X"
    r"i\s+don'?t\s+(like|love|want|enjoy)|"
    r"i\s+do\s+not\s+(like|love|want|enjoy)|"
    r"i\s+(dislike|hate)\b|"
    r"i\s+can'?t\s+stand|"
    # "not a fan of …" / "not happy with …"
    r"not\s+(a\s+fan|happy|satisfied)\s+(of|with)?|"
    # Wave 4.11c — "I'm not happy / sold / loving / convinced" — explicit
    # subject anchors so we never match "this is not good for the kitchen"
    # (which is a constraint statement, not feedback about the design).
    r"i'?m\s+not\s+(happy|sold|loving|convinced|crazy\s+about)|"
    # "X doesn't work" / "X isn't working" / "X is not right".
    # Wave 4.11e (sanity-check follow-up) — broadened to cover plural
    # subjects ("the colors are not good", "these tones aren't right",
    # "those materials are not good") and an optional 0-3 word noun slot
    # between determiner and aux verb ("the colors in this room are not
    # good"). The previous singular-only form mis-routed plural
    # complaints to conversation/general — drove a real beta-test
    # observation surfaced in the Wave 4.11 sanity check.
    r"(this|it|that|these|those|the\s+\w+)(\s+\w+){0,3}\s+"
    r"(doesn'?t|does\s+not|isn'?t|is\s+not|"
    r"aren'?t|are\s+not|weren'?t|were\s+not|don'?t|do\s+not)\s+"
    r"(work|right|landing|coming\s+together|fit|read\s+well|"
    r"great|good|working|fitting|enough)|"
    # Wave 4.11e (sanity-check follow-up) — bare plural noun complaints
    # ("colors are not good", "materials aren't right") anchored at
    # message start to avoid false positives in long sentences.
    r"^\s*\w+s\s+(aren'?t|are\s+not|weren'?t|were\s+not|"
    r"don'?t|do\s+not)\s+(good|right|working|landing|fit|"
    r"read\s+well|great|enough)|"
    # "feels/reads/looks wrong" / "feels off" / "feels forced"
    r"(feels|reads|looks)\s+(wrong|off|bad|forced|sterile|cold|flat|"
    r"weird|cluttered|empty|over\s*(done|crowded))|"
    # Wave 4.11c — "looks worse" / "this looks worse than before"
    r"(looks|feels|reads)\s+worse|"
    # "this is worse" / "this is worse than the previous"
    r"(this|it|that)\s+is\s+worse|"
    # Wave 4.11c — "worse than the previous / before / earlier" — anchored
    # to the comparative so "worse" alone in a benign sentence is ignored.
    r"worse\s+than\s+(the\s+)?(previous|before|earlier|first|last|old|"
    r"original|prior)|"
    # "preferred the previous / older version"
    r"preferred\s+(the\s+)?(previous|older|earlier|first|last|old)\b|"
    r"liked\s+(the\s+)?(previous|older|earlier|first|last|old)\s+"
    r"(version|one|render|generation)"
    r")\b",
    re.IGNORECASE,
)

# Wave 4.11c — message-initial negative shapes ("Not good.", "Not great.",
# "Not what I wanted."). Anchored to "^\s*not …" so embedded uses inside a
# longer constraint sentence ("the dark wood is not great for this kitchen
# because …") never match — that needs a real subject not a sentence-initial
# elision.
_NEGATIVE_FEEDBACK_INIT = re.compile(
    r"^\s*not\s+(good|great|right|working|landing|loving\s+it|"
    r"what\s+i\s+(wanted|expected|asked))\b",
    re.IGNORECASE,
)

# ── Wave 4.11e — SUMMARIZE_DESIGN_BRIEF patterns ─────────────────────────────
#
# User asks the architect to recap / summarize the current direction. This
# is a validation step, not a request for new discussion or generation.
# The handler in main.py emits a bulleted summary derived from
# refinement_state and asks "Ready to generate?". Generation NEVER fires
# directly from this intent — the user follows up with "yes / generate"
# which Wave 4.11d's detect_generation_demand catches.
#
# Patterns anchored at message start where possible (avoid false positives
# inside longer discussions like "tell me what you understand by the term
# 'Japandi'"). EN + FR + KM coverage ; imperfect English variants
# ("summarize what i wanted", "recap please") included.
_SUMMARIZE_BRIEF_EN = re.compile(
    r"^\s*("
    r"(can\s+you\s+|could\s+you\s+|please\s+)?"
    r"(summari[sz]e|recap|sum\s+up|tldr|tl;dr|re[\-\s]?cap)\b"
    r"(\s+(what|the|my|our|this|that|me|us|design|brief|"
    r"requirements?|direction|plan|conversation|discussion))?"
    r"|"
    # "what do you understand?", "what do you understand by ..."
    r"what\s+do\s+you\s+understand\b"
    r"|"
    # "what is my brief?", "what's my brief?", "what's the brief?"
    # Note: in the contracted form "what's", the apostrophe-s attaches
    # directly to "what" (no space), so we treat it as either
    # "what is" (whitespace between) OR "what's" (no whitespace).
    r"what(\s+is|'s)\s+(the|my|our)\s+brief\b"
    r"|"
    # "what are we trying to achieve?", "what are we doing?"
    r"what\s+are\s+we\s+(trying\s+to\s+(achieve|build|create|design)|doing|aiming\s+for)\b"
    r"|"
    # "give me a recap", "give us a summary"
    r"give\s+(me|us)\s+(a\s+)?(recap|summary|summari[sz]ation)\b"
    r"|"
    # "remind me what I said", "remind me what we agreed"
    r"remind\s+me\s+what\s+(i|we)\s+(said|wanted|asked|agreed)"
    r")",
    re.IGNORECASE,
)

_SUMMARIZE_BRIEF_FR = re.compile(
    r"^\s*("
    r"(peux[-\s]?tu\s+|pouvez[-\s]?vous\s+|s'?il\s+te\s+pla[iî]t\s+|stp\s+)?"
    r"(r[eé]sume[zr]?|r[eé]capitule[zr]?|fais\s+(un|le)\s+r[eé]sum[eé]|"
    r"recap|rappelle[-\s]?moi)\b"
    r"|"
    r"qu'?est[-\s]ce\s+que\s+tu\s+(comprends|as\s+compris)\b"
    r"|"
    r"qu'?est[-\s]ce\s+(qu'?on|que\s+nous|on)\s+(essaie\s+de\s+faire|veut\s+faire|cherche)\b"
    r"|"
    r"quel\s+(est|'s)\s+(mon|le|notre)\s+brief\b"
    r")",
    re.IGNORECASE,
)

# Khmer — no \b for Khmer scripts. Minimal initial coverage ; expand based
# on real KM usage logs.
_SUMMARIZE_BRIEF_KM = re.compile(
    r"សង្ខេប|សារសំខាន់|"
    r"តើ\s*អ្នក\s*យល់\s*(ដឹង|អ្វី)|"
    r"និយាយ\s*សង្ខេប|"
    r"រំលឹក\s*ខ្ញុំ"
)


# Anti-pattern : suppress DESIGN_DISCUSSION when the message OPENS with
# an imperative generation verb. A question form like "Would darker
# floors work?" or "Should I keep the rug?" must STILL route to
# DESIGN_DISCUSSION even though it contains design adjectives — the
# question wrapping is the discriminator. We use `^\s*` to anchor so
# only the message's opening verb counts, not vocabulary mid-sentence.
_DESIGN_DISCUSSION_ANTI = re.compile(
    r"^\s*("
    r"add|remove|change|move|swap|replace|put|take\s+out|edit|"
    r"redo|redesign|render|generate|show\s+me|try\s+a|"
    r"make\s+(it|me|the)|i\s+want\s+to|let'?s?\s+(do|try|change|add|go)"
    r")\b",
    re.IGNORECASE,
)


# ── Wave 4.11d — Generation Intent Dominance ─────────────────────────────────
#
# After Wave 4.11a/b/c the architect became too clarification-happy : users
# answered a clarification but got asked another one instead of seeing the
# next vision. This layer adds two stateless detectors that sit BEFORE
# detect_ambiguity in main.py /chat :
#
#   1. detect_generation_demand    — explicit user demand ("generate",
#                                    "just do it", "why don't you generate")
#                                    → immediate GENERATE, bypass ambiguity.
#   2. is_clarification_answer     — previous assistant turn was a
#                                    clarification AND user gave a short
#                                    direct answer → resolve ambiguity,
#                                    route as GENERATE/REFINE_ATMOSPHERE.
#
# Both layers preserve Wave 4.11a/b/c behaviour : first-time ambiguous
# messages still clarify (Principle 1), genuine architectural questions
# still route to DESIGN_DISCUSSION (Principle 5), negative-feedback still
# routes through NEGATIVE_FEEDBACK (Wave 4.11b/c).

# Anchored : the WHOLE message must be a bare demand. "let me know how to
# generate" or "why don't you generate AND change the sofa" do NOT match —
# the latter carries a separate edit instruction and goes through the
# standard chain. Trailing punctuation / "now" / "please" are absorbed.
_GENERATION_DEMAND = re.compile(
    r"^\s*("
    r"generate(\s+(it|now|please|already|the\s+image|the\s+vision))?|"
    r"render(\s+(it|now|please))?|create\s+(it|now)|"
    r"show\s+me(\s+(it|now|please|the\s+(result|vision|image)))?|"
    r"try\s+it(\s+now)?|let'?s?\s+see(\s+(it|the\s+(result|vision)))?|"
    r"just\s+(do|make|render|generate|show)\s+it|"
    r"make\s+it(\s+(now|please|already))?|"
    r"why\s+(don'?t|aren'?t|won'?t|can'?t)\s+you\s+"
    r"(just\s+)?(generat\w*|render\w*|show\w*|creat\w*|mak\w*|do\s+it)|"
    # Wave 4.11d.1 — also catch the French-influenced "why you don't / why
    # you aren't" word order observed in production (backend.log
    # 2026-05-30 09:07:02). Meta_intent now suppresses STOP_GENERATION
    # on this pattern ; Wave 4.11d completes the fix by routing it
    # to GENERATE. Verb tail \w* catches gerund "generating".
    r"why\s+you\s+(don'?t|aren'?t|won'?t|can'?t|cannot)\s+"
    r"(just\s+)?(generat\w*|render\w*|show\w*|creat\w*|mak\w*|do\s+it)|"
    r"how\s+come\s+you\s+(don'?t|aren'?t|won'?t|cannot)\s+"
    r"(generat\w*|render\w*|show\w*|creat\w*|mak\w*|do\s+it)|"
    # Wave 4.11d.1 — "are you (not) going to generate?"
    r"(are|were|weren'?t|aren'?t)\s+you\s+(not\s+)?(going\s+to\s+)?"
    r"(generat\w*|render\w*|show\w*|creat\w*|mak\w*|produc\w*|build\w*)|"
    r"can\s+you\s+(just\s+)?(generate|render|show\s+me|make\s+it|do\s+it)|"
    r"please\s+(generate|render|show\s+me|just\s+do\s+it)|"
    r"go\s+(for\s+it|ahead(\s+(and\s+)?(generate|render))?)|"
    r"do\s+it(\s+now)?|"
    # Wave 4.11d.1 — French explicit demand : "pourquoi tu ne génères pas",
    # "pourquoi tu génères pas", "génère", "rends-le".
    r"pourquoi\s+(tu\s+)?(ne\s+)?(g[eé]n[eè]res?|rends?|cr[eé]es?|fais)\s*(pas)?|"
    r"g[eé]n[eè]re(-le|-moi|\s+maintenant)?|"
    r"vas-y\s+g[eé]n[eè]re|fais-le\s+maintenant"
    r")\s*[!.?]*\s*$",
    re.IGNORECASE,
)

# Markers detected in the LAST assistant message indicating it was a
# clarification dialog. These mirror the templates in
# ambiguity_detector._RULES — if the clarification copy changes
# substantially, this list needs a paired update. The patterns are
# deliberately phrase-fragments, not full strings, so minor wording
# tweaks don't break detection.
_ASSISTANT_CLARIFICATION_MARKERS = re.compile(
    r"(are\s+you\s+thinking|"
    r"in\s+which\s+(direction|sense|layer)|"
    r"of\s+which\s+layer|of\s+which\s*[—\-]|"
    r"tell\s+me\s+which|pick\s+the\s+(angle|layer)|"
    r"what\s+kind\s+of\s+(impact|change)|"
    r"name\s+the\s+layer|sketch\s+the\s+route|"
    r"i'?ll\s+calibrate\s+the\s+next\s+vision|"
    r"open\s+in\s+which\s+sense|"
    # KM clarification markers
    r"ប្រាប់\s*ខ្ញុំ|"
    r"ជ្រើស\s*យក"
    r")",
    re.IGNORECASE,
)

# Discriminators for "is this message a direct clarification answer?".
# A direct answer is short, declarative, on-topic. These reject patterns
# catch the cases where the user redirected the conversation, asked a
# question back, or expressed dissatisfaction — none of which should be
# auto-promoted to GENERATE.
_NOT_AN_ANSWER = re.compile(
    r"^\s*("
    r"actually|wait|hmm+|instead|nope|no\s+no|"
    r"compare|discuss|talk|explain|tell\s+me|why|"
    r"what\s+(about|do|if|are|is)|how\s+(about|do|can)|"
    r"can\s+(we|you|i)|could\s+(we|you|i)|would\s+(we|you|i)|"
    r"let'?s?\s+(do|change|talk|discuss|try\s+something)|"
    r"i\s+(don'?t|do\s+not|am\s+not|'m\s+not)\s+(know|understand|sure|loving)|"
    r"none\s+of|neither"
    r")\b",
    re.IGNORECASE,
)


def detect_generation_demand(message: str) -> bool:
    """Wave 4.11d — explicit generation override.

    Returns True when the user message is a bare demand for the next
    vision — "generate", "why don't you generate", "just do it",
    "show me", "let's see", "make it" (alone), etc. Callers in
    main.py should bypass detect_ambiguity and route directly to
    GENERATE when this returns True.
    """
    if not message:
        return False
    return bool(_GENERATION_DEMAND.match(message.strip()))


def _last_assistant_text(history) -> str:
    """Return the content of the most recent assistant turn in history,
    or '' if the last turn was the user / history is empty."""
    if not history:
        return ""
    for msg in reversed(history):
        if not isinstance(msg, dict):
            continue
        role = str(msg.get("role", "")).lower()
        if role in ("ai", "assistant"):
            return str(msg.get("content", "") or "")
        if role == "user":
            # User turn encountered before any assistant turn — return ''
            return ""
    return ""


def last_assistant_was_clarification(history) -> bool:
    """Wave 4.11d — True if the most recent assistant turn looks like a
    clarification dialog emitted by detect_ambiguity. Detected via the
    canonical clarification markers ; copy changes in
    ambiguity_detector require a paired update here."""
    text = _last_assistant_text(history)
    if not text:
        return False
    return bool(_ASSISTANT_CLARIFICATION_MARKERS.search(text))


def is_clarification_answer(message: str, history) -> bool:
    """Wave 4.11d — True if `message` is a short direct answer to a
    clarification the assistant just emitted. Rejects redirects,
    questions, expressions of confusion or dissatisfaction.

    Caller (main.py) should bypass detect_ambiguity and route as
    GENERATE / REFINE_ATMOSPHERE when this returns True. The
    clarification dialog has been "spent" — the user gets the next
    vision instead of another clarification round.
    """
    if not last_assistant_was_clarification(history):
        return False
    msg = (message or "").strip()
    if not msg:
        return False
    # Reject long replies — direct answers are tight by nature.
    if len(msg.split()) > 10:
        return False
    # Reject question shapes — user is asking, not answering.
    if "?" in msg:
        return False
    # Reject redirects / confusion / discussion verbs.
    if _NOT_AN_ANSWER.match(msg):
        return False
    # Reject explicit dissatisfaction — that's negative feedback, not
    # a clarification answer.
    if _NEGATIVE_FEEDBACK_PATTERNS.search(msg) or _NEGATIVE_FEEDBACK_INIT.match(msg):
        return False
    return True


def _route_wave_411a(
    message: str, iteration: int
) -> "IntentClassification | None":
    """
    Wave 4.11a pre-filter — return a PRODUCT_HELP / SUPPORT /
    DESIGN_DISCUSSION classification if patterns clearly indicate one
    of these intents. Returns None to let the standard classifier run.

    Conservative by design : when a generation verb is present, the
    pre-filter steps aside. The fallback chain in main.py also runs the
    product_knowledge.detect_product_help() for true product topics — so
    if this returns PRODUCT_HELP but no topic resolves, main.py drops
    back to the standard CONVERSATION/GENERATE path.

    V1 (iteration == 1) is NEVER pre-filtered — the first render is law.
    """
    if iteration <= 1 or not message:
        return None

    # Wave 4.11e — SUMMARIZE_DESIGN_BRIEF runs FIRST (before SUPPORT) because
    # its triggers are tightly anchored and the user's intent is opt-in :
    # they explicitly asked for a recap. Routing this to SUMMARIZE prevents
    # mis-classifying messages like "recap please" as conversation/general.
    # Top-level intent stays DESIGN_DISCUSSION (no generation fires from
    # here) ; main.py's dedicated handler emits the bulleted summary text.
    if (_SUMMARIZE_BRIEF_EN.search(message)
            or _SUMMARIZE_BRIEF_FR.search(message)
            or _SUMMARIZE_BRIEF_KM.search(message)):
        return IntentClassification(
            intent=ConversationIntent.DESIGN_DISCUSSION,
            sub_intent=SubIntent.SUMMARIZE_DESIGN_BRIEF,
            confidence=0.90,
            reasoning="Wave 4.11e — summarize design brief pattern matched",
        )

    # SUPPORT — strongest signal, runs first. Errors / bugs always win.
    # Both EN and KM regex are tested ; KM uses a separate compiled
    # pattern because Python's \b word boundary does not register at
    # the edge of a Khmer-script run.
    if _SUPPORT_PATTERNS.search(message) or _SUPPORT_PATTERNS_KM.search(message):
        return IntentClassification(
            intent=ConversationIntent.SUPPORT,
            sub_intent=SubIntent.SUPPORT,
            confidence=0.90,
            reasoning="Wave 4.11a — support pattern matched",
        )

    # Wave 4.11b — NEGATIVE_FEEDBACK runs BEFORE PRODUCT_HELP /
    # DESIGN_DISCUSSION so explicit dissatisfaction never gets classified
    # as PRAISE by the legacy classifier downstream. Top-level intent is
    # DESIGN_DISCUSSION (no generation) ; the dedicated NEGATIVE_FEEDBACK
    # sub-intent drives the calm response pool in architect_response.
    if (_NEGATIVE_FEEDBACK_PATTERNS.search(message)
            or _NEGATIVE_FEEDBACK_INIT.match(message)):
        return IntentClassification(
            intent=ConversationIntent.DESIGN_DISCUSSION,
            sub_intent=SubIntent.NEGATIVE_FEEDBACK,
            confidence=0.85,
            reasoning="Wave 4.11b/c — negative sentiment detected",
        )

    # PRODUCT_HELP — second, guarded by design-verb anti-patterns.
    if _PRODUCT_HELP_PATTERNS.search(message) or _PRODUCT_HELP_PATTERNS_KM.search(message):
        if not _PRODUCT_HELP_ANTI.search(message):
            return IntentClassification(
                intent=ConversationIntent.PRODUCT_HELP,
                sub_intent=SubIntent.PRODUCT_HELP,
                confidence=0.85,
                reasoning="Wave 4.11a — product help pattern matched",
            )

    # DESIGN_DISCUSSION — third, guarded by generation-verb anti-patterns.
    if _DESIGN_DISCUSSION_PATTERNS.search(message) or _DESIGN_DISCUSSION_PATTERNS_KM.search(message):
        if not _DESIGN_DISCUSSION_ANTI.search(message):
            return IntentClassification(
                intent=ConversationIntent.DESIGN_DISCUSSION,
                sub_intent=SubIntent.DESIGN_DISCUSSION,
                confidence=0.80,
                reasoning="Wave 4.11a — design discussion pattern matched",
            )

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

# ── DESIGN_OPINION_QUESTION detector (PR-A : moved here from conversation_router
# to avoid a circular import — classify_intent now consumes it directly).
# The user ASKS for a design opinion rather than COMMANDING a change. High
# precision (validated 10/10 opinions, 0 false-positives on commands): explicit
# opinion frames + choice questions ("A or B?") + a first-person tentative
# proposal ENDING in "?". Plain/polite commands ("make it warmer",
# "can you make it warmer?") do NOT match → routed as edit commands.
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
    # choice question: "round or rectangular?" AND "… face the window or the TV?"
    # (an optional article between "or" and the final noun — else the trailing
    # noun evaded the pattern and a "face"/edit verb wrongly routed it to GENERATE).
    r"\b\w+\s+or\s+(?:the|a|an|my|our|your)?\s*\w+\s*\?",
    # PR-A — advice/recommendation requests ("tell me where…", "where I should…",
    # "where should/to put…"). These ASK for a placement opinion, not a command.
    r"\btell\s+me\s+(where|which|whether|how|if)\b",
    r"\bwhere\s+(should|shall|do|can|could|would|to)\b",
    r"\bwhere\s+(i|we|you)\s+should\b",
    r"\bdois-je\b",
    r"\bdevrais-je\b",
    # Correction Pass 2026-08-13 (A3) — forme FR non inversée. L'ouverture de
    # _LOCAL_EDIT à la peinture (peins/repeins/repeindre) rend cette précédence
    # EXPLICITE : « Est-ce que je devrais repeindre les murs ? » est un avis demandé,
    # pas un ordre. detect_design_opinion_question() est évalué AVANT la branche
    # _has_edit (voir classify_intent, bloc `if has_question`) — ne pas inverser.
    r"\best-ce\s+que\s+je\s+(devrais|dois)\b",
    r"\best-ce\s+qu'?on\s+(devrait|doit)\b",
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

    # Wave 4.11a pre-filter — PRODUCT_HELP / SUPPORT / DESIGN_DISCUSSION.
    # Conservative by design : when a generation verb is present, the
    # pre-filter returns None and the standard classifier runs.
    _early = _route_wave_411a(msg, iteration)
    if _early is not None:
        return _early

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

    # Conversion fonctionnelle de zone (« convert the right side into an open kitchen ») =
    # commande d'EXÉCUTION, pas une suggestion créative → génère. Sauf si c'est formulé en
    # question d'opinion (« should I convert… ? ») → l'architecte conseille.
    if bool(_DESIGN_CONVERSION.search(msg)) and not detect_design_opinion_question(msg):
        return IntentClassification(
            intent=ConversationIntent.GENERATE,
            sub_intent=SubIntent.STRUCTURAL_CHANGE,
            confidence=0.88,
            reasoning="Functional zone conversion → generate",
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

    # TODO (future routing evolution) — replace this verb-based edit detection
    # with GOAL-STATE intent detection : "does the user expect a NEW IMAGE?"
    # rather than "does the message contain a modification verb?". The current
    # deterministic gates depend on an edit-verb lexicon (_LOCAL_EDIT/_REFINE/…)
    # that needs occasional additions ("reverse", "rotate", "face" were missing);
    # a goal-state classifier (or a small LLM router) would remove that lexicon
    # dependence. Deferred on purpose — deterministic gates keep zero latency/cost
    # and are fully testable ; revisit when the lexicon maintenance cost grows.
    # ── PR-A (routing) — intention de RÉSULTAT avant forme grammaticale ────────
    # Une question grammaticale peut être fonctionnellement un ORDRE : « can you
    # move/rotate/reverse the X? » attend une NOUVELLE IMAGE, pas un avis. Le « ? »
    # (has_question) ne domine plus une intention d'édition.
    #   • vraie demande d'opinion (should i / where should / do you think / A or B /
    #     recommend / musing 1re pers.) → l'architecte CONSEILLE ;
    #   • sinon, signal d'édition présent → GÉNÉRATION (commande polie exécutée) ;
    #   • sinon (question pure, sans édition) → conseil.
    if has_question:
        _has_edit = has_refine or has_local or bool(_SCOPED_SIZE.search(msg))
        if detect_design_opinion_question(msg):
            return IntentClassification(
                intent=ConversationIntent.CONVERSATION,
                sub_intent=SubIntent.QUESTION,
                confidence=0.80,
                reasoning="Design opinion question → advice",
            )
        if _has_edit:
            sub = SubIntent.LOCAL_EDIT if has_local and not has_refine else SubIntent.REFINE_ATMOSPHERE
            return IntentClassification(
                intent=ConversationIntent.GENERATE,
                sub_intent=sub,
                confidence=0.90,
                reasoning="Polite edit command in interrogative form → generate",
            )
        return IntentClassification(
            intent=ConversationIntent.CONVERSATION,
            sub_intent=SubIntent.QUESTION,
            confidence=0.75,
            reasoning="Design question without generation trigger",
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

    # Wave 4.11c — scoped size request : "make the sofa bigger", "enlarge
    # the island". The target object is explicit so the ambiguity detector
    # correctly stayed silent ; we promote it to GENERATE/LOCAL_EDIT here
    # rather than letting it fall through to short-unclassified CONVERSATION.
    if _SCOPED_SIZE.search(msg):
        return IntentClassification(
            intent=ConversationIntent.GENERATE,
            sub_intent=SubIntent.LOCAL_EDIT,
            confidence=0.80,
            reasoning="Object-scoped size refinement",
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
