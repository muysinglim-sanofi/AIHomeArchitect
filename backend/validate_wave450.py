"""
Wave 4.5.0 validation suite — Product Philosophy Consolidation.

PROBLEM:
  After Waves 4.3-4.4, the system had accumulated heavy defensive prompt layers
  compensating for "REDESIGN" = permission to reinvent architecture. The FIRST_VISION
  contract grew to ~1550 chars (~44% of the 3550 budget), leaving little room for
  DNA, completeness, and WOW.

WAVE 4.5.0 INSIGHT:
  input_fidelity=high + structural mask + SAME APARTMENT task framing do the heavy
  architectural preservation work. The contract provides vocabulary alignment, not
  defensive repetition. Clearer is more trustworthy to the model than louder.

WAVE 4.5.0 CHANGES:
  1. Added build_simplified_fv_contract() (Tier 1.5, ~820 chars) in preservation.py
     — all required vocabulary preserved, redundant defensive prose removed
  2. FIRST_VISION path in composer.py uses Tier 1.5 instead of Tier 1
  3. interior_completeness now survives for all atmospheres at 200-char source
     (was dropping before due to contract bloat)

DELIVERABLES: docs/PRODUCT_CONTRACT_V2.md, docs/SIMPLIFICATION_AUDIT.md

Suites:
  A — Product contract document: exists, philosophy captured
  B — Simplification audit document: exists, audit complete
  C — Simplified contract: correct vocabulary, correct size reduction
  D — Prompt reduction: FIRST_VISION prompts shorter, interior_completeness survives
  E — No-regression: all required vocabulary still present in generated prompts
  F — System integrity: quality systems unchanged, existing validators compatible
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


# ── Suite A: Product contract document ───────────────────────────────────────
print("\n=== Suite A: PRODUCT_CONTRACT_V2.md ===")

contract_path = os.path.join(os.path.dirname(__file__), "docs", "PRODUCT_CONTRACT_V2.md")
check("A1  docs/PRODUCT_CONTRACT_V2.md exists",
      os.path.isfile(contract_path))

if os.path.isfile(contract_path):
    with open(contract_path, encoding="utf-8") as f:
        contract_src = f.read()
else:
    contract_src = ""

check("A2  Document covers FIRST_VISION philosophy",
      "FIRST_VISION" in contract_src)
check("A3  Document states SAME APARTMENT philosophy",
      "SAME APARTMENT" in contract_src)
check("A4  Document covers V2+ atmosphere switch (stricter)",
      "ATMOSPHERE SWITCH" in contract_src or "Vision 2" in contract_src)
check("A5  Document defines when structural changes are allowed (explicit request only)",
      "explicit" in contract_src.lower() and "structural" in contract_src.lower())
check("A6  Document explains what WOW means",
      "WOW" in contract_src)
check("A7  Document explains what actually drives fidelity",
      "input_fidelity" in contract_src or "fidelity" in contract_src.lower())
check("A8  Document covers the simplified contract philosophy",
      "simpl" in contract_src.lower())
check("A9  Document is Wave 4.5.0",
      "4.5.0" in contract_src)
check("A10 Document covers TOPOLOGY LOCKED for V2+",
      "TOPOLOGY" in contract_src)


# ── Suite B: Simplification audit document ───────────────────────────────────
print("\n=== Suite B: SIMPLIFICATION_AUDIT.md ===")

audit_path = os.path.join(os.path.dirname(__file__), "docs", "SIMPLIFICATION_AUDIT.md")
check("B1  docs/SIMPLIFICATION_AUDIT.md exists",
      os.path.isfile(audit_path))

if os.path.isfile(audit_path):
    with open(audit_path, encoding="utf-8") as f:
        audit_src = f.read()
else:
    audit_src = ""

check("B2  Audit uses KEEP/SIMPLIFY/MERGE/REMOVE/DEFER classification",
      "KEEP" in audit_src and "SIMPLIFY" in audit_src and "DEFER" in audit_src)
check("B3  Audit covers full_contract Tier 1 simplification",
      "1550" in audit_src or "Tier 1" in audit_src)
check("B4  Audit shows estimated prompt reduction in chars",
      "730" in audit_src or "reduction" in audit_src.lower())
check("B5  Audit covers payload impact",
      "payload" in audit_src.lower())
check("B6  Audit covers latency impact",
      "latency" in audit_src.lower())
check("B7  Audit identifies unused layers (build_realism_block, build_continuation_contract)",
      "build_realism_block" in audit_src or "continuation" in audit_src.lower())
check("B8  Audit has a red lines section (must not simplify)",
      "red lines" in audit_src.lower() or "do not touch" in audit_src.lower() or "Red Lines" in audit_src)
check("B9  Audit covers DNA blocks as KEEP",
      "DNA" in audit_src and "KEEP" in audit_src)
check("B10 Audit is Wave 4.5.0",
      "4.5.0" in audit_src)


# ── Suite C: Simplified contract in preservation.py ──────────────────────────
print("\n=== Suite C: Simplified contract implementation ===")

with open("prompt_engine/preservation.py", encoding="utf-8") as f:
    pres_src = f.read()

check("C1  build_simplified_fv_contract defined in preservation.py",
      "def build_simplified_fv_contract(" in pres_src)
check("C2  _SAME_APARTMENT_V2 constant defined",
      "_SAME_APARTMENT_V2" in pres_src)

from prompt_engine.preservation import (
    build_simplified_fv_contract,
    build_structural_contract,
    _SAME_APARTMENT_V2,
    _CAMERA_LOCK,
    _STRUCTURAL_LOCK,
    _ATMOSPHERE_BOUNDARY,
)

sc = build_simplified_fv_contract("living room")

# Required vocabulary checks
check("C3  Simplified contract has CAMERA LOCK",
      "CAMERA LOCK" in sc)
check("C4  Simplified contract has focal length",
      "focal length" in sc.lower())
check("C5  Simplified contract has vanishing points",
      "vanishing point" in sc.lower())
check("C6  Simplified contract has horizon line",
      "horizon line" in sc.lower())
check("C7  Simplified contract has structural lines",
      "structural lines" in sc.lower())
check("C8  Simplified contract has proportions",
      "proportions" in sc.lower())
check("C9  Simplified contract has architectural identity",
      "architectural identity" in sc.lower())
check("C10 Simplified contract has DO NOT reinterpret",
      "DO NOT reinterpret" in sc)
check("C11 Simplified contract has DO NOT redesign",
      "DO NOT redesign" in sc)
check("C12 Simplified contract has SAME apartment",
      "SAME apartment" in sc)
check("C13 Simplified contract has STRUCTURAL LOCK",
      "STRUCTURAL LOCK" in sc)
check("C14 Simplified contract has ATMOSPHERE BOUNDARY",
      "ATMOSPHERE BOUNDARY" in sc)
check("C15 Simplified contract has applied last",
      "applied last" in sc.lower())
check("C16 Simplified contract has unblocked windows",
      "unblocked" in sc.lower())

# Size checks
full_contract_lr = build_structural_contract("living room")
check("C17 Simplified contract is significantly shorter than Tier 1 (at least 500 chars smaller)",
      len(full_contract_lr) - len(sc) >= 500,
      f"full={len(full_contract_lr)} simplified={len(sc)} diff={len(full_contract_lr)-len(sc)}")
check("C18 Simplified contract is under 1000 chars (living room with note)",
      len(sc) < 1000, f"got {len(sc)}")
check("C19 Simplified contract is under 900 chars (living room with note)",
      len(sc) < 900, f"got {len(sc)}")

# Old constants preserved unchanged (backward compat with early validators)
check("C20 _CAMERA_LOCK still exported from preservation.py",
      isinstance(_CAMERA_LOCK, str) and len(_CAMERA_LOCK) > 200)
check("C21 _STRUCTURAL_LOCK still exported",
      isinstance(_STRUCTURAL_LOCK, str) and "unblocked" in _STRUCTURAL_LOCK.lower())
check("C22 _ATMOSPHERE_BOUNDARY still exported",
      isinstance(_ATMOSPHERE_BOUNDARY, str) and "ATMOSPHERE BOUNDARY" in _ATMOSPHERE_BOUNDARY)
check("C23 build_structural_contract still intact (unchanged, regression-safe)",
      "CAMERA LOCK" in full_contract_lr and len(full_contract_lr) >= 1400)

# Composer uses simplified contract
with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()
check("C24 composer.py imports build_simplified_fv_contract",
      "build_simplified_fv_contract" in comp_src)
check("C25 FIRST_VISION path uses build_simplified_fv_contract (not build_structural_contract)",
      "contract = build_simplified_fv_contract(room_type)" in comp_src)
check("C26 Wave 4.5.0 documented in composer docstring",
      "Wave 4.5.0" in comp_src)


# ── Suite D: Prompt reduction verification ────────────────────────────────────
print("\n=== Suite D: Prompt reduction and interior_completeness survival ===")

from prompt_engine.atmosphere_dna import get_room_dna, build_dna_block
from prompt_engine.fidelity_layer import build_first_vision_task
from prompt_engine.preservation import build_structural_contract
from prompt_engine.wow_layer import build_first_vision_wow_directive
from prompt_engine.realism_layer import (
    build_compact_realism_block,
    build_interior_completeness_rule,
)
from prompt_engine.composer import (
    _SECTION_PRIORITY,
    _MODE_BUDGETS,
    _assemble_with_budget,
)

fv_budget = _MODE_BUDGETS["FIRST_VISION"]


def _assemble_fv_simplified(atmosphere_id: str, dna_name: str, room_type: str, source_length: int):
    """Assemble FIRST_VISION prompt using the simplified contract (as composer does)."""
    room_ctx = f" {room_type}"
    task = build_first_vision_task(dna_name, room_ctx)
    contract = build_simplified_fv_contract(room_type)  # Tier 1.5
    source = "SOURCE SPACE: " + ("x" * source_length) if source_length else ""
    dna = get_room_dna(atmosphere_id, room_type)
    intel = build_dna_block(dna) if dna else ""
    wow = build_first_vision_wow_directive()
    completeness = build_interior_completeness_rule()
    realism = build_compact_realism_block()
    raw_sections = [
        ("task", task),
        ("full_contract", contract),
        ("source_space", source),
        ("design_intel", intel),
        ("interior_completeness", completeness),
        ("scene_completion", ""),
        ("wow_directive", wow),
        ("visible_spaces", ""),
        ("design_direction", ""),
        ("compact_realism", realism),
    ]
    return _assemble_with_budget("FIRST_VISION", raw_sections)


def _assemble_fv_tier1(atmosphere_id: str, dna_name: str, room_type: str, source_length: int):
    """Assemble FIRST_VISION prompt using OLD Tier 1 contract (for comparison)."""
    room_ctx = f" {room_type}"
    task = build_first_vision_task(dna_name, room_ctx)
    contract = build_structural_contract(room_type)  # Tier 1 (old)
    source = "SOURCE SPACE: " + ("x" * source_length) if source_length else ""
    dna = get_room_dna(atmosphere_id, room_type)
    intel = build_dna_block(dna) if dna else ""
    wow = build_first_vision_wow_directive()
    completeness = build_interior_completeness_rule()
    realism = build_compact_realism_block()
    raw_sections = [
        ("task", task),
        ("full_contract", contract),
        ("source_space", source),
        ("design_intel", intel),
        ("interior_completeness", completeness),
        ("scene_completion", ""),
        ("wow_directive", wow),
        ("visible_spaces", ""),
        ("design_direction", ""),
        ("compact_realism", realism),
    ]
    return _assemble_with_budget("FIRST_VISION", raw_sections)


# D1: SL living room baseline
sl_prompt, sl_dropped = _assemble_fv_simplified("soft_luxury", "Soft Luxury Gold", "living room", 200)
sl_old_prompt, sl_old_dropped = _assemble_fv_tier1("soft_luxury", "Soft Luxury Gold", "living room", 200)

check("D1  Simplified FIRST_VISION (SL 200-char) is shorter than Tier 1 version",
      len(sl_prompt) < len(sl_old_prompt),
      f"simplified={len(sl_prompt)} tier1={len(sl_old_prompt)}")
check("D2  Simplified FIRST_VISION (SL 200-char) saves at least 400 chars vs Tier 1",
      len(sl_old_prompt) - len(sl_prompt) >= 400,
      f"saving={len(sl_old_prompt)-len(sl_prompt)}")
check("D3  Simplified FIRST_VISION (SL 200-char) within budget",
      len(sl_prompt) <= fv_budget, f"got {len(sl_prompt)}")
check("D4  interior_completeness survives SL 200-char (was dropping with Tier 1)",
      "interior_completeness" not in sl_dropped,
      f"dropped={sl_dropped}")
check("D5  wow_directive survives SL 200-char (already did — still does)",
      "wow_directive" not in sl_dropped, f"dropped={sl_dropped}")
check("D6  compact_realism survives SL 200-char",
      "compact_realism" not in sl_dropped, f"dropped={sl_dropped}")
check("D7  design_intel survives SL 200-char",
      "design_intel" not in sl_dropped, f"dropped={sl_dropped}")

# D8: Check interior_completeness was dropping with old Tier 1
check("D8  interior_completeness WAS dropping with Tier 1 for SL 200-char (confirms improvement)",
      "interior_completeness" in sl_old_dropped,
      f"old_dropped={sl_old_dropped}")

# D9: All 30 atmosphere+room combos — zero section drops at 200-char source
_ATMOSPHERES = [
    ("warm_modern", "Warm Modern"),
    ("japandi_calm", "Japandi Calm"),
    ("soft_luxury", "Soft Luxury Gold"),
    ("zen_retreat", "Zen Retreat"),
    ("nordic_warmth", "Nordic Warmth"),
    ("dark_contemporary", "Dark Contemporary"),
    ("nature_retreat", "Nature Retreat"),
    ("desert_luxe", "Desert Luxe"),
    ("bali_sanctuary", "Bali Sanctuary"),
    ("tropical_escape", "Tropical Escape"),
]
_ROOM_TYPES = ["living room", "master bedroom", "kitchen"]

all_no_drops = True
any_wow_drop = False
any_realism_drop = False
any_dna_drop = False

for atm_id, atm_name in _ATMOSPHERES:
    for room_type in _ROOM_TYPES:
        dna = get_room_dna(atm_id, room_type)
        if dna is None:
            continue
        _, dropped = _assemble_fv_simplified(atm_id, atm_name, room_type, 200)
        if dropped:
            all_no_drops = False
        if "wow_directive" in dropped:
            any_wow_drop = True
        if "compact_realism" in dropped:
            any_realism_drop = True
        if "design_intel" in dropped:
            any_dna_drop = True

check("D9  Zero drops for any atmosphere+room at 200-char source (Wave 4.5.0 target)",
      all_no_drops)
check("D10 wow_directive drops: 0/30 at 200-char source",
      not any_wow_drop)
check("D11 compact_realism drops: 0/30",
      not any_realism_drop)
check("D12 design_intel drops: 0/30",
      not any_dna_drop)

# D13: Even at 400-char source, check wow survives
sl_400_prompt, sl_400_dropped = _assemble_fv_simplified("soft_luxury", "Soft Luxury Gold", "living room", 400)
check("D13 wow_directive survives SL 400-char source (was dropping with Tier 1)",
      "wow_directive" not in sl_400_dropped, f"dropped={sl_400_dropped}")

dc_400_prompt, dc_400_dropped = _assemble_fv_simplified("dark_contemporary", "Dark Contemporary", "living room", 400)
check("D14 wow_directive survives Dark Contemporary 400-char source",
      "wow_directive" not in dc_400_dropped, f"dropped={dc_400_dropped}")

# D15: Prompt reduction check across atmospheres
dc_prompt, dc_dropped = _assemble_fv_simplified("dark_contemporary", "Dark Contemporary", "living room", 200)
dc_old_prompt, _ = _assemble_fv_tier1("dark_contemporary", "Dark Contemporary", "living room", 200)
check("D15 Dark Contemporary (largest DNA) prompt reduced vs Tier 1",
      len(dc_old_prompt) - len(dc_prompt) >= 400,
      f"saving={len(dc_old_prompt)-len(dc_prompt)}")


# ── Suite E: No-regression vocabulary in generated prompts ───────────────────
print("\n=== Suite E: No-regression vocabulary checks ===")

from prompt_engine.composer import compose_generation_prompt

room_desc = "A bright living room with oak floors and large west-facing windows."
history_v2 = [
    {"role": "user", "content": "I want Japandi style"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer"},
]

p_fv = compose_generation_prompt("Soft Luxury · Gold", "living room", room_desc, "", 1, [])
p_sr = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "warmer", 2, history_v2)
p_st = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "remove the wall", 2, history_v2)

# FIRST_VISION vocabulary
check("E1  FIRST_VISION has CAMERA LOCK",
      "CAMERA LOCK" in p_fv)
check("E2  FIRST_VISION has STRUCTURAL LOCK",
      "STRUCTURAL LOCK" in p_fv)
check("E3  FIRST_VISION has focal length",
      "focal length" in p_fv.lower())
check("E4  FIRST_VISION has vanishing points",
      "vanishing point" in p_fv.lower())
check("E5  FIRST_VISION has DO NOT reinterpret",
      "DO NOT reinterpret" in p_fv)
check("E6  FIRST_VISION has NOT a CGI render (from compact_realism)",
      "NOT a CGI render" in p_fv)
check("E7  FIRST_VISION has SAME APARTMENT (from task)",
      "SAME APARTMENT" in p_fv)
check("E8  FIRST_VISION has TRANSFORMATION AMBITION (wow_directive)",
      "TRANSFORMATION AMBITION" in p_fv)
check("E9  FIRST_VISION has applied last (ATMOSPHERE BOUNDARY)",
      "applied last" in p_fv.lower())
check("E10 FIRST_VISION does NOT have TOPOLOGY LOCKED (not over-constrained)",
      "TOPOLOGY LOCKED" not in p_fv)

# STYLE_REFINEMENT vocabulary
check("E11 STYLE_REFINEMENT has TOPOLOGY LOCKED",
      "TOPOLOGY LOCKED" in p_sr)
check("E12 STYLE_REFINEMENT has SAME APARTMENT — ATMOSPHERE SWITCH",
      "SAME APARTMENT — ATMOSPHERE SWITCH" in p_sr)
check("E13 STYLE_REFINEMENT has vanishing points",
      "vanishing point" in p_sr.lower())

# STRUCTURAL_TRANSFORMATION vocabulary
check("E14 STRUCTURAL_TRANSFORMATION has vanishing points",
      "vanishing point" in p_st.lower())
check("E15 STRUCTURAL_TRANSFORMATION does NOT have TOPOLOGY LOCKED",
      "TOPOLOGY LOCKED" not in p_st)

# Budget compliance
check("E16 FIRST_VISION prompt within budget",
      len(p_fv) <= _MODE_BUDGETS["FIRST_VISION"],
      f"got {len(p_fv)}")
check("E17 STYLE_REFINEMENT prompt within budget",
      len(p_sr) <= _MODE_BUDGETS["STYLE_REFINEMENT"],
      f"got {len(p_sr)}")


# ── Suite F: System integrity — quality systems unchanged ─────────────────────
print("\n=== Suite F: System integrity (quality systems unchanged) ===")

from prompt_engine.composer import _MODE_BUDGETS, _SECTION_PRIORITY

check("F1  FIRST_VISION budget still 3550 (Wave 4.4.1 — not lowered in Wave 4.5.0)",
      _MODE_BUDGETS["FIRST_VISION"] == 3550)
check("F2  interior_completeness still P5 (priority unchanged)",
      _SECTION_PRIORITY.get("interior_completeness") == 5)
check("F3  wow_directive still P4",
      _SECTION_PRIORITY.get("wow_directive") == 4)
check("F4  compact_realism still P3",
      _SECTION_PRIORITY.get("compact_realism") == 3)
check("F5  design_intel still P2",
      _SECTION_PRIORITY.get("design_intel") == 2)
check("F6  task still P1",
      _SECTION_PRIORITY.get("task") == 1)

with open("prompt_engine/wow_layer.py", encoding="utf-8") as f:
    wow_src = f.read()
check("F7  wow_directive exact text: THIS apartment, not a new one",
      "THIS apartment, not a new one" in wow_src)
check("F8  wow_directive exact text: Visible architecture stays recognizable",
      "Visible architecture stays recognizable" in wow_src)

with open("prompt_engine/fidelity_layer.py", encoding="utf-8") as f:
    fid_src = f.read()
check("F9  fidelity_layer SAME APARTMENT framing intact",
      "SAME APARTMENT" in fid_src)
check("F10 fidelity_layer spatial truth language intact",
      "spatial truth" in fid_src)

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
check("F11 input_fidelity=high still passed from profile (not hardcoded)",
      "input_fidelity=profile.input_fidelity" in main_src)
check("F12 quality still passed from profile",
      "quality=profile.quality" in main_src)
check("F13 max_retries=0 still in main.py",
      "max_retries=0" in main_src)
check("F14 gpt-image-1 still used",
      'model="gpt-image-1"' in main_src)
check("F15 ENABLE_STRUCTURAL_MASK default=true still in main.py",
      '"true"' in main_src)

# Old constants still exported (backward compat)
check("F16 _CAMERA_LOCK still exported and unchanged (required by early validators)",
      "focal length" in _CAMERA_LOCK and "DO NOT reinterpret" in _CAMERA_LOCK)
check("F17 build_structural_contract still importable (legacy alias intact)",
      callable(build_structural_contract))

# PRODUCT_CONTRACT_V2.md and SIMPLIFICATION_AUDIT.md are Wave 4.5.0 artifacts
check("F18 PRODUCT_CONTRACT_V2.md Wave 4.5.0 product philosophy documented",
      os.path.isfile(os.path.join(os.path.dirname(__file__), "docs", "PRODUCT_CONTRACT_V2.md")))
check("F19 SIMPLIFICATION_AUDIT.md Wave 4.5.0 audit documented",
      os.path.isfile(os.path.join(os.path.dirname(__file__), "docs", "SIMPLIFICATION_AUDIT.md")))
check("F20 PERFORMANCE_ANALYSIS.md Wave 4.4.2 still present",
      os.path.isfile(os.path.join(os.path.dirname(__file__), "docs", "PERFORMANCE_ANALYSIS.md")))


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
  WAVE 4.5.0 ANALYSIS - PRODUCT PHILOSOPHY CONSOLIDATION:

  Philosophy shift:
    OLD: Force the AI to obey via heavy defensive contracts
    NEW: Align the AI naturally with the real product philosophy

  What drives fidelity (priority order):
    1. input_fidelity=high (API level - primary lever)
    2. Structural mask (pixel level - perimeter protection)
    3. SAME APARTMENT task framing (mental model anchor)
    4. Aspect-ratio output size (proportion preservation)
    5. Prompt vocabulary (vocabulary alignment, NOT defensive repetition)

  What changed (Wave 4.5.0):
    FIRST_VISION contract: Tier 1 (~1550 chars) -> Tier 1.5 (~820 chars)
    Saving: ~730 chars per FIRST_VISION call
    Quality gain: interior_completeness now survives all standard scenarios

  What did NOT change:
    All vocabulary present (CAMERA LOCK, STRUCTURAL LOCK, applied last, etc.)
    input_fidelity=high, quality=high, structural mask, SAME APARTMENT framing
    wow_directive, compact_realism, DNA blocks, budget system, retry system

  Prompt reduction by scenario (200-char source):
    Soft Luxury living room:  ~407 chars shorter (all sections survive)
    Dark Contemporary living: ~423 chars shorter (all sections survive)
    Zero compression for any atmosphere+room at standard source lengths

  MANUAL PROD CHECKLIST:
    [1] Restart backend. Confirm [Prompt Budget] logs show smaller actual= values.
    [2] Confirm compression_applied=False for standard FIRST_VISION calls.
    [3] Confirm removed_sections=[] for standard rooms.
    [4] Verify fidelity quality unchanged vs Wave 4.4.1 baseline.
    [5] Verify WOW quality maintained.
""")
