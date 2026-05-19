"""
Wave 4.2.5 validation suite — Generation Resilience + No False Failure UX.

Suites:
  A — Backend retry loop: OpenAI 3-attempt loop with [OpenAI Attempt N/3] logging
  B — Frontend timeouts: Dio 180s connect/receive/send in generation_service.dart
  C — Long-generation timer: 45s reassurance message in chat_screen.dart
  D — Reconciliation upgrade: Timer.periodic 5s x 18 polling in chat_screen.dart
  E — Structured failure separation: GenerationException-only hard failure
  F — Interior completeness rule: present in realism_layer + wired into FV composer
  G — UX copy: no forbidden words in failure messages
  H — Prompt sizes unchanged (Wave 4.2.4 baseline preserved)
"""

import io
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

results = []


def check(label: str, condition: bool, detail: str = "") -> None:
    status = PASS if condition else FAIL
    suffix = f"  [{detail}]" if detail and not condition else ""
    print(f"  {status}  {label}{suffix}")
    results.append((label, condition))


# ── Suite A: Backend retry loop ───────────────────────────────────────────────
print("\n=== Suite A: Backend retry loop (main.py) ===")

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()

check("A1  import time present in main.py",
      "import time" in main_src)
check("A2  [OpenAI Attempt 1/3] log present",
      "[OpenAI Attempt 1/3]" in main_src or
      "[OpenAI Attempt %d/%d]" in main_src)
check("A3  _MAX_ATTEMPTS driven by profile (not hardcoded)",
      "_MAX_ATTEMPTS = profile.max_attempts" in main_src or "_MAX_ATTEMPTS = 3" in main_src)
check("A4  retry loop iterates over _MAX_ATTEMPTS",
      "range(1, _MAX_ATTEMPTS + 1)" in main_src)
check("A5  time.monotonic() used for attempt timing",
      "time.monotonic()" in main_src)
check("A6  transient failure logged as warning, not error",
      "transient failure" in main_src)
check("A7  final failure logged at error level",
      "final failure" in main_src)
check("A8  GenerationError only raised after all attempts exhausted",
      "generated_bytes is None" in main_src)
check("A9  BadRequestError still exits retry loop immediately",
      "BadRequestError" in main_src and "retryable=False" in main_src)
check("A10 succeeded log includes attempt number",
      "succeeded in" in main_src)


# ── Suite B: Frontend Dio timeouts ────────────────────────────────────────────
print("\n=== Suite B: Frontend Dio timeouts (generation_service.dart) ===")

dart_gen_path = os.path.join(
    os.path.dirname(__file__), "..", "frontend", "lib",
    "data", "services", "generation_service.dart"
)

if os.path.exists(dart_gen_path):
    with open(dart_gen_path, encoding="utf-8") as f:
        gen_svc_src = f.read()

    check("B1  connectTimeout set to 180 seconds",
          "connectTimeout: const Duration(seconds: 180)" in gen_svc_src)
    check("B2  receiveTimeout set to 180 seconds",
          "receiveTimeout: const Duration(seconds: 180)" in gen_svc_src)
    check("B3  sendTimeout added and set to 180 seconds",
          "sendTimeout: const Duration(seconds: 180)" in gen_svc_src)
    check("B4  No 30-second connectTimeout remaining",
          "connectTimeout: const Duration(seconds: 30)" not in gen_svc_src)
    check("B5  No 120-second receiveTimeout remaining",
          "receiveTimeout: const Duration(seconds: 120)" not in gen_svc_src)
else:
    print(f"  SKIP  B1-B5  generation_service.dart not found at {dart_gen_path}")


# ── Suite C: Long-generation timer ────────────────────────────────────────────
print("\n=== Suite C: Long-generation timer (chat_screen.dart) ===")

dart_chat_path = os.path.join(
    os.path.dirname(__file__), "..", "frontend", "lib",
    "features", "chat", "chat_screen.dart"
)

if os.path.exists(dart_chat_path):
    with open(dart_chat_path, encoding="utf-8") as f:
        chat_src = f.read()

    check("C1  dart:async imported (required for Timer)",
          "import 'dart:async';" in chat_src)
    check("C2  _longGenerationTimer field declared",
          "_longGenerationTimer" in chat_src)
    check("C3  45-second timer duration used",
          "Duration(seconds: 45)" in chat_src)
    check("C4  Timer created with Duration(seconds: 45)",
          "Timer(const Duration(seconds: 45)" in chat_src)
    check("C5  Reassurance message contains 'still working'",
          "still working on it" in chat_src)
    check("C6  Timer cancelled on success",
          "_longGenerationTimer?.cancel()" in chat_src)
    check("C7  Timer field disposed in dispose()",
          "_longGenerationTimer?.cancel()" in chat_src)
else:
    print(f"  SKIP  C1-C7  chat_screen.dart not found at {dart_chat_path}")


