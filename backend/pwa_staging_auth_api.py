"""Web auth endpoints — the phone-link PREPARE step. Mounted beside the PWA adapter.

WHY THIS ROUTER EXISTS
    GoTrue verifies a `phone_change` OTP by NUMBER, not by session
    (`internal/api/verify.go`: `FindUserByPhoneChangeAndAudience`), and the
    column is not unique. An abandoned attempt on another account can therefore
    answer to a later verification of the same number — a refusal with a real
    SMS OTP, and the WRONG USER'S SESSION with a project test OTP. Supabase's
    own guidance is application-level cleanup of stale `phone_change` values.

    So the client calls `POST …/auth/phone/prepare` right before
    `updateUser({phone})`. The server clears every expired attempt (project-
    wide) through ONE security-definer function (`pwa_staging.
    auth_phone_change_release`, migration 0010) and reports how many OTHER
    users still hold this number inside the OTP window. The client refuses to
    start while that count is non-zero.

WHAT IT NEVER DOES
    * expose the service key — the browser calls this with its own session
      token, the function is executed with the server's key, and the function
      itself is `service_role`-only;
    * touch the caller's own row, a row inside the grace period, or the
      verified `phone` column;
    * grant, debit, or read anything billing-related.

FAIL CLOSED, HONESTLY
    Missing function, missing key, PostgREST down: 503 `PHONE_PREPARE_UNAVAILABLE`.
    The client treats any non-2xx as "no answer" and proceeds under its own
    user-id guard — it only loses the early "please wait" warning.
"""
from __future__ import annotations

import logging
import os
import re
import time

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

import pwa_target
from pwa_staging_api import (_bearer, _supabase_url, _verify_user,
                            _verify_user_claims)

log = logging.getLogger("aih")

_TARGET = pwa_target.current()
router = APIRouter(prefix=f"{_TARGET.prefix}/auth", tags=[f"pwa-{_TARGET.name}-auth"])
_SCHEMA = _TARGET.schema

#: Rows older than this are released. GoTrue's default SMS OTP expiry is 60 s
#: (`sms_otp_exp`); the project is configured to at most 5 minutes
#: (`pwa_staging_auth_cambodia.py`). 10 minutes therefore releases only rows
#: whose token can no longer verify, whatever the exact project setting.
_GRACE_SECONDS = int(os.environ.get("PWA_PHONE_CHANGE_GRACE_S", "600"))

_E164 = re.compile(r"^\+?[1-9][0-9]{7,14}$")


def _service_key() -> str:
    return os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")


class PhonePrepareRequest(BaseModel):
    phone: str = Field(min_length=8, max_length=20)


# ── Which CUSTOM providers this project actually has ────────────────────────
#
# GoTrue's public `/auth/v1/settings` lists a FIXED struct of built-in providers
# (`internal/api/settings.go`) and says nothing about custom OAuth/OIDC ones. So
# the browser cannot discover `custom:telegram` the way it discovers Facebook,
# and a build flag would be a second source of truth that drifts from the
# project. This route is the answer: the SERVER asks the admin API with its own
# service key and reports one boolean per custom door.
#
# It returns booleans ONLY — never the identifier's client id, never a secret.
# Fails CLOSED: any error is "no custom door", so a button never appears for a
# provider that would refuse the person on arrival.

#: The one custom provider this launch knows about.
TELEGRAM_IDENTIFIER = "custom:telegram"

#: Cache for the admin lookup. The answer changes when an operator flips the
#: provider, which is rare; every boot of every visitor asking GoTrue's admin
#: API would not be.
_PROVIDERS_TTL_S = 60.0
_providers_cache: tuple[float, dict] | None = None


def telegram_enabled(payload: object) -> bool:
    """True only when the admin API says `custom:telegram` exists AND is enabled.

    Pure, so the contract is tested without a network: anything unexpected —
    a missing list, a different identifier, a non-boolean — reads as closed.
    """
    if not isinstance(payload, dict):
        return False
    providers = payload.get("providers")
    if not isinstance(providers, list):
        return False
    for p in providers:
        if isinstance(p, dict) and p.get("identifier") == TELEGRAM_IDENTIFIER:
            return p.get("enabled") is True
    return False


@router.get("/providers")
async def auth_providers() -> dict:
    """The custom doors this deployment can actually open. Booleans only."""
    global _providers_cache  # noqa: PLW0603 — one process-wide memo, by design
    now = time.monotonic()
    if _providers_cache and now - _providers_cache[0] < _PROVIDERS_TTL_S:
        return _providers_cache[1]

    key = _service_key()
    answer = {"telegram": False}
    if key:
        try:
            async with httpx.AsyncClient(timeout=10.0) as client:
                r = await client.get(
                    f"{_supabase_url()}/auth/v1/admin/custom-providers",
                    headers={"apikey": key, "Authorization": f"Bearer {key}"},
                )
            if r.status_code == 200:
                answer = {"telegram": telegram_enabled(r.json())}
            else:
                log.warning("[pwa-auth] custom-providers status %s", r.status_code)
        except (httpx.HTTPError, ValueError) as exc:
            log.warning("[pwa-auth] custom-providers unreachable: %s", type(exc).__name__)
    _providers_cache = (now, answer)
    return answer


