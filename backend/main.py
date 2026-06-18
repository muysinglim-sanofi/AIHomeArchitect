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
from fastapi.responses import JSONResponse
from openai import AsyncOpenAI, BadRequestError
from supabase import create_client

# Wave 5.17a — Identity foundation
from auth import CurrentUser, get_current_user
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
# Wave 5.17d — Free-tier scope (room + atmosphere allowlist for non-premium)
from free_tier import check_restrictions
# Wave 5.17d — RevenueCat webhook receiver (POST /webhooks/revenuecat)
from revenuecat_webhook import router as revenuecat_router, _upsert_premium
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
from prompt_engine.preservation import HIGH_FIDELITY_ATMOSPHERES  # PHASE 1.2 — shared with composer's contract-light decision (single source of truth)
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
    serialize_versions,
    version_to_dict,
    resolve_source,
    new_version_id,
    build_source_continuity_clause,
)

from generation_profiles import get_active_profile, list_profiles
from retry_classifier import classify_for_retry, RetryVerdict
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


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Wave 5.17d — Mount the RevenueCat webhook router. The endpoint is
# POST /webhooks/revenuecat ; see revenuecat_webhook.py for the contract.
app.include_router(revenuecat_router)

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
    current_user: CurrentUser = Depends(get_current_user),
):
    """Return {is_admin: bool} for the authenticated user."""
    return {
        "is_admin": await is_admin_role(current_user.user_id),
    }


@app.get("/me/status")
async def get_me_status(
    current_user: CurrentUser = Depends(get_current_user),
):
    """Sprint 1 — READ-ONLY premium + quota snapshot for the UI.

    The backend remains the sole authority: this endpoint only *reports* the
    server-side state (RevenueCat → user_roles → quota). The client cannot use
    it to grant itself anything.

    Returns: is_premium, is_admin, role, quota_used, quota_limit,
    remaining_free_generations (null when premium/admin = unlimited).
    """
    # Sprint 1B — one resolution covers subscription + promo + free quota.
    d = await resolve_generation_access(current_user.user_id)
    is_admin = d.tier == "admin"
    is_premium = d.tier in ("admin", "premium")            # subscription/admin ONLY (promo ≠ premium)
    unlimited = is_premium or d.promo_unlimited_active      # remaining_free is null only when truly unlimited
    return {
        # ── existing Sprint 1 fields (unchanged shape) ──
        "is_premium": is_premium,
        "is_admin": is_admin,
        "role": "admin" if is_admin else ("premium" if is_premium else "free"),
        "quota_used": max(0, FREE_TIER_LIMIT - d.free_remaining),
        "quota_limit": FREE_TIER_LIMIT,
        "remaining_free_generations": None if unlimited else d.free_remaining,
        # ── Sprint 1B — promo fields ──
        "promo_generations_remaining": d.promo_generations_remaining,
        "promo_unlimited_active": d.promo_unlimited_active,
        "active_promo_campaign": d.active_promo_campaign,
        "effective_access_state": d.tier,                  # admin|premium|promo_unlimited|promo_limited|free|blocked
        "can_generate": d.can_generate,
    }


@app.post("/purchases/sync")
async def purchases_sync(
    current_user: CurrentUser = Depends(get_current_user),
):
    """Sprint 1 — fallback reconciliation when the RevenueCat webhook is delayed
    or missed.

    Reads the subscriber's entitlement directly from the RevenueCat REST API
    (server secret key) and, if 'premium' is active, UPSERTs the user_roles row
    via the SAME helper the webhook uses. Flow is RC → backend → user_roles;
    the client never asserts premium. Idempotent (upsert on (user_id, role)).
    """
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
    ent = (((data.get("subscriber") or {}).get("entitlements") or {}).get("premium")) or {}
    expires = ent.get("expires_date")  # ISO-8601, or None for lifetime
    active = False
    if ent:
        if expires is None:
            active = True
        else:
            try:
                exp_dt = datetime.fromisoformat(expires.replace("Z", "+00:00"))
                active = exp_dt > datetime.now(timezone.utc)
            except Exception:
                active = False

    if active:
        await _upsert_premium(
            supa=supa,
            user_id=uid,
            expires_at_iso=expires,
            event_type="MANUAL_SYNC",
            event_id="purchases_sync",
        )
        log.info("[purchases/sync] premium reconciled user=%s expires=%s", uid, expires)
        return {"synced": True, "is_premium": True, "expires_at": expires}

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
    current_user: CurrentUser = Depends(get_current_user),
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
    current_user: CurrentUser = Depends(get_current_user),
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
    current_user: CurrentUser = Depends(get_current_user),
):
    await _require_admin(current_user)
    return {"codes": await list_promo_codes()}


