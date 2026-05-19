"""
response_quality.py — Wave 3.3 Response Quality Engine.

Adds natural, length-calibrated, emotionally-aware responses for the
ARCHITECT_LIGHT tone path (conversational design exchanges).

Does NOT touch:
  - generate_architect_response (post-generation messages)
  - generate_chat_response (ARCHITECT_ACTIVE path)
  - DNA architecture
  - prompt composition

Three core functions:
  detect_emotional_context()          — reads HOW the user is speaking
  select_response_length()            — calibrates SHORT / MEDIUM / EXTENDED
  generate_architect_light_response() — natural, premium conversational response
  get_micro_insight()                 — brief architectural insight by room type

Design principles:
  - 1–2 sentences maximum in all but EXTENDED
  - No consultant language, no jargon, no over-explanation
  - Calm, warm, architecturally grounded
  - Bilingual: English and French
  - Deterministic via MD5 seed
"""

from __future__ import annotations
import hashlib
import re
from enum import Enum


class EmotionalContext(str, Enum):
    NEUTRAL       = "neutral"
    CURIOSITY     = "curiosity"        # design questions: "what do you think about X?"
    EXPLORATION   = "exploration"      # tentative suggestions: "maybe something warmer?"
    HESITATION    = "hesitation"       # uncertainty: "not sure which way to go"
    ACKNOWLEDGMENT = "acknowledgment"  # brief reactions: "interesting", "hmm", "ok"
    PRAISE        = "praise"           # positive reactions: "I love this", "perfect"


class ResponseLength(str, Enum):
    SHORT    = "short"     # 1 sentence
    MEDIUM   = "medium"    # 1–2 sentences
    EXTENDED = "extended"  # 2–3 sentences with an architectural insight


# ── Detection ─────────────────────────────────────────────────────────────────

_ACKNOWLEDGMENT_RE = re.compile(
    r"^\s*(interesting\.?|hmm+\.?|ok\.?|okay\.?|i\s*see\.?|right\.?|noted\.?|cool\.?|"
    r"got\s*it\.?|sure\.?|alright\.?|yep\.?|yeah\.?|yes\.?|ah\.?|"
    r"intéressant\.?|d'accord\.?|compris\.?|bien\.?|oui\.?|je\s*vois\.?|ah\s*oui\.?)\s*$",
    re.IGNORECASE,
)

_PRAISE_RE = re.compile(
    r"\b(love\s*(it|this|that|the)|perfect|amazing|beautiful|stunning|"
    r"looks?\s*(so\s*)?(good|great|amazing|beautiful)|exactly\s*(that|right|what\s+i\s+wanted)?|"
    r"j'?adore|parfait|magnifique|superbe|c'est\s*(bon|bien|parfait|exactement\s*ça))\b",
    re.IGNORECASE,
)

_HESITATION_RE = re.compile(
    r"\b(not\s+(really|quite|sure|convinced)|don'?t\s+(really\s+)?know|uncertain|"
    r"not\s+(100\s*%|entirely)\s+sure|sort\s+of\s+not|"
    r"pas\s+(vraiment|sûr|convaincu|tout\s+à\s+fait)|je\s+ne\s+sais\s+pas\s+vraiment)\b",
    re.IGNORECASE,
)

_EXPLORATION_RE = re.compile(
    r"\b(maybe|perhaps|what\s+(if|about)|how\s+about|could\s+we|thinking\s+(about|of)\s+trying|"
    r"something\s+like|kind\s+of\s+like|leaning\s+(toward|towards)|what\s+if\s+we|"
    r"peut.être|et\s+si\s+(on|nous)|qu'?est.ce\s+qu'?on\s+dirait\s+de|"
    r"quelque\s+chose\s+comme|on\s+pourrait\s+essayer|je\s+pensais\s+à)\b",
    re.IGNORECASE,
)

_CURIOSITY_RE = re.compile(
    r"\b(what\s+do\s+you\s+think|what\s+would\s+you|why\s+does|why\s+is|why\s+do|"
    r"how\s+(does|do|can|would|come)|what\s+(makes|gives|causes|would\s+make|would\s+help)|"
    r"do\s+you\s+think|would\s+it\s+(work|help|look)|would\s+(this|that)\s+(work|help)|"
    r"is\s+it\s+(possible|better|worse)|could\s+it\s+(work|help)|"
    r"qu'?est.ce\s+(tu|vous)\s+(penses?|pensez)|pourquoi\s+(est.ce\s+que|ça|la|le)|"
    r"comment\s+(est.ce\s+que|ça\s+marche|ça\s+fonctionne)|ça\s+marcherait|"
    r"est.ce\s+que\s+(ça|ce|tu|vous))\b",
    re.IGNORECASE,
)


