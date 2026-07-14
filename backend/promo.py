"""Sprint 1B (2026-06-10) — Promo / influencer / admin codes.

Backend-authoritative. ALL state-changing promo logic runs through the
SECURITY DEFINER Postgres RPCs defined in backend/sql/sprint_1b_promo.sql
(atomic, race-safe): redeem_promo_code, consume_promo_generation,
get_promo_access. This module only wraps those + the access resolver that
centralises the generation-access priority for /generate and /me/status.

Isolation: promo NEVER touches user_roles (RevenueCat subscription state) or
the usage_log free-quota ledger. Unlimited VIP = a promo_redemptions row with
unlimited=true — a fully parallel system.

Priority (resolve_generation_access):
  admin/premium  > promo_unlimited > promo_limited > free(watermark) > blocked
"""

import asyncio
import logging
import secrets
import time
from dataclasses import dataclass
from typing import Optional

from quota import (
    has_admin_role, is_admin_role, get_quota_status,
    fetch_roles_flags, count_active_usage, decide_quota,
)

log = logging.getLogger("promo")


def _get_supa():
    """Lazy import of the service-role client (avoids circular import)."""
    from main import supa  # noqa: PLC0415
    return supa


def _rpc_data(res):
    """supabase-py .rpc().execute() → .data. A jsonb-returning function may
    surface as the dict directly or wrapped in a 1-element list. Normalise."""
    data = getattr(res, "data", None)
    if isinstance(data, list):
        return data[0] if data else None
    return data


# ── RPC wrappers ─────────────────────────────────────────────────────────────


async def get_promo_access(user_id: str, *, supa=None) -> dict:
    """{unlimited_active: bool, limited_remaining: int, active_campaign: str|None}.

    Fail-open to the no-promo state so a DB hiccup never blocks a user (the
    free-quota / subscription paths remain authoritative independently)."""
    supa = supa or _get_supa()
    try:
        res = await asyncio.to_thread(
            lambda: supa.rpc("get_promo_access", {"p_user": user_id}).execute()
        )
        d = _rpc_data(res) or {}
        return {
            "unlimited_active": bool(d.get("unlimited_active", False)),
            "limited_remaining": int(d.get("limited_remaining", 0) or 0),
            "active_campaign": d.get("active_campaign"),
        }
    except Exception as exc:  # noqa: BLE001
        log.warning("[promo] get_promo_access failed open — user=%s err=%s", user_id, exc)
        return {"unlimited_active": False, "limited_remaining": 0, "active_campaign": None}


async def redeem_promo(user_id: str, code: str, *, supa=None) -> dict:
    """Atomic redemption via RPC. Returns the function's jsonb:
    {ok:true, type, unlimited, generation_limit, expires_at, campaign} or
    {ok:false, error:'invalid_code'|'inactive_code'|'expired_code'|
                      'already_redeemed'|'max_redemptions_reached'}."""
    supa = supa or _get_supa()
    res = await asyncio.to_thread(
        lambda: supa.rpc(
            "redeem_promo_code", {"p_user": user_id, "p_code": code}
        ).execute()
    )
    return _rpc_data(res) or {"ok": False, "error": "invalid_code"}


async def consume_promo_generation(user_id: str, *, supa=None) -> dict:
    """Atomic single-decrement of a limited promo generation. Called ONLY on a
    successful generation when the resolver picked tier='promo_limited'.
    {ok:true, remaining:int} or {ok:false, error:'no_promo_generations'}."""
    supa = supa or _get_supa()
    try:
        res = await asyncio.to_thread(
            lambda: supa.rpc(
                "consume_promo_generation", {"p_user": user_id}
            ).execute()
        )
        return _rpc_data(res) or {"ok": False, "error": "no_promo_generations"}
    except Exception as exc:  # noqa: BLE001
        # Fail-soft: the image already generated. Log; don't fail the request.
        log.warning("[promo] consume_promo_generation error — user=%s err=%s", user_id, exc)
        return {"ok": False, "error": "consume_error"}


