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

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

import pwa_target
from pwa_staging_api import _bearer, _supabase_url, _verify_user

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
