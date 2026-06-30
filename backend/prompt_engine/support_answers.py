"""
PR2 Support (Ayden Companion) — deterministic Support answers.

Two grounded, multilingual (EN/FR/KM), NO-LLM, NO-image helpers used by /chat:

  build_result_explanation(atmosphere_label, room_type, language)
      Explains the design LOGIC of the current render — anchored on the chosen
      atmosphere + the preservation contract (architecture kept, furnishing
      restyled) + an invitation to change a specific element. Anti-bluff: it
      NEVER claims a specific object/measurement is present (the pixel-specific
      "why THAT exact object" is PR3 Voice+vision). It explains intent, not pixels.

  build_quota_answer(decision, language)
      Turns a real promo.AccessDecision into an honest quota reply: the ACTUAL
      remaining count + where to upgrade. Never invents a number or a price
      (the price lives on the paywall screen). Static product facts stay in
      product_knowledge ; only the live quota number comes from here.

Mirrors out_of_scope.py: small, deterministic, language-keyed with EN fallback.
"""
from __future__ import annotations

import re
from typing import Any


# ── Quota-REMAINING question detector (count, not price) ──────────────────────
# High precision, multilingual. Fires ONLY on "how many do I have left / are
# they free / free generations" — the REMAINING-COUNT question, answerable with
# the user's live quota. Deliberately EXCLUDES pure pricing ("how much does it
# cost", "combien ça coûte", "what's the price") — those want the price, which
# lives on the paywall screen, so they stay with the static billing KB. Never
# fires on design requests ("combien de plantes", "how many plants") because the
# quota lexicon (generation/credit/render/free) is required.
_QUOTA_PATTERNS = [
    # FR — count of generations/credits/trials remaining, or "is it free"
    r"\bcombien\b.*\b(g[ée]n[ée]ration|cr[ée]dit|essai|rendu|image|vision)s?\b",
    r"\b(il\s+me\s+reste|me\s+reste-t-il|reste-t-il)\b.*\b(g[ée]n[ée]ration|cr[ée]dit|essai|gratuit|rendu)s?\b",
    r"\b(g[ée]n[ée]ration|cr[ée]dit|essai|rendu)s?\b.*\b(gratuit|restant|me\s+reste|qu'?il\s+me\s+reste)\b",
    r"\b(c'?\s?est|est-ce(\s+que)?(\s+c'?\s?est)?)\s+gratuit\b",
    r"\bcombien.*gratuit",
    # EN — count of generations/credits/renders remaining, or "is it free"
    r"\bhow\s+many\b.*\b(generation|credit|render|image|vision|free)s?\b",
    r"\b(generation|credit|render)s?\s+(left|remaining)\b",
    r"\bhow\s+many\s+(free\s+)?(generation|credit|render)s?\b",
    r"\b(is\s+it|are\s+they|it'?s)\s+free\b",
    r"\bfree\s+(generation|credit|trial|render)s?\b",
    r"\bdo\s+i\s+have\s+(any\s+)?(generation|credit|render)s?\s+(left|remaining)\b",
]
_QUOTA_COMPILED = [re.compile(p, re.IGNORECASE) for p in _QUOTA_PATTERNS]


def detect_quota_question(message: str) -> bool:
    """True when the user asks how many generations/credits they have left."""
    if not message or not message.strip():
        return False
    return any(p.search(message) for p in _QUOTA_COMPILED)


def _lang(language: str) -> str:
    l = (language or "en").strip().lower()[:2]
    return l if l in ("en", "fr", "km") else "en"


