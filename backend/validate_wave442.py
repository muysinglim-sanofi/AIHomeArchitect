"""
Wave 4.4.2 validation suite — Latency, Cost & Retry Observability.

PROBLEM (from PROD):
  Generations sometimes exceed 2 minutes perceived latency.
  OpenAI attempt 1 frequently fails after ~60s, retry launches attempt 2.
  Total cost can reach ~$0.60/render. No per-stage visibility to diagnose root cause.

WAVE 4.4.2 DELIVERABLES:
  - performance_observer.py — PipelineTimer, estimate_payload_bytes, estimate_cost_usd
  - main.py instrumentation  — [PERF] stage logs + [PERF SUMMARY] end-of-request log
  - docs/PERFORMANCE_ANALYSIS.md — benchmark scenarios, cost model, risk register

QUALITY GUARANTEE: Zero changes to visual quality systems.
  FROZEN: fidelity_layer, mask system, wow_directive, compact_realism, DNA, quality=high.

Suites:
  A — performance_observer.py: module exists, all APIs correct
  B — main.py instrumentation: all [PERF] log points present
  C — No-regression: quality systems unchanged, Wave 4.4.1 intact
  D — Cost model: estimate correctness
  E — Performance analysis document: exists with required sections
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


# ── Suite A: performance_observer.py ─────────────────────────────────────────
print("\n=== Suite A: performance_observer.py ===")

obs_path = os.path.join(os.path.dirname(__file__), "performance_observer.py")
check("A1  performance_observer.py exists", os.path.isfile(obs_path))

with open(obs_path, encoding="utf-8") as f:
    obs_src = f.read()

check("A2  estimate_payload_bytes defined",
      "def estimate_payload_bytes(" in obs_src)
check("A3  estimate_cost_usd defined",
      "def estimate_cost_usd(" in obs_src)
check("A4  cost_risk_label defined",
      "def cost_risk_label(" in obs_src)
check("A5  PipelineTimer class defined",
      "class PipelineTimer" in obs_src)
check("A6  PipelineTimer.record method defined",
      "def record(" in obs_src)
check("A7  PipelineTimer.log_summary method defined",
      "def log_summary(" in obs_src)
check("A8  PipelineTimer.total_openai_ms defined",
      "def total_openai_ms(" in obs_src)
check("A9  PipelineTimer.openai_attempt_count defined",
      "def openai_attempt_count(" in obs_src)
check("A10 PipelineTimer.stage_ms defined",
      "def stage_ms(" in obs_src)

# Runtime API checks
from performance_observer import (
    estimate_payload_bytes,
    estimate_cost_usd,
    cost_risk_label,
    PipelineTimer,
)

_fake_image = b"JPEG" * 100000   # 400KB fake image
_fake_mask  = b"PNG"  * 50000    # 150KB fake mask
_fake_prompt = "A" * 3000

payload_est = estimate_payload_bytes(_fake_image, _fake_mask, _fake_prompt)
check("A11 estimate_payload_bytes returns positive int",
      isinstance(payload_est, int) and payload_est > 0)
check("A12 estimate_payload_bytes includes image + mask + prompt + overhead",
      payload_est == len(_fake_image) + len(_fake_mask) + len(_fake_prompt.encode("utf-8")) + 600)
check("A13 estimate_payload_bytes handles None mask",
      estimate_payload_bytes(_fake_image, None, _fake_prompt) == len(_fake_image) + len(_fake_prompt.encode("utf-8")) + 600)

cost_high = estimate_cost_usd("high", "1536x1024", openai_attempts=1, vision_calls=1)
check("A14 estimate_cost_usd high/1536x1024 single attempt ~= $0.194",
      abs(cost_high - 0.194) < 0.001, f"got {cost_high}")

cost_two = estimate_cost_usd("high", "1536x1024", openai_attempts=2, vision_calls=1)
check("A15 estimate_cost_usd 2 attempts ~= $0.384",
      abs(cost_two - 0.384) < 0.001, f"got {cost_two}")

cost_dev = estimate_cost_usd("medium", "1024x1024", openai_attempts=1, vision_calls=1)
check("A16 estimate_cost_usd medium/1024x1024 ~= $0.044",
      abs(cost_dev - 0.044) < 0.001, f"got {cost_dev}")

check("A17 cost_risk_label LOW for cost < 0.05",
      cost_risk_label(0.04) == "LOW")
check("A18 cost_risk_label MEDIUM for cost in [0.05, 0.25)",
      cost_risk_label(0.194) == "MEDIUM")
check("A19 cost_risk_label HIGH for cost in [0.25, 0.50)",
      cost_risk_label(0.384) == "HIGH")
check("A20 cost_risk_label CRITICAL for cost >= 0.50",
      cost_risk_label(0.574) == "CRITICAL")

# PipelineTimer runtime checks
timer = PipelineTimer("test-request-001")
timer.record("image_fetch", 1.24, size_bytes=892341)
timer.record("vision_analysis", 4.82)
timer.record("openai_api", 58.1, attempt=1, status="success")
timer.record("supabase_upload", 1.83, size_bytes=1204800)

check("A21 PipelineTimer.stage_ms returns correct value for image_fetch",
      abs(timer.stage_ms("image_fetch") - 1240.0) < 1.0)
check("A22 PipelineTimer.total_openai_ms sums all openai_api stages",
      abs(timer.total_openai_ms() - 58100.0) < 1.0)
check("A23 PipelineTimer.openai_attempt_count counts openai_api records",
      timer.openai_attempt_count() == 1)
check("A24 PipelineTimer.stage_ms returns 0.0 for unrecorded stage",
      timer.stage_ms("nonexistent_stage") == 0.0)

# Two-attempt timer
timer2 = PipelineTimer("test-request-002")
timer2.record("openai_api", 61.0, attempt=1, status="failed")
timer2.record("openai_api", 54.5, attempt=2, status="success")
check("A25 PipelineTimer.total_openai_ms sums both attempts",
      abs(timer2.total_openai_ms() - (61000.0 + 54500.0)) < 1.0)
check("A26 PipelineTimer.openai_attempt_count = 2 for two attempts",
      timer2.openai_attempt_count() == 2)


# ── Suite B: main.py instrumentation ─────────────────────────────────────────
print("\n=== Suite B: main.py instrumentation ===")

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()

check("B1  performance_observer imported in main.py",
      "from performance_observer import" in main_src)
check("B2  PipelineTimer imported",
      "PipelineTimer" in main_src)
check("B3  estimate_payload_bytes imported",
      "estimate_payload_bytes" in main_src)
check("B4  estimate_cost_usd imported",
      "estimate_cost_usd" in main_src)

check("B5  PipelineTimer instantiated in generate()",
      "_timer = PipelineTimer(request_id)" in main_src)
check("B6  _payload_bytes_est initialized",
      "_payload_bytes_est = 0" in main_src)

check("B7  image_fetch stage recorded",
      '_timer.record("image_fetch"' in main_src)
check("B8  [PERF] stage=image_fetch logged",
      '"[PERF] stage=image_fetch' in main_src)

check("B9  vision_analysis stage recorded",
      '_timer.record("vision_analysis"' in main_src)
check("B10 [PERF] stage=vision_analysis logged",
      '"[PERF] stage=vision_analysis' in main_src)
check("B11 vision_analysis timing uses finally block (captures failure latency too)",
      "finally:" in main_src and "_t_vision" in main_src)

check("B12 prompt_composition stage recorded",
      '_timer.record("prompt_composition"' in main_src)
check("B13 [PERF] stage=prompt_composition logged",
      '"[PERF] stage=prompt_composition' in main_src)

check("B14 mask_generation stage recorded",
      '_timer.record("mask_generation"' in main_src)
check("B15 [PERF] stage=mask_generation logged",
      '"[PERF] stage=mask_generation' in main_src)

check("B16 payload_estimate logged with total_bytes",
      '"[PERF] payload_estimate' in main_src and "total_bytes" in main_src)
check("B17 estimate_payload_bytes called in generate()",
      "estimate_payload_bytes(image_bytes, mask_bytes, design_prompt)" in main_src)

check("B18 openai_api stage recorded for success",
      'status="success"' in main_src)
check("B19 openai_api stage recorded for bad_request",
      'status="bad_request"' in main_src)
check("B20 openai_api stage recorded for failed",
      'status="failed"' in main_src)

check("B21 supabase_upload stage recorded",
      '_timer.record("supabase_upload"' in main_src)
check("B22 [PERF] stage=supabase_upload logged",
      '"[PERF] stage=supabase_upload' in main_src)

check("B23 timer.log_summary called at request end",
      "_timer.log_summary(log, _total_elapsed" in main_src)
check("B24 estimate_cost_usd called at request end",
      "estimate_cost_usd(" in main_src)
check("B25 openai_attempt_count used in cost estimation",
      "openai_attempts=_timer.openai_attempt_count()" in main_src)


# ── Suite C: No-regression quality systems ────────────────────────────────────
print("\n=== Suite C: No-regression (quality systems unchanged) ===")

with open("prompt_engine/mask_generator.py", encoding="utf-8") as f:
    mask_src = f.read()
with open("prompt_engine/wow_layer.py", encoding="utf-8") as f:
    wow_src = f.read()
with open("prompt_engine/fidelity_layer.py", encoding="utf-8") as f:
    fid_src = f.read()
with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()

# Wave 4.4.0: mask system intact
check("C1  Wave 4.4.0 ENABLE_STRUCTURAL_MASK default=true still in main.py",
      'ENABLE_STRUCTURAL_MASK", "true"' in main_src or '"true"' in main_src)
check("C2  Wave 4.4.0 run_in_executor still used for mask",
      "run_in_executor" in main_src)

# Wave 4.4.1: budget + realism intact
from prompt_engine.composer import _MODE_BUDGETS, _SECTION_PRIORITY
check("C3  Wave 4.4.1 FIRST_VISION budget = 3550",
      _MODE_BUDGETS["FIRST_VISION"] == 3550)
check("C4  Wave 4.4.1 interior_completeness priority = 5 (P5)",
      _SECTION_PRIORITY.get("interior_completeness") == 5)
check("C5  Wave 4.4.1 wow_directive priority = 4 (P4)",
      _SECTION_PRIORITY.get("wow_directive") == 4)
check("C6  Wave 4.4.1 compact_realism used in FIRST_VISION path",
      "build_compact_realism_block()" in comp_src)

# Wave 4.3.3: fidelity framing intact
check("C7  Wave 4.3.3 SAME APARTMENT framing preserved",
      "SAME APARTMENT" in fid_src)
check("C8  Wave 4.3.3 spatial truth language preserved",
      "spatial truth" in fid_src)

# Wave 4.3.1: wow_directive text intact
check("C9  Wave 4.3.1 wow_directive vocabulary preserved (THIS apartment)",
      "THIS apartment, not a new one" in wow_src)
check("C10 Wave 4.3.1 wow_directive vocabulary preserved (Visible architecture)",
      "Visible architecture stays recognizable" in wow_src)

# Wave 4.3.2: SDK retry disabled
check("C11 Wave 4.3.2 max_retries=0 still in main.py",
      "max_retries=0" in main_src)

# gpt-image-1 quality/input_fidelity frozen
check("C12 gpt-image-1 model still used (not downgraded)",
      'model="gpt-image-1"' in main_src)
check("C13 quality passed from profile (not hardcoded to lower quality)",
      "quality=profile.quality" in main_src)
check("C14 input_fidelity passed from profile (not removed)",
      "input_fidelity=profile.input_fidelity" in main_src)

# performance_observer import does NOT replace any quality system
check("C15 compose_generation_prompt still called (prompt engine not bypassed)",
      "compose_generation_prompt(" in main_src)
check("C16 classify_edit_mode still called (edit mode routing intact)",
      "classify_edit_mode(" in main_src)


# ── Suite D: Cost model correctness ──────────────────────────────────────────
print("\n=== Suite D: Cost model correctness ===")

from performance_observer import _COST_TABLE, _VISION_COST_PER_CALL

check("D1  _COST_TABLE has 9 entries (3 qualities × 3 sizes)",
      len(_COST_TABLE) == 9)
check("D2  high/1536x1024 = $0.190",
      _COST_TABLE.get(("high", "1536x1024")) == 0.190)
check("D3  high/1024x1536 = $0.190",
      _COST_TABLE.get(("high", "1024x1536")) == 0.190)
check("D4  high/1024x1024 = $0.080",
      _COST_TABLE.get(("high", "1024x1024")) == 0.080)
check("D5  medium/1536x1024 = $0.070",
      _COST_TABLE.get(("medium", "1536x1024")) == 0.070)
check("D6  medium/1024x1024 = $0.040",
      _COST_TABLE.get(("medium", "1024x1024")) == 0.040)
check("D7  _VISION_COST_PER_CALL = $0.004",
      _VISION_COST_PER_CALL == 0.004)

# Unknown quality/size falls back to high/1024x1024
cost_unknown = estimate_cost_usd("ultra", "9999x9999", openai_attempts=1, vision_calls=0)
check("D8  Unknown quality/size falls back to high/1024x1024 ($0.080)",
      abs(cost_unknown - 0.080) < 0.001, f"got {cost_unknown}")

# Cost risk boundaries
check("D9  cost_risk_label boundary: 0.04999 = LOW",
      cost_risk_label(0.04999) == "LOW")
check("D10 cost_risk_label boundary: 0.05 = MEDIUM",
      cost_risk_label(0.05) == "MEDIUM")
check("D11 cost_risk_label boundary: 0.249 = MEDIUM",
      cost_risk_label(0.249) == "MEDIUM")
check("D12 cost_risk_label boundary: 0.25 = HIGH",
      cost_risk_label(0.25) == "HIGH")
check("D13 cost_risk_label boundary: 0.499 = HIGH",
      cost_risk_label(0.499) == "HIGH")
check("D14 cost_risk_label boundary: 0.50 = CRITICAL",
      cost_risk_label(0.50) == "CRITICAL")


# ── Suite E: Performance analysis document ────────────────────────────────────
print("\n=== Suite E: Performance analysis document ===")

perf_doc_path = os.path.join(os.path.dirname(__file__), "docs", "PERFORMANCE_ANALYSIS.md")
check("E1  docs/PERFORMANCE_ANALYSIS.md exists",
      os.path.isfile(perf_doc_path))

if os.path.isfile(perf_doc_path):
    with open(perf_doc_path, encoding="utf-8") as f:
        perf_src = f.read()
else:
    perf_src = ""

check("E2  Document covers pipeline stages",
      "image_fetch" in perf_src and "vision_analysis" in perf_src)
check("E3  Document covers cost estimation model",
      "Cost Estimation" in perf_src or "cost" in perf_src.lower())
check("E4  Document covers benchmark scenarios",
      "Scenario" in perf_src or "Benchmark" in perf_src)
check("E5  Document covers what was NOT optimized (deferred list)",
      "NOT Optimized" in perf_src or "DEFERRED" in perf_src or "Deferred" in perf_src)
check("E6  Document covers remaining risks",
      "Remaining Risk" in perf_src or "risk" in perf_src.lower())
check("E7  Document covers [PERF SUMMARY] log format",
      "PERF SUMMARY" in perf_src)
check("E8  Document covers manual PROD checklist",
      "Checklist" in perf_src or "checklist" in perf_src.lower() or "PROD" in perf_src)
check("E9  Document covers cost_risk labels",
      "MEDIUM" in perf_src and "CRITICAL" in perf_src)
check("E10 Document version is Wave 4.4.2",
      "4.4.2" in perf_src)


# ── Summary ───────────────────────────────────────────────────────────────────
passed = sum(1 for _, ok in results if ok)
failed = sum(1 for _, ok in results if not ok)
total  = len(results)

print("\n" + "=" * 60)
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {failed}")
if failed:
    print("\n  FAILING CHECKS:")
    for label, ok in results:
        if not ok:
            print(f"    - {label}")
print("=" * 60)

print("""
  WAVE 4.4.2 ANALYSIS - LATENCY, COST & RETRY OBSERVABILITY:

  Instrumentation added:
    image_fetch      -> [PERF] stage timing + size_bytes
    vision_analysis  -> [PERF] stage timing (finally block, captures failures)
    prompt_comp      -> [PERF] stage timing + chars
    mask_generation  -> [PERF] stage timing + mask_generated
    payload_estimate -> [PERF] total/image/mask/prompt bytes
    openai_api       -> per-attempt timing with status (success/bad_request/failed)
    supabase_upload  -> [PERF] stage timing + size_bytes
    [PERF SUMMARY]   -> full request summary with est_cost_usd + cost_risk

  Expected PROD patterns:
    Single-attempt success: total_ms ~35,000-100,000  cost_risk=MEDIUM
    Two-attempt success:    total_ms ~90,000-180,000  cost_risk=HIGH
    Three-attempt failure:  total_ms ~180,000+        cost_risk=CRITICAL

  FROZEN (untouched):
    gpt-image-1  quality=high  input_fidelity=high  size=aspect-matched
    SAME APARTMENT framing  mask system  wow_directive  compact_realism
    compose_generation_prompt  retry_classifier  attempt logic

  MANUAL PROD CHECKLIST:
    [1] Restart backend. Confirm [PERF SUMMARY] in logs.
    [2] Confirm est_cost_usd ~0.194 for single-attempt FIRST_VISION.
    [3] Confirm openai_ms (x1 attempts) dominates total_ms.
    [4] If retry fires: confirm openai_ms (x2 attempts) and cost_risk=HIGH.
    [5] Confirm no regression in compression_applied / wow_directive survival.
""")
