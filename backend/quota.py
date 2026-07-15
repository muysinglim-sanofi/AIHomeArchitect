"""
Wave 5.17b — Usage tracking + quota enforcement.

Public API
──────────
get_quota_status(user_id)          → QuotaStatus
reserve_generation(user_id, ...)   → reservation_id (str)
confirm_generation(reservation_id, cost_usd_estimate)
fail_generation(reservation_id)
has_admin_role(user_id)            → bool (cached 60s)

Design contract — reserve-then-confirm
──────────────────────────────────────
Per the Wave 5.17b plan §2.1, the quota counter MUST close the
parallel-request race :

  1. Quota check counts rows where status != 'failed'  (i.e.,
     'in_progress' AND 'success' both count). This prevents
     a malicious client from firing 10 simultaneous /generate
     calls and all 10 passing the gate before any of them
     finish.

  2. reserve_generation() INSERTs a row with status='in_progress'
     BEFORE the OpenAI call. The row immediately bumps the user's
     count.

  3. After the OpenAI call returns :
       - confirm_generation() → status='success'
       - fail_generation()    → status='failed'  (quota refunded)

  4. A row stuck in 'in_progress' (e.g., backend crashed
     mid-generation) keeps consuming quota until a cleanup job
     (Wave 5.17c) sweeps stale reservations. Acceptable for V1.

Admin bypass
────────────
Founders + internal testers granted the 'admin' role in user_roles
bypass the quota check entirely. The lookup is cached per-process
for 60 seconds to amortise the DB hit on hot founder testing
sessions.

The future 'premium' role (Wave 5.17c — RevenueCat) also bypasses
quota by the same mechanism, gated on expires_at.
"""

from __future__ import annotations
import asyncio
import logging
import time
import uuid
from dataclasses import dataclass
from typing import Optional

from free_tier_config import TOTAL_FREE_GENERATIONS

log = logging.getLogger("wave_5_17b.quota")


# ── Tunable constants ───────────────────────────────────────────────────────

FREE_TIER_LIMIT = TOTAL_FREE_GENERATIONS   # FT1 (2026-07-15) — plafond gratuit TOTAL (1 anon + 2 création), centralisé dans free_tier_config. Affichage /me/status uniquement (autorité = billing ledger).
_ROLE_CACHE_TTL_SECONDS = 60        # admin/premium role lookup cache window
_BYPASS_ROLES = {"admin", "premium"} # any role in this set bypasses quota


# ── Public model ────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class QuotaStatus:
    """Result of `get_quota_status`. Caller dispatches based on `.allowed`."""
    allowed: bool
    used: int
    limit: int
    reason: str           # 'within_quota' | 'quota_exhausted' | 'admin_bypass' | 'premium'


# ── Role cache (in-process, per-worker) ─────────────────────────────────────
#
# Maps user_id → (expires_at_unix, has_bypass_role_bool). On cache hit, no
# DB call. On miss / expiry, look up `user_roles` for an active bypass role
# (admin OR premium), respecting `expires_at`. Cache is per-uvicorn-worker —
# multiple workers = duplicated lookups but no correctness issue.

_role_cache: dict[str, tuple[float, bool, bool]] = {}   # user_id → (expires_at, has_bypass, is_admin)


def _cache_lookup(user_id: str) -> Optional[tuple[bool, bool]]:
    entry = _role_cache.get(user_id)
    if entry is None:
        return None
    expires_at, has_bypass, is_admin = entry
    if expires_at < time.time():
        _role_cache.pop(user_id, None)
        return None
    return (has_bypass, is_admin)


def _cache_set(user_id: str, has_bypass: bool, is_admin: bool) -> None:
    _role_cache[user_id] = (time.time() + _ROLE_CACHE_TTL_SECONDS, has_bypass, is_admin)


def _role_active(expires_at, now_ts: float) -> bool:
    """A user_roles row is active if no expiry, a future expiry, or an unparseable
    expiry (assume active to avoid wrongly blocking). Shared by the role lookups."""
    if expires_at is None:
        return True
    try:
        from datetime import datetime
        return datetime.fromisoformat(expires_at.replace("Z", "+00:00")).timestamp() > now_ts
    except (ValueError, AttributeError):
        return True


# ── Supabase access ─────────────────────────────────────────────────────────
#
# `supa` is the service-role supabase client created in main.py at module
# load. We accept it as a function-injected dependency so this module stays
# testable in isolation (the validation harness can pass a fake supabase
# stub). Production code imports the live client via `_get_supa()`.


def _get_supa():
    """Lazy import to avoid circular dependency at module load."""
    from main import supa  # noqa: PLC0415
    return supa


# ── Public API ──────────────────────────────────────────────────────────────


