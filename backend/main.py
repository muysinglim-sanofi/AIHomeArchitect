import asyncio
import base64
import hashlib
import io
import json
import logging
import os
import time
import traceback
import uuid
from datetime import datetime, timezone

from PIL import Image as PilImage

import httpx
from dotenv import load_dotenv
from fastapi import Body, Depends, FastAPI, Form, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from openai import AsyncOpenAI, BadRequestError
from supabase import create_client

# Wave 5.17a — Identity foundation
# CORRECTIF PERF fast-path (2026-07-14) — get_current_user est ré-importé : les routes
# image /generate,/refine passent de require_active_identity (1 SELECT séquentiel) à
# get_current_user (JWT seul) + garde merged_closed foldée dans le gather du resolver.
from auth import CurrentUser, get_current_user
# Unified Identity V1 — Commit 3a : merge endpoints + active-identity guard
# Commit 3b : sweep de révocation Auth (même worker, isolé)
# enforce_identity_from_decision : enforcement 403/503 fast-path (après le gather resolver).
from identity import (
    identity_router,
    require_active_identity,
    sweep_pending_revocations,
    enforce_identity_from_decision,   # /generate : identité foldée dans le gather resolver
    fetch_identity_active,            # /refine : identité foldée EN PARALLÈLE de l'ownership
    enforce_identity_read,            # /refine : enforce depuis un IdentityRead brut
)
# Wave 5.17b — Quota enforcement + IP rate limit
# Wave 5.18 — Developer Validation Mode admin-flag endpoint
from quota import (
    get_quota_status,
    reserve_generation,
    confirm_generation,
    fail_generation,
    FREE_TIER_LIMIT,
    is_admin_role,
    has_admin_role,
)
# Generation Intent v1 — PR1 (OBSERVATION ONLY). Persists the durable INTENT
# identity + technical JOB rows alongside the current flow. No claim, no
# short-circuit; client_request_id stays the active idempotency key.
from intent_observer import (
    compute_intent_id,
    observe_job_start,
    observe_job_end,
    observe_intent_end,
    get_latest_intent_for_session,
    claim_generation_intent,
    reclaim_generation_intent,
    bump_claim,
    CLAIM_COUNTERS,
)
# Generation Intent v1 — PR4 : reconciliation worker (lifecycle only, no billing).
from intent_reconciliation import reconcile_once, RECONCILE_INTERVAL_SECONDS
# Wave 5.17d — Free-tier scope (room + atmosphere allowlist for non-premium)
from free_tier import check_restrictions
# Wave 5.17d — RevenueCat webhook receiver (POST /webhooks/revenuecat)
from revenuecat_webhook import router as revenuecat_router
from rate_limit import check_ip_rate_limit
# Sprint 1 — server-side free-tier watermark (applied to bytes before upload)
from watermark import apply_watermark
# Sprint 1B — promo / influencer / admin codes (backend-authoritative resolver)
from promo import (
    resolve_generation_access,
    get_promo_access,
    redeem_promo,
    consume_promo_generation,
    create_promo_code,
    list_promo_codes,
    set_promo_active,
    check_redeem_rate,
)

from prompt_engine import (
    compose_generation_prompt,
    parse_history,
    classify_edit_mode,
    classify_room,
    surprise_me,
    rank_atmospheres,
    classify_intent,
    generate_architect_response,
    generate_chat_response,
    generate_mixed_response,
    # Wave 4.11e
    generate_clarification_exit_response,
    generate_brief_summary,
    # Wave 4.11e (sanity-check follow-up)
    generate_generation_demand_response,
    get_suggestion_chips,
    classify_meta_intent,
    MetaIntent,
    generate_meta_response,
    generate_project_aware_greeting,
    build_session_memory,
    select_tone_mode,
    generate_human_soft_response,
    ToneMode,
    detect_emotional_context,
    select_response_length,
    generate_architect_light_response,
    EmotionalContext,
    classify_transformation,
    build_spatial_preservation_addendum,
    TransformationType,
    get_contextual_chips,
)
# PR0 (Ayden Companion) — situational awareness layer (deterministic, no LLM).
# Facts and interpretation are separate layers ; the wire envelope merges them.
from prompt_engine.situational_context import (
    build_situational_facts,
    build_context,
    context_log_line,
    attach_context,
)
# PR-Router (Ayden Companion) — TurnIntent facade : consolidates the existing
# classifiers + RESULT_EXPLANATION / PREFERENCE, and re-exports the OOS detector.
from prompt_engine.conversation_router import (
    TurnIntent,
    resolve_turn_intent,
    detect_result_explanation,   # PR2 Support — RESULT_EXPLANATION gate
    detect_design_opinion_question,  # PR3-router — opinion question → DESIGN_ADVICE
    detect_out_of_scope,
    get_out_of_scope_reply,
)
# PR2 Support (Ayden Companion) — deterministic Support answers (no LLM, no image):
# RESULT_EXPLANATION design-logic reply + honest live-quota reply.
from prompt_engine.support_answers import (
    build_result_explanation,
    build_quota_answer,
    detect_quota_question,
)
# PR3 Designer Voice (Ayden Companion) — LLM voice for DESIGN_ADVICE turns only,
# behind the functional flag AYDEN_VOICE (default OFF). When OFF / non-design /
# action-refine / LLM error, the existing pools stay the byte-identical fallback.
from prompt_engine.designer_voice import (
    designer_voice_enabled, generate_designer_voice,
    generate_execution_voice,  # PR-B — Execution Voice (always-on, fallback-only)
)
from prompt_engine.transformation_state_builder import (
    build_vision_caption,
    build_clean_instruction,
)
from prompt_engine.atmosphere_dna import label_to_atmosphere_id
from prompt_engine.normalization import (  # Phase 2/3/5 — FR/KM<->EN seam
    normalize_to_english,
    normalize_history_to_english,
    localize_reply,
)


def _norm_enabled() -> bool:
    """Phase 2/3/5 — master multilingual-normalize flag (MULTILINGUAL_NORMALIZE)."""
    return os.environ.get("MULTILINGUAL_NORMALIZE", "0") == "1"


# ── Wave 4.9.3 perf — structural-identity capture cache ───────────────────────
# The V1 vision capture (~5-7s, 2× gpt-4o-mini) is a PURE function of the source
# image bytes (architecture-only, atmosphere/room-independent, fixed capture
# prompt), so the same photo always yields the same identity. We cache the
# to_token() string keyed by SHA-256(image_bytes); on hit we from_token() it —
# the EXACT round-trip V2+ already trusts every iteration — so the prompt stays
# byte-identical (zero quality change), we just skip the vision calls.
# In-memory, bounded, per-process. Flag STRUCT_ID_CACHE (default off).
_STRUCT_ID_CACHE: "dict[str, str]" = {}
_STRUCT_ID_CACHE_MAX = 128


def _struct_id_cache_enabled() -> bool:
    return os.environ.get("STRUCT_ID_CACHE", "0") == "1"


def _struct_id_cache_key(image_bytes: bytes) -> str:
    return hashlib.sha256(image_bytes).hexdigest()


def _struct_id_cache_get(key: str):
    return _STRUCT_ID_CACHE.get(key)


def _struct_id_cache_put(key: str, token: str) -> None:
    if not token or key in _STRUCT_ID_CACHE:
        return
    if len(_STRUCT_ID_CACHE) >= _STRUCT_ID_CACHE_MAX:
        _STRUCT_ID_CACHE.pop(next(iter(_STRUCT_ID_CACHE)), None)  # evict oldest
    _STRUCT_ID_CACHE[key] = token


def _resolve_structural_capture_mode() -> str:
    """Single source of truth for STRUCTURAL_CAPTURE_MODE (kill-switch, 2026-07-07).

    Accepts only "off" | "double". Default "off" (benched: no preservation gain
    vs the 4–84s V1 latency + 2 gpt-4o calls). Any unknown/invalid value fails
    safe to "off" with one consistent warning. Used identically by /generate and
    /refine so the two endpoints can never diverge on interpretation.
    """
    raw = os.environ.get("STRUCTURAL_CAPTURE_MODE", "off").strip().lower()
    if raw not in ("off", "double"):
        log.warning(
            "[StructCapMode] unknown STRUCTURAL_CAPTURE_MODE=%r → fail-safe 'off'", raw
        )
        return "off"
    return raw


# ── #4 — /generate idempotency (defence-in-depth against duplicate generations)
# In-memory, per-process, keyed by user:client_request_id (only when the client
# supplied an idempotency key). Two jobs:
#   • a same-key REPLAY that arrives AFTER the first finished → return the cached
#     success payload (no 2nd OpenAI call);
#   • a same-key CONCURRENT duplicate → wait a BOUNDED time for the first to
#     populate the cache, then return it; if it doesn't appear in time, proceed
#     (worst case = today's behaviour — never a hang).
# Safety: request_ids are unique per request, so a stale in-flight entry can
# never false-match a DIFFERENT request → no error-path cleanup needed on the
# many raise sites. Failures are NEVER cached (only the success return writes).
# Flag AYDEN_IDEMPOTENCY (default on); =0 disables entirely.
_IDEM_TTL_S = 300.0  # replay window, measured from SUCCESS (_idem_put at completion). 300s comfortably exceeds the worst-case gen (~180s Dio timeout) + a realistic accidental-refire delay, while memory stays bounded by _IDEM_MAX. Does not affect an intentional regenerate (new attempt → new key).
_IDEM_MAX = 256
_idem_results: "dict[str, tuple[float, dict]]" = {}
_idem_inflight: "set[str]" = set()

# ── TEMP INSTRUMENTATION (2026-06-26) — REMOVE after diagnosis. ────────────────
# Goal: PROVE whether one logical generation can execute openai.images.edit()
# more than once (the 14¢ double-charge question). Pure logging + counters; NO
# behaviour change. Keyed by the logical generation (session:iteration:attempt);
# stores the call count + every distinct request_id that reached the image call
# for that logical gen. Unbounded over process lifetime (acceptable — temporary).
_OPENAI_CALL_LOG: "dict[str, dict]" = {}


def _idem_enabled() -> bool:
    return os.environ.get("AYDEN_IDEMPOTENCY", "1") != "0"


def _idem_get(key: str):
    hit = _idem_results.get(key)
    if hit is None:
        return None
    if time.monotonic() - hit[0] > _IDEM_TTL_S:
        _idem_results.pop(key, None)
        return None
    return hit[1]


def _idem_put(key: str, payload: dict) -> None:
    # opportunistic purge of expired entries + bound the dict size
    now = time.monotonic()
    if len(_idem_results) >= _IDEM_MAX:
        for k in [k for k, v in _idem_results.items() if now - v[0] > _IDEM_TTL_S]:
            _idem_results.pop(k, None)
        if len(_idem_results) >= _IDEM_MAX:
            _idem_results.pop(next(iter(_idem_results)), None)
    _idem_results[key] = (now, payload)
    _idem_inflight.discard(key)


# ── #8 — Ayden Decide exterior support ────────────────────────────────────────
# Interiors render great lean (no room block → atmosphere DNA + gpt-image-1 reads
# the room from the photo). Exteriors broke: the interior-centric atmosphere DNA
# was applied to a garden → incoherent. One tiny gpt-4o-mini call detects
# interior vs exterior (+ which exterior); if exterior, the caller sets room_type
# so the proper exterior room DNA is injected. Returns a canonical exterior room
# id, or "" for interior/unknown (→ keep the lean interior path unchanged).
_EXTERIOR_ROOMS = {"garden", "terrace", "facade", "balcony", "pool_area", "driveway"}


async def _classify_exterior_room(image_bytes: bytes) -> str:
    try:
        b64 = base64.b64encode(image_bytes).decode()
        resp = await openai.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{
                "role": "user",
                "content": [
                    {"type": "image_url",
                     "image_url": {
                         "url": f"data:image/jpeg;base64,{b64}",
                         "detail": "low",  # coarse classification — cheap + fast
                     }},
                    {"type": "text", "text": (
                        "Is this photo an INTERIOR room or an EXTERIOR / outdoor "
                        "space? If exterior, pick the closest type. Reply with "
                        "EXACTLY one lowercase word, no punctuation, from: "
                        "interior, garden, terrace, pool_area, facade, driveway, "
                        "balcony."
                    )},
                ],
            }],
            max_tokens=4,
        )
        ans = (resp.choices[0].message.content or "").strip().lower().replace(" ", "_")
        return ans if ans in _EXTERIOR_ROOMS else ""
    except Exception as exc:
        log.warning("  [AydenDecideExterior] classify failed (non-fatal): %s: %s",
                    type(exc).__name__, exc)
        return ""


# ── Ayden Decide STAGE MODE — interior room classification (Option B) ──────────
# Flag AYDEN_DECIDE_FURNISH (default off). Decision (2026-06-21): on Ayden Decide,
# ALWAYS re-imagine the interior as a fully furnished room — no empty-vs-furnished
# gate (that detection was the fragile link). We only need the room TYPE so the
# right staging items are used; "" for exterior/unclear → no staging.
_INTERIOR_ROOMS = {
    "living_room", "bedroom", "kitchen", "dining_room", "office", "bathroom",
    "entrance", "hallway",
}
# The 5 MVP atmospheres image-driven Surprise Me may recommend.
_MVP_ATMOSPHERES = {
    "warm_modern", "soft_luxury", "japandi_calm", "nordic_warmth", "tropical_escape",
}


async def _classify_ayden(image_bytes: bytes) -> dict:
    """ONE gpt-4o pass for Ayden Decide: room type (drives STAGE) + the best-fit
    atmosphere with confidence + a one-phrase reason (drives image-driven Surprise
    Me). Reused by both consumers so there is a single vision call. All fields
    default empty / 'low' on any failure (callers fall back)."""
    out = {"room": "", "atmosphere": "", "confidence": "low", "reason": ""}
    # AYDEN_UNIFIED_VISION (default OFF): when ON, this SAME single vision pass also
    # classifies EXTERIOR spaces (no 2nd call, no pre-classifier). When OFF,
    # _prompt_text + _room_filter are byte-identical to the original interior-only
    # classifier (the else branch below is the verbatim original prompt).
    _unified = os.environ.get("AYDEN_UNIFIED_VISION", "0") == "1"
    _room_filter = (_INTERIOR_ROOMS | _EXTERIOR_ROOMS) if _unified else _INTERIOR_ROOMS
    if _unified:
        _prompt_text = (
            "Analyse this space (interior OR exterior). Reply with EXACTLY four "
            "fields separated by ' | ', nothing else:\n"
            "room_type | recommended_atmosphere | confidence | reason\n"
            "- room_type: classify into EXACTLY ONE canonical type. CRITICAL "
            "INTERIOR RULE: if the photo is taken from INSIDE a room (interior "
            "walls, a ceiling and an indoor floor are visible), it is an INTERIOR "
            "type EVEN IF a balcony, terrace, garden, pool or city view is visible "
            "THROUGH a window or a glass/sliding door. A visible outdoor view, "
            "skyline, natural light or large glazing is NOT evidence of an exterior "
            "room. Pick an exterior type ONLY when the camera is physically OUTSIDE, "
            "standing on that outdoor surface, with no interior ceiling or enclosing "
            "room around it. Interior: "
            "living_room, bedroom, kitchen, dining_room, office, bathroom, "
            "entrance, hallway, other. Exterior: terrace, balcony, garden, "
            "pool_area, facade, driveway. Never return a generic label such as "
            "'outdoor', 'exterior' or 'outside'. Prefer the MOST SPECIFIC type: "
            "pool_area over garden if a pool dominates; balcony over terrace if "
            "elevated and railing-bound; terrace over garden if it is a paved "
            "usable outdoor living surface; facade if the building front elevation "
            "dominates; driveway if vehicle access or paved parking dominates; for "
            "an entry / door approach choose facade, driveway or terrace by the "
            "dominant content.\n"
            "- recommended_atmosphere: the ONE best-fitting from: "
            "warm_modern (warm walnut/caramel, cosy residential), "
            "soft_luxury (marble/brass/velvet, elegant — fits high "
            "ceilings, large or refined spaces), japandi_calm (pale "
            "wood, minimal, zen — fits simple, bright, uncluttered "
            "spaces), nordic_warmth (pale wood, cosy hygge, light), "
            "tropical_escape (rattan/teak/greenery — fits garden views "
            "or lush, bright spaces). Choose by architecture, light, "
            "materials, view and mood — NOT a default.\n"
            "- confidence: high, medium or low.\n"
            "- reason: a short phrase (max ~8 words).\n"
            "Example: terrace | tropical_escape | high | paved outdoor "
            "living area with greenery"
        )
    else:
        _prompt_text = (
            "Analyse this interior. Reply with EXACTLY four fields "
            "separated by ' | ', nothing else:\n"
            "room_type | recommended_atmosphere | confidence | reason\n"
            "- room_type: one of living_room, bedroom, kitchen, "
            "dining_room, office, bathroom, entrance, hallway, other.\n"
            "- recommended_atmosphere: the ONE best-fitting from: "
            "warm_modern (warm walnut/caramel, cosy residential), "
            "soft_luxury (marble/brass/velvet, elegant — fits high "
            "ceilings, large or refined spaces), japandi_calm (pale "
            "wood, minimal, zen — fits simple, bright, uncluttered "
            "spaces), nordic_warmth (pale wood, cosy hygge, light), "
            "tropical_escape (rattan/teak/greenery — fits garden views "
            "or lush, bright spaces). Choose by architecture, light, "
            "materials, view and mood — NOT a default.\n"
            "- confidence: high, medium or low.\n"
            "- reason: a short phrase (max ~8 words).\n"
            "Example: living_room | soft_luxury | high | high ceilings, "
            "large, elegant proportions"
        )
    try:
        b64 = base64.b64encode(image_bytes).decode()
        # Déterminisme (RCA 2026-07-08) : _classify_ayden était le SEUL appel vision
        # NON couvert par VISION_DETERMINISTIC → le room_type variait d'un run à
        # l'autre sur une image limite (prouvé : mêmes bytes → living_room 5/6,
        # balcony 1/6). On pinne temperature=0 + seed pour que la MÊME photo donne
        # le MÊME room à chaque fois (temp=0 = argmax = le mode observé).
        _vd = os.environ.get("VISION_DETERMINISTIC", "1") != "0"
        _det_kw = {"temperature": 0, "seed": 42} if _vd else {}
        resp = await openai.chat.completions.create(
            model="gpt-4o",
            messages=[{
                "role": "user",
                "content": [
                    {"type": "image_url",
                     "image_url": {
                         "url": f"data:image/jpeg;base64,{b64}",
                         "detail": "low",
                     }},
                    {"type": "text", "text": _prompt_text},
                ],
            }],
            max_tokens=40,
            **_det_kw,
        )
        raw = (resp.choices[0].message.content or "").strip()
        parts = [p.strip().lower() for p in raw.split("|")]
        if len(parts) >= 1:
            r = parts[0].replace(" ", "_")
            out["room"] = r if r in _room_filter else ""
        if len(parts) >= 2:
            a = parts[1].replace(" ", "_")
            out["atmosphere"] = a if a in _MVP_ATMOSPHERES else ""
        if len(parts) >= 3:
            out["confidence"] = parts[2] if parts[2] in ("high", "medium", "low") else "low"
        if len(parts) >= 4:
            out["reason"] = parts[3][:60]
        log.info("  [AydenVision] raw=%r → %r", raw, out)
        log.info("  [AydenVision] classifier=%s  room=%s  atmosphere=%s  confidence=%s",
                 "unified" if _unified else "legacy",
                 out["room"] or "(none)", out["atmosphere"] or "(none)", out["confidence"])
        log.info("  [AydenVision] model=gpt-4o  temperature=%s  seed=%s  prompt_hash=%s  image_sha256=%s",
                 "0" if _vd else "default", "42" if _vd else "none",
                 hashlib.sha1(_prompt_text.encode()).hexdigest()[:12],
                 hashlib.sha256(image_bytes).hexdigest()[:16])
    except Exception as exc:
        log.warning("  [AydenVision] classify failed (non-fatal): %s: %s",
                    type(exc).__name__, exc)
    return out


def resolve_stage_exterior(ayden_room, ayden_conf, kw_room, kw_conf, exterior_rooms):
    """Safety gate (RCA 2026-07-08). PURE. Une pièce intérieure mal lue (pièce vide,
    vue à travers une baie) peut être classée EXTÉRIEUR → un STAGE extérieur
    DESTRUCTEUR sur un intérieur. On rejette un extérieur NON corroboré et on
    retombe en intérieur quand :
      • le classifieur keyword (indépendant, issu de vision_analysis) voit un
        INTÉRIEUR avec assez de confiance (indice indoor fort) → on prend cet
        intérieur ; OU
      • la confiance Ayden est 'low' (incertain) → fallback living_room.
    Les vrais extérieurs (confiance high/medium, aucun signal indoor keyword) passent
    INCHANGÉS → on NE casse PAS les vrais balcons/terrasses/façades. Un room non
    extérieur passe tel quel. Retourne (room_effectif, raison|None)."""
    if ayden_room not in exterior_rooms:
        return ayden_room, None
    kw_indoor = bool(kw_room and kw_room not in exterior_rooms and (kw_conf or 0.0) >= 0.6)
    if kw_indoor:
        return kw_room, (f"exterior '{ayden_room}' overridden by confident indoor "
                         f"keyword '{kw_room}' (conf={kw_conf:.2f})")
    if ayden_conf == "low":
        return "living_room", f"low-confidence exterior '{ayden_room}' → interior fallback"
    return ayden_room, None


# SPECIFIC_ROOM_STAGE — interior rooms allowed to reuse the STAGE contract on a
# Specific (explicit-room) V1. Whitelist = the interior keys of
# preservation._STAGE_ITEMS. Exterior rooms are NOT in this frozenset; they are
# routed to STAGE via preservation.is_exterior_stage_room (membership in the
# exterior tables — pool_area/terrace/garden/balcony/facade/driveway), so a manual
# exterior selection stages the same way Ayden Decide does (parity, no preserve cell).
_SPECIFIC_STAGE_ROOMS = frozenset({
    "living_room", "bedroom", "dining_room", "office",
    "entrance", "hallway", "kitchen", "bathroom",
})
# Form display labels that don't normalise directly to a _STAGE_ITEMS / exterior key.
# CONFIRMED real labels only (frontend en.dart) — no speculative entries.
#   "Master Bedroom" → master_bedroom ; "Home Office" → home_office ;
#   "Entrance Hall" → entrance_hall ; "House Facade" → house_facade → facade
_SPECIFIC_STAGE_MAP = {
    "master_bedroom": "bedroom",
    "home_office": "office",
    "entrance_hall": "entrance",
    "house_facade": "facade",   # frontend EN label "House Facade" → exterior STAGE key
}


async def _localize_chip_list(chips, ui_locale):
    """Phase 5b — localize AI suggestion chips to the UI locale (FR/KM).

    Chips are curated English strings (suggestion_engine); route them through the
    same localize_reply seam (cached per (lang, text)). EN / flag-off -> list
    returned UNCHANGED (no API call). Chat/generate response only — never the
    image prompt. A tapped FR chip re-normalizes to EN on the way back, so intent
    routing is unaffected.
    """
    if not chips or not _norm_enabled():
        return chips
    return [await localize_reply(openai, c, ui_locale, enabled=True) for c in chips]


async def _suggest_localized(ui_locale, **kw):
    return await _localize_chip_list(get_suggestion_chips(**kw), ui_locale)


async def _contextual_localized(ui_locale, **kw):
    return await _localize_chip_list(get_contextual_chips(**kw), ui_locale)
from prompt_engine.intent_classifier import (
    ConversationIntent,
    SubIntent,
    is_confirmation,
    resolve_confirmation,
    # Wave 4.11d — Generation Intent Dominance
    detect_generation_demand,
    is_clarification_answer,
    IntentClassification,
)
from prompt_engine.edit_intent import EditMode
from prompt_engine.preservation import HIGH_FIDELITY_ATMOSPHERES, apply_stage_mode, is_exterior_stage_room  # PHASE 1.2 — shared with composer's contract-light decision (single source of truth); apply_stage_mode — Ayden Decide empty-room staging; is_exterior_stage_room — exterior STAGE eligibility (membership = pool_area, terrace; no env flag)
from prompt_engine.atmosphere_recommender import SIGNATURE_ATMOSPHERES  # Ayden Signature inspiration whitelist (auto-pick draws ONLY from validated atmospheres)
from prompt_engine.mask_generator import build_structural_mask
from prompt_engine.structural_identity import (
    ApartmentStructuralIdentity,
    EMPTY_IDENTITY,
    extract_from_description,
    from_token,
    to_token,
    render_clause,
    render_negative_anchors,
    safe_union_merge,  # Wave 5.24 — parallel structural capture union
)
from prompt_engine.refinement_authority import (
    detect_refinement,
    build_authorized_changes_clause,
    accumulate_refinements,
)
# Wave 4.11a — Architect Intelligence Upgrade
from prompt_engine.product_knowledge import (
    detect_product_help,
    get_product_answer,
)
from prompt_engine.ambiguity_detector import detect_ambiguity
from prompt_engine.trade_off_library import get_trade_off
from prompt_engine.constraint_acknowledgment import (
    should_emit_acknowledgment,
    build_acknowledgment,
)
from prompt_engine.design_alternatives import get_alternative_directions
# Wave 4.11b — Architectural memory
from prompt_engine.architectural_memory import get_memory_reference
from version_state import (
    VersionRecord,
    parse_versions,
    record_for_version,
    latest_record,
    serialize_versions,
    version_to_dict,
    resolve_source,
    new_version_id,
    build_source_continuity_clause,
)

from generation_profiles import get_active_profile, list_profiles
from retry_classifier import classify_for_retry, RetryVerdict
from push_service import send_push  # Phase B — FCM push on completion

# Phase B — keep a strong ref to fire-and-forget push tasks. asyncio.create_task
# only holds a WEAK reference, so without this the task can be garbage-collected
# before it runs (the push would silently never fire). Discarded on completion.
_push_bg_tasks: set = set()
from performance_observer import estimate_payload_bytes, estimate_cost_usd, PipelineTimer

# override=True: .env is the single source of truth for runtime config.
# Without override, python-dotenv keeps any APP_ENV already present in the
# process environment (inherited from a parent shell or a long-lived uvicorn
# --reload supervisor that started while .env still said prod). That silently
# pinned the runtime to PROD even after .env was switched to mobile_mvp_baseline.
# override=True guarantees every (re)load applies the current .env value.
#
# NOTE: load_dotenv() MUST run BEFORE the COMPOSER_VERSION gate below. The gate
# reads os.environ at module-import time; if .env is loaded after, the flag
# never takes effect from .env alone (Wave 5.3 post-mortem fix).
load_dotenv(override=True)

# ── Benched-config defaults (2026-06-19) ─────────────────────────────────────
# The validated "benched" flag set is ON BY DEFAULT in code, so NO environment
# (Render prod, local, CI) has to declare them — eliminating the silent
# "non-benched config" risk (a prod backend that forgot BIMODAL_ENABLED served a
# degraded prompt). This does NOT remove the flag system: an EXPLICIT "0" (or
# false/no/off) in the env still wins → the kill-switch / instant rollback is
# preserved. We run this AFTER load_dotenv(override=True) and treat a
# present-but-EMPTY value as "use the default" too (an empty .env line would
# otherwise silently disable a flag — see .env.example warning).
#
# Scope = ONLY the run.sh-validated set + MULTILINGUAL_NORMALIZE. Deliberately
# NOT defaulted on: experimental / rolled-back flags (ENABLE_STRUCTURAL_MASK is
# already handled separately; SWITCH_REDESIGN_PILOT, PRESERVE_FURNISH_SCOPE,
# COMPOSER_VERSION, the WAVE_61 / 5.14B dormant constants stay OFF).
_BENCHED_DEFAULT_ON = (
    "BIMODAL_ENABLED",
    "VISION_DETERMINISTIC",
    "PROMPT_FURNITURE_FIX",
    "PROMPT_CONTRACT_LIGHT",
    "TRUST_PIXELS_V1",          # already defaults ON at its read site; pinned here too
    "EDIT_FIDELITY_LOW",
    "LOCAL_EDIT_QUALITY_MEDIUM",
    "STYLE_REFINE_QUALITY_MEDIUM",
    "STRUCT_FIDELITY_LOW",
    "STRUCT_ID_CACHE",
    "DNA_CLEANUP_V1",           # already defaults ON at its read site; pinned here too
    "MULTILINGUAL_NORMALIZE",
    # 2026-06-25 — baked from the run.sh canonical launch so BOTH prod (Render)
    # and any local run default these ON WITHOUT needing env vars or manual flags.
    # Explicit env still wins (so any can be flipped off if ever needed).
    "AYDEN_DECIDE_FURNISH",      # Ayden Decide STAGE room detection
    "SURPRISE_VISION",           # image-driven Surprise Me / Ayden Signature atmosphere
    "SWITCH_BLOCK_COMPACT",      # compact switch block (keeps TV/room anchor under budget)
    # 2026-06-25 — promoted to default ON (user decision after the local bench:
    # routing + interior/exterior detection validated). Single vision call;
    # AYDEN_DECIDE_EXTERIOR stays OFF (never combined). Explicit env still wins.
    "AYDEN_UNIFIED_VISION",      # unified interior + exterior room detection (1 call)
    # 2026-06-30 — PR3 Designer Voice promoted from experimental to default-ON.
    # MVP phase (frequent deploys, few users): develop on the real voice rather
    # than keep a major feature dark. The flag STAYS as a kill-switch — set
    # AYDEN_VOICE=0 in the env to fall back to the pools instantly, no Git revert.
    "AYDEN_VOICE",               # LLM Designer voice on DESIGN_ADVICE turns
)
_OFF_VALUES = {"0", "false", "no", "off"}
for _flag in _BENCHED_DEFAULT_ON:
    _cur = os.environ.get(_flag, "").strip()
    if _cur == "":
        os.environ[_flag] = "1"          # absent or empty → benched default ON
    # else: an explicit value (incl. "0"/"false") is respected verbatim.
# (observability log emitted below, once the file handler is attached)

# ── Core image model (2026-06-29) ────────────────────────────────────────────
# Migration gpt-image-1 → gpt-image-2. Benché (39 imgs, 5 atmo × 5 pièces, low +
# sonde medium) : gpt-image-2 quality=low = −84 % de coût vs gpt-image-1 medium,
# préservation et latence équivalentes ; medium (×2,7 coût) rejeté. Deux
# propriétés du modèle, gérées dans le bloc edit_kwargs de generate_design() :
#   • input_fidelity est VERROUILLÉ (l'API le rejette) → omis de chaque appel ;
#   • quality figé à "low" (la seule config benchée) sur tous les chemins.
# Constante = source unique, PAS de flag env → rollback = remettre "gpt-image-1"
# (toute la machinerie per-atmosphère quality/fidelity gpt-image-1 reste intacte,
# juste neutralisée tant que ce modèle est gpt-image-2).
IMAGE_MODEL = "gpt-image-2"

# ── Wave 5.2 — composer feature-flag dispatch ────────────────────────────────
# COMPOSER_VERSION env var selects which composer the /generate handler uses.
#   unset / "v1" (default) → frozen composer.py (rollback baseline; unchanged)
#   "v2"                   → composer_v2.py (5-section clean architecture)
# This is the ONLY freeze exception for Wave 5.2 — composer.py itself is NOT
# modified. Rollback is a single env-var flip.
_COMPOSER_V2_ACTIVE = (
    os.environ.get("COMPOSER_VERSION", "v1").lower().strip() == "v2"
)
if _COMPOSER_V2_ACTIVE:
    from prompt_engine.composer_v2 import (  # noqa: F811
        compose_generation_prompt,
        resolve_switch_strategy as _v2_resolve_switch_strategy,
        is_spatial_edit as _is_spatial_edit,
    )
    logging.getLogger("aih").info(
        "[ComposerV2] feature flag ACTIVE — using composer_v2 for /generate"
    )

# ── Feature flags ─────────────────────────────────────────────────────────────
# ENABLE_STRUCTURAL_MASK: enabled by default in Wave 4.4.0.
# Wave 4.2 failure (RemoteProtocolError) root cause identified and fixed:
#   - Old: synchronous O(w×h) Python pixel loop blocked the asyncio event loop 2-5s
#   - Fix 1: mask_generator.py rewritten with fast PIL draw + blur (C-level, ~50ms)
#   - Fix 2: mask call uses asyncio.run_in_executor (non-blocking)
# Set ENABLE_STRUCTURAL_MASK=false in .env to disable for debugging.
ENABLE_STRUCTURAL_MASK: bool = os.environ.get("ENABLE_STRUCTURAL_MASK", "true").lower() == "true"

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%H:%M:%S",
)
# Wave 5.13c perf diag — mirror everything to a log file so latency
# analysis is possible without a visible uvicorn terminal. Append mode
# (one continuous file across reloads); rotation deferred — file stays
# small in normal use and is meant for short diagnostic sessions only.
_log_path = os.path.join(os.path.dirname(__file__), "logs", "backend.log")
os.makedirs(os.path.dirname(_log_path), exist_ok=True)
_file_handler = logging.FileHandler(_log_path, mode="a", encoding="utf-8")
_file_handler.setFormatter(
    logging.Formatter("%(asctime)s  %(levelname)-8s  %(message)s", datefmt="%H:%M:%S")
)
logging.getLogger().addHandler(_file_handler)
log = logging.getLogger("aih")
log.info("[PerfDiag] file logging active -> %s", _log_path)
log.info(
    "[Flags] benched defaults applied (explicit env still wins): %s",
    {f: os.environ.get(f) for f in _BENCHED_DEFAULT_ON},
)

# ── AYDEN_UNIFIED_VISION startup banner (logging only — makes the ACTIVE vision
# classifier obvious for the A/B benchmark; no functional change) ─────────────
_uv_on = os.environ.get("AYDEN_UNIFIED_VISION", "0") == "1"
# Legacy 2-call exterior detection is mutually exclusive with the unified vision
# (the unified 1-call path already classifies interior + exterior). Force it OFF
# whenever unified vision is on, regardless of the env — this neutralises a stale
# AYDEN_DECIDE_EXTERIOR=1 left in the Render dashboard (kills the redundant 2nd
# GPT call). _de_on is the single source of truth for banner + routing below.
_de_on = os.environ.get("AYDEN_DECIDE_EXTERIOR", "0") == "1" and not _uv_on
if _uv_on:
    _uv_cands = "\n".join(
        f"- {r}" for r in (sorted(_INTERIOR_ROOMS) + sorted(_EXTERIOR_ROOMS))
    )
    log.info(
        "\n==================================================\n"
        "AYDEN_UNIFIED_VISION : ENABLED\n\n"
        "Vision classifier:\n"
        "- Single GPT call\n"
        "- Interior + Exterior unified classification\n\n"
        "Candidates:\n%s\n\n"
        "AYDEN_DECIDE_EXTERIOR : %s\n"
        "==================================================",
        _uv_cands,
        "ENABLED  !! WARNING: legacy 2-call path — must be 0" if _de_on else "DISABLED",
    )
else:
    log.info(
        "\n==================================================\n"
        "AYDEN_UNIFIED_VISION : DISABLED\n"
        "Using legacy interior-only classifier.\n"
        "==================================================",
    )

