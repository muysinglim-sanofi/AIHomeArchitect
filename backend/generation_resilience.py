"""Shared operational resilience for a generation — mobile AND PWA.

Why this module exists
----------------------
A generation costs real money at one precise instant: when the provider returns
the image. Everything that happens after that point is holding the only copy of
something already paid for, and a single unlucky socket must not be allowed to
throw it away.

On 2026-08-06 exactly that happened on the PWA path: OpenAI answered 200, the
JPEG was re-encoded, and the very next TCP connect to Storage timed out after
10 s. There was no retry, so the render was lost.

The audit that followed found the same hole on the MOBILE path — `/generate`
Step 7 uploads once and raises `STORAGE_FAILED` on any exception. So this is not
a PWA bug to be fixed by copying a mobile protection: the protection did not
exist on either side. It is written ONCE here and both callers use it.

What this module deliberately does NOT contain
----------------------------------------------
No prompt, no provider, no model parameter, no image processing, no Supabase, no
FastAPI, no table name. It is pure Python with injected callables, which is what
lets the mobile path (public bucket, `sessions`/`messages`, wallet) and the PWA
path (private bucket, `pwa_staging.*`, no billing) share it without either
learning about the other's data model.

Retries are for TRANSPORT failures only, and only for steps that are safe to
repeat. An HTTP status is never retried here: that is a decision for the caller,
and a 4xx would only fail again. Critically, the provider call itself is NEVER
retried by this module — repeating a non-idempotent paid call is how one render
silently becomes two.
"""
from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from typing import Awaitable, Callable, Iterable, TypeVar

log = logging.getLogger("aih")

T = TypeVar("T")

# Three attempts over ~3 s of backoff. Long enough to ride out the blip that
# cost a render, short enough that a genuinely dead dependency still fails the
# request in seconds rather than minutes.
DEFAULT_ATTEMPTS = 3
DEFAULT_BACKOFF_S = 1.0


class PaidResultLost(Exception):
    """A result that was already paid for could not be stored.

    Raised only after every attempt has been spent. Each caller maps it onto its
    own error envelope — `GenerationError` on mobile, `HTTPException` on the PWA
    adapter — so neither has to learn the other's response shape.

    [stage] says WHICH step gave up, which is what tells a save failure apart
    from a connectivity problem when the message reaches a person.
    """

    def __init__(self, stage: str, cause: BaseException | None = None):
        super().__init__(f"paid result lost at stage={stage}")
        self.stage = stage
        self.cause = cause


@dataclass(frozen=True)
class RetryPolicy:
    attempts: int = DEFAULT_ATTEMPTS
    backoff_s: float = DEFAULT_BACKOFF_S

    def delay_for(self, attempt: int) -> float:
        """Exponential: 1 s, then 2 s. Attempt is 1-based."""
        return self.backoff_s * (2 ** (attempt - 1))


async def with_transport_retries(
    op: Callable[[], Awaitable[T]],
    *,
    stage: str,
    retry_on: Iterable[type[BaseException]],
    policy: RetryPolicy | None = None,
) -> T:
    """Run [op], retrying only the exception types in [retry_on].

    [retry_on] is injected rather than hard-coded because the two callers speak
    to Storage through different clients: the PWA adapter raises
    `httpx.TransportError`, the mobile path raises whatever `supabase-py`
    surfaces. This module stays free of both.

    Anything not in [retry_on] propagates untouched on the first occurrence —
    a permission error is not a blip and retrying it only wastes the user's time.
    """
    policy = policy or RetryPolicy()
    types = tuple(retry_on)
    last: BaseException | None = None

    for attempt in range(1, policy.attempts + 1):
        try:
            return await op()
        except types as exc:  # noqa: PERF203 — the retry IS the point
            last = exc
            # Only the failure TYPE is logged. Never a URL, a path, a header or
            # a token: this runs on a code path that carries a session.
            log.warning(
                "[resilience] stage=%s transport failure %s (attempt %d/%d)",
                stage, type(exc).__name__, attempt, policy.attempts,
            )
            if attempt == policy.attempts:
                break
            await asyncio.sleep(policy.delay_for(attempt))

    log.error("[resilience] stage=%s gave up after %d attempts — PAID RESULT AT RISK",
              stage, policy.attempts)
    raise PaidResultLost(stage, last)


async def save_paid_result(
    *,
    upload: Callable[[], Awaitable[T]],
    persist: Callable[[T], Awaitable[None]] | None = None,
    retry_on: Iterable[type[BaseException]],
    policy: RetryPolicy | None = None,
) -> T:
    """The post-payment save policy, in one place.

    The order is not negotiable and is the whole reason this is a function
    rather than a comment: the bytes go to Storage FIRST and the row is written
    SECOND. A row pointing at an object that does not exist is a black card in
    someone's library; an object with no row is an orphan file that costs a few
    kilobytes and nothing else.

    Both steps are retried, because both sit after the money was spent.
    Returns whatever [upload] returned — a path, a URL, whatever the caller's
    storage layer speaks.
    """
    stored = await with_transport_retries(
        upload, stage="upload_result", retry_on=retry_on, policy=policy
    )
    if persist is not None:
        await with_transport_retries(
            lambda: persist(stored), stage="persist_result",
            retry_on=retry_on, policy=policy,
        )
    return stored
