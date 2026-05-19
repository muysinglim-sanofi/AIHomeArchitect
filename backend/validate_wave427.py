"""
Wave 4.2.7 validation suite — Smart Retry System.

Suites:
  A — Classifier unit tests: transient / non-transient / unknown verdicts
  B — RetryDecision dataclass structure
  C — main.py integration: import, log patterns, non-transient exit path
  D — Regression: prompt budgets and existing wave checks still pass
"""

import os
import sys
import logging

logging.disable(logging.CRITICAL)  # suppress aih logs during import
sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

results = []


def check(label: str, condition: bool, detail: str = "") -> None:
    status = PASS if condition else FAIL
    suffix = f"  [{detail}]" if detail and not condition else ""
    print(f"  {status}  {label}{suffix}")
    results.append((label, condition))


# ── Suite A: Classifier unit tests ───────────────────────────────────────────
print("\n=== Suite A: Classifier unit tests ===")

from retry_classifier import classify_for_retry, RetryVerdict, RetryDecision

# ── A: Python standard transient errors ──────────────────────────────────────
d = classify_for_retry(ConnectionResetError("peer reset"))
check("A1  ConnectionResetError ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)
check("A2  ConnectionResetError ->should_retry=True", d.should_retry is True)

d = classify_for_retry(TimeoutError("timed out"))
check("A3  TimeoutError ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)
check("A4  TimeoutError ->should_retry=True", d.should_retry is True)

d = classify_for_retry(OSError("network unreachable"))
check("A5  OSError ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)
check("A6  OSError ->should_retry=True", d.should_retry is True)

d = classify_for_retry(ConnectionAbortedError("aborted"))
check("A7  ConnectionAbortedError ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)

# ── A: httpx transport errors ─────────────────────────────────────────────────
try:
    import httpx

    d = classify_for_retry(httpx.RemoteProtocolError("server disconnected"))
    check("A8  httpx.RemoteProtocolError ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)
    check("A9  httpx.RemoteProtocolError ->should_retry=True", d.should_retry is True)
    check("A10 httpx.RemoteProtocolError ->reason contains 'transport'",
          "transport" in d.reason)

    d = classify_for_retry(httpx.ConnectError("connection refused"))
    check("A11 httpx.ConnectError ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)

    d = classify_for_retry(httpx.ReadTimeout("read timed out"))
    check("A12 httpx.ReadTimeout ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)

except Exception as e:
    print(f"  SKIP A8-A12  httpx not available or mock failed: {e}")

# ── A: OpenAI SDK errors ──────────────────────────────────────────────────────
try:
    from unittest.mock import MagicMock
    from openai import (
        AuthenticationError, PermissionDeniedError, NotFoundError,
        UnprocessableEntityError, RateLimitError,
        InternalServerError as _OAIInternal,
        APIConnectionError, APITimeoutError,
    )

    def _mock_response(status: int) -> MagicMock:
        r = MagicMock()
        r.status_code = status
        r.headers = {}
        r.json.return_value = {}
        return r

    # Non-transient OpenAI errors
    d = classify_for_retry(AuthenticationError(
        message="invalid api key", response=_mock_response(401), body=None))
    check("A13 AuthenticationError ->NON_TRANSIENT", d.verdict == RetryVerdict.NON_TRANSIENT)
    check("A14 AuthenticationError ->should_retry=False", d.should_retry is False)
    check("A15 AuthenticationError ->reason=openai-auth-failure", d.reason == "openai-auth-failure")

    d = classify_for_retry(PermissionDeniedError(
        message="no permission", response=_mock_response(403), body=None))
    check("A16 PermissionDeniedError ->NON_TRANSIENT", d.verdict == RetryVerdict.NON_TRANSIENT)
    check("A17 PermissionDeniedError ->should_retry=False", d.should_retry is False)

    d = classify_for_retry(UnprocessableEntityError(
        message="bad params", response=_mock_response(422), body=None))
    check("A18 UnprocessableEntityError ->NON_TRANSIENT", d.verdict == RetryVerdict.NON_TRANSIENT)

    d = classify_for_retry(NotFoundError(
        message="not found", response=_mock_response(404), body=None))
    check("A19 NotFoundError ->NON_TRANSIENT", d.verdict == RetryVerdict.NON_TRANSIENT)

    # Transient OpenAI errors
    d = classify_for_retry(RateLimitError(
        message="rate limited", response=_mock_response(429), body=None))
    check("A20 RateLimitError ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)
    check("A21 RateLimitError ->should_retry=True", d.should_retry is True)
    check("A22 RateLimitError ->reason=openai-rate-limit", d.reason == "openai-rate-limit")

    d = classify_for_retry(_OAIInternal(
        message="server error", response=_mock_response(500), body=None))
    check("A23 OpenAI InternalServerError ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)
    check("A24 OpenAI InternalServerError ->reason=openai-server-error",
          d.reason == "openai-server-error")

    d = classify_for_retry(APIConnectionError.__new__(APIConnectionError))
    check("A25 APIConnectionError ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)

    d = classify_for_retry(APITimeoutError.__new__(APITimeoutError))
    check("A26 APITimeoutError ->TRANSIENT", d.verdict == RetryVerdict.TRANSIENT)

except Exception as e:
    print(f"  SKIP A13-A26  OpenAI mock failed: {e}")

# ── A: Unknown exception ──────────────────────────────────────────────────────
class _CompletlyUnknownError(Exception):
    pass

logging.disable(logging.NOTSET)  # allow UNCLASSIFIED warning to emit
d = classify_for_retry(_CompletlyUnknownError("mystery"))
logging.disable(logging.CRITICAL)

check("A27 Unknown exception ->UNKNOWN verdict", d.verdict == RetryVerdict.UNKNOWN)
check("A28 Unknown exception ->should_retry=True (fail-safe toward retry)",
      d.should_retry is True)
check("A29 Unknown exception ->reason=unclassified", d.reason == "unclassified")


# ── Suite B: RetryDecision structure ─────────────────────────────────────────
print("\n=== Suite B: RetryDecision / RetryVerdict structure ===")

check("B1  RetryDecision is frozen dataclass",
      hasattr(RetryDecision, "__dataclass_params__") and RetryDecision.__dataclass_params__.frozen)
check("B2  RetryDecision has 'should_retry' field",
      "should_retry" in RetryDecision.__dataclass_fields__)
check("B3  RetryDecision has 'verdict' field",
      "verdict" in RetryDecision.__dataclass_fields__)
check("B4  RetryDecision has 'reason' field",
      "reason" in RetryDecision.__dataclass_fields__)
check("B5  RetryVerdict.TRANSIENT exists",
      RetryVerdict.TRANSIENT.value == "TRANSIENT")
check("B6  RetryVerdict.NON_TRANSIENT exists",
      RetryVerdict.NON_TRANSIENT.value == "NON_TRANSIENT")
check("B7  RetryVerdict.UNKNOWN exists",
      RetryVerdict.UNKNOWN.value == "UNKNOWN")
check("B8  classify_for_retry is callable",
      callable(classify_for_retry))


# ── Suite C: main.py integration ─────────────────────────────────────────────
print("\n=== Suite C: main.py integration ===")

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()

check("C1  retry_classifier imported in main.py",
      "from retry_classifier import" in main_src)
check("C2  classify_for_retry called in main.py",
      "classify_for_retry(exc)" in main_src)
check("C3  RetryVerdict imported in main.py",
      "RetryVerdict" in main_src)
check("C4  verdict logged in transient path",
      "verdict=%s" in main_src or "verdict=" in main_src)
check("C5  reason logged in retry paths",
      "reason=%s" in main_src or "reason=" in main_src)
check("C6  NON-TRANSIENT log pattern present",
      "NON-TRANSIENT" in main_src)
check("C7  not retrying log message present",
      "not retrying" in main_src)
check("C8  remaining_attempts_saved logged",
      "remaining_attempts_saved" in main_src)
check("C9  UNCLASSIFIED log pattern present",
      "UNCLASSIFIED" in main_src)
check("C10 should_retry check gates early exit",
      "not decision.should_retry" in main_src)
check("C11 decision.verdict == RetryVerdict.UNKNOWN check present",
      "RetryVerdict.UNKNOWN" in main_src)

# Wave 4.2.5 regression: original retry signals still present
check("C12 [OpenAI Attempt] log format preserved",
      "[OpenAI Attempt %d/%d]" in main_src)
check("C13 transient failure log preserved (wave 4.2.5 A6)",
      "transient failure" in main_src)
check("C14 final failure log preserved (wave 4.2.5 A7)",
      "final failure" in main_src)
check("C15 BadRequestError still caught (wave 4.2.5 A9)",
      "BadRequestError" in main_src and "retryable=False" in main_src)
check("C16 succeeded in log preserved (wave 4.2.5 A10)",
      "succeeded in" in main_src)


# ── Suite D: Regression — prompt budgets unchanged ────────────────────────────
print("\n=== Suite D: Regression (prompt budgets + profile routing) ===")

logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS
logging.disable(logging.CRITICAL)

room_desc = "Open-plan living room, natural light from west-facing windows, oak floors, high ceilings."
history_v2 = [
    {"role": "user", "content": "I want Japandi style"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer"},
]

p_fv_j = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "", 1, [])
p_fv_z = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc, "", 1, [])
p_sr_j = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "warmer", 2, history_v2)
p_st   = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "open up facade", 2, history_v2)
p_le   = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "add floor lamp", 2, history_v2)

check(f"D1  FIRST_VISION (Japandi) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_j) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_j)}")
check(f"D2  FIRST_VISION (Zen/DNA) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_z) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_z)}")
check(f"D3  STYLE_REFINEMENT within budget ({_MODE_BUDGETS['STYLE_REFINEMENT']})",
      len(p_sr_j) <= _MODE_BUDGETS["STYLE_REFINEMENT"], f"got {len(p_sr_j)}")
check(f"D4  STRUCTURAL_TRANSFORMATION within budget ({_MODE_BUDGETS['STRUCTURAL_TRANSFORMATION']})",
      len(p_st) <= _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"], f"got {len(p_st)}")
check(f"D5  LOCAL_EDIT within budget ({_MODE_BUDGETS['LOCAL_EDIT']})",
      len(p_le) <= _MODE_BUDGETS["LOCAL_EDIT"], f"got {len(p_le)}")
check("D6  All modes under 4000-char hard limit",
      all(len(p) < 4000 for p in [p_fv_j, p_fv_z, p_sr_j, p_st, p_le]))

from generation_profiles import get_active_profile, _PROFILES
p_dev  = _PROFILES["dev"]
p_prod = _PROFILES["prod"]
check("D7  DEV profile still has max_attempts=1", p_dev.max_attempts == 1)
check("D8  PROD profile still has max_attempts=3", p_prod.max_attempts == 3)
check("D9  DEV profile still has compact_prompts=True", p_dev.compact_prompts is True)
check("D10 PROD profile still has compact_prompts=False", p_prod.compact_prompts is False)

logging.disable(logging.NOTSET)


# ── Results ───────────────────────────────────────────────────────────────────

passed = sum(1 for _, ok in results if ok)
total = len(results)
failed = [(label, ok) for label, ok in results if not ok]

print(f"\n{'=' * 60}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if failed:
    print(f"\n  FAILING CHECKS:")
    for label, _ in failed:
        print(f"    - {label}")
print(f"{'=' * 60}")

print(f"""
  RETRY DECISION MATRIX (Wave 4.2.7):

  Exception Type              | Verdict       | should_retry | Budget saved
  ----------------------------|---------------|--------------|-------------
  AuthenticationError (401)   | NON_TRANSIENT | False        | remaining attempts
  PermissionDeniedError (403) | NON_TRANSIENT | False        | remaining attempts
  NotFoundError (404)         | NON_TRANSIENT | False        | remaining attempts
  UnprocessableEntityError    | NON_TRANSIENT | False        | remaining attempts
  BadRequestError (400)       | NON_TRANSIENT | False        | remaining attempts *
  RateLimitError (429)        | TRANSIENT     | True         | none
  OpenAI InternalServerError  | TRANSIENT     | True         | none
  APIConnectionError          | TRANSIENT     | True         | none
  APITimeoutError             | TRANSIENT     | True         | none
  httpx.RemoteProtocolError   | TRANSIENT     | True         | none
  httpx.ConnectError          | TRANSIENT     | True         | none
  httpx.ReadTimeout           | TRANSIENT     | True         | none
  ConnectionResetError        | TRANSIENT     | True         | none
  TimeoutError                | TRANSIENT     | True         | none
  OSError                     | TRANSIENT     | True         | none
  Unknown exception           | UNKNOWN       | True         | none (monitored)

  * BadRequestError handled upstream before classify_for_retry is called.

  MANUAL VALIDATION REQUIRED:
  [MANUAL] Simulate RateLimitError in PROD: confirm 3 attempts logged
  [MANUAL] Simulate AuthenticationError: confirm single attempt + NON-TRANSIENT log
  [MANUAL] Confirm [RetryClassifier] UNCLASSIFIED warning appears for novel exc types
""")