@router.post("/post-signout-guest")
async def post_signout_guest(
    authorization: str | None = Header(default=None),
) -> dict:
    """Mark the guest created BY A SIGN-OUT as having already had its trial.

    THE ABUSE THIS CLOSES, reproduced on staging (2026-09-16): nothing fires on
    account creation and the free bucket ADDS the trial for as long as no TRIAL
    row exists, so every new anonymous user is projected a fresh one. Sign in,
    sign out, and the guest you land on has a full trial again — round and round,
    one Telegram authorisation per lap.

    The backend cannot tell that guest from a first-ever visitor: both are
    brand-new anonymous users, one second old, with no history. Only the client
    that just performed the sign-out knows, which is why it is the client that
    calls this — and why a first visit, which never calls it, keeps its trial.

    WHAT IT WRITES. Exactly what the mobile rail already writes, through the
    same canonical function: one `TRIAL(delta 0)` row on the idempotency key
    `trial:<uid>`. No credit is granted, none is taken, nothing is debited. The
    checks that already exist then read `trial_granted = true` and a free
    balance of 0 — the projection simply stops.

    THE USER IS THE TOKEN. `user_id` comes from GoTrue and from nowhere else:
    a body that named a victim would be a way to burn somebody else's trial.
    And the caller must be ANONYMOUS — marking a real account would be a bug
    with a permanent consequence, so it is refused outright.
    """
    token = _bearer(authorization)
    async with httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=10.0)) as client:
        user = await _verify_user_claims(client, token)

    if user.get("is_anonymous") is not True:
        # Not a guest: this marker has no meaning here, and writing it would
        # silently cost a real account its trial.
        raise HTTPException(
            status_code=400,
            detail={"error_code": "NOT_ANONYMOUS",
                    "user_message": "Only a guest account applies here.",
                    "retryable": False},
        )

    import billing  # noqa: PLC0415 — lazy, mirrors the adapter's other callers

    try:
        # Idempotent by construction: the key is `trial:<uid>`, so a replay
        # inserts nothing and the client may retry as often as it needs to.
        marked = await billing.mark_trial_consumed(user_id=user["id"])
    except Exception as exc:  # noqa: BLE001
        log.warning("[pwa-auth] post-signout marker failed user=%s err=%s",
                    user["id"][:8], type(exc).__name__)
        raise HTTPException(
            status_code=503,
            detail={"error_code": "POST_SIGNOUT_UNAVAILABLE",
                    "user_message": "Finishing guest setup. Please try again.",
                    "retryable": True},
        ) from exc

    log.info("[pwa-auth] post-signout guest marked user=%s new=%s",
             user["id"][:8], marked)
    return {"status": "ok", "marked": bool(marked)}


def _unavailable(why: str) -> HTTPException:
    log.warning("[pwa-auth] phone/prepare unavailable: %s", why)
    return HTTPException(
        status_code=503,
        detail={"error_code": "PHONE_PREPARE_UNAVAILABLE",
                "user_message": "Phone verification is not available right now.",
                "retryable": True},
    )


@router.post("/phone/prepare")
async def phone_prepare(body: PhonePrepareRequest,
                        authorization: str | None = Header(default=None)) -> dict:
    """Release expired `phone_change` rows and count live holders of this number."""
    raw = body.phone.strip().replace(" ", "")
    if not _E164.match(raw):
        raise HTTPException(
            status_code=422,
            detail={"error_code": "PHONE_INVALID",
                    "user_message": "That phone number does not look right.",
                    "retryable": False},
        )
    # GoTrue stores the number WITHOUT the '+' (`formatPhoneNumber`).
    digits = raw.lstrip("+")

    token = _bearer(authorization)
    key = _service_key()
    if not key:
        raise _unavailable("SUPABASE_SERVICE_ROLE_KEY absent")

    async with httpx.AsyncClient(timeout=15.0) as client:
        # WHO is asking comes from GoTrue, never from the body: the caller's
        # own row is the one the function must leave alone.
        user_id = await _verify_user(client, token)
        try:
            r = await client.post(
                f"{_supabase_url()}/rest/v1/rpc/auth_phone_change_release",
                headers={
                    "apikey": key,
                    "Authorization": f"Bearer {key}",
                    "Content-Profile": _SCHEMA,
                    "Content-Type": "application/json",
                },
                json={"p_phone": digits, "p_caller": user_id,
                      "p_grace_seconds": _GRACE_SECONDS},
            )
        except httpx.HTTPError as exc:  # noqa: PERF203 — one call, one seam
            raise _unavailable(f"postgrest {type(exc).__name__}") from exc

    if r.status_code != 200:
        raise _unavailable(f"rpc status {r.status_code}")
    rows = r.json() if r.content else []
    row = rows[0] if isinstance(rows, list) and rows else (rows if isinstance(rows, dict) else {})
    cleared = int(row.get("cleared", 0) or 0)
    contested = int(row.get("contested", 0) or 0)
    log.info("[pwa-auth] phone/prepare user=%s…  cleared=%d contested=%d grace=%ds",
             user_id[:8], cleared, contested, _GRACE_SECONDS)
    return {
        "cleared": cleared,
        "contested": contested,
        "grace_seconds": _GRACE_SECONDS,
    }
