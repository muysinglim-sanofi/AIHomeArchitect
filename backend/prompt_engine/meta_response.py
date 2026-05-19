"""
meta_response.py — Wave 3.1 meta conversation response generator.

Produces short, architect-voiced responses for meta conversational intents.
Bilingual: English and French.
Deterministic pick via MD5 hash (same pattern as architect_response.py).

Response rules:
  - 1–2 sentences maximum
  - Calm, warm, premium — no enthusiasm, no emojis
  - Architect-like: brief, direct, confident
  - Language-aware: always responds in target_language
  - For LANGUAGE_SWITCH: responds in the requested language (confirming the switch)
  - For all others: responds in the detected input language
"""

from __future__ import annotations
import hashlib
from .meta_intent import MetaIntent, MetaClassification


def _pick(options: list[str], seed: str) -> str:
    idx = int(hashlib.md5(seed.encode()).hexdigest(), 16) % len(options)
    return options[idx]


_RESPONSES: dict[MetaIntent, dict[str, list[str]]] = {
    MetaIntent.GREETING: {
        "en": [
            "Hello — what room are we working on today?",
            "Hi — what would you like to design?",
            "Good to connect. What direction are you thinking for this space?",
        ],
        "fr": [
            "Bonjour — sur quelle pièce travaille-t-on aujourd'hui ?",
            "Salut — qu'est-ce que vous voulez créer ?",
            "Bonsoir — quelle direction envisagez-vous pour cet espace ?",
        ],
    },
    MetaIntent.LANGUAGE_SWITCH: {
        "fr": [
            "Oui bien sûr — nous pouvons continuer en français.",
            "Parfait — je continue en français.",
        ],
        "en": [
            "Of course — continuing in English.",
            "Sure, let's continue in English.",
        ],
    },
    MetaIntent.THANKS: {
        "en": [
            "Of course. What would you refine next?",
            "Glad that landed well. What's the next direction?",
            "My pleasure. Where would you like to take it from here?",
        ],
        "fr": [
            "Avec plaisir. Qu'aimeriez-vous affiner ensuite ?",
            "Ravi que ça vous convienne. Quelle est la prochaine étape ?",
            "Bien sûr. Dans quelle direction souhaitez-vous aller maintenant ?",
        ],
    },
    MetaIntent.CONFUSION: {
        "en": [
            "Let me clarify — which specific element are you asking about?",
            "Happy to explain. Which part would you like more detail on?",
        ],
        "fr": [
            "Permettez-moi de préciser — sur quel élément portait votre question ?",
            "Bien sûr — quelle partie souhaitez-vous que j'explique davantage ?",
        ],
    },
    MetaIntent.CORRECTION: {
        "en": [
            "Understood — what direction were you aiming for?",
            "I see — let's realign. What were you looking for?",
            "Got it. What would you like instead?",
        ],
        "fr": [
            "Je comprends — quelle direction souhaitiez-vous prendre ?",
            "D'accord — réajustons. Qu'est-ce que vous espériez obtenir ?",
            "Compris. Qu'aimeriez-vous à la place ?",
        ],
    },
    MetaIntent.FRUSTRATION: {
        "en": [
            "Understood. What specifically isn't working for you?",
            "I hear you — what would you like me to change?",
        ],
        "fr": [
            "Compris — qu'est-ce qui précisément ne fonctionne pas ?",
            "Je vous entends. Qu'aimeriez-vous que je modifie ?",
        ],
    },
    MetaIntent.STOP_GENERATION: {
        "en": [
            "Of course — let's discuss first. What are you thinking about?",
            "Understood, no generation yet. What direction are you considering?",
        ],
        "fr": [
            "Bien sûr — discutons d'abord. Qu'avez-vous à l'esprit ?",
            "Compris — pas de génération pour l'instant. Quelle direction envisagez-vous ?",
        ],
    },
    MetaIntent.CLARIFICATION: {
        "en": [
            "Happy to explain — which aspect are you curious about?",
            "Of course — which part would you like more detail on?",
        ],
        "fr": [
            "Bien sûr — sur quelle partie souhaitez-vous plus de détails ?",
            "Volontiers — quel aspect vous intéresse davantage ?",
        ],
    },
    MetaIntent.SMALL_TALK: {
        "en": [
            "Focused on the design — ready when you are.",
            "I'm here whenever you'd like to start.",
            "Happy to help with the space. What are you thinking about?",
            "I work best with design conversations — what's on your mind?",
        ],
        "fr": [
            "Concentré sur le design — prêt quand vous l'êtes.",
            "Je suis là quand vous voulez commencer.",
            "Ravi de vous aider sur le design. À quoi pensez-vous ?",
            "Je travaille mieux sur des questions de design — qu'avez-vous en tête ?",
        ],
    },
    MetaIntent.OPEN_CONVERSATION: {
        "en": [
            "Take your time — I'm here whenever you're ready.",
            "No rush. What's on your mind?",
            "Happy to just talk through ideas before anything visual.",
        ],
        "fr": [
            "Prenez votre temps — je suis là quand vous êtes prêt.",
            "Pas de précipitation. À quoi pensez-vous ?",
            "On peut simplement discuter avant de passer au visuel.",
        ],
    },
}


