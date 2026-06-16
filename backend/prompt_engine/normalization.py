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

import asyncio
import logging

from prompt_engine.meta_intent import _detect_language  # reuse the language detector

log = logging.getLogger("ayden")

# Phase 3 — in-process translation cache: (lang, original_text) -> english.
# Translation is deterministic (temp 0) so entries never go stale / need
# invalidation. Bounded to cap memory; cleared on process restart (re-warms
# cheaply). Shared across sessions safely (key is the text, user-independent).
_TRANSLATION_CACHE: dict[tuple[str, str], str] = {}
_CACHE_MAX = 1024

# Languages that get translated. Everything else (notably "en") is passthrough.
_NORMALIZE_LANGS = {"fr", "km"}

# Phase 5 — reply-localization cache: (target_lang, english_reply) -> localized.
_REPLY_CACHE: dict[tuple[str, str], str] = {}
_LANG_NAMES = {"fr": "French", "km": "Khmer"}

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


async def normalize_history_to_english(client, history_messages, lang, *, enabled):
    """Phase 3 — return conversation history with USER-message contents
    translated to English (FR/KM), so parse_history / accumulate_refinements
    (English keyword matchers) work on multi-turn FR/KM sessions.

    Strict passthrough — returns the SAME object — for EN / flag-off / empty /
    unsupported lang (history byte-identical, English-freeze preserved).
    assistant / system messages are never touched. Translations are cached
    in-process so each unique user message is translated at most once.
    Errors fall back to the original message content (never blocks).
    """
    if not enabled or lang not in _NORMALIZE_LANGS or not history_messages:
        return history_messages  # passthrough — SAME object (freeze guard)

    # Translate (cache-aware, deduped, in parallel) the user messages we don't
    # have yet.
    pending = []
    seen = set()
    for m in history_messages:
        if m.get("role") == "user":
            c = (m.get("content") or "").strip()
            if c and (lang, c) not in _TRANSLATION_CACHE and c not in seen:
                seen.add(c)
                pending.append(c)
    if pending:
        results = await asyncio.gather(
            *[normalize_to_english(client, t, lang, enabled=True) for t in pending]
        )
        for t, en in zip(pending, results):
            # Only cache a REAL translation; on error/no-op (en == t) skip so it
            # retries later instead of pinning the original for the session.
            if en != t and len(_TRANSLATION_CACHE) < _CACHE_MAX:
                _TRANSLATION_CACHE[(lang, t)] = en

    # Rebuild history applying cached translations; untranslated/other roles
    # keep their original message object.
    out = []
    for m in history_messages:
        if m.get("role") == "user":
            c = (m.get("content") or "").strip()
            en = _TRANSLATION_CACHE.get((lang, c))
            if en:
                nm = dict(m)
                nm["content"] = en
                out.append(nm)
                continue
        out.append(m)
    return out


async def localize_reply(client, text, target_lang, *, enabled):
    """Phase 5 — translate a FINAL assistant reply into the user's language, but
    ONLY when it is still English (i.e. an EN template fallback). Replies already
    written in the target language (hand-crafted FR/KM templates) are detected
    and returned UNCHANGED — no double-translation, no quality loss.

    Strict passthrough (SAME object) for EN target / flag-off / empty, so the
    English path stays byte-identical. Errors fall back to the original + log.
    """
    if not enabled or target_lang not in _NORMALIZE_LANGS or not text or not text.strip():
        return text
    detected = _detect_language(text)
    if detected == target_lang:
        return text  # already localized (hand-crafted template) — preserve it
    if detected != "en":
        return text  # unknown / mixed — don't risk mistranslating

    key = (target_lang, text)
    if key in _REPLY_CACHE:
        return _REPLY_CACHE[key]

    lang_name = _LANG_NAMES.get(target_lang, target_lang)
    try:
        resp = await client.chat.completions.create(
            model="gpt-4o-mini",
            temperature=0,
            max_tokens=400,
            messages=[
                {"role": "system", "content": (
                    "You are a translation layer for an interior-design app. "
                    f"Translate the assistant's chat message into natural, concise {lang_name}.\n"
                    "RULES:\n"
                    "- Translation ONLY. Keep the same meaning, tone and length.\n"
                    "- Preserve atmosphere/style/room names and proper nouns "
                    "verbatim (e.g. 'Japandi', 'Warm Modern', 'Nordic').\n"
                    f"- If the text is already in {lang_name}, return it unchanged.\n"
                    "- Output ONLY the translated message: no quotes, no preamble."
                )},
                {"role": "user", "content": text},
            ],
        )
        out = (resp.choices[0].message.content or "").strip() or text
        if out != text and len(_REPLY_CACHE) < _CACHE_MAX:
            _REPLY_CACHE[key] = out
        return out
    except Exception as e:  # network / timeout / API — never block the reply
        log.warning("[localize_reply] en->%s failed (keeping original): %s", target_lang, e)
        return text