async def is_admin_role(user_id: str, *, supa=None) -> bool:
    """Wave 5.18 — admin-specific check for /me/access endpoint.

    True iff the user has an active role == 'admin' in user_roles
    (NOT 'premium'). Distinct from `has_admin_role` which is the
    BYPASS check (admin OR premium combined). This function is used
    by the Developer Validation Mode endpoint to expose the admin
    flag to the frontend without conflating it with subscription state.

    The frontend combines `accessProvider.isAdmin` with the existing
    `premiumProvider` (driven by RevenueCat) to compute full-access
    UI gating — keeping the two signals separate avoids race
    conditions on the live RC stream.

    Fail-open : if the DB lookup errors, return False (UI degrades
    to free tier ; backend bypass remains authoritative via the
    cached `has_admin_role` path).
    """
    supa = supa or _get_supa()
    try:
        result = await asyncio.to_thread(
            lambda: supa.table("user_roles")
            .select("role, expires_at")
            .eq("user_id", user_id)
            .eq("role", "admin")
            .execute()
        )
        rows = getattr(result, "data", None) or []
    except Exception as exc:
        log.warning(
            "[Wave 5.18] is_admin_role lookup failed open — user=%s error=%s",
            user_id, exc,
        )
        return False

    now_ts = time.time()
    for r in rows:
        expires_at = r.get("expires_at")
        if expires_at is None:
            return True  # permanent admin
        try:
            from datetime import datetime
            expires_dt = datetime.fromisoformat(
                expires_at.replace("Z", "+00:00")
            )
            if expires_dt.timestamp() > now_ts:
                return True
        except (ValueError, AttributeError):
            return True  # unparseable expiry → assume active
    return False


async def fetch_roles_flags(user_id: str, *, supa=None) -> tuple[bool, bool]:
    """UNE lecture `user_roles` → (has_bypass, is_admin). Cachée 60 s par user.

    has_bypass = un rôle actif dans _BYPASS_ROLES (admin OU premium) ;
    is_admin   = un rôle actif == 'admin' (sous-ensemble).

    Source UNIQUE partagée par has_admin_role et par resolve_generation_access
    (chemin parallèle) → supprime la requête `is_admin_role` redondante côté
    resolver. Fail-open (False, False) — comme l'ancien has_admin_role : un
    hoquet DB ne bloque personne (le quota via usage_log reste indépendant)."""
    cached = _cache_lookup(user_id)
    if cached is not None:
        return cached

    supa = supa or _get_supa()
    try:
        result = await asyncio.to_thread(
            lambda: supa.table("user_roles")
            .select("role, expires_at")
            .eq("user_id", user_id)
            .execute()
        )
        rows = getattr(result, "data", None) or []
    except Exception as exc:
        log.warning(
            "[Wave 5.17b] role lookup failed open — user=%s error=%s",
            user_id, exc,
        )
        _cache_set(user_id, False, False)
        return (False, False)

    now_ts = time.time()
    has_bypass = False
    is_admin = False
    for r in rows:
        if not _role_active(r.get("expires_at"), now_ts):
            continue
        role = r.get("role")
        if role in _BYPASS_ROLES:
            has_bypass = True
        if role == "admin":
            is_admin = True

    _cache_set(user_id, has_bypass, is_admin)
    return (has_bypass, is_admin)


async def has_admin_role(user_id: str, *, supa=None) -> bool:
    """True iff the user has an active 'admin' or 'premium' role in user_roles.
    Cached 60s per user. Delegates to fetch_roles_flags (the single roles read)."""
    return (await fetch_roles_flags(user_id, supa=supa))[0]


def decide_quota(has_bypass: bool, used: int) -> QuotaStatus:
    """Décision quota PURE depuis (has_bypass, used). Aucun I/O. Ordre INCHANGÉ :
    bypass → admin_bypass(used=0) ; used<limit → within_quota ; sinon quota_exhausted."""
    if has_bypass:
        return QuotaStatus(allowed=True, used=0, limit=FREE_TIER_LIMIT, reason="admin_bypass")
    if used < FREE_TIER_LIMIT:
        return QuotaStatus(allowed=True, used=used, limit=FREE_TIER_LIMIT, reason="within_quota")
    return QuotaStatus(allowed=False, used=used, limit=FREE_TIER_LIMIT, reason="quota_exhausted")


async def count_active_usage(user_id: str, *, supa=None) -> int:
    """Compte les usage_log status != 'failed' (la consommation free-quota). L'index
    partiel (user_id, status) WHERE status != 'failed' garde ça tendu. Fail-open → 0
    (miroir du fail-open existant de get_quota_status = within_quota). Isolé pour que
    resolve_generation_access le lance EN PARALLÈLE des lectures rôles + promo (le
    count ne dépend pas du résultat rôles)."""
    supa = supa or _get_supa()
    try:
        result = await asyncio.to_thread(
            lambda: supa.table("usage_log")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .neq("status", "failed")
            .execute()
        )
        return getattr(result, "count", None) or 0
    except Exception as exc:
        log.warning(
            "[Wave 5.17b] quota count failed open — user=%s error=%s",
            user_id, exc,
        )
        return 0