# Emit active profile at import time so the running mode is visible immediately.
_startup_profile = get_active_profile()
log.info(
    "[GenerationProfile] ACTIVE: %s  quality=%s  input_fidelity=%s  "
    "size=%s  max_attempts=%d  compact_prompts=%s  "
    "(APP_ENV=%r, available: %s)",
    _startup_profile.name,
    _startup_profile.quality,
    _startup_profile.input_fidelity,
    _startup_profile.size_override or "auto",
    _startup_profile.max_attempts,
    _startup_profile.compact_prompts,
    os.environ.get("APP_ENV", "unset"),
    list_profiles(),
)

# Sprint 1 — monetization config visibility. Logs PRESENCE only (booleans), never
# the secret values, so a missing key is obvious at boot without any leak.
log.info(
    "[Monetization] config - REVENUECAT_WEBHOOK_AUTH=%s  REVENUECAT_SECRET_API_KEY=%s",
    "set" if os.environ.get("REVENUECAT_WEBHOOK_AUTH") else "MISSING",
    "set" if os.environ.get("REVENUECAT_SECRET_API_KEY") else "MISSING",
)
if not os.environ.get("REVENUECAT_WEBHOOK_AUTH"):
    log.warning(
        "[Monetization] REVENUECAT_WEBHOOK_AUTH is MISSING - /webhooks/revenuecat "
        "will reject all events; premium purchases will NOT propagate to user_roles."
    )

# Wave 4.7.9 — Functional Layout Intelligence observability (Task 8).
# Folded into the compact realism block, length-neutral. budget_safe asserts
# the block did not grow beyond Soft Luxury V1's 6-char headroom.
from prompt_engine.realism_layer import build_compact_realism_block as _bcr
_FUNC_REALISM_PREV_CHARS = 133  # pre-4.7.9 compact realism length
_func_realism_now = len(_bcr())
log.info(
    "[FunctionalLayout] functional_realism_enabled=%s  realism_chars_before=%d  "
    "realism_chars_after=%d  budget_safe=%s",
    ("camera-staged" in _bcr()),
    _FUNC_REALISM_PREV_CHARS, _func_realism_now,
    (_func_realism_now <= _FUNC_REALISM_PREV_CHARS + 6),
)


class GenerationError(Exception):
    """Structured generation failure returned to Flutter as JSON."""
    def __init__(
        self,
        error_code: str,
        user_message: str,
        retryable: bool,
        request_id: str = "",
        status_code: int = 500,
        # Wave 5.6b — carry the session_id so the exception handler can
        # persist the failure message to Supabase. Needed for users who
        # navigate away mid-generation: without server-side persistence
        # they'd see no error feedback on session reopen.
        session_id: str = "",
    ):
        self.error_code = error_code
        self.user_message = user_message
        self.retryable = retryable
        self.request_id = request_id
        self.status_code = status_code
        self.session_id = session_id


app = FastAPI(title="AIHomeArchitect API")


@app.exception_handler(GenerationError)
async def _generation_error_handler(_req: Request, exc: GenerationError) -> JSONResponse:
    log.warning("GenerationError  code=%s  retryable=%s  request_id=%s",
                exc.error_code, exc.retryable, exc.request_id)
    # Issue 13 — un GenerationError levé APRÈS le HOLD laissait le crédit retenu.
    await _release_hold_if_pending(_req, why=f"generation_error:{exc.error_code}")
    # Wave 5.6b — best-effort server-side persistence of the failure
    # message. Mirrors the Wave 5.6 success-path persistence (frontend
    # also writes on disconnect-free path; backend write is the
    # disconnect-tolerant fallback). Skipped for session_id == "" or
    # "new" (no session row to attach to yet).
    message_persisted = False
    if exc.session_id and exc.session_id != "new":
        try:
            supa.from_("messages").insert({
                "session_id": exc.session_id,
                "role": "ai",
                "content": exc.user_message,
                "message_type": "text",
            }).execute()
            message_persisted = True
            log.info(
                "[Wave 5.6b] failure message persisted server-side  session_id=%s  code=%s",
                exc.session_id, exc.error_code,
            )
        except Exception as msg_err:
            log.warning(
                "[Wave 5.6b] server-side failure-message insert FAILED: %s: %s",
                type(msg_err).__name__, msg_err,
            )
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error_code": exc.error_code,
            "user_message": exc.user_message,
            "retryable": exc.retryable,
            "request_id": exc.request_id,
            # Wave 5.6b — same flag as success path: frontend skips its
            # own insertMessage when backend already wrote, falls back
            # to client-side write if backend failed to persist.
            "message_persisted": message_persisted,
        },
    )


# ── Issue 13 (2026-08-14) — un échec technique APRÈS le HOLD doit RELÂCHER ───
#
# LE DÉFAUT. `/generate` pose un HOLD(-1) atomique (billing.try_hold) puis
# traverse ~2000 lignes — réservation usage_log, ownership, vision, composer,
# OpenAI, post-traitement, upload — avant d'atteindre le terminal SUCCEEDED.
# Le mécanisme de libération existe déjà et est correct (`_decide` : FAILED →
# RELEASE(+1), clé idempotente `release:<intent>`), mais RIEN ne le déclenchait
# dans cette fenêtre : le seul gestionnaire applicatif était celui de
# GenerationError, qui persiste un message et ne relâche pas ; une exception
# brute partait en 500 Starlette sans rien relâcher du tout. Constaté en
# staging : deux requêtes mortes sur `usage_log` (table absente, puis violation
# de FK) ont consommé deux crédits pour ZÉRO appel OpenAI.
#
# POURQUOI PAS UN try/except AUTOUR DE LA RÉGION. Il faudrait ré-indenter ~2000
# lignes — or ce fichier porte de gros littéraux de prompt en triple guillemets,
# que la ré-indentation modifierait. Les prompts doivent rester byte-identiques.
# On marque donc l'intent sur `request.state`, qui traverse intact jusqu'aux
# gestionnaires d'exception (contrairement à un ContextVar, que le
# BaseHTTPMiddleware de Starlette ne propage pas vers l'amont).
#
# PÉRIMÈTRE. Marqué APRÈS l'octroi du hold, effacé APRÈS l'observation
# SUCCEEDED : un succès déjà commité ne peut donc pas être relâché par erreur.
# Vérifié : AUCUNE HTTPException n'est levée entre ces deux bornes, donc les
# deux gestionnaires ci-dessous couvrent toute la fenêtre.
_HOLD_STATE_ATTR = "ayden_hold_intent"


async def _release_hold_if_pending(request: Request, *, why: str) -> None:
    """Relâche le HOLD si la requête en portait un non terminalisé.

    Idempotent par construction : `observe_intent_end(FAILED)` écrit une entrée
    `release:<intent>` dans un ledger append-only avec ON CONFLICT DO NOTHING —
    un double appel ne peut pas produire un double remboursement.

    NE MASQUE JAMAIS L'ERREUR D'ORIGINE : un échec de libération est journalisé,
    jamais levé. L'appelant relève l'exception initiale.
    """
    intent_id = getattr(request.state, _HOLD_STATE_ATTR, None)
    if not intent_id:
        return
    setattr(request.state, _HOLD_STATE_ATTR, None)   # une seule tentative
    try:
        await observe_intent_end(
            intent_id, "FAILED",
            error={"error_code": "TECHNICAL_FAILURE", "reason": why}, supa=supa)
        log.info("[ISSUE13] hold released — intent=%s reason=%s", intent_id, why)
    except Exception as exc:  # noqa: BLE001 — best-effort, jamais fatal
        log.error("[ISSUE13] hold release FAILED — intent=%s reason=%s err=%s: %s",
                  intent_id, why, type(exc).__name__, str(exc)[:200])


@app.exception_handler(Exception)
async def _unhandled_error_handler(request: Request, exc: Exception):
    """Filet pour les exceptions BRUTES (postgrest, httpx, TypeError…).

    Réponse volontairement IDENTIQUE au défaut Starlette (texte brut, 500) :
    ce handler existe pour relâcher le hold, pas pour changer le contrat HTTP
    des clients existants. `Exception` seulement — KeyboardInterrupt et
    SystemExit dérivent de BaseException et ne sont donc jamais avalés.
    """
    await _release_hold_if_pending(request, why="unhandled_exception")
    log.error("[ISSUE13] unhandled %s on %s: %s",
              type(exc).__name__, request.url.path, str(exc)[:300])
    return PlainTextResponse("Internal Server Error", status_code=500)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def _server_timing_mw(request: Request, call_next):
    """PR0 (2026-07-06) — measure the FULL request wall-time (INCLUDING the auth
    Depends, which runs before the handler body, and response serialization) and
    expose it to the client via the standard `Server-Timing` header, so the app
    can reconstruct click-to-pixel without log access. Pure passthrough: the
    response is returned unchanged; a failure to add the header must NEVER affect
    the response. No behaviour change."""
    _t0 = time.monotonic()
    response = await call_next(request)
    try:
        response.headers["Server-Timing"] = f"app;dur={(time.monotonic() - _t0) * 1000.0:.0f}"
    except Exception:  # noqa: BLE001 — observability must never break a response
        pass
    return response

# Wave 5.17d — Mount the RevenueCat webhook router. The endpoint is
# POST /webhooks/revenuecat ; see revenuecat_webhook.py for the contract.
app.include_router(revenuecat_router)

# Unified Identity V1. Endpoints POST /identity/merge-ticket + /claim — ALWAYS ACTIVE
# (no feature flag). Protégés par le garde merged_closed + les contrôles métier du RPC.
app.include_router(identity_router)

# max_retries=0: disable SDK-level retries entirely.
# The OpenAI Python SDK defaults to max_retries=2 (1 initial + 2 SDK retries = 3 SDK-level
# attempts per call). With PROD max_attempts=3, that silently becomes 3 × 3 = 9 API calls
# per user request — uncontrolled cost and latency amplification.
# Our retry_classifier is the single source of retry truth.
openai = AsyncOpenAI(
    api_key=os.environ["OPENAI_API_KEY"],
    max_retries=0,
    # Wave 6.15 (2026-06-06) — cap the OpenAI call at 180s (was the SDK default
    # 600s). A real gpt-image-1 generation finishes in 30-90s (≤~90s even at
    # input_fidelity=high); a call still running at 180s is stalled OpenAI-side.
    # Failing fast surfaces the EXISTING front-end error+retry in ~3 min instead
    # of leaving the user stuck on "still working" for the full 10 min. connect
    # kept short. Revert = drop the timeout kwarg.
    timeout=httpx.Timeout(180.0, connect=5.0),
)
log.info(
    "[OpenAI Client] max_retries=%d  timeout=%s  "
    "— SDK internal retries DISABLED; backend retry_classifier is the sole retry authority. "
    "Worst-case API calls per request: max_attempts(%d) × 1 = %d",
    openai.max_retries,
    openai.timeout,
    _startup_profile.max_attempts,
    _startup_profile.max_attempts,
)
supa = create_client(
    os.environ["SUPABASE_URL"],
    os.environ["SUPABASE_SERVICE_ROLE_KEY"],
)

# ── Transport hardening (2026-07-02) — force PostgREST to HTTP/1.1 ────────────
# OBSERVED in prod: ~2-min /generate stalls, with logs "pseudo-header in trailer",
# BlockingIOError(11, 'Resource temporarily unavailable'), then a ReadTimeout ~120s
# later → the lookup "fails open" and /generate continues (the stall lands BEFORE
# the claim, in resolve_generation_access's admin/quota Supabase lookups — see the
# [ACCESS-TIMING] logs).
#   PROVEN : the errors are HTTP/2 framing corruption on the shared sync Supabase
#            client, and the default ~120s timeout is what turns it into a 2-min hang.
#   HYPOTHESIS (NOT yet proven) : the trigger is CONCURRENT access to that one
#            HTTP/2 connection from many threads (every supa call runs in
#            asyncio.to_thread ; getLatestIntent polling + reconcile worker + billing
#            reprojections + claim/observe hooks now overlap). A single stale/expired
#            keep-alive could produce the SAME symptom — not disambiguated yet.
# This change is valid EITHER WAY : HTTP/1.1 uses a thread-safe connection POOL (each
# concurrent request its own connection → kills the whole h2-corruption class), and
# the 15s timeout means any stale connection fails fast instead of hanging ~2 min.
# The [ACCESS-TIMING] instrumentation will CONFIRM or REFUTE the mechanism: if stalls
# vanish and per-call timings stay low, the transport was responsible.
# We REPLACE the session post-construction (copying base_url + the apikey/auth
# headers supabase-py already built); injecting a bare httpx_client drops auth.
# Verified against supabase-py 2.31.0 / httpx 0.28.1. Defensive: never bricks boot.
try:
    _pg_session = supa.postgrest.session
    supa.postgrest.session = httpx.Client(
        base_url=_pg_session.base_url,
        headers=_pg_session.headers,          # apikey + authorization + x-client-info
        timeout=httpx.Timeout(15.0, connect=5.0),
        follow_redirects=True,
        http2=False,                          # HTTP/1.1 pool → concurrency-safe
    )
    log.info("[Supabase] PostgREST session → HTTP/1.1 (concurrency-safe pool, timeout=15s)")
except Exception as _supa_h1_exc:  # noqa: BLE001 — must never block startup
    log.warning("[Supabase] could not switch PostgREST to HTTP/1.1 (%s: %s) — default kept",
                type(_supa_h1_exc).__name__, _supa_h1_exc)


# ── Wave 5.17a — session ownership validation ───────────────────────────────

# Sentinel for the chat-screen pattern where the very first request uses
# session_id "new" before any row has been persisted. The chat screen
# later replaces this with a real UUID once the project lands in the
# sessions table. We allow these through unconditionally — the JWT-
# verified user_id will be attached to the new row when persistence
# happens, and any subsequent /generate against a real UUID will be
# validated normally.
_NEW_SESSION_SENTINELS = {"new", ""}


async def _validate_session_ownership(
    *, session_id: str, user_id: str
) -> bool:
    """
    Wave 5.17a — verify the authenticated user owns `session_id`.

    Returns True iff:
      - session_id is a "new" sentinel (no row exists yet, ownership
        is established at insert time — handled by the frontend's
        supabase client which writes user_id from auth.uid()), OR
      - The sessions row exists AND sessions.user_id == user_id.

    Returns False iff:
      - The sessions row exists AND sessions.user_id != user_id (a
        third party trying to drive cost against someone else's
        session — refuse before the OpenAI call).

    On unexpected errors (network, supabase down) we ALLOW the request
    through. The historical behaviour was no-ownership-check at all ;
    failing closed here would create a hard outage for every user the
    moment supabase has a hiccup. Better to log + continue than to
    take the whole product down for a defensive check.
    """
    if (session_id or "").strip().lower() in _NEW_SESSION_SENTINELS:
        return True

    try:
        # Use the service-role supabase client so we can read any session
        # regardless of RLS. The point is to ENFORCE ownership at the
        # backend layer ; the RLS policy on `sessions` is a second line
        # of defence for direct DB access, not a substitute.
        result = await asyncio.to_thread(
            lambda: supa.table("sessions")
            .select("user_id")
            .eq("id", session_id)
            .limit(1)
            .execute()
        )
        rows = getattr(result, "data", None) or []
        if not rows:
            # Row not yet in the table — treat as "new" : either the
            # frontend hasn't persisted it yet, or this is a stale
            # session_id. Allow the call ; if the frontend later
            # creates the row, it does so under the authenticated user.
            return True
        owner_id = rows[0].get("user_id")
        if not owner_id:
            # Row exists but has no owner — unusual but not a refusal
            # case ; the next sessions write will attach the current user.
            return True
        return str(owner_id) == str(user_id)
    except Exception as exc:
        log.warning(
            "[Wave 5.17a] session ownership check failed open — "
            "session=%s user=%s error=%s",
            session_id, user_id, exc,
        )
        return True


# ── Image utilities ───────────────────────────────────────────────────────────

def _detect_output_size(image_bytes: bytes) -> str:
    """
    Detect source image orientation and return the matching gpt-image-1 output size.

    Landscape (w > h) → 1536x1024
    Portrait  (h > w) → 1024x1536
    Square           → 1024x1024

    Preserving the source aspect ratio is critical: forcing 1024x1024 on a
    landscape room physically destroys room proportions before the model even
    edits the image.
    """
    try:
        with PilImage.open(io.BytesIO(image_bytes)) as img:
            w, h = img.size
        if w > h:
            return "1536x1024"
        if h > w:
            return "1024x1536"
        return "1024x1024"
    except Exception:
        return "1024x1024"  # safe fallback


async def _capture_structural_text(image_bytes: bytes) -> str:
    """
    Wave 4.7.2 — ONE-TIME structural capture (provider boundary).

    Returns a short, architecture-ONLY sentence describing the apartment's
    structural identity. Its output is fed through the deterministic,
    provider-agnostic parser (structural_identity.extract_from_description),
    so this function is the ONLY provider-coupled point and is trivially
    swappable. NON-FATAL: returns "" on any failure (graceful fallback).

    GATING (enforced by the caller): this runs at most ONCE per session —
    only at V1 (iteration == 1) when the client has no persisted identity
    token. It is NOT per-generation vision analysis; V2/V3/V4 reuse the
    persisted token and never call this.

    Wave 5.5.11 (Structured V1 Capture Stabilization, 2026-05-22):
    benchmarks after the frontend round-trip fixes (struct_identity +
    versions + history) revealed that V2/V3/V4 quality directly tracks
    V1 capture density. With the legacy short prompt ("Max 35 words",
    max_tokens=90), the mini stochastically produced facts=3 OR facts=5
    on the same photo — and a poor V1 capture poisoned the whole session
    via byte-identity token round-trip. Fix: a numbered 5-bullet
    checklist scoped to the EXACT 5 dataclass fields (dominant opening,
    glass partition, spatial depth, kitchen visibility, secondary
    opening), max_tokens raised 90→150 to give room for coverage.

    Wave 5.13g (Structural Identity Reliability, 2026-05-27): bench
    showed WM + Nature Retreat sessions captured the apartment with
    facts=3 (missing dominant_opening), while other 5 sessions captured
    facts=4 on the SAME photo. Root cause confirmed by precedent memory
    [mini_door_classification_resistance]: gpt-4o-mini is empirically
    unreliable on opening classification. Fix: model upgrade
    gpt-4o-mini → gpt-4o + detail "low" → "high". Cost delta ~$0.0025
    per session (V1 only — captured once, reused via token forever) =
    ~3% of one gpt-image-1 generation. Latency +0.5–2s once per session.
    Aligns with Wave 5.13f principle "fewer but stronger" — single point
    upgrade, no fallback heuristic, no retry logic. Rollback = revert
    model + detail.
    """
    try:
        b64 = base64.b64encode(image_bytes).decode()
        resp = await openai.chat.completions.create(
            model="gpt-4o",
            messages=[{
                "role": "user",
                "content": [
                    {"type": "image_url",
                     "image_url": {"url": f"data:image/jpeg;base64,{b64}", "detail": "high"}},
                    {"type": "text", "text": (
                        # ── Wave 5.19 (2026-06-01) — Structural Capture Enrichment ─────
                        # Expands the prompt from 5 buckets to 11 buckets, covering
                        # interior doors, fixed built-ins, vertical circulation,
                        # ceiling signature, surface transitions, and fixed wall
                        # fixtures. Audit (cf. wave_5_19 memory) confirmed the
                        # original 5-bucket prompt was systematically blind to
                        # non-glass architectural features (notably wooden doors),
                        # yielding facts=1 on simple rooms where 3-4 facts were
                        # visually present.
                        #
                        # The downstream parser in structural_identity.extract_
                        # from_description() matches the EXACT vocabulary listed
                        # below for each bucket — outputs that deviate are
                        # filtered silently (hallucination guard).
                        "Analyze this room photograph for architectural identity. "
                        "List each architectural fact VISIBLY PRESENT in the photo; "
                        "skip cleanly if absent. Use the EXACT vocabulary listed "
                        "for each bucket — the downstream parser depends on it. "
                        "NEVER infer, NEVER invent — only what is visually "
                        "verifiable in the photograph counts.\n"
                        "\n"
                        "OPENINGS:\n"
                        "(1) Dominant opening — pick the best match: "
                        "'floor-to-ceiling window', 'bay window', 'panoramic "
                        "window', 'corner window', 'glazed wall', 'glazed facade', "
                        "'sliding glass door', 'patio door', 'french door', "
                        "'pivot door', 'bi-fold door', or 'picture window'. Add a "
                        "size qualifier ('wide', 'tall', 'full-height', 'dominant') "
                        "and state the wall (left/right/back).\n"
                        "(2) Secondary opening — if visible, state 'pair of "
                        "windows', 'additional windows on the same facade', or "
                        "'second door' with position.\n"
                        "\n"
                        "PARTITIONS & WALL FEATURES:\n"
                        "(3) Glass partition — if visible, say 'glass partition' "
                        "with frame colour ('black-framed' etc.) and position.\n"
                        "(4) Interior door — if a wooden or painted (NON-GLASS) "
                        "door is visible, say EXACTLY 'wooden door' or 'painted "
                        "door' visible on the (upper-)left/right/back wall. If "
                        "multiple, say 'two interior doors' with position. Skip "
                        "if no such door is visible.\n"
                        "(5) Fixed built-in — if visible, say one of: 'fireplace', "
                        "'alcove', 'niche', 'recessed shelving', 'bookshelf', "
                        "'floating cabinetry', 'kitchen island', 'mantel', "
                        "'hearth'. State position. Skip decorative objects.\n"
                        "\n"
                        "CIRCULATION:\n"
                        "(6) Vertical circulation — if visible, say one of: 'open "
                        "staircase', 'spiral stair', 'floating stair', 'staircase', "
                        "'mezzanine', 'loft level', 'gallery floor'. State "
                        "position.\n"
                        "\n"
                        "SPATIAL:\n"
                        "(7) Spatial depth — say 'open-plan' if the layout is "
                        "open, otherwise describe depth (e.g. 'diagonal depth "
                        "toward rear space', 'enclosed space').\n"
                        "(8) Visible kitchen — even if only partially visible at "
                        "the image edge, say EXACTLY 'open kitchen visible on the "
                        "left' OR 'open kitchen visible on the right' (verbatim).\n"
                        "\n"
                        "BOUNDING SURFACES:\n"
                        "(9) Ceiling signature — if visually distinctive, say one "
                        "of: 'exposed beam' (with wood/timber/steel material if "
                        "visible), 'vaulted ceiling', 'cathedral ceiling', "
                        "'raised ceiling section', 'lowered ceiling section'. "
                        "Skip if the ceiling is flat and unremarkable.\n"
                        "(10) Surface transition — only if prominent, say one of: "
                        "'raised step into the rear zone', 'floor level change', "
                        "'step up to the kitchen', 'split level', 'threshold at "
                        "the kitchen'. Skip subtle transitions.\n"
                        "\n"
                        "FIXED FIXTURES:\n"
                        "(11) Fixed appliance — only when VISUALLY PROMINENT, say "
                        "one of: 'wall-mounted AC unit' (with position), "
                        "'vertical radiator', 'wall heater'. Skip small details "
                        "and any portable items.\n"
                        "\n"
                        "CRITICAL RULES:\n"
                        "- Architecture ONLY. NO furniture, NO decor, NO style, "
                        "NO atmosphere, NO subjective adjectives.\n"
                        "- Skip cleanly any fact NOT VISUALLY PRESENT.\n"
                        "- Use EXACT vocabulary per bucket. Outputs deviating from "
                        "the vocabulary are silently dropped by the parser.\n"
                        "- Max 120 words total."
                    )},
                ],
            }],
            # Wave 5.19 — bumped 150 → 200 to accommodate the expanded
            # 11-bucket output (up to ~120 words ≈ 180 tokens).
            max_tokens=200,
            # PHASE 0.1 (post-build, 2026-06-13) — VISION_DETERMINISTIC.
            # The default gpt-4o temperature (1.0) made this capture stochastic:
            # the SAME apartment yielded 6 different structural tokens across a
            # 6-atmosphere bench (facts=3 vs 5; secondary door / glass partition
            # / ceiling section captured at random). That token is the lineage's
            # structural guard (inherited by every switch), so a missed feature
            # is unprotected for the whole session — pure luck of the read.
            # temperature=0 (+ seed) makes the read repeatable. Flagged for A/B:
            # set VISION_DETERMINISTIC=0 to restore the stochastic baseline.
            # Rollback = delete the unpack below.
            **({"temperature": 0, "seed": 42}
               if os.environ.get("VISION_DETERMINISTIC", "1") != "0" else {}),
        )
        _raw = (resp.choices[0].message.content or "").strip()
        # Wave 5.13g+ debug — log raw gpt-4o output so we can audit which
        # facts the model returned vs which ones the deterministic parser
        # caught. Helps decide whether to relax parser vocab or tighten the
        # capture prompt when downstream PHOTO FACTS shrink unexpectedly.
        log.info("[StructuralCapture] raw_text=%r", _raw)
        return _raw
    except Exception as exc:  # non-fatal: identity simply stays absent
        log.warning("  structural capture failed (non-fatal): %s: %s",
                    type(exc).__name__, exc)
        return ""


# ── Wave 5.23 — Mini Orientation Consensus (2026-06-03) ──────────────────────
#
# Targeted stabilization for the dominant_opening wall position.
# Empirical evidence : gpt-4o vision capture stochastically flips LEFT/RIGHT/
# BACK on the same source photo across separate sessions (12.5% on WM, 50% on
# SL bench 2026-06-03). When the flipped position reaches the gpt-image-1
# prompt, the model resolves the prompt-vs-photo contradiction by inventing
# walls.
#
# Approach (user-recommended over best-of-N full capture) : keep the existing
# 1× full structural capture unchanged ; add 2× tiny parallel classification
# calls that ONLY answer LEFT/RIGHT/BACK/UNKNOWN for the dominant opening.
# Apply consensus voting :
#
#   • A == B and explicit  → use the consensus position (patch full capture
#     if it disagrees)
#   • A or B is UNKNOWN    → prefer the explicit one
#   • A != B (both explicit) → OMIT position from final identity (safer than
#     wrong direction)
#   • Both UNKNOWN          → OMIT position
#
# Cost : 2× gpt-4o-mini classification calls @ ~$0.00002 each = ~$0.00004 per
# V1 (negligible). Latency : run parallel with the full capture via
# asyncio.gather → total wall-time ≈ full capture time (mini is faster).
#
# Fallback : on any mini call exception, behave as if UNKNOWN. On both-fail,
# return None → no patch → existing full capture used as-is (current
# behaviour preserved).
#
# Why gpt-4o-mini and not gpt-4o : constrained 4-class classification on a
# clear architectural feature is mini-grade. The
# mini_door_classification_resistance memory documented mini's failure on
# CATEGORY classification (window vs door) — that's a different cognitive
# task. Position classification is consistently reliable on mini.

_ORIENTATION_VALID = {"LEFT", "RIGHT", "BACK"}


async def _capture_orientation_mini(image_bytes: bytes) -> str:
    """Wave 5.23 — micro vision classification : where is the dominant
    sliding glass opening / primary window located ?

    Returns 'LEFT' | 'RIGHT' | 'BACK' | 'UNKNOWN' (or '' on exception —
    treated as UNKNOWN by the consensus logic).
    """
    try:
        b64 = base64.b64encode(image_bytes).decode()
        resp = await openai.chat.completions.create(
            model="gpt-4o-mini",
            messages=[{
                "role": "user",
                "content": [
                    {"type": "image_url",
                     "image_url": {
                         "url": f"data:image/jpeg;base64,{b64}",
                         "detail": "low",
                     }},
                    {"type": "text", "text": (
                        "Looking at this room photograph, on which wall "
                        "is the main sliding glass door, picture window, "
                        "or primary opening located, relative to the "
                        "camera viewpoint ?\n"
                        "Answer ONLY with one of these four words "
                        "(no prose, no explanation) :\n"
                        "LEFT\n"
                        "RIGHT\n"
                        "BACK\n"
                        "UNKNOWN"
                    )},
                ],
            }],
            max_tokens=4,
        )
        raw = (resp.choices[0].message.content or "").strip().upper()
        for token in ("LEFT", "RIGHT", "BACK", "UNKNOWN"):
            if token in raw:
                return token
        return "UNKNOWN"
    except Exception as exc:
        log.warning(
            "[Wave5.23] mini orientation capture failed (non-fatal): %s: %s",
            type(exc).__name__, exc,
        )
        return ""


async def _resolve_orientation_consensus(image_bytes: bytes) -> str | None:
    """Wave 5.23 — run 2× mini orientation classifications in parallel +
    apply consensus voting. Returns 'left'|'right'|'back' if a confident
    consensus is reached, None to leave the existing full-capture position
    untouched (safer-than-wrong default)."""
    a, b = await asyncio.gather(
        _capture_orientation_mini(image_bytes),
        _capture_orientation_mini(image_bytes),
    )
    a_up = (a or "").upper()
    b_up = (b or "").upper()

    # Case A — same answer twice, both explicit
    if a_up == b_up and a_up in _ORIENTATION_VALID:
        log.info(
            "[Wave5.23] mini_orientation_consensus=A:%s B:%s final:%s",
            a_up or "FAIL", b_up or "FAIL", a_up,
        )
        return a_up.lower()

    # Case B / C — one explicit, the other UNKNOWN (or empty=failed)
    if a_up in _ORIENTATION_VALID and b_up not in _ORIENTATION_VALID:
        log.info(
            "[Wave5.23] mini_orientation_consensus=A:%s B:%s final:%s "
            "(B uncertain → defer to A)",
            a_up, b_up or "FAIL", a_up,
        )
        return a_up.lower()
    if b_up in _ORIENTATION_VALID and a_up not in _ORIENTATION_VALID:
        log.info(
            "[Wave5.23] mini_orientation_consensus=A:%s B:%s final:%s "
            "(A uncertain → defer to B)",
            a_up or "FAIL", b_up, b_up,
        )
        return b_up.lower()

    # Case D — contradiction (both explicit, different) OR both
    # UNKNOWN/failed → omit (safer than wrong direction)
    log.info(
        "[Wave5.23] mini_orientation_consensus=A:%s B:%s final:OMITTED",
        a_up or "FAIL", b_up or "FAIL",
    )
    return None


def _patch_dominant_opening_position(
    identity, position: str,
):
    """Wave 5.23 — replace the wall position suffix in identity.dominant_
    opening with the mini-consensus result. Returns a new identity (the
    dataclass is frozen-by-convention ; we use dataclasses.replace)."""
    import re
    from dataclasses import replace

    current = identity.dominant_opening
    if not current:
        return identity

    # Strip any existing " on the X wall" suffix (handles Wave 5.21d output).
    stripped = re.sub(
        r"\s+on the (left|right|back|front)\s+wall$",
        "",
        current,
        flags=re.IGNORECASE,
    )
    # Append the consensus-validated position.
    patched = f"{stripped} on the {position} wall"

    if patched != current:
        log.info(
            "[Wave5.23] dominant_opening patched : '%s' → '%s'",
            current, patched,
        )

    return replace(identity, dominant_opening=patched)


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok"}


# ── Wave 5.18 — Developer Validation Mode admin flag ─────────────────────────
# Single-purpose endpoint that exposes the admin status of the authenticated
# user to the frontend. The frontend's `accessProvider` polls this on app
# start + auth state changes and combines the result with `premiumProvider`
# (RevenueCat) for UI gating :
#     hasFullAccess = isPremium || isAdmin
#
# Backend remains the single source of truth — no RevenueCat custom
# entitlement, no JWT claim, no local override. Granting admin is a manual
# INSERT in user_roles (expires_at NULL for permanent).
#
# Premium status is NOT exposed here. Premium is tracked client-side via the
# RC SDK stream so the UI updates instantly on purchase, without a backend
# round-trip. Mixing the two signals into a single endpoint would create a
# stale-window after purchase.
#
# Response shape is deliberately minimal — extending later (e.g. adding
# is_premium, role_expires_at) is non-breaking since callers parse only
# fields they need.
@app.get("/me/access")
async def get_me_access(
    current_user: CurrentUser = Depends(require_active_identity),
):
    """Return {is_admin: bool} for the authenticated user."""
    _is_admin = await is_admin_role(current_user.user_id)
    log.info("[Access] /me/access user=%s is_admin=%s", current_user.user_id, _is_admin)
    return {
        "is_admin": _is_admin,
    }


async def _read_wallet_snapshot(user_id: str) -> dict:
    """BUG4 (RC-PR2b) — snapshot READ-ONLY du wallet pour l'affichage profil.
    Le wallet est une projection (peut ne pas exister → {} → 0 crédit, pas de
    pass). Best-effort : une erreur DB ne casse jamais /me/status."""
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("wallets")
            .select("available_credits, active_pass_id, pass_expires_at")
            .eq("user_id", user_id).limit(1).execute()
        )
        rows = getattr(res, "data", None) or []
        return rows[0] if rows else {}
    except Exception as exc:  # noqa: BLE001 — l'affichage ne bloque jamais
        log.warning("[me/status] wallet snapshot failed user=%s err=%s", user_id[:8], exc)
        return {}


def _pass_still_active(expires_iso: "str | None") -> bool:
    """True si pass_expires_at est dans le futur (le wallet peut être stale : un
    premium bypasse le débit → sa projection n'est pas rafraîchie en continu)."""
    if not expires_iso:
        return False
    try:
        exp = datetime.fromisoformat(str(expires_iso).replace("Z", "+00:00"))
        if exp.tzinfo is None:
            exp = exp.replace(tzinfo=timezone.utc)
        return exp > datetime.now(timezone.utc)
    except (TypeError, ValueError):
        return False


async def _read_latest_pass_ends_at(user_id: str) -> "str | None":
    """BUG 3 (2026-07-11) — READ-ONLY : ends_at du DERNIER pass connu de l'user,
    N'IMPORTE QUEL statut/fenêtre. Non-null = un abonnement MESURÉ a déjà existé.

    La projection `billing_reproject_wallet` met `active_pass_id = NULL` dès que la
    fenêtre du pass est lapsée (renouvellement pas encore projeté) → le snapshot wallet
    ne distingue pas « abo actif dont la fenêtre a lapsé » de « rôle sans AUCUN pass ».
    Cette lecture indexée tranche : pass ayant existé → renouvellement en attente
    (0 spaces · renews, JAMAIS restore) ; aucun pass → vrai restore_required.
    Best-effort : une erreur DB ne casse jamais /me/status."""
    try:
        res = await asyncio.to_thread(
            lambda: supa.table("passes")
            .select("ends_at")
            .eq("user_id", user_id)
            .order("ends_at", desc=True)
            .limit(1).execute()
        )
        rows = getattr(res, "data", None) or []
        return rows[0].get("ends_at") if rows else None
    except Exception as exc:  # noqa: BLE001 — l'affichage ne bloque jamais
        log.warning("[me/status] latest-pass read failed user=%s err=%s", user_id[:8], exc)
        return None


def _sku_to_plan_type(sku: "str | None") -> str:
    """Premium Center (Lot 1) — mappe le sku produit → plan_type d'affichage. PURE/testable.
    INFORMATIF seulement : ne participe NI au gate NI au débit NI à la projection."""
    if sku == "weekly_pass":
        return "weekly"
    if sku == "annual_pass":
        return "annual"
    return "none"


