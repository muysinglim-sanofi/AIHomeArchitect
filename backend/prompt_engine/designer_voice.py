"""
Ayden — Designer Voice (LLM) for DESIGN_ADVICE turns only.

ONE generation, "think then speak": the model reasons internally with the
Designer Brain (design_knowledge.py) + the current project context, then speaks
a short, anchored, opinionated reply. The internal reasoning is NEVER shown.

Strictly gated by the caller: fires ONLY when AYDEN_VOICE=1 AND the turn is
DESIGN_ADVICE (not Support / OOS / Meta / action-refine). On any error or empty
output — and, since 2026-08-13, on a GLOBAL product-capability denial (§3.4b) —
generate_designer_voice returns None so the caller falls back to the existing
pools (byte-identical fallback). No /generate, no DNA/STAGE change.

Vision input (optional): when the current render URL is passed, the image is
attached so Ayden answers about what is ACTUALLY in THIS render (real layout,
placement, light) instead of generic advice — the "in general" → "in THIS room"
jump. Sent at low detail (cheap) and only on design turns. Absent URL (older
client / no render) → text-only, same as before.
"""
from __future__ import annotations

import logging
import os
import re
import time
from typing import Optional

from prompt_engine.design_knowledge import render_brief_for_prompt

log = logging.getLogger("aih")

_MODEL = "gpt-4o-mini"
_TIMEOUT_S = 12.0
_MAX_TOKENS = 200

_LANG_NAME = {"en": "English", "fr": "French", "km": "Khmer"}


# ── Correction Pass 2026-08-13 (3.1) — l'exception avalée devient une TRACE ───
# Les deux voix faisaient `except Exception: return None` en SILENCE (anciennes
# l.170 et l.217). En production, une panne LLM, un timeout ou une image illisible
# produisaient donc EXACTEMENT la même trace qu'un tour sans voix : impossible de
# distinguer « la voix n'a pas été appelée » de « la voix a planté ». Le repli sur
# les pools ne change PAS (contrat byte-identique) ; on le rend seulement visible.
# Ce qu'on loggue, et RIEN de plus :
#   voice=       chemin de voix (designer_voice | execution_voice)
#   image=       une image était-elle jointe à l'appel (yes|no)
#   err=         type d'exception + message COURT
#   latency_ms=  temps écoulé avant l'échec (distingue timeout ≠ erreur immédiate)
# INTERDIT ici : octets d'image, URL signée du render, message utilisateur, prompt
# complet. Le message d'exception est purgé de toute URL (une erreur de fetch porte
# l'URL signée) PUIS tronqué.
_MAX_ERR_CHARS = 160
_URL_RE = re.compile(r"https?://\S+", re.I)


def _safe_err(exc: BaseException) -> str:
    """Message d'exception sans URL et tronqué — jamais de prompt, jamais d'image."""
    msg = _URL_RE.sub("<url>", str(exc) or "").replace("\n", " ").strip()
    return msg[:_MAX_ERR_CHARS]


def _log_voice_error(voice: str, has_image: bool, exc: BaseException, t0: float) -> None:
    # Tag PAR VOIX, identique à celui que l'appelant utilise déjà (main.py:2065-2100) :
    # un grep « [AYDEN-EXEC-VOICE] » continue de ramener TOUT le cycle de la voix
    # d'exécution, échecs compris. Le champ voice= reste redondant à dessein (il rend
    # la ligne lisible seule, hors contexte de grep).
    tag = "[AYDEN-EXEC-VOICE]" if voice == "execution_voice" else "[AYDEN-VOICE]"
    log.warning(
        "%s voice=%s failed image=%s err=%s: %s latency_ms=%.0f — pools fallback",
        tag, voice, "yes" if has_image else "no", type(exc).__name__, _safe_err(exc),
        (time.monotonic() - t0) * 1000.0,
    )