@app.patch("/admin/promo-codes/{code_id}")
async def admin_patch_promo_code(
    code_id: str,
    payload: dict = Body(...),
    current_user: CurrentUser = Depends(get_current_user),
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
    current_user: CurrentUser = Depends(get_current_user),  # Wave 5.17a
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
        return {
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": suggestions,
            "should_generate": False,
            "intent": "conversation",
            "sub_intent": meta.intent.value,
            "session_language": meta.target_language,
        }

    _lang_for_4_11a = (
        "km" if _early_session_memory.session_language == "km" else "en"
    )

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
        return {
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": suggestions,
            "should_generate": True,
            "intent": intent_class.intent.value,
            "sub_intent": intent_class.sub_intent.value,
            "session_language": session_memory.session_language,
        }

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
        return {
            "ai_message": await localize_reply(openai, _clarification.clarification_text, ui_locale, enabled=_norm_enabled()),
            "suggestions": [],
            "should_generate": False,
            "intent": "design_discussion",
            "sub_intent": "design_discussion",
            "session_language": _early_session_memory.session_language,
        }

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

    # ── Wave 4.11a: PRODUCT_HELP / SUPPORT direct routing — the pre-filter
    # inside classify_intent returns one of these when the user is asking
    # about the product rather than asking for a design change. Look up the
    # specific topic answer in product_knowledge and return it ; never
    # trigger a generation on these paths.
    if intent_class.intent in (
        ConversationIntent.PRODUCT_HELP,
        ConversationIntent.SUPPORT,
    ):
        topic_id = detect_product_help(message, language=_lang_for_4_11a)
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
        return {
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": [],
            "should_generate": False,
            "intent": intent_class.intent.value,
            "sub_intent": intent_class.sub_intent.value,
            "session_language": _early_session_memory.session_language,
        }

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
        return {
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": [],
            "should_generate": False,
            "intent": intent_class.intent.value,
            "sub_intent": intent_class.sub_intent.value,
            "session_language": _early_session_memory.session_language,
        }

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
        return {
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": suggestions,
            "should_generate": False,
            "intent": "conversation",
            "sub_intent": intent_class.sub_intent.value,
            "session_language": session_memory.session_language,
        }

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
        return {
            "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
            "suggestions": suggestions,
            "should_generate": False,
            "intent": "conversation",
            "sub_intent": intent_class.sub_intent.value,
            "session_language": session_memory.session_language,
        }

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

    return {
        "ai_message": await localize_reply(openai, ai_message, ui_locale, enabled=_norm_enabled()),
        "suggestions": suggestions,
        "should_generate": should_generate,
        "intent": intent_class.intent.value,
        "sub_intent": intent_class.sub_intent.value,
        "session_language": meta.language,
    }


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
    structural_identity: str = Form(""),  # Wave 4.7.2 — persisted apartment identity token (client round-trip)
    source_mode: str = Form(""),          # Wave 4.7.3 — ORIGINAL | LATEST | SPECIFIC_VERSION (missing => default)
    source_version_id: str = Form(""),    # Wave 4.7.3 — target version id when source_mode=SPECIFIC_VERSION
    versions: str = Form(""),             # Wave 4.7.3 — JSON ledger of prior versions (client round-trip)
    generation_mode: str = Form("preserve"),  # Wave 5.5.14b.1 — bimodal intent: "preserve" | "creative". Default matches today's behaviour. NOT YET ROUTED — read & logged only; composer wiring lands in Wave 5.5.14c.
    ui_locale: str = Form("en"),          # Phase 1 — authoritative reply/caption language (en|fr|km). Does NOT touch the generation prompt (English-internal).
    current_user: CurrentUser = Depends(get_current_user),  # Wave 5.17a
):
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
    _ownership_ok = await _validate_session_ownership(
        session_id=session_id, user_id=current_user.user_id
    )
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
    _decision = await resolve_generation_access(current_user.user_id)
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

    if not _decision.can_generate:
        log.info(
            "[Sprint 1B] generation blocked — user=%s tier=%s free_remaining=%d",
            current_user.user_id, _decision.tier, _decision.free_remaining,
        )
        raise HTTPException(
            status_code=402,
            detail={
                "error_code": "QUOTA_EXHAUSTED",
                "user_message": (
                    "Your free architectural explorations are complete. "
                    "Unlock unlimited redesigns and continue working with "
                    "your AI Architect."
                ),
                "quota_used": max(0, FREE_TIER_LIMIT - _decision.free_remaining),
                "quota_limit": FREE_TIER_LIMIT,
                "retryable": False,
                "request_id": "",
            },
        )
    log.info(
        "[Sprint 1B] access OK — user=%s tier=%s free_remaining=%d promo_remaining=%d promo_unlimited=%s",
        current_user.user_id, _decision.tier, _decision.free_remaining,
        _decision.promo_generations_remaining, _decision.promo_unlimited_active,
    )

    # ── Wave 5.17d — Free-tier scope check (Sprint 1B: promo bypasses too) ─────
    # Non-entitled users may only generate Living Room + (Nordic Warmth |
    # Soft Luxury). admin/premium AND promo (limited or unlimited) bypass —
    # _decision.bypass_scope is True for every tier except 'free'.
    if not _decision.bypass_scope:
        await check_restrictions(
            user_id=current_user.user_id,
            room_type_id=room_type_id,
            atmosphere_id=atmosphere_id,
            let_ai_decide=let_ai_decide,
            surprise_me=surprise_me_flag,
        )

    # ── Step 1: log request ───────────────────────────────────────────────────
    request_id = client_request_id.strip() or uuid.uuid4().hex

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
    structural_id_obj: ApartmentStructuralIdentity = EMPTY_IDENTITY
    if structural_identity.strip():
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
    _timer.record("struct_id", time.monotonic() - _t_sid)
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

    if surprise_me_flag:
        log.info("--- Surprise Me: selecting atmosphere for room=%s ---", room_type)
        selected_atmosphere = surprise_me(
            room_type=room_type,
            vision_description=room_description,
            user_prompt=prompt_en,
        )
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
    )
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
        "--- calling OpenAI images.edit (gpt-image-1, quality=%s, "
        "input_fidelity=%s, size=%s, mask=%s, max_attempts=%d) ---",
        profile.quality, profile.input_fidelity or "omitted",
        output_size, "yes" if mask_bytes else "no", profile.max_attempts,
    )

    _MAX_ATTEMPTS = profile.max_attempts
    _last_exc: Exception | None = None
    generated_bytes: bytes | None = None

    for _attempt in range(1, _MAX_ATTEMPTS + 1):
        _t0 = time.monotonic()
        log.info(
            "[OpenAI Attempt %d/%d] starting  (backend-controlled; SDK max_retries=%d)",
            _attempt, _MAX_ATTEMPTS, openai.max_retries,
        )
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
            # Wave 5.14A Last-Chance Step 4 / Option E REMOVED (2026-06-02
            # evening) — omit-both config triggered OpenAI default quality=
            # "auto" which heuristically selected "high" tier (~55s OpenAI
            # processing, ~4× the cost of medium). Latency + cost too high
            # vs visual gain. User reverted to Step 5 (quality=low set by
            # Step 1 + fidelity=OMIT set by Step 5 below).
            edit_kwargs: dict = dict(
                model="gpt-image-1",
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

            response = await openai.images.edit(**edit_kwargs)
            _elapsed = time.monotonic() - _t0
            _timer.record("openai_api", _elapsed, attempt=_attempt, status="success")
            log.info("[OpenAI Attempt %d/%d] succeeded in %.1fs", _attempt, _MAX_ATTEMPTS, _elapsed)

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
        # Wave 4.7.2: client persists this in session state and echoes it back
        # on every subsequent /generate so the apartment's structural identity is
        # captured ONCE (at V1) and reused deterministically forever.
        "structural_identity": structural_identity_token,
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
    _total_elapsed = time.monotonic() - _req_start
    _est_cost = estimate_cost_usd(
        quality=profile.quality,
        size=output_size,
        openai_attempts=_timer.openai_attempt_count(),
        vision_calls=1,
    )
    _timer.log_summary(log, _total_elapsed, _payload_bytes_est, len(design_prompt), _est_cost)
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
    log.info("=== /generate SUCCESS ===  request_id=%s", request_id)
    return payload
