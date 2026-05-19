"""
Retry classifier — Wave 4.2.7: Smart Retry System.

Determines whether an OpenAI generation failure warrants another attempt.

Verdict taxonomy:
  TRANSIENT     — temporary infra failure; retry may succeed
  NON_TRANSIENT — structural/auth/validation failure; retry will not help
  UNKNOWN       — unrecognised exception type; treated as transient with monitoring

Cost protection principle:
  Retries exist for technical recoverability only.
  Non-transient failures surface immediately — no wasted API budget.
  Aesthetic quality is never a retry signal.

Note: BadRequestError (400 content-policy / bad input) is handled upstream
in the retry loop before this function is called — always NON_TRANSIENT.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from enum import Enum

log = logging.getLogger("aih")


class RetryVerdict(str, Enum):
    TRANSIENT = "TRANSIENT"          # temporary; retry is justified
    NON_TRANSIENT = "NON_TRANSIENT"  # structural; retry wastes budget
    UNKNOWN = "UNKNOWN"              # unclassified; retried with monitoring


@dataclass(frozen=True)
class RetryDecision:
    """
    Immutable retry decision returned by classify_for_retry().

    should_retry  True  → transient; enter retry loop if attempts remain
                  False → non-transient; raise immediately, save API budget
    verdict       why the decision was made (for logs and future metrics)
    reason        short machine-readable label  e.g. "openai-rate-limit"
    """
    should_retry: bool
    verdict: RetryVerdict
    reason: str


# ── Internal constructors ─────────────────────────────────────────────────────

def _non_transient(reason: str) -> RetryDecision:
    return RetryDecision(should_retry=False, verdict=RetryVerdict.NON_TRANSIENT, reason=reason)


def _transient(reason: str) -> RetryDecision:
    return RetryDecision(should_retry=True, verdict=RetryVerdict.TRANSIENT, reason=reason)


def _unknown() -> RetryDecision:
    return RetryDecision(should_retry=True, verdict=RetryVerdict.UNKNOWN, reason="unclassified")


# ── Main classifier ───────────────────────────────────────────────────────────

def classify_for_retry(exc: Exception) -> RetryDecision:
    """
    Classify a generation-layer exception and return a RetryDecision.

    Imports of openai and httpx are deferred inside the function to keep
    module load clean and avoid circular-import issues.

    Classification order:
      1. OpenAI SDK errors (auth, permission, validation → NON_TRANSIENT;
         rate-limit, server-error, connection, timeout → TRANSIENT)
      2. httpx transport errors (disconnect, timeout → TRANSIENT;
         4xx client errors → NON_TRANSIENT)
      3. Python standard network errors (TRANSIENT)
      4. Everything else → UNKNOWN (retried, logged for monitoring)
    """

    # ── 1. OpenAI SDK errors ──────────────────────────────────────────────────
    try:
        from openai import (
            AuthenticationError,
            PermissionDeniedError,
            NotFoundError,
            UnprocessableEntityError,
            RateLimitError,
            InternalServerError as _OAIInternalServerError,
            APIConnectionError,
            APITimeoutError,
        )

        if isinstance(exc, AuthenticationError):
            return _non_transient("openai-auth-failure")
        if isinstance(exc, PermissionDeniedError):
            return _non_transient("openai-permission-denied")
        if isinstance(exc, NotFoundError):
            return _non_transient("openai-not-found")
        if isinstance(exc, UnprocessableEntityError):
            return _non_transient("openai-unprocessable")

        if isinstance(exc, RateLimitError):
            return _transient("openai-rate-limit")
        if isinstance(exc, _OAIInternalServerError):
            return _transient("openai-server-error")
        if isinstance(exc, APIConnectionError):
            return _transient("openai-connection-error")
        if isinstance(exc, APITimeoutError):
            return _transient("openai-timeout")

    except ImportError:
        pass  # openai not installed — continue to generic classification

    # ── 2. httpx transport errors ─────────────────────────────────────────────
    try:
        import httpx

        if isinstance(exc, (httpx.RemoteProtocolError, httpx.ConnectError)):
            return _transient("transport-disconnect")
        if isinstance(exc, (httpx.TimeoutException, httpx.ReadTimeout, httpx.WriteTimeout)):
            return _transient("transport-timeout")
        if isinstance(exc, httpx.HTTPStatusError):
            status = exc.response.status_code
            if status >= 500:
                return _transient(f"http-{status}")
            return _non_transient(f"http-{status}")

    except ImportError:
        pass

    # ── 3. Python standard network errors ─────────────────────────────────────
    if isinstance(exc, (ConnectionResetError, ConnectionAbortedError)):
        return _transient("connection-reset")
    if isinstance(exc, TimeoutError):
        return _transient("timeout")
    if isinstance(exc, OSError):
        return _transient("os-network-error")

    # ── 4. Unknown — retry with monitoring ────────────────────────────────────
    log.warning(
        "[RetryClassifier] UNCLASSIFIED exception type=%s — "
        "treating as transient; add to classifier if this appears frequently",
        type(exc).__name__,
    )
    return _unknown()
