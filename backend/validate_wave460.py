"""
Wave 4.6.0 validation suite — Core Product Simplification.

PROBLEM:
  Despite Wave 4.5.1 adding "Decorate this photo — do not recompose it", the system
  still contained three composition-authoritative instructions that worked against the
  photo-first philosophy:
    1. DNA furniture_language prescribed specific pieces → model replaces uploaded furniture
    2. build_scene_completion() had "COMPLETE THE SCENE: include sofa grouping, coffee
       table..." → most direct composition-override instruction in the system
    3. build_simplified_fv_contract() ROOM LOCK phrases assumed specific furniture positions
       not grounded in uploaded photo ("preserve TV wall or fireplace position, sofa zone")
    4. build_first_vision_task() used "reproduce... exactly. Then transform" framing
       which still carried implicit reconstruction license
    5. interior_completeness "never sparse, empty, under-furnished" contradicted photo-first
       when uploaded room is intentionally minimal

WAVE 4.6.0 CHANGES:
  1. All 10 DNA files — living_room + master_bedroom furniture_language changed from
     specific piece names ("deep curved bouclé sofa in ivory") to material/texture vocab
     ("bouclé upholstery in warm ivory on curved seating") — RESTYLING DNA, not COMPOSITION DNA
  2. preservation.py build_simplified_fv_contract() — removed _room_note() ROOM LOCK phrases
  3. fidelity_layer.py build_first_vision_task() — "reproduce" → "preserve", added "Restyle only"
  4. dream_scene_completion.py build_scene_completion() — removed element checklist; quality note only
  5. composer.py Path D DNA branch — completeness="" (DNA handles richness; photo-first for minimal rooms)

Suites:
  A — DNA furniture_language: restyling vocab (all 10 atmospheres × 2 room types)
  B — preservation.py: ROOM LOCK removed, required vocab preserved
  C — fidelity_layer: restyling framing, backward-compat vocabulary intact
  D — dream_scene_completion: no element checklist, quality note preserved
  E — composer: Wave 4.6.0 wiring — completeness empty on DNA path, source ordering intact
  F — Rendered prompts: photo-first improvements verified end-to-end
  G — Regression: prior-wave vocabulary, budgets, system integrity
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


# ── Suite A: DNA furniture_language — restyling vocabulary ───────────────────
print("\n=== Suite A: DNA furniture_language — restyling vocab (no replacement instructions) ===")

from prompt_engine.atmosphere_dna import get_room_dna, build_dna_block

# Restyling/material vocab — describes material quality, texture, atmosphere (Wave 4.6.1: pure material/texture)
# Wave 4.6.0: "upholstery", "surface for", "frame" etc. (material-on-furniture descriptors)
# Wave 4.6.1: "tactile", "warmth", "richness" etc. (pure material/atmosphere descriptors)
RESTYLING_SIGNALS = ["tactile", "warmth", "richness", "texture", "organic", "softness", "depth"]

# Composition-replacement signals that must NOT appear in living_room/master_bedroom
REPLACEMENT_SIGNALS = [
    "sofa in ivory or blush",
    "bouclé sofa",
    "cashmere armchairs",
    "platform sofa in",
    "sofa in natural",
    "sofa in raw cotton",
    "sofa with thick",
    "low-profile ash sofa",
    "deep low sofa in dark",
    "deep sofa in undyed",
    "deep low teak sofa",
    "curved boucle sofa in oat",
    "sofa in natural wool",
    "four-poster teak bed",
    "platform bed in pale ash",
    "floor-level sleeping platform in pale",
    "padded arched headboard in cashmere",
    "low upholstered platform bed in dark",
    "reclaimed oak platform bed with",
    "low bed platform in warm timber",
    "timber or rattan bed frame with white",
    "upholstered linen headboard in warm oat",
    "pine or birch bed frame with natural linen",
]

_ATM_LIVING = [
    "soft_luxury", "japandi_calm", "zen_retreat", "warm_modern", "nordic_warmth",
    "dark_contemporary", "nature_retreat", "desert_luxe", "tropical_escape", "bali_sanctuary",
]

for atm in _ATM_LIVING:
    dna = get_room_dna(atm, "living_room")
    if dna is None:
        check(f"A-{atm}-lr  living_room DNA exists", False, "DNA not found")
        continue
    fl_text = " ".join(dna.furniture_language)
    has_restyling = any(s in fl_text for s in RESTYLING_SIGNALS)
    has_replacement = any(s in fl_text for s in REPLACEMENT_SIGNALS)
    check(f"A1-{atm[:8]}  living_room has restyling vocab signal",
          has_restyling, f"furniture_language={fl_text[:80]}")
    check(f"A2-{atm[:8]}  living_room has no composition-replacement signal",
          not has_replacement, f"found in: {fl_text[:80]}")

_ATM_BEDROOM = _ATM_LIVING  # same 10

for atm in _ATM_BEDROOM:
    dna = get_room_dna(atm, "master_bedroom")
    if dna is None:
        check(f"A-{atm}-mb  master_bedroom DNA exists", False, "DNA not found")
        continue
    fl_text = " ".join(dna.furniture_language)
    has_restyling = any(s in fl_text for s in RESTYLING_SIGNALS)
    has_replacement = any(s in fl_text for s in REPLACEMENT_SIGNALS)
    check(f"A3-{atm[:8]}  master_bedroom has restyling vocab signal",
          has_restyling, f"furniture_language={fl_text[:80]}")
    check(f"A4-{atm[:8]}  master_bedroom has no composition-replacement signal",
          not has_replacement, f"found in: {fl_text[:80]}")

# Spot-check the most critical atmosphere
sl_lr = get_room_dna("soft_luxury", "living_room")
sl_mb = get_room_dna("soft_luxury", "master_bedroom")
check("A5  soft_luxury living_room has 'bouclé' in furniture_language (Wave 4.6.1 pure material)",
      sl_lr is not None and "bouclé" in " ".join(sl_lr.furniture_language))
check("A6  soft_luxury living_room has NO 'bouclé sofa in ivory'",
      sl_lr is not None and "bouclé sofa in ivory" not in " ".join(sl_lr.furniture_language))
check("A7  soft_luxury master_bedroom has 'cashmere' in furniture_language (Wave 4.6.1 pure material)",
      sl_mb is not None and "cashmere" in " ".join(sl_mb.furniture_language))
check("A8  soft_luxury master_bedroom has NO 'padded arched headboard in cashmere'",
      sl_mb is not None and "padded arched headboard in cashmere" not in " ".join(sl_mb.furniture_language))

zen_lr = get_room_dna("zen_retreat", "living_room")
check("A9  zen_retreat living_room has 'linen upholstery' not 'sofa in natural unbleached linen'",
      zen_lr is not None and
      "sofa in natural unbleached linen" not in " ".join(zen_lr.furniture_language) and
      "linen" in " ".join(zen_lr.furniture_language))

bali_mb = get_room_dna("bali_sanctuary", "master_bedroom")
check("A10 bali_sanctuary master_bedroom has NO 'four-poster teak bed with sheer canopy drapes' (old form)",
      bali_mb is not None and
      "four-poster teak bed with sheer canopy drapes" not in " ".join(bali_mb.furniture_language))
check("A11 bali_sanctuary master_bedroom has 'teak' and 'cotton canopy' (Wave 4.6.1 pure material form)",
      bali_mb is not None and
      "teak" in " ".join(bali_mb.furniture_language) and
      "cotton canopy" in " ".join(bali_mb.furniture_language))


# ── Suite B: preservation.py — ROOM LOCK removed from simplified contract ────
print("\n=== Suite B: preservation.py — ROOM LOCK removed from simplified contract ===")

with open("prompt_engine/preservation.py", encoding="utf-8") as f:
    pres_src = f.read()

from prompt_engine.preservation import build_simplified_fv_contract

sc_lr = build_simplified_fv_contract("living room")
sc_br = build_simplified_fv_contract("bedroom")
sc_ki = build_simplified_fv_contract("kitchen")

check("B1  build_simplified_fv_contract living room has NO 'ROOM LOCK'",
      "ROOM LOCK" not in sc_lr)
check("B2  build_simplified_fv_contract bedroom has NO 'ROOM LOCK'",
      "ROOM LOCK" not in sc_br)
check("B3  build_simplified_fv_contract kitchen has NO 'ROOM LOCK'",
      "ROOM LOCK" not in sc_ki)
check("B4  build_simplified_fv_contract living room has NO 'TV wall or fireplace'",
      "TV wall or fireplace" not in sc_lr)
check("B5  build_simplified_fv_contract living room has NO 'sofa zone'",
      "sofa zone" not in sc_lr)

# Required vocabulary still present
check("B6  simplified contract still has CAMERA LOCK", "CAMERA LOCK" in sc_lr)
check("B7  simplified contract still has STRUCTURAL LOCK", "STRUCTURAL LOCK" in sc_lr)
check("B8  simplified contract still has ATMOSPHERE BOUNDARY", "ATMOSPHERE BOUNDARY" in sc_lr)
check("B9  simplified contract still has focal length", "focal length" in sc_lr.lower())
check("B10 simplified contract still has vanishing points", "vanishing point" in sc_lr.lower())
check("B11 simplified contract still has DO NOT reinterpret", "DO NOT reinterpret" in sc_lr)
check("B12 simplified contract still has SAME apartment", "SAME apartment" in sc_lr)

# Size: living room with note was ~820 chars; without note is ~693 chars — both pass C18/C19
check("B13 simplified contract under 900 chars (C19 regression)",
      len(sc_lr) < 900, f"got {len(sc_lr)}")
check("B14 simplified contract under 1000 chars (C18 regression)",
      len(sc_lr) < 1000, f"got {len(sc_lr)}")
check("B15 simplified contract same for all room types (ROOM LOCK removed, no branching)",
      sc_lr == sc_br == sc_ki)

# Wave 4.6.0 documented in source
check("B16 Wave 4.6.0 documented in preservation.py",
      "Wave 4.6.0" in pres_src)


# ── Suite C: fidelity_layer — restyling framing ───────────────────────────────
print("\n=== Suite C: fidelity_layer — restyling framing ===")

from prompt_engine.fidelity_layer import build_first_vision_task

task_lr = build_first_vision_task("Zen Retreat", " living room")
task_mb = build_first_vision_task("Soft Luxury · Gold", " master bedroom")
task_empty = build_first_vision_task("Japandi", "")

# New restyling vocabulary
check("C1  task contains 'preserve' (restyling, not reconstruction)",
      "preserve" in task_lr)
check("C2  task contains 'Restyle only'",
      "Restyle only" in task_lr)
check("C3  task contains 'lighting' in transform clause",
      "lighting" in task_lr)
check("C4  task contains 'atmosphere' in transform clause",
      "atmosphere" in task_lr)

# Removed reconstruction vocabulary
check("C5  task does NOT contain 'reproduce'",
      "reproduce" not in task_lr)
check("C6  task does NOT contain 'Then transform all surfaces'",
      "Then transform all surfaces" not in task_lr)

# Wave 4.3.3 required vocabulary still present (regression)
check("C7  task still contains 'SAME APARTMENT' (A2 regression)",
      "SAME APARTMENT" in task_lr)
check("C8  task still contains 'spatial truth' (A3 regression)",
      "spatial truth" in task_lr)
check("C9  task still contains 'geometry' (A4 regression)",
      "geometry" in task_lr)
check("C10 task still contains 'windows' (A5 regression)",
      "windows" in task_lr)
check("C11 task still contains 'openings' (A6 regression)",
      "openings" in task_lr)
check("C12 task still contains 'depth' (A7 regression)",
      "depth" in task_lr)
check("C13 task still contains 'camera' (A8 regression)",
      "camera" in task_lr)
check("C14 task still contains 'transform' (A9 regression)",
      "transform" in task_lr.lower())
check("C15 task with room_ctx contains room name (A10 regression)",
      "living room" in task_lr)
check("C16 task without room_ctx contains 'this space' (A11 regression)",
      "this space" in task_empty)
check("C17 task length 150-250 chars for living room (A14 regression)",
      150 <= len(task_lr) <= 250, f"got {len(task_lr)}")
check("C18 task length 150-250 chars for master bedroom (budget-aware)",
      150 <= len(task_mb) <= 250, f"got {len(task_mb)}")

with open("prompt_engine/fidelity_layer.py", encoding="utf-8") as f:
    fid_src = f.read()

check("C19 fidelity_layer documents Wave 4.6.0",
      "Wave 4.6.0" in fid_src)
check("C20 fidelity_layer still documents Wave 4.3.3 (prior wave context preserved)",
      "Wave 4.3.3" in fid_src)


# ── Suite D: dream_scene_completion — no element checklist ───────────────────
print("\n=== Suite D: dream_scene_completion — no element checklist ===")

from prompt_engine.dream_scene_completion import (
    build_scene_completion,
    build_dream_micro_layer,
    build_dream_addendum,
)

sc_lr_zen = build_scene_completion("living room", "zen_retreat")
sc_lr_sl  = build_scene_completion("living room", "soft_luxury")
sc_br_wm  = build_scene_completion("bedroom", "warm_modern")
sc_nondna = build_scene_completion("home office", "nordic_warmth")

check("D1  build_scene_completion has NO 'COMPLETE THE SCENE'",
      "COMPLETE THE SCENE" not in sc_lr_zen)
check("D2  build_scene_completion (bedroom) has NO 'COMPLETE THE SCENE'",
      "COMPLETE THE SCENE" not in sc_br_wm)
check("D3  build_scene_completion has NO furniture list 'sofa grouping'",
      "sofa grouping" not in sc_lr_zen)
check("D4  build_scene_completion has NO furniture list 'coffee table'",
      "coffee table" not in sc_lr_zen)
check("D5  build_scene_completion has NO 'area rug'",
      "area rug" not in sc_lr_zen)
check("D6  build_scene_completion still has 'QUALITY:' (atmosphere richness note)",
      "QUALITY:" in sc_lr_zen)
check("D7  build_scene_completion (soft_luxury) has atmosphere quality descriptor",
      "plush" in sc_lr_sl or "premium" in sc_lr_sl or "elegant" in sc_lr_sl)
check("D8  build_scene_completion still has dream factor aspiration",
      "aspirational" in sc_lr_zen or "warm" in sc_lr_zen)
check("D9  build_scene_completion under 200 chars (compressed)",
      len(sc_lr_zen) < 200, f"got {len(sc_lr_zen)}")
check("D10 build_dream_micro_layer() unchanged (SR path unaffected)",
      "Layered lighting" in build_dream_micro_layer())
check("D11 build_dream_addendum() unchanged (SR non-DNA path unaffected)",
      "DREAM QUALITY:" in build_dream_addendum("soft_luxury"))


# ── Suite E: composer — Wave 4.6.0 wiring ─────────────────────────────────────
print("\n=== Suite E: composer — Wave 4.6.0 wiring ===")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()

check("E1  Wave 4.6.0 documented in composer docstring",
      "Wave 4.6.0" in comp_src)
check("E2  completeness = '' on DNA path (Wave 4.6.0 change)",
      'completeness = ""  # Wave 4.6.0' in comp_src)
# Wave 4.7.1 R2 superseded the original 4.6.0 split policy: the non-DNA FIRST_VISION
# path now uses completeness="" too (unified with the DNA path). The function stays
# imported (E6) for validator harness compatibility; only the FV usage was removed.
check("E3  non-DNA FIRST_VISION completeness unified to '' (Wave 4.7.1 R2 — was build_interior_completeness_rule())",
      'completeness = ""  # Wave 4.7.1 R2' in comp_src and
      "completeness = build_interior_completeness_rule()" not in comp_src)
check("E4  ('interior_completeness', completeness) still in raw_sections source (validator compat)",
      '("interior_completeness", completeness)' in comp_src)

# Validate ordering: interior_completeness appears before wow_directive in source
ic_pos = comp_src.find('("interior_completeness", completeness)')
wow_pos = comp_src.find('("wow_directive", wow_block)')
check("E5  interior_completeness listed before wow_directive in raw_sections (ordering preserved)",
      0 < ic_pos < wow_pos, f"ic_pos={ic_pos} wow_pos={wow_pos}")

# build_interior_completeness_rule still imported (used in non-DNA path)
check("E6  build_interior_completeness_rule still imported in composer",
      "build_interior_completeness_rule" in comp_src)

# DNA path changes documented
check("E7  DNA path comment explains Wave 4.6.0 completeness change",
      "Wave 4.6.0: completeness" in comp_src or "Wave 4.6.0: DNA handles richness" in comp_src)


# ── Suite F: Rendered prompts — photo-first improvements end-to-end ──────────
print("\n=== Suite F: Rendered prompts — photo-first verification ===")

logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS
logging.disable(logging.CRITICAL)

room_desc = "A bright living room with oak floors, large west-facing windows, and a sofa."

# FIRST_VISION — DNA path
p_sl = compose_generation_prompt("Soft Luxury · Gold", "living room", room_desc, "", 1, [])
p_zen = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc, "", 1, [])
p_wm = compose_generation_prompt("Warm Modern · Oat", "living room", room_desc, "", 1, [])

# FIRST_VISION — non-DNA path. Wave 4.8.1b note: "Japandi · Harmony" now
# correctly resolves to japandi_calm DNA (the prior non-DNA result was the
# label→DNA-id bug). Use a genuinely-unregistered atmosphere to exercise the
# real non-DNA fallback path.
p_nondna = compose_generation_prompt("Custom Theme · Studio", "home office", room_desc, "", 1, [])

# STYLE_REFINEMENT path — must be unaffected
history_v2 = [
    {"role": "user", "content": "I want Soft Luxury"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer"},
]
p_sr = compose_generation_prompt("Soft Luxury · Gold", "living room", room_desc, "warmer", 2, history_v2)

# ROOM LOCK gone from all FV prompts
check("F1  FV (Soft Luxury) has NO 'ROOM LOCK'",
      "ROOM LOCK" not in p_sl)
check("F2  FV (Zen Retreat) has NO 'ROOM LOCK'",
      "ROOM LOCK" not in p_zen)
check("F3  FV has NO 'TV wall or fireplace position'",
      "TV wall or fireplace position" not in p_sl)

# Restyling task framing
check("F4  FV (Zen) contains 'preserve this living room's'",
      "preserve this living room" in p_zen)
check("F5  FV (Zen) contains 'Restyle only'",
      "Restyle only" in p_zen)
check("F6  FV (Zen) does NOT contain 'reproduce this living room'",
      "reproduce this living room" not in p_zen)

# interior_completeness removed from DNA path
check("F7  FV (Soft Luxury DNA) has NO 'never sparse'",
      "never sparse" not in p_sl)
check("F8  FV (Warm Modern DNA) has NO 'never sparse'",
      "never sparse" not in p_wm)

# No element checklist in any FV prompt
check("F9  FV (DNA path) has NO 'COMPLETE THE SCENE'",
      "COMPLETE THE SCENE" not in p_sl)
check("F10 FV (non-DNA path) has NO 'COMPLETE THE SCENE'",
      "COMPLETE THE SCENE" not in p_nondna)
check("F11 FV (non-DNA path) still has 'QUALITY:' (quality note preserved)",
      "QUALITY:" in p_nondna)

# STYLE_REFINEMENT path unaffected
check("F12 SR path still contains 'TOPOLOGY LOCKED' (unaffected)",
      "TOPOLOGY LOCKED" in p_sr)
check("F13 SR path still contains 'SAME APARTMENT — ATMOSPHERE SWITCH' (unaffected)",
      "SAME APARTMENT — ATMOSPHERE SWITCH" in p_sr)

# Core quality signals still present on FV DNA path
check("F14 FV (Zen) still contains 'TRANSFORMATION AMBITION' (wow_directive intact)",
      "TRANSFORMATION AMBITION" in p_zen)
check("F15 FV (Zen) still contains 'CAMERA LOCK'",
      "CAMERA LOCK" in p_zen)
check("F16 FV (Zen) still contains 'NOT a CGI render' (compact_realism intact)",
      "NOT a CGI render" in p_zen or "not a CGI render" in p_zen.lower())
check("F17 FV (Zen) still contains 'SAME APARTMENT'",
      "SAME APARTMENT" in p_zen)

# Budget compliance
fv_budget = _MODE_BUDGETS["FIRST_VISION"]
check(f"F18 FV (Soft Luxury) within budget ({fv_budget})",
      len(p_sl) <= fv_budget, f"got {len(p_sl)}")
check(f"F19 FV (Zen) within budget ({fv_budget})",
      len(p_zen) <= fv_budget, f"got {len(p_zen)}")
check(f"F20 FV (non-DNA) within budget ({fv_budget})",
      len(p_nondna) <= fv_budget, f"got {len(p_nondna)}")


# ── Suite G: Regression — prior wave vocabulary and system integrity ──────────
print("\n=== Suite G: Regression — prior waves and system integrity ===")

# Wave 4.5.1 — restyling wow directive intact
from prompt_engine.wow_layer import build_restyling_wow_directive, build_first_vision_wow_directive

wow_r = build_restyling_wow_directive()
check("G1  build_restyling_wow_directive() has 'TRANSFORMATION AMBITION'",
      "TRANSFORMATION AMBITION" in wow_r)
check("G2  build_restyling_wow_directive() has 'Decorate this photo'",
      "Decorate this photo" in wow_r)
check("G3  build_first_vision_wow_directive() unchanged (backward compat)",
      "TRANSFORMATION AMBITION" in build_first_vision_wow_directive())

# Wave 4.5.0 — simplified contract backward compat
from prompt_engine.preservation import (
    build_structural_contract,
    _CAMERA_LOCK, _STRUCTURAL_LOCK, _ATMOSPHERE_BOUNDARY,
)
check("G4  build_structural_contract() (Tier 1) still intact",
      "CAMERA LOCK" in build_structural_contract("living room") and
      len(build_structural_contract("living room")) >= 1400)
check("G5  _CAMERA_LOCK exported (backward compat)",
      isinstance(_CAMERA_LOCK, str) and len(_CAMERA_LOCK) > 200)
check("G6  _STRUCTURAL_LOCK exported (backward compat)",
      isinstance(_STRUCTURAL_LOCK, str) and "unblocked" in _STRUCTURAL_LOCK.lower())

# Wave 4.5.1 — DNA STYLE key
from prompt_engine.atmosphere_dna import build_dna_block
sl_lr_dna = get_room_dna("soft_luxury", "living_room")
if sl_lr_dna:
    dna_text = build_dna_block(sl_lr_dna)
    check("G7  DNA block still has 'ATMOSPHERE STYLE (restyle existing elements)'",
          "ATMOSPHERE STYLE (restyle existing elements)" in dna_text)
    check("G8  DNA block still has material palette (not compressed)",
          "marble" in dna_text.lower() or "bouclé" in dna_text.lower())
    check("G9  DNA block does NOT have 'STYLE: deep curved bouclé sofa' (old form gone)",
          "STYLE: deep curved bouclé sofa" not in dna_text)

# Wave 4.3.3 — task framing regression (validate_wave433.py full regression)
p_fv_zen_r = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc, "", 1, [])
check("G10 FV still contains 'SAME APARTMENT' (W433 C1)",
      "SAME APARTMENT" in p_fv_zen_r)
check("G11 FV still contains 'spatial truth' (W433 C2)",
      "spatial truth" in p_fv_zen_r)
check("G12 FV still contains 'STRUCTURAL LOCK' (W433 C6)",
      "STRUCTURAL LOCK" in p_fv_zen_r)
check("G13 FV does NOT contain 'TOPOLOGY LOCKED' (W433 C11)",
      "TOPOLOGY LOCKED" not in p_fv_zen_r)

# Wave 4.2.4 — retry classifier and generation profiles
from retry_classifier import classify_for_retry, RetryVerdict, RetryDecision
from generation_profiles import get_active_profile, _PROFILES

check("G14 classify_for_retry still importable", callable(classify_for_retry))
p_prod = _PROFILES["prod"]
p_dev  = _PROFILES["dev"]
check("G15 PROD max_attempts=3 unchanged", p_prod.max_attempts == 3)
check("G16 DEV compact_prompts=True unchanged", p_dev.compact_prompts is True)

# DEV compact mode — completeness still empty even in compact (compact skips all P4+)
p_dev_compact = compose_generation_prompt(
    "Soft Luxury · Gold", "living room", room_desc, "", 1, [], compact_prompts=True
)
check("G17 DEV compact still contains 'SAME APARTMENT' (P1 never dropped)",
      "SAME APARTMENT" in p_dev_compact)
check("G18 DEV compact has NO 'never sparse' (completeness empty + compact skips P5)",
      "never sparse" not in p_dev_compact)

# max_retries=0 in main.py
with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
check("G19 max_retries=0 still in main.py (cost protection)",
      "max_retries=0" in main_src)

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
  WAVE 4.6.0 — CORE PRODUCT SIMPLIFICATION SUMMARY:

  Change                          | Before                          | After
  --------------------------------|---------------------------------|----------------------------------
  DNA furniture_language (LR/MB)  | Specific pieces (replace)       | Material/texture vocab (restyle)
  build_simplified_fv_contract()  | Includes ROOM LOCK (~127 chars) | Returns _SAME_APARTMENT_V2 only
  build_first_vision_task()       | "reproduce... Then transform"   | "preserve... Restyle only"
  build_scene_completion()        | COMPLETE THE SCENE: include...  | QUALITY: [atmosphere note] only
  interior_completeness (DNA path)| "never sparse, empty..."        | "" (empty, filtered by budget)

  NET EFFECT:
  - All 5 composition-authoritative instructions that contradicted photo-first philosophy removed
  - DNA is now RESTYLING DNA: describes how to restyle, not what furniture to place
  - Photo-first philosophy consistently applied: uploaded furniture/composition is preserved
  - All luxury quality signals (WOW, DNA materials/lighting, compact_realism) intact
  - Prompt size reduced by ~127 chars (ROOM LOCK) + ~110 chars (interior_completeness)
""")
