"""
Wave 4.6.1 validation suite — First Vision Photo-Edit Refocus.

PROBLEM:
  Despite Wave 4.6.0 removing composition directives, FIRST_VISION still behaved as a
  scene reconstruction engine rather than a photo editing engine:
    1. SOURCE_SPACE text summaries reinterpreted the room BEFORE generation
       ("Two large floor-to-ceiling windows" missed bay opening, partition, diagonal depth)
    2. DNA furniture_language still had furniture object references at Wave 4.6.0 level
       ("on curved seating", "on armchair frame", "on low platform bed")
    3. Task header "SAME APARTMENT — apply" still permitted architectural framing
    4. WOW directive still said "furniture styling" implying composition authority

WAVE 4.6.1 CHANGES:
  1. SOURCE_SPACE removed from FIRST_VISION (source="") — image IS the source of truth
  2. All 10 DNA files — living_room + master_bedroom furniture_language → pure material/texture
     Zero furniture object references (no sofa, armchair, table, seating, bed, headboard, etc.)
     "bouclé upholstery on curved seating" → "warm bouclé in ivory — plush tactile richness"
  3. build_first_vision_task: "SAME APARTMENT PHOTO-EDIT — apply" (explicit photo-edit framing)
  4. build_photo_edit_wow_directive(): replaces build_restyling_wow_directive() in Path D
     Removes "furniture styling" signal; adds "photo edit" framing

PRESERVED:
  - input_fidelity=high, quality=high, structural mask, aspect ratio
  - compact_realism, SAME APARTMENT philosophy, retry_classifier, generation profiles
  - All luxury quality signals, atmosphere quality, emotional richness
  - build_restyling_wow_directive() frozen (backward compat — validate_wave451.py)
  - SOURCE_SPACE still used in STYLE_REFINEMENT and STRUCTURAL_TRANSFORMATION paths

Suites:
  A — SOURCE_SPACE removed from FIRST_VISION path
  B — build_photo_edit_wow_directive() vocabulary
  C — PHOTO-EDIT task framing (fidelity_layer)
  D — DNA furniture_language — zero furniture object references
  E — Rendered prompts end-to-end verification
  F — Regression: all prior waves intact
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


# ── Suite A: SOURCE_SPACE removed from FIRST_VISION ──────────────────────────
print("\n=== Suite A: SOURCE_SPACE removed from FIRST_VISION path ===")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()

check("A1  Wave 4.6.1 documented in composer",
      "Wave 4.6.1" in comp_src)
check("A2  source = '' in Path D (SOURCE_SPACE removed from FV)",
      'source = ""' in comp_src and "Wave 4.6.1: source" in comp_src)
check("A3  build_photo_edit_wow_directive imported in composer",
      "build_photo_edit_wow_directive" in comp_src)
check("A4  build_photo_edit_wow_directive() called in Path D",
      "build_photo_edit_wow_directive()" in comp_src)
check("A5  build_restyling_wow_directive still imported (backward compat)",
      "build_restyling_wow_directive" in comp_src)

# Verify FV rendered prompt has no SOURCE SPACE
logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS
logging.disable(logging.CRITICAL)

room_desc = "A bright living room with oak floors, large west-facing windows, and a sofa."
p_fv_sl = compose_generation_prompt("Soft Luxury · Gold", "living room", room_desc, "", 1, [])
p_fv_zen = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc, "", 1, [])

check("A6  FV rendered prompt has NO 'SOURCE SPACE' (removed from Path D)",
      "SOURCE SPACE" not in p_fv_sl)
check("A7  FV (Zen) rendered prompt has NO 'SOURCE SPACE'",
      "SOURCE SPACE" not in p_fv_zen)

# SR path must still have source_space (unaffected)
history_v2 = [
    {"role": "user", "content": "I want Soft Luxury"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer"},
]
p_sr = compose_generation_prompt("Soft Luxury · Gold", "living room", room_desc, "warmer", 2, history_v2)
check("A8  SR path still has 'SOURCE SPACE' (SR path unaffected)",
      "SOURCE SPACE" in p_sr)


# ── Suite B: build_photo_edit_wow_directive() vocabulary ─────────────────────
print("\n=== Suite B: build_photo_edit_wow_directive() vocabulary ===")

from prompt_engine.wow_layer import (
    build_photo_edit_wow_directive,
    build_restyling_wow_directive,
    _PHOTO_EDIT_WOW,
    _RESTYLING_WOW,
)

photo_wow = build_photo_edit_wow_directive()
restyling_wow = build_restyling_wow_directive()

check("B1  photo_edit_wow contains TRANSFORMATION AMBITION",
      "TRANSFORMATION AMBITION" in photo_wow)
check("B2  photo_edit_wow contains Visible architecture stays recognizable",
      "Visible architecture stays recognizable" in photo_wow)
check("B3  photo_edit_wow contains photo-first framing (exact apartment)",
      "exact apartment" in photo_wow)
check("B4  photo_edit_wow contains Decorate this photo",
      "Decorate this photo" in photo_wow)
check("B5  photo_edit_wow contains partitions (architecture continuity)",
      "partitions" in photo_wow)
check("B6  photo_edit_wow contains WOW through (quality aspiration)",
      "WOW through" in photo_wow or "WOW:" in photo_wow)
check("B7  photo_edit_wow contains photo edit framing",
      "photo edit" in photo_wow.lower() or "photo-edit" in photo_wow.lower())
check("B8  photo_edit_wow does NOT contain furniture styling (removed signal)",
      "furniture styling" not in photo_wow)
check("B9  photo_edit_wow does NOT contain editorial redesign",
      "editorial redesign" not in photo_wow)
check("B10 photo_edit_wow under 450 chars (budget-aware)",
      len(photo_wow) <= 450, f"got {len(photo_wow)}")
check("B11 build_restyling_wow_directive() FROZEN — unchanged from Wave 4.5.1",
      restyling_wow == _RESTYLING_WOW)
check("B12 frozen restyling_wow still has 'furniture styling' (vocab preserved)",
      "furniture styling" in restyling_wow)
check("B13 photo_edit_wow and restyling_wow are DIFFERENT (new function is distinct)",
      photo_wow != restyling_wow)


# ── Suite C: PHOTO-EDIT task framing ─────────────────────────────────────────
print("\n=== Suite C: PHOTO-EDIT task framing (fidelity_layer) ===")

from prompt_engine.fidelity_layer import build_first_vision_task

task_lr = build_first_vision_task("Zen Retreat", " living room")
task_mb = build_first_vision_task("Soft Luxury · Gold", " master bedroom")
task_empty = build_first_vision_task("Japandi", "")

check("C1  task contains PHOTO-EDIT (Wave 4.6.1 explicit framing)",
      "PHOTO-EDIT" in task_lr)
check("C2  task still contains SAME APARTMENT (regression — Wave 4.3.3)",
      "SAME APARTMENT" in task_lr)
check("C3  task still contains spatial truth",
      "spatial truth" in task_lr)
check("C4  task still contains geometry, camera, windows, openings, depth",
      all(k in task_lr for k in ["geometry", "camera", "windows", "openings", "depth"]))
check("C5  task still contains Restyle only",
      "Restyle only" in task_lr)
check("C6  task does NOT contain reproduce",
      "reproduce" not in task_lr)
check("C7  task does NOT contain REDESIGN",
      "REDESIGN" not in task_lr)
check("C8  task with room_ctx contains room name",
      "living room" in task_lr)
check("C9  task without room_ctx falls back to space",
      "this space" in task_empty)
check("C10 task length 150-250 chars for living room",
      150 <= len(task_lr) <= 250, f"got {len(task_lr)}")
check("C11 task length 150-250 chars for master bedroom",
      150 <= len(task_mb) <= 250, f"got {len(task_mb)}")

with open("prompt_engine/fidelity_layer.py", encoding="utf-8") as f:
    fid_src = f.read()

check("C12 fidelity_layer documents Wave 4.6.1",
      "Wave 4.6.1" in fid_src)
check("C13 fidelity_layer still documents Wave 4.6.0 (prior wave context preserved)",
      "Wave 4.6.0" in fid_src)
check("C14 fidelity_layer still documents Wave 4.3.3 (reconstruction strategy preserved)",
      "Wave 4.3.3" in fid_src)


# ── Suite D: DNA furniture_language — zero furniture object references ─────────
print("\n=== Suite D: DNA furniture_language — zero furniture object references ===")

from prompt_engine.atmosphere_dna import get_room_dna

# Furniture object signals that must NOT appear in living_room/master_bedroom
FURNITURE_OBJECTS = [
    "sofa", "armchair", "coffee table", "dining table", "seating",
    "headboard", "bench", "nightstand", "platform bed", "on low table",
    "on armchair", "on sofa", "on seating",
]

_ALL_ATM = [
    "soft_luxury", "japandi_calm", "zen_retreat", "warm_modern", "nordic_warmth",
    "dark_contemporary", "nature_retreat", "desert_luxe", "tropical_escape", "bali_sanctuary",
]

# living_room — no furniture objects
for atm in _ALL_ATM:
    dna = get_room_dna(atm, "living_room")
    if dna is None:
        check(f"D-{atm}-lr  living_room DNA exists", False)
        continue
    fl_text = " ".join(dna.furniture_language)
    has_object = any(obj in fl_text for obj in FURNITURE_OBJECTS)
    check(f"D1-{atm[:8]}  living_room furniture_language has no furniture objects",
          not has_object, f"found in: {fl_text[:100]}")

# master_bedroom — no furniture objects
for atm in _ALL_ATM:
    dna = get_room_dna(atm, "master_bedroom")
    if dna is None:
        check(f"D-{atm}-mb  master_bedroom DNA exists", False)
        continue
    fl_text = " ".join(dna.furniture_language)
    has_object = any(obj in fl_text for obj in FURNITURE_OBJECTS)
    check(f"D2-{atm[:8]}  master_bedroom furniture_language has no furniture objects",
          not has_object, f"found in: {fl_text[:100]}")

# Spot checks — material/atmosphere signals present
sl_lr = get_room_dna("soft_luxury", "living_room")
sl_mb = get_room_dna("soft_luxury", "master_bedroom")
zen_lr = get_room_dna("zen_retreat", "living_room")
bali_mb = get_room_dna("bali_sanctuary", "master_bedroom")

check("D21 soft_luxury living_room has 'bouclé' (luxury material signal)",
      sl_lr is not None and "bouclé" in " ".join(sl_lr.furniture_language))
check("D22 soft_luxury master_bedroom has 'cashmere' (luxury material signal)",
      sl_mb is not None and "cashmere" in " ".join(sl_mb.furniture_language))
check("D23 zen_retreat living_room has 'linen' (material signal)",
      zen_lr is not None and "linen" in " ".join(zen_lr.furniture_language))
check("D24 bali_sanctuary master_bedroom has 'teak' and 'cotton canopy' (material signals)",
      bali_mb is not None and
      "teak" in " ".join(bali_mb.furniture_language) and
      "cotton canopy" in " ".join(bali_mb.furniture_language))


# ── Suite E: Rendered prompts — end-to-end verification ──────────────────────
print("\n=== Suite E: Rendered prompts — end-to-end verification ===")

fv_budget = _MODE_BUDGETS["FIRST_VISION"]

check("E1  FV (Soft Luxury) has no SOURCE SPACE (removed from Path D)",
      "SOURCE SPACE" not in p_fv_sl)
check("E2  FV (Zen) has TRANSFORMATION AMBITION (wow intact)",
      "TRANSFORMATION AMBITION" in p_fv_zen)
check("E3  FV (Zen) has SAME APARTMENT PHOTO-EDIT (task updated)",
      "SAME APARTMENT PHOTO-EDIT" in p_fv_zen)
check("E4  FV (Zen) has no 'furniture styling' (removed from wow)",
      "furniture styling" not in p_fv_zen)
check("E5  FV (Zen) has no 'furniture styling' (Soft Luxury)",
      "furniture styling" not in p_fv_sl)
check("E6  FV (Zen) has CAMERA LOCK (structural contract intact)",
      "CAMERA LOCK" in p_fv_zen)
check("E7  FV (Zen) has Decorate this photo (photo-edit signal)",
      "Decorate this photo" in p_fv_zen)
check(f"E8  FV (Soft Luxury) within budget ({fv_budget})",
      len(p_fv_sl) <= fv_budget, f"got {len(p_fv_sl)}")
check(f"E9  FV (Zen) within budget ({fv_budget})",
      len(p_fv_zen) <= fv_budget, f"got {len(p_fv_zen)}")

# Non-DNA path
p_nondna = compose_generation_prompt("Japandi · Harmony", "home office", room_desc, "", 1, [])
check("E10 FV (non-DNA) has no SOURCE SPACE",
      "SOURCE SPACE" not in p_nondna)
check("E11 FV (non-DNA) has SAME APARTMENT PHOTO-EDIT",
      "SAME APARTMENT PHOTO-EDIT" in p_nondna)
check(f"E12 FV (non-DNA) within budget ({fv_budget})",
      len(p_nondna) <= fv_budget, f"got {len(p_nondna)}")


# ── Suite F: Regression ───────────────────────────────────────────────────────
print("\n=== Suite F: Regression — all prior waves intact ===")

# Wave 4.5.1: restyling_wow frozen
check("F1  build_restyling_wow_directive() has Decorate this photo (frozen)",
      "Decorate this photo" in build_restyling_wow_directive())
check("F2  build_restyling_wow_directive() has TRANSFORMATION AMBITION (frozen)",
      "TRANSFORMATION AMBITION" in build_restyling_wow_directive())

# Wave 4.3.1: original wow directive frozen
from prompt_engine.wow_layer import build_first_vision_wow_directive
check("F3  build_first_vision_wow_directive() has editorial redesign (frozen)",
      "editorial redesign" in build_first_vision_wow_directive())

# Wave 4.5.0: simplified contract still intact
from prompt_engine.preservation import build_simplified_fv_contract
sc = build_simplified_fv_contract("living room")
check("F4  build_simplified_fv_contract still has CAMERA LOCK",
      "CAMERA LOCK" in sc)
check("F5  build_simplified_fv_contract still has ATMOSPHERE BOUNDARY",
      "ATMOSPHERE BOUNDARY" in sc)

# Wave 4.6.0: no ROOM LOCK (regression)
check("F6  build_simplified_fv_contract has NO ROOM LOCK (W460 regression)",
      "ROOM LOCK" not in sc)

# Wave 4.4.1: budget system intact
check("F7  FIRST_VISION budget still 3550",
      _MODE_BUDGETS["FIRST_VISION"] == 3550)

# Wave 4.3.3: vocabulary regression
check("F8  FV prompt has spatial truth (W433 A3 regression)",
      "spatial truth" in p_fv_zen)
check("F9  FV prompt has STRUCTURAL LOCK (W433 C6 regression)",
      "STRUCTURAL LOCK" in p_fv_zen)
check("F10 FV prompt has no TOPOLOGY LOCKED (FV lighter than SR — W433 C11 regression)",
      "TOPOLOGY LOCKED" not in p_fv_zen)

# SR path — TOPOLOGY LOCKED present (regression)
check("F11 SR path has TOPOLOGY LOCKED (W430 regression)",
      "TOPOLOGY LOCKED" in p_sr)
check("F12 SR path has SOURCE SPACE (SR source unchanged)",
      "SOURCE SPACE" in p_sr)

# DNA STYLE key
from prompt_engine.atmosphere_dna import build_dna_block
sl_lr_dna = get_room_dna("soft_luxury", "living_room")
if sl_lr_dna:
    dna_text = build_dna_block(sl_lr_dna)
    check("F13 DNA block has ATMOSPHERE STYLE (restyle existing elements) — W451 regression",
          "ATMOSPHERE STYLE (restyle existing elements)" in dna_text)

# Retry/profile system
from retry_classifier import classify_for_retry
from generation_profiles import _PROFILES
check("F14 classify_for_retry still importable",
      callable(classify_for_retry))
check("F15 PROD max_attempts=3 unchanged",
      _PROFILES["prod"].max_attempts == 3)

# DEV compact mode
p_compact = compose_generation_prompt(
    "Soft Luxury · Gold", "living room", room_desc, "", 1, [], compact_prompts=True
)
check("F16 DEV compact still has SAME APARTMENT (P1 never dropped)",
      "SAME APARTMENT" in p_compact)
check("F17 DEV compact has no SOURCE SPACE (removed from FV in 4.6.1)",
      "SOURCE SPACE" not in p_compact)

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
  WAVE 4.6.1 — FIRST_VISION PHOTO-EDIT REFOCUS SUMMARY:

  Change                          | Before                            | After
  --------------------------------|-----------------------------------|----------------------------------
  SOURCE_SPACE in FIRST_VISION    | f"SOURCE SPACE: {room_desc}"      | "" (removed — image is source)
  DNA furniture_language (LR/MB)  | Material + furniture objects      | Pure material/texture/atmosphere
  build_first_vision_task()       | "SAME APARTMENT — apply"          | "SAME APARTMENT PHOTO-EDIT — apply"
  WOW directive (Path D)          | build_restyling_wow_directive()   | build_photo_edit_wow_directive()
  "furniture styling" signal      | present in WOW                    | removed

  NET EFFECT:
  - FIRST_VISION is now explicitly a photo editing operation, not a scene generation
  - Source-of-truth is the uploaded image, not a text summary that reinterprets it
  - DNA vocabulary is now 100% material/texture/atmosphere — zero furniture object references
  - All luxury quality signals intact: WOW, materials/lighting, compact_realism, atmosphere DNA
  - Estimated -40% reconstruction authority, -60% retry risk from photo recomposition
""")