# ── Access resolver (single source of truth for /generate + /me/status) ───────


@dataclass(frozen=True)
class AccessDecision:
    tier: str                       # admin|premium|promo_unlimited|promo_limited|free|blocked
    can_generate: bool
    clean_watermark: bool           # True → NO watermark
    bypass_scope: bool              # True → all rooms/atmospheres (skip free-tier restriction)
    consumes_free_quota: bool       # True → reserve a usage_log slot (free only)
    consume_promo_on_success: bool  # True → call consume_promo_generation on success
    # status context
    promo_unlimited_active: bool
    promo_generations_remaining: int
    active_promo_campaign: Optional[str]
    free_remaining: int
    # ── CORRECTIF PERF fast-path (2026-07-14) — garde identité foldée dans le gather ──
    # Renseignés UNIQUEMENT quand l'appelant passe include_identity=True (routes image
    # /generate, /refine). Défauts sûrs : les appelants non-image (/me/status, chat…)
    # ne les demandent pas → identity_checked=False, et ces routes gardent la dépendance
    # require_active_identity. read_ok True par défaut (jamais fail-open sur une route qui
    # ne fait pas la lecture). L'enforcement 403/503 est fait par
    # identity.enforce_identity_from_decision, PAS ici (cette fonction ne fait que LIRE).
    identity_checked: bool = False
    identity_read_ok: bool = True
    identity_merged_closed: bool = False