def detect_emotional_context(message: str) -> EmotionalContext:
    """Detect how the user is speaking — not what they want, but the emotional register."""
    msg = message.strip()

    # Anchored check first (brief reactions — very specific)
    if _ACKNOWLEDGMENT_RE.match(msg):
        return EmotionalContext.ACKNOWLEDGMENT

    # Praise — but not if mixed with hesitation ("I love it but not sure")
    if _PRAISE_RE.search(msg) and not _HESITATION_RE.search(msg):
        return EmotionalContext.PRAISE

    # Hesitation (uncertainty about direction)
    if _HESITATION_RE.search(msg):
        return EmotionalContext.HESITATION

    # Exploration (tentative suggestions)
    if _EXPLORATION_RE.search(msg):
        return EmotionalContext.EXPLORATION

    # Curiosity (design questions)
    if _CURIOSITY_RE.search(msg) or msg.rstrip().endswith("?"):
        return EmotionalContext.CURIOSITY

    return EmotionalContext.NEUTRAL


def select_response_length(
    message: str,
    emotional_context: EmotionalContext,
) -> ResponseLength:
    """Calibrate response length to match the conversational weight of the message."""
    msg_len = len(message.strip())

    if emotional_context == EmotionalContext.ACKNOWLEDGMENT:
        return ResponseLength.SHORT

    if emotional_context == EmotionalContext.HESITATION:
        return ResponseLength.SHORT if msg_len < 35 else ResponseLength.MEDIUM

    if emotional_context == EmotionalContext.PRAISE:
        return ResponseLength.SHORT if msg_len < 35 else ResponseLength.MEDIUM

    if emotional_context == EmotionalContext.EXPLORATION:
        return ResponseLength.MEDIUM

    if emotional_context == EmotionalContext.CURIOSITY:
        # Deep analytical questions ("why does...", "how does...", "what makes...")
        # get EXTENDED; simple questions stay MEDIUM
        deep = bool(re.search(
            r"\b(why\s+(does|do|is|are|would)|how\s+(does|do|would|come)|"
            r"what\s+(makes|gives|causes|creates)|qu[']?est.ce\s+qui|pourquoi|comment\s+\S+)\b",
            message, re.IGNORECASE,
        ))
        return ResponseLength.EXTENDED if (deep and msg_len > 20) else ResponseLength.MEDIUM

    # NEUTRAL
    return ResponseLength.SHORT if msg_len < 22 else ResponseLength.MEDIUM


# ── Response pools ─────────────────────────────────────────────────────────────
# Guidelines:
#   - No "That could significantly enhance the atmosphere" — too formal
#   - No repeated sentence structures
#   - Simple, natural, architect-voiced
#   - Ends with a question or an open statement, not a full stop lecture

