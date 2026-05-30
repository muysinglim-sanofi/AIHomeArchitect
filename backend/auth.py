"""
Wave 5.17a — Identity foundation.

Verifies Supabase-issued JWTs sent by the Flutter client and exposes
`get_current_user` as a FastAPI dependency that other endpoints (/chat,
/generate) depend on.

Design contract
───────────────
- Every authenticated endpoint receives the user's Supabase JWT in the
  `Authorization: Bearer <jwt>` header. The frontend Dio interceptor
  injects this automatically (see frontend/lib/data/services/
  generation_service.dart Wave 5.17a block).
- Both ANONYMOUS and SIGNED-IN JWTs are valid here — they are real
  Supabase tokens, signed with the same project HS256 secret, both
  carry a `sub` claim (the user UUID). The only difference is the
  `is_anonymous` boolean claim, exposed via `CurrentUser.is_anonymous`.
- Wave 5.17a deliberately does NOT enforce per-tier quotas. Both anon
  and signed-in users can call /chat and /generate freely. Quotas land
  in Wave 5.17b ; they will gate on `CurrentUser.is_anonymous` +
  `usage_log` lookups.

JWT secret
──────────
`SUPABASE_JWT_SECRET` must be set in the backend `.env`. Found in the
Supabase dashboard under: Project Settings → API → JWT Settings.
Without it, every authenticated request returns 401.

Token lifetime
──────────────
Supabase access tokens default to 3600 seconds. The `supabase_flutter`
SDK auto-refreshes ; the backend just verifies the current `exp`. We
allow a small leeway (60 s) to account for client/server clock skew.

Failure modes (all return 401 with informative `detail`)
───────────────────────────────────────────────────────
- No Authorization header              → "missing_authorization"
- Header not Bearer                    → "invalid_authorization_format"
- JWT signature invalid                → "invalid_jwt_signature"
- JWT expired                          → "jwt_expired"
- JWT missing required `sub` claim     → "jwt_missing_subject"
- Backend misconfigured (no secret)    → 503 "backend_misconfigured"
"""

from __future__ import annotations
import os
from dataclasses import dataclass
from typing import Optional

import jwt
from fastapi import Depends, HTTPException, Request, status


# ── Configuration ────────────────────────────────────────────────────────────

# Supabase signs JWTs with HS256 using the project-level shared secret.
# Note this is DIFFERENT from the anon key. The anon key is a JWT signed
# with this secret ; the backend verifies CLIENT tokens against the same
# secret. Found at: Supabase Dashboard → Project Settings → API → JWT.
#
# Read lazily (per-request, not at import time) so :
#   - Test setups that set the env var AFTER importing the module work
#   - uvicorn --reload picks up dashboard rotations without process restart
_JWT_ALGORITHM = "HS256"
# Supabase's default audience for client tokens is "authenticated".
_JWT_AUDIENCE = "authenticated"
# Small skew tolerance — accounts for client/server clock drift.
_LEEWAY_SECONDS = 60


def _get_jwt_secret() -> str:
    return os.environ.get("SUPABASE_JWT_SECRET", "")


# ── Public model ─────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class CurrentUser:
    """Identity extracted from a verified Supabase JWT."""
    user_id: str
    is_anonymous: bool
    email: Optional[str] = None  # absent for anonymous, present for signed-in
    raw_claims: Optional[dict] = None  # full JWT payload for debugging

    @property
    def is_signed_in(self) -> bool:
        return not self.is_anonymous


# ── FastAPI dependency ──────────────────────────────────────────────────────

def get_current_user(request: Request) -> CurrentUser:
    """
    Validate the request's `Authorization: Bearer <jwt>` header and return
    the authenticated user. Used as a FastAPI `Depends(...)` on protected
    routes.

    Accepts BOTH anonymous and signed-in Supabase tokens — distinguishing
    between them via the `CurrentUser.is_anonymous` field. Quota
    enforcement (Wave 5.17b) decides whether to allow the call based on
    that flag + usage history.
    """
    jwt_secret = _get_jwt_secret()
    if not jwt_secret:
        # Misconfiguration — never the user's fault, never their problem
        # to solve. Returning 401 here would mislead the client into
        # thinking THEIR token is bad.
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="backend_misconfigured",
        )

    auth_header = request.headers.get("Authorization") or request.headers.get("authorization")
    if not auth_header:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="missing_authorization",
        )

    parts = auth_header.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer" or not parts[1].strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid_authorization_format",
        )
    token = parts[1].strip()

    try:
        payload = jwt.decode(
            token,
            jwt_secret,
            algorithms=[_JWT_ALGORITHM],
            audience=_JWT_AUDIENCE,
            leeway=_LEEWAY_SECONDS,
        )
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="jwt_expired",
        )
    except jwt.InvalidAudienceError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid_jwt_audience",
        )
    except jwt.InvalidSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid_jwt_signature",
        )
    except jwt.PyJWTError:
        # Catch-all for any other decode failure — malformed token, bad
        # algorithm, missing required claims, etc. We deliberately keep
        # the detail vague to avoid leaking which specific validation
        # failed.
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid_jwt",
        )

    user_id = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="jwt_missing_subject",
        )

    # Supabase tags anonymous tokens with `is_anonymous: true` directly
    # on the payload. Older tokens may carry the flag inside
    # `app_metadata` ; check both for forward + backward compatibility.
    is_anon = bool(
        payload.get("is_anonymous")
        or (payload.get("app_metadata", {}) or {}).get("is_anonymous", False)
    )

    return CurrentUser(
        user_id=str(user_id),
        is_anonymous=is_anon,
        email=payload.get("email"),
        raw_claims=payload,
    )


# ── Convenience helpers ──────────────────────────────────────────────────────

def get_current_user_optional(request: Request) -> Optional[CurrentUser]:
    """
    Same as `get_current_user` but returns None instead of raising when
    no/invalid token is present. Useful for endpoints that work for both
    authenticated and unauthenticated callers (none currently in V1 ;
    reserved for future read-only public endpoints).
    """
    try:
        return get_current_user(request)
    except HTTPException:
        return None


CurrentUserDep = Depends(get_current_user)