async def _read_active_pass_product(user_id: str) -> "tuple[str, str | None]":
    """Premium Center (Lot 1) — READ-ONLY, ADDITIF : (plan_type, active_product_id) du pass
    ACTIF de l'user (embed products via la FK passes.product_id). Purement INFORMATIF pour l'UX
    (distinguer Weekly d'Annual) — n'entre NI dans reserve_decision, NI dans try_hold, NI dans la
    projection wallet. Best-effort : erreur → ('none', None).

    FIX A (2026-07-18) — ne considère QU'UN pass réellement ACTIF (status=ACTIVE ET ends_at>now).
    L'ancien code lisait le pass le PLUS RÉCENT sans filtre → un Annual EXPIRÉ remontait comme
    « produit actif » (active_product_id=annual) alors qu'aucun pass n'était actif. Aucun pass
    actif → ('none', None) : jamais un ancien produit expiré."""
    try:
        _now = datetime.now(timezone.utc).isoformat()
        res = await asyncio.to_thread(
            lambda: supa.table("passes")
            .select("ends_at, status, products(sku, apple_product_id)")
            .eq("user_id", user_id)
            .eq("status", "ACTIVE")
            .gt("ends_at", _now)
            .order("ends_at", desc=True)
            .limit(1).execute()
        )
        rows = getattr(res, "data", None) or []
        if not rows:
            return ("none", None)
        prod = rows[0].get("products") or {}
        return (_sku_to_plan_type(prod.get("sku")), prod.get("apple_product_id"))
    except Exception as exc:  # noqa: BLE001 — l'affichage ne bloque jamais
        log.warning("[me/status] pass-product read failed user=%s err=%s", user_id[:8], exc)
        return ("none", None)


def _classify_access_source(
    *, is_admin: bool, has_active_pass: bool, promo_active: bool,
    has_premium_role: bool,
) -> str:
    """VÉRITÉ de génération, PURE (testable sans DB).
    Priorité : admin > pass (mesuré) > promo > restore_required > free.

    FIX B (2026-07-18) — SUPERSEDE l'heuristique BUG 3 `ever_had_pass`. Un rôle premium
    (entitlement RC actif) SANS pass actif POSSÉDÉ ne doit PLUS être classé 'pass' au seul motif
    qu'un pass a existé : ça masquait le cas réel « le pass de l'abonnement est sur une AUTRE
    identité (RC-transféré, transaction déjà consommée) ou un webhook a été manqué » en
    « 0 spaces · renews » sans jamais proposer de restore. → 'restore_required' explicite : un
    restore/sync déclenche le reconcile (qui crée le pass si l'abo renouvelle réellement sous CE
    user, ou surface le vrai blocage). On ne déduit JAMAIS 'pass' du seul historique."""
    if is_admin:
        return "admin"
    if has_active_pass:
        return "pass"
    if promo_active:
        return "promo"
    if has_premium_role:
        return "restore_required"   # premium reconnu MAIS aucun pass actif possédé → restore réel
    return "free"


@app.get("/me/status")
async def get_me_status(
    current_user: CurrentUser = Depends(require_active_identity),
):
    """Sprint 1 — READ-ONLY premium + quota snapshot for the UI.

    The backend remains the sole authority: this endpoint only *reports* the
    server-side state (RevenueCat → user_roles → quota). The client cannot use
    it to grant itself anything.

    Returns: is_premium, is_admin, role, quota_used, quota_limit,
    remaining_free_generations (null when premium/admin = unlimited), promo fields,
    and (RC-PR2b, additif) the wallet/pass snapshot: available_credits,
    active_pass_id, pass_expires_at, has_active_pass, access_source.
    """
    # Sprint 1B — one resolution covers subscription + promo + free quota.
    d = await resolve_generation_access(current_user.user_id)
    is_admin = d.tier == "admin"
    # P0 (2026-07-10) — `is_premium` = droit aux FEATURES premium (admin ou rôle
    # premium). Ne signifie PLUS "génération illimitée" (RC-PR3b : seuls admin +
    # promo_unlimited sont illimités ; un rôle premium seul ne débloque PAS la génération).
    is_premium = d.tier in ("admin", "premium")
    _has_premium_role = d.tier == "premium"

    # ── Wallet/pass snapshot (READ-ONLY) ──
    _wallet = await _read_wallet_snapshot(current_user.user_id)
    _available_credits = int(_wallet.get("available_credits") or 0)
    _active_pass_id = _wallet.get("active_pass_id")
    _pass_expires_at = _wallet.get("pass_expires_at")
    _has_active_pass = bool(_active_pass_id) and _pass_still_active(_pass_expires_at)

    # ── P0 (2026-07-10) — SOURCE DE VÉRITÉ UNIQUE : /me/status lit EXACTEMENT le même
    # gate que /generate (billing.reserve_decision). Fin de la divergence "Premium
    # active dans le profil + génération bloquée par paywall". can_generate = la
    # décision réelle ; gate_reason = pourquoi (no_active_pass, pass_exhausted, …).
    import billing  # noqa: PLC0415
    _gate = await billing.reserve_decision(
        user_id=current_user.user_id, is_free=d.consumes_free_quota, tier=d.tier)
    _can_generate = _gate.allow
    _gate_reason = _gate.reason
    # P0 (2026-07-10) — autorité pass = le gate (lecture live), pas le snapshot wallet.
    _has_active_pass = _gate.has_active_pass

    # Seuls admin + promo_unlimited sont VRAIMENT illimités (le rôle premium ne l'est plus).
    unlimited = is_admin or d.promo_unlimited_active

    # ── P0 (2026-07-10) — SOURCE UNIQUE : buckets additifs exposés DEPUIS le gate
    #    (même calcul que le wallet). total = free + pass (+ promo, borné, séparé en V1).
    if unlimited:
        _free_credits = _pass_credits = _promo_credits = _total_credits = None
    elif d.tier == "promo_limited":
        _free_credits, _pass_credits = 0, 0
        _promo_credits = d.promo_generations_remaining
        _total_credits = d.promo_generations_remaining
    else:
        _free_credits = _gate.free_credits
        _pass_credits = _gate.pass_credits
        _promo_credits = 0
        _total_credits = _gate.total_credits

    _promo_active = d.promo_unlimited_active or d.promo_generations_remaining > 0
    # FIX B (2026-07-18) — ancre « renews » UNIQUEMENT pour un pass RÉELLEMENT actif ; jamais
    # l'ends_at d'un ancien pass expiré (l'heuristique `ever_had_pass`/`_read_latest_pass_ends_at`
    # est supprimée : elle affichait « renews » + produit périmé pour un pass en fait bloqué sur
    # une autre identité, sans jamais proposer de restore).
    _pass_renews_at = _pass_expires_at if _has_active_pass else None

    # access_source = la VÉRITÉ de génération (même autorité que le gate), PURE/testable.
    _access_source = _classify_access_source(
        is_admin=is_admin, has_active_pass=_has_active_pass, promo_active=_promo_active,
        has_premium_role=_has_premium_role,
    )
    # FIX B — état incohérent « premium reconnu MAIS aucun pass actif possédé » (pass de l'abo sur
    # une autre identité / webhook manqué) : access_source='restore_required' → needs_restore=true +
    # gate_reason EXPLICITE. On ne montre JAMAIS 'pass' + 'renews' + un produit périmé pour cet état.
    if _access_source == "restore_required":
        _gate_reason = "premium_without_owned_active_pass"
        log.info("[me/status] premium role, no OWNED active pass → restore_required gate=%s user=%s",
                 _gate_reason, current_user.user_id[:8])

    # Premium Center (Lot 1) — plan_type/active_product_id INFORMATIFS : distinguer Weekly d'Annual
    # côté UX. Lecture UNIQUEMENT pour un abonné (access_source=='pass' ⇒ pass actif, cf. FIX A) →
    # coût nul pour free/promo/admin/restore_required. N'entre dans AUCUNE décision gate/débit/proj.
    _plan_type, _active_product_id = "none", None
    if _access_source == "pass":
        _plan_type, _active_product_id = await _read_active_pass_product(current_user.user_id)

    # remaining_free_generations = bucket free du LEDGER (source unique), plus usage_log.
    _rfg = None if unlimited else (_free_credits if _free_credits is not None else 0)

    # [IDENTITY][STATUS] — corrèle l'identité serveur avec les logs frontend [IDENTITY][*] :
    # au reinstall, un free_remaining ré-ouvert à 3 pour un NOUVEAU user_id = ré-attribution du
    # trial (BUG 4). Preuve directe côté backend, keyée sur le user_id courant.
    log.info("[IDENTITY][STATUS] user=%s free_remaining=%s total_spaces=%s access_source=%s",
             current_user.user_id, _rfg, _total_credits, _access_source)

    # P0 bloc (b) — "Redesigns" = générations RÉUSSIES (V1 + refine + switch + reupload) via
    # generation_intents SUCCEEDED (exact ; le comptage de SESSIONS sous-comptait les refines).
    from intent_observer import count_succeeded_intents  # noqa: PLC0415 — lazy
    _gens_succeeded = await count_succeeded_intents(current_user.user_id)

    return {
        # `is_premium` = FEATURES premium (all rooms/atmospheres/HD/no-watermark),
        # PAS "génération illimitée". La capacité de génération = can_generate.
        "is_premium": is_premium,
        "is_admin": is_admin,
        "role": "admin" if is_admin else ("premium" if is_premium else "free"),
        "quota_used": None if unlimited else max(0, FREE_TIER_LIMIT - (_free_credits or 0)),
        "quota_limit": FREE_TIER_LIMIT,
        "remaining_free_generations": _rfg,
        # ── Sprint 1B — promo fields ──
        "promo_generations_remaining": d.promo_generations_remaining,
        "promo_unlimited_active": d.promo_unlimited_active,
        "active_promo_campaign": d.active_promo_campaign,
        "effective_access_state": d.tier if _can_generate else "blocked",
        "can_generate": _can_generate,
        "gate_reason": _gate_reason,     # "" | bypass | pass_exhausted | no_active_pass | insufficient_credits
        # ── P0 buckets (source unique, additifs) ──
        "free_credits": _free_credits,
        "pass_credits": _pass_credits,
        "promo_credits": _promo_credits,
        "total_credits": _total_credits,   # None = illimité (admin/promo_unlimited)
        # ── wallet/pass snapshot (legacy, = total_credits pour un user post-trial) ──
        "available_credits": _available_credits,
        "active_pass_id": _active_pass_id,
        "pass_expires_at": _pass_expires_at,
        # BUG 3 (2026-07-11) — ancre d'affichage « renews {date} » : expiry du pass actif,
        # ou (fenêtre lapsée) ends_at du dernier pass connu. null pour free/promo/admin.
        "pass_renews_at": _pass_renews_at,
        "has_active_pass": _has_active_pass,
        "access_source": _access_source,
        # FIX B (2026-07-18) — EXPLICITE : premium reconnu mais aucun pass actif possédé → true
        # (le frontend le dérive déjà de access_source ; on l'expose pour lever toute ambiguïté API).
        "needs_restore": _access_source == "restore_required",
        # Premium Center (Lot 1) — INFORMATIFS (UX distinguer Weekly/Annual), hors gate/débit.
        "plan_type": _plan_type,                 # "weekly" | "annual" | "none"
        "active_product_id": _active_product_id,  # ex "com.aydenstudio.app.weekly" | None

        # P0 bloc (b) — compteur "Redesigns" (générations réussies, source unique backend).
        "generations_succeeded": _gens_succeeded,
    }


@app.get("/v1/intents/latest")
async def get_latest_intent(
    session_id: str,
    current_user: CurrentUser = Depends(require_active_identity),
):
    """Generation Intent v1 — PR3 (READ-ONLY). État du dernier Intent d'une
    session, pour que le client se ré-attache à une génération en cours après
    un kill d'app (il n'a peut-être jamais reçu l'intent_id). Scopé à l'user du
    JWT. AUCUNE écriture, AUCUN claim, AUCUN /generate → ne peut pas créer de
    doublon (le claim atomique reste PR2). Fallback : {status:null} si rien.
    """
    row = await get_latest_intent_for_session(
        user_id=current_user.user_id, session_id=session_id,
    )
    if row is None:
        return {"intent_id": None, "status": None, "iteration": None,
                "has_result": False, "after_image_url": None}
    return row


@app.get("/v1/intents/by-id/{intent_id}")
async def get_intent_by_id_route(
    intent_id: str,
    current_user: CurrentUser = Depends(require_active_identity),
):
    """Generation Intent v1 — récupération UNIFIÉE par id (Phase 1). Chemin littéral
    'by-id/{id}' → JAMAIS de collision avec /v1/intents/latest. Owner check EXPLICITE
    (user_id + intent_id) : le backend est service-role, on NE se repose PAS sur la RLS.
    Renvoie {intent_id, status, iteration, has_result, result_ref} ou 404. READ-ONLY."""
    from intent_observer import get_intent_by_id  # local — évite de toucher le bloc d'import
    info = await get_intent_by_id(user_id=current_user.user_id, intent_id=intent_id)
    if info is None:
        raise HTTPException(status_code=404, detail={
            "error_code": "INTENT_NOT_FOUND",
            "user_message": "This edit could not be found.", "retryable": False})
    return info


# ── Generation Intent v1 — PR4 reconciliation (lifecycle only, no billing) ────
_reconcile_bg_tasks: set = set()


async def _reconcile_cycle():
    """Un cycle du worker : reconcile Intent/billing PUIS sweep de révocation Auth
    (Commit 3b), chacun ISOLÉ dans son propre try/except — une branche ne bloque
    JAMAIS l'autre. CancelledError se propage (arrêt propre du worker)."""
    try:
        await reconcile_once()
    except Exception as exc:  # never let billing break the cycle
        log.warning("[RECONCILE] worker cycle failed (continuing): %s", exc)
    try:
        await sweep_pending_revocations()   # no-op si IDENTITY_AUTH_REVOCATION_ENABLED=false
    except Exception as exc:  # never let revocation break the cycle
        log.warning("[REVOCATION] sweep cycle failed error=%s", type(exc).__name__)


@app.on_event("startup")
async def _start_reconciliation_worker():
    """Periodic Intent lifecycle reconciliation: repair orphans (image in DB but
    Intent still RUNNING) + timeout-fail stuck RUNNING. Best-effort, in-process;
    idempotent across instances (transitions guarded by .eq(status,'RUNNING')).
    Le même worker porte aussi le sweep de révocation (Commit 3b), isolé — aucun
    second worker. Démarrage inconditionnel (déjà le cas) ⇒ tourne que billing ou
    révocation soient actifs."""
    async def _loop():
        while True:
            try:
                await asyncio.sleep(RECONCILE_INTERVAL_SECONDS)
                await _reconcile_cycle()
            except asyncio.CancelledError:
                break

    _t = asyncio.create_task(_loop())
    _reconcile_bg_tasks.add(_t)
    _t.add_done_callback(_reconcile_bg_tasks.discard)
    log.info("[RECONCILE] worker started (interval=%ss)", RECONCILE_INTERVAL_SECONDS)


@app.on_event("startup")
async def _verify_claim_functions_deployed():
    """Deploy guard — le claim atomique (PR2) est LOAD-BEARING. Si la migration
    claim_intent/reclaim_intent n'est pas appliquée, l'anti-double est INACTIF
    (le wrapper fail-open génère quand même). On le crie FORT au boot plutôt que
    silencieusement à chaque requête. Sonde NON-POLLUANTE : reclaim d'un intent_id
    inexistant = UPDATE qui ne matche rien (aucune ligne insérée). Appel RPC
    DIRECT (pas via le wrapper qui avale les erreurs) pour détecter PGRST202
    (fonction absente)."""
    try:
        await asyncio.to_thread(
            lambda: supa.rpc(
                "reclaim_intent", {"p_intent_id": "__startup_probe__", "p_max": 0}
            ).execute()
        )
        log.info("[CLAIM] deploy guard OK — claim_intent/reclaim_intent present")
    except Exception as exc:  # noqa: BLE001
        log.error(
            "[CLAIM] ⚠️ DEPLOY GUARD FAILED — claim functions missing/unreachable? "
            "anti-double is INACTIVE until the PR2 migration is applied. err=%s: %s",
            type(exc).__name__, exc,
        )


@app.post("/internal/reconcile")
async def trigger_reconcile(request: Request):
    """PR4 — manual reconciliation pass (testing + prod cron). Gated by the
    X-Reconcile-Secret header == env RECONCILE_SECRET; disabled (403) when the
    env is unset. Only transitions stuck RUNNING intents; no billing, no OpenAI."""
    secret = os.environ.get("RECONCILE_SECRET")
    if not secret:
        raise HTTPException(status_code=403, detail="reconcile disabled (RECONCILE_SECRET unset)")
    if request.headers.get("X-Reconcile-Secret") != secret:
        raise HTTPException(status_code=403, detail="forbidden")
    return await reconcile_once()


@app.get("/internal/claim-stats")
async def claim_stats(request: Request):
    """PR2 — snapshot LIVE des issues du claim (won/running/replay/reclaim/
    fail_open), depuis le dernier redéploiement. Gated par X-Reconcile-Secret.
    Métrique DURABLE = les logs `[CLAIM-OUTCOME]` (survivent aux restarts) ; cet
    endpoint est un raccourci de pilotage en temps réel. Aucun accès DB."""
    secret = os.environ.get("RECONCILE_SECRET")
    if not secret:
        raise HTTPException(status_code=403, detail="claim-stats disabled (RECONCILE_SECRET unset)")
    if request.headers.get("X-Reconcile-Secret") != secret:
        raise HTTPException(status_code=403, detail="forbidden")
    return {"counters": dict(CLAIM_COUNTERS), "total": sum(CLAIM_COUNTERS.values())}


@app.post("/purchases/sync")
async def purchases_sync(
    current_user: CurrentUser = Depends(require_active_identity),
):
    """P0 (2026-07-10) — RÉCONCILIE un PASS MESURÉ depuis le subscriber RevenueCat
    (restore / sync / reinstall / device-change / RC transfer / webhook manqué / App
    Review). Lit le subscriber via l'API REST RC et, si premium actif + store_transaction_id
    fiable + produit mappé → reconstruit un pass IDEMPOTENT via grant_purchase (JAMAIS
    un rôle-seul, JAMAIS unlimited). Sinon → restore_required. Le client n'assure jamais
    le premium lui-même.
    """
    log.info("[purchases/sync] ENTER user=%s", current_user.user_id)
    secret = os.environ.get("REVENUECAT_SECRET_API_KEY", "")
    if not secret:
        # Not configured yet (operational step). Don't pretend it worked.
        raise HTTPException(
            status_code=503,
            detail={
                "error_code": "RC_SYNC_NOT_CONFIGURED",
                "user_message": "Purchase sync is temporarily unavailable.",
            },
        )

    uid = current_user.user_id
    url = f"https://api.revenuecat.com/v1/subscribers/{uid}"
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, headers={"Authorization": f"Bearer {secret}"})
    except Exception as exc:
        log.warning("[purchases/sync] RC unreachable user=%s err=%s", uid, exc)
        raise HTTPException(
            status_code=502,
            detail={"error_code": "RC_UNREACHABLE", "user_message": "Could not reach the store."},
        )

    if resp.status_code != 200:
        # 404 = RC has never seen this app_user_id (no purchase). Not an error.
        log.info("[purchases/sync] RC status=%s user=%s (no active entitlement)", resp.status_code, uid)
        return {"synced": False, "is_premium": False, "reason": f"rc_status_{resp.status_code}"}

    data = resp.json()
    # P0 (2026-07-10) — RÉCONCILIATION restore/sync → pass MESURÉ (reinstall, device-
    # change, RC transfer, webhook manqué, App Review restore). Même chemin idempotent
    # que le webhook (grant_purchase) ; JAMAIS unlimited, JAMAIS rôle-seul. La logique
    # (parse subscriber + guards + grant idempotent) vit dans billing (testable FakeSupa).
    import billing  # noqa: PLC0415 — lazy
    rec = await billing.reconcile_pass_from_subscriber(
        user_id=uid, subscriber=(data.get("subscriber") or {}), supa=supa)
    # Log prod structuré (sans payload complet ni secret).
    log.info(
        "[purchases/sync] rc_sync entitlement_active=%s user=%s product_id=%r "
        "store_transaction_id_present=%s expires_date_present=%s state=%s reason=%s grant=%s",
        rec.get("state") != "free", uid, rec.get("product_id"),
        rec.get("store_tx_present"), rec.get("expires_present"),
        rec.get("state"), rec.get("reason") or "-", rec.get("grant_status") or "-",
    )
    # P0 (2026-07-10) — entitlement RC ACTIF (state pass|restore_required) → le RÔLE
    # premium (FEATURES) doit exister/être rafraîchi : miroir du dual-write webhook
    # (reinstall / device-change / RC transfer / webhook manqué / App Review). JAMAIS
    # unlimited : la génération reste MÉTRÉE par le pass (reserve_decision).
    if rec.get("state") in ("pass", "restore_required"):
        try:
            from revenuecat_webhook import _upsert_premium  # noqa: PLC0415 — lazy (évite circular import)
            await _upsert_premium(supa=supa, user_id=uid,
                                  expires_at_iso=rec.get("expires_at"),
                                  event_type="PURCHASES_SYNC", event_id="sync")
            log.info("[purchases/sync] premium role upserted (features) user=%s state=%s", uid, rec.get("state"))
        except Exception as exc:  # noqa: BLE001 — best-effort : le pass reste l'autorité de génération
            log.warning("[purchases/sync] premium role upsert failed user=%s err=%s", uid, exc)

    if rec.get("state") == "pass":
        return {"synced": True, "is_premium": True, "has_measurable_pass": True,
                "expires_at": rec.get("expires_at"), "grant_status": rec.get("grant_status")}
    if rec.get("state") == "restore_required":
        # is_premium=True = FEATURES (entitlement RC actif) ; has_measurable_pass=False
        # = pas encore de pass mesuré → l'app affiche « restore required », JAMAIS unlimited.
        return {"synced": False, "is_premium": True, "has_measurable_pass": False,
                "state": "restore_required", "expires_at": rec.get("expires_at"),
                "reason": rec.get("reason")}
    return {"synced": False, "is_premium": False, "reason": "no_active_entitlement"}


# ── Sprint 1B — Promo / influencer / admin codes ──────────────────────────────


async def _require_admin(current_user: CurrentUser) -> None:
    """Backend-authoritative STRICT admin gate — admin role ONLY (NOT premium).
    Rejects regardless of any client flag; the frontend opening an admin screen
    grants nothing. Every admin endpoint calls this first."""
    if not await is_admin_role(current_user.user_id):
        raise HTTPException(
            status_code=403,
            detail={"error_code": "forbidden", "user_message": "Admin access required."},
        )


@app.post("/promo/redeem")
async def promo_redeem_endpoint(
    payload: dict = Body(...),
    current_user: CurrentUser = Depends(require_active_identity),
):
    """Redeem a promo code for the authenticated user (atomic, via RPC)."""
    code = str(payload.get("code") or "").strip()
    if not code:
        raise HTTPException(
            status_code=400,
            detail={"error_code": "invalid_code", "user_message": "Enter a promo code."},
        )
    if not check_redeem_rate(current_user.user_id):
        raise HTTPException(
            status_code=429,
            detail={"error_code": "rate_limited",
                    "user_message": "Too many attempts. Please try again later."},
        )
    result = await redeem_promo(current_user.user_id, code)
    if not result.get("ok"):
        err = result.get("error", "invalid_code")
        log.info("[Sprint 1B] redeem rejected — user=%s error=%s", current_user.user_id, err)
        raise HTTPException(
            status_code=400,
            detail={"error_code": err,
                    "user_message": "This promo code could not be applied."},
        )
    log.info("[Sprint 1B] redeem OK — user=%s type=%s campaign=%s",
             current_user.user_id, result.get("type"), result.get("campaign"))
    return {
        "ok": True,
        "type": result.get("type"),
        "unlimited": bool(result.get("unlimited")),
        "generation_limit": result.get("generation_limit"),
        "campaign": result.get("campaign"),
    }


@app.post("/admin/promo-codes")
async def admin_create_promo_code(
    payload: dict = Body(...),
    current_user: CurrentUser = Depends(require_active_identity),
):
    await _require_admin(current_user)
    type_ = str(payload.get("type") or "")
    if type_ not in ("limited_generations", "unlimited"):
        raise HTTPException(400, detail={"error_code": "invalid_type",
                                         "user_message": "Invalid code type."})
    gen_limit = payload.get("generation_limit")
    if type_ == "limited_generations":
        if not isinstance(gen_limit, int) or gen_limit <= 0:
            raise HTTPException(400, detail={"error_code": "invalid_generation_limit",
                                             "user_message": "generation_limit must be a positive integer."})
    else:
        gen_limit = None
    max_red = payload.get("max_redemptions")
    if max_red is not None and (not isinstance(max_red, int) or max_red <= 0):
        raise HTTPException(400, detail={"error_code": "invalid_max_redemptions",
                                         "user_message": "max_redemptions must be a positive integer or null."})
    custom = payload.get("code")
    if custom is not None:
        custom = str(custom).strip() or None
    try:
        row = await create_promo_code(
            created_by=current_user.user_id,
            code=custom,
            type_=type_,
            generation_limit=gen_limit,
            max_redemptions=max_red,
            expires_at=payload.get("expires_at"),     # ISO-8601 string or null
            campaign=(payload.get("campaign") or None),
            note=(payload.get("note") or None),
        )
    except Exception as exc:  # noqa: BLE001 — duplicate code → unique index violation
        log.warning("[Sprint 1B] create promo failed — admin=%s err=%s",
                    current_user.user_id, exc)
        raise HTTPException(409, detail={"error_code": "code_conflict",
                                         "user_message": "That code already exists. Try another."})
    log.info("[Sprint 1B] promo code created — admin=%s code=%s type=%s",
             current_user.user_id, row.get("code"), type_)
    return row


@app.get("/admin/promo-codes")
async def admin_list_promo_codes(
    current_user: CurrentUser = Depends(require_active_identity),
):
    await _require_admin(current_user)
    return {"codes": await list_promo_codes()}


@app.patch("/admin/promo-codes/{code_id}")
async def admin_patch_promo_code(
    code_id: str,
    payload: dict = Body(...),
    current_user: CurrentUser = Depends(require_active_identity),
):
    await _require_admin(current_user)
    active = payload.get("active")
    if not isinstance(active, bool):
        raise HTTPException(400, detail={"error_code": "invalid_active",
                                         "user_message": "active must be true or false."})
    updated = await set_promo_active(code_id, active)
    if not updated:
        raise HTTPException(404, detail={"error_code": "not_found",
                                         "user_message": "Promo code not found."})
    log.info("[Sprint 1B] promo code %s set active=%s by admin=%s",
             code_id, active, current_user.user_id)
    return updated


async def resolve_design_ai_message(
    client,
    *,
    fallback_msg: str,
    message: str,
    intent_class,
    should_generate: bool,
    room_type: str,
    atmosphere_label: str,
    has_vision: bool,
    ui_locale: str,
    normalize_enabled: bool,
    image_url: str = "",
) -> str:
    """PR3 Designer Voice gate for DESIGN_ADVICE turns.

    Returns the final ai_message. The LLM voice fires ONLY when AYDEN_VOICE=1
    AND the resolved TurnIntent is DESIGN_ADVICE AND the turn is not an
    action/refine (should_generate). In every other case — flag OFF, non-design
    turn, or any LLM error/empty — it returns the existing pools reply localized
    EXACTLY as before (byte-identical fallback). No /generate.

    When `image_url` (the current render) is present, it is passed to the voice
    so Ayden grounds his answer in THIS image ("in general" → "in THIS room").
    Absent (older client / no render) → text-only, unchanged."""
    turn = resolve_turn_intent(message, intent_class=intent_class)
    _room = room_type or "(none)"

    if should_generate or turn != TurnIntent.DESIGN_ADVICE:
        # PR-B — Execution Voice : sur un tour de GÉNÉRATION, remplacer le pool
        # aveugle par une courte ligne « architecte qui agit » liée au message.
        # Always-on (pas de flag) ; timeout court ; sur timeout / erreur / vide →
        # fallback pool localisé BYTE-IDENTIQUE (ci-dessous). Ne se déclenche QUE
        # sur should_generate=True (jamais OOS/Support/Advice).
        if should_generate:
            _t0 = time.monotonic()
            try:
                _exec = await asyncio.wait_for(
                    generate_execution_voice(
                        client, message=message, room_type=room_type,
                        atmosphere_label=atmosphere_label, language=ui_locale),
                    timeout=2.0,
                )
            except Exception:  # noqa: BLE001 — TimeoutError inclus → fallback pool
                _exec = None
            _ms = (time.monotonic() - _t0) * 1000.0
            if _exec and _exec.strip():
                log.info("[AYDEN-EXEC-VOICE] enabled latency_ms=%.0f", _ms)
                return _exec.strip()
            log.info("[AYDEN-EXEC-VOICE] fallback (timeout/empty/error) latency_ms=%.0f — pools", _ms)
        log.info(
            "[AYDEN-VOICE] disabled (turn=%s should_generate=%s) — pools fallback",
            getattr(turn, "value", turn), should_generate,
        )
        return await localize_reply(client, fallback_msg, ui_locale, enabled=normalize_enabled)

    if not designer_voice_enabled():
        log.info(
            "[AYDEN-VOICE] disabled (flag OFF) intent=design_advice room=%s has_vision=%s — pools fallback",
            _room, has_vision,
        )
        return await localize_reply(client, fallback_msg, ui_locale, enabled=normalize_enabled)

    _vision = bool(image_url and image_url.strip().startswith("http"))
    _t0 = time.monotonic()
    voice = await generate_designer_voice(
        client, message=message, room_type=room_type,
        atmosphere_label=atmosphere_label, has_vision=has_vision, language=ui_locale,
        image_url=image_url,
    )
    _ms = (time.monotonic() - _t0) * 1000.0
    if voice:
        log.info(
            "[AYDEN-VOICE] enabled intent=design_advice room=%s has_vision=%s vision_input=%s latency_ms=%.0f",
            _room, has_vision, _vision, _ms,
        )
        return voice
    log.info(
        "[AYDEN-VOICE] enabled intent=design_advice room=%s has_vision=%s vision_input=%s latency_ms=%.0f "
        "fallback_reason=llm_empty_or_error — pools fallback",
        _room, has_vision, _vision, _ms,
    )
    return await localize_reply(client, fallback_msg, ui_locale, enabled=normalize_enabled)