_POOLS: dict[tuple[EmotionalContext, ResponseLength], dict[str, list[str]]] = {

    # ── CURIOSITY ─────────────────────────────────────────────────────────────
    (EmotionalContext.CURIOSITY, ResponseLength.SHORT): {
        "en": [
            "It can work — depends mostly on how the light reads in the space.",
            "That's a good instinct for this kind of room.",
            "It might, yes — the key is the material balance around it.",
            "Worth considering — it usually depends on the scale.",
        ],
        "fr": [
            "Ça peut fonctionner — tout dépend de la lumière dans l'espace.",
            "C'est un bon instinct pour ce type de pièce.",
            "Peut-être, oui — l'essentiel est l'équilibre des matériaux autour.",
            "À considérer — ça dépend généralement de l'échelle.",
        ],
    },
    (EmotionalContext.CURIOSITY, ResponseLength.MEDIUM): {
        "en": [
            "That could work really well here — the key is keeping the overall palette from feeling too heavy.",
            "It's a solid direction. What matters most is how it reads against the light in the space.",
            "Honestly, yes — that kind of choice tends to ground a room without making it feel enclosed.",
            "There's real potential there. The question is whether you want contrast or continuity with the rest of the space.",
        ],
        "fr": [
            "Ça pourrait très bien fonctionner ici — l'essentiel est d'éviter que la palette paraisse trop lourde.",
            "C'est une bonne direction. Ce qui compte le plus, c'est comment ça se comporte face à la lumière.",
            "Franchement, oui — ce type de choix ancre une pièce sans la refermer.",
            "Il y a un vrai potentiel. La question est de savoir si vous voulez du contraste ou de la continuité.",
        ],
    },
    (EmotionalContext.CURIOSITY, ResponseLength.EXTENDED): {
        "en": [
            "That's worth thinking about carefully. Material weight matters a lot here — darker elements lower the visual ceiling, which can feel intimate or heavy depending on how much light the room gets.",
            "It could work beautifully. The instinct is right — the real variable is natural light. Heavier materials need room to breathe, otherwise they make the space feel smaller than it actually is.",
            "There's real potential in that direction. The main thing to watch is visual balance — one strong material choice usually needs a counterweight somewhere else in the room to feel resolved.",
            "Honestly, it depends on what you're optimising for. If the room already reads as quite open, you have latitude. If it's compact, you'll want to keep the palette lighter and let the material do the talking instead.",
        ],
        "fr": [
            "Ça mérite réflexion. Le poids des matériaux compte beaucoup ici — les éléments sombres abaissent le plafond visuel, ce qui peut paraître intime ou lourd selon la lumière naturelle.",
            "Ça pourrait très bien fonctionner. L'instinct est bon — la vraie variable, c'est la lumière naturelle. Les matériaux lourds ont besoin d'espace pour respirer.",
            "Il y a un vrai potentiel dans cette direction. L'essentiel est l'équilibre visuel — un matériau fort a besoin d'un contrepoids ailleurs dans la pièce.",
            "Ça dépend vraiment de ce que vous voulez optimiser. Si la pièce est déjà ouverte, vous avez de la latitude. Si elle est compacte, gardez la palette plus légère.",
        ],
    },

    # ── EXPLORATION ───────────────────────────────────────────────────────────
    (EmotionalContext.EXPLORATION, ResponseLength.SHORT): {
        "en": [
            "That's worth trying.",
            "Good direction — we could start there.",
            "We could go that way, yes.",
            "That instinct is right.",
        ],
        "fr": [
            "Ça vaut la peine d'essayer.",
            "Bonne direction — on peut commencer par là.",
            "On pourrait aller dans ce sens, oui.",
            "Cet instinct est juste.",
        ],
    },
    (EmotionalContext.EXPLORATION, ResponseLength.MEDIUM): {
        "en": [
            "We could try that direction — the palette would shift noticeably, which is probably what you're looking for.",
            "That's a good place to start. Usually the first shift reveals whether the overall direction needs more or less of it.",
            "That makes sense as a move. Let's see how far we push it before deciding if it needs more.",
            "It's worth exploring. The lighter version of that idea often reads better in practice than expected.",
        ],
        "fr": [
            "On peut essayer cette direction — la palette changerait sensiblement, ce qui est probablement ce que vous cherchez.",
            "C'est un bon point de départ. En général, le premier changement révèle si la direction a besoin de plus ou de moins.",
            "Ça a du sens comme mouvement. Voyons jusqu'où on pousse avant de décider si ça en veut plus.",
            "Ça vaut la peine d'explorer. La version plus légère de cette idée fonctionne souvent mieux qu'on ne s'y attend.",
        ],
    },

    # ── ACKNOWLEDGMENT ────────────────────────────────────────────────────────
    (EmotionalContext.ACKNOWLEDGMENT, ResponseLength.SHORT): {
        "en": [
            "Yeah, I think that's where things start to shift.",
            "Exactly — we can work with that.",
            "Good. Let's carry that through.",
            "That's a useful read.",
            "Yes — the direction is getting clearer.",
        ],
        "fr": [
            "Oui, je pense que c'est là que les choses commencent à changer.",
            "Exactement — on peut travailler dans ce sens.",
            "Bien. Continuons dans cette direction.",
            "C'est utile à noter.",
            "Oui — la direction se précise.",
        ],
    },

    # ── HESITATION ────────────────────────────────────────────────────────────
    (EmotionalContext.HESITATION, ResponseLength.SHORT): {
        "en": [
            "That's okay — we can take this slowly.",
            "No rush. What's pulling you toward one direction or another?",
            "We can explore a few paths before committing.",
        ],
        "fr": [
            "Pas de problème — on peut prendre le temps qu'il faut.",
            "Pas d'urgence. Qu'est-ce qui vous attire dans une direction plutôt qu'une autre ?",
            "On peut explorer quelques pistes avant de s'engager.",
        ],
    },
    (EmotionalContext.HESITATION, ResponseLength.MEDIUM): {
        "en": [
            "That's completely fine — not knowing yet is often where the best decisions start. What's the feeling you're chasing, even loosely?",
            "We can work with uncertainty. Usually it helps to eliminate what you definitely don't want first — that narrows things down quickly.",
            "There's no wrong starting point. Tell me what the room feels like to you right now, and we can find the gap.",
        ],
        "fr": [
            "C'est tout à fait normal — ne pas encore savoir, c'est souvent là que les meilleures décisions commencent. Quelle est l'atmosphère que vous cherchez, même vaguement ?",
            "On peut travailler avec l'incertitude. En général, il aide d'éliminer ce qu'on ne veut définitivement pas — ça réduit rapidement les options.",
            "Il n'y a pas de mauvais point de départ. Dites-moi ce que la pièce vous évoque maintenant, et on trouvera ce qui manque.",
        ],
    },

    # ── PRAISE ────────────────────────────────────────────────────────────────
    (EmotionalContext.PRAISE, ResponseLength.SHORT): {
        "en": [
            "Glad that's working. What would you change next?",
            "Good — where would you like to take it from here?",
            "That's a strong direction. What still feels off?",
            "Happy to hear it. What's the next move?",
        ],
        "fr": [
            "Ravi que ça fonctionne. Qu'est-ce que vous changeriez ensuite ?",
            "Bien — où voulez-vous aller à partir d'ici ?",
            "C'est une bonne direction. Qu'est-ce qui semble encore décalé ?",
            "Ravi de l'entendre. Quelle est la prochaine étape ?",
        ],
    },
    (EmotionalContext.PRAISE, ResponseLength.MEDIUM): {
        "en": [
            "Good — this direction suits the space. The next layer is usually about fine-tuning the material balance rather than major changes.",
            "It's coming together well. At this stage, small calibrations — lighting, one texture, a single accent — usually make the biggest difference.",
            "That's exactly the register we're aiming for. The question now is whether to deepen it or shift one element.",
        ],
        "fr": [
            "Bien — cette direction convient à l'espace. La prochaine étape consiste généralement à affiner l'équilibre des matériaux plutôt qu'à faire des changements majeurs.",
            "Ça prend bien forme. À ce stade, les petits ajustements — lumière, texture, un accent — font généralement la plus grande différence.",
            "C'est exactement le registre qu'on cherche. La question est maintenant de l'approfondir ou de déplacer un élément.",
        ],
    },

    # ── NEUTRAL ───────────────────────────────────────────────────────────────
    (EmotionalContext.NEUTRAL, ResponseLength.SHORT): {
        "en": [
            "That makes sense for this space.",
            "Worth considering.",
            "Noted — where would you like to start?",
            "That reads well.",
        ],
        "fr": [
            "C'est logique pour cet espace.",
            "À considérer.",
            "Noté — par où voulez-vous commencer ?",
            "C'est cohérent.",
        ],
    },
    (EmotionalContext.NEUTRAL, ResponseLength.MEDIUM): {
        "en": [
            "That's a reasonable direction — the main consideration is how it interacts with the light and material balance already in the space.",
            "It would work here. The real question is whether you want this to feel like an evolution of the current direction or a shift.",
            "That could be the right move. It depends mostly on how much contrast you're comfortable with.",
            "Makes sense. The key is usually keeping one anchor element constant while shifting everything else.",
        ],
        "fr": [
            "C'est une direction raisonnable — la principale considération est son interaction avec la lumière et l'équilibre des matériaux existants.",
            "Ça fonctionnerait ici. La vraie question est de savoir si vous voulez une évolution ou un changement de cap.",
            "Ça pourrait être le bon mouvement. Ça dépend surtout du niveau de contraste avec lequel vous êtes à l'aise.",
            "C'est logique. L'essentiel est généralement de garder un élément d'ancrage constant pendant qu'on modifie le reste.",
        ],
    },
}