async def get_quota_status(user_id: str, *, supa=None) -> QuotaStatus:
    """
    Return the user's current quota state.

    Decision order :
      1. Admin / premium bypass → allowed=True, reason='admin_bypass'
      2. Count usage_log rows where status != 'failed'
      3. If count < FREE_TIER_LIMIT → allowed=True, reason='within_quota'
      4. Else → allowed=False, reason='quota_exhausted'

    Délègue à fetch_roles_flags + count_active_usage + decide_quota (résultat
    INCHANGÉ ; les briques de fetch sont désormais réutilisables par le resolver
    parallèle). Standalone : bypass court-circuite le count comme avant."""
    has_bypass, _ = await fetch_roles_flags(user_id, supa=supa)
    if has_bypass:
        return decide_quota(True, 0)
    used = await count_active_usage(user_id, supa=supa)
    return decide_quota(False, used)


async def reserve_generation(
    *,
    user_id: str,
    session_id: Optional[str],
    request_id: str,
    supa=None,
) -> str:
    """INSERT a 'in_progress' usage_log row. Returns the row id. The
    row counts against quota immediately — even before the OpenAI call
    completes — so parallel requests cannot bypass the gate.
    """
    supa = supa or _get_supa()
    row_id = str(uuid.uuid4())
    try:
        await asyncio.to_thread(
            lambda: supa.table("usage_log")
            .insert({
                "id": row_id,
                "user_id": user_id,
                "session_id": session_id if session_id and session_id not in ("new", "") else None,
                "call_type": "generate",
                "status": "in_progress",
                "request_id": request_id,
            })
            .execute()
        )
        log.info(
            "[Wave 5.17b] quota reserved — user=%s reservation=%s request_id=%s",
            user_id, row_id, request_id,
        )
        return row_id
    except Exception as exc:
        log.error(
            "[Wave 5.17b] reserve_generation FAILED — user=%s error=%s",
            user_id, exc,
        )
        # Re-raise — the caller (main.py /generate) decides how to handle.
        # Failing the reservation means we have no quota record, so we
        # would either block the user (strict) or allow without tracking
        # (lenient). Strict is safer for cost ; lenient is safer for UX.
        # We RE-RAISE so the caller can decide. In main.py we treat this
        # as a 500 error.
        raise


async def confirm_generation(
    reservation_id: str,
    *,
    cost_usd_estimate: float = 0.0,
    supa=None,
) -> None:
    """UPDATE the reservation row to status='success' + record the cost
    estimate. Idempotent : re-confirming an already-confirmed row is a
    no-op.
    """
    supa = supa or _get_supa()
    try:
        await asyncio.to_thread(
            lambda: supa.table("usage_log")
            .update({
                "status": "success",
                "cost_usd_estimate": cost_usd_estimate,
                "completed_at": "now()",
            })
            .eq("id", reservation_id)
            .execute()
        )
        log.info(
            "[Wave 5.17b] quota confirmed — reservation=%s cost_usd=%.4f",
            reservation_id, cost_usd_estimate,
        )
    except Exception as exc:
        log.warning(
            "[Wave 5.17b] confirm_generation failed — reservation=%s error=%s",
            reservation_id, exc,
        )
        # Confirmation failure is non-blocking : the row stays
        # 'in_progress' and will be swept by a future cleanup job. The
        # user got their image ; we just lose precise cost tracking.


async def fail_generation(reservation_id: str, *, supa=None) -> None:
    """UPDATE the reservation row to status='failed'. Used when the
    OpenAI call errored and we believe no cost was incurred (refunding
    the quota slot so the user can retry without consuming it).
    """
    supa = supa or _get_supa()
    try:
        await asyncio.to_thread(
            lambda: supa.table("usage_log")
            .update({
                "status": "failed",
                "completed_at": "now()",
            })
            .eq("id", reservation_id)
            .execute()
        )
        log.info(
            "[Wave 5.17b] quota refunded — reservation=%s",
            reservation_id,
        )
    except Exception as exc:
        log.warning(
            "[Wave 5.17b] fail_generation failed — reservation=%s error=%s",
            reservation_id, exc,
        )
        # If we can't mark it failed, the row stays 'in_progress' and
        # consumes quota. User loses one free gen on backend errors.
        # Acceptable failure mode ; cleanup job in 5.17c sweeps stuck
        # reservations.


# ── Test helpers ────────────────────────────────────────────────────────────

def _clear_role_cache() -> None:
    """Test-only — clear the role cache so a granted-then-tested admin
    role is picked up immediately. Production callers never need this.
    """
    _role_cache.clear()