@app.post("/chat")
async def chat(
    session_id: str = Form(...),
    message: str = Form(...),
    style_label: str = Form(...),
    room_type: str = Form(""),
    iteration: int = Form(1),
    history: str = Form(""),           # JSON-encoded list of {role, content} messages
    secondary_spaces: str = Form(""),  # JSON-encoded list of secondary room type keys
    ui_locale: str = Form("en"),       # Phase 1 — authoritative reply language (en|fr|km)
    # ── PR0 (Ayden Companion) — situational context. All optional ; an older
    # client that omits them yields safe backend defaults (fallback intact).
    has_vision: str = Form(""),                 # "1"/"0" — frontend _hasGenerated
    generation_in_progress: str = Form(""),     # "1"/"0" — frontend _isGenerating/_v1Priming
    current_image_url: str = Form(""),          # displayed render — vision-input hook (PR2), carried not opened
    displayed_version_id: str = Form(""),       # frontend _branchSourceVersionId / latest
    original_image_url: str = Form(""),         # V1 source upload
    current_user: CurrentUser = Depends(require_active_identity),  # Wave 5.17a
):
    """
    Conversation-only endpoint — no image generation.

    Returns ai_message, suggestion chips, and a should_generate hint.
    The frontend uses should_generate to decide whether to also call /generate.

    Conversation mode (QUESTION, PRAISE):  should_generate = False
    Generation mode (user asked for change): should_generate = True
    Mixed mode (question + change intent):  should_generate = False (chips guide toward it)
    """
    log.info("=== /chat called === session=%s iteration=%d", session_id, iteration)
    log.info("  message: %s", message[:120] if message else "(empty)")
    log.info("  style: %s  room: %s", style_label, room_type or "(none)")

    # Parse history
    history_messages: list[dict] = []
    if history:
        try:
            history_messages = json.loads(history)
        except Exception:
            log.warning("  Could not parse history JSON — ignoring")

    # Phase 3 — normalize FR/KM user history to English for the keyword-matching
    # consumers (parse_history). EN / flag-off -> SAME object (byte-identical).
    history_messages_en = await normalize_history_to_english(
        openai, history_messages, ui_locale,
        enabled=os.environ.get("MULTILINGUAL_NORMALIZE", "0") == "1",
    )
    refinement_state = parse_history(history_messages_en, iteration)

    # Parse secondary spaces
    secondary_visible_spaces: list[str] = []
    if secondary_spaces:
        try:
            secondary_visible_spaces = json.loads(secondary_spaces)
        except Exception:
            log.warning("  Could not parse secondary_spaces JSON — ignoring")

    atmosphere_id = label_to_atmosphere_id(style_label)

    # ── Wave 3.1: meta intent check (before design routing) ───────────────────
    meta = classify_meta_intent(message)
    log.info(
        "  meta: %s  lang: %s->%s  conf: %.2f",
        meta.intent.value, meta.language, meta.target_language, meta.confidence,
    )

    # ── Wave 3.4.1: session memory built early — pass UI state as hints ──────
    # atmosphere_id and room_type from the request are reliable context signals
    # even when conversation history hasn't mentioned them yet (e.g. after
    # a series of generations with no chat messages).
    _early_session_memory = build_session_memory(
        history=history_messages,
        # Phase 1 — the UI locale (the language the user chose in the app) is the
        # authoritative reply language; per-message detection is the fallback.
        # In-chat explicit LANGUAGE_SWITCH still wins via the override below.
        detected_language=(ui_locale.strip() or meta.language),
        session_language_override=meta.target_language if meta.target_language != meta.language else "",
        atmosphere_id_hint=atmosphere_id,
        room_type_hint=room_type,
    )

    # ── PR0 (Ayden Companion) — situational awareness ─────────────────────────
    # Facts layer: a pure snapshot of "where are we now", assembled once. The
    # interpretation layer (mode / is_about_image) is resolved per branch via
    # build_context(facts, mode) once the routing branch is known, then logged
    # ([SITCTX]) and attached to the response under `context`. No behaviour
    # change : ai_message is left exactly as the routing below produces it.
    facts = build_situational_facts(
        room_type=room_type,
        atmosphere_id=atmosphere_id,
        iteration=iteration,
        session_language=_early_session_memory.session_language,
        has_vision_raw=has_vision,
        generation_in_progress_raw=generation_in_progress,
        current_image_url=current_image_url,
        displayed_version_id=displayed_version_id,
        original_image_url=original_image_url,
    )

    if meta.intent != MetaIntent.NONE:
        # Wave 3.4.1: project-aware greeting whenever we have any context
        # (iteration > 1 means at least one vision was generated, or history exists)
        has_project_context = (
            iteration > 1
            or _early_session_memory.message_count > 0
            or bool(_early_session_memory.atmosphere_mentioned)
        )
        if meta.intent == MetaIntent.GREETING and has_project_context:
            ai_message = generate_project_aware_greeting(meta, _early_session_memory, seed_extra=session_id[:8])
        else:
            ai_message = generate_meta_response(meta, seed_extra=session_id[:8])
        suggestions = await _suggest_localized(ui_locale,
            atmosphere_id=atmosphere_id,
            room_type=room_type,
            iteration=iteration,
            edit_mode=EditMode.STYLE_REFINEMENT,
            sub_intent=SubIntent.GENERAL,
        )
        log.info("  meta ai_message: %s", ai_message)
        log.info("=== /chat META SUCCESS === %s", meta.intent.value)
        ctx = build_context(facts, TurnIntent.META)
        log.info("[SITCTX] %s", context_log_line(ctx))
        return attach_context({
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": suggestions,
            "should_generate": False,
            "intent": "conversation",
            "sub_intent": meta.intent.value,
            "session_language": meta.target_language,
        }, ctx)

    # ── PR1 (Ayden Companion) — Out of Scope gate ─────────────────────────────
    # Deterministic, high-precision refusal of clearly off-domain requests.
    # Runs AFTER meta (greetings/thanks already returned) and BEFORE design /
    # support routing. Fires ONLY on a positive off-domain signal — never on
    # "design did not match" — so a real design or app-support question is never
    # blocked. No LLM, no generation.
    if detect_out_of_scope(message, language=_early_session_memory.session_language):
        ai_message = get_out_of_scope_reply(ui_locale)
        log.info("=== /chat OUT_OF_SCOPE SUCCESS ===")
        ctx = build_context(facts, TurnIntent.OUT_OF_SCOPE)
        log.info("[SITCTX] %s", context_log_line(ctx))
        return attach_context({
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": [],
            "should_generate": False,
            "intent": "out_of_scope",
            "sub_intent": "out_of_scope",
            "session_language": _early_session_memory.session_language,
        }, ctx)

    _lang_for_4_11a = (
        "km" if _early_session_memory.session_language == "km" else "en"
    )

    # ── PR2 Support (Ayden Companion) — quota honesty gate ────────────────────
    # "Combien de générations gratuites il me reste / how many do I have left /
    # is it free" — a high-precision REMAINING-COUNT question. Answer with the
    # user's REAL live quota (AccessDecision) + where to upgrade ; never an
    # invented number. Placed HERE — after meta/OOS, BEFORE the generate
    # dominance + design routing — because classify_intent otherwise mislabels
    # these questions as GENERATE (proven: they never reach the PRODUCT_HELP
    # branch). Pure pricing ("combien ça coûte") is deliberately NOT caught here
    # (it wants the price, which lives on the paywall → static billing KB).
    # Deterministic, no LLM, no image, should_generate=False.
    if detect_quota_question(message):
        _qdecision = await resolve_generation_access(current_user.user_id)
        ai_message = build_quota_answer(
            _qdecision, language=_early_session_memory.session_language)
        log.info(
            "  [PR2 quota] tier=%s free_remaining=%s",
            getattr(_qdecision, "tier", "?"), getattr(_qdecision, "free_remaining", "?"),
        )
        log.info("=== /chat PR2 QUOTA SUCCESS ===")
        ctx = build_context(facts, TurnIntent.PRODUCT_HELP)
        log.info("[SITCTX] %s", context_log_line(ctx))
        return attach_context({
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": [],
            "should_generate": False,
            "intent": "product_help",
            "sub_intent": "product_help",
            "session_language": _early_session_memory.session_language,
        }, ctx)

    # ── Wave 4.11d: Generation Intent Dominance ────────────────────────────
    # Two stateless detectors that sit BEFORE detect_ambiguity. When either
    # fires, the user gets the next vision instead of another clarification.
    # Preserves Wave 4.11a/b/c : first-time ambiguous messages still clarify ;
    # genuine architectural questions still route to DESIGN_DISCUSSION ;
    # negative-feedback still flows through NEGATIVE_FEEDBACK.
    _wave411d_reason = None
    if iteration > 1 and detect_generation_demand(message):
        _wave411d_reason = "generation_demand"
    elif iteration > 1 and is_clarification_answer(message, history_messages):
        _wave411d_reason = "clarification_resolved"

    if _wave411d_reason is not None:
        log.info("  [Wave 4.11d] generation dominance fired : %s", _wave411d_reason)
        intent_class = IntentClassification(
            intent=ConversationIntent.GENERATE,
            sub_intent=SubIntent.REFINE_ATMOSPHERE,
            confidence=0.90 if _wave411d_reason == "generation_demand" else 0.85,
            reasoning=f"Wave 4.11d — {_wave411d_reason}",
        )
        # Skip ambiguity check entirely — the user has shown they want a
        # vision. Fall straight to the standard generate flow below.
        session_memory = _early_session_memory
        # Wave 4.11e — both Wave 4.11d dominance branches need an action-
        # oriented chat response that does NOT open a new discussion topic.
        # clarification_resolved   → echo the user's clarification answer
        #                            ("Got it — overall room feeling. On it.")
        # generation_demand        → bare commit ("Got it — generating the
        #                            next vision now.") since the user did
        #                            not narrate anything to echo back.
        # Both branches set should_generate=True so /generate fires next.
        if _wave411d_reason == "clarification_resolved":
            ai_message = generate_clarification_exit_response(
                user_answer=message,
                atmosphere_id=atmosphere_id,
                room_type=room_type,
                language=session_memory.session_language,
                seed_extra=session_id[:8],
            )
        else:
            # Wave 4.11e (sanity-check follow-up) — generation_demand
            # MUST NOT use the generic chat response which would ask
            # "what would you change next?" — the very phrasing the
            # demand was meant to silence.
            ai_message = generate_generation_demand_response(
                atmosphere_id=atmosphere_id,
                room_type=room_type,
                language=session_memory.session_language,
                seed_extra=session_id[:8],
            )
        suggestions = await _suggest_localized(ui_locale,
            atmosphere_id=atmosphere_id,
            room_type=room_type,
            iteration=iteration,
            edit_mode=EditMode.STYLE_REFINEMENT,
            sub_intent=intent_class.sub_intent,
        )
        log.info("=== /chat WAVE 4.11d GENERATE DOMINANCE (%s) ===",
                 _wave411d_reason)
        ctx = build_context(facts, TurnIntent.ACTION_REFINE)
        log.info("[SITCTX] %s", context_log_line(ctx))
        return attach_context({
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": suggestions,
            "should_generate": True,
            "intent": intent_class.intent.value,
            "sub_intent": intent_class.sub_intent.value,
            "session_language": session_memory.session_language,
        }, ctx)

    # ── Wave 4.11a: ambiguity check — V2+ messages with truly ambiguous
    # standalone adjectives ("make it bigger") trigger a clarification
    # instead of guessing. Returns early when fired ; clear directional
    # intents ("warmer", "more wood", "more luxury") pass through to the
    # standard classifier untouched.
    _clarification = detect_ambiguity(
        message, iteration, language=_lang_for_4_11a,
        room_type=room_type or None,  # Wave 4.11b — room-aware clarifications
    )
    if _clarification is not None:
        log.info(
            "  ambiguity: id=%s confidence=%.2f language=%s",
            _clarification.ambiguity_id,
            _clarification.confidence,
            _clarification.language,
        )
        log.info("=== /chat AMBIGUITY CLARIFY SUCCESS ===")
        ctx = build_context(facts, TurnIntent.AMBIGUOUS)
        log.info("[SITCTX] %s", context_log_line(ctx))
        return attach_context({
            "ai_message": await localize_reply(openai, _clarification.clarification_text, ui_locale, enabled=_norm_enabled()),
            "suggestions": [],
            "should_generate": False,
            "intent": "design_discussion",
            "sub_intent": "design_discussion",
            "session_language": _early_session_memory.session_language,
        }, ctx)

    # ── PR2 Support (Ayden Companion) — RESULT_EXPLANATION handler ────────────
    # "pourquoi tu as mis / changé / pas mis X" — the subject is the SYSTEM, not
    # the user (that subject test, in detect_result_explanation, separates it
    # from design advice "pourquoi JE devrais…"). Explain the design LOGIC of
    # THIS render — anchored on the chosen atmosphere + the preservation contract
    # — and invite a concrete change. Deterministic, no LLM, no image opened.
    # Anti-bluff (persona): we never claim a specific object/measurement is
    # present; the pixel-specific "why THAT exact object" is PR3 Voice+vision.
    # Gated on has_vision: with no render yet there is nothing to explain, so we
    # fall through to the normal routing. Priority matches resolve_turn_intent
    # (after AMBIGUOUS, before PRODUCT_HELP / DESIGN_ADVICE).
    if facts.has_vision and detect_result_explanation(message):
        ai_message = build_result_explanation(
            atmosphere_label=style_label,
            room_type=room_type or "",
            language=_early_session_memory.session_language,
        )
        log.info("=== /chat PR2 RESULT_EXPLANATION SUCCESS ===")
        ctx = build_context(facts, TurnIntent.RESULT_EXPLANATION)
        log.info("[SITCTX] %s", context_log_line(ctx))
        return attach_context({
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": [],
            "should_generate": False,
            "intent": "design_discussion",
            "sub_intent": "design_discussion",
            "session_language": _early_session_memory.session_language,
        }, ctx)

    # ── Wave 2.5: design intent routing ───────────────────────────────────────
    # Phase 2: design intent routing runs on canonical English (FR/KM -> EN).
    # classify_meta_intent above stays on the ORIGINAL message (language + FR/KM
    # meta replies); only this design router receives the normalized text.
    # EN / flag-off -> strict passthrough (message_en IS message).
    message_en = await normalize_to_english(
        openai, message, ui_locale,
        enabled=os.environ.get("MULTILINGUAL_NORMALIZE", "0") == "1",
    )
    if message_en is not message:
        log.info("  [normalize] %s->en  %r -> %r", ui_locale, message[:60], message_en[:60])
    intent_class = classify_intent(message_en, iteration)

    # ── PR3-router-fix (Ayden Companion) — two recall corrections + observability.
    # Resolve the product topic ONCE (used both to route AND to answer).
    _topic_id = detect_product_help(message, language=_lang_for_4_11a)
    _opinion_q = detect_design_opinion_question(message)
    # Fix B — DESIGN_ADVICE recall : an elliptical opinion question phrased like a
    # statement ("I put the TV in front of the window?") is mislabelled GENERATE,
    # so the backend generated instead of giving an opinion. When it's an opinion
    # question (and NOT a product topic, NOT a real confirmation), downgrade
    # GENERATE → design discussion so the Designer voice answers. Plain commands
    # ("make it warmer", "add a lamp") never match the opinion detector → untouched.
    if (_topic_id is None
            and intent_class.intent == ConversationIntent.GENERATE
            and _opinion_q):
        log.info("  [PR3-router] GENERATE→DESIGN_ADVICE (opinion question): %r", message[:80])
        intent_class = IntentClassification(
            intent=ConversationIntent.DESIGN_DISCUSSION,
            sub_intent=SubIntent.GENERAL,
            confidence=0.80,
            reasoning="PR3-router — design opinion question, not a change command",
        )
    # Observability — log the detected intent for EVERY chat request (debug routing).
    log.info(
        "[TURN-INTENT] classify=%s/%s product_topic=%s opinion_q=%s → turn=%s",
        intent_class.intent.value, intent_class.sub_intent.value, _topic_id, _opinion_q,
        resolve_turn_intent(
            message, intent_class=intent_class,
            product=(_topic_id is not None or intent_class.intent in (
                ConversationIntent.PRODUCT_HELP, ConversationIntent.SUPPORT)),
        ).value,
    )

    # ── Wave 4.11a: PRODUCT_HELP / SUPPORT direct routing — the pre-filter
    # inside classify_intent returns one of these when the user is asking
    # about the product rather than asking for a design change. Look up the
    # specific topic answer in product_knowledge and return it ; never
    # trigger a generation on these paths.
    # Fix A — PRODUCT_HELP recall : a confident KB topic match is authoritative,
    # so route to product help even when the base classifier missed it (e.g.
    # "what is the re-upload?" was labelled CONVERSATION → design voice deflected).
    if (intent_class.intent in (
            ConversationIntent.PRODUCT_HELP,
            ConversationIntent.SUPPORT,
        ) or _topic_id is not None):
        topic_id = _topic_id
        if topic_id is not None:
            ai_message = get_product_answer(topic_id, language=_lang_for_4_11a)
        else:
            # Pre-filter matched a generic shape but no specific topic
            # resolved — fall back to the contact_support answer rather
            # than emit silence.
            ai_message = get_product_answer(
                "support_contact", language=_lang_for_4_11a
            )
        log.info(
            "  product_knowledge: intent=%s topic=%s lang=%s",
            intent_class.intent.value,
            topic_id or "(generic_fallback)",
            _lang_for_4_11a,
        )
        log.info("=== /chat PRODUCT_HELP / SUPPORT SUCCESS ===")
        ctx = build_context(facts, TurnIntent.PRODUCT_HELP)
        log.info("[SITCTX] %s", context_log_line(ctx))
        return attach_context({
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": [],
            "should_generate": False,
            "intent": intent_class.intent.value,
            "sub_intent": intent_class.sub_intent.value,
            "session_language": _early_session_memory.session_language,
        }, ctx)

    # ── Wave 4.11e: SUMMARIZE_DESIGN_BRIEF handler ────────────────────────────
    # User explicitly asked "summarize what I want / recap / what do you
    # understand". Emit a bulleted summary derived from refinement_state +
    # "Ready to generate?" footer. Never generates from this branch — the
    # user follows up with "yes / generate" which Wave 4.11d catches.
    if intent_class.sub_intent == SubIntent.SUMMARIZE_DESIGN_BRIEF:
        ai_message = generate_brief_summary(
            refinement_state=refinement_state,
            atmosphere_id=atmosphere_id,
            room_type=room_type or "",
            language=_early_session_memory.session_language,
            last_user_message=message,
        )
        log.info("  [Wave 4.11e] design brief summary emitted")
        log.info("=== /chat WAVE 4.11e SUMMARIZE_DESIGN_BRIEF SUCCESS ===")
        ctx = build_context(facts, TurnIntent.DESIGN_ADVICE)
        log.info("[SITCTX] %s", context_log_line(ctx))
        return attach_context({
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": [],
            "should_generate": False,
            "intent": intent_class.intent.value,
            "sub_intent": intent_class.sub_intent.value,
            "session_language": _early_session_memory.session_language,
        }, ctx)

    # ── Wave 4.7.7: gated conversational generate confirmation ───────────────
    # Runs AFTER classify_meta_intent (so STOP_GENERATION / THANKS / reflection
    # questions still win — meta != NONE returned above). Promotes a bare
    # confirmation to GENERATE ONLY when a concrete design request is pending.
    # Additive: never downgrades an existing classification.
    confirmation_generate = False
    _conf_detected = is_confirmation(message)
    if meta.intent == MetaIntent.NONE and iteration > 1:
        _conf = resolve_confirmation(message, history_messages)
        if _conf is not None:
            intent_class = _conf
            confirmation_generate = True

    log.info(
        "  intent: %s  sub_intent: %s  confidence: %.2f  reason: %s",
        intent_class.intent.value, intent_class.sub_intent.value,
        intent_class.confidence, intent_class.reasoning,
    )
    log.info(
        "[GenerateConfirmation] pending_design_intent=%s  confirmation_detected=%s  "
        "tone_veto_bypassed=%s",
        confirmation_generate, _conf_detected, confirmation_generate,
    )

    # ── Wave 3.2 + 3.3: session memory (reuse early build) + emotional context + tone calibration ──
    session_memory = _early_session_memory
    emotional_ctx = detect_emotional_context(message)
    tone_mode = select_tone_mode(
        meta_intent=meta.intent,
        sub_intent=intent_class.sub_intent,
        confidence=intent_class.confidence,
        session_memory=session_memory,
        emotional_context=emotional_ctx,
    )
    log.info(
        "  tone: %s  emotional: %s  exploring: %s  session_lang: %s",
        tone_mode.value, emotional_ctx.value,
        session_memory.is_exploring, session_memory.session_language,
    )

    # Wave 4.7.7 Task 3: a confirmed, pending-gated GENERATE must not be vetoed
    # by the presentation-tone layer (ACKNOWLEDGMENT → ARCHITECT_LIGHT).
    if tone_mode == ToneMode.HUMAN_SOFT and not confirmation_generate:
        ai_message = generate_human_soft_response(
            session_memory=session_memory,
            sub_intent=intent_class.sub_intent,
            seed_extra=session_id[:8],
        )
        suggestions = await _suggest_localized(ui_locale,
            atmosphere_id=atmosphere_id,
            room_type=room_type,
            iteration=iteration,
            edit_mode=EditMode.STYLE_REFINEMENT,
            sub_intent=SubIntent.GENERAL,
        )
        log.info("  human_soft ai_message: %s", ai_message)
        log.info("=== /chat HUMAN_SOFT SUCCESS ===")
        ctx = build_context(facts, resolve_turn_intent(message, intent_class=intent_class))
        log.info("[SITCTX] %s", context_log_line(ctx))
        return attach_context({
            "ai_message": await resolve_design_ai_message(
                openai, fallback_msg=ai_message, message=message,
                intent_class=intent_class, should_generate=False,
                room_type=room_type, atmosphere_label=style_label,
                has_vision=facts.has_vision, ui_locale=ui_locale,
                image_url=facts.current_image_url or "",
                normalize_enabled=_norm_enabled()),
            "suggestions": suggestions,
            "should_generate": False,
            "intent": "conversation",
            "sub_intent": intent_class.sub_intent.value,
            "session_language": session_memory.session_language,
        }, ctx)

    if tone_mode == ToneMode.ARCHITECT_LIGHT and not confirmation_generate:
        resp_length = select_response_length(message, emotional_ctx)
        ai_message = generate_architect_light_response(
            user_message=message,
            atmosphere_id=atmosphere_id,
            room_type=room_type,
            emotional_context=emotional_ctx,
            length=resp_length,
            language=session_memory.session_language,
            seed_extra=session_id[:8],
        )
        suggestions = await _suggest_localized(ui_locale,
            atmosphere_id=atmosphere_id,
            room_type=room_type,
            iteration=iteration,
            edit_mode=EditMode.STYLE_REFINEMENT,
            sub_intent=intent_class.sub_intent,
        )
        log.info("  architect_light ai_message [%s/%s]: %s", emotional_ctx.value, resp_length.value, ai_message)
        log.info("=== /chat ARCHITECT_LIGHT SUCCESS ===")
        ctx = build_context(facts, resolve_turn_intent(message, intent_class=intent_class))
        log.info("[SITCTX] %s", context_log_line(ctx))
        return attach_context({
            "ai_message": await resolve_design_ai_message(
                openai, fallback_msg=ai_message, message=message,
                intent_class=intent_class, should_generate=False,
                room_type=room_type, atmosphere_label=style_label,
                has_vision=facts.has_vision, ui_locale=ui_locale,
                image_url=facts.current_image_url or "",
                normalize_enabled=_norm_enabled()),
            "suggestions": suggestions,
            "should_generate": False,
            "intent": "conversation",
            "sub_intent": intent_class.sub_intent.value,
            "session_language": session_memory.session_language,
        }, ctx)

    if intent_class.intent == ConversationIntent.MIXED:
        ai_message = generate_mixed_response(
            user_message=message,
            atmosphere_id=atmosphere_id,
            room_type=room_type,
            sub_intent=intent_class.sub_intent,
        )
        should_generate = False
    else:
        ai_message = generate_chat_response(
            user_message=message,
            atmosphere_id=atmosphere_id,
            room_type=room_type,
            sub_intent=intent_class.sub_intent,
            secondary_spaces=secondary_visible_spaces,
            refinement_state=refinement_state,
        )
        should_generate = (intent_class.intent == ConversationIntent.GENERATE)

    # Determine edit_mode from sub_intent for chip selection
    sub_to_edit = {
        SubIntent.LOCAL_EDIT: EditMode.LOCAL_EDIT,
        SubIntent.STRUCTURAL_CHANGE: EditMode.STRUCTURAL_TRANSFORMATION,
        SubIntent.REFINE_ATMOSPHERE: EditMode.STYLE_REFINEMENT,
    }
    edit_mode_for_chips = sub_to_edit.get(intent_class.sub_intent, EditMode.STYLE_REFINEMENT)

    suggestions = await _suggest_localized(ui_locale,
        atmosphere_id=atmosphere_id,
        room_type=room_type,
        iteration=iteration,
        edit_mode=edit_mode_for_chips,
        sub_intent=intent_class.sub_intent,
    )

    log.info("  ai_message: %s", ai_message[:100])
    log.info("  suggestions: %s", suggestions)
    log.info("  should_generate: %s", should_generate)
    log.info(
        "[GenerateConfirmation] final_should_generate=%s  confirmation_generate=%s",
        should_generate, confirmation_generate,
    )
    log.info("=== /chat SUCCESS ===")

    ctx = build_context(
        facts,
        TurnIntent.ACTION_REFINE if should_generate
        else resolve_turn_intent(message, intent_class=intent_class),
    )
    log.info("[SITCTX] %s", context_log_line(ctx))
    return attach_context({
        "ai_message": await resolve_design_ai_message(
            openai, fallback_msg=ai_message, message=message,
            intent_class=intent_class, should_generate=should_generate,
            room_type=room_type, atmosphere_label=style_label,
            has_vision=facts.has_vision, ui_locale=ui_locale,
            image_url=facts.current_image_url or "",
            normalize_enabled=_norm_enabled()),
        "suggestions": suggestions,
        "should_generate": should_generate,
        "intent": intent_class.intent.value,
        "sub_intent": intent_class.sub_intent.value,
        "session_language": meta.language,
    }, ctx)