_FALLBACK_POOL = {
    "en": ["What direction feels most right to you from here?"],
    "fr": ["Quelle direction vous semble la plus juste à partir d'ici ?"],
}


# ── Micro-insights ─────────────────────────────────────────────────────────────
# Short, believable architectural observations keyed by room type.
# Used in EXTENDED responses and can be fetched standalone.

_MICRO_INSIGHTS: dict[str, dict[str, list[str]]] = {
    "living_room": {
        "en": [
            "Most living rooms need one anchor — a sofa, rug, or pendant that reads as intentional and holds everything else in place.",
            "If the room feels smaller than it should, the issue is usually light reflection rather than actual size.",
            "Open-plan spaces tend to need one element that quietly defines the zones — a rug does that better than a partition.",
            "The ceiling height does a lot of work in a living room — a low pendant can make a tall space feel more human-scaled.",
        ],
        "fr": [
            "La plupart des salons ont besoin d'un ancrage — un canapé, un tapis ou un luminaire qui semble intentionnel.",
            "Si la pièce semble plus petite qu'elle ne l'est, le problème vient souvent de la réflexion lumineuse plutôt que de la taille réelle.",
            "Les espaces ouverts ont besoin d'un élément qui délimite les zones discrètement — un tapis le fait mieux qu'une cloison.",
            "La hauteur du plafond joue un rôle important dans un salon — une suspension basse peut rendre un espace trop haut plus à l'échelle humaine.",
        ],
    },
    "bedroom": {
        "en": [
            "Bedrooms respond well to indirect lighting — overhead fixtures tend to feel too clinical for the space.",
            "A floating bed frame can make a small bedroom read as noticeably more spacious.",
            "The headboard wall is usually the right place to introduce texture or material depth — it anchors the room without overwhelming it.",
            "In a bedroom, the ceiling is often overlooked — a warm-toned ceiling colour changes the light quality more than most wall changes.",
        ],
        "fr": [
            "Les chambres répondent bien à l'éclairage indirect — les plafonniers ont souvent un rendu trop clinique.",
            "Un lit flottant peut rendre une petite chambre nettement plus spacieuse visuellement.",
            "Le mur de la tête de lit est généralement le bon endroit pour introduire de la texture — ça ancre la pièce sans l'écraser.",
            "Dans une chambre, le plafond est souvent négligé — une couleur chaude au plafond change la qualité de lumière plus que la plupart des changements muraux.",
        ],
    },
    "kitchen": {
        "en": [
            "Kitchens are often over-lit — reducing ambient light and adding focused task lighting tends to feel immediately more considered.",
            "The worktop material sets the emotional register for the whole kitchen — it's worth getting right before anything else.",
            "Handleless cabinetry reads cleaner in smaller kitchens, but hardware can add a lot of warmth to a larger one.",
        ],
        "fr": [
            "Les cuisines sont souvent trop éclairées — réduire la lumière ambiante et ajouter un éclairage de travail ciblé semble immédiatement plus réfléchi.",
            "Le plan de travail définit le registre émotionnel de toute la cuisine — c'est le bon endroit pour commencer.",
            "Les portes sans poignée paraissent plus épurées dans les petites cuisines, mais la quincaillerie peut apporter beaucoup de chaleur dans une grande.",
        ],
    },
    "bathroom": {
        "en": [
            "In bathrooms, material temperature matters more than colour — cool stone versus warm wood changes the feel entirely.",
            "A single large mirror does more for a small bathroom than most other changes — it doubles the perceived depth without adding visual noise.",
            "Bathroom lighting is often poorly considered — a warm backlit mirror changes the register of the whole space.",
        ],
        "fr": [
            "Dans les salles de bain, la température des matériaux compte plus que la couleur — pierre froide ou bois chaud change tout.",
            "Un seul grand miroir fait plus pour une petite salle de bain que la plupart des autres changements — il double la profondeur perçue.",
            "L'éclairage des salles de bain est souvent mal pensé — un miroir rétroéclairé change le registre de tout l'espace.",
        ],
    },
    "home_office": {
        "en": [
            "Task lighting in a home office is consistently underestimated — it affects focus and the overall emotional feel of the space.",
            "The sightline from the desk matters as much as the desk itself — what you face while working shapes the energy of the room.",
            "A home office benefits from one element that isn't purely functional — a material, a plant, something that offsets the clinical tendency of workspaces.",
        ],
        "fr": [
            "L'éclairage de travail dans un bureau est constamment sous-estimé — il influence la concentration et l'ambiance générale.",
            "La ligne de vue depuis le bureau compte autant que le bureau lui-même — ce qu'on regarde en travaillant définit l'énergie de la pièce.",
            "Un bureau bénéficie d'un élément qui n'est pas purement fonctionnel — un matériau, une plante, quelque chose qui compense la tendance clinique.",
        ],
    },
    "dining_room": {
        "en": [
            "Pendant height above a dining table changes the feel of the room significantly — lower reads more intimate, higher more formal.",
            "A dining room is one of the few spaces where a statement light fixture almost always works — the eye needs somewhere to land.",
            "The table material tends to set the tone for everything else in a dining room — it's the one surface everyone looks at.",
        ],
        "fr": [
            "La hauteur des suspensions au-dessus d'une table à manger change considérablement l'atmosphère — plus bas, c'est plus intime.",
            "La salle à manger est l'un des rares espaces où un luminaire fort fonctionne presque toujours — l'œil a besoin d'un point d'ancrage.",
            "Le matériau de la table définit généralement le ton de tout le reste dans une salle à manger — c'est la surface que tout le monde regarde.",
        ],
    },
    "entrance_hall": {
        "en": [
            "Entrance halls set the entire emotional register of a home — a single strong element here reads through every space that follows.",
            "Even in a narrow hallway, one considered lighting choice shifts the experience significantly — it's worth the attention.",
            "The floor material in an entrance does disproportionate emotional work — it's the first surface touched and the one that frames what's ahead.",
        ],
        "fr": [
            "L'entrée définit le registre émotionnel de toute la maison — un seul élément fort ici se répercute dans tous les espaces suivants.",
            "Même dans un couloir étroit, un seul choix d'éclairage réfléchi change l'expérience de manière significative.",
            "Le revêtement de sol à l'entrée a un impact émotionnel disproportionné — c'est la première surface touchée et celle qui cadre ce qui suit.",
        ],
    },
    "generic": {
        "en": [
            "The key is usually getting one element to anchor the space before adding detail — everything else can follow from that.",
            "Light and material temperature do most of the emotional work in a room — colour tends to follow from those decisions.",
            "Spatial perception is mostly about proportions and light, not necessarily about size — small changes in those often have large effects.",
            "One considered material choice tends to elevate a space more reliably than many smaller additions.",
        ],
        "fr": [
            "L'essentiel est souvent d'avoir un élément qui ancre l'espace avant d'ajouter des détails.",
            "La lumière et la température des matériaux font l'essentiel du travail émotionnel dans une pièce — la couleur suit généralement ces décisions.",
            "La perception de l'espace est surtout une question de proportions et de lumière, pas nécessairement de taille.",
            "Un seul choix de matériau réfléchi améliore un espace plus sûrement que beaucoup de petits ajouts.",
        ],
    },
}


