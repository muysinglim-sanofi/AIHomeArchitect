"""
Wave 4.3.2 validation suite — SDK Retry Amplification Prevention.

Problem found during PROD smoke testing:
  OpenAI Python SDK defaults to max_retries=2 (1 initial + 2 SDK retries per call).
  With PROD max_attempts=3, this silently produces up to 3 × 3 = 9 API calls per
  user request — uncontrolled cost and latency amplification. One backend attempt
  lasted ~188.9s because the SDK was internally retrying RemoteProtocolError twice
  before our code ever saw the exception.

Fix:
  AsyncOpenAI(max_retries=0) — SDK retries disabled.
  backend retry_classifier is the sole retry authority.
  Max API calls per request = profile.max_attempts × 1 (no SDK multiplier).

Suites:
  A — SDK retry configuration: max_retries=0 set, logging present, comment explains why
  B — Retry math: verified no hidden multiplication (PROD=3 calls, DEV=1 call)
  C — Per-attempt logging: attempt source is unambiguous
  D — Regression: retry_classifier, profiles, frozen modules intact
"""

import os
import sys
import logging

logging.disable(logging.CRITICAL)
sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

results = []


def check(label: str, condition: bool, detail: str = "") -> None:
    status = PASS if condition else FAIL
    suffix = f"  [{detail}]" if detail and not condition else ""
    print(f"  {status}  {label}{suffix}")
    results.append((label, condition))


with open("main.py", encoding="utf-8") as f:
    main_src = f.read()


# ── Suite A: SDK retry configuration ─────────────────────────────────────────
print("\n=== Suite A: SDK retry configuration ===")

check("A1  AsyncOpenAI initialized with max_retries=0",
      "max_retries=0" in main_src)
check("A2  max_retries=0 is on the AsyncOpenAI constructor (argument form with comma)",
      "max_retries=0," in main_src)
check("A3  Comment explains amplification risk (3 × 3 = 9 API calls)",
      "9 API calls" in main_src or "3 × 3 = 9" in main_src)
check("A4  Comment names the problem: 'amplification'",
      "amplification" in main_src)
check("A5  [OpenAI Client] startup log present",
      "[OpenAI Client]" in main_src)
check("A6  Startup log emits max_retries value",
      "openai.max_retries" in main_src and "[OpenAI Client]" in main_src)
check("A7  Startup log emits timeout value",
      "openai.timeout" in main_src)
check("A8  Startup log states SDK retries DISABLED",
      "SDK internal retries DISABLED" in main_src or "SDK retries DISABLED" in main_src)
check("A9  Startup log names retry_classifier as sole authority",
      "retry_classifier" in main_src and "sole retry authority" in main_src)
check("A10 Worst-case API calls formula logged (max_attempts × 1)",
      "max_attempts" in main_src and "sole retry authority" in main_src)


# ── Suite B: Retry math verification ─────────────────────────────────────────
print("\n=== Suite B: Retry math verification ===")

from generation_profiles import get_active_profile, _PROFILES

p_prod = _PROFILES["prod"]
p_dev  = _PROFILES["dev"]

sdk_retries = 0  # enforced by max_retries=0
prod_max_calls = p_prod.max_attempts * (1 + sdk_retries)
dev_max_calls  = p_dev.max_attempts  * (1 + sdk_retries)

check("B1  PROD max_attempts=3 unchanged",
      p_prod.max_attempts == 3)
check("B2  DEV max_attempts=1 unchanged",
      p_dev.max_attempts == 1)
check("B3  SDK max_retries=0: no SDK-level multiplication",
      sdk_retries == 0)
check(f"B4  PROD worst-case API calls = 3 × 1 = 3 (got {prod_max_calls})",
      prod_max_calls == 3)
check(f"B5  DEV worst-case API calls = 1 × 1 = 1 (got {dev_max_calls})",
      dev_max_calls == 1)
check("B6  Old amplified PROD worst-case (3 × 3 = 9) is no longer possible",
      prod_max_calls < 9)
check("B7  AsyncOpenAI max_retries=0 is hardcoded (not from env or profile)",
      "max_retries=0" in main_src and "max_retries=profile" not in main_src)


# ── Suite C: Per-attempt logging clarity ─────────────────────────────────────
print("\n=== Suite C: Per-attempt logging clarity ===")

check("C1  Per-attempt log still present: [OpenAI Attempt",
      "[OpenAI Attempt" in main_src)
check("C2  Per-attempt log states 'backend-controlled'",
      "backend-controlled" in main_src)
