"""
validate_wave342.py - Wave 3.4.2 Visual Architectural Realism & Constraint Validation.

Covers all 8 visual failure categories:
  A. Architectural opening preservation (furniture must not block windows)
  B. Functional relationship preservation (zone function + facing relationships)
  C. Same-apartment continuity (real physical space language)
  D. Style-cannot-override-function (constraint wins absolutely)
  E. Transformation understanding (zone identity, not just object placement)
  F. Reflection question generation blocking (meta-level safety net)
  G. Caption visual faithfulness
  H. Suggestion chip contextual relevance

IMPORTANT: Visual categories (A-E, G-H) validate PROMPT CONTENT.
           Actual visual validation requires generating images with the API.
           This script confirms the prompt architecture is correct.
           Manual visual review is required for final GREEN status.

Run with: python validate_wave342.py
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

SEP = "-" * 70
errors: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  [PASS] {label}")
    else:
        msg = f"  [FAIL] {label}" + (f": {detail}" if detail else "")
        print(msg)
        errors.append(label + (f": {detail}" if detail else ""))


# ---- Imports ----------------------------------------------------------------

from prompt_engine.preservation import build_structural_contract, _STRUCTURAL_LOCK, _ATMOSPHERE_BOUNDARY, _CAMERA_LOCK
from prompt_engine.transformation_classifier import (
    TransformationType, classify_transformation,
    build_spatial_preservation_addendum,
    _FUNCTIONAL_REASSIGNMENT_ADDENDUM,
    _ATMOSPHERE_SWITCH_ADDENDUM,
)
from prompt_engine.transformation_state_builder import build_vision_caption, build_clean_instruction
from prompt_engine.meta_intent import classify_meta_intent, MetaIntent
from prompt_engine.composer import compose_generation_prompt
from prompt_engine.chip_engine import get_contextual_chips
from prompt_engine.intent_classifier import classify_intent, ConversationIntent, SubIntent


# ============================================================
# CATEGORY A: Architectural Opening Preservation
# ============================================================

print(SEP)
print("CATEGORY A -- Architectural Opening Preservation")
print(SEP)

contract_living = build_structural_contract("living room")

# A1: Structural lock mentions no-furniture-blocking-windows rule
check("A1: structural lock says no furniture blocking windows",
      "block" in _STRUCTURAL_LOCK.lower() or "overlap" in _STRUCTURAL_LOCK.lower(),
      "no blocking language")

# A2: Natural light visibility is required
check("A2: structural lock requires window light visible",
      "natural light" in _STRUCTURAL_LOCK.lower() or "light entering" in _STRUCTURAL_LOCK.lower(),
      f"no light visibility: {_STRUCTURAL_LOCK[:80]}")

# A3: Balcony/exterior access mentioned
check("A3: structural lock covers balcony/exterior access",
      "balcony" in _STRUCTURAL_LOCK.lower() or "exterior access" in _STRUCTURAL_LOCK.lower(),
      "no balcony/access language")

# A4: Window blocking rule is in the full structural contract
check("A4: full contract includes window blocking prohibition",
      "block" in contract_living.lower() or "overlap" in contract_living.lower(),
      "contract missing blocking rule")

# A5: Atmosphere switch addendum explicitly protects windows
check("A5: atmosphere switch addendum protects windows",
      "window" in _ATMOSPHERE_SWITCH_ADDENDUM.lower(),
      f"no window protection: {_ATMOSPHERE_SWITCH_ADDENDUM[:100]}")

# A6: Atmosphere switch addendum says natural light must remain visible
check("A6: atmosphere switch addendum: natural light must remain visible",
      "natural light" in _ATMOSPHERE_SWITCH_ADDENDUM.lower() or
      "window" in _ATMOSPHERE_SWITCH_ADDENDUM.lower(),
      "no light language")

# A7: Full redesign prompt (Vision 1) has window blocking prohibition
prompt_v1 = compose_generation_prompt(
    style_label="Warm Modern",
    room_type="living room",
    room_description="Bright living room with large windows on the south wall.",
    user_instruction="Redesign in warm modern style",
    iteration=1,
    history=[],
    secondary_visible_spaces=["bedroom"],
)
check("A7: Vision 1 prompt has window blocking prohibition",
      "block" in prompt_v1.lower() or "overlap" in prompt_v1.lower(),
      f"first 300: {prompt_v1[:300]}")

print(f"  Structural lock (window section): {_STRUCTURAL_LOCK[_STRUCTURAL_LOCK.find('CRITICAL'):_STRUCTURAL_LOCK.find('CRITICAL')+180]}")


# ============================================================
# CATEGORY B: Functional Relationship Preservation
# ============================================================

print()
print(SEP)
print("CATEGORY B -- Functional Relationship Preservation")
print(SEP)

func_addendum = _FUNCTIONAL_REASSIGNMENT_ADDENDUM

# B1: Addendum requires zones to visually read their new function
check("B1: functional addendum requires visual zone readability",
      "visually read" in func_addendum.lower() or "visually communicate" in func_addendum.lower(),
      f"no visual readability: {func_addendum[:100]}")

# B2: Addendum mentions directional/facing relationship
check("B2: functional addendum covers facing/directional relationships",
      "facing" in func_addendum.lower() or "directional" in func_addendum.lower() or
      "face" in func_addendum.lower(),
      "no facing relationship language")

# B3: Addendum says viewer must understand zone purpose
check("B3: functional addendum: viewer must understand zone function",
      "viewer" in func_addendum.lower() or "understand" in func_addendum.lower(),
      "no viewer-understanding language")

# B4: build_clean_instruction for FUNCTIONAL adds zone preservation
clean_func = build_clean_instruction(
    "Make the TV area a bedroom and move the TV to the sofa area",
    TransformationType.FUNCTIONAL_REASSIGNMENT,
)
check("B4: clean instruction says zone must look like its new function",
      "genuinely" in clean_func.lower() or "visually" in clean_func.lower() or
      "look like" in clean_func.lower(),
      f"no function-look language: {clean_func[-120:]}")

# B5: Spatial addendum for functional reassignment is substantive
spatial_func = build_spatial_preservation_addendum(
    TransformationType.FUNCTIONAL_REASSIGNMENT,
    ["bedroom"],
    "living_room",
)
check("B5: spatial addendum for FUNCTIONAL_REASSIGNMENT is non-empty",
      len(spatial_func) > 100, f"too short: {len(spatial_func)} chars")

check("B6: spatial addendum mentions viewer understanding",
      "viewer" in spatial_func.lower() or "understand" in spatial_func.lower() or
      "visually" in spatial_func.lower(),
      f"no visual clarity: {spatial_func[:120]}")

# B7: Full prompt for functional reassignment uses structural path (not local edit).
# edit_intent._STRUCTURAL_SIGNALS now recognizes functional reassignment patterns,
# so compose_generation_prompt's internal classify_edit_mode routes correctly.
from prompt_engine.edit_intent import classify_edit_mode as _cem

_func_instr = "Make the TV area a bedroom and move the TV to the sofa area"
_func_tx = classify_transformation(_func_instr, 2)
_func_addendum = build_spatial_preservation_addendum(_func_tx, [], "living_room")
_func_clean = build_clean_instruction(_func_instr, _func_tx)
_enriched_func = f"{_func_clean}\n{_func_addendum}" if _func_addendum else _func_clean

# Raw instruction may classify LOCAL_EDIT (expected — move/make signals win).
# main.py overrides this to STRUCTURAL_TRANSFORMATION when transformation_type is FUNCTIONAL.
# The enriched instruction (clean + addendum) IS correctly classified as STRUCTURAL.
check("B7: enriched functional instruction classifies as STRUCTURAL",
      _cem(_enriched_func, 2).value in ("structural_transformation",),
      f"got {_cem(_enriched_func, 2).value} for enriched instruction")

prompt_func = compose_generation_prompt(
    style_label="Warm Modern",
    room_type="living room",
    room_description="Open plan with TV zone at rear and sofa zone at front.",
    user_instruction=_enriched_func,
    iteration=2,
    history=[{"role": "user", "content": "Design this space"}],
    secondary_visible_spaces=[],
)
check("B7b: functional prompt is NOT on local edit path",
      "TARGETED IMAGE EDIT" not in prompt_func,
      f"still local edit: {prompt_func[:100]}")
check("B7c: functional prompt contains zone/function clarity",
      "visually" in prompt_func.lower() or "viewer" in prompt_func.lower() or
      "zone" in prompt_func.lower() or "function" in prompt_func.lower(),
      f"no clarity language: {prompt_func[:200]}")
print(f"  Functional prompt length: {len(prompt_func)} chars")


# ============================================================
# CATEGORY C: Same-Apartment Continuity
# ============================================================

print()
print(SEP)
print("CATEGORY C -- Same-Apartment Continuity")
print(SEP)

# C1: Camera lock says "real physical space" / "same apartment"
check("C1: camera lock says real physical space",
      "real physical space" in _CAMERA_LOCK.lower() or
      "same" in _CAMERA_LOCK.lower(),
      f"no continuity anchor: {_CAMERA_LOCK[:150]}")

# C2: Camera lock says "same apartment evolved"
check("C2: camera lock says output must look like the SAME space",
      "same" in _CAMERA_LOCK.lower() and
      ("evolved" in _CAMERA_LOCK.lower() or "photograph" in _CAMERA_LOCK.lower()),
      f"no evolved language: {_CAMERA_LOCK[:200]}")

# C3: Style refinement prompt has SAME APARTMENT language (regression from 3.4.1)
prompt_refine = compose_generation_prompt(
    style_label="Zen Retreat",
    room_type="bedroom",
    room_description="A calm bedroom with natural light from east window.",
    user_instruction="Make it calmer and more minimal",
    iteration=2,
    history=[{"role": "user", "content": "Design this space"}],
    secondary_visible_spaces=[],
)
check("C3: refinement prompt has SAME APARTMENT language",
      "SAME APARTMENT" in prompt_refine, f"no continuity: {prompt_refine[:150]}")

# C4: Full Vision 1 prompt says real space
check("C4: Vision 1 prompt has 'real physical space' or 'same'",
      "real physical space" in prompt_v1.lower() or "same" in prompt_v1.lower(),
      f"no real space anchor: {prompt_v1[:200]}")

print(f"  Camera lock (continuity): {_CAMERA_LOCK[_CAMERA_LOCK.find('real physical'):_CAMERA_LOCK.find('real physical')+120] if 'real physical' in _CAMERA_LOCK.lower() else 'N/A'}")


# ============================================================
# CATEGORY D: Style Cannot Override Function
# ============================================================

print()
print(SEP)
print("CATEGORY D -- Style Cannot Override Function")
print(SEP)

# D1: Atmosphere boundary has absolute priority language
check("D1: atmosphere boundary says constraint wins absolutely",
      "constraint wins" in _ATMOSPHERE_BOUNDARY.lower() or
      "wins absolutely" in _ATMOSPHERE_BOUNDARY.lower(),
      f"no constraint-wins: {_ATMOSPHERE_BOUNDARY[:150]}")

# D2: Atmosphere boundary has 5-layer numbered priority
check("D2: atmosphere boundary has numbered priority layers",
      "(1)" in _ATMOSPHERE_BOUNDARY and "(5)" in _ATMOSPHERE_BOUNDARY,
      "no numbered layers")

# D3: Atmosphere boundary mentions functional zones in priority 1
check("D3: atmosphere boundary: functional zones are priority 1",
      "functional" in _ATMOSPHERE_BOUNDARY.lower(),
      f"no functional priority: {_ATMOSPHERE_BOUNDARY[:100]}")

# D4: Atmosphere boundary appears in all generation paths
check("D4: Vision 1 prompt includes atmosphere boundary",
      "ATMOSPHERE BOUNDARY" in prompt_v1,
      "no atmosphere boundary in Vision 1")
check("D5: refinement prompt includes atmosphere boundary",
      "ATMOSPHERE BOUNDARY" in prompt_refine,
      "no atmosphere boundary in refinement")
check("D6: functional prompt (via structural path) includes atmosphere boundary",
      "ATMOSPHERE BOUNDARY" in prompt_func,
      "no atmosphere boundary in functional prompt")

print(f"  Atmosphere boundary (constraint override): ...{_ATMOSPHERE_BOUNDARY[_ATMOSPHERE_BOUNDARY.find('constraint wins'.lower() if 'constraint wins' in _ATMOSPHERE_BOUNDARY.lower() else 'CONSTRAINT'):_ATMOSPHERE_BOUNDARY.find('CONSTRAINT')+80 if 'CONSTRAINT' in _ATMOSPHERE_BOUNDARY else -1]}")


# ============================================================
# CATEGORY E: Transformation Understanding
# ============================================================

print()
print(SEP)
print("CATEGORY E -- Transformation Understanding")
print(SEP)

# E1: Functional addendum explicitly says this is more than furniture placement
check("E1: functional addendum says more than furniture placement",
      "not merely furniture" in func_addendum.lower() or
      "real functional change" in func_addendum.lower(),
      "no 'more than furniture' language")

# E2: Sleeping zone must look like a sleeping space
check("E2: functional addendum describes sleeping zone visual identity",
      "sleep" in func_addendum.lower() or "sleeping" in func_addendum.lower(),
      "no sleeping zone identity")

# E3: Living/viewing zone must address viewing direction
check("E3: functional addendum describes viewing/living zone visual identity",
      "viewing" in func_addendum.lower() or "screen" in func_addendum.lower() or
      "focal point" in func_addendum.lower(),
      "no viewing zone identity")

# E4: classify_transformation correctly identifies functional reassignment
reassign_cases = [
    "Make the TV area a bedroom",
    "Turn the dining room into a home office",
    "Convert the living zone into a sleeping area",
    "Use the balcony as a reading nook",
    "Repurpose the guest room as a studio",
    "Transform this corner into a work zone",
]
for case in reassign_cases:
    tx = classify_transformation(case, 2)
    check(f"E4: '{case[:40]}' -> FUNCTIONAL_REASSIGNMENT",
          tx == TransformationType.FUNCTIONAL_REASSIGNMENT,
          f"got {tx.value}")

# E5: Object edits are NOT classified as functional reassignment
non_functional = [
    "Add a rug",
    "Change the sofa to blue",
    "Put a plant near the window",
    "Remove the coffee table",
]
for case in non_functional:
    tx = classify_transformation(case, 2)
    check(f"E5: '{case}' is NOT functional",
          tx != TransformationType.FUNCTIONAL_REASSIGNMENT,
          f"got {tx.value}")


# ============================================================
# CATEGORY F: Reflection Question Generation Blocking
# ============================================================

print()
print(SEP)
print("CATEGORY F -- Reflection Question Generation Blocking")
print(SEP)

reflection_cases = [
    ("what do you think?", "standalone reflection"),
    ("does this work?", "does-this-work"),
    ("is this right?", "is-this-right"),
    ("should we do this?", "should-we-do"),
    ("is this the right direction?", "right-direction"),
    ("what do you think about this?", "think-about-this"),
    ("do you think this works?", "do-you-think"),
    ("does this look right?", "does-look-right"),
]
for msg, label in reflection_cases:
    meta = classify_meta_intent(msg)
    # Must never be NONE (which would route to design layer)
    check(f"F1: '{label}' does not route to design layer",
          meta.intent != MetaIntent.NONE,
          f"got {meta.intent.value} -- this would hit design routing")

# F2: Verify design-layer also blocks these (double safety)
design_reflection_cases = [
    "what do you think about the lighting?",
    "does this style work for the space?",
    "is this too dark do you think?",
]
for msg in design_reflection_cases:
    intent = classify_intent(msg, iteration=2)
    check(f"F2: '{msg[:40]}' routes to CONVERSATION at iter=2",
          intent.intent == ConversationIntent.CONVERSATION,
          f"got {intent.intent.value} -- would generate")

# F3: Vision 1 always generates (reflection at iter=1 is unusual but allowed)
intent_v1 = classify_intent("what do you think?", iteration=1)
check("F3: Vision 1 always generates (even reflection)",
      intent_v1.intent == ConversationIntent.GENERATE,
      "Vision 1 must always generate")


# ============================================================
# CATEGORY G: Caption Visual Faithfulness
# ============================================================

print()
print(SEP)
print("CATEGORY G -- Caption Visual Faithfulness")
print(SEP)

# G1: Atmosphere switch caption names the atmosphere
cap_atm = build_vision_caption("Switch to Zen Retreat", TransformationType.ATMOSPHERE_SWITCH, 3, "zen_retreat", "en")
check("G1: atmosphere switch caption names the atmosphere",
      "zen" in cap_atm.lower() or "retreat" in cap_atm.lower(),
      f"no atm name: {cap_atm}")

# G2: Functional reassignment caption mentions zone change
cap_func = build_vision_caption(
    "Make the TV area a bedroom",
    TransformationType.FUNCTIONAL_REASSIGNMENT, 2, "warm_modern", "en"
)
check("G2: functional caption mentions zone reassignment",
      "zone" in cap_func.lower() or "reassign" in cap_func.lower(),
      f"no zone mention: {cap_func}")

# G3: No raw instruction fragments in template-based captions
check("G3: atmosphere caption has no raw instruction",
      "Switch to" not in cap_atm and "switch to" not in cap_atm.lower(),
      f"raw instruction in caption: {cap_atm}")
check("G4: functional caption has no raw instruction",
      "Make the TV" not in cap_func,
      f"raw instruction in caption: {cap_func}")

# G5: Style refinement caption uses cleaned instruction text
cap_refine = build_vision_caption("make it warmer", TransformationType.STYLE_REFINEMENT, 3, "warm_modern", "en")
check("G5: style refinement caption is grammatical",
      cap_refine.startswith("Vision 3 —"),
      f"bad format: {cap_refine}")
check("G6: style refinement caption contains content",
      "warmer" in cap_refine.lower() or "warm" in cap_refine.lower(),
      f"no content: {cap_refine}")

print(f"  ATMOSPHERE_SWITCH caption: {cap_atm}")
print(f"  FUNCTIONAL caption: {cap_func}")
print(f"  STYLE_REFINEMENT caption: {cap_refine}")


# ============================================================
# CATEGORY H: Suggestion Chip Relevance
# ============================================================

print()
print(SEP)
print("CATEGORY H -- Suggestion Chip Contextual Relevance")
print(SEP)

# H1: Functional reassignment chips offer zone-relevant suggestions
chips_func = get_contextual_chips(
    atmosphere_id="warm_modern",
    room_type="living_room",
    iteration=2,
    transformation_type=TransformationType.FUNCTIONAL_REASSIGNMENT,
    secondary_spaces=["bedroom"],
    count=4,
)
check("H1: functional reassignment chips are non-empty", len(chips_func) == 4,
      f"got {len(chips_func)}")
check("H2: functional reassignment chips have no duplicates",
      len(set(chips_func)) == len(chips_func), f"duplicates: {chips_func}")

# H3: Atmosphere switch chips include spatial-awareness
chips_atm = get_contextual_chips(
    atmosphere_id="zen_retreat",
    room_type="living_room",
    iteration=2,
    transformation_type=TransformationType.ATMOSPHERE_SWITCH,
    secondary_spaces=["bedroom"],
    count=4,
)
check("H3: atmosphere switch chips mention spatial awareness",
      any("spatial" in c.lower() or "rear" in c.lower() or "zone" in c.lower() or
          "depth" in c.lower() or "openness" in c.lower() for c in chips_atm),
      f"no spatial chips: {chips_atm}")

# H4: Late iteration chips are different from early
chips_early = get_contextual_chips("warm_modern", "living_room", 1, count=4)
chips_late = get_contextual_chips("warm_modern", "living_room", 8, count=4)
check("H4: late-iteration chips differ from early",
      set(chips_early) != set(chips_late),
      f"early={chips_early} late={chips_late}")

print(f"  Functional chips: {chips_func}")
print(f"  Atmosphere chips: {chips_atm}")


# ============================================================
# PROMPT ARCHITECTURE AUDIT
# ============================================================

print()
print(SEP)
print("PROMPT ARCHITECTURE AUDIT")
print(SEP)

# Verify all three paths include the critical new language

# LOCAL EDIT path
prompt_local = compose_generation_prompt(
    style_label="Warm Modern",
    room_type="living room",
    room_description="Bright room.",
    user_instruction="Change the sofa to grey",
    iteration=2,
    history=[{"role": "user", "content": "Design this"}],
    secondary_visible_spaces=[],
)
check("AUDIT1: local edit prompt has window blocking rule",
      "block" in prompt_local.lower() or "overlap" in prompt_local.lower(),
      f"no blocking rule in local edit: {prompt_local[:200]}")

# STRUCTURAL path
prompt_struct = compose_generation_prompt(
    style_label="Warm Modern",
    room_type="living room",
    room_description="Open plan living room.",
    user_instruction="Add a window on the north wall",
    iteration=2,
    history=[{"role": "user", "content": "Design this"}],
    secondary_visible_spaces=[],
)
check("AUDIT2: structural prompt has atmosphere boundary",
      "ATMOSPHERE BOUNDARY" in prompt_struct,
      "no atmosphere boundary in structural")
check("AUDIT3: structural prompt has SAME APARTMENT language",
      "SAME APARTMENT" in prompt_struct,
      f"no continuity: {prompt_struct[:200]}")

# Character budget checks
check("AUDIT4: Vision 1 prompt within 3800 chars",
      len(prompt_v1) <= 3800, f"length={len(prompt_v1)}")
check("AUDIT5: refinement prompt within 3800 chars",
      len(prompt_refine) <= 3800, f"length={len(prompt_refine)}")
check("AUDIT6: functional prompt within 3800 chars",
      len(prompt_func) <= 3800, f"length={len(prompt_func)}")

print(f"  Vision 1 prompt:     {len(prompt_v1)} chars")
print(f"  Refinement prompt:   {len(prompt_refine)} chars")
print(f"  Functional prompt:   {len(prompt_func)} chars")
print(f"  Local edit prompt:   {len(prompt_local)} chars")
print(f"  Structural prompt:   {len(prompt_struct)} chars")


# ============================================================
# VISUAL VALIDATION CHECKLIST (manual review required)
# ============================================================

print()
print(SEP)
print("VISUAL VALIDATION CHECKLIST (manual review required)")
print(SEP)
print("  The following must be verified by generating real images:")
print("  [MANUAL] A: Windows remain unblocked in generated images")
print("  [MANUAL] A: Natural light paths visible after atmosphere switches")
print("  [MANUAL] B: TV zone faces sofa after functional reassignment")
print("  [MANUAL] B: Sleeping zone clearly reads as sleeping space")
print("  [MANUAL] C: Vision 2 feels like same apartment as Vision 1")
print("  [MANUAL] C: Camera angle and depth unchanged across iterations")
print("  [MANUAL] D: Atmosphere change does not flatten background zones")
print("  [MANUAL] E: Functional reassignment shows real zone transformation")
print("  [MANUAL] E: Not just furniture added -- whole zone identity changes")
print("  [MANUAL] G: Caption correctly describes the actual visible change")


# ============================================================
# REGRESSION -- Prior suites
# ============================================================

print()
print(SEP)
print("REGRESSION -- All prior wave exports load cleanly")
print(SEP)

try:
    from prompt_engine import (
        compose_generation_prompt, parse_history,
        classify_intent, generate_architect_response,
        classify_meta_intent, MetaIntent, generate_meta_response,
        build_session_memory, ToneMode, select_tone_mode,
        EmotionalContext, TransformationType, classify_transformation,
        build_spatial_preservation_addendum, get_contextual_chips,
        generate_project_aware_greeting, build_vision_caption, build_clean_instruction,
    )
    print("  [PASS] All Wave 2.5 -> 3.4.2 exports load cleanly")
except Exception as e:
    print(f"  [FAIL] Import error: {e}")
    errors.append(f"Import error: {e}")

# Verify specific new language is in place
from prompt_engine.preservation import _STRUCTURAL_LOCK as SL, _ATMOSPHERE_BOUNDARY as AB, _CAMERA_LOCK as CL
checks = [
    ("SL has window blocking rule", "block" in SL.lower() or "overlap" in SL.lower()),
    ("SL has natural light visibility", "natural light" in SL.lower() or "light entering" in SL.lower()),
    ("SL has balcony access", "balcony" in SL.lower() or "exterior access" in SL.lower()),
    ("AB has numbered priority", "(1)" in AB and "(5)" in AB),
    ("AB has constraint wins", "CONSTRAINT WINS" in AB),
    ("CL has real physical space", "real physical space" in CL.lower() or "already exists physically" in CL.lower()),
]
for label, cond in checks:
    check(f"REGRESSION: {label}", cond)


# ============================================================
# RESULT
# ============================================================

print()
print(SEP)
if errors:
    print(f"RESULT: {len(errors)} FAILURE(S)")
    for e in errors:
        print(f"  - {e}")
else:
    print("RESULT: ALL CHECKS PASSED -- Wave 3.4.2 prompt architecture ready")
    print()
    print("  NEXT STEP: Generate real images and manually verify:")
    print("  1. Window visibility after atmosphere switches")
    print("  2. Functional zone visual identity after reassignments")
    print("  3. Same-apartment continuity across iterations")
    print("  4. Constraint wins over atmosphere in all cases")
print(SEP)