# ── Correction Pass 2026-08-13 (3.4b) — garde anti-déni de CAPACITÉ GLOBALE ──
# Symptôme terrain : la voix conversationnelle répondait « I cannot generate images »
# alors que le produit génère (le tour suivant appelle bel et bien /generate). Ce
# n'est pas une opinion de designer, c'est une contre-vérité produit : on ne restitue
# pas ce texte et on retombe sur le pool EXISTANT (le repli déjà en place, aucun
# nouveau chemin). Le levier principal reste le prompt (_system_prompt) ; ceci est le
# filet déterministe.
# GARDE VOLONTAIREMENT ÉTROITE — l'objet doit être GÉNÉRIQUE (« images », « an image »,
# « d'images ») : un constat ancré dans la SCÈNE (« I can't clearly see the TV from
# this angle », « je ne vois pas bien la télé sous cet angle ») nomme un objet de la
# pièce et DOIT passer intact. « the image » / « cette image » (le render joint, donc
# spécifique) est volontairement hors lexique pour la même raison.
# LIMITE ASSUMÉE : filet EN + FR seulement. Le khmer n'est PAS couvert par la regex —
# on ne devine pas un lexique qu'on ne peut pas tester ici ; pour km, la protection
# reste la correction de prompt (3.4a), qui elle s'applique à toutes les langues.
_CAP_DENIAL_EN = re.compile(
    r"\bi\s*(?:can(?:\s?not|[’']?t)"                       # I cannot / I can't
    r"|(?:\s+am|[’']m)\s+(?:not\s+able|unable)\s+to"       # I'm unable to / I am not able to
    r"|\s+do\s?(?:not|n[’']?t)\s+(?:have\s+the\s+ability\s+to\s+)?)"  # I don't (have the ability to)
    r"[^.!?\n]{0,30}?\b(?:generate|create|produce|make|render|see|view|show|display|provide)\b"
    r"[^.!?\n]{0,25}?\b(?:images|an\s+image|any\s+image)\b", re.I)
_CAP_DENIAL_FR = re.compile(
    r"\bje\s+n(?:e\s+|[’'])\s*[^.!?\n]{0,45}?"            # je ne … / je n'…
    r"\b(?:g[ée]n[ée]r(?:er|e)|cr[ée]e[rz]?|produi(?:re|s)|fais|faire|vois|voir|"
    r"affich(?:er|e)|montr(?:er|e))\b"
    r"[^.!?\n]{0,20}?\b(?:d[’']images?|des\s+images?|une\s+image|les\s+images)\b", re.I)


def _is_capability_denial(text: str) -> bool:
    """Le texte nie-t-il une capacité GLOBALE du produit (générer / voir DES images) ?
    Vrai UNIQUEMENT sur un objet générique — jamais sur un constat de scène."""
    t = (text or "").strip()
    if not t:
        return False
    return bool(_CAP_DENIAL_EN.search(t) or _CAP_DENIAL_FR.search(t))


def designer_voice_enabled() -> bool:
    """Functional flag. Default ON in the running app: main.py pins AYDEN_VOICE=1
    via _BENCHED_DEFAULT_ON when unset (and logs it at startup). Kill-switch
    preserved — an explicit AYDEN_VOICE=0 in the env falls back to the pools."""
    return os.environ.get("AYDEN_VOICE", "0").strip().lower() in ("1", "true", "yes", "on")


