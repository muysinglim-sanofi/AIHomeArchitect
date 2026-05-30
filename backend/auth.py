"""
Wave 5.17a — Identity foundation (Wave 5.17c — JWKS / ES256 migration).

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
  Supabase tokens, signed with the project's asymmetric private key,
  both carry a `sub` claim (the user UUID). The only difference is the
  `is_anonymous` boolean claim, exposed via `CurrentUser.is_anonymous`.
- Wave 5.17a deliberately does NOT enforce per-tier quotas. Both anon
  and signed-in users can call /chat and /generate freely. Quotas land
  in Wave 5.17b ; they gate on `CurrentUser.user_id` + `usage_log`
  lookups.

Signing keys (JWKS / ES256)
───────────────────────────
Supabase projects now sign access tokens with an asymmetric key pair
(ES256 by default, RS256 supported). The public key is published as a
JWKS document at :
    {SUPABASE_URL}/auth/v1/.well-known/jwks.json
The backend never holds a shared secret ; only the JWKS public keys,
selected by the token's `kid` header. `PyJWKClient` caches keys in-
process for `_JWKS_LIFESPAN` seconds and auto-refreshes when a new
`kid` arrives — Supabase key rotation is transparent.

Critical — algorithm allowlist
──────────────────────────────
`_ALLOWED_ALGORITHMS` deliberately EXCLUDES HS256. Permitting HS256
alongside asymmetric algorithms opens the classic "alg confusion"
attack : an attacker forges a token with alg=HS256 and signs it with
the project public key used as the HMAC shared secret ; pyjwt then
verifies against that public key (HS256 path) and accepts the forged
token. Restricting to ES256/RS256 forces signature verification to the
genuine private key, which only Supabase holds.

Token lifetime
──────────────
Supabase access tokens default to 3600 seconds. The `supabase_flutter`
SDK auto-refreshes ; the backend just verifies the current `exp`. We
allow a 60 s leeway to account for client/server clock skew.

Failure modes (all return 401 with informative `detail`)
───────────────────────────────────────────────────────
- No Authorization header              → "missing_authorization"
- Header not Bearer                    → "invalid_authorization_format"
- Token `kid` not in JWKS              → "jwks_key_not_found"
- JWKS endpoint unreachable            → "jwks_unavailable"
- JWT signature invalid                → "invalid_jwt_signature"
- JWT expired                          → "jwt_expired"
- JWT audience invalid                 → "invalid_jwt_audience"
- JWT missing required `sub` claim     → "jwt_missing_subject"
- Token alg not in allowlist           → "invalid_jwt" (with err detail in log)
- Backend misconfigured (no URL)       → 503 "backend_misconfigured"
"""

from __future__ import annotations
import logging
import os
from dataclasses import dataclass
from typing import Optional

import jwt
from jwt import PyJWKClient
from jwt.exceptions import PyJWKClientError
from fastapi import Depends, HTTPException, Request, status

# Diagnostic logger — additive, no product logic change. Surfaces the
# exact rejection branch + unverified token claims so the operator can
# distinguish (a) frontend not sending a token from (b) backend rejecting
# a real Supabase token (secret mismatch, alg mismatch, audience mismatch).
log = logging.getLogger("aih.auth")


def _peek_unverified(token: str) -> dict:
    """Decode the JWT WITHOUT verifying signature/expiry/audience. Used
    only to log alg/iss/aud/sub when verification fails — never to grant
    access. Returns empty dict on any parse failure."""
    try:
        header = jwt.get_unverified_header(token)
        claims = jwt.decode(
            token,
            options={
                "verify_signature": False,
                "verify_aud": False,
                "verify_exp": False,
                "verify_nbf": False,
                "verify_iat": False,
            },
        )
        return {
            "alg": header.get("alg"),
            "kid": header.get("kid"),
            "typ": header.get("typ"),
            "iss": claims.get("iss"),
            "aud": claims.get("aud"),
            "sub": claims.get("sub"),
            "exp": claims.get("exp"),
            "role": claims.get("role"),
            "is_anonymous": claims.get("is_anonymous"),
        }
    except Exception as exc:  # noqa: BLE001
        return {"_peek_error": str(exc)}


# ── Configuration ────────────────────────────────────────────────────────────

# Asymmetric algorithms only. HS256 is EXCLUDED on purpose — see module
# docstring for the alg-confusion rationale. Listing both ES256 and RS256
# accommodates Supabase's per-project key choice without future code
# changes ; both are verified against the JWKS public key.
_ALLOWED_ALGORITHMS = ["ES256", "RS256"]
# Supabase's default audience for client tokens is "authenticated".
_JWT_AUDIENCE = "authenticated"
# Small skew tolerance — accounts for client/server clock drift.
_LEEWAY_SECONDS = 60
# JWKS public-key cache lifespan. PyJWKClient also refreshes on cache
# miss (unseen `kid`), so the lifespan only bounds staleness in the
# rotation-without-new-kid case (rare).
_JWKS_LIFESPAN_SECONDS = 3600


