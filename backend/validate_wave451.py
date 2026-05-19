"""
Wave 4.5.1 validation suite — First Vision Philosophy Refocus.

PROBLEM (from PROD):
  System behaved like "architectural reconstruction + luxury redesign" instead
  of "faithful premium restyling of the SAME photo." The photo was treated as
  inspiration rather than dominant source of truth.

WAVE 4.5.1 FIXES:
  1. build_restyling_wow_directive() — photo-first WOW framing, no "editorial redesign"
  2. DNA STYLE key: "STYLE:" -> "ATMOSPHERE STYLE (restyle existing elements):"
  3. composer.py Path D now uses build_restyling_wow_directive() for wow_block

PRESERVED:
  - build_first_vision_wow_directive() unchanged (backward compat)
  - "TRANSFORMATION AMBITION" vocabulary still present in new directive
  - "Visible architecture stays recognizable" still present
  - All DNA content, budget system, realism, contract unchanged

Suites:
  A — FIRST_VISION_REFOCUS.md document
  B — build_restyling_wow_directive() vocabulary checks
  C — composer.py wiring: new function used, old framing absent from rendered output
  D — DNA STYLE key change in build_dna_block
  E — Regression: required vocabulary still present in rendered prompts
  F — System integrity: all quality systems intact
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


# ── Suite A: FIRST_VISION_REFOCUS.md ─────────────────────────────────────────
print("\n=== Suite A: FIRST_VISION_REFOCUS.md ===")

refocus_path = os.path.join(os.path.dirname(__file__), "docs", "FIRST_VISION_REFOCUS.md")
check("A1  docs/FIRST_VISION_REFOCUS.md exists",
      os.path.isfile(refocus_path))

if os.path.isfile(refocus_path):
    with open(refocus_path, encoding="utf-8") as f:
        refocus_src = f.read()
else:
    refocus_src = ""

check("A2  Refocus doc states Wave 4.5.1",
      "4.5.1" in refocus_src)
check("A3  Refocus doc describes the problem (photo as inspiration vs source of truth)",
      "source of truth" in refocus_src.lower() or "dominant source" in refocus_src.lower())
check("A4  Refocus doc mentions editorial redesign removal",
      "editorial redesign" in refocus_src)
check("A5  Refocus doc mentions new restyling directive",
      "build_restyling_wow_directive" in refocus_src)
check("A6  Refocus doc mentions DNA STYLE key change",
      "ATMOSPHERE STYLE" in refocus_src)
check("A7  Refocus doc preserves backward-compat note",
      "build_first_vision_wow_directive" in refocus_src)
check("A8  Refocus doc lists what was NOT changed",
      "NOT Changed" in refocus_src or "Was NOT Changed" in refocus_src
      or "not changed" in refocus_src.lower())
check("A9  Refocus doc mentions TRANSFORMATION AMBITION preserved",
      "TRANSFORMATION AMBITION" in refocus_src)
check("A10 Refocus doc has expected behavioral change section",
      "Behavioral Change" in refocus_src or "behavioral change" in refocus_src.lower())


# ── Suite B: build_restyling_wow_directive() vocabulary ──────────────────────
print("\n=== Suite B: build_restyling_wow_directive() vocabulary ===")

from prompt_engine.wow_layer import (
    build_first_vision_wow_directive,
    build_restyling_wow_directive,
    _WOW_DIRECTIVE,
    _RESTYLING_WOW,
)

old_wow = build_first_vision_wow_directive()
new_wow = build_restyling_wow_directive()

# Required vocabulary in new directive
check("B1  New directive contains TRANSFORMATION AMBITION",
      "TRANSFORMATION AMBITION" in new_wow)
check("B2  New directive contains Visible architecture stays recognizable",
      "Visible architecture stays recognizable" in new_wow)
check("B3  New directive contains photo-first framing (this exact apartment photo)",
      "this exact apartment photo" in new_wow or "exact apartment photo" in new_wow)
check("B4  New directive contains Decorate this photo",
      "Decorate this photo" in new_wow)
check("B5  New directive does NOT contain editorial redesign",
      "editorial redesign" not in new_wow)
check("B6  New directive does NOT contain Transform the character fully",
      "Transform the character fully" not in new_wow)
check("B7  New directive does NOT contain a new one (old wording)",
      "not a new one." not in new_wow)
check("B8  New directive is within budget (<=380 chars)",
      len(new_wow) <= 380, f"got {len(new_wow)}")
check("B9  Old directive is UNCHANGED (backward compat — Wave 4.3.1 frozen)",
      old_wow == _WOW_DIRECTIVE)
check("B10 Old directive still contains editorial redesign (frozen vocabulary)",
      "editorial redesign" in old_wow)
check("B11 Old directive still contains Transform the character fully",
      "Transform the character fully" in old_wow)
check("B12 New directive contains WOW through (quality aspiration)",
      "WOW through" in new_wow or "WOW:" in new_wow)


# ── Suite C: Composer wiring ──────────────────────────────────────────────────
print("\n=== Suite C: Composer wiring ===")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()

check("C1  build_restyling_wow_directive imported in composer",
      "build_restyling_wow_directive" in comp_src)
check("C2  Wave 4.5.1 documented in composer docstring",
      "Wave 4.5.1" in comp_src)
check("C3  photo_edit_wow or restyling_wow used in Path D (Wave 4.6.1 moves to photo_edit_wow)",
      "build_photo_edit_wow_directive()" in comp_src or comp_src.count("build_restyling_wow_directive()") >= 2)

# Rendered prompt checks
from prompt_engine.atmosphere_dna import get_room_dna, build_dna_block
from prompt_engine.fidelity_layer import build_first_vision_task
from prompt_engine.preservation import build_simplified_fv_contract
from prompt_engine.wow_layer import build_restyling_wow_directive as restyle_wow
from prompt_engine.realism_layer import build_compact_realism_block, build_interior_completeness_rule
from prompt_engine.composer import _assemble_with_budget, _MODE_BUDGETS

fv_budget = _MODE_BUDGETS["FIRST_VISION"]


def _assemble_fv(atmosphere_id: str, dna_name: str, room_type: str, source_length: int):
    room_ctx = f" {room_type}"
    task = build_first_vision_task(dna_name, room_ctx)
    contract = build_simplified_fv_contract(room_type)
    source = "SOURCE SPACE: " + ("x" * source_length) if source_length else ""
    dna = get_room_dna(atmosphere_id, room_type)
    intel = build_dna_block(dna) if dna else ""
    wow = restyle_wow()
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


sl_prompt, sl_dropped = _assemble_fv("soft_luxury", "Soft Luxury Gold", "living room", 200)
jp_prompt, jp_dropped = _assemble_fv("japandi_calm", "Japandi Calm", "living room", 200)

check("C4  editorial redesign NOT in rendered SL FV prompt",
      "editorial redesign" not in sl_prompt,
      f"found 'editorial redesign' in prompt")
check("C5  Transform the character fully NOT in rendered SL FV prompt",
      "Transform the character fully" not in sl_prompt)
check("C6  TRANSFORMATION AMBITION IS in rendered SL FV prompt",
      "TRANSFORMATION AMBITION" in sl_prompt)
check("C7  Decorate this photo IS in rendered SL FV prompt",
      "Decorate this photo" in sl_prompt)
check("C8  wow_directive survives for SL living room 200-char (Wave 4.4.1 regression)",
      "wow_directive" not in sl_dropped, f"dropped={sl_dropped}")
check("C9  SL FV prompt within budget",
      len(sl_prompt) <= fv_budget, f"got {len(sl_prompt)}")
check("C10 editorial redesign NOT in rendered Japandi FV prompt",
      "editorial redesign" not in jp_prompt)

# STYLE_REFINEMENT unchanged — no new wow in SR path
logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt
logging.disable(logging.CRITICAL)

room_desc = "A bright living room with oak floors and large west-facing windows."
history_v2 = [
    {"role": "user", "content": "I want Japandi style"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer"},
]
p_sr = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "warmer", 2, history_v2)
check("C11 STYLE_REFINEMENT does not contain Decorate this photo (SR path unchanged)",
      "Decorate this photo" not in p_sr)
check("C12 STYLE_REFINEMENT does not contain editorial redesign (SR path unchanged)",
      "editorial redesign" not in p_sr)


# ── Suite D: DNA STYLE key change ─────────────────────────────────────────────
print("\n=== Suite D: DNA STYLE key change ===")

with open("prompt_engine/atmosphere_dna/_base.py", encoding="utf-8") as f:
    dna_src = f.read()

check("D1  ATMOSPHERE STYLE (restyle existing elements) in _base.py",
      "ATMOSPHERE STYLE (restyle existing elements)" in dna_src)
check("D2  Old bare STYLE: key NOT used in build_dna_block room_line",
      "f\"STYLE: {style}." not in dna_src)

# Check rendered DNA block
from prompt_engine.atmosphere_dna import get_room_dna, build_dna_block as _build_dna

sl_dna = get_room_dna("soft_luxury", "living room")
jp_dna = get_room_dna("japandi_calm", "living room")
zen_dna = get_room_dna("zen_retreat", "living room")

if sl_dna:
    sl_dna_block = _build_dna(sl_dna)
    check("D3  SL DNA block contains ATMOSPHERE STYLE (restyle existing elements)",
          "ATMOSPHERE STYLE (restyle existing elements)" in sl_dna_block,
          sl_dna_block[:200])
    check("D4  SL DNA block does NOT contain bare STYLE: prefix",
          "\nSTYLE:" not in sl_dna_block and "LIGHT: " not in sl_dna_block[:30])
else:
    check("D3  SL DNA registered", False, "no SL DNA found")
    check("D4  SL DNA bare STYLE check skipped", False, "no SL DNA")

if jp_dna:
    jp_dna_block = _build_dna(jp_dna)
    check("D5  Japandi DNA block contains ATMOSPHERE STYLE (restyle existing elements)",
          "ATMOSPHERE STYLE (restyle existing elements)" in jp_dna_block)
else:
    check("D5  Japandi DNA registered", False, "no Japandi DNA found")

if zen_dna:
    zen_dna_block = _build_dna(zen_dna)
    check("D6  Zen DNA block contains ATMOSPHERE STYLE (restyle existing elements)",
          "ATMOSPHERE STYLE (restyle existing elements)" in zen_dna_block)
else:
    check("D6  Zen DNA registered", False, "no Zen DNA found")

# Verify core DNA content not corrupted
if sl_dna:
    check("D7  SL DNA ATMOSPHERE line still present",
          "ATMOSPHERE" in sl_dna_block)
    check("D8  SL DNA LIGHT section still present",
          "LIGHT:" in sl_dna_block)
    check("D9  SL DNA REALISM section still present",
          "REALISM:" in sl_dna_block)
    check("D10 SL DNA AVOID section still present",
          "AVOID:" in sl_dna_block)


# ── Suite E: Regression — required vocabulary in rendered prompts ─────────────
print("\n=== Suite E: Regression — required vocabulary in rendered prompts ===")

dc_prompt, dc_dropped = _assemble_fv("dark_contemporary", "Dark Contemporary", "living room", 200)
zen_prompt, zen_dropped = _assemble_fv("zen_retreat", "Zen Retreat", "living room", 200)

# Wave 4.4.1: wow_directive must survive for all major atmospheres (200-char source)
check("E1  wow_directive survives for Dark Contemporary (200-char source, Wave 4.4.1)",
      "wow_directive" not in dc_dropped, f"dropped={dc_dropped}")
check("E2  wow_directive survives for Zen Retreat (200-char source, Wave 4.4.1)",
      "wow_directive" not in zen_dropped, f"dropped={zen_dropped}")

# Wave 4.3.3: SAME APARTMENT in all prompts
check("E3  SAME APARTMENT in SL FV prompt (Wave 4.3.3 intact)",
      "SAME APARTMENT" in sl_prompt)
check("E4  SAME APARTMENT in Japandi FV prompt (Wave 4.3.3 intact)",
      "SAME APARTMENT" in jp_prompt)

# Wave 4.3.1: Visible architecture stays recognizable in new wow directive
check("E5  Visible architecture stays recognizable in SL FV (new WOW, Wave 4.3.1 vocabulary)",
      "Visible architecture stays recognizable" in sl_prompt)

# Wave 4.2.x: compact_realism quality floor
check("E6  NOT a CGI render in SL FV (compact realism intact)",
      "NOT a CGI render" in sl_prompt)
check("E7  DSLR in SL FV (compact realism intact)",
      "DSLR" in sl_prompt)

# Wave 4.5.0: Tier 1.5 contract vocabulary
check("E8  CAMERA LOCK in SL FV (Tier 1.5 contract)",
      "CAMERA LOCK" in sl_prompt)
check("E9  STRUCTURAL LOCK in SL FV (Tier 1.5 contract)",
      "STRUCTURAL LOCK" in sl_prompt)
check("E10 ATMOSPHERE BOUNDARY in SL FV (Tier 1.5 contract)",
      "ATMOSPHERE BOUNDARY" in sl_prompt)

# Budget checks
check("E11 DC FV prompt within budget",
      len(dc_prompt) <= fv_budget, f"got {len(dc_prompt)}")
check("E12 Zen FV prompt within budget",
      len(zen_prompt) <= fv_budget, f"got {len(zen_prompt)}")

# STYLE_REFINEMENT vocabulary preserved
check("E13 TOPOLOGY LOCKED in SR path (Wave 4.3.0 intact)",
      "TOPOLOGY LOCKED" in p_sr)
check("E14 SAME APARTMENT in SR path",
      "SAME APARTMENT" in p_sr)

# DEV compact mode still works
p_dev = compose_generation_prompt("Japandi · Harmony", "living room", room_desc, "", 1, [], compact_prompts=True)
check("E15 DEV compact mode: SAME APARTMENT still present (P1 task never drops)",
      "SAME APARTMENT" in p_dev)


# ── Suite F: System integrity ─────────────────────────────────────────────────
print("\n=== Suite F: System integrity ===")

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
with open("prompt_engine/fidelity_layer.py", encoding="utf-8") as f:
    fidelity_src = f.read()
with open("prompt_engine/wow_layer.py", encoding="utf-8") as f:
    wow_src = f.read()

# Old wow function still intact in wow_layer.py (backward compat)
check("F1  build_first_vision_wow_directive still exists in wow_layer.py",
      "def build_first_vision_wow_directive" in wow_src)
check("F2  _WOW_DIRECTIVE still in wow_layer.py (frozen vocabulary)",
      "_WOW_DIRECTIVE" in wow_src)
check("F3  editorial redesign still in _WOW_DIRECTIVE (backward compat)",
      "editorial redesign" in wow_src)
check("F4  build_restyling_wow_directive defined in wow_layer.py",
      "def build_restyling_wow_directive" in wow_src)
check("F5  _RESTYLING_WOW defined in wow_layer.py",
      "_RESTYLING_WOW" in wow_src)

# Wave 4.4.0: mask still enabled
check("F6  Wave 4.4.0 mask default still true",
      'ENABLE_STRUCTURAL_MASK", "true"' in main_src or '"true"' in main_src)
check("F7  Wave 4.4.0 run_in_executor still in main.py",
      "run_in_executor" in main_src)

# Wave 4.3.3: reconstruction-first task framing
check("F8  Wave 4.3.3 SAME APARTMENT in fidelity_layer",
      "SAME APARTMENT" in fidelity_src)
check("F9  Wave 4.3.3 spatial truth in fidelity_layer",
      "spatial truth" in fidelity_src)

# Wave 4.3.2: retry system
check("F10 Wave 4.3.2 max_retries=0 in main.py",
      "max_retries=0" in main_src)

# Wave 4.3.1: old wow vocabulary frozen
check("F11 Wave 4.3.1 THIS apartment, not a new one in wow_src",
      "THIS apartment, not a new one" in wow_src)
check("F12 Wave 4.3.1 Visible architecture stays recognizable in wow_src",
      "Visible architecture stays recognizable" in wow_src)

# Wave 4.4.1: budget 3550
with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src2 = f.read()
check("F13 Wave 4.4.1 FIRST_VISION budget 3550",
      '"FIRST_VISION": 3550' in comp_src2)
check("F14 Wave 4.4.1 interior_completeness priority 5",
      '"interior_completeness": 5' in comp_src2)

# Intent classifier frozen
from prompt_engine.intent_classifier import classify_intent
check("F15 intent_classifier still importable and functional",
      callable(classify_intent))

rc_src = open("retry_classifier.py", encoding="utf-8").read()
check("F16 retry_classifier.py still contains RemoteProtocolError handling",
      "RemoteProtocolError" in rc_src)

# Performance observer preserved
check("F17 performance_observer.py still exists (Wave 4.4.2)",
      os.path.isfile(os.path.join(os.path.dirname(__file__), "performance_observer.py")))

# Wave 4.5.0: simplified contract still in use
check("F18 Wave 4.5.0 build_simplified_fv_contract used in composer",
      "build_simplified_fv_contract" in comp_src2)

# Wave 4.5.1: both WOW functions exported
from prompt_engine.wow_layer import build_first_vision_wow_directive, build_restyling_wow_directive
check("F19 build_first_vision_wow_directive callable",
      callable(build_first_vision_wow_directive))
check("F20 build_restyling_wow_directive callable",
      callable(build_restyling_wow_directive))


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
  WAVE 4.5.1 ANALYSIS -- FIRST VISION PHILOSOPHY REFOCUS:

  Change                 | Before                     | After
  -----------------------|----------------------------|----------------------------
  WOW directive          | editorial redesign framing | premium restyling framing
  "Transform fully"      | present                    | removed
  "Decorate this photo"  | absent                     | present
  DNA STYLE key          | STYLE:                     | ATMOSPHERE STYLE (restyle)
  Old WOW function       | in use                     | preserved (backward compat)
  TRANSFORMATION AMBITION| present                    | present (preserved)
  Vis. arch. recognizable| present                    | present (preserved)
  Budget system          | unchanged                  | unchanged
  All other paths        | unchanged                  | unchanged

  EXPECTED PROD BEHAVIOR:
    - Generated images should look like the uploaded apartment restyled
    - Furniture composition should more closely match uploaded photo layout
    - Atmosphere/material quality unchanged (driven by DNA + realism block)
    - Architecture fidelity improved (less "editorial redesign" permission)

  MANUAL PROD CHECKLIST:
    [1] Restart backend. Confirm logs show restyling directive in prompts.
    [2] Test with benchmark apartment: SL living room, standard description.
    [3] Verify output looks like SAME apartment with new atmosphere.
    [4] Verify atmosphere quality / luxury feel maintained (not diminished).
    [5] Score architecture fidelity: should improve from baseline.
    [6] Score transformation quality: should remain >= 4.0.
""")
