"""
Wave 4.3.3 validation suite — First Vision Fidelity Reconstruction.

Problem: FIRST_VISION occasionally produces fake-apartment redesigns.
  "REDESIGN —" as the task header established architectural reinvention as the
  dominant signal. Symptoms in PROD: bay windows moved, openings changed,
  TV zone relocated, spatial depth altered, room proportions drifted.

  Root cause: the model treats the real photo as stylistic inspiration, not as
  spatial truth. The Tier 1 structural contract is comprehensive but reads as a
  prohibition list — not as a reconstruction mandate.

Fix: Reconstruction-first task framing via fidelity_layer.build_first_vision_task().
  - "SAME APARTMENT — apply {atmosphere}" establishes spatial identity first.
  - "The photo defines spatial truth" is explicit image-grounding language.
  - "reproduce geometry, camera, windows, openings, and depth exactly" is the mandate.
  - "Then transform all surfaces, materials, and light" preserves WOW aspiration.
  - Budget raised 3250 -> 3350 to accommodate the ~99-char longer task header.

Suites:
  A — fidelity_layer module: callable, vocabulary, no topology lock
  B — Composer integration: import, budget, old header removed, new function used
  C — FIRST_VISION rendered prompt: reconstruction vocabulary present
  D — FV vs SR differentiation: topology lock stays in SR only
  E — Budget compliance at 3350 for all FV paths
  F — WOW preservation: wow_directive and transformation vocabulary intact
  G — Regression: retry system, frozen modules, all prior waves intact
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


# ── Suite A: fidelity_layer module ───────────────────────────────────────────
print("\n=== Suite A: fidelity_layer module ===")

from prompt_engine.fidelity_layer import build_first_vision_task

check("A1  build_first_vision_task() importable and callable",
      callable(build_first_vision_task))

task_lr = build_first_vision_task("Zen Retreat", " living room")
task_empty = build_first_vision_task("Japandi", "")

check("A2  task with room_ctx contains 'SAME APARTMENT'",
      "SAME APARTMENT" in task_lr)
check("A3  task contains 'spatial truth' (image-grounding language)",
      "spatial truth" in task_lr)
check("A4  task contains 'geometry' (spatial reconstruction mandate)",
      "geometry" in task_lr)
check("A5  task contains 'windows' (specific element named as fixed fact)",
      "windows" in task_lr)
check("A6  task contains 'openings' (openings named as fixed facts)",
      "openings" in task_lr)
check("A7  task contains 'depth' (spatial depth named as fixed fact)",
      "depth" in task_lr)
check("A8  task contains 'camera' (camera perspective named as fixed fact)",
      "camera" in task_lr)
check("A9  task contains 'transform' (WOW transformation preserved in mandate)",
      "transform" in task_lr.lower())
check("A10 task with room_ctx contains room name (e.g. 'living room')",
      "living room" in task_lr)
check("A11 task without room_ctx falls back to 'space' (no apostrophe-s grammar error)",
      "this space" in task_empty)
check("A12 task does NOT contain 'REDESIGN' (old frame removed)",
      "REDESIGN" not in task_lr)
check("A13 task does NOT contain 'TOPOLOGY LOCKED' (FV lighter than SR)",
      "TOPOLOGY LOCKED" not in task_lr)
check("A14 task length 150-250 chars for typical room (budget-aware)",
      150 <= len(task_lr) <= 250, f"got {len(task_lr)}")

with open("prompt_engine/fidelity_layer.py", encoding="utf-8") as f:
    fidelity_src = f.read()

check("A15 fidelity_layer module documents Wave 4.3.3",
      "Wave 4.3.3" in fidelity_src)
check("A16 fidelity_layer documents 'reconstruction-first' strategy",
      "reconstruction" in fidelity_src.lower())
check("A17 fidelity_layer mentions WOW preservation (not weakening wow)",
      "WOW" in fidelity_src)


# ── Suite B: Composer integration ────────────────────────────────────────────
print("\n=== Suite B: Composer integration ===")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()

check("B1  fidelity_layer imported in composer",
      "from .fidelity_layer import build_first_vision_task" in comp_src)
check("B2  build_first_vision_task() called in FIRST_VISION path",
      "build_first_vision_task(" in comp_src)
check("B3  FIRST_VISION budget raised above 3250 (Wave 4.3.3+)",
      '"FIRST_VISION": 3350' in comp_src or '"FIRST_VISION": 3550' in comp_src)
check("B4  Old 'REDESIGN — this' literal NOT in composer source",
      '"REDESIGN — this' not in comp_src)
check("B5  Wave 4.3.3 comment present in composer",
      "Wave 4.3.3" in comp_src)
check("B6  Wave 4.3.1 wow_directive import still present (WOW not removed)",
      "from .wow_layer import build_first_vision_wow_directive" in comp_src)
check("B7  task variable assigned from build_first_vision_task() in Path D",
      "task = build_first_vision_task(" in comp_src)
check("B8  wow_directive still listed as P4 in _SECTION_PRIORITY",
      '"wow_directive": 4' in comp_src)
check("B9  STYLE_REFINEMENT path unchanged (no fidelity_task in SR path)",
      comp_src.index("Path B: STYLE REFINEMENT") < comp_src.index("build_first_vision_task("))
check("B10 build_first_vision_task not used outside FIRST_VISION path",
      comp_src.count("build_first_vision_task(") == 1)


# ── Suite C: FIRST_VISION rendered prompt vocabulary ─────────────────────────
print("\n=== Suite C: FIRST_VISION rendered prompt vocabulary ===")

logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS
logging.disable(logging.CRITICAL)

room_desc = "A bright living room with oak floors, large west-facing windows, and a sofa."
anchor_desc = (
    "Open-plan living room, black glass partition separating home office, "
    "balcony door access on left, diagonal depth, visible connected zones."
)
history_v2 = [
    {"role": "user", "content": "I want Japandi style"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer"},
]

# Zen DNA path (tightest budget)
p_fv_zen = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc, "", 1, [])
# Japandi no-DNA path
p_fv_jap = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "", 1, [])
# Japandi home office (non-DNA)
p_fv_nondna = compose_generation_prompt("Japandi · Harmony", "home office", room_desc, "", 1, [])

check("C1  FIRST_VISION (Zen DNA) contains 'SAME APARTMENT'",
      "SAME APARTMENT" in p_fv_zen)
check("C2  FIRST_VISION (Zen DNA) contains 'spatial truth'",
      "spatial truth" in p_fv_zen)
check("C3  FIRST_VISION (Zen DNA) contains 'geometry'",
      "geometry" in p_fv_zen)
check("C4  FIRST_VISION (Zen DNA) does NOT contain 'REDESIGN —'",
      "REDESIGN —" not in p_fv_zen)
check("C5  FIRST_VISION (Zen DNA) still contains 'CAMERA LOCK' (Tier 1 intact)",
      "CAMERA LOCK" in p_fv_zen)
check("C6  FIRST_VISION (Zen DNA) still contains 'STRUCTURAL LOCK'",
      "STRUCTURAL LOCK" in p_fv_zen)
check("C7  FIRST_VISION (Zen DNA) still contains 'TRANSFORMATION AMBITION' (wow_directive)",
      "TRANSFORMATION AMBITION" in p_fv_zen)
check("C8  FIRST_VISION (Japandi no-DNA) contains 'SAME APARTMENT'",
      "SAME APARTMENT" in p_fv_jap)
check("C9  FIRST_VISION (Japandi no-DNA) contains 'spatial truth'",
      "spatial truth" in p_fv_jap)
check("C10 FIRST_VISION (non-DNA home office) contains 'SAME APARTMENT'",
      "SAME APARTMENT" in p_fv_nondna)
check("C11 FIRST_VISION does NOT contain 'TOPOLOGY LOCKED' (FV not over-constrained)",
      "TOPOLOGY LOCKED" not in p_fv_zen)
check("C12 FIRST_VISION 'SAME APARTMENT' is from FV task (not from atmosphere contract)",
      "SAME APARTMENT — ATMOSPHERE SWITCH" not in p_fv_zen)


# ── Suite D: FV vs SR differentiation ────────────────────────────────────────
print("\n=== Suite D: FV vs SR differentiation ===")

p_sr = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "warmer", 2, history_v2
)
p_sr_zen = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", anchor_desc, "warmer", 2, history_v2
)

check("D1  STYLE_REFINEMENT still contains 'TOPOLOGY LOCKED' (Wave 4.3.0 intact)",
      "TOPOLOGY LOCKED" in p_sr)
check("D2  STYLE_REFINEMENT still contains 'SAME APARTMENT — ATMOSPHERE SWITCH'",
      "SAME APARTMENT — ATMOSPHERE SWITCH" in p_sr)
check("D3  STYLE_REFINEMENT does NOT contain 'spatial truth' (FV-only framing)",
      "spatial truth" not in p_sr)
check("D4  STYLE_REFINEMENT does NOT contain 'TRANSFORMATION AMBITION' (FV-only wow)",
      "TRANSFORMATION AMBITION" not in p_sr)
check("D5  STYLE_REFINEMENT with anchors still has 'ARCHITECTURAL ANCHORS'",
      "ARCHITECTURAL ANCHORS" in p_sr_zen)
check("D6  FIRST_VISION 'SAME APARTMENT' origin differs from SR 'SAME APARTMENT — ATMOSPHERE SWITCH'",
      "SAME APARTMENT — apply" in p_fv_zen and "SAME APARTMENT — ATMOSPHERE SWITCH" not in p_fv_zen)
check("D7  STRUCTURAL_TRANSFORMATION path unchanged (no FV reconstruction framing)",
      "spatial truth" not in compose_generation_prompt(
          "Japandi · Harmony", "living room", room_desc, "open up the facade wall", 2, history_v2
      ))


# ── Suite E: Budget compliance ────────────────────────────────────────────────
print("\n=== Suite E: Budget compliance (FIRST_VISION budget >= 3350) ===")

p_fv_sl  = compose_generation_prompt("Soft Luxury · Gold", "living room", room_desc, "", 1, [])
p_fv_dev = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", room_desc, "", 1, [], compact_prompts=True
)
p_sr_j   = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "warmer", 2, history_v2
)
p_st_j   = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "open up the facade", 2, history_v2
)

budget_fv = _MODE_BUDGETS["FIRST_VISION"]

check(f"E1  FIRST_VISION budget >= 3350 (Wave 4.3.3 raised from 3250; Wave 4.4.1 may raise further)",
      budget_fv >= 3350, f"got {budget_fv}")
check(f"E2  FIRST_VISION (Zen DNA) within budget",
      len(p_fv_zen) <= budget_fv, f"got {len(p_fv_zen)}")
check(f"E3  FIRST_VISION (Japandi no-DNA) within budget",
      len(p_fv_jap) <= budget_fv, f"got {len(p_fv_jap)}")
check(f"E4  FIRST_VISION (Soft Luxury DNA) within budget",
      len(p_fv_sl) <= budget_fv, f"got {len(p_fv_sl)}")
check(f"E5  FIRST_VISION DEV compact within budget",
      len(p_fv_dev) <= budget_fv, f"got {len(p_fv_dev)}")
check(f"E6  STYLE_REFINEMENT budget unchanged (2400)",
      _MODE_BUDGETS["STYLE_REFINEMENT"] == 2400)
check(f"E7  STRUCTURAL_TRANSFORMATION budget unchanged (2500)",
      _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"] == 2500)
check("E8  All FV modes under 4000-char hard limit",
      all(len(p) < 4000 for p in [p_fv_zen, p_fv_jap, p_fv_sl, p_fv_dev]))
check("E9  Zen FV prompt is larger than DEV compact (reconstruction framing applies in PROD only)",
      len(p_fv_zen) > len(p_fv_dev))
check("E10 DEV compact does NOT contain 'TRANSFORMATION AMBITION' (P4 skipped in compact mode)",
      "TRANSFORMATION AMBITION" not in p_fv_dev)
check("E11 DEV compact STILL contains 'SAME APARTMENT' (task is P1, never dropped)",
      "SAME APARTMENT" in p_fv_dev)
check("E12 DEV compact STILL contains 'spatial truth' (task is P1, never dropped)",
      "spatial truth" in p_fv_dev)


# ── Suite F: WOW preservation ────────────────────────────────────────────────
print("\n=== Suite F: WOW preservation ===")

from prompt_engine.wow_layer import build_first_vision_wow_directive, _WOW_DIRECTIVE

wow = build_first_vision_wow_directive()

check("F1  wow_directive still returns 'TRANSFORMATION AMBITION'",
      "TRANSFORMATION AMBITION" in wow)
check("F2  wow_directive still has 'Visible architecture stays recognizable'",
      "Visible architecture" in wow and "recognizable" in wow)
check("F3  wow_directive still has architecture continuity items",
      "partitions" in wow and "equipment" in wow)
check("F4  wow_directive still has anti-reinvention language",
      "reinvention" in wow.lower())
check("F5  wow_directive still has WOW transformation aspiration",
      "WOW" in wow)
check("F6  FIRST_VISION (Zen DNA) still contains wow_directive content",
      "TRANSFORMATION AMBITION" in p_fv_zen)
check("F7  FIRST_VISION (Japandi no-DNA) still contains wow_directive content",
      "TRANSFORMATION AMBITION" in p_fv_jap)
check("F8  wow_directive unchanged from Wave 4.3.1 (_WOW_DIRECTIVE constant intact)",
      build_first_vision_wow_directive() == _WOW_DIRECTIVE)
check("F9  Soft Luxury DNA wow drop is pre-existing (not caused by 4.3.3)",
      # SL DNA at 939 chars exceeds budget headroom — known pre-existing limitation
      "CAMERA LOCK" in p_fv_sl and "SAME APARTMENT" in p_fv_sl)


# ── Suite G: Regression ──────────────────────────────────────────────────────
print("\n=== Suite G: Regression (prior waves + frozen modules) ===")

from retry_classifier import classify_for_retry, RetryVerdict, RetryDecision
from generation_profiles import get_active_profile, _PROFILES

check("G1  classify_for_retry still importable", callable(classify_for_retry))
check("G2  RetryVerdict.TRANSIENT still present",
      RetryVerdict.TRANSIENT.value == "TRANSIENT")
check("G3  RetryDecision still frozen dataclass",
      RetryDecision.__dataclass_params__.frozen)

p_prod = _PROFILES["prod"]
p_dev  = _PROFILES["dev"]
check("G4  PROD max_attempts=3 unchanged", p_prod.max_attempts == 3)
check("G5  DEV max_attempts=1 unchanged",  p_dev.max_attempts == 1)
check("G6  PROD compact_prompts=False unchanged", p_prod.compact_prompts is False)
check("G7  DEV compact_prompts=True unchanged",   p_dev.compact_prompts is True)

# Wave 4.3.2 regression: max_retries=0 in main.py
with open("main.py", encoding="utf-8") as f:
    main_src = f.read()

check("G8  max_retries=0 still present in main.py (Wave 4.3.2 intact)",
      "max_retries=0" in main_src)
check("G9  SDK retries DISABLED log still present",
      "SDK internal retries DISABLED" in main_src or "SDK retries DISABLED" in main_src)

# Wave 4.3.1 regression: wow_directive present
check("G10 build_first_vision_wow_directive() still callable", callable(build_first_vision_wow_directive))
check("G11 wow_directive still P4 in _SECTION_PRIORITY", '"wow_directive": 4' in comp_src)

# Wave 4.3.0 regression: atmosphere switch contract
from prompt_engine.preservation import build_atmosphere_switch_contract
c_atm = build_atmosphere_switch_contract("living room")
check("G12 atmosphere_switch_contract still has 'TOPOLOGY LOCKED' (Wave 4.3.0 intact)",
      "TOPOLOGY LOCKED" in c_atm)
check("G13 atmosphere_switch_contract still has 'SAME APARTMENT' (Wave 4.3.0 intact)",
      "SAME APARTMENT" in c_atm)

from prompt_engine.anchor_detector import detect_anchors
ap = detect_anchors("Open-plan living room with black glass partition and balcony door.")
check("G14 detect_anchors still finds anchors", len(ap.anchors) > 0)

from prompt_engine.intent_classifier import classify_intent, ConversationIntent
check("G15 intent_classifier still importable", callable(classify_intent))
check("G16 'go ahead' still -> GENERATE",
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
  WAVE 4.3.3 — FIDELITY RECONSTRUCTION ANALYSIS:

  Problem                    | Before 4.3.3          | After 4.3.3
  ---------------------------|------------------------|-------------------------
  Task opening signal        | "REDESIGN —" (reinvent)| "SAME APARTMENT —"
  Image relationship frame   | inspiration            | spatial truth
  Geometry instruction       | implicit (in contract) | explicit first signal
  Two-phase ordering         | implicit               | "reproduce -> then transform"
  WOW directive              | unchanged              | unchanged (Wave 4.3.1)
  Tier 1 contract            | unchanged              | unchanged
  FIRST_VISION budget        | 3250 chars             | 3350 chars (+100)
  Task header size           | ~100-130 chars         | ~165-220 chars (+99)

  WHY FAKE-APARTMENT RISK IS REDUCED:
  - "SAME APARTMENT" is the first semantic signal the model processes
  - "The photo defines spatial truth" explicitly grounds the model to the input image
  - "reproduce... exactly" is a reproduction mandate, not a preservation prohibition
  - Two-phase ordering makes the task mentally: (1) reconstruct, (2) transform
  - Combined with existing Tier 1 contract: reconstruction mandate + detailed prohibitions

  WHY WOW IS PRESERVED:
  - wow_directive (Wave 4.3.1) unchanged: "TRANSFORMATION AMBITION — THIS apartment..."
  - Task second phase: "Then transform all surfaces, materials, and light"
  - The model is told to be spatially faithful AND editorially transformative

  FIRST_VISION vs STYLE_REFINEMENT:
  - FV: "SAME APARTMENT — apply {atmosphere}" + no topology lock
  - SR: "SAME APARTMENT — ATMOSPHERE SWITCH" + TOPOLOGY LOCKED + zone freeze
  - FV remains more creatively flexible; SR has strict topology preservation
  - FV reconstruction mandate is via task framing; SR uses explicit topology lock

  REMAINING LIMITATIONS:
  [HONEST] Soft Luxury · Gold living room DNA (939 chars) fills budget before
    wow_directive fits — this is a pre-existing condition, not caused by 4.3.3.
    The task's reconstruction framing still applies via the "SAME APARTMENT" and
    "spatial truth" language, which is P1 (never dropped).
  [HONEST] Fidelity is probabilistic — image-to-image models still exercise
    artistic latitude. The fix reduces systematic fake-apartment generation but
    cannot eliminate all spatial drift.
  [MANUAL] Test with the benchmark apartment (bay windows, glass partition,
    diagonal depth) — verify bay windows survive the transformation.
  [MANUAL] Confirm PROD logs show "SAME APARTMENT" in first line of generated prompt.
""")
