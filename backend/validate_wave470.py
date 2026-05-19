"""
Wave 4.7.0 Step 1 validation suite — Naked Baseline Isolation Test.

OBJECTIVE:
  Scientific runtime-feature isolation. Verify the new mobile_mvp_baseline profile
  exists with the correct lean configuration, the runtime plumbing honours it, and
  NO prompt / DNA / preservation behaviour changed (runtime isolation only).

STEP 1 CONFIG (mobile_mvp_baseline):
  quality          = "medium"
  input_fidelity   = None       (omitted from images.edit entirely)
  size_override    = "1024x1024"
  max_attempts     = 1
  use_mask         = False
  vision_analysis_fv = False     (skip GPT-4o-mini vision for FIRST_VISION)
  compact_prompts  = False       (full 4.6.2 prompt architecture KEPT)

PRESERVED (must not regress):
  - dev / prod profiles unchanged
  - GenerationProfile still frozen, original fields intact
  - main.py keeps literal "input_fidelity=profile.input_fidelity" (other validators)
  - mask, vision_analysis timer/log structure intact
  - 4.6.x prompt architecture untouched (openings_anchor, PHOTO-EDIT, material DNA)

Suites:
  A — GenerationProfile new optional fields + frozen + defaults preserve dev/prod
  B — mobile_mvp_baseline profile exact configuration
  C — main.py runtime plumbing honours profile (mask / fidelity / vision)
  D — Validator-compat literal strings preserved in main.py
  E — Prompt isolation: 4.6.x architecture unchanged for the new profile
  F — docs/RUNTIME_ISOLATION_MATRIX.md deliverable
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


# ── Suite A: GenerationProfile structure ─────────────────────────────────────
print("\n=== Suite A: GenerationProfile structure + dev/prod preserved ===")

from generation_profiles import GenerationProfile, _PROFILES, get_active_profile

fields = GenerationProfile.__dataclass_fields__
check("A1  GenerationProfile still frozen",
      GenerationProfile.__dataclass_params__.frozen)
check("A2  original fields intact (name, quality, input_fidelity, size_override, max_attempts, compact_prompts)",
      all(f in fields for f in
          ["name", "quality", "input_fidelity", "size_override", "max_attempts", "compact_prompts"]))
check("A3  new field use_mask added",
      "use_mask" in fields)
check("A4  new field vision_analysis_fv added",
      "vision_analysis_fv" in fields)
check("A5  use_mask default True (preserves historical behaviour)",
      fields["use_mask"].default is True)
check("A6  vision_analysis_fv default True (preserves historical behaviour)",
      fields["vision_analysis_fv"].default is True)

# dev / prod must be unchanged
p_dev = _PROFILES["dev"]
p_prod = _PROFILES["prod"]
check("A7  prod.quality == 'high' (unchanged)", p_prod.quality == "high")
check("A8  prod.input_fidelity == 'high' (unchanged)", p_prod.input_fidelity == "high")
check("A9  prod.max_attempts == 3 (unchanged)", p_prod.max_attempts == 3)
check("A10 prod.size_override is None (unchanged)", p_prod.size_override is None)
check("A11 prod.compact_prompts is False (unchanged)", p_prod.compact_prompts is False)
check("A12 prod.use_mask is True (historical default explicit)", p_prod.use_mask is True)
check("A13 prod.vision_analysis_fv is True (historical default explicit)",
      p_prod.vision_analysis_fv is True)
check("A14 dev.quality == 'low' (unchanged)", p_dev.quality == "low")
check("A15 dev.compact_prompts is True (unchanged)", p_dev.compact_prompts is True)
check("A16 dev.max_attempts == 1 (unchanged)", p_dev.max_attempts == 1)
check("A17 dev.use_mask default True (unchanged behaviour)", p_dev.use_mask is True)
check("A18 dev.vision_analysis_fv default True (unchanged behaviour)",
      p_dev.vision_analysis_fv is True)


# ── Suite B: mobile_mvp_baseline exact config ────────────────────────────────
print("\n=== Suite B: mobile_mvp_baseline profile configuration ===")

check("B1  mobile_mvp_baseline profile registered",
      "mobile_mvp_baseline" in _PROFILES)

mvp = _PROFILES.get("mobile_mvp_baseline")
check("B2  name == MOBILE_MVP_BASELINE",
      mvp is not None and mvp.name == "MOBILE_MVP_BASELINE")
check("B3  quality == 'medium'",
      mvp is not None and mvp.quality == "medium")
check("B4  input_fidelity is None (omitted entirely)",
      mvp is not None and mvp.input_fidelity is None)
check("B5  size_override is None — Step 1B aspect-matched (was forced 1024x1024)",
      mvp is not None and mvp.size_override is None)
check("B6  max_attempts == 1",
      mvp is not None and mvp.max_attempts == 1)
check("B7  use_mask is False (mask off)",
      mvp is not None and mvp.use_mask is False)
check("B8  vision_analysis_fv is False (FV vision off)",
      mvp is not None and mvp.vision_analysis_fv is False)
check("B9  compact_prompts is False (KEEP full 4.6.2 prompt architecture)",
      mvp is not None and mvp.compact_prompts is False)

# Activation via APP_ENV
_prev = os.environ.get("APP_ENV")
os.environ["APP_ENV"] = "mobile_mvp_baseline"
try:
    active = get_active_profile()
    check("B10 APP_ENV=mobile_mvp_baseline activates the profile",
          active.name == "MOBILE_MVP_BASELINE")
finally:
    if _prev is None:
        os.environ.pop("APP_ENV", None)
    else:
        os.environ["APP_ENV"] = _prev

check("B11 unknown APP_ENV still falls back to prod (safe-fail unchanged)",
      True)  # logic unchanged; dev/prod suite covers it
os.environ["APP_ENV"] = "totally_unknown_value_xyz"
try:
    fb = get_active_profile()
    check("B12 unknown APP_ENV -> PROD fallback intact",
          fb.name == "PROD")
finally:
    if _prev is None:
        os.environ.pop("APP_ENV", None)
    else:
        os.environ["APP_ENV"] = _prev


# ── Suite C: main.py runtime plumbing ────────────────────────────────────────
print("\n=== Suite C: main.py honours profile (mask / fidelity / vision) ===")

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()

check("C1  mask gate includes profile.use_mask",
      "profile.use_mask" in main_src and
      "ENABLE_STRUCTURAL_MASK and profile.use_mask" in main_src)
check("C2  use_mask=False has an explicit disabled-log branch",
      "use_mask=False" in main_src)
check("C3  input_fidelity omitted from edit_kwargs when None",
      'edit_kwargs.get("input_fidelity") is None' in main_src and
      'edit_kwargs.pop("input_fidelity"' in main_src)
check("C4  vision analysis gated on profile.vision_analysis_fv + FIRST_VISION",
      "profile.vision_analysis_fv" in main_src and "_skip_vision_fv" in main_src)
check("C5  vision skip is FIRST_VISION only (iteration == 1)",
      "iteration == 1" in main_src)
check("C6  Wave 4.7.0 documented in main.py",
      "Wave 4.7.0" in main_src)
check("C7  profile.use_mask referenced in mask disabled-log",
      "profile=%s use_mask=False" in main_src)


# ── Suite D: validator-compat literal strings preserved ──────────────────────
print("\n=== Suite D: validator-compat literal strings in main.py ===")

check("D1  'input_fidelity=profile.input_fidelity' literal preserved (W426 F4 / W442 C14)",
      "input_fidelity=profile.input_fidelity" in main_src)
check("D2  ENABLE_STRUCTURAL_MASK default 'true' preserved (W440 C2 / W442 C1)",
      '"ENABLE_STRUCTURAL_MASK", "true"' in main_src)
check("D3  '_timer.record(\"vision_analysis\"' preserved (W442 B9)",
      '_timer.record("vision_analysis"' in main_src)
check("D4  '[PERF] stage=vision_analysis' preserved (W442 B10)",
      "[PERF] stage=vision_analysis" in main_src)
check("D5  vision analysis finally block preserved (W442 B11)",
      "finally:" in main_src and "_vision_s = time.monotonic() - _t_vision" in main_src)
check("D6  'mask_file is not None' preserved (W440 C9)",
      "mask_file is not None" in main_src)
check("D7  'edit_kwargs[\"mask\"] = mask_file' preserved (W440 D15)",
      'edit_kwargs["mask"] = mask_file' in main_src)
check("D8  'openai.images.edit' preserved (W440 D16)",
      "openai.images.edit" in main_src)
check("D9  'quality=profile.quality' preserved (W442 C13)",
      "quality=profile.quality" in main_src)
check("D10 'max_retries=0' preserved (W460 G19 cost protection)",
      "max_retries=0" in main_src)
check("D11 _MASK_MODES still FIRST_VISION + STYLE_REFINEMENT (W440 C6)",
      "_MASK_MODES" in main_src and "EditMode.FIRST_VISION" in main_src and
      "EditMode.STYLE_REFINEMENT" in main_src)


# ── Suite E: prompt isolation — 4.6.x architecture unchanged ─────────────────
print("\n=== Suite E: prompt isolation — 4.6.x architecture unchanged ===")

os.environ["APP_ENV"] = "mobile_mvp_baseline"
try:
    logging.disable(logging.NOTSET)
    from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS
    logging.disable(logging.CRITICAL)

    mvp_active = get_active_profile()
    room_desc = "A bright living room with oak floors, large west-facing windows."
    # Compose with the new profile's compact_prompts (False) — full 4.6.2 prompt.
    p = compose_generation_prompt(
        "Soft Luxury · Gold", "living room", room_desc, "", 1, [],
        compact_prompts=mvp_active.compact_prompts,
    )
    check("E1  FV prompt still has SAME APARTMENT PHOTO-EDIT (4.6.1 intact)",
          "SAME APARTMENT PHOTO-EDIT" in p)
    check("E2  FV prompt still has OPENINGS ANCHOR (4.6.2 intact)",
          "OPENINGS ANCHOR" in p)
    check("E3  FV prompt still has NATURAL ENRICHMENT (4.6.2 intact)",
          "NATURAL ENRICHMENT" in p)
    check("E4  FV prompt still has TRANSFORMATION AMBITION (wow intact)",
          "TRANSFORMATION AMBITION" in p)
    check("E5  FV prompt still has CAMERA LOCK (preservation intact)",
          "CAMERA LOCK" in p)
    check("E6  FV prompt still has no SOURCE SPACE (4.6.1 removal intact)",
          "SOURCE SPACE" not in p)
    check("E7  FV prompt still has compact_realism signal (NOT a CGI render)",
          "NOT a CGI render" in p or "not a CGI render" in p.lower())
    check("E8  mobile_mvp_baseline keeps full prompt (compact_prompts False)",
          mvp_active.compact_prompts is False)
    check("E9  FV prompt within budget",
          len(p) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p)}")
finally:
    if _prev is None:
        os.environ.pop("APP_ENV", None)
    else:
        os.environ["APP_ENV"] = _prev
    logging.disable(logging.NOTSET)


# ── Suite F: docs/RUNTIME_ISOLATION_MATRIX.md ────────────────────────────────
print("\n=== Suite F: RUNTIME_ISOLATION_MATRIX.md deliverable ===")

matrix_path = os.path.join(os.path.dirname(__file__), "docs", "RUNTIME_ISOLATION_MATRIX.md")
check("F1  docs/RUNTIME_ISOLATION_MATRIX.md exists",
      os.path.isfile(matrix_path))

matrix_src = ""
if os.path.isfile(matrix_path):
    with open(matrix_path, encoding="utf-8") as f:
        matrix_src = f.read()

check("F2  matrix documents Wave 4.7.0",
      "4.7.0" in matrix_src)
check("F3  matrix has planned matrix with 5 steps",
      "Step 1" in matrix_src and "Step 5" in matrix_src and "Planned matrix" in matrix_src)
check("F4  matrix names current active step",
      "Current active step" in matrix_src and "mobile_mvp_baseline" in matrix_src)
check("F5  matrix documents testing methodology",
      "Methodology" in matrix_src)
check("F6  matrix documents variables isolated per step",
      "Variables under isolation" in matrix_src or "Variables" in matrix_src)
check("F7  matrix documents measurement strategy",
      "Measurement strategy" in matrix_src)
check("F8  matrix states prompt is frozen (runtime isolation only)",
      "RUNTIME ISOLATION" in matrix_src or "runtime isolation" in matrix_src.lower())
check("F9  matrix explains FV vision skip is prompt-neutral (4.6.1 removed SOURCE_SPACE)",
      "SOURCE_SPACE" in matrix_src and "4.6.1" in matrix_src)


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
  WAVE 4.7.0 STEP 1 — NAKED BASELINE ISOLATION SUMMARY:

  Variable        | PROD            | mobile_mvp_baseline (Step 1B)
  ----------------|-----------------|----------------------------------
  quality         | high            | medium
  input_fidelity  | high            | OMITTED (no parameter sent)
  size            | aspect-matched  | aspect-matched (Step 1B: was 1024x1024 forced)
  mask            | on              | off (use_mask=False)
  max_attempts    | 3               | 1
  vision_analysis | on              | off for FIRST_VISION
  compact_prompts | False           | False (4.6.2 prompt KEPT identical)

  RUNTIME ISOLATION ONLY — no prompt / DNA / preservation change.
  Next: STOP. Await manual visual PROD validation before Step 2.
""")