async def resolve_generation_access(
    user_id: str, *, supa=None, include_identity: bool = False,
) -> AccessDecision:
    """Resolve the user's effective generation access ONCE, in priority order.

    admin/premium > promo_unlimited > promo_limited > free(watermark) > blocked.
    Only the 'free' tier consumes the usage_log quota + gets a watermark + is
    scope-restricted. promo/premium are clean, unlimited-room, off-ledger.

    CORRECTIF PERF fast-path (2026-07-14) — include_identity : quand True (routes image
    /generate, /refine), on ajoute une 4ᵉ lecture (account_state.merged_closed) DANS LE
    MÊME asyncio.gather que roles/promo/usage → 0 RTT séquentiel ajouté. Cette fonction
    ne fait que LIRE : elle renseigne identity_checked/identity_read_ok/identity_merged_
    closed sur l'AccessDecision. L'enforcement 403/503 est fait par l'appelant via
    identity.enforce_identity_from_decision (AVANT toute écriture / OpenAI). La lecture
    identité est fail-CLOSED (jamais coercée en "actif"), à la différence des lectures
    roles/promo/usage qui restent fail-open."""
    supa = supa or _get_supa()
    # ── Variante B (2026-07-02) — les 3 lectures Supabase RÉELLEMENT indépendantes
    # (rôles / promo / count usage_log) en PARALLÈLE au lieu de 4 appels séquentiels.
    #   • is_admin est DÉRIVÉ de la lecture rôles (fetch_roles_flags) → 0 requête en
    #     plus (supprime l'ancien is_admin_role redondant, même table).
    #   • le count usage_log ne dépend pas des rôles → parallélisable ; decide_quota
    #     applique la MÊME décision (bypass court-circuite le count via has_bypass).
    # La décision d'accès (priorité plus bas) est INCHANGÉE — seule la concurrence de
    # fetch change. return_exceptions=True + coercition fail-open : une erreur ne peut
    # JAMAIS altérer la décision (parité avec les défauts fail-open existants ; ces
    # helpers avalent déjà leurs erreurs, ceci est une ceinture-bretelles).
    # [ACCESS-TIMING] par appel (chevauché) + total → mesure avant/après. warn ≥ 2 s.
    _t0 = time.monotonic()

    async def _timed(_name, _coro):
        _t = time.monotonic()
        try:
            return await _coro
        finally:
            _dt = (time.monotonic() - _t) * 1000.0
            (log.warning if _dt >= 2000 else log.info)(
                "[ACCESS-TIMING] %s took=%.0fms user=%s", _name, _dt, user_id[:8])

    # Base gather (roles/promo/usage) — INCHANGÉ. include_identity ajoute la lecture
    # account_state.merged_closed comme 4e coroutine DU MÊME gather → elle partage le
    # temps mural (0 RTT séquentiel). fetch_identity_active est importée en lazy pour
    # casser le cycle promo↔identity (identity.py n'importe jamais promo).
    _tasks = [
        _timed("fetch_roles_flags", fetch_roles_flags(user_id, supa=supa)),
        _timed("get_promo_access", get_promo_access(user_id, supa=supa)),
        _timed("count_active_usage", count_active_usage(user_id, supa=supa)),
    ]
    if include_identity:
        from identity import fetch_identity_active  # noqa: PLC0415 — lazy (anti-cycle)
        _tasks.append(_timed("fetch_identity_active", fetch_identity_active(user_id, supa=supa)))

    _results = await asyncio.gather(*_tasks, return_exceptions=True)
    _roles_res, _promo_res, _usage_res = _results[0], _results[1], _results[2]
    _identity_res = _results[3] if include_identity else None

    if isinstance(_roles_res, tuple):
        full, is_admin = _roles_res            # (has_bypass, is_admin) — cf. fetch_roles_flags
    else:
        log.warning("[ACCESS] roles fetch raised — fail-open free: %s", _roles_res)
        full, is_admin = False, False
    if isinstance(_promo_res, dict):
        promo = _promo_res
    else:
        log.warning("[ACCESS] promo fetch raised — fail-open no-promo: %s", _promo_res)
        promo = {"unlimited_active": False, "limited_remaining": 0, "active_campaign": None}
    used = _usage_res if isinstance(_usage_res, int) and not isinstance(_usage_res, bool) else 0

    # Identité (include_identity) — fail-CLOSED, DISTINCT des lectures fail-open ci-dessus :
    # on ne coerce JAMAIS en "actif". Un IdentityRead(read_ok=False) OU une exception qui
    # aurait échappé au helper → read_ok=False → l'appelant (enforce_identity_from_decision)
    # renverra 503. Jamais fail-open (un compte fusionné ne doit pas passer sur un hoquet).
    _id_checked = False
    _id_read_ok = True
    _id_merged = False
    if include_identity:
        from identity import IdentityRead  # noqa: PLC0415 — lazy (anti-cycle)
        _id_checked = True
        if isinstance(_identity_res, IdentityRead):
            _id_read_ok = _identity_res.read_ok
            _id_merged = _identity_res.merged_closed
        else:
            log.warning("[ACCESS] identity fetch raised — fail-CLOSED (503 côté appelant): %s",
                        _identity_res)
            _id_read_ok = False
            _id_merged = False

    q = decide_quota(full, used)
    free_remaining = max(0, q.limit - q.used)
    log.info("[ACCESS-TIMING] resolve_total took=%.0fms user=%s",
             (time.monotonic() - _t0) * 1000.0, user_id[:8])

    ctx = dict(
        promo_unlimited_active=promo["unlimited_active"],
        promo_generations_remaining=promo["limited_remaining"],
        active_promo_campaign=promo["active_campaign"],
        free_remaining=free_remaining,
        # fast-path identité (défauts sûrs quand include_identity=False)
        identity_checked=_id_checked,
        identity_read_ok=_id_read_ok,
        identity_merged_closed=_id_merged,
    )

    if full:
        return AccessDecision(
            tier=("admin" if is_admin else "premium"),
            can_generate=True, clean_watermark=True, bypass_scope=True,
            consumes_free_quota=False, consume_promo_on_success=False, **ctx,
        )
    if promo["unlimited_active"]:
        return AccessDecision(
            tier="promo_unlimited", can_generate=True, clean_watermark=True,
            bypass_scope=True, consumes_free_quota=False,
            consume_promo_on_success=False, **ctx,
        )
    if promo["limited_remaining"] > 0:
        return AccessDecision(
            tier="promo_limited", can_generate=True, clean_watermark=True,
            bypass_scope=True, consumes_free_quota=False,
            consume_promo_on_success=True, **ctx,
        )
    # Billing PR2b (voie a) — le resolver ne décide PLUS l'épuisement du quota.
    # Non-entitled → TOUJOURS tier="free" (pure identité). Le gate quota est le
    # WALLET (billing.reserve_decision), appliqué dans /generate APRÈS le scope.
    # `free_remaining` (usage_log) reste calculé pour l'AFFICHAGE legacy
    # (status/chat), mais ne gate plus rien ici. Le tier "blocked" disparaît.
    return AccessDecision(
        tier="free", can_generate=True, clean_watermark=False,
        bypass_scope=False, consumes_free_quota=True,
        consume_promo_on_success=False, **ctx,
    )