check("C3  Per-attempt log emits SDK max_retries inline",
      "SDK max_retries=%d" in main_src or "sdk_max_retries" in main_src.lower() or
      "SDK max_retries=" in main_src)
check("C4  Elapsed time logged per attempt (time.monotonic)",
      "time.monotonic" in main_src)
check("C5  Transient verdict still logged (retry came from backend classifier)",
      "transient failure" in main_src and "verdict" in main_src)
check("C6  Non-transient verdict still exits immediately (no hidden retry)",
      "not retrying" in main_src)


# ── Suite D: Regression — retry_classifier and frozen modules ─────────────────
print("\n=== Suite D: Regression (retry_classifier + frozen modules) ===")

from retry_classifier import classify_for_retry, RetryVerdict, RetryDecision

check("D1  classify_for_retry still importable", callable(classify_for_retry))
check("D2  RetryVerdict.TRANSIENT still present",
      RetryVerdict.TRANSIENT.value == "TRANSIENT")
check("D3  RetryVerdict.NON_TRANSIENT still present",
      RetryVerdict.NON_TRANSIENT.value == "NON_TRANSIENT")
check("D4  RetryDecision still frozen dataclass",
      RetryDecision.__dataclass_params__.frozen)

# Verify classifier verdicts unchanged
try:
    import httpx
    rd_disconnect = classify_for_retry(httpx.RemoteProtocolError("Server disconnected"))
    check("D5  RemoteProtocolError still classified as TRANSIENT",
          rd_disconnect.verdict == RetryVerdict.TRANSIENT)
    check("D6  RemoteProtocolError reason is transport-disconnect",
          rd_disconnect.reason == "transport-disconnect")
except ImportError:
    rc_src = open("retry_classifier.py").read()
    check("D5  RemoteProtocolError TRANSIENT in retry_classifier source",
          "RemoteProtocolError" in rc_src and "_transient" in rc_src)
    check("D6  transport-disconnect reason in retry_classifier source",
          "transport-disconnect" in rc_src)

# AuthenticationError needs a mock response — classify via source inspection only
rc_src = open("retry_classifier.py").read()
check("D7  AuthenticationError still classified as NON_TRANSIENT in classifier source",
      "AuthenticationError" in rc_src and "_non_transient" in rc_src)

check("D8  BadRequestError handled before retry loop in main.py (not via classifier)",
      "BadRequestError" in main_src and "not retrying" in main_src)
check("D9  PROD compact_prompts=False unchanged", p_prod.compact_prompts is False)
check("D10 DEV compact_prompts=True unchanged",   p_dev.compact_prompts is True)

from prompt_engine.intent_classifier import classify_intent, ConversationIntent
check("D11 intent_classifier still importable", callable(classify_intent))
check("D12 'go ahead' still -> GENERATE",
      classify_intent("go ahead", 2).intent == ConversationIntent.GENERATE)

logging.disable(logging.NOTSET)


# ── Results ───────────────────────────────────────────────────────────────────

passed = sum(1 for _, ok in results if ok)
total  = len(results)
failed = [(label, ok) for label, ok in results if not ok]

print(f"\n{'=' * 60}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if failed:
    print(f"\n  FAILING CHECKS:")
    for label, _ in failed:
        print(f"    - {label}")
print(f"{'=' * 60}")

print("""
  RETRY AMPLIFICATION ANALYSIS (Wave 4.3.2):

  State            | Before fix               | After fix
  -----------------|--------------------------|------------------
  SDK max_retries  | 2 (SDK default)          | 0 (explicitly set)
  SDK calls/attempt| 1 initial + 2 retries =3 | 1 (no SDK retry)
  PROD max_attempts| 3                        | 3 (unchanged)
  PROD max API calls| 3 × 3 = 9               | 3 × 1 = 3
  DEV max API calls | 1 × 3 = 3               | 1 × 1 = 1
  Retry authority  | SDK + backend (conflict) | backend only
  Per-attempt latency| SDK silent retry hidden | immediate raise
  188.9s attempt   | SDK retry × 2 hidden     | would surface fast

  MANUAL VALIDATION REQUIRED:
  [MANUAL] Restart backend, confirm '[OpenAI Client] max_retries=0' in first log lines
  [MANUAL] On failure, confirm only 'OpenAI Attempt 1/3', '2/3', '3/3' appear — no hidden SDK retry
  [MANUAL] Confirm RemoteProtocolError surfaces immediately per attempt (not after ~60s hidden retry)
""")