@app.post("/devices")
async def register_device(
    token: str = Form(...),
    platform: str = Form(""),            # "ios" | "android"
    current_user: CurrentUser = Depends(require_active_identity),
):
    """Phase B — register/refresh this device's FCM token for the user, so the
    backend can push "vision ready" when the app is backgrounded. Upsert on the
    token (one row per device; re-registration just refreshes user/updated_at)."""
    tok = (token or "").strip()
    if not tok:
        raise HTTPException(status_code=400, detail="missing token")
    try:
        supa.table("device_tokens").upsert(
            {
                "user_id": current_user.user_id,
                "token": tok,
                "platform": (platform or "").strip().lower() or "unknown",
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
            on_conflict="token",
        ).execute()
    except Exception as exc:
        log.warning("[Push] device register failed: %s: %s", type(exc).__name__, exc)
        raise HTTPException(status_code=500, detail="register failed")
    return {"ok": True}


@app.post("/generate")
async def generate(
    request: Request,                     # Wave 5.17b — needed for IP rate limit (request.client.host)
    session_id: str = Form(...),
    prompt: str = Form(...),
    before_image_url: str = Form(...),
    style_label: str = Form(...),
    room_type: str = Form(""),
    # Wave 5.17d — canonical ids (locale-stable) for the free-tier scope
    # check. The legacy label form params above stay for prompt-engine
    # compatibility ; these ids drive the membership test ONLY.
    room_type_id: str = Form(""),
    atmosphere_id: str = Form(""),
    iteration: int = Form(1),
    history: str = Form(""),              # JSON-encoded list of {role, content} messages
    let_ai_decide: bool = Form(False),    # AI infers primary room type from image
    surprise_me_flag: bool = Form(False), # AI selects best atmosphere for this room
    secondary_spaces: str = Form(""),     # JSON-encoded list of secondary room type keys
    original_image_url: str = Form(""),  # V1 source image — structural anchor for V2+
    client_request_id: str = Form(""),  # idempotency key from Flutter
    generation_attempt: str = Form("0"),  # #4 defense — bumped by the client ONLY on an intentional regenerate; lets the secondary (content) idempotency key allow a deliberate re-gen while still deduping accidental retries
    generation_trigger: str = Form("unknown"),  # Part 5 observability — auto | button | switch | chat | resume | unknown (logged only; never changes behaviour)
    structural_identity: str = Form(""),  # Wave 4.7.2 — persisted apartment identity token (client round-trip)
    source_mode: str = Form(""),          # Wave 4.7.3 — ORIGINAL | LATEST | SPECIFIC_VERSION (missing => default)
    source_version_id: str = Form(""),    # Wave 4.7.3 — target version id when source_mode=SPECIFIC_VERSION
    versions: str = Form(""),             # Wave 4.7.3 — JSON ledger of prior versions (client round-trip)
    generation_mode: str = Form("preserve"),  # Wave 5.5.14b.1 — bimodal intent: "preserve" | "creative". Default matches today's behaviour. NOT YET ROUTED — read & logged only; composer wiring lands in Wave 5.5.14c.
    ui_locale: str = Form("en"),          # Phase 1 — authoritative reply/caption language (en|fr|km). Does NOT touch the generation prompt (English-internal).
    # CORRECTIF PERF fast-path (2026-07-14) — get_current_user (JWT seul, 0 DB) au lieu de
    # require_active_identity (1 SELECT account_state SÉQUENTIEL). La garde merged_closed est
    # foldée dans le gather de resolve_generation_access (include_identity=True) puis ENFORCÉE
    # ci-dessous, AVANT tout write/OpenAI → 0 RTT séquentiel ajouté par Unified Identity.
    current_user: CurrentUser = Depends(get_current_user),  # Wave 5.17a + fast-path 2026-07-14
):
    # PR0 (2026-07-06) — TRUE handler-entry timestamp (before any pre-flight
    # gate). The PERF timer _req_start starts far below (after auth/ownership/
    # access/claim/billing/quota) so those ~2.5-6s of Supabase RTT were invisible
    # in total_ms. preflight_ms (= _req_start − _handler_entry) is emitted in the
    # PERF SUMMARY. Pure observability; no branch, no behaviour change.
    _handler_entry = time.monotonic()
    # ── Step 0: resolve generation profile ───────────────────────────────────
    profile = get_active_profile()

    # ── Wave 5.17a: session ownership validation ─────────────────────────────
    # Before paying for the gpt-image-1 call, verify the authenticated
    # user actually owns the session_id they're targeting. The MVP
    # backend previously trusted any session_id from the client ; that
    # opens a session-id-forgery vector that becomes a quota-bypass
    # vector as soon as Wave 5.17b's quota gate lands. Closing the gap
    # here is the precondition.
    #
    # New sessions (those with no row yet in the `sessions` table — e.g.
    # the very first /generate call where the frontend has not yet
    # created the session row) are ALLOWED through with a log line. The
    # frontend's supabase RLS still scopes any subsequent reads. This
    # mirrors the legacy "session_id == 'new'" pattern used by the chat
    # screen for in-memory project starts.
    _t_own = time.monotonic()
    _ownership_ok = await _validate_session_ownership(
        session_id=session_id, user_id=current_user.user_id
    )
    _ownership_ms = (time.monotonic() - _t_own) * 1000.0  # fast-path timing (lecture sécurité)
    if not _ownership_ok:
        log.warning(
            "[Wave 5.17a] session ownership rejected — "
            "session=%s claimed_user=%s",
            session_id, current_user.user_id,
        )
        raise HTTPException(
            status_code=403,
            detail={
                "error_code": "SESSION_OWNERSHIP_DENIED",
                "user_message": "This project belongs to a different account.",
                "retryable": False,
                "request_id": "",
            },
        )

    # ── Wave 5.17b — IP rate limit (defensive ceiling, anon-only) ────────────
    # 10 generations / IP / 24h. Signed-in users bypass (account-bound quota
    # below governs them). Wave 5.21c (2026-06-02) — admin/premium roles
    # ALSO bypass the IP ceiling, matching the quota bypass scope. Anonymous
    # admin sessions (dev/validation flows) previously tripped the ceiling
    # at gen #11 even though their user-level quota was uncapped.
    # has_admin_role is cached 60s ; get_quota_status below hits the same
    # cache (no extra DB roundtrip).
    # ── Sprint 1B — centralised access resolver ───────────────────────────────
    # ONE resolution of the generation-access priority:
    #   admin/premium > promo_unlimited > promo_limited > free(watermark) > blocked
    # It drives: the anon IP-limit bypass, the paywall gate, the free-tier scope
    # check, the usage_log reservation, the promo consume, and the watermark.
    # CORRECTIF PERF fast-path — include_identity=True : la lecture merged_closed est
    # foldée dans le gather (roles/promo/usage/identity) → 0 RTT séquentiel ajouté.
    _t_access = time.monotonic()
    _decision = await resolve_generation_access(current_user.user_id, include_identity=True)
    _access_resolver_ms = (time.monotonic() - _t_access) * 1000.0
    # ── Garde merged_closed ENFORCÉE ICI — AVANT tout write (claim/HOLD/reserve) et tout
    #    appel OpenAI. Sémantique identique à require_active_identity (403 merged / 503
    #    read-error). Rien d'écrit avant ce point : ownership (au-dessus) est une lecture.
    enforce_identity_from_decision(_decision, current_user.user_id)
    # Entitled tiers (admin/premium/promo) get clean images AND skip the
    # anonymous IP rate limit; free/blocked do not. Kept under the legacy name
    # `_is_admin_bypass` so the watermark site below stays unchanged — it now
    # means "no watermark" which is exactly clean_watermark.
    _is_admin_bypass = _decision.clean_watermark
    check_ip_rate_limit(
        ip=getattr(getattr(request, "client", None), "host", None),
        is_anonymous=current_user.is_anonymous,
        is_admin=_is_admin_bypass,
    )

    # Billing PR2b (voie a) — le gate quota N'EST PLUS ici. Le resolver ne renvoie
    # plus tier="blocked" (pure identité) ; l'autorité quota passe au WALLET via
    # billing.reserve_decision, APRÈS le scope (plus bas). Ce bloc `if not
    # can_generate → 402` (usage_log) est donc retiré.
    log.info(
        "[Sprint 1B] access OK — user=%s tier=%s free_remaining=%d promo_remaining=%d promo_unlimited=%s",
        current_user.user_id, _decision.tier, _decision.free_remaining,
        _decision.promo_generations_remaining, _decision.promo_unlimited_active,
    )

    # ── Wave 5.17d — Free-tier scope check (Sprint 1B: promo bypasses too) ─────
    # Non-entitled users may only generate Living Room + (Nordic Warmth |
    # Soft Luxury). admin/premium AND promo (limited or unlimited) bypass —
    # _decision.bypass_scope is True for every tier except 'free'.
    # AYDEN_REFINE_FREE (default off): a refinement (iteration > 1) INHERITS the
    # V1 room/atmosphere — which was already allowed, or freely delegated via
    # Ayden Decide / Signature. Re-running the scope check on it wrongly paywalls
    # a legit in-session edit ("move the table") or an atmosphere switch, even
    # with quota left. So scope-gate only the FIRST vision; quota still caps the
    # total. AYDEN_REFINE_FREE=0 restores the old per-generation scope check.
    _refine_free = os.environ.get("AYDEN_REFINE_FREE", "0") == "1"
    _skip_scope_for_refine = _refine_free and iteration > 1
    if not _decision.bypass_scope and not _skip_scope_for_refine:
        await check_restrictions(
            user_id=current_user.user_id,
            room_type_id=room_type_id,
            atmosphere_id=atmosphere_id,
            let_ai_decide=let_ai_decide,
            surprise_me=surprise_me_flag,
        )
    elif _skip_scope_for_refine:
        log.info("[free-tier] scope check skipped for refinement (iteration=%d)",
                 iteration)

    # ── Billing PR2b (voie a) — GATE WALLET (§2.3), LECTURE SEULE, AVANT le claim ─
    # Le wallet (ledger) est désormais la source d'autorité du quota (remplace
    # usage_log). entitled → bypass (aucune lecture) ; free → available_balance ≥ 1
    # (available + TRIAL si pas encore accordé). AUCUNE écriture ici : le HOLD est
    # posé APRÈS le claim-won → « aucune réservation avant ownership ». deny → 402
    # propre, aucun intent créé, aucun HOLD. FAIL-OPEN sur hoquet DB (reason=fail_open).
    import billing  # noqa: PLC0415 — lazy, évite les surprises d'ordre d'import
    _t_reserve = time.monotonic()
    _gate = await billing.reserve_decision(
        user_id=current_user.user_id, is_free=_decision.consumes_free_quota,
        tier=_decision.tier,   # RC-PR3b — premium = features only ; gén. métrée par le pass
    )
    _reserve_decision_ms = (time.monotonic() - _t_reserve) * 1000.0  # fast-path timing
    if not _gate.allow:
        raise HTTPException(
            status_code=402,
            detail={
                "error_code": "QUOTA_EXHAUSTED",   # compat frontend (GenerationException.quotaExhausted)
                "user_message": (
                    "Your free architectural explorations are complete. "
                    "Unlock unlimited redesigns and continue working with "
                    "your AI Architect."
                ),
                "quota_used": FREE_TIER_LIMIT,
                "quota_limit": FREE_TIER_LIMIT,
                "wallet_available": _gate.wallet_available,
                "reason": _gate.reason,            # insufficient_credits
                "paywall": "pass",                 # PR2b : seul le trial existe → paywall=pass
                "retryable": False,
                "request_id": "",
            },
        )

    # ── Step 1: log request ───────────────────────────────────────────────────
    request_id = client_request_id.strip() or uuid.uuid4().hex
    # [RETRY-PROOF] (logging-only) — whether the client supplied an idempotency
    # key. Two generations sharing one client_request_id ⇒ frontend double-fire
    # of the SAME action; two different ids around one user action ⇒ a timeout
    # re-trigger created a duplicate generation. Lets us tell them apart in prod.
    log.info(
        "[RETRY-PROOF] request_id=%s  trigger=%s  client_supplied=%s  iteration=%d  session=%s",
        request_id, (generation_trigger or "unknown"),
        bool(client_request_id.strip()), iteration, session_id or "(none)",
    )
    # [INTENT-ID] (PR1a, 2026-06-28 — LOGGING ONLY) — observe the normalized INTENT
    # IDENTITY (the user's expressed wish), computed PRE-RESOLUTION (before Ayden
    # Decide / Surprise resolve atmosphere/room downstream at AYDEN_UNIFIED_VISION).
    # NOTE — this is the identity of the INTENT, NOT of the Generation. The system will
    # later use this `iid` to INSTANTIATE-OR-ATTACH a Generation (which gets its OWN id).
    # Pure diagnostic: NO behaviour change, NO enforcement, NO persistence, NO
    # retry/pipeline/frontend impact. Gate of proof (read in prod logs):
    #   • same intent re-fired                       → SAME iid
    #   • switch atmosphere / regenerate(revision++) / re-upload → DIFFERENT iid
    #   • Ayden Decide / Surprise re-fired            → SAME iid (intent is pre-resolution)
    # `revision` = business revision of the wish (read from generation_attempt): a
    # RETRY keeps it (same wish), a REGENERATE bumps it (a new wish). Source: prefer the
    # STABLE anchor (pinned version > V1 upload > immediate URL), hashed — never log the
    # URL. Atmosphere/room use the REQUEST intent, not the resolved style. No sensitive
    # data (no full prompt/URL/key/bytes).
    # Generation Intent v1 — compute_intent_id is the SINGLE authoritative
    # implementation of the identity (spec §3, backend-authoritative) ; it
    # replicates the old inline [INTENT-ID] recipe byte-for-byte so the
    # gate-of-proof holds. PR2 : cet intent_id est ensuite CLAIMÉ (plus bas,
    # après l'idempotence mémoire) — le claim atomique remplace l'observation
    # PR1 (observe_intent_start) et devient la source de vérité anti-double.
    _intent = compute_intent_id(
        user_id=current_user.user_id, session_id=session_id or "",
        source_version_id=source_version_id, original_image_url=original_image_url,
        before_image_url=before_image_url, iteration=iteration,
        room_type_id=room_type_id, room_type=room_type,
        atmosphere_id=atmosphere_id, style_label=style_label, prompt=prompt,
        generation_mode=generation_mode, source_mode=source_mode,
        generation_attempt=generation_attempt,
        let_ai_decide=let_ai_decide, surprise_me_flag=surprise_me_flag,
    )
    log.info(
        "[INTENT-ID] iid=%s user=%s session=%s src=%s iter=%s room=%s action=%s "
        "atmo=%s let_decide=%s surprise=%s revision=%s creq=%s req=%s trigger=%s",
        _intent.id, current_user.user_id[:8], session_id or "(none)", _intent.src_sha1, iteration,
        _intent.room, _intent.action, _intent.atmosphere, let_ai_decide, surprise_me_flag,
        _intent.revision, client_request_id.strip() or "(none)", request_id, generation_trigger or "unknown",
    )
    # ── R2 (dur) — une vraie génération DOIT avoir une vraie session ──────────
    # L'intent_id inclut la session : un session_id 'new'/'' casserait l'identité
    # déterministe (deux gens de la « même » session non-corrélables, GATE 1). On
    # refuse tôt, AVANT tout claim / OpenAI. Le frontend doit résoudre la session
    # réelle avant /generate (invariant PR2b).
    if (session_id or "").strip() in ("new", ""):
        raise HTTPException(
            status_code=400,
            detail="session_id must reference a real session (not 'new')",
        )

    # ── #4 — idempotency guard (defence-in-depth) ─────────────────────────────
    # Only when the client supplied a real idempotency key (a uuid fallback is
    # unique → nothing to dedup). Returns the cached success for a replay; for a
    # concurrent duplicate, waits a BOUNDED ~5s for the first to finish, else
    # proceeds. Never hangs; failures never cached.
    _idem_key = (
        f"{current_user.user_id}:{request_id}"
        if (_idem_enabled() and client_request_id.strip())
        else None
    )
    # #4 defense-in-depth (2026-06-25) — SECONDARY content key. The primary key
    # dedups identical client_request_ids; this catches an accidental frontend
    # re-fire that arrives with a DIFFERENT id but is the SAME logical generation
    # (same user + session + iteration + source + attempt). Success-replay only
    # (the 120s cache) — the in-flight semantics stay on the primary key, so a
    # legitimate retry-after-failure is never blocked. An intentional regenerate
    # bumps `generation_attempt` → different key → allowed (not treated as a dup).
    _src_for_idem = (before_image_url or original_image_url or "").strip()
    _idem_key2 = (
        f"{current_user.user_id}:{session_id}:{iteration}:"
        f"{hashlib.sha1(_src_for_idem.encode('utf-8')).hexdigest()[:12]}:"
        f"{(generation_attempt or '0').strip()}"
        if (_idem_enabled() and _src_for_idem)
        else None
    )
    if _idem_key is not None or _idem_key2 is not None:
        _cached = (
            (_idem_get(_idem_key) if _idem_key is not None else None)
            or (_idem_get(_idem_key2) if _idem_key2 is not None else None)
        )
        if _cached is not None:
            log.info("[IDEMPOTENCY] replay hit — returning cached result "
                     "(request_id=%s  via=%s)", request_id,
                     "primary" if (_idem_key and _idem_get(_idem_key)) else "content_key")
            return _cached
        if _idem_key is not None and _idem_key in _idem_inflight:
            log.info("[IDEMPOTENCY] concurrent duplicate — waiting for the "
                     "in-flight generation (request_id=%s)", request_id)
            for _ in range(50):  # bounded ~5s; never an unbounded wait
                await asyncio.sleep(0.1)
                _cached = (
                    _idem_get(_idem_key)
                    or (_idem_get(_idem_key2) if _idem_key2 is not None else None)
                )
                if _cached is not None:
                    log.info("[IDEMPOTENCY] joined in-flight — returning its "
                             "result (request_id=%s)", request_id)
                    return _cached
            log.info("[IDEMPOTENCY] in-flight wait timed out — proceeding "
                     "(request_id=%s)", request_id)
        if _idem_key is not None:
            _idem_inflight.add(_idem_key)

    # ── Generation Intent v1 — PR2 : CLAIM ATOMIQUE (LOAD-BEARING) ────────────
    # Placé APRÈS l'idempotence mémoire (option B) : si la couche mémoire
    # court-circuitait déjà (replay/attente), elle le fait TOUJOURS à l'identique
    # → le claim n'engage QUE quand on va vraiment générer → zéro régression sur
    # le chemin existant (V1 / switch / re-upload). Le claim remplace l'upsert
    # d'observe_intent_start : INSERT ON CONFLICT → un seul process gagne (won) et
    # exécute OpenAI ; les autres branchent SANS OpenAI (replay / 202 / re-claim).
    # Ferme GATE 2. « Le frontend peut se tromper ; le backend ne doit jamais doubler. »
    _claim_t0 = time.monotonic()
    _claim = await claim_generation_intent(
        intent_id=_intent.id, user_id=current_user.user_id, session_id=session_id,
        iteration=iteration, intent=_intent.intent_dict, client_request_id=request_id,
    )
    _claim_ms = (time.monotonic() - _claim_t0) * 1000.0  # fast-path timing
    log.info(
        "[CLAIM] intent=%s won=%s status=%s reclaim=%d took=%.1fms",
        _intent.id, _claim.won, _claim.status, _claim.reclaim_count,
        (time.monotonic() - _claim_t0) * 1000.0,
    )

    if _claim.won:
        log.info("[CLAIM-OUTCOME] outcome=won total=%d intent=%s",
                 bump_claim("won"), _intent.id)
    else:
        # Doublon observé (preuve GATE 2 + garde le %DUP du dashboard). Best-effort.
        try:
            await asyncio.to_thread(
                lambda: supa.rpc("increment_intent_fire", {"p_intent_id": _intent.id}).execute()
            )
        except Exception:  # noqa: BLE001 — observabilité, jamais fatale
            pass
        if _claim.status == "SUCCEEDED":
            if _claim.result_ref:
                # Replay BYTE-IDENTIQUE : on renvoie le PAYLOAD COMPLET stocké
                # verbatim → le frontend reçoit exactement le même JSON qu'un
                # succès normal, sans savoir qu'il y a eu replay. AUCUN OpenAI,
                # AUCUN re-débit.
                log.info("[CLAIM-OUTCOME] outcome=replay total=%d intent=%s (no OpenAI, no re-bill)",
                         bump_claim("replay"), _intent.id)
                return _claim.result_ref
            # SUCCEEDED sans payload stocké (ex. intent réparé par la
            # réconciliation PR4) : on n'invente PAS un JSON simplifié. On renvoie
            # 202 → le frontend re-sonde et réconcilie via la table messages.
            log.info("[CLAIM-OUTCOME] outcome=replay_no_payload total=%d intent=%s → 202",
                     bump_claim("replay_no_payload"), _intent.id)
            return JSONResponse(
                status_code=202, content={"status": "running", "intent_id": _intent.id}
            )
        if _claim.status == "RUNNING":
            # Une exécution est déjà en cours pour cette intention (2 devices, 2
            # taps, retry timeout). Personne d'autre ne relance OpenAI.
            log.info("[CLAIM-OUTCOME] outcome=running total=%d intent=%s → 202",
                     bump_claim("running"), _intent.id)
            return JSONResponse(
                status_code=202, content={"status": "running", "intent_id": _intent.id}
            )
        if _claim.status in ("FAILED", "FAILED_TERMINAL"):
            # Retry délibéré du MÊME intent : re-claim BORNÉ FAILED→RUNNING (max 3).
            # FAILED_TERMINAL n'est jamais re-claim (reclaim_intent le refuse par
            # `and status='FAILED'`). La transition est atomique (row-lock DB).
            _re = await reclaim_generation_intent(intent_id=_intent.id, max_reclaims=3)
            if not _re.won:
                log.info(
                    "[CLAIM-OUTCOME] outcome=failed_refused total=%d intent=%s status=%s reclaim=%d",
                    bump_claim("failed_refused"), _intent.id, _claim.status, _claim.reclaim_count,
                )
                return JSONResponse(
                    status_code=200,
                    content={"status": _claim.status.lower(), "intent_id": _intent.id},
                )
            log.info("[CLAIM-OUTCOME] outcome=reclaim_won total=%d intent=%s reclaim=%d",
                     bump_claim("reclaim_won"), _intent.id, _re.reclaim_count)
            # on possède l'intent (RUNNING) → on continue vers OpenAI.

    # ── won (ou re-claimed) → on POSSÈDE l'intent (RUNNING) ───────────────────
    # Billing reserve (déplacé depuis observe_intent_start) : TRIAL(+3 1re gen) +
    # HOLD(-1). PURE RELAY, best-effort, idempotent, AUCUN gate ; ne casse jamais
    # /generate (règle Billing PR1). Seul le GAGNANT réserve → pas de double HOLD.
    # ── P0a-bis (2026-07-10) — RÉSERVATION ATOMIQUE (gate+HOLD) = AUTORITÉ de génération ──
    # Le gagnant du claim tente un HOLD ATOMIQUE (billing_try_hold : advisory-lock par
    # user + HOLD conditionnel solde≥1, 1 transaction). reserve_decision (plus haut) était
    # INDICATIF (fast-fail + /me/status) ; ICI est le VRAI droit : OpenAI ne part QUE si
    # granted=true. Ferme la course concurrence (N /generate concurrents à intents distincts
    # ne peuvent plus sur-consommer le bucket). Idempotent (hold:<intent> → reclaim/replay
    # ne re-débitent pas). FAIL-OPEN dans le wrapper (un hoquet DB ne bloque jamais).
    import billing  # noqa: PLC0415 — lazy
    _t_hold = time.monotonic()
    _hold = await billing.try_hold(
        user_id=current_user.user_id, intent_id=_intent.id, tier=_decision.tier, supa=supa)
    _hold_ms = (time.monotonic() - _t_hold) * 1000.0  # fast-path timing
    if not _hold.get("granted"):
        _hreason = _hold.get("reason") or "insufficient_credits"
        # L'intent est RUNNING (claim gagné) mais AUCUN crédit réservé → on le TERMINALISE
        # (pas de RUNNING fantôme) et on refuse AVANT OpenAI → aucun coût, aucune image.
        try:
            await observe_intent_end(
                _intent.id, "FAILED",
                error={"error_code": "ATOMIC_DENY", "reason": _hreason}, supa=supa)
        except Exception:  # noqa: BLE001 — best-effort
            pass
        if _idem_key is not None:
            _idem_inflight.discard(_idem_key)
        if _hreason == "atomic_hold_missing":
            # RPC billing_try_hold absente (fenêtre deploy AVANT apply-SQL) : ce N'EST PAS
            # un paywall → 503 transitoire (retryable), pas de fausse "quota exhausted".
            log.error("[BILLING-ATOMIC] deny intent=%s reason=atomic_hold_missing → 503 (SQL à appliquer)",
                      _intent.id)
            raise HTTPException(
                status_code=503,
                detail={"error_code": "BILLING_UNAVAILABLE",
                        "user_message": "We're finishing an update. Please try again in a moment.",
                        "retryable": True, "request_id": request_id})
        log.info("[BILLING-ATOMIC] deny intent=%s reason=%s → 402 avant OpenAI (0 coût)", _intent.id, _hreason)
        raise HTTPException(
            status_code=402,
            detail={
                "error_code": "QUOTA_EXHAUSTED",
                "user_message": (
                    "Your free architectural explorations are complete. "
                    "Unlock unlimited redesigns and continue working with your AI Architect."),
                "quota_used": FREE_TIER_LIMIT, "quota_limit": FREE_TIER_LIMIT,
                "wallet_available": _hold.get("total_after") or 0,
                "reason": _hreason, "paywall": "pass", "retryable": False, "request_id": request_id,
            },
        )

    # Issue 13 — HOLD acquis : à partir d'ici, toute sortie non terminalisée doit
    # relâcher. Effacé après l'observation SUCCEEDED (voir plus bas).
    setattr(request.state, _HOLD_STATE_ATTR, _intent.id)

    # ── Wave 5.17b — Reserve quota slot BEFORE the OpenAI call ──────────────
    # INSERTs a 'in_progress' usage_log row. Counts immediately against the
    # user's quota — closes the parallel-request race. Confirmed on OpenAI
    # success (status='success'), refunded on every error path
    # (status='failed' — quota slot returned to the user).
    _reservation_id = None
    if _decision.consumes_free_quota:
        # ONLY the 'free' tier consumes the usage_log quota. admin/premium and
        # promo (limited/unlimited) are off-ledger — so a promo that later
        # expires leaves the free quota intact. promo_limited consumes from its
        # OWN ledger via consume_promo_generation on success (below).
        _reservation_id = await reserve_generation(
            user_id=current_user.user_id,
            session_id=session_id,
            request_id=request_id,
        )
    _req_start = time.monotonic()
    # ── CORRECTIF PERF fast-path — la décomposition du pré-vol est REPLIÉE dans le
    #    [PERF SUMMARY] unique de fin de handler (via preflight_breakdown) : AUCUN log.info
    #    supplémentaire systématique par génération, et AUCUN user_id (le résumé ne porte
    #    que request_id + timings). identity_access est FOLDÉ dans access_resolver_ms
    #    (gather parallèle) → son coût séquentiel propre = 0 ; son temps individuel reste
    #    tracé par [ACCESS-TIMING] fetch_identity_active. pre_openai_ms == preflight_ms
    #    (déjà émis par le résumé). Les captures time.monotonic locales sont négligeables.
    _preflight_breakdown = (
        f"ownership_ms={_ownership_ms:.0f} access_resolver_ms={_access_resolver_ms:.0f} "
        f"reserve_decision_ms={_reserve_decision_ms:.0f} claim_ms={_claim_ms:.0f} "
        f"hold_ms={_hold_ms:.0f}"
    )
    _timer = PipelineTimer(request_id)
    _payload_bytes_est = 0
    log.info("=== /generate called ===")
    log.info("  request_id    : %s", request_id)
    log.info("  session_id    : %s", session_id)
    log.info("  style_label   : %s", style_label)
    log.info("  room_type     : %s", room_type or "(none)")
    log.info("  iteration     : %d", iteration)
    # Wave 5.5.14c — bimodal intent routed conditionally. Strip applied only
    # when BIMODAL_ENABLED env var is truthy AND generation_mode=="preserve".
    # Unknown values normalised to "preserve" (today's behaviour).
    if generation_mode not in ("preserve", "creative"):
        generation_mode = "preserve"
    from prompt_engine.atmosphere_dna.bimodal_classifier import is_bimodal_enabled
    log.info(
        "  mode          : %s  (BIMODAL_ENABLED=%s — strip %s)",
        generation_mode,
        is_bimodal_enabled(),
        "ACTIVE" if (is_bimodal_enabled() and generation_mode == "preserve") else "INACTIVE",
    )
    log.info("  prompt        : %s", prompt or "(empty)")
    log.info("  before_url    : %s", before_image_url[:80] + "..." if len(before_image_url) > 80 else before_image_url)
    log.info("  original_url  : %s", (original_image_url[:80] + "...") if len(original_image_url) > 80 else (original_image_url or "(not provided)"))
    log.info(
        "[GenerationProfile] mode=%s  quality=%s  input_fidelity=%s  "
        "size=%s  max_attempts=%d  compact_prompts=%s",
        profile.name, profile.quality, profile.input_fidelity,
        profile.size_override or "auto", profile.max_attempts, profile.compact_prompts,
    )

    # ── Step 2: fetch source image (Wave 4.7.3 — source selection) ───────────
    # VISUAL/DESIGN SOURCE vs ARCHITECTURAL TRUTH are now separate concepts:
    #   - V1 always edits the ORIGINAL uploaded photo.
    #   - V2+ default = LATEST generated vision (design continuity), NOT original.
    #   - source_mode=ORIGINAL restarts from the original photo.
    #   - source_mode=SPECIFIC_VERSION continues from a chosen prior version.
    # original_image_url + structural_identity remain the authoritative
    # architectural truth (injected as text), never conflated with the visual
    # source. Legacy clients (no source_mode/versions) get the V2+ LATEST default.
    _versions = parse_versions(versions)

    # (2026-06-22) ONE source-record identification, shared by:
    #   • axis C — previous atmosphere (the source vision's atmosphere), and
    #   • axis β — lineage_customized (the source vision's cumulative flag).
    # The "source record" is the vision this generation is edited FROM: a
    # client-pinned prior vision (branch / continue-from-vision) by id, else the
    # linear chain tail (LATEST). No lineage walk, no parallel source logic.
    _src_vid = (source_version_id or "").strip()
    _src_record = (record_for_version(_versions, _src_vid) if _src_vid
                   else latest_record(_versions))
    _src_basis = ("source-version" if (_src_vid and _src_record)
                  else "linear-tail" if _src_record else "none")

    # axis C — previous atmosphere (language/phrasing-proof; chat-text regex
    # fails for AI-chosen atmospheres). Fed to BOTH switch evaluations so a
    # switch after an AI-chosen V1 is seen as REBOOT_FRESH, not INCREMENTAL.
    _ledger_prev_atmo_id = (
        label_to_atmosphere_id(_src_record.atmosphere)
        if (_src_record and _src_record.atmosphere) else ""
    )

    # axis β — the SOURCE vision's lineage_customized verdict (read value).
    # None when: no ledger, source not found, or a pre-β record (field unset) →
    # resolver falls back to the legacy history scan (never silently FRESH).
    # The READ is flag-gated (LINEAGE_CUSTOM_FLAG); the WRITE below always runs
    # so ledgers populate the field for a smooth migration.
    # Default ON (2026-06-22) — device-validated A/B/D (pristine→FRESH, real
    # spatial edit→CUSTOMIZED, sibling branch isolated). Set LINEAGE_CUSTOM_FLAG=0
    # as a kill-switch (→ legacy detect_history_customizations). WRITE always runs.
    _lineage_flag_on = os.environ.get("LINEAGE_CUSTOM_FLAG", "1") == "1"
    _src_lineage_customized = (
        _src_record.lineage_customized
        if (_src_record is not None and _src_record.lineage_customized is not None)
        else None
    )
    _explicit_customized = _src_lineage_customized if _lineage_flag_on else None
    if iteration > 1:
        _cd_basis = ("lineage-flag" if _explicit_customized is not None
                     else "legacy-history")
        _cd_reason = ("" if _explicit_customized is not None
                      else (" reason=flag_off" if not _lineage_flag_on
                            else " reason=no_ledger" if not _versions
                            else " reason=source_not_found" if _src_record is None
                            else " reason=missing_lineage_field"))
        log.info(
            "[SwitchPrev] iteration=%d basis=%s src_vid=%s ledger_size=%d → prev_atmo=%s",
            iteration, _src_basis, _src_vid or "(none)", len(_versions),
            _ledger_prev_atmo_id or "(none)",
        )
        log.info(
            "[CustomDetect] basis=%s%s src=%s lineage_customized=%s",
            _cd_basis, _cd_reason, (_src_record.version_id if _src_record else "(none)"),
            ("(legacy)" if _explicit_customized is None else _explicit_customized),
        )

    # ── Wave 5.3 — atmosphere-switch source-mode override ────────────────────
    # On a PURE atmosphere switch (V2+, atmosphere differs from history's V1,
    # AND no user customizations detected in history), override source_mode
    # to ORIGINAL so the model edits the original uploaded photo — producing
    # a fresh V1-equivalent in the new atmosphere instead of editing the
    # previous-vision's pixels (which baked the old atmosphere's furniture
    # identity into the input). Customized switches keep source_mode=LATEST
    # so user-approved spatial changes (added bed, moved TV, etc.) survive
    # the atmosphere switch. Honors an explicit client source_mode — never
    # overrides if the client already chose one. v2-composer only (the v1
    # frozen composer has no switch-awareness, so the override would create
    # a prompt↔image mismatch under v1).
    _switch_override_applied = False
    if (
        _COMPOSER_V2_ACTIVE
        and iteration > 1
        and not source_mode.strip()
    ):
        try:
            _history_list_for_switch = json.loads(history) if history else []
            if not isinstance(_history_list_for_switch, list):
                _history_list_for_switch = []
        except (ValueError, TypeError):
            _history_list_for_switch = []
        _switch_atmos_id = label_to_atmosphere_id(style_label)
        _strategy, _prev_id, _has_custom = _v2_resolve_switch_strategy(
            _history_list_for_switch, _switch_atmos_id, iteration,
            _ledger_prev_atmo_id, _explicit_customized,
        )
        log.info(
            "[SwitchDetect] iteration=%d current=%s ledger_prev=%s customized=%s → strategy=%s prev=%s",
            iteration, _switch_atmos_id, _ledger_prev_atmo_id or "(none)",
            ("(legacy)" if _explicit_customized is None else _explicit_customized),
            _strategy.value, _prev_id or "(none)",
        )
        if _strategy.value == "REBOOT_FRESH":
            # Wave 5.21 EXPERIMENT (2026-06-01, TEMPORARY) — V1 anchor.
            # On a PURE atmosphere switch (no customizations in history), pin
            # the image source to V1 (vision_number == 1) instead of LATEST.
            # Rationale (Wave 5.21b audit, Section G) :
            #   • V1 was generated at medium+high — a clean architectural
            #     reference, single-cascade-step from the original photo.
            #   • LATEST on V4+ would cascade from V3 which itself cascaded
            #     from V2 — quality decay compounds across deep atmosphere-
            #     shopping sessions.
            #   • REBOOT_CUSTOMIZED branch (any prior customization) is
            #     unchanged — keeps source=LATEST to preserve user spatial
            #     changes. Confirmed safe: detect_history_customizations is
            #     sticky-True once any customization exists, so this block
            #     is unreachable after a custom edit.
            # Robustness: select by vision_number == 1 (not index [0]) to
            # survive parse_versions silent-skip on corrupt entries.
            # Multi-upload fix (2026-06-12): scan the ledger REVERSED so we pin
            # the V1 of the CURRENT lineage. A mid-session re-upload resets the
            # iteration counter, so its fresh V1 is ALSO vision_number==1 — the
            # ledger then holds several vn==1 entries. The forward scan pinned
            # the FIRST (the original upload's V1 → wrong space); reversed pins
            # the most recent V1 = the re-uploaded lineage the user is in.
            _v1 = next(
                (v for v in reversed(_versions) if v.vision_number == 1),
                None,
            )
            if _v1 and _v1.generated_image_url:
                source_mode = "SPECIFIC_VERSION"
                source_version_id = _v1.version_id
                _switch_override_applied = True
                log.info(
                    "[Wave5.21-EXPERIMENT] REBOOT_FRESH detected — "
                    "prev=%s new=%s customizations=False "
                    "→ source pinned to V1 (v_id=%s) — cascade-free anchor",
                    _prev_id, _switch_atmos_id, _v1.version_id,
                )
            else:
                log.info(
                    "[Wave5.21-EXPERIMENT] REBOOT_FRESH detected — "
                    "prev=%s new=%s but V1 entry missing/empty "
                    "→ fallback to LATEST (ledger_size=%d)",
                    _prev_id, _switch_atmos_id, len(_versions),
                )
        elif _strategy.value == "REBOOT_CUSTOMIZED":
            log.info(
                "[Wave5.3] customized atmosphere SWITCH detected — "
                "prev=%s new=%s customizations=True "
                "→ source_mode kept as LATEST (preserve user changes)",
                _prev_id, _switch_atmos_id,
            )

    _resolved = resolve_source(
        source_mode=source_mode,
        source_version_id=source_version_id,
        iteration=iteration,
        original_image_url=original_image_url,
        before_image_url=before_image_url,
        versions=_versions,
    )
    log.info("--- fetching source image ---")
    # Variable name preserved (validator/source-inspection compatibility).
    generation_image_url = _resolved.image_url
    log.info(
        "  source: type=%s requested=%r resolved=%s version_id=%r "
        "(iteration=%d, original_provided=%s, ledger=%d)",
        _resolved.source_type, _resolved.mode_requested or "(none)",
        _resolved.mode_resolved, _resolved.source_version_id or "(n/a)",
        iteration, bool(original_image_url), len(_versions),
    )
    # [LINEAGE-PROOF] (logging-only) — show the URL TAILS so a cross-lineage leak
    # is visible: if resolved_url != before_url/original_url for an edit the user
    # pinned via Edit-From-Vision, the wrong apartment was selected. implicit_latest
    # = LATEST was chosen as a SILENT default (no explicit pin) on iteration>1 —
    # the suspected root cause when a re-upload purged the version ledger.
    _implicit_latest = (
        _resolved.mode_resolved == "LATEST"
        and (_resolved.mode_requested or "").strip().upper() != "LATEST"
    )
    log.info(
        "  [LINEAGE-PROOF] resolved_url=…%s before_url=…%s original_url=…%s "
        "source_version_id=%r implicit_latest=%s request_id=%s",
        (generation_image_url or "")[-48:], (before_image_url or "")[-48:],
        (original_image_url or "")[-48:], source_version_id or "(none)",
        _implicit_latest, request_id,
    )
    _t_stage = time.monotonic()
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            r = await client.get(generation_image_url)
            log.info("  HTTP %s", r.status_code)
            r.raise_for_status()
            image_bytes = r.content
            _fetch_s = time.monotonic() - _t_stage
            _timer.record("image_fetch", _fetch_s, size_bytes=len(image_bytes))
            log.info("  size: %d bytes (%.1f KB)", len(image_bytes), len(image_bytes) / 1024)
            log.info("[PERF] stage=image_fetch  duration_ms=%.0f  size_bytes=%d",
                     _fetch_s * 1000, len(image_bytes))
    except Exception as exc:
        log.error("  FAILED: %s: %s", type(exc).__name__, exc)
        log.error(traceback.format_exc())
        # PATCH 3 (2026-07-16) — RELEASE le HOLD posé pré-OpenAI AVANT de propager. Cette erreur
        # survient APRÈS le HOLD atomique (billing.try_hold @ _hold) et AVANT le 1er appel OpenAI :
        # sans transition terminale, le HOLD(-1) reste ORPHELIN (compteur premium décrémenté)
        # jusqu'au reconciler (~12 min). On émet EXACTEMENT la même paire terminale que la voie
        # "OpenAI épuisé" (fail_generation + observe_intent_end FAILED, cf. plus bas) → le HOLD est
        # relâché (net 0), aucune image produite, aucun coût. Ce `raise` SORT de /generate (capté
        # par _generation_error_handler) → chemin MUTUELLEMENT EXCLUSIF avec la voie OpenAI → aucun
        # double-RELEASE. Best-effort : le release ne doit JAMAIS masquer l'échec source.
        try:
            if _reservation_id is not None:
                await fail_generation(_reservation_id)
                _reservation_id = None
            await observe_intent_end(
                _intent.id, "FAILED",
                error={"type": "pre_openai", "error_code": "IMAGE_FETCH_FAILED"},
                is_free=_decision.consumes_free_quota,
            )
        except Exception:  # noqa: BLE001 — le release est best-effort ; ne masque pas le raise
            log.exception("[BILLING] pre-OpenAI hold release failed (intent=%s)", _intent.id)
        raise GenerationError(
            error_code="IMAGE_FETCH_FAILED",
            user_message="We couldn't load your photo. Please try again.",
            retryable=False,
            request_id=request_id,
            status_code=400,
            session_id=session_id,
        )

    # ── Step 3: parse conversation history ───────────────────────────────────
    history_messages: list[dict] = []
    if history:
        try:
            history_messages = json.loads(history)
        except Exception:
            log.warning("  Could not parse history JSON — ignoring")

    # Phase 3 — normalize FR/KM user history to English for the keyword-matching
    # consumers (parse_history + accumulate_refinements below). EN / flag-off ->
    # SAME object (history byte-identical, English-freeze preserved).
    _t_hist = time.monotonic()
    history_messages_en = await normalize_history_to_english(
        openai, history_messages, ui_locale,
        enabled=os.environ.get("MULTILINGUAL_NORMALIZE", "0") == "1",
    )
    refinement_state = parse_history(history_messages_en, iteration)
    _timer.record("history_norm", time.monotonic() - _t_hist)  # PERF: multilingual history normalize + parse
    log.info(
        "  refinement — keep:%d add:%d remove:%d directions:%d",
        len(refinement_state.keep), len(refinement_state.add),
        len(refinement_state.remove), len(refinement_state.directions),
    )

    # ── Step 4: vision analysis of source image (GPT-4o-mini) ────────────────
    # detail="high" gives the model full image resolution understanding.
    # The prompt extracts structural anchors (windows, camera, perspective, depth)
    # so the generation prompt can ground geometry preservation in actual data
    # rather than relying solely on textual lock instructions.
    log.info("--- GPT-4o-mini vision analysis (detail=high) ---")
    room_description = ""
    _t_vision = time.monotonic()
    # Wave 4.7.0 Step 1 (runtime isolation): mobile_mvp_baseline disables vision
    # analysis for FIRST_VISION (iteration == 1). Wave 4.6.1 already removed
    # SOURCE_SPACE from the FV prompt, so room_description is unused for FV anyway —
    # this skip has zero prompt impact and only removes one GPT-4o-mini call.
    #
    # Wave 5.5.7c (2026-05-21) — extended skip to ALL iterations on profiles
    # where `vision_analysis_fv=False` (i.e. mobile_mvp_baseline). Rationale:
    # vision_analysis's only downstream impact on V2/V3 prompts is via
    # `detect_anchors(room_description)` which produces a redundant
    # architectural_anchors clause (already covered by the persistent
    # STRUCTURAL_IDENTITY token from V1 capture). Empirically: V1 on this
    # profile already runs without vision_analysis and produces the best
    # quality (proven by morning's V1 vs V2/V3 comparison). The asymmetry
    # `iteration == 1` only-skip created prompt drift (+100 chars on V2/V3
    # from architectural_anchors clause that V1 doesn't have), which was
    # the root of the post-Wave-5.5.6 V1 vs V2/V3 byte-mismatch the user
    # observed. Global skip:
    #   • Makes V1 and V2/V3 prompts truly byte-identical on pure switches
    #   • Saves 3-8s latency per V2+ generation
    #   • Saves ~$0.001-0.003 OpenAI cost per V2+ generation
    #   • Aligns with the "naked baseline" philosophy of the profile
    # No quality regression expected (V1 evidence). let_ai_decide and
    # surprise_me features (which use room_description) are V1-only flows
    # and weren't functional on mobile_mvp_baseline before this change either.
    # Rollback = revert to `(not profile.vision_analysis_fv) and iteration == 1`.
    _skip_vision_fv = not profile.vision_analysis_fv
    try:
        if _skip_vision_fv:
            log.info(
                "  vision analysis SKIPPED (profile=%s, iteration=%d — Wave "
                "5.5.7c global skip on mobile_mvp_baseline; room_description "
                "stays empty for all generations on this profile)",
                profile.name, iteration,
            )
        else:
            b64_source = base64.b64encode(image_bytes).decode()
            analysis = await openai.chat.completions.create(
                model="gpt-4o-mini",
                messages=[{
                    "role": "user",
                    "content": [
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{b64_source}",
                                "detail": "high",
                            },
                        },
                        {
                            "type": "text",
                            "text": (
                                "Analyze this room for an architectural interior photographer. "
                                "Provide a structured description covering: "
                                "(1) Room type and primary function. "
                                "(2) Window count, approximate positions (left/center/right/back wall), "
                                "and whether they are floor-to-ceiling or standard height. "
                                "(3) Camera angle: eye-level, slightly high, or slightly low. "
                                "(4) Perspective: single vanishing point (straight-on) or two-point (corner view). "
                                "(5) Visible spatial depth: shallow (flat wall), medium, or deep (visible secondary spaces). "
                                "(6) Ceiling: flat, vaulted, exposed beams, or height impression (low/normal/high). "
                                "(7) Key structural anchors: any columns, open doorways, kitchen island, fireplace wall. "
                                "Be factual and concise — this is used as generation guidance, not prose description. "
                                "Max 4 sentences."
                            ),
                        },
                    ],
                }],
                max_tokens=220,
            )
            room_description = analysis.choices[0].message.content.strip()
            log.info("  room: %s", room_description)
    except Exception as exc:
        log.warning("  Vision analysis failed (non-fatal): %s: %s", type(exc).__name__, exc)
    finally:
        _vision_s = time.monotonic() - _t_vision
        _timer.record("vision_analysis", _vision_s)
        log.info("[PERF] stage=vision_analysis  duration_ms=%.0f", _vision_s * 1000)

    # ── Step 4b: resolve PERSISTENT structural identity (Wave 4.7.2) ──────────
    # Capture ONCE, reuse forever. Resolution order:
    #   1. client-persisted token  -> reuse (V2/V3/V4: ZERO model calls)
    #   2. V1 (iteration == 1), no token:
    #        a. deterministic parse of room_description (free, if any text)
    #        b. else ONE structural capture call (V1-only gate; provider boundary)
    #   3. V2+ with no token:
    #        a. deterministic parse of room_description (free, if any text)
    #        b. Wave 5.5.12 recovery — capture from image_bytes when client lost
    #           the persisted token (hot reload, app reopen, session restore,
    #           navigation reset). image_bytes is the ORIGINAL photo because
    #           Wave 5.3 forces source_mode=ORIGINAL on REBOOT_FRESH pure
    #           switches, so the capture is V1-equivalent.
    # Graceful: EMPTY_IDENTITY -> "" clause -> falls back to Wave 4.7.1 behaviour.
    _t_sid = time.monotonic()  # PERF: time the full structural-identity resolution
    _si_source = "none"
    _struct_calls = 0  # real gpt-4o structural captures on this request (PERF)
    structural_id_obj: ApartmentStructuralIdentity = EMPTY_IDENTITY
    # Structural-capture kill-switch (2026-07-07). Benched OFF by default: 45
    # single-shot + 18 lineage images (V1→switch→refine) showed NO architecture-
    # preservation gain vs the 4–84s V1 latency + 2 gpt-4o calls the capture adds.
    #   off    = zero passport RECEIVED, captured, extracted, recovered, reused or
    #            injected — even if the client still POSTs an old token; empty
    #            clause; empty token echoed back so stale passports die.
    #   double = strict historical behaviour (the whole chain below) — rollback.
    # Unknown value => fail-safe to off with an explicit warning.
    _cap_mode = _resolve_structural_capture_mode()
    if _cap_mode == "off":
        structural_id_obj = EMPTY_IDENTITY
        _si_source = "disabled"
        log.info(
            "[StructCapMode] off — capture disabled (client token ignored, "
            "0 calls, empty passport, no cache, no recovery)"
        )
    elif structural_identity.strip():
        structural_id_obj = from_token(structural_identity)
        _si_source = "client_session" if structural_id_obj.is_present else "none"
    elif iteration == 1:
        structural_id_obj = extract_from_description(room_description)
        if structural_id_obj.is_present:
            _si_source = "text_v1"
        else:
            # Wave 4.9.3 perf — structural-identity capture cache (flag-gated).
            # Same source photo → reuse the cached identity token and skip the
            # ~5-7s vision capture below. from_token() is the exact round-trip
            # V2+ already trusts, so the prompt stays byte-identical.
            _v1_cached = False
            _img_key = (
                _struct_id_cache_key(image_bytes)
                if (_struct_id_cache_enabled() and image_bytes) else None
            )
            if _img_key is not None:
                _cached_tok = _struct_id_cache_get(_img_key)
                if _cached_tok is not None:
                    structural_id_obj = from_token(_cached_tok)
                    _si_source = (
                        "vision_capture_v1_cached"
                        if structural_id_obj.is_present else "none"
                    )
                    _v1_cached = True
                    log.info(
                        "[StructIdCache] HIT key=%s facts=%d (skipped ~5-7s capture)",
                        _img_key[:12], structural_id_obj.fact_count,
                    )
            if not _v1_cached:
                # Wave 5.24 (2026-06-03) — run 2× full structural captures in
                # parallel + safe-union merge. Supersedes Wave 5.23 mini
                # orientation consensus on the V1 FV path : 2 full captures
                # naturally provide a 2-vote orientation consensus AND enrich
                # the complementary architectural facts (interior door, kitchen
                # visibility, ceiling signature, etc.) — empirically these
                # additional facts correlate inversely with wall hallucination
                # rate (3 facts = 40%, 5+ facts = 0%).
                #
                # Wave 5.23 mini consensus remains in code as rollback assets
                # and is still wired in the recovery path below.
                #
                # Cost : +$0.0025 per V1 (~6% of total V1 cost). Latency : zero
                # via parallel asyncio.gather. Merge logic in
                # structural_identity.safe_union_merge — drops contradictory
                # facts (missing > wrong principle).
                _cap_a, _cap_b = await asyncio.gather(
                    _capture_structural_text(image_bytes),
                    _capture_structural_text(image_bytes),
                )
                _struct_calls += 2  # PERF — two real structural captures (parallel)
                _identity_a = extract_from_description(_cap_a)
                _identity_b = extract_from_description(_cap_b)
                structural_id_obj, _merge_decisions = safe_union_merge(
                    _identity_a, _identity_b,
                )
                # Telemetry — empirical validation depends on these logs.
                log.info(
                    "[Wave5.24] capture_A facts=%d capture_B facts=%d merged facts=%d",
                    _identity_a.fact_count,
                    _identity_b.fact_count,
                    structural_id_obj.fact_count,
                )
                _added = [
                    k for k, v in _merge_decisions.items()
                    if v in ("additive_a", "additive_b")
                ]
                _stripped = [
                    k for k, v in _merge_decisions.items()
                    if v == "contradict_position_stripped"
                ]
                _kept = [
                    k for k, v in _merge_decisions.items()
                    if v in ("kept_a_longer", "kept_b_longer")
                ]
                if _added:
                    log.info("[Wave5.24] additive merged fields: %s", _added)
                if _stripped:
                    log.info(
                        "[Wave5.24] contradict position stripped: %s", _stripped,
                    )
                if _kept:
                    log.info(
                        "[Wave5.24] non-position disagreement, kept longer: %s",
                        _kept,
                    )
                _si_source = "vision_capture_v1" if structural_id_obj.is_present else "none"
                if _img_key is not None and structural_id_obj.is_present:
                    _struct_id_cache_put(_img_key, to_token(structural_id_obj))
                    log.info(
                        "[StructIdCache] STORE key=%s facts=%d",
                        _img_key[:12], structural_id_obj.fact_count,
                    )
    else:
        structural_id_obj = extract_from_description(room_description)
        if structural_id_obj.is_present:
            _si_source = "text_fallback"
        else:
            # Wave 5.5.12 — recovery from frontend token loss. iteration>1 with
            # empty structural_identity reaching here means the client lost the
            # round-trip state (hot reload, app reopen, session restore, etc.).
            # Without anchors the prompt is architecturally generic and
            # gpt-image-1 hallucinates walls / loses kitchen / restructures
            # facade. Recovery: re-run the V1 capture against the source image
            # bytes (ORIGINAL photo on REBOOT_FRESH per Wave 5.3, so the capture
            # is V1-equivalent). Cost: +$0.001-0.003 and +1-2s when triggered;
            # 0 cost on the healthy-token path. Scope: backend-only, uses the
            # existing _capture_structural_text (Wave 5.5.11 prompt unchanged),
            # no DNA touch, no composer touch, no budget change.
            log.info(
                "[StructuralRecovery] missing structural_identity on "
                "iteration>1 (iteration=%d, token_chars=0), regenerating "
                "from source image bytes",
                iteration,
            )
            # Wave 5.23 (2026-06-03) — same parallel capture + mini consensus
            # pattern as the V1 path above. Applies to recovery cases (token
            # lost on hot reload / app reopen) so the regenerated identity
            # benefits from the same orientation stabilization.
            _cap_text, _orient_consensus = await asyncio.gather(
                _capture_structural_text(image_bytes),
                _resolve_orientation_consensus(image_bytes),
            )
            _struct_calls += 1  # PERF — one real structural capture (recovery)
            structural_id_obj = extract_from_description(_cap_text)
            if (
                _orient_consensus is not None
                and structural_id_obj.dominant_opening
            ):
                structural_id_obj = _patch_dominant_opening_position(
                    structural_id_obj, _orient_consensus,
                )
            _si_source = (
                "vision_capture_recovery"
                if structural_id_obj.is_present else "none"
            )

    structural_identity_token = to_token(structural_id_obj)
    # PERF: V1 = the ~7s parallel vision capture (vision_capture_v1); V2+ =
    # near-0 token decode; recovery path = a re-capture when the token was lost.
    # OFF = 0 work (kill-switch); force struct_id_ms=0 so the metric is exact.
    _struct_id_ms = 0.0 if _cap_mode == "off" else (time.monotonic() - _t_sid) * 1000.0
    _timer.record("struct_id", _struct_id_ms / 1000.0)
    # effective_chars = the identity ACTUALLY applied to the prompt (0 in off even
    # if the client POSTed an old token, since it is ignored above).
    _si_effective_chars = 0 if _cap_mode == "off" else len(structural_identity_token)
    log.info(
        "[StructCapMode] structural_capture_mode=%s  structural_identity_input_chars=%d  "
        "structural_identity_effective_chars=%d  structural_identity_output_chars=%d  "
        "structural_calls_count=%d  struct_id_ms=%.0f  structural_identity_source=%s",
        _cap_mode, len(structural_identity or ""), _si_effective_chars,
        len(structural_identity_token), _struct_calls, _struct_id_ms, _si_source,
    )
    log.info(
        "[StructuralIdentity] present=%s  source=%s  facts=%d  token_chars=%d  iteration=%d",
        structural_id_obj.is_present, _si_source,
        structural_id_obj.fact_count, len(structural_identity_token), iteration,
    )

    # ── Step 5a: resolve Let AI Decide + Surprise Me + secondary spaces ──────
    secondary_visible_spaces: list[str] = []
    if secondary_spaces:
        try:
            secondary_visible_spaces = json.loads(secondary_spaces)
        except Exception:
            log.warning("  Could not parse secondary_spaces JSON — ignoring")

    # ── Phase 2: multilingual normalization seam (FR/KM -> English) ──────────
    # Translate the user instruction to canonical English BEFORE any classifier
    # or prompt composition, so the generation engine stays English-internal.
    # EN / flag-off -> strict passthrough (prompt_en IS prompt -> byte-identical).
    # The ORIGINAL `prompt` is kept for reply/caption display (build_vision_caption
    # echoes it in the user's language); only the design pipeline uses prompt_en.
    _t_norm = time.monotonic()
    prompt_en = await normalize_to_english(
        openai, prompt, ui_locale,
        # Perf — iteration==1 (V1) is ALWAYS the English auto-instruction
        # ("Generate the first architectural vision…"), never user FR/KM text, so
        # translating it is a wasted ~1-2s gpt-4o-mini call on the pre-image
        # critical path. Only normalize user-typed V2+ instructions. (Safe: the
        # detector-based skip was rejected — it mislabels accent-less French.)
        enabled=(os.environ.get("MULTILINGUAL_NORMALIZE", "0") == "1" and iteration > 1),
    )
    _timer.record("normalize", time.monotonic() - _t_norm)  # PERF: multilingual prompt normalize (gated iter>1)
    if prompt_en is not prompt:
        log.info("  [normalize] %s->en  %r -> %r", ui_locale, prompt[:60], prompt_en[:60])

    classification = None  # keyword room classifier — corroboration du safety gate
    if let_ai_decide and room_description:
        log.info("--- Let AI Decide: classifying room from vision ---")
        _t_cr = time.monotonic()
        classification = classify_room(
            vision_description=room_description,
            user_prompt=prompt_en,
            room_type_hint=room_type,
        )
        _timer.record("classify_room", time.monotonic() - _t_cr)  # PERF
        room_type = classification.primary_room
        log.info(
            "  classified: %s (confidence=%.2f) secondary=%s reason=%s",
            room_type, classification.confidence,
            classification.secondary_spaces, classification.reasoning,
        )
        for s in classification.secondary_spaces:
            if s not in secondary_visible_spaces:
                secondary_visible_spaces.append(s)

    # #8 — Ayden Decide exterior routing (flag AYDEN_DECIDE_EXTERIOR, default off).
    # Runs only on the delegated path with no room resolved yet (on mobile the
    # full vision is skipped, so room_type stays empty here). One tiny mini call:
    # if the photo is an EXTERIOR, set room_type so its proper exterior DNA is
    # injected (fixes incoherent gardens); interiors keep room_type empty →
    # byte-identical lean behaviour. V2+/explicit-room/surprise flows untouched.
    if (
        let_ai_decide
        and not room_type
        and _de_on  # forced off when unified vision is on (see startup banner)
    ):
        log.info("--- Ayden Decide: interior/exterior detection ---")
        _t_ext = time.monotonic()
        _ext_room = await _classify_exterior_room(image_bytes)
        log.info("  [AydenDecideExterior] result=%r in %.2fs",
                 _ext_room or "interior", time.monotonic() - _t_ext)
        if _ext_room:
            room_type = _ext_room  # → exterior room DNA injected downstream

    # Single Ayden vision pass — ONE gpt-4o call shared by two consumers (no
    # double call): STAGE MODE (room type) + image-driven Surprise Me (atmosphere).
    # Runs only if at least one is needed & enabled. Flag(s) off ⇒ no call ⇒
    # byte-identical.
    _ayden_vision = None
    _want_stage = (
        let_ai_decide and not room_type and iteration == 1
        and os.environ.get("AYDEN_DECIDE_FURNISH", "0") == "1"
    )
    _want_surprise_vision = (
        surprise_me_flag and iteration == 1
        and os.environ.get("SURPRISE_VISION", "0") == "1"
    )
    if _want_stage or _want_surprise_vision:
        log.info("--- Ayden vision pass (stage=%s surprise=%s) ---",
                 _want_stage, _want_surprise_vision)
        _t_v = time.monotonic()
        _ayden_vision = await _classify_ayden(image_bytes)
        log.info("  [AydenVision] room=%r atmo=%r conf=%s reason=%r in %.2fs",
                 _ayden_vision["room"], _ayden_vision["atmosphere"],
                 _ayden_vision["confidence"], _ayden_vision["reason"],
                 time.monotonic() - _t_v)

    # STAGE consumes the room type (Option B: always re-imagine; swap happens after
    # composition; "" exterior/unclear ⇒ preserve).
    _detected_room = _ayden_vision["room"] if (_want_stage and _ayden_vision) else ""
    # Safety gate (RCA 2026-07-08) — un intérieur mal lu en extérieur ne doit pas
    # déclencher un STAGE extérieur destructeur. Corroboration par le classifieur
    # keyword (vision_analysis) ou par une confiance 'low'. Les vrais extérieurs
    # (high/medium conf, aucun signal indoor) passent inchangés. N'agit que sur le
    # chemin STAGE (_detected_room non vide) et uniquement sur un extérieur.
    if _detected_room:
        _gated_room, _gate_reason = resolve_stage_exterior(
            _detected_room, (_ayden_vision or {}).get("confidence", "low"),
            classification.primary_room if classification else "",
            classification.confidence if classification else 0.0,
            _EXTERIOR_ROOMS,
        )
        if _gate_reason:
            log.info("[AydenSafetyGate] %s", _gate_reason)
            _detected_room = _gated_room
    # AYDEN_UNIFIED_VISION — STAGE is an INTERIOR furnish contract; an exterior
    # space must NOT be staged. Route exteriors to PRESERVE: keep _stage_room ""
    # (so apply_stage_mode is skipped) but still propagate the detected room below
    # so its existing DNA applies. When the flag is OFF, _classify_ayden never
    # returns an exterior → _is_exterior is always False → byte-identical to today.
    _is_exterior = _detected_room in _EXTERIOR_ROOMS
    # An exterior room is STAGE-eligible iff it is a validated exterior STAGE room
    # (membership: pool_area, terrace — no env flag, Git is the rollback). Eligible
    # exterior → STAGE (exterior shell-lock); every other exterior → PRESERVE (blank
    # _stage_room). Interiors are unaffected (_is_exterior is False for them).
    _exterior_staged = _is_exterior and is_exterior_stage_room(_detected_room)
    _stage_room = _detected_room if (not _is_exterior or _exterior_staged) else ""
    if _is_exterior:
        log.info("[AydenUnified] exterior detected room=%s → %s", _detected_room,
                 "STAGE (exterior shell-lock)" if _exterior_staged
                 else "PRESERVE (STAGE skipped)")

    # PRIORITY FIX (flag AYDEN_DECIDE_PROPAGATE_ROOM) — propagate the DETECTED
    # interior room so it becomes the official room_type. This reactivates the
    # EXISTING per-atmosphere DNA (build_dna_room_context → furniture_language +
    # TV anchor + room_specific constraints) for the V1 generation AND, via the
    # payload round-trip, for every V2+ switch (which inherits the persisted
    # room). Before: Ayden Decide kept room_type="" → DNA dropped → weak
    # atmosphere + drifting TV. The composer's _normalise_room maps the id
    # (e.g. "living_room") to the DNA key. Default ON (proven perf-neutral,
    # 2026-06-22 bench: room=living_room, dna_room_context 374/418, switches
    # inherit); set AYDEN_DECIDE_PROPAGATE_ROOM=0 as a kill-switch.
    if _detected_room and os.environ.get("AYDEN_DECIDE_PROPAGATE_ROOM", "1") == "1":
        log.info("[AydenDecide] propagate detected room → room_type=%r (was %r) "
                 "— reactivates per-atmosphere DNA (furniture/TV anchor/decor)",
                 _detected_room, room_type or "(none)")
        room_type = _detected_room

    # SPECIFIC_ROOM_STAGE (2026-06-22, flag-gated, MINIMAL) — let a Specific
    # (explicit-room) V1 reuse the existing STAGE contract. Additive + guarded so
    # Ayden Decide stays byte-identical: `not let_ai_decide` excludes the Decide
    # path by construction, `not _stage_room` means Decide didn't already set it,
    # `iteration == 1` is V1-only (no switch/edit/continue). Sets `_stage_room`
    # only (room_type untouched → zero V2+ effect). Interiors via the whitelist;
    # exteriors via is_exterior_stage_room (manual exterior selection now STAGEs at
    # parity with Ayden Decide — see _SPECIFIC_STAGE_ROOMS note).
    # Default ON (2026-06-23, routing device-validated: Living/Kitchen/Bathroom +
    # Bedroom/Office/Entrance via _SPECIFIC_STAGE_MAP); SPECIFIC_ROOM_STAGE=0 is
    # the kill-switch.
    if (not _stage_room and not let_ai_decide and iteration == 1 and room_type
            and os.environ.get("SPECIFIC_ROOM_STAGE", "1") == "1"):
        _sk = "_".join(room_type.strip().lower().split())
        _sk = _SPECIFIC_STAGE_MAP.get(_sk, _sk)  # form label → _STAGE_ITEMS / exterior key (confirmed labels only)
        if _sk in _SPECIFIC_STAGE_ROOMS or is_exterior_stage_room(_sk):
            _stage_room = _sk
            log.info("[SpecificStage] enabled=true room=%r stage_room=%s", room_type, _sk)
        else:
            log.info("[SpecificStage] skipped reason=unsupported_room room=%r", room_type)

    if surprise_me_flag:
        # Room for the compat lookup: explicit room if set, else the vision's guess.
        _room_for_atmo = room_type or ((_ayden_vision or {}).get("room") or "")
        selected_atmosphere = ""
        # Image-driven pick (SURPRISE_VISION): use the AI atmosphere only if it is
        # valid, confident, and not a poor fit for the room (base_compat ≥ 0.45);
        # otherwise fall back to the curated table. Keeps a safe warm_modern path.
        if _want_surprise_vision and _ayden_vision and _ayden_vision["atmosphere"]:
            _ai_atmo = _ayden_vision["atmosphere"]
            _ai_conf = _ayden_vision["confidence"]
            _score = dict(rank_atmospheres(_room_for_atmo)).get(_ai_atmo, 0.0)
            # Ayden Signature draws ONLY from validated atmospheres — an AI pick
            # of Japandi / Nordic is rejected here and falls back to the curated
            # table (which is itself restricted to SIGNATURE_ATMOSPHERES below).
            _in_signature = _ai_atmo in SIGNATURE_ATMOSPHERES
            if _in_signature and _ai_conf != "low" and _score >= 0.45:
                selected_atmosphere = _ai_atmo
                log.info("[Surprise] room=%s ai_reco=%s conf=%s reason=%r "
                         "base_compat=%.2f in_signature=%s → SELECTED %s",
                         _room_for_atmo or "(none)", _ai_atmo, _ai_conf,
                         _ayden_vision["reason"], _score, _in_signature, _ai_atmo)
            else:
                log.info("[Surprise] room=%s ai_reco=%s conf=%s base_compat=%.2f "
                         "in_signature=%s → FALLBACK (%s)",
                         _room_for_atmo or "(none)", _ai_atmo, _ai_conf, _score,
                         _in_signature,
                         "not a validated Ayden Signature atmosphere"
                         if not _in_signature else "conf=low or below floor 0.45")
        if not selected_atmosphere:
            selected_atmosphere = surprise_me(
                room_type=_room_for_atmo,
                vision_description=room_description,
                user_prompt=prompt_en,
                only=list(SIGNATURE_ATMOSPHERES),  # Ayden Signature: validated atmospheres only
            )
            log.info("[Surprise] table fallback (signature-only) → %s", selected_atmosphere)
        log.info("  selected atmosphere: %s", selected_atmosphere)
        style_label = selected_atmosphere.replace("_", " ").title()

    if secondary_visible_spaces:
        log.info("  secondary visible spaces: %s", secondary_visible_spaces)

    # Derive atmosphere_id from the final style_label (after Surprise Me may have changed it)
    atmosphere_id = label_to_atmosphere_id(style_label)
    log.info("  atmosphere_id: %s", atmosphere_id)

    # ── Step 5b: classify intent for response generation ─────────────────────
    _t_ci = time.monotonic()
    intent_class = classify_intent(prompt_en, iteration)
    _timer.record("classify_intent", time.monotonic() - _t_ci)  # PERF
    log.info(
        "  intent: %s  sub_intent: %s",
        intent_class.intent.value, intent_class.sub_intent.value,
    )

    # ── Step 5c: Wave 3.4.1 — classify transformation + clean + enrich ──────────
    _t_ct = time.monotonic()
    transformation_type = classify_transformation(prompt_en, iteration)
    _timer.record("classify_transformation", time.monotonic() - _t_ct)  # PERF
    log.info("--- transformation: %s ---", transformation_type.value)

    # Clean the raw user instruction before injecting into the prompt
    clean_instruction = build_clean_instruction(prompt_en, transformation_type)

    # Build spatial preservation addendum (appended after cleaned instruction)
    spatial_addendum = build_spatial_preservation_addendum(
        transformation_type=transformation_type,
        secondary_spaces=secondary_visible_spaces,
        room_type=room_type,
        atmosphere_id=atmosphere_id,
    )
    enriched_instruction = (
        f"{clean_instruction}\n{spatial_addendum}" if spatial_addendum else clean_instruction
    )
    log.info("  addendum: %d chars  enriched: %d chars", len(spatial_addendum), len(enriched_instruction))

    # ── Step 5d: compose design prompt via engine ─────────────────────────────
    _t_ce = time.monotonic()
    edit_mode = classify_edit_mode(prompt_en, iteration)
    _timer.record("classify_edit_mode", time.monotonic() - _t_ce)  # PERF
    _t_prompt = time.monotonic()

    # Override: LOCAL_EDIT and LAYOUT_CHANGE bypass the structural contract and
    # atmosphere boundary. Functional reassignment and structural changes require
    # those layers — if the edit_mode classifier routes them to LOCAL_EDIT (e.g.,
    # "make the TV area a bedroom" has local signals) or LAYOUT_CHANGE (e.g.,
    # "rearrange the room into a bedroom" has layout signals), elevate to
    # STRUCTURAL_TRANSFORMATION so the full prompt path is used and the
    # spatial/functional constraints are included.
    # Wave 5.13c — extended the elevation to LAYOUT_CHANGE so transformation-type
    # signals override the new layout classification when they conflict.
    if edit_mode in (EditMode.LOCAL_EDIT, EditMode.LAYOUT_CHANGE) and transformation_type in (
        TransformationType.FUNCTIONAL_REASSIGNMENT,
        TransformationType.STRUCTURAL_CHANGE,
        TransformationType.LAYOUT_REINTERPRETATION,
    ):
        log.info(
            "  edit_mode elevated %s → STRUCTURAL_TRANSFORMATION (transformation_type=%s)",
            edit_mode.value, transformation_type.value,
        )
        edit_mode = EditMode.STRUCTURAL_TRANSFORMATION

    log.info("--- edit mode: %s ---", edit_mode.value)

    # Wave 4.7.2: render the persistent identity with the final edit_mode.
    # V1/V2 = facts-only; V3 = facts-only + "only the explicit edit may alter them".
    if iteration <= 1:
        _gen_mode = "V1"
    elif edit_mode == EditMode.STRUCTURAL_TRANSFORMATION:
        _gen_mode = "V3"
    else:
        _gen_mode = "V2"
    # Wave 5.5.14d — the render_clause + render_negative_anchors helpers now
    # accept `generation_mode` so creative mode (BIMODAL_ENABLED=1 + creative)
    # softens the identity clause and drops the negative anchors entirely.
    structural_identity_clause = render_clause(
        structural_id_obj, _gen_mode, generation_mode
    )
    # Wave 4.7.4: negative topology anchors (no-new-wall) — V1/V2/V3, derived
    # ONLY from the persistent identity (architecture-only, leak-guarded). "" when
    # no identity (Task 6 — zero prompt cost on a no-anchor apartment).
    negative_anchors_clause = render_negative_anchors(
        structural_id_obj, generation_mode
    )

    # Wave 4.7.3: structural_permission = this generation is allowed to alter
    # architecture (only V3 / explicit structural request). V1/V2 = False.
    structural_permission = (edit_mode == EditMode.STRUCTURAL_TRANSFORMATION)

    # Wave 4.7.8: accumulate recent unresolved refinements (history + current)
    # into ONE ordered request, so successive compatible asks stack instead of
    # the latest overwriting the prior. Bounded, deterministic, history-only.
    # Wave 4.7.5: localized authorized-change authority (V2+ only). Composer
    # injects it only on Path B/C; LOCAL_EDIT already authorizes via build_local_edit_prompt.
    _t_acc = time.monotonic()
    _acc = accumulate_refinements(history_messages_en, prompt_en)
    _timer.record("accumulate", time.monotonic() - _t_acc)  # PERF
    _acc_src = _acc.text or prompt_en  # fallback to current prompt → zero regression
    _refine_detected, _refine_zone = detect_refinement(_acc_src)
    authorized_changes_clause = build_authorized_changes_clause(_acc_src, iteration)
    log.info(
        "[RefinementAccumulation] append_detected=%s  replace_detected=%s  "
        "accumulated_refinement_count=%d  final_accumulated_request=%s",
        _acc.append_count > 1, _acc.replace_detected, _acc.append_count,
        (_acc_src[:160] + ("..." if len(_acc_src) > 160 else "")),
    )
    log.info(
        "[RefinementAuthority] requested_change_detected=%s  localized_authority=%s  "
        "authorized_change_chars=%d  detected_zone=%s  structural_permission=%s  mode=%s",
        _refine_detected, bool(authorized_changes_clause),
        len(authorized_changes_clause), _refine_zone or "(none)",
        structural_permission, _gen_mode,
    )
    # Concise continuity wording for V2+ only ("" for V1 — edits the original).
    source_continuity_clause = build_source_continuity_clause(
        _resolved.source_type, iteration
    )
    log.info(
        "[StructuralIdentity] generation_mode=%s  structural_identity_present=%s  "
        "structural_identity_source=%s  structural_identity_chars=%d",
        _gen_mode, structural_id_obj.is_present, _si_source,
        len(structural_identity_clause),
    )

    design_prompt = compose_generation_prompt(
        style_label=style_label,
        room_type=room_type,
        room_description=room_description,
        user_instruction=enriched_instruction,
        iteration=iteration,
        history=history_messages,
        secondary_visible_spaces=secondary_visible_spaces or None,
        compact_prompts=profile.compact_prompts,
        structural_identity=structural_identity_clause,
        source_continuity=source_continuity_clause,
        structural_negative_anchors=negative_anchors_clause,
        authorized_user_changes=authorized_changes_clause,
        generation_mode=generation_mode,  # Wave 5.5.14c — no-op unless BIMODAL_ENABLED=1
        edit_mode=edit_mode,  # Wave 5.13d Phase 1 — single source of truth (main.py classified + elevated)
        prev_atmosphere_id=_ledger_prev_atmo_id,  # (2026-06-22) authoritative prev → switch detection inside the composer matches main.py's
        lineage_customized=_explicit_customized,  # β — authoritative customization verdict (source's flag; None → legacy scan)
    )
    # Ayden Decide STAGE MODE — swap the preserve contract for the furnish
    # contract so an empty room is reliably staged (flag-gated; detected above).
    # The architecture lock is preserved VERBATIM inside the stage contract, so
    # the walls=0 guard is unaffected. Self-guarding: no-op if no preserve
    # contract is present in the composed prompt.
    if _stage_room:
        design_prompt, _staged = apply_stage_mode(
            design_prompt, room_label=_stage_room, atmosphere_label=style_label,
            atmosphere_id=atmosphere_id,
        )
        log.info("[AydenDecideFurnish] STAGE MODE %s (room=%s)",
                 "applied" if _staged else "NO-OP (preserve contract not found)",
                 _stage_room)
    _prompt_s = time.monotonic() - _t_prompt
    log.info(
        "--- prompt composed (%d chars, compact_prompts=%s) ---",
        len(design_prompt), profile.compact_prompts,
    )
    _timer.record("prompt_composition", _prompt_s, chars=len(design_prompt))
    log.info("[PERF] stage=prompt_composition  duration_ms=%.0f  chars=%d",
             _prompt_s * 1000, len(design_prompt))
    log.debug("  prompt:\n%s", design_prompt)
    # Observability (2026-06-14) — dump the EXACT composed prompt (= what is sent
    # to images.edit) at INFO, clearly delimited, so it is always log-extractable
    # without enabling the OpenAI SDK's DEBUG (which would also log image b64).
    log.info("===PROMPT_DUMP_BEGIN [%s | %s | %d chars]===\n%s\n===PROMPT_DUMP_END===",
             style_label, room_type or "(none)", len(design_prompt), design_prompt)

    # ── Step 6: call OpenAI image edit ────────────────────────────────────────
    # PROD: size matched to source aspect ratio (preserves room proportions).
    # DEV: profile.size_override forces 1024x1024 for speed + cost reduction.
    if profile.size_override:
        output_size = profile.size_override
        log.info("  output_size: %s (profile override)", output_size)
    else:
        output_size = _detect_output_size(image_bytes)

    # ── Wave 4.7.3: mandatory version-state observability (Task 7) ───────────
    _latest_version_id = _versions[-1].version_id if _versions else ""
    log.info(
        "[VersionState] generation_mode=%s  source_mode_requested=%s  "
        "source_mode_resolved=%s  source_version_id=%s  source_image_url_type=%s  "
        "latest_version_id=%s  structural_identity_present=%s  "
        "structural_permission=%s  negative_anchors_chars=%d  "
        "prompt_chars=%d  output_size=%s",
        _gen_mode, _resolved.mode_requested or "(none)", _resolved.mode_resolved,
        _resolved.source_version_id or "(n/a)", _resolved.source_type,
        _latest_version_id or "(none)", structural_id_obj.is_present,
        structural_permission, len(negative_anchors_clause),
        len(design_prompt), output_size,
    )

    # ── Diagnostic: log source image dimensions ───────────────────────────────
    try:
        with PilImage.open(io.BytesIO(image_bytes)) as _src_diag:
            _src_w, _src_h = _src_diag.size
            _src_mode = _src_diag.mode
        log.info("  source image: %dx%d mode=%s size_bytes=%d -> output_size=%s",
                 _src_w, _src_h, _src_mode, len(image_bytes), output_size)
    except Exception as _diag_exc:
        log.warning("  source image diagnostic failed: %s", _diag_exc)

    # ── Structural mask (soft perimeter + window protection) ──────────────────
    # ENABLE_STRUCTURAL_MASK is False by default (feature flag in .env).
    # When enabled, mask is applied only for FIRST_VISION and STYLE_REFINEMENT.
    # STRUCTURAL_TRANSFORMATION and LOCAL_EDIT skip the mask — they need free
    # editing of zones that overlap the perimeter.
    _MASK_MODES = {EditMode.FIRST_VISION, EditMode.STYLE_REFINEMENT}
    mask_bytes = None
    if ENABLE_STRUCTURAL_MASK and profile.use_mask and edit_mode in _MASK_MODES:
        # Run mask generation in thread pool — avoids blocking the async event loop.
        # Wave 4.4.0: old synchronous pixel loop was the root cause of RemoteProtocolError.
        _t_mask = time.monotonic()
        _loop = asyncio.get_running_loop()
        mask_bytes = await _loop.run_in_executor(None, build_structural_mask, image_bytes)
        _mask_s = time.monotonic() - _t_mask
        _timer.record("mask_generation", _mask_s, generated=bool(mask_bytes))
        log.info("[PERF] stage=mask_generation  duration_ms=%.0f  mask_generated=%s",
                 _mask_s * 1000, bool(mask_bytes))
        if mask_bytes:
            # Diagnostic: verify mask properties before sending
            try:
                with PilImage.open(io.BytesIO(mask_bytes)) as _mk:
                    _mk_w, _mk_h = _mk.size
                    _mk_mode = _mk.mode
                log.info("  structural mask: %d bytes, %dx%d mode=%s (source=%dx%d, match=%s)",
                         len(mask_bytes), _mk_w, _mk_h, _mk_mode,
                         _src_w, _src_h, (_mk_w == _src_w and _mk_h == _src_h))
            except Exception as _mk_diag:
                log.warning("  mask diagnostic failed: %s", _mk_diag)
        else:
            log.info("  structural mask: skipped (generation failed or PIL unavailable)")
    elif not ENABLE_STRUCTURAL_MASK:
        log.info("  structural mask: disabled (ENABLE_STRUCTURAL_MASK=false)")
    elif not profile.use_mask:
        log.info(
            "  structural mask: disabled (profile=%s use_mask=False — Wave 4.7.0 runtime isolation)",
            profile.name,
        )
    else:
        log.info("  structural mask: skipped (mode=%s not in mask modes)", edit_mode.value)

    _payload_bytes_est = estimate_payload_bytes(image_bytes, mask_bytes, design_prompt)
    log.info(
        "[PERF] payload_estimate  total_bytes=%d  image_bytes=%d  mask_bytes=%d  prompt_bytes=%d",
        _payload_bytes_est, len(image_bytes),
        len(mask_bytes) if mask_bytes else 0, len(design_prompt.encode("utf-8")),
    )
    log.info(
        "--- calling OpenAI images.edit (%s, quality=%s, "
        "input_fidelity=%s, size=%s, mask=%s, max_attempts=%d) ---",
        IMAGE_MODEL, profile.quality, profile.input_fidelity or "omitted",
        output_size, "yes" if mask_bytes else "no", profile.max_attempts,
    )

    # 2026-06-26 — guarantee at least ONE retry on a TRANSIENT failure (the
    # recurring `APIConnectionError: Connection error` that blanks a generation
    # with "service issue"). SAFE on cost: a connection error means OpenAI never
    # produced an image → not billed → retrying can't double-charge. Retries fire
    # ONLY on transient verdicts (the except block below); content/BadRequest stay
    # non-retryable and surface immediately. No effect on the success path.
    _MAX_ATTEMPTS = max(profile.max_attempts, 2)
    _last_exc: Exception | None = None
    generated_bytes: bytes | None = None
    _intent_job_id: str | None = None   # Generation Intent v1 (PR1) — current attempt's Job

    for _attempt in range(1, _MAX_ATTEMPTS + 1):
        _t0 = time.monotonic()
        log.info(
            "[OpenAI Attempt %d/%d] starting  (backend-controlled; SDK max_retries=%d)",
            _attempt, _MAX_ATTEMPTS, openai.max_retries,
        )
        # OBSERVATION — one Job row per technical attempt (best-effort).
        _intent_job_id = await observe_job_start(_intent.id, _attempt)
        try:
            img_file = io.BytesIO(image_bytes)
            img_file.name = "source.jpg"

            mask_file = None
            if mask_bytes:
                mask_file = io.BytesIO(mask_bytes)
                mask_file.name = "mask.png"

            # Wave 5.13n (2026-05-28) — hybrid quality + fidelity overrides
            # for preserve mode. Quality: per-atmosphere override from
            # profile.quality_overrides (e.g. WM/Desert use low, others use
            # the profile default). Fidelity: input_fidelity=high in preserve
            # mode for source-photo anchored architectural preservation.
            # Creative mode (dormant V1) keeps profile defaults for both, so
            # V2 activation is unaffected. Revert = remove these 2 lines.
            _qo_dict = dict(profile.quality_overrides)
            _quality_override = _qo_dict.get(atmosphere_id, profile.quality)
            # Wave 5.13c Phase 2 (2026-05-31) — LOCAL_EDIT quality downgrade.
            # Empirical finding : even with the strict differential prompt
            # (source_continuity + structural_identity + DIFFERENTIAL IMAGE
            # EDIT framing introduced earlier in Wave 5.13c), gpt-image-1
            # still re-renders the whole image and introduces stippling /
            # grain artifacts on textile, wood, and stone surfaces when
            # quality=medium. Low quality's pictorial smoothing masks these
            # artifacts. Trade-off accepted : the requested change (e.g.
            # "white curtain") is slightly less crisp, but the surrounding
            # preserved zones look clean instead of noisy.
            # Scope STRICTLY LOCAL_EDIT — the medium default for
            # STYLE_REFINEMENT / STRUCTURAL_TRANSFORMATION / LAYOUT_CHANGE /
            # FIRST_VISION stays untouched. (Per-atmosphere quality overrides
            # are currently empty after Desert Luxe deregistration 2026-06-03.)
            # Revert = delete this 2-line conditional.
            #
            # Wave 5.13d Phase A (2026-05-31) — extend the LOCAL_EDIT recipe
            # (quality=low + fidelity=OMIT below) to STYLE_REFINEMENT. The
            # cascade-noise audit confirmed STYLE_REFINEMENT was running on
            # quality=medium + fidelity=high + source=LATEST — the exact
            # combination LOCAL_EDIT had pre-correction. Aligning STYLE_REFINEMENT
            # on the corrected recipe is the targeted fix for cascade pixel
            # grain on iterations 2+ (V2 "Nordic instead", V4 "make it warmer",
            # V8 "more luxurious"). STRUCTURAL_TRANSFORMATION and STYLE_SWITCH
            # customized are NOT touched in Phase A — empirical validation
            # of Phase A drives the next step.
            # PHASE EXP (2026-06-13, user-requested) — LOCAL_EDIT_QUALITY_MEDIUM.
            # LOCAL_EDIT was low (pictorial smoothing to mask cascade grain). But
            # its source is LATEST = often a clean render (e.g. V1 at iter2), so
            # low just over-smooths / loses detail with no grain to mask. Bump to
            # medium. STYLE_REFINEMENT stays low for now. ⚠️ On DEEP local-edit
            # chains where LATEST is a degraded AI image, medium may re-surface
            # grain — watch it. LOCAL_EDIT_QUALITY_MEDIUM=0 restores low.
            if edit_mode == EditMode.LOCAL_EDIT:
                _quality_override = (
                    "medium" if os.environ.get("LOCAL_EDIT_QUALITY_MEDIUM", "1") != "0"
                    else "low"
                )
            elif edit_mode == EditMode.STYLE_REFINEMENT:
                # User-requested 2026-06-17 — STYLE_REFINEMENT quality low→medium.
                # ⚠️ Re-introduces the cascade-grain risk that low's pictorial
                # smoothing masked on source=LATEST AI images (Wave 5.13d Phase A
                # / cascade_noise_recipe), esp. on deep refinement chains.
                # STYLE_REFINE_QUALITY_MEDIUM=0 restores low.
                _quality_override = (
                    "medium" if os.environ.get("STYLE_REFINE_QUALITY_MEDIUM", "1") != "0"
                    else "low"
                )
            # Wave 5.22a EXPERIMENT (2026-06-02) — REBOOT_FRESH quality bump.
            # Wave 5.21 V1 anchor eliminates the source=LATEST cascade chain
            # that Wave 5.13d Phase A's quality=low was designed to mask. With
            # V1 as the single ancestor (medium+high render), the model can
            # safely render REBOOT_FRESH at medium quality without re-introducing
            # cascade grain. INCREMENTAL / REBOOT_CUSTOMIZED keep low (their
            # source=LATEST cascade risk is intact). LOCAL_EDIT / LAYOUT_CHANGE
            # are untouched (also source=LATEST cascade risk).
            # fidelity=OMIT is NOT touched in this experiment — strict
            # 1-variable A/B vs current production. If insufficient, next
            # experiment is medium+high (Wave 5.22b).
            # Discriminator: `_switch_override_applied` is True iff Wave 5.21
            # block (lines 1200-1240) pinned source to V1 — i.e. exactly the
            # REBOOT_FRESH-with-V1-anchor case.
            # REVERT = comment out the two lines below.
            if _switch_override_applied:
                _quality_override = "medium"
            # Wave 5.14A Last-Chance Experiment (2026-06-02, TEMPORARY) — test
            # if quality=low on V1 FIRST_VISION (paired with fidelity=high +
            # Editorial Realism active) gives a more photographic render than
            # quality=medium. Hypothesis : medium re-rendering introduces
            # subtle artifacts that the Editorial Realism vocabulary amplifies ;
            # low-quality pictorial smoothing may absorb those artifacts →
            # more photo-like, less "rendered detail" feel. User reported
            # historical Wave 5.13 era V1 perceived as superior — quality
            # tier is one of the only V1-affecting variables that changed.
            # Historical precedent : desert_luxe previously used quality=low
            # on V1 FV via profile.quality_overrides (no regression observed).
            # That atmosphere was deregistered 2026-06-03 ; precedent stands.
            # Restore Best Empirical V1 Step 9 (2026-06-02 evening) — V1 FV
            # configured to quality=MEDIUM (profile default, no override) +
            # fidelity=low (Step 3/A1 uncommented below). Step 8 quality=high
            # override DISABLED — empirically rejected for 4× cost / 2×
            # latency without proportional visual gain. Combined with 5.14A
            # + 5.14B disabled via editorial_realism_enabled=False (composer_v2
            # V1 delegation), this restores the cleaner natural render feel
            # that the user identified as "commercializable" baseline.
            # REVERT to Step 8 (quality=high) = uncomment the two lines below.
            # if edit_mode == EditMode.FIRST_VISION:
            #     _quality_override = "high"
            _fidelity_override = "high" if generation_mode == "preserve" else profile.input_fidelity
            # Wave 5.13c Option C (2026-05-31) — drop input_fidelity for
            # LOCAL_EDIT + LAYOUT_CHANGE. Phase 2 (quality=low) alone didn't
            # kill the stippling grain artifacts on regenerated surfaces.
            # Hypothesis : input_fidelity=high forces the model to "anchor
            # hard + reproduce" the V1 AI image, and its reproduction
            # introduces the grain. Omitting fidelity gives the model
            # latitude to render from its internal priors (cleaner surface
            # textures) instead of pixel-matching the V1 cascade-degraded
            # input. The strict differential prompt + source_continuity +
            # structural_identity still constrain WHAT changes.
            #
            # Wave 5.13c Plan B (2026-05-31, second amendment) — extend the
            # fidelity drop to LAYOUT_CHANGE. Empirical finding (V4 test) :
            # with fidelity=high, the model refused to relocate the TV ("it's
            # already facing the sofa from across the room"). Omitting
            # fidelity gives LAYOUT_CHANGE the latitude needed to actually
            # apply the spatial rearrangement requested. Trade-off : the
            # model may also drift on architecture (e.g. doors disappearing)
            # — the LAYOUT_CHANGE prompt + structural_identity must hold
            # the line. If architectural drift becomes a regression, the
            # next lever is reinforcing the prompt's "preserve all openings
            # including doors" wording.
            # Wave 5.13d Phase A (2026-05-31) — add STYLE_REFINEMENT to the
            # fidelity-OMIT set. Same rationale as the quality=low extension
            # above : cascade-noise audit showed STYLE_REFINEMENT on LATEST
            # source with fidelity=high anchored the model to noisy AI pixels.
            # Omitting fidelity lets the model render from clean internal
            # priors. structural_identity + accumulated_state in the prompt
            # still constrain WHAT changes.
            #
            # Wave 5.13d Phase B (2026-05-31) — extend the fidelity-OMIT set
            # to STRUCTURAL_TRANSFORMATION. Quality stays medium for STRUCT
            # (large semantic transformations — opening a wall, removing a
            # partition — need re-render definition that low quality smooths
            # away). Only fidelity drops, so the model gets latitude from
            # internal priors instead of pixel-anchoring to a potentially
            # noisy AI source. structural_identity + structural_permission
            # in the V3 prompt still constrain WHAT can change.
            # PHASE EXP (2026-06-13, user-requested) — EDIT_FIDELITY_LOW.
            # LOCAL_EDIT / LAYOUT_CHANGE / STYLE_REFINEMENT move from OMIT to a
            # light pixel anchor (low) for tighter structural preservation on
            # refinements. STRUCTURAL_TRANSFORMATION stays OMIT (large semantic
            # changes need latitude). ⚠️ Re-introduces the cascade-grain risk
            # OMIT was designed to mask on source=LATEST AI images
            # (Wave 5.13c/d / cascade_noise_recipe). EDIT_FIDELITY_LOW=0 = OMIT.
            if edit_mode == EditMode.STRUCTURAL_TRANSFORMATION:
                # User-requested 2026-06-17 — STRUCT fidelity omit→low (light
                # pixel anchor for tighter architecture preservation during
                # structural edits). ⚠️ Less latitude for large semantic changes
                # (open a wall / remove a partition) — the model may under-apply
                # or refuse the transformation (Wave 5.13c Plan B symptom on
                # LAYOUT). STRUCT_FIDELITY_LOW=0 restores OMIT (None).
                _fidelity_override = (
                    "low" if os.environ.get("STRUCT_FIDELITY_LOW", "1") != "0"
                    else None
                )
            elif edit_mode in (
                EditMode.LOCAL_EDIT,
                EditMode.LAYOUT_CHANGE,
                EditMode.STYLE_REFINEMENT,
            ):
                _fidelity_override = (
                    "low" if os.environ.get("EDIT_FIDELITY_LOW", "1") != "0"
                    else None
                )
            # Wave 5.14A Last-Chance Step 6 (2026-06-02 evening) — V1 FV
            # configured to quality=low + fidelity=HIGH (per user request).
            # Step 1 already sets quality=low for V1 FV ; this block (Step
            # 3/A1 fidelity=low override) is now COMMENTED OUT so V1 FV
            # falls back to the natural preserve override fidelity="high"
            # set at line 1815. Combined with 5.14B Photographic Credibility
            # re-enabled this time (was OFF when Step 1 originally tested
            # this same low+high combo and user reported "trop dessiné").
            # History : Step 1 (low+high+Editorial only → trop dessiné) →
            # Step 2 (+5.14B → mieux) → Step 3 (low+low → ?) → Step 4 Option
            # E (omit+omit → 4× cost rejected) → Step 5 (low+omit) → Step 3
            # restored (low+low) → Step 6 (low+high WITH 5.14B).
            # Restore Best Empirical V1 FINAL (2026-06-03) + per-atmosphere
            # fidelity=high exceptions (SL initial, Japandi added 2026-06-03
            # late, Nordic added 2026-06-04) — V1 FV fidelity=LOW for all
            # atmospheres EXCEPT Soft Luxury, Japandi, and Nordic Warmth,
            # which get fidelity=HIGH.
            # Rationale :
            #   • LOW default : Row 1 vs Row 2 A/B showed low gives more
            #     atmosphere drama (Tropical lush, WM warm) without losing
            #     architecture preservation thanks to prompt-level anchors
            #     (structural_identity, Wave 5.21d, BIMODAL strips).
            #   • SL exception : SL bench shows higher wall invention rate
            #     (25% with Wave 5.24 v2 vs ~15% target). SL is
            #     intrinsically "evening mood" — atmosphere drama already
            #     supplied by DNA (cove lighting, warm evening tone). The
            #     model needs the extra pixel-anchor from fidelity=high
            #     to keep architecture stable, and the trade-off (less
            #     atmosphere latitude) is acceptable because SL DNA is
            #     dramatic enough already.
            #   • Japandi exception : empirically benefits from stronger
            #     preservation anchoring (cleaner architectural lines, less
            #     drift on the restraint-driven aesthetic). Same trade-off
            #     accepted as SL — Japandi DNA already supplies the
            #     atmosphere identity ; the extra pixel anchor helps the
            #     calm/restrained signature read cleanly.
            #   • Nordic exception (2026-06-04) : Nordic preserve bench on
            #     Type B sources showed door/window preservation
            #     sensitivity (1/3 capture hallucination rate). Nordic DNA
            #     already supplies hygge identity through warm wool, amber
            #     glass, pine — atmosphere readable without needing
            #     low-fidelity latitude. Extra pixel-anchor from
            #     fidelity=high stabilises architecture rendering on
            #     ambiguous-source captures. Trade-off (slightly less
            #     daylit airy drama) accepted in exchange for door/window
            #     fidelity.
            # REVERT exceptions = remove ids from the tuple.
            if edit_mode == EditMode.FIRST_VISION:
                # Wave 6.13j (2026-06-05) — WM KITCHEN-only fidelity=high.
                # SL/Japandi/Nordic already use high here and preserve door/window
                # well (SL 3/4); WM was kept at low for the airy-daylit look and
                # pays it in structure (WM kitchen 1/4 door+window kept). Pixel-
                # anchor from fidelity=high stabilises architecture rendering —
                # scoped to WM kitchen ONLY (other WM rooms stay low/airy).
                # ~2x latency on this cell only. room_type normalised for
                # client-casing safety. Revert = drop the warm_modern clause.
                # Wave 6.16 (2026-06-06) — WM home_office added to the high list:
                # its 6.16 dual-zone floor furniture needs the same pixel-anchor as
                # kitchen. Normalised (handles "Home Office"/spaces). SL/Japandi/
                # Nordic home_office already high via the atmosphere tuple.
                # Wave 6.14 (2026-06-09) — WM promoted to ALL-rooms fidelity=high.
                # User decision after the WM-Living A/B: high KEEPS the 6.14
                # styling-layer density (cushions/throw/anchored greenery/cond.
                # art all survived) AND tightens structural preservation, at
                # acceptable latency (~37-48s @ quality=medium). WM now joins
                # SL/Japandi/Nordic as always-high — this SUPERSEDES the former
                # per-room WM high clauses (kitchen 6.13j, home_office 6.16,
                # bathroom 6.20, outdoor 6.28 — all subsumed). Tropical stays LOW
                # (lush atmosphere drama / permissive core — do NOT promote).
                # REVERT (WM back to low/airy) = drop "warm_modern" from the tuple
                # and restore the per-room clause above.
                # PHASE 1.2 — shared allow-list with composer's contract-light
                # decision (prompt_engine.preservation.HIGH_FIDELITY_ATMOSPHERES)
                # so fidelity=high and the compact contract can never desync.
                # Consolidated 2026-06-14 — all 5 MVP atmospheres are in
                # HIGH_FIDELITY_ATMOSPHERES (Tropical promoted to the tuple), so
                # the former TROPICAL_V1_HIGH else-branch flag is now dead and
                # removed. Any future non-listed atmosphere defaults to low.
                _fidelity_override = (
                    "high" if atmosphere_id in HIGH_FIDELITY_ATMOSPHERES else "low"
                )
            # Wave 5.22b EXPERIMENT (2026-06-02) — REBOOT_FRESH fidelity bump.
            # Pairs with Wave 5.22a quality=medium. Wave 5.21 V1 anchor source
            # is a clean medium+high render (single-edit-from-photo), not a
            # cascade-degraded AI image. Re-introducing light pixel anchoring
            # ("low" tier — between OMIT and "high") lets the model reference
            # V1's architecture (window position, furniture proportions)
            # without the transformation-rigidity risk that fidelity=high
            # carried (Wave 5.13c original symptom).
            # Wave 5.22c (fidelity=high) was tested and ROLLED BACK : ~2× more
            # latency (avg 59s vs 30s) without sufficient visual gain.
            # Other paths (INCREMENTAL/REBOOT_CUSTOMIZED/LOCAL_EDIT/LAYOUT_CHANGE
            # /STRUCT) keep OMIT — their source=LATEST cascade rationale intact.
            # REVERT = comment the two lines below.
            if _switch_override_applied:
                _fidelity_override = "low"
            # gpt-image-2 migration (2026-06-29) — le modèle VERROUILLE
            # input_fidelity (l'API le rejette) et a été benché en quality=low.
            # On force les deux ICI pour que le reste du bloc (conçu pour le
            # tuning per-atmosphère gpt-image-1) émette un appel valide :
            #   • _fidelity_override=None → routé vers la branche OMIT plus bas
            #     (pop + log "OMITTED"), donc input_fidelity absent de l'appel ;
            #   • _quality_override="low" → config benchée (−84 % coût), figée
            #     sur TOUS les chemins (y c. itérations) — medium = ×2,7 rejeté.
            # Rollback complet = IMAGE_MODEL="gpt-image-1" (réactive le tuning).
            if IMAGE_MODEL.startswith("gpt-image-2"):
                _fidelity_override = None
                _quality_override = "low"
            # Wave 5.14A Last-Chance Step 4 / Option E REMOVED (2026-06-02
            # evening) — omit-both config triggered OpenAI default quality=
            # "auto" which heuristically selected "high" tier (~55s OpenAI
            # processing, ~4× the cost of medium). Latency + cost too high
            # vs visual gain. User reverted to Step 5 (quality=low set by
            # Step 1 + fidelity=OMIT set by Step 5 below).
            edit_kwargs: dict = dict(
                model=IMAGE_MODEL,
                image=img_file,
                prompt=design_prompt,
                n=1,
                size=output_size,
                quality=_quality_override,
                input_fidelity=_fidelity_override,
            )
            # Wave 4.7.0 Step 1: mobile_mvp_baseline sets input_fidelity=None —
            # omit the parameter entirely from the API call (absent, not "low").
            _atmo_override = atmosphere_id in _qo_dict
            if edit_mode == EditMode.LOCAL_EDIT:
                _edit_mode_label = "yes(LOCAL_EDIT)"
            elif edit_mode == EditMode.LAYOUT_CHANGE:
                _edit_mode_label = "yes(LAYOUT_CHANGE)"
            elif edit_mode == EditMode.STYLE_REFINEMENT:
                # Wave 5.22a+b — REBOOT_FRESH path receives different
                # params than incremental SR (V1 anchor changes the
                # cascade math). Distinguish in the log so empirical
                # comparisons can be made on the right cohort.
                if _switch_override_applied:
                    _edit_mode_label = "yes(REBOOT_FRESH/Wave5.22a+b)"
                else:
                    _edit_mode_label = "yes(STYLE_REFINEMENT/Wave5.13d-PhaseA)"
            elif edit_mode == EditMode.STRUCTURAL_TRANSFORMATION:
                _edit_mode_label = "yes(STRUCTURAL_TRANSFORMATION/Wave5.13d-PhaseB)"
            else:
                _edit_mode_label = "no"
            if edit_kwargs.get("input_fidelity") is None:
                edit_kwargs.pop("input_fidelity", None)
                if _attempt == 1:
                    log.info(
                        "  [Wave 5.13n+c2] quality=%s (atmo=%s atmo_override=%s edit_mode_override=%s) input_fidelity: OMITTED from API call",
                        _quality_override, atmosphere_id,
                        "yes" if _atmo_override else "no",
                        _edit_mode_label,
                    )
            elif _attempt == 1:
                log.info(
                    "  [Wave 5.13n+c2] quality=%s (atmo=%s atmo_override=%s edit_mode_override=%s) input_fidelity=%s (preserve override active)",
                    _quality_override, atmosphere_id,
                    "yes" if _atmo_override else "no",
                    _edit_mode_label,
                    _fidelity_override,
                )
            if mask_file is not None:
                edit_kwargs["mask"] = mask_file

            # ── TEMP INSTRUMENTATION (2026-06-26) — REMOVE after diagnosis. ──
            # logical_key = session:iteration:attempt. An intentional regenerate
            # bumps `generation_attempt` → new key, so logical_call_count > 1 here
            # is a TRUE accidental duplicate (same logical gen hitting the image
            # call twice — whether from the same request_id or a different one).
            _img_uuid = uuid.uuid4().hex
            _logical_key = (
                f"{session_id or '-'}:{iteration}:"
                f"{(generation_attempt or '0').strip()}"
            )
            _rec = _OPENAI_CALL_LOG.setdefault(
                _logical_key, {"count": 0, "request_ids": set()})
            _rec["count"] += 1
            _rec["request_ids"].add(request_id)
            log.info(
                "[OPENAI IMAGE START] img_uuid=%s ts=%.3f request_id=%s session=%s "
                "iteration=%d attempt_field=%s loop_attempt=%d/%d logical_key=%s "
                "logical_call_count=%d distinct_request_ids=%d",
                _img_uuid, time.time(), request_id, session_id or "(none)", iteration,
                (generation_attempt or "0").strip(), _attempt, _MAX_ATTEMPTS,
                _logical_key, _rec["count"], len(_rec["request_ids"]),
            )
            if _rec["count"] > 1:
                log.warning(
                    "[OPENAI IMAGE DUPLICATE] logical_key=%s executed "
                    "openai.images.edit %d times — request_ids=%s (this img_uuid=%s)",
                    _logical_key, _rec["count"], sorted(_rec["request_ids"]), _img_uuid,
                )
            # ── END TEMP INSTRUMENTATION (START half) ──
            # [OPENAI-CALL] — PERMANENT, intent-keyed. Un couple START/END par
            # appel OpenAI effectif → preuve directe « 1 intention = N appels »
            # en prod : SELECT sur intent=<id> doit montrer autant de END que
            # d'images réellement facturées. (grep '[OPENAI-CALL]')
            log.info("[OPENAI-CALL] START intent=%s attempt=%d/%d img=%s",
                     _intent.id, _attempt, _MAX_ATTEMPTS, _img_uuid)
            response = await openai.images.edit(**edit_kwargs)
            # ── TEMP INSTRUMENTATION (2026-06-26) — REMOVE after diagnosis. ──
            log.info(
                "[OPENAI IMAGE END] img_uuid=%s ts=%.3f request_id=%s session=%s "
                "iteration=%d loop_attempt=%d",
                _img_uuid, time.time(), request_id, session_id or "(none)",
                iteration, _attempt,
            )
            # ── END TEMP INSTRUMENTATION ──
            # ── OBSERVABILITÉ FACTURATION (2026-06-29) — usage tokens réels.
            # Pur log, AUCUN changement de comportement, AUCUN base64.
            # Répond à : OpenAI facture-t-il différemment la MÊME requête ?
            #   input_tokens_details.image_tokens  = coût input_fidelity=high
            #   output_tokens_details.image_tokens = coût quality × size
            # Si pour une image identique ces tokens (ou le $/token) ont bougé
            # dans le temps → c'est la plateforme OpenAI, pas notre code.
            try:
                _usage = getattr(response, "usage", None)
                _oai_rid = getattr(response, "_request_id", None)
                _itd = getattr(_usage, "input_tokens_details", None)
                _otd = getattr(_usage, "output_tokens_details", None)
                log.info(
                    "\n========== OPENAI IMAGE RESPONSE ==========\n"
                    "openai_request_id=%s\n"
                    "input_tokens=%s (image=%s text=%s)\n"
                    "output_tokens=%s (image=%s)\n"
                    "total_tokens=%s\n"
                    "payload: size=%s quality=%s input_fidelity=%s n=%s model=%s\n"
                    "===========================================",
                    _oai_rid,
                    getattr(_usage, "input_tokens", None),
                    getattr(_itd, "image_tokens", None),
                    getattr(_itd, "text_tokens", None),
                    getattr(_usage, "output_tokens", None),
                    getattr(_otd, "image_tokens", None),
                    getattr(_usage, "total_tokens", None),
                    output_size, _quality_override, _fidelity_override,
                    edit_kwargs.get("n"), IMAGE_MODEL,
                )
            except Exception as _uexc:  # noqa: BLE001 — observabilité non-fatale
                log.warning("[OpenAI Usage] log usage échoué (non-fatal): %s", _uexc)
            _elapsed = time.monotonic() - _t0
            _timer.record("openai_api", _elapsed, attempt=_attempt, status="success")
            log.info("[OpenAI Attempt %d/%d] succeeded in %.1fs", _attempt, _MAX_ATTEMPTS, _elapsed)
            log.info("[OPENAI-CALL] END intent=%s attempt=%d status=success elapsed=%.1fs",
                     _intent.id, _attempt, _elapsed)

            b64 = response.data[0].b64_json
            if not b64:
                log.error("  b64_json is empty — data_count=%d", len(response.data))
                # Wave 5.17b — refund the reserved quota slot. OpenAI returned
                # but with no content : the user got nothing of value.
                if _reservation_id is not None:
                    await fail_generation(_reservation_id)
                    _reservation_id = None
                raise GenerationError(
                    error_code="EMPTY_IMAGE",
                    user_message="The generation returned an empty result. Please try again.",
                    retryable=True,
                    request_id=request_id,
                    status_code=502,
                    session_id=session_id,
                )

            generated_bytes = base64.b64decode(b64)
            log.info("  generated: %d bytes (%.1f KB)", len(generated_bytes), len(generated_bytes) / 1024)
            # [RETRY-PROOF] (logging-only) — which attempt succeeded. "N>1" means
            # ONE backend generation retried internally (expected); two SEPARATE
            # [RETRY-PROOF] success lines with DIFFERENT request_ids ⇒ a real
            # double generation (the timeout-retrigger bug).
            log.info(
                "[RETRY-PROOF] request_id=%s SUCCESS on attempt %d/%d",
                request_id, _attempt, _MAX_ATTEMPTS,
            )

            # Wave 5.17b — quota CONFIRM. OpenAI succeeded → cost incurred →
            # the reservation is committed. From this point on, any
            # downstream failure (persistence, etc.) does NOT refund the
            # quota slot : the user got their image, even if it was lost
            # to a storage error. Skipped when _reservation_id is None
            # (admin / premium bypass).
            if _reservation_id is not None:
                await confirm_generation(_reservation_id, cost_usd_estimate=0.0)
                _reservation_id = None  # mark as committed — fail() path won't fire
            # Sprint 1B — consume ONE promo generation on success (promo_limited
            # only; _reservation_id is None for promo since it's off the
            # usage_log ledger). Fail-soft inside consume_promo_generation: the
            # image already succeeded, so a ledger hiccup never fails the request.
            if _decision.consume_promo_on_success:
                _pc = await consume_promo_generation(current_user.user_id)
                log.info(
                    "[Sprint 1B] promo generation consumed — user=%s result=%s",
                    current_user.user_id, _pc,
                )
            # OBSERVATION — this attempt's Job succeeded (Intent terminal marked
            # after persistence, near the response). Best-effort.
            await observe_job_end(_intent_job_id, "SUCCEEDED")
            break  # success — exit retry loop

        except BadRequestError as exc:
            _elapsed = time.monotonic() - _t0
            _timer.record("openai_api", _elapsed, attempt=_attempt, status="bad_request")
            log.error(
                "[OpenAI Attempt %d/%d] NON-TRANSIENT BadRequestError in %.1fs  "
                "status=%s  code=%s  verdict=NON_TRANSIENT  reason=content-policy  — not retrying",
                _attempt, _MAX_ATTEMPTS, _elapsed, exc.status_code, exc.code,
            )
            # Wave 5.17b — content-policy rejections are pre-API in spirit
            # (no successful image generated). Refund the quota slot.
            if _reservation_id is not None:
                await fail_generation(_reservation_id)
                _reservation_id = None
            # OBSERVATION — non-transient (content-policy) → terminal, no re-claim.
            await observe_job_end(_intent_job_id, "FAILED", error_type="non_transient")
            await observe_intent_end(
                _intent.id, "FAILED_TERMINAL",
                error={"type": "content_policy", "message": "OPENAI_REJECTED"},
                is_free=_decision.consumes_free_quota,
            )
            raise GenerationError(
                error_code="OPENAI_REJECTED",
                user_message="The design request was rejected. Try rephrasing or using a different photo.",
                retryable=False,
                request_id=request_id,
                status_code=502,
                session_id=session_id,
            )

        except (HTTPException, GenerationError):
            raise

        except Exception as exc:
            _elapsed = time.monotonic() - _t0
            _exc_type = type(exc).__name__
            decision = classify_for_retry(exc)
            _remaining = _MAX_ATTEMPTS - _attempt
            _timer.record("openai_api", _elapsed, attempt=_attempt, status="failed")

            if not decision.should_retry:
                # Non-transient — surface immediately, save remaining API budget
                log.error(
                    "[OpenAI Attempt %d/%d] NON-TRANSIENT failure in %.1fs  "
                    "(%s: %s)  verdict=%s  reason=%s  remaining_attempts_saved=%d  — not retrying",
                    _attempt, _MAX_ATTEMPTS, _elapsed, _exc_type, exc,
                    decision.verdict.value, decision.reason, _remaining,
                )
                # Wave 5.17b — refund quota on non-transient failures.
                if _reservation_id is not None:
                    await fail_generation(_reservation_id)
                    _reservation_id = None
                # OBSERVATION — non-transient → terminal, no re-claim.
                await observe_job_end(_intent_job_id, "FAILED", error_type="non_transient")
                await observe_intent_end(
                    _intent.id, "FAILED_TERMINAL",
                    error={"type": _exc_type, "message": str(exc)[:200]},
                    is_free=_decision.consumes_free_quota,
                )
                raise GenerationError(
                    error_code="OPENAI_FAILED",
                    user_message="Generation could not be completed. Please try again.",
                    retryable=False,
                    request_id=request_id,
                    status_code=502,
                    session_id=session_id,
                )

            # Transient or unknown — retry if attempts remain
            _last_exc = exc
            # OBSERVATION — close THIS attempt's Job as transient failure. The
            # Intent stays RUNNING ; the next attempt opens a new Job (proves
            # "1 Intent / N Jobs"). Intent terminal is set after the loop if
            # every attempt is exhausted.
            await observe_job_end(_intent_job_id, "FAILED", error_type="transient")
            if decision.verdict == RetryVerdict.UNKNOWN:
                log.warning(
                    "[OpenAI Attempt %d/%d] UNCLASSIFIED failure in %.1fs  "
                    "(%s: %s)  verdict=%s  reason=%s  — treating as transient",
                    _attempt, _MAX_ATTEMPTS, _elapsed, _exc_type, exc,
                    decision.verdict.value, decision.reason,
                )
            if _remaining > 0:
                log.warning(
                    "[OpenAI Attempt %d/%d] transient failure in %.1fs  "
                    "(%s: %s)  verdict=%s  reason=%s  remaining=%d  — will retry",
                    _attempt, _MAX_ATTEMPTS, _elapsed, _exc_type, exc,
                    decision.verdict.value, decision.reason, _remaining,
                )
                # 2026-06-26 — brief backoff so a momentary network blip clears
                # before the retry (only on a failed attempt; no happy-path cost).
                await asyncio.sleep(2.0)
            else:
                log.error(
                    "[OpenAI Attempt %d/%d] final failure in %.1fs  "
                    "(%s: %s)  verdict=%s  reason=%s  — all attempts exhausted",
                    _attempt, _MAX_ATTEMPTS, _elapsed, _exc_type, exc,
                    decision.verdict.value, decision.reason,
                )
                log.error(traceback.format_exc())

    if generated_bytes is None:
        # All attempts exhausted
        # Wave 5.17b — refund quota when every retry failed. The user
        # got no image ; they should not lose a free generation slot.
        if _reservation_id is not None:
            await fail_generation(_reservation_id)
            _reservation_id = None
        # OBSERVATION — every transient attempt exhausted → Intent FAILED
        # (re-claimable by the same intent_id on a user re-tir, in PR2).
        await observe_intent_end(
            _intent.id, "FAILED",
            error={"type": "exhausted", "message": "all_attempts_failed"},
            is_free=_decision.consumes_free_quota,
        )
        raise GenerationError(
            error_code="OPENAI_FAILED",
            user_message="Generation failed due to a service issue. Please try again.",
            retryable=True,
            request_id=request_id,
            status_code=502,
            session_id=session_id,
        )

    # ── Step 6b: re-encode to JPEG q=85 before upload (Wave 5.13c perf) ──────
    # gpt-image-1 returns PNG bytes (typically 2-3 MB at 1536×1024). Uploading
    # that raw payload through Supabase Storage + serving it back to mobile
    # over Cloudflare CDN was costing 5-7 s in each direction on bandwidth-
    # constrained connections. Re-encoding to JPEG q=85 with `optimize=True`
    # shrinks the payload ~3× (target ~600-800 KB) with no perceptible
    # quality loss on architectural renders. Net saving: ~8 s end-to-end.
    # Done synchronously here because PIL JPEG encode of a 1536×1024 image is
    # ~80-150 ms — negligible vs the upload/download savings.
    _t_compress = time.monotonic()
    _orig_size = len(generated_bytes)
    try:
        with PilImage.open(io.BytesIO(generated_bytes)) as _src_img:
            # JPEG can't carry alpha; flatten to RGB on a white background
            # so PNGs with transparency don't blow up encoding.
            if _src_img.mode in ("RGBA", "LA", "P"):
                _flat = PilImage.new("RGB", _src_img.size, (255, 255, 255))
                _flat.paste(_src_img.convert("RGBA"), mask=_src_img.convert("RGBA").split()[-1])
                _src_img = _flat
            elif _src_img.mode != "RGB":
                _src_img = _src_img.convert("RGB")
            # ── Sprint 1: free-tier watermark baked into the bytes ──────────
            # Premium/admin (server-authoritative has_admin_role → the
            # _is_admin_bypass computed earlier in this request) get a CLEAN
            # image. Free users get the mark composited HERE, before the JPEG
            # encode + upload — so the stored/served URL is never clean.
            if not _is_admin_bypass:
                _src_img = apply_watermark(_src_img)
                log.info("  watermark: APPLIED (free tier)")
            else:
                log.info("  watermark: skipped (premium/admin)")
            _buf = io.BytesIO()
            _src_img.save(_buf, format="JPEG", quality=85, optimize=True, progressive=True)
            generated_bytes = _buf.getvalue()
        _compress_s = time.monotonic() - _t_compress
        _ratio = _orig_size / max(len(generated_bytes), 1)
        log.info(
            "[PERF] stage=image_compression  duration_ms=%.0f  "
            "in_bytes=%d  out_bytes=%d  ratio=%.2fx  quality=85",
            _compress_s * 1000, _orig_size, len(generated_bytes), _ratio,
        )
        _timer.record(
            "image_compression", _compress_s,
            in_bytes=_orig_size, out_bytes=len(generated_bytes),
        )
    except Exception as exc:
        # Non-fatal: if compression fails for any reason, upload the original
        # PNG bytes so the user still gets their image. Safety net only.
        log.warning(
            "  image compression FAILED (non-fatal, uploading original): "
            "%s: %s", type(exc).__name__, exc,
        )

    # ── Step 7: upload to Supabase Storage ────────────────────────────────────
    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    path = f"{session_id}/{ts}_{uuid.uuid4().hex[:8]}.jpg"
    log.info("--- uploading to Supabase (generated/%s) ---", path)
    _t_upload = time.monotonic()
    try:
        supa.storage.from_("generated").upload(
            path=path,
            file=generated_bytes,
            file_options={"content-type": "image/jpeg"},
        )
        public_url = supa.storage.from_("generated").get_public_url(path)
        _upload_s = time.monotonic() - _t_upload
        _timer.record("supabase_upload", _upload_s, size_bytes=len(generated_bytes))
        log.info("  upload OK  url: %s", public_url)
        log.info("[PERF] stage=supabase_upload  duration_ms=%.0f  size_bytes=%d",
                 _upload_s * 1000, len(generated_bytes))
    except Exception as exc:
        log.error("  Supabase upload FAILED: %s: %s", type(exc).__name__, exc)
        log.error(traceback.format_exc())
        # Wave 5.17b — STORAGE_FAILED occurs AFTER the OpenAI cost was
        # incurred and AFTER confirm_generation was called at the `break`,
        # so _reservation_id is normally None here. This guard is defensive :
        # if storage fails before the confirm (extremely unusual control
        # flow), refund the slot. Otherwise it's a no-op.
        if _reservation_id is not None:
            await fail_generation(_reservation_id)
            _reservation_id = None
        raise GenerationError(
            error_code="STORAGE_FAILED",
            user_message="Your design was generated but couldn't be saved. Please try again.",
            retryable=True,
            request_id=request_id,
            status_code=500,
            session_id=session_id,
        )

    # ── Step 8: compose architect response + suggestion chips ─────────────────
    atmosphere_id = label_to_atmosphere_id(style_label)

    # Wave 3.4.1: detect session language for bilingual caption.
    # Phase 1 — the caption/architect-reply language now follows the UI locale
    # (was hardcoded "en"). EN clients send "en" → byte-identical to before.
    # This does NOT affect the English-internal generation prompt.
    _gen_session_memory = build_session_memory(
        history=history_messages,
        detected_language=(ui_locale.strip() or "en"),
        atmosphere_id_hint=atmosphere_id,
        room_type_hint=room_type,
    )
    session_lang = _gen_session_memory.session_language

    # Build a clean caption first (prevents malformed raw fragments in responses)
    caption = build_vision_caption(
        user_instruction=prompt,
        transformation_type=transformation_type,
        iteration=iteration,
        atmosphere_id=atmosphere_id,
        language=session_lang,
    )

    # ── Wave 4.11a: compute architect enrichments (strict orchestration) ─
    # Each helper returns "" / [] / False when the conditions aren't met.
    # generate_architect_response() then picks AT MOST one main enrichment
    # + AT MOST one CONFIDENT opening before applying the brevity cap.
    _wave411_transformation = (
        transformation_type.value
        if hasattr(transformation_type, "value")
        else (transformation_type or "")
    )
    _trade_off = get_trade_off(
        user_message=prompt,
        transformation_type=_wave411_transformation,
        atmosphere_id=atmosphere_id,
        room_type=room_type,
        iteration=iteration,
    )
    _emit_ack = should_emit_acknowledgment(
        iteration=iteration,
        transformation_type=_wave411_transformation,
        refinement_state=refinement_state,
        history_messages=history_messages,
    )
    _constraint_ack = (
        build_acknowledgment(
            structural_identity=structural_id_obj,
            refinement_state=refinement_state,
            atmosphere_id=atmosphere_id,
            transformation_type=_wave411_transformation,
        )
        if _emit_ack
        else ""
    )
    _alternatives = get_alternative_directions(
        atmosphere_id=atmosphere_id,
        room_type=room_type,
        refinement_state=refinement_state,
        iteration=iteration,
        count=3,
    )
    # Wave 4.11b — architectural memory injection. Returns "" when the
    # iteration is too early (< V3), the keep list has no recognised
    # architectural anchor, or the user just mentioned the only kept
    # anchor in this turn. architect_response then decides whether to
    # actually surface it (suppressed when main enrichment is
    # constraint_ack or alternatives).
    _memory_ref = get_memory_reference(
        refinement_state=refinement_state,
        iteration=iteration,
        user_message=prompt,
    )
    _wave411_emotional = detect_emotional_context(prompt)
    _wave411_tone = select_tone_mode(
        meta_intent=MetaIntent.NONE,
        sub_intent=intent_class.sub_intent,
        confidence=intent_class.confidence,
        session_memory=_gen_session_memory,
        emotional_context=_wave411_emotional,
        iteration=iteration,
        recent_meta_intents=[],
    )
    log.info(
        "[Wave4.11a] tone=%s trade_off=%d ack=%d alternatives=%d memory=%d",
        _wave411_tone.value,
        len(_trade_off),
        len(_constraint_ack),
        len(_alternatives),
        len(_memory_ref),
    )

    # Generate the full architect response (includes follow-up question).
    # Wave 4.11a passes the enrichment inputs ; generate_architect_response
    # handles selection + brevity internally.
    arch_response = generate_architect_response(
        atmosphere_id=atmosphere_id,
        room_type=room_type,
        iteration=iteration,
        edit_mode=edit_mode,
        refinement_state=refinement_state,
        sub_intent=intent_class.sub_intent,
        secondary_spaces=secondary_visible_spaces,
        user_message=prompt,
        # Wave 4.11a + 4.11b enrichments
        tone_mode=_wave411_tone,
        transformation_type=_wave411_transformation,
        constraint_ack=_constraint_ack,
        trade_off_clause=_trade_off,
        alternatives=_alternatives,
        memory_reference=_memory_ref,
    )

    # For Vision 1, the architect response is the primary message.
    # For Vision 2+, prefix with the clean caption so the user always sees
    # what changed, followed by the follow-up question.
    if iteration <= 1:
        ai_message = arch_response
    else:
        # The caption IS the result message; arch_response adds the follow-up
        # Only append the follow-up question, not the duplicate context
        follow_up = arch_response.split(". ", 1)[-1] if ". " in arch_response else arch_response
        ai_message = f"{caption} {follow_up}"

    # Wave 3.4: contextual chips use transformation type + secondary spaces
    suggestions = await _contextual_localized(ui_locale,
        atmosphere_id=atmosphere_id,
        room_type=room_type,
        iteration=iteration,
        transformation_type=transformation_type,
        secondary_spaces=secondary_visible_spaces or None,
    )

    log.info("  ai_message: %s", ai_message[:100])
    log.info("  suggestions: %s", suggestions)

    # ── β (2026-06-22): cumulative lineage_customized for this new version ───
    # new.lineage_customized = (source's flag) OR (this generation is spatial).
    # Computed at WRITE so the read-time decision is O(1) (no lineage walk). The
    # WRITE always runs (independent of LINEAGE_CUSTOM_FLAG) so ledgers populate
    # the field for a smooth migration; only the READ above is flag-gated.
    # Under the frozen v1 composer (no switch awareness) we write None.
    if _COMPOSER_V2_ACTIVE:
        _this_spatial = _is_spatial_edit(transformation_type)
        _base_customized = (
            _src_record.lineage_customized
            if (_src_record is not None and _src_record.lineage_customized is not None)
            else False
        )
        _new_lineage_customized = bool(_base_customized or _this_spatial)
        log.info(
            "[LineageFlag] iteration=%d transformation=%s this_spatial=%s "
            "src=%s src_lineage=%s → lineage_customized=%s",
            iteration, getattr(transformation_type, "value", transformation_type),
            _this_spatial, (_src_record.version_id if _src_record else "(none)"),
            (_src_record.lineage_customized if _src_record else "(none)"),
            _new_lineage_customized,
        )
    else:
        _new_lineage_customized = None  # v1 path: β not applicable

    # ── Wave 4.7.3: append this vision to the version ledger (Task 2) ────────
    # Lightweight, client-persisted (same round-trip pattern as history /
    # structural_identity). The client echoes `versions` back so SPECIFIC_VERSION
    # and LATEST resolution work without server-side session storage.
    _new_version = VersionRecord(
        version_id=new_version_id(),
        vision_number=iteration,
        source_mode_used=_resolved.mode_resolved,
        source_version_id_used=_resolved.source_version_id,
        source_image_url_used=generation_image_url,
        generated_image_url=public_url,
        atmosphere=style_label,
        user_request=prompt[:240],
        structural_permission=structural_permission,
        structural_identity_token=structural_identity_token,
        lineage_customized=_new_lineage_customized,
    )
    _updated_versions = _versions + [_new_version]
    log.info(
        "[VersionState] persisted version_id=%s vision_number=%d ledger_size=%d",
        _new_version.version_id, _new_version.vision_number, len(_updated_versions),
    )

    # ── Wave 5.6 — Backend-side message persistence ──────────────────────────
    # Write the AI image_result message to Supabase BEFORE returning the HTTP
    # response. If the client has navigated away mid-generation, this ensures
    # the result is still recoverable on next session reopen (frontend's
    # _loadMessages fetches it). Best-effort: on failure we log but still
    # return the generation result (frontend can fall back to its own
    # insertMessage via the message_persisted flag in the response).
    _message_persisted = False
    if session_id and session_id != "new":
        try:
            supa.from_("messages").insert({
                "session_id": session_id,
                "role": "ai",
                "content": ai_message,
                "message_type": "image_result",
                "before_image_url": generation_image_url,
                "after_image_url": public_url,
                "style_label": style_label,
            }).execute()
            _message_persisted = True
            log.info("[Wave 5.6] message persisted server-side  session_id=%s", session_id)
        except Exception as msg_err:
            log.warning(
                "[Wave 5.6] server-side message insert FAILED — frontend will fall back: %s: %s",
                type(msg_err).__name__, msg_err,
            )

    payload = {
        "after_image_url": public_url,
        "thumbnail_url": public_url,
        "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
        "suggestions": suggestions,
        "request_id": request_id,
        # Generation Intent v1 (PR1) — durable identity, returned for
        # propagation/debug. The frontend may memorise it (spec §3) ; it is NOT
        # yet load-bearing (client_request_id remains the active idempotency key).
        "intent_id": _intent.id,
        # #8 — the room actually used (e.g. an exterior detected by Ayden Decide),
        # so the client can fill its header when the room was AI-delegated. Empty
        # for the lean interior Ayden Decide path (unchanged).
        "room_type": room_type,
        # Wave 4.7.2: client persists this in session state and echoes it back
        # on every subsequent /generate so the apartment's structural identity is
        # captured ONCE (at V1) and reused deterministically forever.
        "structural_identity": structural_identity_token,
        # Kill-switch (2026-07-07): tell the client capture is off so it DROPS any
        # stale local token (empty responses alone don't, due to its isNotEmpty
        # guard). Absent/false in double mode → historical frontend behaviour.
        "structural_capture_disabled": _cap_mode == "off",
        # Wave 4.7.3: client persists the ledger + this record and echoes
        # `versions` back so source_mode=LATEST/SPECIFIC_VERSION resolve correctly.
        "version_id": _new_version.version_id,
        "version_record": version_to_dict(_new_version),
        "versions": serialize_versions(_updated_versions),
        # Wave 5.6 — frontend uses this flag to decide whether to do its own
        # insertMessage fallback. True = backend already wrote the message;
        # False = backend write failed, frontend should do its own write.
        "message_persisted": _message_persisted,
    }

    # OBSERVATION — Intent SUCCEEDED. On stocke le PAYLOAD COMPLET dans result_ref
    # (pas un format réduit) : sur un re-tir de la MÊME intention, le claim renvoie
    # ce result_ref VERBATIM → le frontend reçoit exactement le même JSON qu'un
    # succès normal, sans savoir qu'il y a eu replay. Best-effort ; ne bloque pas
    # la réponse. (Un intent réparé par PR4 n'aura pas ce payload → le replay
    # bascule alors en 202 côté claim, jamais un JSON simplifié inventé.)
    # Issue 13 — succès commité : le hold ne doit plus jamais être relâché.
    setattr(request.state, _HOLD_STATE_ATTR, None)
    await observe_intent_end(_intent.id, "SUCCEEDED", result_ref=payload,
                             is_free=_decision.consumes_free_quota)

    _total_elapsed = time.monotonic() - _req_start
    _est_cost = estimate_cost_usd(
        quality=profile.quality,
        size=output_size,
        openai_attempts=_timer.openai_attempt_count(),
        vision_calls=1,
    )
    # PR0 — enrich the PERF line so gpt-image-2/low prod records are separable
    # from historical gpt-image-1/medium, and the pre-flight gates are measured.
    _gen_type = ("v1" if iteration == 1
                 else "switch" if generation_trigger == "switch"
                 else "v2")
    # Log the EFFECTIVE quality sent to the model, NOT profile.quality. gpt-image-2
    # hard-overrides quality→"low" just before edit_kwargs (main.py ~4011), so
    # profile.quality (=medium on MOBILE_MVP_BASELINE) is the KNOWN cosmetic
    # PRE-override value (see memory gpt_image_2_migration, "piège #1"). Logging
    # profile.quality would make PR0 perpetuate the very "quality=medium" artifact
    # it exists to dispel.
    _effective_quality = ("low" if IMAGE_MODEL.startswith("gpt-image-2")
                          else profile.quality)
    _timer.log_summary(
        log, _total_elapsed, _payload_bytes_est, len(design_prompt), _est_cost,
        model=IMAGE_MODEL, quality=_effective_quality, iteration=iteration,
        generation_type=_gen_type,
        preflight_ms=(_req_start - _handler_entry) * 1000.0,
        preflight_breakdown=_preflight_breakdown,  # fast-path : décompo repliée (0 log en +)
    )
    log.info(
        "[Generation Cost] mode=%s  duration=%.1fs  "
        "quality=%s  input_fidelity=%s  size=%s  "
        "prompt_chars=%d  compact_prompts=%s  "
        "request_id=%s",
        profile.name, _total_elapsed,
        profile.quality, profile.input_fidelity, output_size,
        len(design_prompt), profile.compact_prompts,
        request_id,
    )
    log.info("[AydenDecide] payload room_type=%r (returned to client → switches inherit)", room_type)
    log.info("=== /generate SUCCESS ===  request_id=%s", request_id)
    # #4 — cache the SUCCESS payload so a same-key replay / concurrent duplicate
    # returns it instead of launching a 2nd generation (failures are never
    # cached — only this success path writes). Clears the in-flight marker.
    if _idem_key is not None:
        _idem_put(_idem_key, payload)
    # #4 defense — also cache under the content key so an accidental re-fire with
    # a different client_request_id (within the 120s TTL) replays this success
    # instead of launching a 2nd OpenAI generation.
    if _idem_key2 is not None:
        _idem_put(_idem_key2, payload)
    # Phase B — fire-and-forget "vision ready" push (no-op unless PUSH_ENABLED +
    # FCM configured). Never blocks the response, never raises. Reaches the device
    # even when the app is backgrounded/suspended (where local notifs can't fire).
    _push_title, _push_body = {
        "fr": ("Votre vision est prête", "Touchez pour voir votre nouveau design."),
        "km": ("ចក្ខុវិស័យ​របស់​អ្នក​រួចរាល់​ហើយ", "ប៉ះ​ដើម្បី​មើល​ការ​រចនា​ថ្មី​របស់​អ្នក។"),
    }.get(ui_locale, ("Your vision is ready", "Tap to view your new design."))
    _push_task = asyncio.create_task(send_push(
        supa=supa,
        user_id=current_user.user_id,
        title=_push_title,
        body=_push_body,
        session_id=session_id or "",
    ))
    _push_bg_tasks.add(_push_task)
    _push_task.add_done_callback(_push_bg_tasks.discard)
    return payload


