"""Phase 2 — Multilingual normalization seam (FR/KM -> English-internal).

ONE boundary that translates the user's free-text instruction to canonical
English BEFORE it reaches any classifier / prompt composition, so the whole
generation engine (DNA, preservation, classifiers, prompts) keeps receiving
English only. This is a translation boundary — NOT a multilingual prompt
rewrite, and it never touches DNA/preservation/classifier logic.

Hard guarantees:
  * EN / flag-off / empty  -> returns the EXACT input object (strict passthrough,
    so the English path is byte-identical by construction).
  * FR/KM (flag on)        -> concise, faithful English translation via a cheap
    model (gpt-4o-mini, temperature 0). Translation only — no enrichment.
  * Any error / timeout    -> returns the ORIGINAL text + logs (never blocks).

The original user text is preserved by the caller for display / history.
"""

import logging

log = logging.getLogger("ayden")

# Languages that get translated. Everything else (notably "en") is passthrough.
_NORMALIZE_LANGS = {"fr", "km"}

_SYSTEM_PROMPT = (
    "You are a translation layer for an interior-design app. Translate the "
    "user's design instruction into CONCISE, FAITHFUL English.\n"
    "RULES:\n"
    "- Translation ONLY. Do NOT rewrite, enrich, simplify, summarize, or add "
    "any detail that is not in the source.\n"
    "- Preserve design terminology, atmosphere/style names, room names and "
    "proper nouns verbatim (e.g. 'Japandi', 'Warm Modern', 'Nordic').\n"
    "- Preserve temporal / lighting intent exactly (e.g. 'la nuit' -> 'at "
    "night', 'cinematique' -> 'cinematic', 'lumiere du jour' -> 'daylight', "
    "'coucher de soleil' -> 'sunset').\n"
    "- Preserve spatial / structural verbs exactly (move, open up, knock down, "
    "remove wall, add window, rearrange).\n"
    "- If the text is already English, return it unchanged.\n"
    "- Output ONLY the English instruction: no quotes, no preamble, no notes."
)


async def normalize_to_english(client, text, lang, *, enabled):
    """Return ``text`` normalized to English for FR/KM; strict passthrough else.

    Args:
        client: an AsyncOpenAI-compatible client (only used on the FR/KM path).
        text:   the raw user instruction (original language).
        lang:   the authoritative UI locale ('en' | 'fr' | 'km' | ...).
        enabled: master flag (``MULTILINGUAL_NORMALIZE``). When False -> no-op.

    Returns:
        The SAME object as ``text`` on the passthrough path (EN / flag-off /
        empty / unsupported lang / error), or a translated English string.
    """
    # Strict passthrough — return the identical object so downstream inputs are
    # byte-identical (this is the English-freeze guarantee, verified by tests).
    if not enabled:
        return text
    if not text or not text.strip():
        return text
    if lang not in _NORMALIZE_LANGS:
        return text

    try:
        resp = await client.chat.completions.create(
            model="gpt-4o-mini",
            temperature=0,
            max_tokens=240,
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": text},
            ],
        )
        out = (resp.choices[0].message.content or "").strip()
        return out if out else text
    except Exception as e:  # network / timeout / API — never block generation
        log.warning("[normalize] %s->en failed (keeping original): %s", lang, e)
        return text
