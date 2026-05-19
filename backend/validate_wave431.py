"""
Wave 4.3.1 validation suite — First Vision Rebalancing.

Suites:
  A — wow_layer module: content, vocabulary, budget
  B — FIRST_VISION task header: strengthened editorial framing
  C — Composer integration: source inspection for FIRST_VISION path wiring
  D — Use-case differentiation: FV has wow, SR unchanged, ST/LE unaffected
  E — Budget compliance: all modes within hard budgets after 4.3.1
  F — Regression: Wave 4.3.0 preservation intelligence intact; frozen modules
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


# ── Suite A: wow_layer module tests ──────────────────────────────────────────
print("\n=== Suite A: wow_layer module ===")

from prompt_engine.wow_layer import build_first_vision_wow_directive, _WOW_DIRECTIVE

wow = build_first_vision_wow_directive()

check("A1  build_first_vision_wow_directive() returns non-empty string", bool(wow))
check("A2  directive contains 'TRANSFORMATION AMBITION'",
      "TRANSFORMATION AMBITION" in wow)
check("A3  directive contains 'editorial' (not just redesign)",
      "editorial" in wow.lower())
check("A4  directive contains 'THIS apartment, not a new one' (anti-fake-apartment)",
      "THIS apartment, not a new one" in wow)
check("A5  directive contains 'equipment' (equipment identity note)",
      "equipment" in wow.lower())
check("A6  directive contains 'furniture' (furniture identity note)",
      "furniture" in wow.lower())
check("A7  directive contains 'transform' verb",
      "transform" in wow.lower())
check("A8  directive length within 200-320 chars (budget-safe)",
      200 <= len(wow) <= 320, f"got {len(wow)}")
check("A9  directive does NOT contain 'TOPOLOGY LOCKED' (FV lighter than Tier 3.5)",
      "TOPOLOGY LOCKED" not in wow)
check("A10 _WOW_DIRECTIVE and function return same value",
      build_first_vision_wow_directive() == _WOW_DIRECTIVE)
check("A11 directive contains 'recognizable' (architecture continuity, no topology lock)",
      "recognizable" in wow.lower())
check("A12 directive contains 'reinvention' (anti-fake-apartment vocabulary)",
      "reinvention" in wow.lower())
check("A13 directive does NOT contain 'TOPOLOGY LOCKED', 'zone count'",
      "TOPOLOGY LOCKED" not in wow and "zone count" not in wow)
check("A14 directive contains 'partitions' (glass partition / verrière coverage)",
      "partitions" in wow.lower())
check("A15 directive contains 'Visible architecture' (explicit preservation framing)",
      "Visible architecture" in wow)


# ── Suite B: FIRST_VISION task header ─────────────────────────────────────────
# Wave 4.3.3 updated: task header now uses reconstruction-first framing via fidelity_layer.
print("\n=== Suite B: FIRST_VISION task header ===")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()
with open("prompt_engine/fidelity_layer.py", encoding="utf-8") as f:
    fidelity_src = f.read()

check("B1  fidelity_layer imported and used for task in composer (Wave 4.3.3)",
      "from .fidelity_layer import build_first_vision_task" in comp_src and
      "build_first_vision_task(" in comp_src)
check("B2  fidelity_layer contains 'SAME APARTMENT' reconstruction framing",
      "SAME APARTMENT" in fidelity_src)
check("B3  fidelity_layer contains 'spatial truth' image-grounding language",
      "spatial truth" in fidelity_src)
check("B4  old 'REDESIGN — this' literal REMOVED from composer (Wave 4.3.3 supersedes 4.3.1)",
      '"REDESIGN — this' not in comp_src)
check("B5  Wave 4.3.1 comment still present in composer (Wave 4.3.1 WOW directive intact)",
      "Wave 4.3.1" in comp_src)
check("B6  Wave 4.3.3 comment present in composer",
      "Wave 4.3.3" in comp_src)


# ── Suite C: Composer integration — source inspection ─────────────────────────
print("\n=== Suite C: Composer integration (source inspection) ===")

check("C1  build_first_vision_wow_directive imported in composer",
      "from .wow_layer import build_first_vision_wow_directive" in comp_src)
check("C2  'wow_directive' section key present in composer",
      '"wow_directive"' in comp_src)
check("C3  wow_directive is P4 in _SECTION_PRIORITY",
      '"wow_directive": 4' in comp_src)
check("C4  build_first_vision_wow_directive() called in FIRST_VISION path",
      "build_first_vision_wow_directive()" in comp_src)
check("C5  ('wow_directive', wow_block) in FIRST_VISION raw_sections",
      '("wow_directive", wow_block)' in comp_src)
check("C6  interior_completeness listed BEFORE wow_directive in raw_sections",
      comp_src.index('"interior_completeness", completeness') <
      comp_src.index('"wow_directive", wow_block'))
check("C7  scene_completion listed BEFORE wow_directive in raw_sections",
      comp_src.index('"scene_completion", completion_block') <
      comp_src.index('"wow_directive", wow_block'))
check("C8  STYLE_REFINEMENT path still uses dream_micro (unchanged)",
      "build_dream_micro_layer()" in comp_src)
check("C9  STYLE_REFINEMENT path still uses dream_addendum (unchanged)",
      "build_dream_addendum(atmosphere_id)" in comp_src)
check("C10 wow_block variable defined in all three FIRST_VISION branches",
      comp_src.count("wow_block = ") >= 3)


# ── Suite D: Use-case differentiation — composed prompts ─────────────────────
print("\n=== Suite D: Use-case differentiation ===")

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

# FIRST_VISION (Before/After WOW) — must have wow directive, no topology lock
p_fv = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "", 1, [])
check("D1  FIRST_VISION contains 'TRANSFORMATION AMBITION'",
      "TRANSFORMATION AMBITION" in p_fv)
check("D2  FIRST_VISION contains 'SAME APARTMENT' (Wave 4.3.3 reconstruction-first task)",
      "SAME APARTMENT" in p_fv)
check("D3  FIRST_VISION contains 'spatial truth' (Wave 4.3.3 image-grounding language)",
      "spatial truth" in p_fv)
check("D4  FIRST_VISION does NOT contain 'TOPOLOGY LOCKED' (FV not over-constrained)",
      "TOPOLOGY LOCKED" not in p_fv)
check("D5  FIRST_VISION does NOT contain dream_micro literal text",
      "Layered lighting, complete furnishing composition, emotionally warm atmosphere." not in p_fv)
check("D6  FIRST_VISION still contains 'CAMERA LOCK' (full structural contract intact)",
      "CAMERA LOCK" in p_fv)
check("D7  FIRST_VISION still contains 'STRUCTURAL LOCK' (preservation intact)",
      "STRUCTURAL LOCK" in p_fv)
check("D8  FIRST_VISION contains 'equipment' from wow_directive",
      "equipment" in p_fv)

# FIRST_VISION non-DNA path: Japandi/home office has no registered room DNA
p_fv_nondna = compose_generation_prompt("Japandi · Harmony", "home office", room_desc, "", 1, [])
check("D9  FIRST_VISION non-DNA path also contains 'TRANSFORMATION AMBITION'",
      "TRANSFORMATION AMBITION" in p_fv_nondna)

# STYLE_REFINEMENT (Atmosphere Switch) — must remain unchanged from 4.3.0
p_sr = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "warmer", 2, history_v2)
check("D10 STYLE_REFINEMENT still contains 'TOPOLOGY LOCKED' (4.3.0 intact)",
      "TOPOLOGY LOCKED" in p_sr)
check("D11 STYLE_REFINEMENT still contains 'SAME APARTMENT — ATMOSPHERE SWITCH'",
      "SAME APARTMENT — ATMOSPHERE SWITCH" in p_sr)
check("D12 STYLE_REFINEMENT does NOT contain 'TRANSFORMATION AMBITION'",
      "TRANSFORMATION AMBITION" not in p_sr)
check("D13 STYLE_REFINEMENT does NOT contain 'spatial truth' (FV-only framing)",
      "spatial truth" not in p_sr)

# STYLE_REFINEMENT anchor path (Wave 4.3.0 anchor detection intact)
p_sr_anchor = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", anchor_desc, "warmer", 2, history_v2
)
check("D14 STYLE_REFINEMENT with anchors still detects 'ARCHITECTURAL ANCHORS'",
      "ARCHITECTURAL ANCHORS" in p_sr_anchor)

# STRUCTURAL_TRANSFORMATION — neither wow nor topology locked
p_st = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "open up the facade wall", 2, history_v2
)
check("D15 STRUCTURAL_TRANSFORMATION does NOT contain 'TRANSFORMATION AMBITION'",
      "TRANSFORMATION AMBITION" not in p_st)
check("D16 STRUCTURAL_TRANSFORMATION does NOT contain 'TOPOLOGY LOCKED'",
      "TOPOLOGY LOCKED" not in p_st)


# ── Suite E: Budget compliance ─────────────────────────────────────────────────
print("\n=== Suite E: Budget compliance ===")

p_fv_j   = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "", 1, [])
p_fv_sl  = compose_generation_prompt("Soft Luxury · Gold", "living room", room_desc, "", 1, [])
p_fv_zr  = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc, "", 1, [])
p_fv_dev = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "", 1, [], compact_prompts=True)
p_sr_j   = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "warmer", 2, history_v2)
p_sr_anc = compose_generation_prompt("Japandi · Harmony", "living room", anchor_desc, "warmer", 2, history_v2)
p_st_j   = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "open up the facade", 2, history_v2)
p_le_j   = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "add a floor lamp", 2, history_v2)

check(f"E1  FIRST_VISION (Japandi DNA) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_j) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_j)}")
check(f"E2  FIRST_VISION (Soft Luxury DNA) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_sl) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_sl)}")
check(f"E3  FIRST_VISION (Zen non-DNA) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_zr) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_zr)}")
check("E4  FIRST_VISION compact (DEV) does NOT contain 'TRANSFORMATION AMBITION'",
      "TRANSFORMATION AMBITION" not in p_fv_dev)
check(f"E5  STYLE_REFINEMENT (plain room) within budget ({_MODE_BUDGETS['STYLE_REFINEMENT']})",
      len(p_sr_j) <= _MODE_BUDGETS["STYLE_REFINEMENT"], f"got {len(p_sr_j)}")
check(f"E6  STYLE_REFINEMENT (anchor room) within budget ({_MODE_BUDGETS['STYLE_REFINEMENT']})",
      len(p_sr_anc) <= _MODE_BUDGETS["STYLE_REFINEMENT"], f"got {len(p_sr_anc)}")
check(f"E7  STRUCTURAL_TRANSFORMATION within budget ({_MODE_BUDGETS['STRUCTURAL_TRANSFORMATION']})",
      len(p_st_j) <= _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"], f"got {len(p_st_j)}")
check("E8  All modes under 4000-char hard limit",
      all(len(p) < 4000 for p in [p_fv_j, p_fv_sl, p_fv_zr, p_sr_j, p_sr_anc, p_st_j, p_le_j]))


# ── Suite F: Regression — Wave 4.3.0 and frozen modules ──────────────────────
print("\n=== Suite F: Regression (frozen modules + 4.3.0 preservation) ===")

# 4.3.0 preservation intelligence still intact
from prompt_engine.anchor_detector import detect_anchors
from prompt_engine.preservation import (
    build_atmosphere_switch_contract,
    build_structural_contract,
    build_continuation_contract,
    build_structural_evolution_contract,
)

ap = detect_anchors("Open-plan living room with black glass partition and balcony door.")
check("F1  detect_anchors still finds anchors in benchmark description",
      len(ap.anchors) > 0)
check("F2  detect_anchors clause still within 185-char cap",
      len(ap.clause) <= 185)

c_atm = build_atmosphere_switch_contract("living room")
check("F3  build_atmosphere_switch_contract still has 'TOPOLOGY LOCKED'",
      "TOPOLOGY LOCKED" in c_atm)
check("F4  build_atmosphere_switch_contract still has 'SAME APARTMENT'",
      "SAME APARTMENT" in c_atm)

check("F5  build_structural_contract still has 'CAMERA LOCK' (Tier 1 intact)",
      "CAMERA LOCK" in build_structural_contract("living room"))
check("F6  build_continuation_contract still callable (Tier 3 not removed)",
      callable(build_continuation_contract))
check("F7  build_structural_evolution_contract still callable",
      callable(build_structural_evolution_contract))

# STYLE_REFINEMENT path unchanged (4.3.0 keys preserved in _SECTION_PRIORITY)
check("F8  'atmosphere_contract': 1 still in composer _SECTION_PRIORITY",
      '"atmosphere_contract": 1' in comp_src)
check("F9  STYLE_REFINEMENT uses build_atmosphere_switch_contract (not continuation)",
      "build_atmosphere_switch_contract(room_type" in comp_src)

# Frozen modules
from generation_profiles import _PROFILES
p_dev  = _PROFILES["dev"]
p_prod = _PROFILES["prod"]
check("F10 DEV compact_prompts=True unchanged", p_dev.compact_prompts is True)
check("F11 PROD compact_prompts=False unchanged", p_prod.compact_prompts is False)
check("F12 DEV max_attempts=1 unchanged", p_dev.max_attempts == 1)
check("F13 PROD max_attempts=3 unchanged", p_prod.max_attempts == 3)

from retry_classifier import classify_for_retry, RetryDecision
check("F14 retry_classifier still importable", callable(classify_for_retry))

from prompt_engine.intent_classifier import classify_intent, ConversationIntent
check("F15 'go ahead' still -> GENERATE (intent classifier frozen)",
      classify_intent("go ahead", 2).intent == ConversationIntent.GENERATE)
check("F16 'generate' still -> GENERATE",
      classify_intent("generate", 2).intent == ConversationIntent.GENERATE)
check("F17 iteration 1 still always GENERATE",
      classify_intent("what do you think?", 1).intent == ConversationIntent.GENERATE)

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
  FIRST VISION REBALANCING (Wave 4.3.1):

  Dimension               | Before 4.3.1        | After 4.3.1
  ------------------------|---------------------|------------------------
  Task header             | "Redesign this..."  | "REDESIGN — ... Preserve structure; reimagine..."
  Dream layer (DNA path)  | dream_micro (78ch)  | wow_directive (~252ch)
  Dream layer (non-DNA)   | (absent)            | wow_directive (~252ch)
  Transformation signal   | Implicit            | Explicit: editorial, not safe
  Equipment preservation  | None                | "Carry forward distinctive furniture/equipment"
  STYLE_REFINEMENT path   | unchanged           | unchanged (4.3.0 intact)
  TOPOLOGY LOCKED         | FIRST_VISION: NO    | FIRST_VISION: still NO

  MANUAL VALIDATION REQUIRED:
  [MANUAL] PROD smoke: Before/After WOW with "Japandi" on a well-furnished apartment
           Check: editorial transformation, not safe/generic, equipment preserved
  [MANUAL] PROD smoke: Atmosphere switch (STYLE_REFINEMENT) on benchmark apartment
           Check: same apartment identity, only atmosphere changed (4.3.0 still working)
""")