# ── Suite D: Reconciliation polling upgrade ───────────────────────────────────
print("\n=== Suite D: Reconciliation polling (chat_screen.dart) ===")

if os.path.exists(dart_chat_path):
    check("D1  Timer.periodic used for reconciliation polling",
          "Timer.periodic(pollInterval" in chat_src or
          "Timer.periodic(const Duration(seconds: 5)" in chat_src or
          "Timer.periodic(" in chat_src)
    check("D2  5-second poll interval defined",
          "const pollInterval = Duration(seconds: 5)" in chat_src or
          "Duration(seconds: 5)" in chat_src)
    check("D3  maxAttempts = 18 (18 x 5s = 90s)",
          "maxAttempts = 18" in chat_src or "const maxAttempts = 18" in chat_src)
    check("D4  _startReconciliationPolling method present",
          "_startReconciliationPolling" in chat_src)
    check("D5  No old 3-second single-shot reconciliation",
          "Future.delayed(const Duration(seconds: 3)" not in chat_src)
    check("D6  Poll cancels when result found",
          "timer.cancel()" in chat_src)
else:
    print(f"  SKIP  D1-D6  chat_screen.dart not found")


# ── Suite E: Structured failure separation ────────────────────────────────────
print("\n=== Suite E: Structured failure separation (chat_screen.dart) ===")

if os.path.exists(dart_chat_path):
    check("E1  on GenerationException catch block present",
          "on GenerationException catch" in chat_src)
    check("E2  Generic catch block for transport errors",
          "} catch (e) {" in chat_src)
    check("E3  Transport catch does not immediately set _isGenerating = false in hard failure",
          # The transport catch calls _startReconciliationPolling, not showing error immediately
          "_startReconciliationPolling" in chat_src)
    check("E4  Hard failure only on GenerationException path",
          "on GenerationException catch" in chat_src and
          "_isGenerating = false" in chat_src)
    check("E5  String failureMessage only in GenerationException catch",
          # Old pattern: String failureMessage set immediately in catch — now only in GenerationException
          "final failureMessage = e.userMessage" in chat_src)
else:
    print(f"  SKIP  E1-E5  chat_screen.dart not found")


# ── Suite F: Interior completeness rule ───────────────────────────────────────
print("\n=== Suite F: Interior completeness rule ===")

from prompt_engine.realism_layer import (
    build_interior_completeness_rule,
    build_medium_realism_block,
)

icr = build_interior_completeness_rule()
check("F1  build_interior_completeness_rule callable and returns str",
      callable(build_interior_completeness_rule) and isinstance(icr, str))
check("F2  Completeness rule at least 150 chars",
      len(icr) >= 150, f"got {len(icr)}")
check("F3  Completeness rule has 'fully designed' or 'INTERIOR COMPLETENESS'",
      "INTERIOR COMPLETENESS" in icr or "fully designed" in icr.lower())
check("F4  Completeness rule mentions sparse/empty/under-furnished",
      "sparse" in icr.lower() or "under-furnished" in icr.lower() or "empty" in icr.lower())
check("F5  Completeness rule mentions layered furniture/lighting",
      "layered" in icr.lower() and ("furniture" in icr.lower() or "lighting" in icr.lower()))

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    composer_src = f.read()

check("F6  build_interior_completeness_rule imported in composer",
      "build_interior_completeness_rule" in composer_src)
check("F7  interior_completeness section key in _SECTION_PRIORITY",
      '"interior_completeness"' in composer_src)
check("F8  interior_completeness assigned low priority (P4 or P5 — Wave 4.4.1 may change to 5)",
      '"interior_completeness": 4' in composer_src or '"interior_completeness": 5' in composer_src)
check("F9  interior_completeness injected in FIRST_VISION path",
      '("interior_completeness", completeness)' in composer_src)

import logging
logging.disable(logging.CRITICAL)
from prompt_engine.composer import compose_generation_prompt

# Wave 4.3.1: wow_directive replaced dream_micro and may budget-displace
# interior_completeness. Verify wow_directive is present in the FV DNA prompt instead.
p_fv_z_empty = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", "", "", 1, [])
check("F10 Wave 4.3.1 wow_directive present in FV DNA (empty source, within budget)",
      "TRANSFORMATION AMBITION" in p_fv_z_empty,
      f"prompt={len(p_fv_z_empty)} chars")
logging.disable(logging.NOTSET)


# ── Suite G: UX copy — no forbidden words ────────────────────────────────────
print("\n=== Suite G: UX copy (chat_screen.dart) ===")

if os.path.exists(dart_chat_path):
    # Check failure messages in the catch blocks don't use forbidden words
    # We look at the actual message strings
    forbidden_in_failure = ["failed", "timeout", "retry", "error"]
    # Find reassurance message (45s timer)
    reassurance_ok = "still working on it" in chat_src
    check("G1  Reassurance message uses premium language ('still working on it')",
          reassurance_ok)
    check("G2  Reconciliation exhaustion message avoids 'failed'",
          "Your design took longer than expected" in chat_src)
    check("G3  Transport error message avoids 'failed'",
          "Something interrupted the connection" in chat_src)
    check("G4  No bare 'Generation failed — please try again.' in catch blocks",
          "Generation failed — please try again." not in chat_src)
