"""
PR1 — Out of Scope gate (Ayden Companion).

Deterministic, high-precision / partial-recall refusal of clearly off-domain
requests (general trivia, content generation, programming, finance, weather…).

The ONE rule that matters:
  Fire ONLY on a positive off-domain signal — NEVER on "the design router did
  not match". When in doubt, do NOT classify OOS : let the turn through. It is
  far better to occasionally answer an off-topic question than to refuse a real
  design or app-support question. Full recall arrives for free with Ayden Voice.

No LLM. Runs on the raw message (no normalisation round-trip). Patterns are
curated for PRECISION : every entry must NOT collide with interior-design or
Ayden-Studio vocabulary. Multilingual (EN / FR) so a French user is caught
without a translation step ; Khmer handled best-effort via the shared keywords.
"""
import re
from typing import Optional

# Each pattern is a clearly off-domain signal. Conservative on purpose : we
# accept missing some OOS rather than risk blocking a genuine design question.
_OOS_PATTERNS = [
    # ── general knowledge / trivia ────────────────────────────────────────────
    r"\bcapital(e)?\s+(of|d[eu]\b|des\b|d['’])",        # capital of / capitale du
    r"\bpopulation\s+(of|d[eu])\b",

    # ── content generation (write me an email / poem / essay …) ───────────────
    r"\b(write|compose|draft)\s+(me\s+)?(an?\s+)?"
    r"(e-?mail|email|letter|poem|essay|song|story|speech|cv|resume|"
    r"cover\s+letter|tweet|caption|blog|article)\b",
    r"\b([ée]cri[ts]|r[ée]dige[rz]?|r[ée]diger|compose[rz]?)\s+(moi\s+)?(un[e]?\s+)?"
    r"(e-?mail|mail|courriel|lettre|po[èe]me|texte|message|chanson|histoire|"
    r"discours|cv|tweet|article)\b",

    # ── programming / tech tasks ──────────────────────────────────────────────
    r"\bsql\b",
    r"\b(python|javascript|typescript|c\+\+|html|css|php)\b",
    r"\b(regex|algorithm[e]?)\b",
    r"\b(debug|compile)\b",

    # ── finance / crypto ──────────────────────────────────────────────────────
    r"\b(bitcoin|crypto(currency)?|blockchain|ethereum|forex|nft)\b",
    r"\bstock\s+market\b",
    r"\bbourse\b",

    # ── weather ───────────────────────────────────────────────────────────────
    r"\b(weather|forecast)\b",
    r"\bm[ée]t[ée]o\b",

    # ── translation ───────────────────────────────────────────────────────────
    r"\btranslate\b",
    r"\b(tradui[stz]+|traduire)\b",

    # ── trivia math (kept narrow : "how much is X plus Y") ────────────────────
    r"\bcombien\s+font\b",
    r"\bhow\s+much\s+is\s+\d+",

    # ── cooking / recipes ─────────────────────────────────────────────────────
    r"\brecipe\b",
    r"\brecette\b",
]

_OOS_COMPILED = [re.compile(p, re.IGNORECASE) for p in _OOS_PATTERNS]


def detect_out_of_scope(message: str, language: str = "en") -> bool:
    """
    True only when the message carries a clear off-domain signal.

    `language` is accepted for symmetry with the other classifiers and future
    per-language tuning ; today all patterns are applied regardless (keyword
    collisions across EN/FR are negligible).
    """
    if not message or not message.strip():
        return False
    for pat in _OOS_COMPILED:
        if pat.search(message):
            return True
    return False


# Fixed refusal — never answers the off-topic content. Selected by reply
# language ; falls back to English.
OUT_OF_SCOPE_REPLY = {
    "en": (
        "I'm specialised in interior design and Ayden Studio. I can help you "
        "improve your project or answer questions about the app, but I can't "
        "help with that one."
    ),
    "fr": (
        "Je suis spécialisé dans le design d'intérieur et Ayden Studio. Je peux "
        "t'aider à améliorer ton projet ou répondre à tes questions sur "
        "l'application, mais je ne peux pas répondre à cette question."
    ),
    "km": (
        "ខ្ញុំជំនាញខាងការរចនាខាងក្នុង និង Ayden Studio។ ខ្ញុំអាចជួយអ្នកកែលម្អគម្រោងរបស់អ្នក "
        "ឬឆ្លើយសំណួរអំពីកម្មវិធី ប៉ុន្តែខ្ញុំមិនអាចឆ្លើយសំណួរនេះបានទេ។"
    ),
}


def get_out_of_scope_reply(language: Optional[str] = "en") -> str:
    """Return the fixed refusal in the requested reply language (EN fallback)."""
    if not language:
        return OUT_OF_SCOPE_REPLY["en"]
    return OUT_OF_SCOPE_REPLY.get(language) or OUT_OF_SCOPE_REPLY["en"]