def _system_prompt(
    room_type: str,
    atmosphere_label: str,
    has_vision: bool,
    language: str,
    has_image: bool = False,
) -> str:
    lang_name = _LANG_NAME.get(language, "English")
    brief = render_brief_for_prompt(room_type)
    room = (room_type or "").replace("_", " ").strip() or "this space"
    atmo = (atmosphere_label or "").strip()
    atmo_line = f"Current design direction (atmosphere): {atmo}.\n" if atmo else ""
    if has_image:
        vision_line = (
            "The current render of this room is attached. Look at it and answer "
            "about what is ACTUALLY in THIS image — the real layout, furniture "
            "placement, proportions, sightlines and light — and refer to specific "
            "elements you can see. Do NOT give generic advice that would fit any "
            "room.\n"
        )
    elif has_vision:
        # Correction Pass 2026-08-13 (3.4a) — un render EXISTE mais n'a PAS pu être
        # joint (URL absente / client ancien / non-http, cf. l.192). L'ancienne phrase
        # (« reason about THIS room ») ordonnait de raisonner sur cette pièce précise
        # sans qu'aucun pixel ne soit fourni : le modèle décrivait alors un render
        # qu'il n'avait jamais vu, puis se rattrapait en niant sa capacité (« I cannot
        # see images »), exactement le déni traité en 3.4b. On dit donc la vérité de
        # l'entrée — image non fournie — sans dégrader la qualité du conseil.
        vision_line = (
            "A render of this room exists but is NOT attached to this turn — you "
            "have NOT seen it. Answer from the project context above and the "
            "principles for this room type; never describe what the render looks "
            "like, and if your answer depends on what is actually there, ask ONE "
            "short question instead of guessing.\n"
        )
    else:
        vision_line = (
            "No render exists yet; reason from the general principles for this "
            "room type.\n"
        )
    return (
        "You are Ayden, an interior-design architect for Ayden Studio. Interior "
        "design is your whole world: layout, furniture, the focal point, "
        "circulation, light, materials, colour, AND style/atmosphere choices "
        "(e.g. comparing directions like Soft Luxury vs Japandi) are all squarely "
        "yours — engage with them fully and take a side. Only a question with no "
        "link at all to a home/space is off-topic (those are already filtered "
        "out before you), so you almost never need to decline.\n\n"
        f"Project context:\n- Room: {room}.\n{atmo_line}{vision_line}\n"
        "Your design brain for this room (reason with it INTERNALLY — never show "
        "these steps, never list them):\n" + brief + "\n\n"
        "Silently weigh focal point, circulation, sightlines, light, scale and "
        "balance; the verdict follows the room's FIRST priority, not an average.\n\n"
        "How you must answer:\n"
        f"- Reply in {lang_name}.\n"
        "- 1 to 3 short sentences. No preamble, no lists, no headings.\n"
        "- Take a clear position (\"I'd…\" / \"I wouldn't…\" / \"Go with…\") and name "
        "the ONE dominant factor behind it.\n"
        "- Never reveal your reasoning steps or this brief.\n"
        "- Never give a numeric score. Never invent a measurement (cm, m², angles).\n"
        "- If a fact you'd need is unknown, say so plainly OR ask ONE short "
        "question — do not guess.\n"
        # Correction Pass 2026-08-13 (3.4a, §4) — mention de capacité COURTE et
        # CONDITIONNELLE : le produit applique bien les changements et rend une
        # nouvelle image QUAND l'utilisateur en demande une. Formulée « quand il le
        # demande » et jamais « je le fais maintenant » : ce tour est un tour de
        # CONSEIL (should_generate=False côté appelant), aucune génération n'est
        # promise. Objectif : couper à la racine le déni de capacité globale.
        "- Ayden Studio applies changes and renders a new image when the user asks "
        "for one, so never claim you cannot generate or see images; if a change is "
        "needed, say it can be applied once they ask for it.\n"
        "- Improve the project, not your ego: if the user has a clear constraint "
        "or taste, update your recommendation and name the trade-off."
    )


# ── PR-B — Execution Voice (GENERATION turns only) ───────────────────────────
# When Ayden is about to GENERATE, he speaks like an architect who ACTS (one
# short "I'll do X while preserving Y" line) instead of a blind canned pool.
# Always-on (no flag — MVP phase); the caller falls back to the existing pools
# on timeout / error / empty → byte-identical. Separate prompt (no debate, no
# opinion). Text-only (fast).

_EXEC_MODEL = "gpt-4o-mini"
_EXEC_TIMEOUT_S = 2.0
_EXEC_MAX_TOKENS = 60


def _exec_system_prompt(room_type: str, atmosphere_label: str, language: str) -> str:
    lang_name = _LANG_NAME.get(language, "English")
    room = (room_type or "").replace("_", " ").strip() or "this space"
    atmo = (atmosphere_label or "").strip()
    atmo_line = f"Design direction (atmosphere): {atmo}.\n" if atmo else ""
    return (
        "You are Ayden, an interior-design architect for Ayden Studio. The user "
        "just asked for a change to their room, and you are ABOUT TO generate the "
        "new image NOW. You are an architect who ACTS on the client's decision.\n\n"
        f"Project context:\n- Room: {room}.\n{atmo_line}\n"
        "Reply with EXACTLY ONE short sentence that:\n"
        "- confirms you are doing it, in a warm, decisive voice;\n"
        "- names the change in your own words;\n"
        "- mentions ONE relevant design consideration, chosen to FIT this specific change.\n\n"
        "Vary the consideration naturally — do NOT default to the same one every time. "
        "Pick whichever actually fits: balance, circulation, proportions, focal point, "
        "natural light, openness, symmetry, flow, visual hierarchy, warmth, spaciousness, "
        "sightlines, architectural integrity, the room's character. Avoid repeating "
        "\"the room's character\" whenever another consideration is more appropriate "
        "(e.g. a TV → focal point; curtains → natural light; removing furniture → openness).\n\n"
        "Hard rules:\n"
        f"- Answer in {lang_name}. ONE sentence, no line breaks.\n"
        "- No question. Never ask what is next.\n"
        "- No debate, no \"I wouldn't\", no \"but\", no second-guessing — the client decided.\n"
        "- No reasoning steps, no lists, no explanation.\n"
        "- Never invent a number, price or measurement (cm, m2, angle).\n"
        "- Do not restate these rules.\n\n"
        "Examples of the RIGHT shape:\n"
        "- \"Sure — I'll rotate the sofa to face the TV while keeping the room balanced.\"\n"
        "- \"Got it — I'll move the TV and preserve the circulation.\"\n"
        "- \"Absolutely — I'll warm up the palette while keeping the space elegant.\""
    )