# ── Helpers ────────────────────────────────────────────────────────────────────

def _pick(options: list[str], seed: str) -> str:
    idx = int(hashlib.md5(seed.encode()).hexdigest(), 16) % len(options)
    return options[idx]


# ── Public API ─────────────────────────────────────────────────────────────────

def generate_architect_light_response(
    user_message: str,
    atmosphere_id: str,
    room_type: str,
    emotional_context: EmotionalContext,
    length: ResponseLength,
    language: str = "en",
    seed_extra: str = "",
) -> str:
    """
    Generate a natural, length-calibrated architect response for conversational exchanges.

    Used for ARCHITECT_LIGHT tone path (QUESTION, PRAISE, ACKNOWLEDGMENT, HESITATION).
    Never references the prompt system or generation mechanics.
    """
    key = (emotional_context, length)
    pool = _POOLS.get(key)
    if pool is None:
        # Fallback to NEUTRAL + MEDIUM
        pool = _POOLS.get((EmotionalContext.NEUTRAL, ResponseLength.MEDIUM), _FALLBACK_POOL)

    options = pool.get(language) or pool.get("en") or _FALLBACK_POOL.get("en", ["What direction feels right to you?"])
    seed = f"alight{emotional_context.value}{length.value}{language}{seed_extra}"
    return _pick(options, seed)


def get_micro_insight(
    room_type: str = "",
    language: str = "en",
    seed: str = "",
) -> str:
    """
    Return a brief, believable architectural observation for the space.
    Used to enrich EXTENDED responses or as a standalone insight.
    """
    pool_key = room_type if room_type in _MICRO_INSIGHTS else "generic"
    pool = _MICRO_INSIGHTS[pool_key]
    options = pool.get(language) or pool.get("en") or []
    if not options:
        return ""
    idx = int(hashlib.md5(seed.encode()).hexdigest(), 16) % len(options)
    return options[idx]