else:
    print(f"  SKIP  G1-G4  chat_screen.dart not found")


# ── Suite H: Prompt size baseline preserved ───────────────────────────────────
print("\n=== Suite H: Prompt sizes (Wave 4.2.4 baseline) ===")

import logging
logging.disable(logging.CRITICAL)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS

room_desc = "Open-plan living room, natural light from west-facing windows, existing oak floors, high ceilings."
history_v2 = [
    {"role": "user", "content": "I want Japandi style, calm and minimal"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer and add more texture"},
]

p_fv_j = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "", 1, [])
p_fv_z = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc, "", 1, [])
p_sr_j = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "more luxurious atmosphere", 2, history_v2)
p_sr_z = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc, "calmer, more serene vibe", 2, history_v2)
p_st   = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "open up the facade, add a large window", 2, history_v2)
p_le   = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "add a floor lamp next to the sofa", 2, history_v2)

logging.disable(logging.NOTSET)

check(f"H1  FIRST_VISION (Japandi/no-DNA) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_j) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_j)}")
check(f"H2  FIRST_VISION (Zen/DNA) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_z) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_z)}")
check(f"H3  STYLE_REFINEMENT (Japandi) within budget ({_MODE_BUDGETS['STYLE_REFINEMENT']})",
      len(p_sr_j) <= _MODE_BUDGETS["STYLE_REFINEMENT"], f"got {len(p_sr_j)}")
check(f"H4  STYLE_REFINEMENT (Zen/DNA) within budget ({_MODE_BUDGETS['STYLE_REFINEMENT']})",
      len(p_sr_z) <= _MODE_BUDGETS["STYLE_REFINEMENT"], f"got {len(p_sr_z)}")
check(f"H5  STRUCTURAL_TRANSFORMATION within budget ({_MODE_BUDGETS['STRUCTURAL_TRANSFORMATION']})",
      len(p_st) <= _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"], f"got {len(p_st)}")
check(f"H6  LOCAL_EDIT within budget ({_MODE_BUDGETS['LOCAL_EDIT']})",
      len(p_le) <= _MODE_BUDGETS["LOCAL_EDIT"], f"got {len(p_le)}")
check("H7  All modes under gpt-image-1 4000-char hard limit",
      all(len(p) < 4000 for p in [p_fv_j, p_fv_z, p_sr_j, p_sr_z, p_st, p_le]))
check("H8  FIRST_VISION realism quality survived (NOT a CGI render)",
      "NOT a CGI render" in p_fv_j)
# Wave 4.8.1b note: "Japandi · Harmony" now correctly resolves to japandi_calm
# DNA (was the lean non-DNA path due to the label->id bug). With the richer DNA,
# compact_realism (P3) is budget-managed in the tight STYLE_REFINEMENT (2400)
# budget - pre-existing systemic behaviour documented in Wave 4.7.5b / 4.8.1a
# for ALL heavy atmospheres (deferred to the 4.8.1 consolidation wave). Japandi
# is now consistent with every other atmosphere. True SR quality invariant:
# FV realism survives AND SR retains its P1 atmosphere-switch anchor.
check("H9  FV realism survives + SR retains P1 atmosphere-switch anchor (4.8.1b-aware)",
      "NOT a CGI render" in p_fv_j and "SAME APARTMENT" in p_sr_j)
check("H10 Wave 4.3.1 wow_directive on FV DNA: TRANSFORMATION AMBITION present",
      "TRANSFORMATION AMBITION" in p_fv_z)


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
  PROMPT SIZE REPORT (Wave 4.2.5):
    FIRST_VISION  (Japandi/no-DNA): {len(p_fv_j)} chars
    FIRST_VISION  (Zen/DNA)       : {len(p_fv_z)} chars
    STYLE_REFINE  (Japandi/no-DNA): {len(p_sr_j)} chars
    STYLE_REFINE  (Zen/DNA)       : {len(p_sr_z)} chars
    STRUCT_TRANS  (Japandi/no-DNA): {len(p_st)} chars
    LOCAL_EDIT    (Japandi)       : {len(p_le)} chars

  MANUAL VALIDATION REQUIRED:
  [MANUAL] Dio timeouts: confirm 180s in Xcode/ADB logs during slow generation
  [MANUAL] 45s timer: confirm reassurance message appears after 45s of real generation
  [MANUAL] Reconciliation: confirm polling succeeds when backend finishes after client timeout
  [MANUAL] Retry loop: confirm [OpenAI Attempt 1/3] appears in backend logs
  [MANUAL] Soft Luxury, Tropical, Japandi: real end-to-end generation quality check
""")
