"""
Phase B — FCM (Firebase Cloud Messaging) push, HTTP v1.

Sends a "your vision is ready" push when a generation completes while the app is
backgrounded/suspended (iOS local notifications can't fire then — the isolate is
suspended; only a server push reaches the device). Cross-platform (iOS + Android)
via FCM, which relays to APNs for iOS.

Design:
  • Per-user device tokens live in Supabase `device_tokens` (registered by the
    app via POST /devices).
  • send_push() is FIRE-AND-FORGET from /generate (never blocks the response,
    never raises into the request).
  • Fully gated: no-op unless PUSH_ENABLED=1 AND FCM creds are configured. The
    google-auth import is LAZY so the backend boots even without the dependency.

Env:
  PUSH_ENABLED               "1" to enable (default off)
  FCM_PROJECT_ID             Firebase project id
  FCM_SERVICE_ACCOUNT_JSON   the service-account JSON (full string)
"""

from __future__ import annotations

import json
import logging
import os
import time

import httpx

log = logging.getLogger("aih")

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"

# Cached OAuth access token (service-account tokens last ~1h).
_token_cache: dict = {"value": "", "exp": 0.0}


def push_enabled() -> bool:
    return (
        os.environ.get("PUSH_ENABLED", "0") == "1"
        and bool(os.environ.get("FCM_PROJECT_ID"))
        and bool(os.environ.get("FCM_SERVICE_ACCOUNT_JSON"))
    )


def _access_token() -> str:
    """OAuth2 access token from the service account (cached ~55 min). Lazy import
    so a missing google-auth dependency never breaks import/boot."""
    now = time.time()
    if _token_cache["value"] and now < _token_cache["exp"]:
        return _token_cache["value"]
    from google.oauth2 import service_account  # lazy
    from google.auth.transport.requests import Request  # lazy

    info = json.loads(os.environ["FCM_SERVICE_ACCOUNT_JSON"])
    creds = service_account.Credentials.from_service_account_info(
        info, scopes=[_FCM_SCOPE]
    )
    creds.refresh(Request())
    _token_cache["value"] = creds.token
    # creds.expiry is UTC datetime; refresh ~5 min early.
    _token_cache["exp"] = now + 55 * 60
    return creds.token


async def _user_tokens(supa, user_id: str) -> list[str]:
    try:
        res = (
            supa.table("device_tokens")
            .select("token")
            .eq("user_id", user_id)
            .execute()
        )
        return [r["token"] for r in (res.data or []) if r.get("token")]
    except Exception as exc:
        log.warning("[Push] token fetch failed: %s: %s", type(exc).__name__, exc)
        return []


async def _delete_token(supa, token: str) -> None:
    try:
        supa.table("device_tokens").delete().eq("token", token).execute()
    except Exception:
        pass


async def send_push(
    *,
    supa,
    user_id: str,
    title: str,
    body: str,
    session_id: str,
) -> None:
    """Fire-and-forget push to all of the user's devices. Never raises."""
    try:
        if not push_enabled() or not user_id:
            return
        tokens = await _user_tokens(supa, user_id)
        if not tokens:
            return
        project_id = os.environ["FCM_PROJECT_ID"]
        url = f"https://fcm.googleapis.com/v1/projects/{project_id}/messages:send"
        headers = {
            "Authorization": f"Bearer {_access_token()}",
            "Content-Type": "application/json",
        }
        sent = 0
        async with httpx.AsyncClient(timeout=10) as client:
            for tok in tokens:
                payload = {
                    "message": {
                        "token": tok,
                        "notification": {"title": title, "body": body},
                        "data": {"session_id": session_id},
                    }
                }
                try:
                    r = await client.post(url, headers=headers, json=payload)
                    if r.status_code == 200:
                        sent += 1
                    elif r.status_code in (404, 400):
                        # UNREGISTERED / invalid token → prune it.
                        await _delete_token(supa, tok)
                    else:
                        log.warning("[Push] FCM %s: %s", r.status_code, r.text[:200])
                except Exception as exc:
                    log.warning("[Push] send error: %s: %s", type(exc).__name__, exc)
        log.info("[Push] sent %d/%d  user=%s session=%s", sent, len(tokens),
                 user_id, session_id)
    except Exception as exc:
        # Absolute safety: a push failure must never affect /generate.
        log.warning("[Push] send_push failed (non-fatal): %s: %s",
                    type(exc).__name__, exc)
