"""
Wave 5.17b — Per-IP rate limit (defensive ceiling).

Purpose
───────
Catches a viral abuse pattern where many anonymous users from the same
network attempt to drain free quota by uninstall/reinstall cycles. This
is NOT the primary quota gate (that's `quota.py` keyed by user_id). It's
a backstop : even if `quota.py` is bypassed for any reason, the IP limit
caps cost exposure per /24h.

Scope rules (per locked product decision)
──────────────────────────────────────────
1. ANON USERS ONLY. Signed-in users are governed by account-level
   quotas (Wave 5.17b: free tier ; Wave 5.17c: premium). Their IP is
   irrelevant — multiple legitimate users on the same shared NAT must
   not be blocked.
2. 10 generations per IP per 24 hours.
3. In-memory, per-uvicorn-worker. Resets on backend restart. Acceptable
   for a defensive ceiling (its job is to bound abuse, not to track
   usage perfectly). A Redis-backed cluster-wide implementation is a
   Wave 5.17c+ enhancement IF abuse logs warrant it.

Storage shape
─────────────
`_BUCKETS: dict[str, deque[float]]` — keyed by client IP, holds a
sliding window of timestamps. On each /generate call from an anon user,
we trim timestamps older than 24h, check the deque length, and if
under the limit, append the current timestamp.

Failure mode
────────────
If the bucket is full → raise HTTPException(429). The frontend treats
this as a non-retryable error in V1 ; future wave 5.17c could surface a
"Try again tomorrow or subscribe" message instead.
"""

from __future__ import annotations
import logging
import time
from collections import deque
from typing import Optional

from fastapi import HTTPException, status

log = logging.getLogger("wave_5_17b.rate_limit")

# ── Tunable constants ───────────────────────────────────────────────────────

# 10 successful generations per IP per 24h. Tracks all anon /generate
# attempts (not just successes — failed attempts also indicate intent).
_MAX_GENS_PER_IP_PER_WINDOW = 10
_WINDOW_SECONDS = 86400  # 24 hours


# ── In-memory bucket ────────────────────────────────────────────────────────

_BUCKETS: dict[str, deque] = {}


def _trim_bucket(bucket: deque, now_ts: float) -> None:
    """Discard timestamps older than the rolling window."""
    cutoff = now_ts - _WINDOW_SECONDS
    while bucket and bucket[0] < cutoff:
        bucket.popleft()


def check_ip_rate_limit(
    ip: Optional[str],
    *,
    is_anonymous: bool,
    is_admin: bool = False,
) -> None:
    """
    Raise HTTPException(429) if `ip` has exceeded the rolling 24h
    quota for anonymous users. No-op when :
      - The user is signed-in (account quota governs instead)
      - The user has an admin/premium role bypass (matches the quota
        bypass scope — paying / admin users should never hit the
        defensive ceiling). Wave 5.21c (2026-06-02).
      - `ip` is None or empty (can't enforce without a key)
    """
    if not is_anonymous:
        return
    if is_admin:
        return
    if not ip:
        return

    bucket = _BUCKETS.setdefault(ip, deque())
    now_ts = time.time()
    _trim_bucket(bucket, now_ts)

    if len(bucket) >= _MAX_GENS_PER_IP_PER_WINDOW:
        oldest = bucket[0]
        retry_after_seconds = int(oldest + _WINDOW_SECONDS - now_ts) + 1
        log.warning(
            "[Wave 5.17b] IP rate limit triggered — ip=%s count=%d retry_after=%ds",
            ip, len(bucket), retry_after_seconds,
        )
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail={
                "error_code": "RATE_LIMIT_EXCEEDED",
                "user_message": (
                    "Too many generations from this network. "
                    "Please try again later."
                ),
                "retry_after_seconds": retry_after_seconds,
                "retryable": False,
            },
        )

    bucket.append(now_ts)


# ── Test helpers ────────────────────────────────────────────────────────────

def _clear_buckets() -> None:
    """Test-only — reset all buckets so consecutive test runs don't
    contaminate each other. Production callers never call this."""
    _BUCKETS.clear()


def _bucket_size(ip: str) -> int:
    """Test-only — return the current bucket size for an IP."""
    return len(_BUCKETS.get(ip, deque()))
