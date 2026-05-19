"""
validate_wave341.py — Wave 3.4.1 Final Continuity Stabilization validation.

Covers all 11 acceptance criteria:
  A. Greeting context continuity
  B. Multi-space preservation
  C. Atmosphere boundary (structure-first priority)
  D. Iteration continuity language
  E. Functional reassignment
  F. Response naturalness (no jargon)
  G. Response length
  H. Suggestion chip quality
  I. Language persistence
  J. Vision caption cleanup
  K. Transformation state extraction

Run with: python validate_wave341.py
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


# ── Import all modules ────────────────────────────────────────────────────────
from prompt_engine.conversation_memory import build_session_memory, SessionMemory
from prompt_engine.meta_intent import classify_meta_intent, MetaIntent, MetaClassification
from prompt_engine.meta_response import generate_meta_response, generate_project_aware_greeting
from prompt_engine.transformation_classifier import (
    TransformationType, classify_transformation, build_spatial_preservation_addendum,
)
from prompt_engine.transformation_state_builder import build_vision_caption, build_clean_instruction
from prompt_engine.preservation import build_structural_contract
from prompt_engine.edit_intent import build_style_refinement_header, build_structural_transformation_header
from prompt_engine.chip_engine import get_contextual_chips
from prompt_engine.architect_response import generate_architect_response, generate_chat_response
from prompt_engine.intent_classifier import SubIntent
from prompt_engine.edit_intent import EditMode
from prompt_engine.refinement_memory import RefinementState


# ── Problem A: Greeting context continuity ────────────────────────────────────

print(SEP)
print("PROBLEM A — Greeting context continuity")
print(SEP)

# A1: Session memory uses atmosphere_id_hint when history is empty
mem_hint = build_session_memory([], "en", atmosphere_id_hint="warm_modern", room_type_hint="living_room")
check("A1: atmosphere hint applied", mem_hint.atmosphere_mentioned == "warm_modern",
      f"got {mem_hint.atmosphere_mentioned}")
check("A2: room hint applied", mem_hint.room_type_mentioned == "living_room",
      f"got {mem_hint.room_type_mentioned}")

# A3: History wins over hint
hist = [{"role": "user", "content": "I want a japandi bedroom"}]
mem_hist = build_session_memory(hist, "en", atmosphere_id_hint="warm_modern", room_type_hint="kitchen")
check("A3: history atmosphere wins over hint", mem_hist.atmosphere_mentioned == "japandi_calm",
      f"got {mem_hist.atmosphere_mentioned}")

# A4: Project-aware greeting when atmosphere_id_hint is present (iteration > 1 logic)
mc_greet = MetaClassification(MetaIntent.GREETING, "en", "en", 0.90)
mem_with_atm = SessionMemory(
    session_language="en",
    atmosphere_mentioned="warm_modern",
    room_type_mentioned="living_room",
    message_count=0,  # history empty, but hint filled it in
)
resp = generate_project_aware_greeting(mc_greet, mem_with_atm, "test")
check("A4: greeting references atmosphere", "warm" in resp.lower() or "modern" in resp.lower(),
      f"response: {resp}")
check("A5: greeting is short", len(resp.split(".")) <= 2, f"too long: {resp}")
print(f"  Greeting with context: {resp}")

# A6: Standard greeting (no context) doesn't say 'atmosphere'
mc_greet_no_ctx = MetaClassification(MetaIntent.GREETING, "en", "en", 0.90)
mem_empty = SessionMemory(session_language="en", message_count=0)
resp_std = generate_project_aware_greeting(mc_greet_no_ctx, mem_empty, "test")
check("A6: no-context greeting avoids reset language",
      "what atmosphere" not in resp_std.lower(),
      f"response: {resp_std}")
print(f"  Standard greeting (no context): {resp_std}")

# A7: FR greeting with project context
mc_greet_fr = MetaClassification(MetaIntent.GREETING, "fr", "fr", 0.90)
mem_fr = SessionMemory(
    session_language="fr",
    atmosphere_mentioned="japandi_calm",
    room_type_mentioned="bedroom",
    message_count=2,
)
resp_fr = generate_project_aware_greeting(mc_greet_fr, mem_fr, "test")
check("A7: FR greeting with context is non-empty", len(resp_fr) > 10, f"empty: {resp_fr}")
check("A8: FR greeting non-empty and relevant",
      "japandi" in resp_fr.lower() or "calm" in resp_fr.lower() or "chambre" in resp_fr.lower(),
      f"response: {resp_fr}")
print(f"  FR project-aware greeting: {resp_fr}")


# ── Problem B: Multi-space preservation ───────────────────────────────────────

print()
print(SEP)
print("PROBLEM B — Multi-space preservation")
print(SEP)

# B1: STYLE_REFINEMENT + secondary spaces now gets multi-space lock
addendum_style = build_spatial_preservation_addendum(
    TransformationType.STYLE_REFINEMENT,
    ["bedroom", "living_room"],
    "kitchen",
)
check("B1: STYLE_REFINEMENT gets multi-space lock",
      "MULTI-SPACE" in addendum_style or "TOPOLOGY" in addendum_style,
      f"no lock in: {addendum_style[:80]}")

# B2: UNKNOWN + secondary spaces now gets multi-space lock
addendum_unk = build_spatial_preservation_addendum(
    TransformationType.UNKNOWN,
    ["bedroom"],
    "kitchen",
)
check("B2: UNKNOWN gets multi-space lock",
      "MULTI-SPACE" in addendum_unk or "TOPOLOGY" in addendum_unk,
      f"no lock in: {addendum_unk[:80]}")

# B3: Multi-space lock includes depth/perspective language
addendum_full = build_spatial_preservation_addendum(
    TransformationType.ATMOSPHERE_SWITCH,
    ["bedroom"],
    "living_room",
)
check("B3: lock mentions depth", "depth" in addendum_full.lower(), "no 'depth'")
check("B4: lock mentions perspective", "perspective" in addendum_full.lower(), "no 'perspective'")
check("B5: lock says no flatten/compress",
      "flatten" in addendum_full.lower() or "compress" in addendum_full.lower(),
      "no anti-flatten language")
print(f"  Multi-space lock: {addendum_full[addendum_full.find('MULTI'):addendum_full.find('MULTI')+150]}...")

# B6: OBJECT_EDIT still excluded from multi-space lock (surgical edits)
addendum_obj = build_spatial_preservation_addendum(
    TransformationType.OBJECT_EDIT,
    ["bedroom"],
    "living_room",
)
check("B6: OBJECT_EDIT still excluded from multi-space lock",
      "MULTI-SPACE" not in addendum_obj and "TOPOLOGY" not in addendum_obj,
      f"has lock: {addendum_obj[:80]}")


# ── Problem C: Atmosphere boundary (structure-first) ──────────────────────────

print()
print(SEP)
print("PROBLEM C — Atmosphere boundary / structure-first")
print(SEP)

contract = build_structural_contract("living_room")
check("C1: structural contract includes atmosphere boundary",
      "ATMOSPHERE BOUNDARY" in contract, "no atmosphere boundary block")
check("C2: priority order present",
      "priority order" in contract.lower() or "First:" in contract,
      "no priority order")
check("C3: topology preserved before atmosphere",
      contract.index("ATMOSPHERE BOUNDARY") > contract.index("STRUCTURAL LOCK"),
      "atmosphere boundary appears before structural lock")
print(f"  Atmosphere boundary preview: ...{contract[-200:]}")


# ── Problem D: Iteration continuity language ──────────────────────────────────

print()
print(SEP)
print("PROBLEM D — Iteration continuity language")
print(SEP)

header = build_style_refinement_header("Make it warmer", "Warm Modern", "living room")
check("D1: refinement header says SAME APARTMENT",
      "SAME APARTMENT" in header, f"no continuity phrase: {header[:100]}")
check("D2: refinement header says not new generation",
      "NOT a new generation" in header or "not a new" in header.lower(),
      "no 'not new generation' language")
check("D3: refinement header preserves visible secondary spaces",
      "visible secondary spaces" in header or "secondary" in header,
      "no secondary space preservation language")
print(f"  Refinement header: {header[:200]}...")

struct_header = build_structural_transformation_header("Open up the kitchen", "Warm Modern", "kitchen")
check("D4: structural header says SAME APARTMENT",
      "SAME APARTMENT" in struct_header, f"no continuity phrase")
check("D5: structural header mentions visible zones",
      "visible zones" in struct_header.lower() or "secondary" in struct_header.lower(),
      "no visible zones mention")


# ── Problem E: Functional reassignment ────────────────────────────────────────

print()
print(SEP)
print("PROBLEM E — Functional reassignment")
print(SEP)

func_instruction = "Make the TV area a bedroom and move the TV to the sofa area."
clean = build_clean_instruction(func_instruction, TransformationType.FUNCTIONAL_REASSIGNMENT)
check("E1: functional clean instruction is non-empty", len(clean) > 10)
check("E2: functional instruction includes zone preservation",
      "preserve" in clean.lower() or "distinct" in clean.lower(),
      f"no preservation language: {clean[:100]}")
check("E3: functional instruction includes source instruction",
      "TV" in clean or "bedroom" in clean.lower(),
      f"lost original: {clean[:100]}")
print(f"  Functional clean instruction: {clean[:150]}...")

# E4: Functional reassignment detection
check("E4: functional reassignment detected",
      classify_transformation("Make the TV area a bedroom") == TransformationType.FUNCTIONAL_REASSIGNMENT)

# E5: Functional addendum has preservation language
addendum_func = build_spatial_preservation_addendum(
    TransformationType.FUNCTIONAL_REASSIGNMENT, [], "living_room"
)
check("E5: functional addendum has footprint language",
      "footprint" in addendum_func.lower(), "no footprint")


# ── Problem F: Response naturalness (no jargon) ───────────────────────────────

print()
print(SEP)
print("PROBLEM F — Response naturalness (jargon audit)")
print(SEP)

JARGON_WORDS = [
    "materially honest",
    "negative space",
    "atmospheric work",
    "primary anchor",
    "deepen the layering",
    "resolved",
    "register",
]

rs = RefinementState()
rs.latest = "Make it warmer"
arch_resp = generate_architect_response(
    atmosphere_id="warm_modern",
    room_type="living_room",
    iteration=2,
    edit_mode=EditMode.STYLE_REFINEMENT,
    refinement_state=rs,
    sub_intent=SubIntent.REFINE_ATMOSPHERE,
    secondary_spaces=[],
    user_message="Make it warmer",
)
print(f"  Architect response (style refine): {arch_resp}")
for jarg in JARGON_WORDS:
    check(f"F: no '{jarg}' in architect response",
          jarg.lower() not in arch_resp.lower(),
          f"found in: {arch_resp[:80]}")

# Chat response naturalness
chat_resp = generate_chat_response(
    user_message="What do you think?",
    atmosphere_id="japandi_calm",
    room_type="living_room",
    sub_intent=SubIntent.QUESTION,
    secondary_spaces=[],
    refinement_state=RefinementState(),
)
print(f"  Chat response (question): {chat_resp}")
check("F: no 'negative space' in chat",
      "negative space" not in chat_resp.lower(),
      f"found in: {chat_resp}")
check("F: no 'materially honest' in chat",
      "materially honest" not in chat_resp.lower(),
      f"found in: {chat_resp}")


# ── Problem G: Response length (mobile-appropriate) ───────────────────────────

print()
print(SEP)
print("PROBLEM G — Response length (mobile-appropriate)")
print(SEP)

# Vision 1 response
rs_v1 = RefinementState()
resp_v1 = generate_architect_response(
    atmosphere_id="warm_modern",
    room_type="living_room",
    iteration=1,
    edit_mode=EditMode.FIRST_VISION,
    refinement_state=rs_v1,
    sub_intent=SubIntent.REDESIGN,
    secondary_spaces=[],
    user_message="Design this space",
)
print(f"  Vision 1 response ({len(resp_v1)} chars): {resp_v1}")
check("G1: Vision 1 response under 220 chars", len(resp_v1) <= 220,
      f"length={len(resp_v1)}")
check("G2: Vision 1 has at most 2 sentences",
      resp_v1.count(".") + resp_v1.count("?") <= 3,
      f"too many sentences: {resp_v1}")

# Local edit response
rs_le = RefinementState()
rs_le.latest = "Add a floor lamp"
resp_le = generate_architect_response(
    atmosphere_id="warm_modern",
    room_type="living_room",
    iteration=2,
    edit_mode=EditMode.LOCAL_EDIT,
    refinement_state=rs_le,
    sub_intent=SubIntent.LOCAL_EDIT,
    secondary_spaces=[],
    user_message="Add a floor lamp",
)
print(f"  Local edit response ({len(resp_le)} chars): {resp_le}")
check("G3: Local edit response under 160 chars", len(resp_le) <= 160,
      f"length={len(resp_le)}")


# ── Problem H: Suggestion chip quality ────────────────────────────────────────

print()
print(SEP)
print("PROBLEM H — Suggestion chip quality")
print(SEP)

# H1: Atmosphere switch chips include depth/rear-room awareness
chips_atm = get_contextual_chips(
    atmosphere_id="zen_retreat",
    room_type="living_room",
    iteration=2,
    transformation_type=TransformationType.ATMOSPHERE_SWITCH,
    secondary_spaces=["bedroom"],
)
print(f"  ATMOSPHERE_SWITCH chips: {chips_atm}")
has_spatial = any(
    "rear" in c.lower() or "depth" in c.lower() or "zone" in c.lower() or
    "open" in c.lower() or "bedroom" in c.lower() or "spatial" in c.lower()
    for c in chips_atm
)
check("H1: atmosphere switch chips include spatial awareness", has_spatial, f"chips={chips_atm}")
check("H2: no duplicate chips", len(set(chips_atm)) == len(chips_atm), "duplicates found")

# H3: Iteration 6 chips different from iteration 1
chips_i1 = get_contextual_chips("warm_modern", "living_room", 1)
chips_i6 = get_contextual_chips("warm_modern", "living_room", 6)
check("H3: late-iteration chips differ from early",
      chips_i1 != chips_i6, f"same: {chips_i6}")
has_late = any("final" in c.lower() or "adjust" in c.lower() or "version" in c.lower()
               for c in chips_i6)
check("H4: iteration 6 has late-stage chips", has_late, f"chips={chips_i6}")


# ── Problem I: Language persistence ───────────────────────────────────────────

print()
print(SEP)
print("PROBLEM I — Language persistence")
print(SEP)

fr_history = [
    {"role": "user", "content": "Je voudrais un appartement japandi"},
    {"role": "ai", "content": "Bien sûr..."},
]
mem_fr_lang = build_session_memory(fr_history, "fr")
check("I1: FR history -> session_language=fr",
      mem_fr_lang.session_language == "fr", f"got {mem_fr_lang.session_language}")

# Override via hint
mem_switch = build_session_memory([], "en", session_language_override="fr")
check("I2: language override works", mem_switch.session_language == "fr",
      f"got {mem_switch.session_language}")

# FR greeting
mc_fr = MetaClassification(MetaIntent.GREETING, "fr", "fr", 0.90)
resp_fr_greet = generate_meta_response(mc_fr, "test")
check("I3: FR greeting response is French", any(
    w in resp_fr_greet.lower() for w in ["bonjour", "bonsoir", "salut", "pièce", "créer"]),
    f"response: {resp_fr_greet}")


# ── Problem J: Vision caption cleanup ─────────────────────────────────────────

print()
print(SEP)
print("PROBLEM J — Vision caption cleanup")
print(SEP)

# J1: Template-based caption for ATMOSPHERE_SWITCH
cap_atm = build_vision_caption(
    "Switch to Zen Retreat", TransformationType.ATMOSPHERE_SWITCH, 2, "zen_retreat", "en"
)
check("J1: atmosphere switch caption is grammatical",
      not cap_atm.startswith("Vision 2 — Switch"),
      f"raw instruction in caption: {cap_atm}")
check("J2: atmosphere switch caption mentions atmosphere name",
      "zen" in cap_atm.lower() or "retreat" in cap_atm.lower(),
      f"no atm in: {cap_atm}")
print(f"  ATMOSPHERE_SWITCH caption: {cap_atm}")

# J3: Functional reassignment template caption (no zone-reassignment fragments)
cap_func = build_vision_caption(
    "Make the TV area a bedroom and move the TV to the sofa area.",
    TransformationType.FUNCTIONAL_REASSIGNMENT, 3, "warm_modern", "en"
)
check("J3: functional caption doesn't inject raw instruction",
      "Make the TV" not in cap_func,
      f"raw instruction leaked: {cap_func}")
check("J4: functional caption mentions reassignment",
      "reassign" in cap_func.lower() or "zone" in cap_func.lower(),
      f"no context: {cap_func}")
print(f"  FUNCTIONAL_REASSIGNMENT caption: {cap_func}")

# J5: Malformed instruction cleanup
cap_bad = build_vision_caption(
    "and put the TV in the room where we have the sofa",
    TransformationType.OBJECT_EDIT, 2, "warm_modern", "en"
)
check("J5: leading 'and' removed from caption",
      not cap_bad.lower().startswith("vision 2 — and"),
      f"leading 'and': {cap_bad}")
print(f"  Bad instruction caption (cleaned): {cap_bad}")

# J6: FR caption
cap_fr = build_vision_caption(
    "Essaie le style japandi", TransformationType.ATMOSPHERE_SWITCH, 2, "japandi_calm", "fr"
)
check("J6: FR caption in French",
      "vision" in cap_fr.lower() or "interprétation" in cap_fr.lower(),
      f"not French: {cap_fr}")
print(f"  FR ATMOSPHERE_SWITCH caption: {cap_fr}")


# ── Problem K: Transformation state extraction ────────────────────────────────

print()
print(SEP)
print("PROBLEM K — Transformation state extraction")
print(SEP)

# K1: Functional instruction cleaned properly
raw = "Make the TV area a bedroom and move the TV to the sofa area"
clean_k = build_clean_instruction(raw, TransformationType.FUNCTIONAL_REASSIGNMENT)
check("K1: functional instruction includes original intent",
      "bedroom" in clean_k or "TV" in clean_k, f"lost intent: {clean_k[:80]}")
check("K2: functional instruction appends zone preservation",
      "preserve" in clean_k.lower() and "zone" in clean_k.lower(),
      f"no preservation: {clean_k[:100]}")
check("K3: functional instruction does not end with raw fragment",
      not clean_k.endswith("sofa area") and len(clean_k) > len(raw),
      f"no addendum: {clean_k[-60:]}")
print(f"  Functional clean instruction: {clean_k[:150]}...")

# K4: Non-functional instruction — basic cleaning only
raw_simple = "Make it warmer"
clean_simple = build_clean_instruction(raw_simple, TransformationType.STYLE_REFINEMENT)
check("K4: simple instruction passes through",
      "warmer" in clean_simple.lower(), f"lost content: {clean_simple}")

# K5: Compound instruction with leading conjunction
raw_junk = "and bring in more warmth"
cap_junk = build_vision_caption(raw_junk, TransformationType.STYLE_REFINEMENT, 2, "warm_modern", "en")
check("K5: leading conjunction cleaned in caption",
      not cap_junk.lower().startswith("vision 2 — and"),
      f"junk not cleaned: {cap_junk}")
print(f"  Cleaned compound caption: {cap_junk}")


# ── Prompt composition audit ───────────────────────────────────────────────────

print()
print(SEP)
print("PROMPT COMPOSITION AUDIT")
print(SEP)

from prompt_engine.composer import compose_generation_prompt

# Audit 1: Style refinement prompt includes same-apartment language
prompt_refine = compose_generation_prompt(
    style_label="Warm Modern",
    room_type="living room",
    room_description="A bright living room with large windows.",
    user_instruction="Make it warmer",
    iteration=2,
    history=[{"role": "user", "content": "Design this space"}],
    secondary_visible_spaces=["bedroom"],
)
check("AUDIT1: refinement prompt has SAME APARTMENT",
      "SAME APARTMENT" in prompt_refine, "no continuity phrase")
check("AUDIT2: refinement prompt has atmosphere boundary",
      "ATMOSPHERE BOUNDARY" in prompt_refine, "no atmosphere boundary")
check("AUDIT3: refinement prompt is under 3800 chars",
      len(prompt_refine) <= 3800, f"length={len(prompt_refine)}")
print(f"  Refinement prompt length: {len(prompt_refine)} chars")
print(f"  First 150 chars: {prompt_refine[:150]}...")

# Audit 2: Full redesign prompt has atmosphere boundary
prompt_v1 = compose_generation_prompt(
    style_label="Zen Retreat",
    room_type="living room",
    room_description="Open plan with rear bedroom visible.",
    user_instruction="Create a zen space",
    iteration=1,
    history=[],
    secondary_visible_spaces=["bedroom"],
)
check("AUDIT4: vision 1 prompt has atmosphere boundary",
      "ATMOSPHERE BOUNDARY" in prompt_v1, "no atmosphere boundary")
check("AUDIT5: vision 1 prompt has visible spaces block",
      "VISIBLE" in prompt_v1, "no visible spaces")
print(f"  Vision 1 prompt length: {len(prompt_v1)} chars")


# ── No regression ─────────────────────────────────────────────────────────────

print()
print(SEP)
print("REGRESSION — All wave exports load cleanly")
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
    print("  [PASS] All Wave 2.5 -> 3.4.1 exports load cleanly")
except Exception as e:
    print(f"  [FAIL] Import error: {e}")
    errors.append(f"import: {e}")

try:
    from prompt_engine.preservation import build_structural_contract, _ATMOSPHERE_BOUNDARY
    assert "ATMOSPHERE BOUNDARY" in _ATMOSPHERE_BOUNDARY
    print("  [PASS] preservation._ATMOSPHERE_BOUNDARY exists")
except Exception as e:
    print(f"  [FAIL] preservation: {e}")
    errors.append(str(e))

try:
    from prompt_engine.transformation_state_builder import build_vision_caption, build_clean_instruction
    cap = build_vision_caption("test", TransformationType.STYLE_REFINEMENT, 2, "warm_modern", "en")
    assert "Vision 2" in cap
    print("  [PASS] transformation_state_builder functions work")
except Exception as e:
    print(f"  [FAIL] state builder: {e}")
    errors.append(str(e))


# ── Summary ───────────────────────────────────────────────────────────────────

print()
print(SEP)
if not errors:
    print("RESULT: ALL CHECKS PASSED — Wave 3.4.1 is ready")
else:
    print(f"RESULT: {len(errors)} FAILURE(S)")
    for e in errors:
        print(f"  - {e}")
print(SEP)