# ═══════════════════════════════════════════════════════════════════════════════
# REFINE ENGINE V2 — Moteur 2 (ISOLÉ). Ne touche NI /generate, NI le composer, NI la
# DNA/préservation/identité structurelle (Moteur 1 GELÉ). Contrat §9/§14 :
#   POST /refine         → status advisory (YELLOW/RED, 0 gen) | completed (image
#                          immédiate, verification=deferred) | error
#   POST /refine/verify  → verified | incomplete | unavailable + report + missing[]
# Spec : docs/REFINE_ENGINE_V2.md. Réutilise l'infra partagée (openai, supa, auth,
# storage 'generated', httpx) — aucune logique V1.
# ═══════════════════════════════════════════════════════════════════════════════
from refine.parser import parse_changes as _refine_parse, Change as _RefineChange
from refine.advisor import advise as _refine_advise, build_advisory_message as _refine_advisory_msg
from refine.normalizer import normalize_changes as _refine_normalize
from refine.engine import refine_generate as _refine_generate, prepare as _refine_prepare
from refine.verify import (verify as _refine_verify, build_report as _refine_build_report,
                           missing_changes as _refine_missing)
from refine.billing_hook import (reserve as _refine_bill_reserve, commit as _refine_bill_commit,
                                 refine_billing_enabled as _refine_billing_enabled)