# ── Admin CRUD (service role; RLS bypassed) ───────────────────────────────────

# Unambiguous charset (no I/O/0/1/L) for human-typed codes.
_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


def generate_code() -> str:
    """Cryptographically random AYD-XXXX-XXXX."""
    def grp() -> str:
        return "".join(secrets.choice(_CODE_ALPHABET) for _ in range(4))
    return f"AYD-{grp()}-{grp()}"


async def create_promo_code(
    *, created_by: str, code: Optional[str], type_: str,
    generation_limit: Optional[int], max_redemptions: Optional[int],
    expires_at: Optional[str], campaign: Optional[str], note: Optional[str],
    supa=None,
) -> dict:
    """Insert a promo code (code normalised UPPER; auto-generated if absent).
    Raises on duplicate code (DB unique index) — caller maps to 409."""
    supa = supa or _get_supa()
    norm = (code or generate_code()).strip().upper()
    row = {
        "code": norm,
        "type": type_,
        "generation_limit": generation_limit if type_ == "limited_generations" else None,
        "max_redemptions": max_redemptions,
        "expires_at": expires_at,
        "active": True,
        "campaign": campaign,
        "note": note,
        "created_by": created_by,
    }
    res = await asyncio.to_thread(
        lambda: supa.table("promo_codes").insert(row).execute()
    )
    data = getattr(res, "data", None) or []
    return data[0] if data else row


async def list_promo_codes(*, supa=None) -> list:
    supa = supa or _get_supa()
    res = await asyncio.to_thread(
        lambda: supa.table("promo_codes")
        .select("*")
        .order("created_at", desc=True)
        .execute()
    )
    return getattr(res, "data", None) or []


async def set_promo_active(code_id: str, active: bool, *, supa=None) -> dict:
    supa = supa or _get_supa()
    res = await asyncio.to_thread(
        lambda: supa.table("promo_codes")
        .update({"active": active})
        .eq("id", code_id)
        .execute()
    )
    data = getattr(res, "data", None) or []
    return data[0] if data else {}


# ── Redeem rate limit (anti brute-force on guessable custom codes) ────────────
# Per-user attempt cap, per-uvicorn-worker in-memory. Codes are also bounded by
# max_redemptions + once-per-user, so this is defence-in-depth.

_REDEEM_ATTEMPTS: dict[str, list] = {}
_REDEEM_WINDOW_S = 3600.0
_REDEEM_MAX = 12


def check_redeem_rate(user_id: str) -> bool:
    """True if allowed; False if the user exceeded _REDEEM_MAX attempts/hour."""
    now = time.time()
    attempts = [t for t in _REDEEM_ATTEMPTS.get(user_id, []) if now - t < _REDEEM_WINDOW_S]
    if len(attempts) >= _REDEEM_MAX:
        _REDEEM_ATTEMPTS[user_id] = attempts
        return False
    attempts.append(now)
    _REDEEM_ATTEMPTS[user_id] = attempts
    return True