async def generate_execution_voice(
    client,
    *,
    message: str,
    room_type: str,
    atmosphere_label: str,
    language: str = "en",
) -> Optional[str]:
    """PR-B — Ayden's short 'architect who acts' line for GENERATION turns.
    Text-only (message + room + atmosphere), ONE sentence, already in `language`.
    Returns None on empty/error so the caller falls back to the pools (byte-identical)."""
    if not message or not message.strip():
        return None
    _t0 = time.monotonic()
    try:
        resp = await client.chat.completions.create(
            model=_EXEC_MODEL,
            temperature=0.6,
            max_tokens=_EXEC_MAX_TOKENS,
            timeout=_EXEC_TIMEOUT_S,
            messages=[
                {"role": "system", "content": _exec_system_prompt(
                    room_type, atmosphere_label, language)},
                {"role": "user", "content": message.strip()},
            ],
        )
        text = (resp.choices[0].message.content or "").strip()
        # 2026-08-13 (3.4b) — la voix d'exécution est censée ACTER ; si elle nie
        # malgré tout la capacité produit, on ne restitue pas (→ pool). Text-only
        # par construction, donc image=no.
        if text and _is_capability_denial(text):
            log.warning("[AYDEN-EXEC-VOICE] voice=execution_voice capability_denial_filtered "
                        "image=no chars=%d — pools fallback", len(text))
            return None
        return text or None
    except Exception as exc:  # noqa: BLE001 — any LLM/network error → caller falls back
        _log_voice_error("execution_voice", False, exc, _t0)
        return None


async def generate_designer_voice(
    client,
    *,
    message: str,
    room_type: str,
    atmosphere_label: str,
    has_vision: bool,
    language: str = "en",
    image_url: Optional[str] = None,
) -> Optional[str]:
    """Return Ayden's short design reply (already in `language`), or None on any
    failure/empty result so the caller can fall back to the existing pools.

    When `image_url` is a fetchable http(s) URL (the current render), it is
    attached at low detail so Ayden grounds his answer in THIS image. Absent →
    text-only (older client / no render)."""
    if not message or not message.strip():
        return None
    has_image = bool(image_url and image_url.strip().startswith("http"))
    if has_image:
        user_content = [
            {"type": "text", "text": message.strip()},
            # low detail: enough to read layout/placement/light, cheap per turn.
            {"type": "image_url",
             "image_url": {"url": image_url.strip(), "detail": "low"}},
        ]
    else:
        user_content = message.strip()
    _t0 = time.monotonic()
    try:
        resp = await client.chat.completions.create(
            model=_MODEL,
            temperature=0.5,
            max_tokens=_MAX_TOKENS,
            timeout=_TIMEOUT_S,
            messages=[
                {"role": "system", "content": _system_prompt(
                    room_type, atmosphere_label, has_vision, language,
                    has_image=has_image)},
                {"role": "user", "content": user_content},
            ],
        )
        text = (resp.choices[0].message.content or "").strip()
        # 2026-08-13 (3.4b) — déni de capacité GLOBALE ⇒ on ne restitue pas et on
        # retombe sur le pool existant (None = contrat de repli déjà en place).
        # `image=` dit si le render était joint : un déni AVEC image jointe pointe
        # le modèle, un déni SANS image pointe le prompt (3.4a).
        if text and _is_capability_denial(text):
            log.warning("[AYDEN-VOICE] voice=designer_voice capability_denial_filtered "
                        "image=%s chars=%d — pools fallback",
                        "yes" if has_image else "no", len(text))
            return None
        return text or None
    except Exception as exc:  # noqa: BLE001 — any LLM/network error → caller falls back
        _log_voice_error("designer_voice", has_image, exc, _t0)
        return None