# ── RESULT_EXPLANATION ────────────────────────────────────────────────────────
def build_result_explanation(
    atmosphere_label: str, room_type: str, language: str = "en"
) -> str:
    """Explain the design reasoning behind the current render (intent, not pixels)."""
    lang = _lang(language)
    atmo = (atmosphere_label or "").strip()
    room = (room_type or "").strip().replace("_", " ")

    if lang == "fr":
        atmo_part = f" en direction « {atmo} »" if atmo else ""
        room_part = f" cette {room}" if room else " cet espace"
        return (
            f"Voilà mon raisonnement sur{room_part} : je l'ai travaillé{atmo_part} — "
            "c'est cette direction qui guide les matières, la palette et la lumière "
            "que tu vois. Tout du long, je conserve ton architecture existante "
            "(murs, fenêtres, portes, volume de la pièce) et je restyle le mobilier "
            "et les finitions par-dessus. Si un élément précis ne te convient pas, "
            "dis-moi quoi changer et je l'ajuste."
        )
    if lang == "km":
        atmo_part = f"តាមទិសដៅ « {atmo} »" if atmo else ""
        return (
            f"នេះជាហេតុផលរបស់ខ្ញុំ៖ ខ្ញុំបានរចនាវា{atmo_part} — ទិសដៅនេះកំណត់សម្ភារៈ "
            "ពណ៌ និងពន្លឺដែលអ្នកឃើញ។ ខ្ញុំរក្សាស្ថាបត្យកម្មដើមរបស់អ្នក (ជញ្ជាំង បង្អួច ទ្វារ "
            "និងទម្រង់បន្ទប់) ហើយប្ដូររចនាបថគ្រឿងសង្ហារិម និងការបញ្ចប់នៅពីលើ។ "
            "បើមានធាតុណាមួយមិនត្រូវចិត្ត ប្រាប់ខ្ញុំ ខ្ញុំនឹងកែវា។"
        )
    atmo_part = f" as a {atmo} space" if atmo else ""
    room_part = f" this {room}" if room else " this space"
    return (
        f"Here's the thinking behind{room_part}: I worked it{atmo_part} — that "
        "direction leads the materials, palette and lighting you see. Throughout, "
        "I keep your existing architecture (walls, windows, doors, the room's "
        "shape) and restyle the furnishing and finishes on top of it. If a "
        "specific element isn't what you'd choose, tell me what to change and "
        "I'll adjust it."
    )


# ── Quota honesty ─────────────────────────────────────────────────────────────
def _is_unlimited(decision: Any) -> bool:
    tier = getattr(decision, "tier", "free")
    return tier in ("admin", "premium", "promo_unlimited") or bool(
        getattr(decision, "promo_unlimited_active", False)
    )


def build_quota_answer(decision: Any, language: str = "en") -> str:
    """Honest, live quota reply from a promo.AccessDecision. Never invents numbers."""
    lang = _lang(language)
    tier = getattr(decision, "tier", "free")

    if _is_unlimited(decision):
        return {
            "fr": "Tu as un accès illimité aux générations pour le moment — "
                  "crée autant de visions que tu veux.",
            "km": "បច្ចុប្បន្នអ្នកមានសិទ្ធិបង្កើតរូបភាពគ្មានដែនកំណត់ — "
                  "បង្កើតវិស័យបានតាមចិត្ត។",
            "en": "You have unlimited generations right now — create as many "
                  "visions as you like.",
        }[lang]

    if tier == "promo_limited":
        n = int(getattr(decision, "promo_generations_remaining", 0) or 0)
        return {
            "fr": f"Il te reste {n} génération(s) dans ton offre promo. "
                  "Ensuite, tu pourras passer à l'abonnement depuis l'app.",
            "km": f"អ្នកនៅសល់ {n} ការបង្កើតក្នុងកម្មវិធីប្រូម៉ូ។ "
                  "បន្ទាប់មក អ្នកអាចជាវនៅក្នុងកម្មវិធី។",
            "en": f"You have {n} generation(s) left in your promo. After that, "
                  "you can subscribe from the app.",
        }[lang]

    # free tier — the real remaining count + where to upgrade (no price invented)
    n = int(getattr(decision, "free_remaining", 0) or 0)
    if lang == "fr":
        return (
            f"Il te reste {n} génération(s) gratuite(s). "
            + ("Quand tu seras à court, l'écran d'abonnement de l'app te montre "
               "les options pour continuer." if n > 0 else
               "Pour continuer à générer, passe à l'abonnement depuis l'écran "
               "dédié dans l'app.")
        )
    if lang == "km":
        return (
            f"អ្នកនៅសល់ការបង្កើតឥតគិតថ្លៃ {n} ដង។ "
            + ("ពេលអស់ អេក្រង់ជាវនៅក្នុងកម្មវិធីបង្ហាញជម្រើសបន្ត។" if n > 0 else
               "ដើម្បីបន្តបង្កើត សូមជាវនៅក្នុងកម្មវិធី។")
        )
    return (
        f"You have {n} free generation(s) left. "
        + ("When you run out, the subscription screen in the app shows your "
           "options to keep going." if n > 0 else
           "To keep generating, upgrade from the subscription screen in the app.")
    )