def generate_meta_response(meta: MetaClassification, seed_extra: str = "") -> str:
    """
    Generate a concise architect-voiced meta response.

    For LANGUAGE_SWITCH: responds in target_language (confirming the switch).
    For all other meta intents: responds in the detected input language.
    Falls back to English if no pool exists for the target language.
    """
    pool = _RESPONSES.get(meta.intent, {})
    lang = meta.target_language
    options = pool.get(lang) or pool.get("en") or ["I'm here. What would you like to adjust?"]
    seed = f"{meta.intent.value}{lang}{seed_extra}"
    return _pick(options, seed)


def generate_project_aware_greeting(
    meta: MetaClassification,
    session_memory: "object",  # SessionMemory — typed loosely to avoid circular import
    seed_extra: str = "",
) -> str:
    """
    Generate a greeting that references the active project when context exists.

    Falls back to standard greeting when no atmosphere or room is known.
    Used when the user says "hello" mid-session with active project state.
    """
    lang = meta.target_language

    atm_id: str = getattr(session_memory, "atmosphere_mentioned", "")
    room_id: str = getattr(session_memory, "room_type_mentioned", "")
    msg_count: int = getattr(session_memory, "message_count", 0)

    # Only project-aware if we have meaningful context
    if not atm_id and not room_id:
        return generate_meta_response(meta, seed_extra)

    atm_label = atm_id.replace("_", " ").title() if atm_id else ""
    room_label = room_id.replace("_", " ") if room_id else "space"

    if lang == "fr":
        if atm_label and room_label != "space":
            options = [
                f"Hey — la direction {atm_label} est toujours là. On continue ?",
                f"Bonjour — votre {room_label} {atm_label} est là où on l'a laissé. Qu'est-ce qu'on ajuste ?",
                f"Bonjour — la base {atm_label} est active. Qu'est-ce qu'on pousse maintenant ?",
                f"Salut — votre projet {atm_label} est prêt. Qu'est-ce qu'on affine ?",
            ]
        elif atm_label:
            options = [
                f"Bonjour — la direction {atm_label} est toujours active. On reprend ?",
                f"Hey — votre direction {atm_label} est là. Qu'est-ce qu'on change ?",
            ]
        else:
            options = [
                "Bonjour — votre espace est prêt. Qu'est-ce qu'on affine ?",
                "Salut — je suis là. On continue ?",
            ]
    else:
        if atm_label and room_label != "space":
            options = [
                f"Hey — the {atm_label} direction is still active. Ready to keep going?",
                f"Hi — your {atm_label} {room_label} is right where we left it. What would you like to adjust?",
                f"Good to see you. The {atm_label} base is set — what do you want to push next?",
                f"Hello — we can keep refining this {atm_label} direction. What's next?",
            ]
        elif atm_label:
            options = [
                f"Hey — the {atm_label} direction is still active. What's next?",
                f"Hi — your {atm_label} project is right here. What would you like to change?",
            ]
        else:
            options = [
                "Good to see you. Your space is ready — what would you like to refine?",
                "Hi — we're right where we left off. What's next?",
            ]

    seed = f"project_greeting{lang}{atm_id}{room_id}{seed_extra}"
    return _pick(options, seed)