# ── JWKS client (lazy module singleton) ──────────────────────────────────────
#
# A single PyJWKClient per process is sufficient — the underlying HTTP
# fetcher is thread-safe and amortises one JWKS request across all
# subsequent verifications. The lazy getter is overridable from tests by
# replacing `_jwks_client` on the module (see _wave_5_17b_validation.py
# S8 fixtures).

_jwks_client: Optional[PyJWKClient] = None


def _get_jwks_client() -> Optional[PyJWKClient]:
    """Return the cached PyJWKClient. Derives its URL from `SUPABASE_URL`
    so a missing env returns None (caller maps None → 503). Reads env
    lazily so test harnesses can set it after import.
    """
    global _jwks_client
    if _jwks_client is not None:
        return _jwks_client
    base_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    if not base_url:
        return None
    jwks_url = f"{base_url}/auth/v1/.well-known/jwks.json"
    _jwks_client = PyJWKClient(
        jwks_url,
        cache_keys=True,
        lifespan=_JWKS_LIFESPAN_SECONDS,
    )
    return _jwks_client


def _reset_jwks_client() -> None:
    """Test-only — drop the cached client so a subsequent _get_jwks_client
    call re-reads `SUPABASE_URL` or picks up a module-level fake set by
    the test fixture. Production code never calls this."""
    global _jwks_client
    _jwks_client = None


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
    jwks_client = _get_jwks_client()
    if jwks_client is None:
        log.warning("[Wave 5.17a auth] reject=backend_misconfigured (SUPABASE_URL empty — cannot derive JWKS endpoint)")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="backend_misconfigured",
        )

    auth_header = request.headers.get("Authorization") or request.headers.get("authorization")
    if not auth_header:
        log.warning("[Wave 5.17a auth] reject=missing_authorization (no Authorization header) path=%s", request.url.path)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="missing_authorization",
        )

    parts = auth_header.split(None, 1)
    if len(parts) != 2 or parts[0].lower() != "bearer" or not parts[1].strip():
        log.warning("[Wave 5.17a auth] reject=invalid_authorization_format header_prefix=%r", auth_header[:30])
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid_authorization_format",
        )
    token = parts[1].strip()

    # Resolve the signing key for this token's `kid`. PyJWKClient inspects
    # the JWT header, looks up the matching key in its cached JWKS, and
    # refreshes the cache once if the kid is unknown (handles Supabase
    # key rotation transparently). Failures here are NOT signature
    # failures — they mean we can't find/fetch the key at all.
    try:
        signing_key = jwks_client.get_signing_key_from_jwt(token)
    except PyJWKClientError as exc:
        log.warning(
            "[Wave 5.17a auth] reject=jwks_key_not_found err=%s peek=%s",
            exc, _peek_unverified(token),
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="jwks_key_not_found",
        )
    except Exception as exc:  # network errors, malformed JWKS, etc.
        log.warning(
            "[Wave 5.17a auth] reject=jwks_unavailable err=%s peek=%s",
            exc, _peek_unverified(token),
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="jwks_unavailable",
        )

    try:
        payload = jwt.decode(
            token,
            signing_key.key,
            algorithms=_ALLOWED_ALGORITHMS,
            audience=_JWT_AUDIENCE,
            leeway=_LEEWAY_SECONDS,
        )
    except jwt.ExpiredSignatureError:
        log.warning("[Wave 5.17a auth] reject=jwt_expired peek=%s", _peek_unverified(token))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="jwt_expired",
        )
    except jwt.InvalidAudienceError:
        log.warning("[Wave 5.17a auth] reject=invalid_jwt_audience expected=%r peek=%s", _JWT_AUDIENCE, _peek_unverified(token))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid_jwt_audience",
        )
    except jwt.InvalidSignatureError:
        log.warning("[Wave 5.17a auth] reject=invalid_jwt_signature peek=%s", _peek_unverified(token))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid_jwt_signature",
        )
    except jwt.PyJWTError as exc:
        log.warning("[Wave 5.17a auth] reject=invalid_jwt err=%s peek=%s", exc, _peek_unverified(token))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid_jwt",
        )

    user_id = payload.get("sub")
    if not user_id:
        log.warning("[Wave 5.17a auth] reject=jwt_missing_subject claims=%s", payload)
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

    log.info(
        "[Wave 5.17a auth] OK user=%s is_anonymous=%s aud=%s iss=%s",
        user_id, is_anon, payload.get("aud"), payload.get("iss"),
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