# Phase 1 — Generation Orchestrator (lifecycle persistant partagé) branché sur /refine.
import intent_observer as _io
from refine import identity as _refine_identity, orchestrator_adapter as _refine_adapter
from generation_orchestrator import (run_generation as _run_generation,
                                     OrchestratorError as _OrchestratorError)

_REFINE_MIME_FALLBACK = "image/jpeg"


def _refine_change_to_dict(c: _RefineChange) -> dict:
    return {"type": c.type, "object": c.object, "detail": c.detail,
            "raw": c.raw, "normalized": c.normalized}


def _refine_change_from_dict(d: dict) -> _RefineChange:
    return _RefineChange(type=str(d.get("type", "modify")), object=str(d.get("object", "")),
                         detail=str(d.get("detail", "")), raw=str(d.get("raw", "")),
                         normalized=str(d.get("normalized", "")))


async def _refine_fetch_bytes(url: str) -> tuple[bytes, str]:
    """Télécharge une image (source/résultat). Patchable en test. Renvoie (bytes, mime)."""
    async with httpx.AsyncClient(timeout=30) as client:
        r = await client.get(url)
        r.raise_for_status()
        mime = (r.headers.get("content-type", _REFINE_MIME_FALLBACK).split(";")[0]
                or _REFINE_MIME_FALLBACK)
        return r.content, mime


