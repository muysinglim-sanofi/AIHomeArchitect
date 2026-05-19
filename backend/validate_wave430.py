"""
Wave 4.3.0 validation suite — Preservation Intelligence.

Suites:
  A — AnchorProfile / detect_anchors unit tests
  B — Atmosphere switch contract structure (Tier 3.5)
  C — Composer integration: STYLE_REFINEMENT path wiring (source inspection)
  D — Use-case differentiation: FIRST_VISION not weakened; other paths unchanged
  E — Budget compliance: no path exceeds mode budget
  F — Regression: frozen modules, profiles, retry, intent classification intact
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


# ── Suite A: detect_anchors unit tests ───────────────────────────────────────
print("\n=== Suite A: detect_anchors unit tests ===")

from prompt_engine.anchor_detector import detect_anchors, AnchorProfile

# Empty / generic room — no anchors expected
ap = detect_anchors("")
check("A1  empty description -> no anchors", len(ap.anchors) == 0)
check("A2  empty description -> empty clause", ap.clause == "")

ap = detect_anchors("A plain room with white walls and a sofa.")
check("A3  generic room -> no anchors detected", len(ap.anchors) == 0)
check("A4  generic room -> empty clause", ap.clause == "")

# Glass partition detection
ap = detect_anchors("Living room with a black glass partition separating the office zone.")
check("A5  'black glass partition' -> anchors detected", len(ap.anchors) > 0)
check("A6  'black glass' label present in anchors", any("black glass" in a for a in ap.anchors))
check("A7  clause contains 'ARCHITECTURAL ANCHORS'", "ARCHITECTURAL ANCHORS" in ap.clause)
check("A8  clause contains 'LOCKED'", "LOCKED" in ap.clause)

# Multi-zone detection
ap = detect_anchors("Open-plan living-dining space with visible kitchen connection.")
check("A9  'open-plan' -> multi-zone anchor detected", len(ap.anchors) > 0)
check("A10 multi-zone anchor appears in clause", ap.clause != "")

# Spatial depth detection
ap = detect_anchors("Wide room with diagonal depth, long perspective, layered zones.")
check("A11 'diagonal depth' -> depth anchor detected", len(ap.anchors) > 0)

# Distinctive opening detection
ap = detect_anchors("Living room with floor-to-ceiling window and balcony door access.")
check("A12 'floor-to-ceiling window' -> opening anchor detected", len(ap.anchors) > 0)
check("A13 'balcony door' -> opening anchor detected",
      any("balcony" in a for a in ap.anchors))

# Structural element detection
ap = detect_anchors("Industrial loft with exposed concrete beams and spiral staircase.")
check("A14 'exposed concrete' -> structural anchor detected", len(ap.anchors) > 0)
check("A15 'spiral staircase' -> structural anchor detected",
      any("spiral" in a for a in ap.anchors))

# Benchmark apartment (known stress test)
benchmark_desc = (
    "Open-plan living room, black glass partition separating the home office zone, "
    "balcony door access on the left, diagonal spatial depth with visible connected zones."
)
ap = detect_anchors(benchmark_desc)
check("A16 benchmark apartment -> anchors detected", len(ap.anchors) >= 2)
check("A17 benchmark -> clause non-empty", ap.clause != "")
check("A18 benchmark -> clause within budget cap (185 chars)", len(ap.clause) <= 185)
check("A19 benchmark -> anchor count capped at 4", len(ap.anchors) <= 4)
check("A20 AnchorProfile is frozen dataclass",
      hasattr(AnchorProfile, "__dataclass_params__") and AnchorProfile.__dataclass_params__.frozen)

# Clause always within hard cap
for desc in [
    "glass partition; open-plan; diagonal depth; balcony door; spiral staircase; mezzanine; exposed brick",
    "black glass partition, double-height space, floor-to-ceiling window, exposed concrete beam, archway",
]:
    ap = detect_anchors(desc)
    if ap.clause:
        check(f"A21 clause <= 185 chars for [{desc[:40]}...]",
              len(ap.clause) <= 185, f"got {len(ap.clause)}")


# ── Suite B: Atmosphere switch contract structure ─────────────────────────────
print("\n=== Suite B: Atmosphere switch contract (Tier 3.5) ===")

from prompt_engine.preservation import build_atmosphere_switch_contract, build_continuation_contract

c_no_anchor = build_atmosphere_switch_contract("")
c_living    = build_atmosphere_switch_contract("living room")
c_anchor    = build_atmosphere_switch_contract(
    "living room",
    "ARCHITECTURAL ANCHORS — LOCKED: black glass; open-plan. Preserve these unchanged in the output."
)
c_old       = build_continuation_contract("living room")  # Tier 3 still exists (not removed)

check("B1  'SAME APARTMENT' present in atmosphere_switch_contract",
      "SAME APARTMENT" in c_no_anchor)
check("B2  'DO NOT generate a new apartment' present",
      "DO NOT generate a new apartment" in c_no_anchor)
check("B3  'TOPOLOGY LOCKED' present",
      "TOPOLOGY LOCKED" in c_no_anchor)
check("B4  'zone count' present",
      "zone count" in c_no_anchor)
check("B5  'spatial openness' present",
      "spatial openness" in c_no_anchor)
check("B6  'multi-zone visibility' present",
      "multi-zone visibility" in c_no_anchor)
check("B7  'depth relationships' present",
      "depth relationships" in c_no_anchor)
check("B8  'Do not collapse multi-zone' present",
      "Do not collapse multi-zone" in c_no_anchor)
check("B9  'Do not flatten spatial depth' present",
      "Do not flatten spatial depth" in c_no_anchor)
check("B10 'ATMOSPHERE BOUNDARY' present (compact boundary)",
      "ATMOSPHERE BOUNDARY" in c_no_anchor)
check("B11 'Topology > camera > atmosphere' priority present",
      "Topology > camera > atmosphere" in c_no_anchor)
check("B12 ROOM LOCK included when room_type provided",
      "ROOM LOCK" in c_living)
check("B13 anchor clause injected when provided",
      "ARCHITECTURAL ANCHORS" in c_anchor)
check("B14 anchor clause absent when not provided",
      "ARCHITECTURAL ANCHORS" not in c_no_anchor)
check("B15 atmosphere_switch_contract > continuation_contract (stronger, more text)",
      len(c_no_anchor) > len(c_old),
      f"switch={len(c_no_anchor)}  continuation={len(c_old)}")
check("B16 build_continuation_contract still callable (not removed)",
      callable(build_continuation_contract))
check("B17 contract with anchor within budget envelope (< 1000 chars)",
      len(c_anchor) < 1000, f"got {len(c_anchor)}")


# ── Suite C: Composer integration — source inspection ─────────────────────────
print("\n=== Suite C: Composer integration (source inspection) ===")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()

check("C1  detect_anchors imported in composer",
      "from .anchor_detector import detect_anchors" in comp_src)
check("C2  build_atmosphere_switch_contract imported in composer",
      "build_atmosphere_switch_contract" in comp_src)
check("C3  'atmosphere_contract' section key present",
      '"atmosphere_contract"' in comp_src)
check("C4  atmosphere_contract is P1 in _SECTION_PRIORITY",
      '"atmosphere_contract": 1' in comp_src)
check("C5  STYLE_REFINEMENT path calls detect_anchors",
      "detect_anchors(room_description)" in comp_src)
check("C6  STYLE_REFINEMENT path calls build_atmosphere_switch_contract",
      "build_atmosphere_switch_contract(room_type" in comp_src)
check("C7  anchor_profile.clause passed to contract builder",
      "anchor_profile.clause" in comp_src)
check("C8  AnchorDetect log emitted when anchors found",
      "[AnchorDetect]" in comp_src)
check("C9  continuation_contract NOT used in STYLE_REFINEMENT path",
      # continuation_contract still in _SECTION_PRIORITY (as legacy key) but not
      # used as a section tuple in the STYLE_REFINEMENT raw_sections
      '("atmosphere_contract", contract)' in comp_src)
check("C10 Wave 4.3.0 comment present in composer",
      "Wave 4.3.0" in comp_src)
check("C11 FIRST_VISION path uses a structural contract (Tier 1 or Tier 1.5 — Wave 4.5.0 uses simplified)",
      "build_structural_contract(room_type)" in comp_src or "build_simplified_fv_contract(room_type)" in comp_src)
check("C12 STRUCTURAL_TRANSFORMATION still uses build_structural_evolution_contract",
      "build_structural_evolution_contract(room_type)" in comp_src)


# ── Suite D: Use-case differentiation ─────────────────────────────────────────
print("\n=== Suite D: Use-case differentiation ===")

logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS
logging.disable(logging.CRITICAL)

room_desc = "Open-plan living room, natural light from west-facing windows, oak floors, high ceilings."
anchor_desc = (
    "Open-plan living room, black glass partition separating home office, "
    "balcony door access on left, diagonal depth, visible connected zones."
)
history_v2 = [
    {"role": "user", "content": "I want Japandi style"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer"},
]

# FIRST_VISION (Before/After WOW) — must contain full structural contract vocabulary
p_fv = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "", 1, [])
check("D1  FIRST_VISION contains CAMERA LOCK", "CAMERA LOCK" in p_fv)
check("D2  FIRST_VISION contains STRUCTURAL LOCK", "STRUCTURAL LOCK" in p_fv)
check("D3  FIRST_VISION contains TRANSFORMATION_SCOPE (CHANGE ONLY)",
      "CHANGE ONLY" in p_fv)
check("D4  FIRST_VISION contains full ATMOSPHERE BOUNDARY priority order",
      "applied last" in p_fv)
check("D5  FIRST_VISION does NOT contain 'TOPOLOGY LOCKED' (not overconstrained)",
      "TOPOLOGY LOCKED" not in p_fv)
# Wave 4.7.1 R1 superseded the original 4.3.0 invariant. The 4.3.0 design kept
# anchors STYLE_REFINEMENT-only, leaving V1 LESS spatially anchored than V2 — the
# 4.7.1 audit identified that asymmetry as the dominant structural-fidelity-variance
# cause. R1 now injects the same deterministic detect_anchors() clause into
# FIRST_VISION when the description carries structural cues. Anchors are
# descriptive-only (not a topology lock) so D5 ("no TOPOLOGY LOCKED") still holds —
# FIRST_VISION is strengthened, not overconstrained.
check("D6  FIRST_VISION WITH structural desc now contains 'ARCHITECTURAL ANCHORS' (Wave 4.7.1 R1 — V1/V2 anchor parity)",
      "ARCHITECTURAL ANCHORS" in p_fv)
p_fv_generic = compose_generation_prompt("Japandi · Harmony", "living room", "", "", 1, [])
check("D6b FIRST_VISION with empty desc adds NO anchors (graceful — no inflation on plain rooms)",
      "ARCHITECTURAL ANCHORS" not in p_fv_generic)

# STYLE_REFINEMENT (Atmosphere Switch) — must use atmosphere_switch_contract
p_sr = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "warmer", 2, history_v2)
check("D7  STYLE_REFINEMENT contains TOPOLOGY LOCKED",
      "TOPOLOGY LOCKED" in p_sr)
check("D8  STYLE_REFINEMENT contains 'SAME APARTMENT — ATMOSPHERE SWITCH'",
      "SAME APARTMENT — ATMOSPHERE SWITCH" in p_sr)
check("D9  STYLE_REFINEMENT contains 'DO NOT generate a new apartment'",
      "DO NOT generate a new apartment" in p_sr)
check("D10 STYLE_REFINEMENT contains 'zone count'", "zone count" in p_sr)
check("D11 STYLE_REFINEMENT contains 'Do not collapse multi-zone'",
      "Do not collapse multi-zone" in p_sr)

# STYLE_REFINEMENT with anchor-rich description — anchors appear in prompt
p_sr_anchor = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", anchor_desc, "warmer", 2, history_v2
)
check("D12 STYLE_REFINEMENT with anchor room_desc contains ARCHITECTURAL ANCHORS",
      "ARCHITECTURAL ANCHORS" in p_sr_anchor)
check("D13 anchor clause names detected features",
      any(kw in p_sr_anchor for kw in ["black glass", "open-plan", "balcony", "diagonal"]))

# STRUCTURAL_TRANSFORMATION (AI companion — architectural creativity allowed)
p_st = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "open up the facade wall", 2, history_v2
)
check("D14 STRUCTURAL_TRANSFORMATION does NOT contain 'TOPOLOGY LOCKED'",
      "TOPOLOGY LOCKED" not in p_st)
check("D15 STRUCTURAL_TRANSFORMATION does NOT contain 'ARCHITECTURAL ANCHORS'",
      "ARCHITECTURAL ANCHORS" not in p_st)
check("D16 STRUCTURAL_TRANSFORMATION contains ARCHITECTURAL INTENT",
      "ARCHITECTURAL INTENT" in p_st)

# LOCAL_EDIT (AI companion — surgical object creativity allowed)
p_le = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "add a floor lamp", 2, history_v2
)
check("D17 LOCAL_EDIT does NOT contain 'TOPOLOGY LOCKED'",
      "TOPOLOGY LOCKED" not in p_le)
check("D18 LOCAL_EDIT does NOT contain 'ARCHITECTURAL ANCHORS'",
      "ARCHITECTURAL ANCHORS" not in p_le)
check("D19 LOCAL_EDIT contains 'TARGETED IMAGE EDIT'",
      "TARGETED IMAGE EDIT" in p_le)


# ── Suite E: Budget compliance ─────────────────────────────────────────────────
print("\n=== Suite E: Budget compliance ===")

# All existing budget tests (replicated from wave427 D1-D6 with new implementation)
p_fv_j = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "", 1, [])
p_fv_z = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc, "", 1, [])
p_sr_j = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "warmer", 2, history_v2)
p_sr_anchor_full = compose_generation_prompt(
    "Japandi · Harmony", "living room", anchor_desc, "warmer", 2, history_v2
)
p_st_j = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "open up the facade", 2, history_v2
)
p_le_j = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "add floor lamp", 2, history_v2
)

check(f"E1  FIRST_VISION (Japandi) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_j) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_j)}")
check(f"E2  FIRST_VISION (Zen) within budget ({_MODE_BUDGETS['FIRST_VISION']})",
      len(p_fv_z) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_fv_z)}")
check(f"E3  STYLE_REFINEMENT (plain room) within budget ({_MODE_BUDGETS['STYLE_REFINEMENT']})",
      len(p_sr_j) <= _MODE_BUDGETS["STYLE_REFINEMENT"], f"got {len(p_sr_j)}")
check(f"E4  STYLE_REFINEMENT (anchor room) within budget ({_MODE_BUDGETS['STYLE_REFINEMENT']})",
      len(p_sr_anchor_full) <= _MODE_BUDGETS["STYLE_REFINEMENT"], f"got {len(p_sr_anchor_full)}")
check(f"E5  STRUCTURAL_TRANSFORMATION within budget ({_MODE_BUDGETS['STRUCTURAL_TRANSFORMATION']})",
      len(p_st_j) <= _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"], f"got {len(p_st_j)}")
check(f"E6  LOCAL_EDIT within budget ({_MODE_BUDGETS['LOCAL_EDIT']})",
      len(p_le_j) <= _MODE_BUDGETS["LOCAL_EDIT"], f"got {len(p_le_j)}")
check("E7  All modes under 4000-char hard limit",
      all(len(p) < 4000 for p in [p_fv_j, p_fv_z, p_sr_j, p_sr_anchor_full, p_st_j, p_le_j]))
check("E8  Anchor detection adds no cost when room is generic (no anchors)",
      len(p_sr_j) <= _MODE_BUDGETS["STYLE_REFINEMENT"], f"got {len(p_sr_j)}")


# ── Suite F: Regression — frozen modules intact ───────────────────────────────
print("\n=== Suite F: Regression (frozen modules) ===")

# Verify no frozen modules were modified unexpectedly
with open("prompt_engine/composer.py", encoding="utf-8") as f:
    c = f.read()
check("F1  _MODE_BUDGETS still present in composer", "_MODE_BUDGETS" in c)
check("F2  _design_intelligence_block still present", "_design_intelligence_block" in c)
check("F3  compose_generation_prompt still present", "def compose_generation_prompt" in c)
check("F4  FIRST_VISION path still has full_contract P1 section",
      '"full_contract"' in c)
check("F5  continuation_contract still in _SECTION_PRIORITY (not removed)",
      '"continuation_contract": 1' in c)

from generation_profiles import get_active_profile, _PROFILES
p_dev  = _PROFILES["dev"]
p_prod = _PROFILES["prod"]
check("F6  DEV profile max_attempts=1 unchanged", p_dev.max_attempts == 1)
check("F7  PROD profile max_attempts=3 unchanged", p_prod.max_attempts == 3)
check("F8  DEV compact_prompts=True unchanged", p_dev.compact_prompts is True)
check("F9  PROD compact_prompts=False unchanged", p_prod.compact_prompts is False)

from retry_classifier import classify_for_retry, RetryVerdict, RetryDecision
check("F10 retry_classifier still importable", callable(classify_for_retry))
check("F11 RetryVerdict.TRANSIENT still present", RetryVerdict.TRANSIENT.value == "TRANSIENT")
check("F12 RetryDecision still frozen", RetryDecision.__dataclass_params__.frozen)

from prompt_engine.intent_classifier import classify_intent, ConversationIntent
check("F13 intent_classifier still importable", callable(classify_intent))
check("F14 'go ahead' still -> GENERATE on iteration 2",
      classify_intent("go ahead", 2).intent == ConversationIntent.GENERATE)
check("F15 iteration 1 still always GENERATE",
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
  PRESERVATION HIERARCHY (Wave 4.3.0):

  Use Case               | Contract         | Topology | Anchors | Creativity
  -----------------------|------------------|----------|---------|----------
  Before/After WOW       | Tier 1 (full)    | Camera   | None    | Full transform
  Atmosphere Switch (SR) | Tier 3.5 (atm.)  | LOCKED   | LOCKED  | Atm. only
  AI Companion Struct.   | Tier 2 (evol.)   | Camera   | None    | Arch. changes
  AI Companion Local     | Edit block       | Camera   | None    | Object edits

  MANUAL VALIDATION REQUIRED:
  [MANUAL] Run PROD smoke: atmosphere switch on benchmark apartment
           (black glass partition, multi-zone, balcony door, diagonal depth)
           Check: same partition visible, same spatial openness, only atmosphere changed
  [MANUAL] Run PROD smoke: Before/After WOW on same apartment
           Check: still transformative — not overconstrained
""")