def _refine_upload(session_id: str, data: bytes) -> str:
    """Upload le résultat refine dans le bucket 'generated' (même infra que /generate)."""
    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    path = f"{session_id or 'refine'}/{ts}_refine_{uuid.uuid4().hex[:8]}.jpg"
    supa.storage.from_("generated").upload(
        path=path, file=data, file_options={"content-type": "image/jpeg"})
    return supa.storage.from_("generated").get_public_url(path)


def _refine_persist_message(session_id: str, before_url: str, after_url: str, style_label: str) -> bool:
    """Persiste le message image_result côté serveur AVANT de répondre (ferme la
    fenêtre Q1 : kill post-gen/pré-insert → la réouverture réhydrate le refine).
    Calque de /generate (Wave 5.6). Best-effort ; patchable en test. Renvoie True si écrit."""
    if not session_id or session_id == "new":
        return False
    try:
        supa.from_("messages").insert({
            "session_id": session_id, "role": "ai", "content": "",
            "message_type": "image_result",
            "before_image_url": before_url, "after_image_url": after_url,
            "style_label": style_label,
        }).execute()
        return True
    except Exception as exc:  # noqa: BLE001 — l'échec d'écriture ne bloque pas la réponse
        log.warning("[refine] server-side message insert failed: %s: %s", type(exc).__name__, exc)
        return False


def _refine_intent_id(session_id: str, message: str, before_image_url: str) -> str:
    """ID déterministe (idempotence billing future) — pas de hash() salé."""
    h = hashlib.sha1(f"{session_id}|{message}|{before_image_url}".encode()).hexdigest()[:16]
    return f"refine:{session_id}:{h}"


def _refine_fire_and_forget(coro, label: str) -> None:
    """Logs/analytics/billing NON bloquants — jamais sur le chemin critique (§14)."""
    try:
        t = asyncio.create_task(coro)
        _push_bg_tasks.add(t)
        t.add_done_callback(_push_bg_tasks.discard)
    except Exception:  # noqa: BLE001 — l'observabilité ne casse jamais la réponse
        log.warning("[refine] fire-and-forget '%s' scheduling failed", label)


# ── Phase 1 : IO déterministe pour l'orchestrateur (upload upsert, message idempotent) ──
async def _refine_upload_deterministic(path: str, data: bytes) -> str:
    """Upload UPSERT sur un chemin DÉTERMINISTE (keyé intent_id) → UN SEUL objet logique
    quel que soit le nombre de re-runs. Renvoie l'URL publique DURABLE (bucket public)."""
    def _do():
        try:
            supa.storage.from_("generated").upload(
                path=path, file=data,
                file_options={"content-type": "image/jpeg", "upsert": "true"})
        except Exception as exc:  # noqa: BLE001 — objet déjà présent (re-run) → overwrite
            log.warning("[refine] upload upsert fallback→update path=%s err=%s", path, exc)
            supa.storage.from_("generated").update(
                path=path, file=data, file_options={"content-type": "image/jpeg"})
        return supa.storage.from_("generated").get_public_url(path)
    return await asyncio.to_thread(_do)


async def _refine_persist_message_idempotent(session_id: str, before_url: str, after_url: str,
                                             style_label: str, intent_id: str) -> bool:
    """Message image_result IDEMPOTENT : lookup (session, message_type, after_image_url)
    AVANT insertion → jamais dupliqué sur un re-run, jamais manquant. Best-effort."""
    if not session_id or session_id == "new":
        return False
    def _do():
        try:
            ex = (supa.from_("messages").select("id")
                  .eq("session_id", session_id).eq("message_type", "image_result")
                  .eq("after_image_url", after_url).limit(1).execute())
            if getattr(ex, "data", None):
                return True   # déjà présent → idempotent (0 doublon)
            supa.from_("messages").insert({
                "session_id": session_id, "role": "ai", "content": "",
                "message_type": "image_result", "before_image_url": before_url,
                "after_image_url": after_url, "style_label": style_label}).execute()
            return True
        except Exception as exc:  # noqa: BLE001
            log.warning("[refine] idempotent message insert failed: %s: %s", type(exc).__name__, exc)
            return False
    return await asyncio.to_thread(_do)


@app.post("/refine")
async def refine_endpoint(
    session_id: str = Form(...),
    message: str = Form(...),
    before_image_url: str = Form(...),     # la vision EXISTANTE à modifier (storage URL)
    room_type: str = Form(""),
    confirm: bool = Form(False),           # passe outre un advisory (Continue anyway)
    # ── Ledger adapter (ORCHESTRATION seulement — le package refine/ ignore tout ceci) ──
    # Le frontend echo l'état lignée ; l'endpoint (pas le moteur) construit le VersionRecord
    # et renvoie le MÊME contrat versions que /generate → refine = version de 1ʳᵉ classe.
    versions: str = Form(""),              # ledger client (JSON) round-trip
    structural_identity: str = Form(""),   # token identité — HÉRITÉ (le refine préserve l'identité)
    style_label: str = Form(""),           # atmosphère courante (pour le record)
    iteration: int = Form(1),              # numéro de vision de ce refine
    source_version_id: str = Form(""),     # version affichée dont ce refine dérive
    client_request_id: str = Form(""),     # PR0 — id partagé avec PerfC2P (correlation obs)
    operation_id: str = Form(""),          # Phase 1 — 1 soumission utilisateur = 1 operation_id (idempotence)
    retry_of_intent_id: str = Form(""),    # Phase 1 — Retry après FAILED (INFORMATIF : trace, jamais réouverture)
    ui_locale: str = Form("en"),           # BUG1 — langue du push "vision ready" (en|fr|km) ; défaut en
    # CORRECTIF PERF fast-path (2026-07-14) — get_current_user (JWT seul) au lieu de
    # require_active_identity : la garde merged_closed est foldée dans le gather du resolver
    # REMONTÉ ci-dessous (avant tout OpenAI) → 0 RTT séquentiel ajouté.
    current_user: CurrentUser = Depends(get_current_user),  # + fast-path 2026-07-14
):
    """Contrat unique (D-b) : advisory (YELLOW/RED, 0 gen) | completed (image immédiate,
    verification=deferred) | running (lost-claim récupérable). Moteur 2 isolé ; le
    lifecycle persistant est délégué au Generation Orchestrator (Phase 1)."""
    _handler_entry = time.monotonic()  # PR0 — true entry for the /refine [PERF SUMMARY]
    # Structural-capture kill-switch (2026-07-07) — in off mode the refine inherits
    # an EMPTY passport: any stale token the client still round-trips is dropped so
    # it can never resurface downstream. double = historical inherit-verbatim.
    _refine_cap_off = _resolve_structural_capture_mode() == "off"
    if _refine_cap_off:
        structural_identity = ""
    # ── CORRECTIF PERF fast-path — la garde merged_closed est foldée EN PARALLÈLE de la
    #    validation de propriété de session (lecture réseau DÉJÀ obligatoire) via un
    #    asyncio.gather → 0 RTT séquentiel ajouté vs le chemin d'avant, Y COMPRIS sur les
    #    chemins advisory/empty (qui NE lancent PAS le resolver). On N'exécute PAS le
    #    resolver ici (ces chemins le sautaient auparavant — le resolver reste au gate).
    #    Enforce AVANT _refine_parse/_refine_advise et avant toute écriture. Aucune écriture
    #    ni session créée avant ce point (ownership + identité = lectures).
    _t_own = time.monotonic()
    _own_ok, _id_read = await asyncio.gather(
        _validate_session_ownership(session_id=session_id, user_id=current_user.user_id),
        fetch_identity_active(current_user.user_id),
    )
    _ownership_ms = (time.monotonic() - _t_own) * 1000.0  # ownership ∥ identité (1 RTT mural)
    if not _own_ok:
        raise HTTPException(status_code=403, detail={
            "error_code": "SESSION_OWNERSHIP_DENIED",
            "user_message": "This project belongs to a different account.", "retryable": False})
    enforce_identity_read(_id_read, current_user.user_id)

    # 1) Parser
    _t_parse = time.monotonic()
    changes = await _refine_parse(message, client=openai)
    _parser_ms = (time.monotonic() - _t_parse) * 1000.0
    if not changes:
        return {"status": "error", "error": "empty_request",
                "user_message": "I couldn't read a change to make — could you rephrase?"}

    # 2) Request Advisor (AVANT génération). confirm=true → sauté (Continue anyway).
    if not confirm:
        advice = await _refine_advise(changes, room_type or None, client=openai)
        if advice.overall.value != "green":
            return {
                "status": "advisory",
                "advice": {
                    "overall": advice.overall.value,
                    "message": _refine_advisory_msg(advice),
                    "min_confidence": advice.min_confidence,
                    "flagged": [{"raw": a.change.raw, "verdict": a.verdict.value,
                                 "reason": a.reason, "alternative": a.alternative,
                                 "confidence": a.confidence} for a in advice.flagged],
                },
                "echo": {"changes": [_refine_change_to_dict(c) for c in changes],
                         "room_type": room_type},
            }

    # 3) GREEN → génération sous le Generation Orchestrator (lifecycle persistant partagé).
    #    operation_id OBLIGATOIRE : 1 soumission utilisateur = 1 operation_id → idempotence
    #    (double-tap/timeout/retry technique = même op ; regenerate/Retry-après-FAILED = nouvelle op).
    _op = (operation_id or client_request_id or "").strip()
    if not _op:
        raise HTTPException(status_code=422, detail={
            "error_code": "MISSING_OPERATION_ID",
            "user_message": "Missing operation id for this edit.", "retryable": False})

    _refine_normalize(changes)                     # normalize UNE fois (créatif)
    prepared = _refine_prepare(changes)            # resolve_conflicts + plan → plan/prompt FIGÉS (une fois)
    _billing_enabled = _refine_billing_enabled()   # AYDEN_REFINE_BILLING (défaut OFF)
    _struct_perm = any(c.type == "structure" for c in prepared.ordered_changes)

    intent_id = _refine_identity.refine_intent_id(current_user.user_id, session_id, _op)
    intent_meta = {
        **_refine_identity.build_intent_meta(
            operation_id=_op, source_version_id=source_version_id,
            changes_sig=_refine_identity.changes_signature(prepared.ordered_changes),
            edit_mode="refine", iteration=iteration, room_type=room_type, atmosphere=style_label,
            retry_of_intent_id=(retry_of_intent_id.strip() or None)),
        "billing_enabled": _billing_enabled,       # métadonnée persistée (le reconcile la LIT)
    }

    async def _msg_fn(*, session_id, before_url, after_url, style_label, intent_id, result_version_id):
        await _refine_persist_message_idempotent(session_id, before_url, after_url, style_label, intent_id)

    persist_fn = _refine_adapter.build_persist_result_fn(
        upload_fn=_refine_upload_deterministic,
        get_result_ref_fn=_io.get_intent_result_ref, set_result_ref_fn=_io.set_intent_result_ref,
        persist_message_fn=_msg_fn, source_image_url=before_image_url, atmosphere=style_label,
        room_type=room_type, style_label=style_label, user_request=message,
        structural_permission=_struct_perm, structural_identity_token=structural_identity)
    response_fn = _refine_adapter.build_response_fn(
        prior_versions_json=versions, conflicts=prepared.conflicts,
        changes=[_refine_change_to_dict(c) for c in prepared.ordered_changes],
        estimated_success=prepared.estimated_success)
    execute_fn = _refine_adapter.build_execute_fn(openai, prepared.prompt)

    # RC-PR3b — gate refine sur la MÊME source que /generate (bucket wallet/pass) :
    # un pass à 0 ne peut pas refine non plus. Débit refine reste OFF (Phase 1).
    import billing  # noqa: PLC0415 — lazy (parité /generate)
    # Resolver à sa POSITION D'ORIGINE (au gate) : les chemins advisory/empty ne
    # l'atteignent jamais → 0 RTT resolver pour eux (pas de régression). PAS d'include_
    # identity ici : la garde identité est DÉJÀ faite en tête, foldée dans l'ownership.
    _t_access = time.monotonic()
    _ref_access = await resolve_generation_access(current_user.user_id)
    _access_resolver_ms = (time.monotonic() - _t_access) * 1000.0  # replié dans le PERF SUMMARY
    _ref_gate = await billing.reserve_decision(
        user_id=current_user.user_id, is_free=_ref_access.consumes_free_quota,
        tier=_ref_access.tier)
    if not _ref_gate.allow:
        log.info("[BILLING-GATE] refine denied user=%s reason=%s available=%d",
                 current_user.user_id[:8], _ref_gate.reason, _ref_gate.wallet_available)
        raise GenerationError(
            error_code="QUOTA_EXHAUSTED",
            user_message=("You've used all the spaces in your plan. Unlock more to "
                          "keep refining with your AI Architect."),
            retryable=False, status_code=402, session_id=(session_id or ""))

    # ── P0 (2026-07-11) — DÉBIT ATOMIQUE du refine (parité /generate) ──────────
    # reserve_decision ci-dessus est INDICATIF ; ICI on POSE le HOLD atomique
    # (billing.try_hold : advisory-lock user + HOLD conditionnel solde≥1, pass-first puis
    # free, idempotent hold:<intent>). Le COMMIT/RELEASE terminal est DÉJÀ câblé
    # (observe_intent_end dans l'orchestrateur → apply_billing retrouve le bucket via
    # _intent_hold_bucket, SANS tier) → 1 refine produisant une image = 1 space débité,
    # remboursé (RELEASE) si échec. Aucun claim n'est posé ICI (il vit dans l'orchestrateur)
    # → sur deny, RIEN à terminaliser : on lève juste 402/503 AVANT tout coût OpenAI image.
    if _billing_enabled:
        _rhold = await billing.try_hold(
            user_id=current_user.user_id, intent_id=intent_id, tier=_ref_access.tier, supa=supa)
        if not _rhold.get("granted"):
            _rreason = _rhold.get("reason") or "insufficient_credits"
            if _rreason == "atomic_hold_missing":
                # RPC billing_try_hold absente (fenêtre deploy avant apply-SQL) → 503
                # transitoire (retryable), PAS un faux "quota exhausted".
                raise GenerationError(
                    error_code="BILLING_UNAVAILABLE",
                    user_message="We're finishing an update. Please try again in a moment.",
                    retryable=True, status_code=503, session_id=(session_id or ""))
            log.info("[BILLING-ATOMIC] refine deny user=%s intent=%s reason=%s → 402 avant OpenAI (0 coût image)",
                     current_user.user_id[:8], intent_id, _rreason)
            raise GenerationError(
                error_code="QUOTA_EXHAUSTED",
                user_message=("You've used all the spaces in your plan. Unlock more to "
                              "keep refining with your AI Architect."),
                retryable=False, status_code=402, session_id=(session_id or ""))

    try:
        resp = await _run_generation(
            kind="refine", user_id=current_user.user_id, session_id=session_id,
            operation_id=_op, intent_id=intent_id, intent_meta=intent_meta,
            iteration=iteration, is_free=False,           # billing OFF (Phase 1) → 0 écriture ledger
            source_image_url=before_image_url, max_attempts=2,
            fetch_source_fn=_refine_fetch_bytes, execute_fn=execute_fn,
            persist_result_fn=persist_fn, build_response_fn=response_fn,
            request_id=(client_request_id.strip() or _op))
    except _OrchestratorError as oe:
        # erreur STRUCTURÉE (502/503) — jamais un 500 brut vers le frontend
        raise GenerationError(error_code=oe.error_code, user_message=oe.user_message,
                              retryable=oe.retryable, request_id=oe.request_id,
                              status_code=oe.status_code, session_id=session_id)

    _refine_total_ms = (time.monotonic() - _handler_entry) * 1000.0
    log.info(
        "[PERF SUMMARY] request_id=%s  total_ms=%.0f  model=%s  quality=low  iteration=%d"
        "  gen_type=refine  parser_ms=%.0f  ownership_ms=%.0f  access_resolver_ms=%.0f"
        "  status=%s  intent=%s",
        (client_request_id.strip() or _op), _refine_total_ms, IMAGE_MODEL, iteration,
        _parser_ms, _ownership_ms, _access_resolver_ms, resp.get("status"), intent_id,
    )

    # RUNNING (lost-claim) → statut RÉCUPÉRABLE, aucune génération, pas d'extras 'completed'.
    if resp.get("status") != "completed":
        return resp

    # BUG1 (P0) — Phase B push "vision ready" pour le REFINE. MIROIR de /generate
    # (main.py:4849) : le refine ne le faisait PAS → aucune notif iOS quand l'app
    # est backgroundée/tuée (le local notif ne peut pas s'afficher, isolate gelé).
    # Fire-and-forget, additif, jamais bloquant, no-op si PUSH_ENABLED/FCM absent.
    # Uniquement sur 'completed' (une vraie image) — jamais sur 'running'.
    _rf_title, _rf_body = {
        "fr": ("Votre vision est prête", "Touchez pour voir votre nouveau design."),
        "km": ("ចក្ខុវិស័យ​របស់​អ្នក​រួចរាល់​ហើយ", "ប៉ះ​ដើម្បី​មើល​ការ​រចនា​ថ្មី​របស់​អ្នក។"),
    }.get(ui_locale, ("Your vision is ready", "Tap to view your new design."))
    _rf_push = asyncio.create_task(send_push(
        supa=supa,
        user_id=current_user.user_id,
        title=_rf_title,
        body=_rf_body,
        session_id=session_id or "",
    ))
    _push_bg_tasks.add(_rf_push)
    _rf_push.add_done_callback(_push_bg_tasks.discard)

    # 'completed' → merge des extras endpoint (identité héritée + kill-switch + before).
    return {
        **resp,
        "structural_identity": structural_identity,       # hérité (echo) — "" en mode off
        "structural_capture_disabled": _refine_cap_off,   # kill-switch → frontend efface le token
        "before_image_url": before_image_url,
        "message_persisted": True,                        # persist idempotent a écrit/vérifié le message
        "room_type": room_type,
    }


@app.post("/refine/verify")
async def refine_verify_endpoint(
    before_image_url: str = Form(...),     # original
    after_image_url: str = Form(...),      # résultat renvoyé par /refine
    changes: str = Form(...),              # JSON list des changements (echo de /refine)
    current_user: CurrentUser = Depends(require_active_identity),
):
    """Verify STATELESS (2e appel §14) : verified|incomplete|unavailable + report + missing[].
    Gratuit (vision gpt-4o-mini, PAS une génération). Moteur 2 isolé."""
    try:
        parsed = [_refine_change_from_dict(d) for d in json.loads(changes or "[]")]
    except Exception:  # noqa: BLE001
        parsed = []
    if not parsed:
        return {"verification": "unavailable",
                "report": "Ayden couldn't automatically verify this result.", "missing": []}
    orig, orig_mime = await _refine_fetch_bytes(before_image_url)
    edited, _ = await _refine_fetch_bytes(after_image_url)
    result = await _refine_verify(openai, orig, orig_mime, edited, parsed)
    return {
        "verification": result.status.value,
        "report": _refine_build_report(result, parsed),
        "missing": [_refine_change_to_dict(c) for c in _refine_missing(result, parsed)],
        "identity_preserved": result.identity_preserved,
        "needs_refinement": result.needs_refinement,
    }
