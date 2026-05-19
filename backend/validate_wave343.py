"""
validate_wave343.py — Wave 3.4.3 validation suite.

Tests:
  A. Human conversational realism (jargon suppression)
  B. Social/meta conversation understanding (language questions, AI identity)
  C. Functional-first response ordering
  D. Caption grammar and naturalness
  E. Suggestion chip contextuality (Zen lighting discipline)
  F. Incremental refinement lock language
  G. Atmosphere lighting discipline (Zen Retreat)
  H. Functional reasoning / ergonomic plausibility
  REGRESSION — All prior wave exports load cleanly
"""

import sys, os
sys.path.insert(0, os.path.dirname(__file__))

PASS = "[PASS]"
FAIL = "[FAIL]"
results = []

def check(label: str, condition: bool, detail: str = "") -> None:
    status = PASS if condition else FAIL
    results.append((status, label, detail))
    print(f"  {status} {label}" + (f"\n         detail: {detail}" if detail and not condition else ""))

def section(title: str) -> None:
    print(f"\n{'-'*70}")
    print(f"{title}")
    print(f"{'-'*70}")


# ─────────────────────────────────────────────────────────────────────────────
section("CATEGORY A — Human Conversational Realism")
# ─────────────────────────────────────────────────────────────────────────────

from prompt_engine.architect_response import (
    generate_chat_response,
    generate_architect_response,
    _secondary_space_note,
)
from prompt_engine.edit_intent import EditMode
from prompt_engine.refinement_memory import RefinementState
from prompt_engine.intent_classifier import SubIntent

empty_state = RefinementState()

# A1: secondary space note no longer uses "same language" jargon
note = _secondary_space_note("warm_modern", ["bedroom"])
check("A1: secondary space note is non-empty", bool(note))
check("A1: secondary space note avoids 'same language' jargon", "same language" not in (note or ""))
check("A1: secondary space note is natural", "consistent" in (note or "") or "background" in (note or ""))
print(f"  Secondary space note: {note}")

# A2: MIXED/GENERAL response avoids "especially if the ... stays consistent" jargon
chat_general = generate_chat_response(
    user_message="I like this direction",
    atmosphere_id="warm_modern",
    room_type="living_room",
    sub_intent=SubIntent.GENERAL,
    secondary_spaces=[],
    refinement_state=empty_state,
)
check("A2: general response avoids 'stays consistent' jargon", "stays consistent" not in chat_general)
check("A2: general response avoids 'material harmony' jargon", "material harmony" not in chat_general)
check("A2: general response is concise (under 200 chars)", len(chat_general) < 200)
print(f"  General response: {chat_general}")

# A3: Vision 1 response avoids "fluted ivory" or "architectural layering" type language
v1_response = generate_architect_response(
    atmosphere_id="warm_modern",
    room_type="living_room",
    iteration=1,
    edit_mode=EditMode.FIRST_VISION,
    refinement_state=empty_state,
    sub_intent=SubIntent.GENERAL,
    secondary_spaces=[],
    user_message="Make it warm modern",
)
JARGON_WORDS = ["architectural layering", "spatial palette", "material harmony", "same language"]
for jw in JARGON_WORDS:
    check(f"A3: V1 response avoids '{jw}'", jw not in v1_response)
check("A3: V1 response under 220 chars", len(v1_response) < 220)
print(f"  V1 response: {v1_response}")

# A4: STRUCTURAL response leads with spatial acknowledgment
structural_resp = generate_chat_response(
    user_message="Turn the dining room into a home office",
    atmosphere_id="warm_modern",
    room_type="living_room",
    sub_intent=SubIntent.STRUCTURAL_CHANGE,
    secondary_spaces=[],
    refinement_state=empty_state,
)
check("A4: structural response exists", bool(structural_resp))
check("A4: structural response doesn't start with style", not structural_resp.lower().startswith("that could work well in"))
FUNCTION_WORDS = ["zone", "spatial", "function", "change", "shift", "transform"]
has_function_word = any(w in structural_resp.lower() for w in FUNCTION_WORDS)
check("A4: structural response has functional/spatial language", has_function_word)
print(f"  Structural (function-first) response: {structural_resp}")


# ─────────────────────────────────────────────────────────────────────────────
section("CATEGORY B — Social/Meta Conversation Understanding")
# ─────────────────────────────────────────────────────────────────────────────

from prompt_engine.meta_intent import classify_meta_intent, MetaIntent

SOCIAL_MESSAGES = [
    ("can you speak Khmer?", "language-capability"),
    ("do you speak Japanese?", "language-capability"),
    ("what languages do you support?", "language-list"),
    ("are you an AI?", "ai-identity"),
    ("do you remember me?", "memory-question"),
    ("who made you?", "ai-identity"),
    ("you're getting better!", "ai-compliment"),
]

for msg, label in SOCIAL_MESSAGES:
    meta = classify_meta_intent(msg)
    check(
        f"B1: '{label}' does not route to design layer",
        meta.intent != MetaIntent.NONE,
        f"msg='{msg}' got intent={meta.intent.value}",
    )

# B2: social messages must not produce architecture commentary
from prompt_engine.meta_response import generate_meta_response
for msg, label in SOCIAL_MESSAGES[:3]:
    meta = classify_meta_intent(msg)
    if meta.intent != MetaIntent.NONE:
        resp = generate_meta_response(meta)
        # Check for genuine architecture jargon — not conversational words like "direction"
        ARCH_JARGON = ["atmosphere", "material", "DNA", "palette", "spatial", "wabi", "travertine"]
        has_arch = any(w in resp for w in ARCH_JARGON)
        check(f"B2: '{label}' response avoids architecture jargon", not has_arch, f"resp='{resp}'")

# B3: design messages still route to NONE (false-positive guard)
DESIGN_MESSAGES = [
    "Add a floor lamp",
    "Make it warmer",
    "Turn the sofa grey",
    "Can you add more plants?",
    "Push this direction further",
]
for dm in DESIGN_MESSAGES:
    meta = classify_meta_intent(dm)
    check(f"B3: design msg routes to NONE | '{dm}'", meta.intent == MetaIntent.NONE)


# ─────────────────────────────────────────────────────────────────────────────
section("CATEGORY C — Functional-First Response Ordering")
# ─────────────────────────────────────────────────────────────────────────────

FUNCTIONAL_INSTRUCTIONS = [
    "Turn the TV area into a sleeping zone",
    "Convert the dining room into a home office",
    "Make the living zone a bedroom",
]

for instr in FUNCTIONAL_INSTRUCTIONS:
    resp = generate_chat_response(
        user_message=instr,
        atmosphere_id="zen_retreat",
        room_type="living_room",
        sub_intent=SubIntent.STRUCTURAL_CHANGE,
        secondary_spaces=[],
        refinement_state=empty_state,
    )
    # Must NOT start with style/atmosphere commentary
    STYLE_STARTERS = ["that could work well in", "in zen", "the zen", "beautiful", "cinematic"]
    starts_with_style = any(resp.lower().startswith(s) for s in STYLE_STARTERS)
    check(f"C1: function-first | '{instr[:35]}'", not starts_with_style, f"resp='{resp[:80]}'")
    SPATIAL_WORDS = ["zone", "spatial", "function", "change", "shift", "transform", "layout"]
    has_spatial = any(w in resp.lower() for w in SPATIAL_WORDS)
    check(f"C2: spatial language present | '{instr[:35]}'", has_spatial, f"resp='{resp[:80]}'")


# ─────────────────────────────────────────────────────────────────────────────
section("CATEGORY D — Caption Grammar and Naturalness")
# ─────────────────────────────────────────────────────────────────────────────

from prompt_engine.transformation_state_builder import build_vision_caption, _clean_text
from prompt_engine.transformation_classifier import TransformationType

# D1: bad grammar fragments are cleaned
BAD_CAPTIONS = [
    ("show me the room where there is a 2 chairs", "where there is"),
    ("can you add more decoration things", "can you"),
    ("i want you to make it warmer", "i want you"),
    ("please add a floor lamp", "please"),
    ("could you remove the sofa because it's too big", "because"),
]
for bad_text, fragment in BAD_CAPTIONS:
    cleaned = _clean_text(bad_text, max_len=70)
    check(f"D1: fragment '{fragment}' removed", fragment not in cleaned.lower(), f"cleaned='{cleaned}'")

# D2: cleaned text starts with capital
for bad_text, _ in BAD_CAPTIONS[:3]:
    cleaned = _clean_text(bad_text, max_len=70)
    if cleaned:
        check("D2: cleaned text starts with capital", cleaned[0].isupper())

# D3: atmosphere switch caption is grammatical
atm_caption = build_vision_caption(
    user_instruction="Switch to Zen Retreat",
    transformation_type=TransformationType.ATMOSPHERE_SWITCH,
    iteration=2,
    atmosphere_id="zen_retreat",
    language="en",
)
check("D3: atmosphere caption is non-empty", bool(atm_caption))
check("D3: atmosphere caption has no raw instruction fragment", "Switch to" not in atm_caption)
print(f"  Atmosphere caption: {atm_caption}")

# D4: functional caption is grammatical
func_caption = build_vision_caption(
    user_instruction="Turn the TV area into a sleeping zone",
    transformation_type=TransformationType.FUNCTIONAL_REASSIGNMENT,
    iteration=3,
    atmosphere_id="zen_retreat",
    language="en",
)
check("D4: functional caption is non-empty", bool(func_caption))
check("D4: functional caption has no raw instruction", "TV area" not in func_caption)
print(f"  Functional caption: {func_caption}")

# D5: object edit caption is cleaned
obj_caption = build_vision_caption(
    user_instruction="can you add more decoration things",
    transformation_type=TransformationType.OBJECT_EDIT,
    iteration=2,
    atmosphere_id="warm_modern",
    language="en",
)
check("D5: object edit caption avoids 'can you'", "can you" not in obj_caption.lower())
print(f"  Object edit caption: {obj_caption}")

# D6: style refinement caption is cleaned
style_caption = build_vision_caption(
    user_instruction="i want you to make it warmer",
    transformation_type=TransformationType.STYLE_REFINEMENT,
    iteration=2,
    atmosphere_id="warm_modern",
    language="en",
)
check("D6: style refinement caption avoids 'i want you'", "i want you" not in style_caption.lower())
print(f"  Style refinement caption: {style_caption}")


# ─────────────────────────────────────────────────────────────────────────────
section("CATEGORY E — Suggestion Chip Contextuality")
# ─────────────────────────────────────────────────────────────────────────────

from prompt_engine.suggestion_engine import _ATM_CHIPS
from prompt_engine.chip_engine import get_contextual_chips

# E1: Zen chips no longer contain darkness-promoting options
zen_chips = _ATM_CHIPS.get("zen_retreat", [])
DARK_CHIPS = ["Darken the stone palette", "More shadow in the space", "Try a lower light level"]
for dark in DARK_CHIPS:
    check(f"E1: zen chips do not contain '{dark}'", dark not in zen_chips)

# E2: Zen chips contain light-preserving options
LIGHT_CHIPS = ["natural light", "brightness", "clear", "breathable", "open"]
has_light_chip = any(
    any(lw in chip.lower() for lw in LIGHT_CHIPS)
    for chip in zen_chips
)
check("E2: zen chips contain light-preserving option", has_light_chip)
print(f"  Zen chips: {zen_chips[:5]}")

# E3: functional reassignment chips reference zone identity / lighting
func_chips = get_contextual_chips(
    atmosphere_id="zen_retreat",
    room_type="living_room",
    iteration=2,
    transformation_type=TransformationType.FUNCTIONAL_REASSIGNMENT,
    secondary_spaces=["bedroom"],
    count=4,
)
check("E3: functional chips non-empty", len(func_chips) == 4)
check("E3: functional chips no duplicates", len(set(func_chips)) == len(func_chips))
FUNC_WORDS = ["zone", "identity", "privacy", "lighting", "boundary", "defined"]
has_func_word = any(any(fw in chip.lower() for fw in FUNC_WORDS) for chip in func_chips)
check("E3: functional chips reference zone concept", has_func_word)
print(f"  Functional chips: {func_chips}")

# E4: atmosphere switch chips reference spatial awareness
atm_chips = get_contextual_chips(
    atmosphere_id="zen_retreat",
    room_type="living_room",
    iteration=1,
    transformation_type=TransformationType.ATMOSPHERE_SWITCH,
    secondary_spaces=["bedroom"],
    count=4,
)
SPATIAL_CHIP_WORDS = ["spatial", "layout", "light", "windows", "open", "visible"]
has_spatial_chip = any(any(sw in chip.lower() for sw in SPATIAL_CHIP_WORDS) for chip in atm_chips)
check("E4: atmosphere switch chips reference spatial awareness", has_spatial_chip)
print(f"  Atmosphere switch chips: {atm_chips}")


# ─────────────────────────────────────────────────────────────────────────────
section("CATEGORY F — Incremental Refinement Lock")
# ─────────────────────────────────────────────────────────────────────────────

from prompt_engine.edit_intent import build_style_refinement_header

refinement_header = build_style_refinement_header(
    user_instruction="Make it warmer",
    style_name="Warm Modern",
    room_type="living room",
)

check("F1: refinement header has SAME APARTMENT", "SAME APARTMENT" in refinement_header)
check("F2: refinement header has incremental lock", "INCREMENTAL EVOLUTION" in refinement_header)
check("F3: refinement header says do not reimagine", "reimagine" in refinement_header.lower())
check("F4: refinement header locks furniture positions", "furniture positions" in refinement_header.lower())
check("F5: refinement header has spatial anchors", "spatial anchors" in refinement_header.lower())
check("F6: refinement header says one step forward", "one visible step forward" in refinement_header.lower())
print(f"  Refinement header length: {len(refinement_header)} chars")
print(f"  First 200 chars: {refinement_header[:200]}")


# ─────────────────────────────────────────────────────────────────────────────
section("CATEGORY G — Atmosphere Lighting Discipline (Zen Retreat)")
# ─────────────────────────────────────────────────────────────────────────────

from prompt_engine.transformation_classifier import build_spatial_preservation_addendum, _ZEN_LIGHTING_DISCIPLINE

# G1: Zen lighting discipline constant exists and contains key phrases
check("G1: zen lighting discipline exists", bool(_ZEN_LIGHTING_DISCIPLINE))
check("G1: zen lighting says breathable", "breathable" in _ZEN_LIGHTING_DISCIPLINE)
check("G1: zen lighting says NOT dark", "NOT dark" in _ZEN_LIGHTING_DISCIPLINE or "not dark" in _ZEN_LIGHTING_DISCIPLINE.lower())
check("G1: zen lighting says material restraint", "MATERIAL RESTRAINT" in _ZEN_LIGHTING_DISCIPLINE or "material restraint" in _ZEN_LIGHTING_DISCIPLINE.lower())
check("G1: zen lighting says DO NOT darken", "DO NOT darken" in _ZEN_LIGHTING_DISCIPLINE)

# G2: Zen addendum is injected when atmosphere_id=zen_retreat
zen_addendum = build_spatial_preservation_addendum(
    transformation_type=TransformationType.ATMOSPHERE_SWITCH,
    secondary_spaces=[],
    room_type="living_room",
    atmosphere_id="zen_retreat",
)
check("G2: zen addendum contains lighting discipline", "ZEN LIGHTING DISCIPLINE" in zen_addendum)
check("G2: zen addendum says breathable", "breathable" in zen_addendum)

# G3: Non-zen atmosphere does NOT get zen lighting discipline
warm_addendum = build_spatial_preservation_addendum(
    transformation_type=TransformationType.ATMOSPHERE_SWITCH,
    secondary_spaces=[],
    room_type="living_room",
    atmosphere_id="warm_modern",
)
check("G3: warm_modern addendum does not have zen lighting", "ZEN LIGHTING DISCIPLINE" not in warm_addendum)

# G4: Zen lighting in functional reassignment context too
zen_func_addendum = build_spatial_preservation_addendum(
    transformation_type=TransformationType.FUNCTIONAL_REASSIGNMENT,
    secondary_spaces=["bedroom"],
    room_type="living_room",
    atmosphere_id="zen_retreat",
)
check("G4: zen functional addendum has lighting discipline", "ZEN LIGHTING DISCIPLINE" in zen_func_addendum)

# G5: Backward compat — no atmosphere_id still works
no_atm_addendum = build_spatial_preservation_addendum(
    transformation_type=TransformationType.ATMOSPHERE_SWITCH,
    secondary_spaces=[],
    room_type="living_room",
)
check("G5: no atmosphere_id arg works (backward compat)", "ATMOSPHERE SWITCH" in no_atm_addendum)
check("G5: no atmosphere_id does not inject zen lighting", "ZEN LIGHTING DISCIPLINE" not in no_atm_addendum)


# ─────────────────────────────────────────────────────────────────────────────
section("CATEGORY H — Functional Reasoning / Ergonomic Plausibility")
# ─────────────────────────────────────────────────────────────────────────────

from prompt_engine.transformation_classifier import _FUNCTIONAL_REASSIGNMENT_ADDENDUM

check("H1: functional addendum has ergonomic plausibility", "ERGONOMIC PLAUSIBILITY" in _FUNCTIONAL_REASSIGNMENT_ADDENDUM)
check("H2: functional addendum requires correct scale", "correct human scale" in _FUNCTIONAL_REASSIGNMENT_ADDENDUM.lower() or "human scale" in _FUNCTIONAL_REASSIGNMENT_ADDENDUM.lower())
check("H3: functional addendum requires circulation paths", "circulation" in _FUNCTIONAL_REASSIGNMENT_ADDENDUM.lower())
check("H4: functional addendum says real usable space", "real, usable space" in _FUNCTIONAL_REASSIGNMENT_ADDENDUM.lower() or "real usable" in _FUNCTIONAL_REASSIGNMENT_ADDENDUM.lower())
check("H5: functional addendum says viewer must understand", "viewer must immediately understand" in _FUNCTIONAL_REASSIGNMENT_ADDENDUM.lower())

# H6: functional addendum has directional relationship language
check("H6: functional addendum has facing/directional language", "facing" in _FUNCTIONAL_REASSIGNMENT_ADDENDUM.lower() or "directional" in _FUNCTIONAL_REASSIGNMENT_ADDENDUM.lower())

# H7: functional addendum has visual clarity requirement
check("H7: functional addendum has visual clarity requirement", "VISUAL CLARITY REQUIREMENT" in _FUNCTIONAL_REASSIGNMENT_ADDENDUM)


# ─────────────────────────────────────────────────────────────────────────────
section("INCREMENTAL PROMPT AUDIT")
# ─────────────────────────────────────────────────────────────────────────────

from prompt_engine import compose_generation_prompt
from prompt_engine.edit_intent import build_structural_transformation_header

# Audit 1: style refinement prompt has incremental lock
refinement_prompt = compose_generation_prompt(
    style_label="Warm Modern",
    room_type="living room",
    room_description="A bright modern living room with large windows.",
    user_instruction="Make it warmer",
    iteration=2,
    history=[],
    secondary_visible_spaces=None,
)
check("AUDIT1: refinement prompt has incremental lock", "INCREMENTAL EVOLUTION" in refinement_prompt)
check("AUDIT2: refinement prompt within 3800 chars", len(refinement_prompt) <= 3800)

# Audit 2: zen_retreat atmosphere switch prompt has lighting discipline (early position)
zen_atm_instruction = (
    "Switch to Zen Retreat. "
    + build_spatial_preservation_addendum(
        transformation_type=TransformationType.ATMOSPHERE_SWITCH,
        secondary_spaces=[],
        room_type="living_room",
        atmosphere_id="zen_retreat",
    )
)
zen_atm_prompt = compose_generation_prompt(
    style_label="Zen Retreat",
    room_type="living room",
    room_description="A modern apartment with large windows and open plan layout.",
    user_instruction=zen_atm_instruction,
    iteration=2,
    history=[],
    secondary_visible_spaces=None,
)
check("AUDIT3: zen atm prompt within 3800 chars", len(zen_atm_prompt) <= 3800)
check("AUDIT4: zen atm prompt has atmosphere boundary", "ATMOSPHERE BOUNDARY" in zen_atm_prompt)
check("AUDIT4b: zen atm prompt has zen lighting discipline in generated text", "ZEN LIGHTING" in zen_atm_prompt or "breathable" in zen_atm_prompt)
print(f"  Zen atmosphere prompt: {len(zen_atm_prompt)} chars")
print(f"  Has ZEN LIGHTING: {'ZEN LIGHTING' in zen_atm_prompt}, breathable: {'breathable' in zen_atm_prompt}")

# Audit 3: local edit prompt has window blocking rule
from prompt_engine.edit_intent import build_local_edit_prompt
local_prompt = build_local_edit_prompt(
    user_instruction="Add a floor lamp near the window",
    style_name="Warm Modern",
    room_type="living room",
    room_description="",
)
check("AUDIT5: local edit prompt has window blocking rule", "window" in local_prompt.lower() and "unblocked" in local_prompt.lower())


# ─────────────────────────────────────────────────────────────────────────────
section("REGRESSION — All prior wave exports load cleanly")
# ─────────────────────────────────────────────────────────────────────────────

try:
    from prompt_engine import (
        compose_generation_prompt, parse_history,
        classify_edit_mode, classify_room, surprise_me, classify_intent,
        generate_architect_response, generate_chat_response,
        generate_mixed_response, get_suggestion_chips,
        classify_meta_intent, MetaIntent,
        generate_meta_response, generate_project_aware_greeting,
        build_session_memory, select_tone_mode,
        generate_human_soft_response, ToneMode,
        detect_emotional_context, select_response_length,
        generate_architect_light_response, EmotionalContext,
        classify_transformation, build_spatial_preservation_addendum,
        TransformationType, get_contextual_chips,
    )
    from prompt_engine.transformation_state_builder import build_vision_caption, build_clean_instruction
    from prompt_engine.meta_intent import _SOCIAL_QUESTION
    from prompt_engine.edit_intent import build_style_refinement_header, build_local_edit_prompt
    from prompt_engine.transformation_classifier import _ZEN_LIGHTING_DISCIPLINE, _FUNCTIONAL_REASSIGNMENT_ADDENDUM
    check("REGRESSION: all Wave 2.5–3.4.3 exports load cleanly", True)
    check("REGRESSION: _SOCIAL_QUESTION pattern exists", _SOCIAL_QUESTION is not None)
    check("REGRESSION: _ZEN_LIGHTING_DISCIPLINE exists", bool(_ZEN_LIGHTING_DISCIPLINE))
    check("REGRESSION: build_spatial_preservation_addendum has atmosphere_id param", True)
except Exception as e:
    check("REGRESSION: all exports load cleanly", False, str(e))

# Regression: reflection question still blocked
meta_reflect = classify_meta_intent("what do you think?")
check("REGRESSION: reflection question still blocked", meta_reflect.intent != MetaIntent.NONE)

# Regression: functional reassignment still classified correctly
from prompt_engine.transformation_classifier import classify_transformation
check("REGRESSION: 'Turn the TV area into a bedroom' = FUNCTIONAL_REASSIGNMENT",
      classify_transformation("Turn the TV area into a bedroom") == TransformationType.FUNCTIONAL_REASSIGNMENT)
check("REGRESSION: 'Make it warmer' = STYLE_REFINEMENT",
      classify_transformation("Make it warmer") == TransformationType.STYLE_REFINEMENT)
check("REGRESSION: 'Add a floor lamp' = OBJECT_EDIT",
      classify_transformation("Add a floor lamp") == TransformationType.OBJECT_EDIT)

# Regression: incremental lock in refinement header from wave341
header = build_style_refinement_header("make it warmer", "Warm Modern", "living room")
check("REGRESSION: refinement header has SAME APARTMENT", "SAME APARTMENT" in header)

# Regression: atmosphere boundary still has priority order and functional
from prompt_engine.preservation import build_structural_contract
contract = build_structural_contract("living room")
check("REGRESSION: contract has PRIORITY ORDER", "PRIORITY ORDER" in contract)
check("REGRESSION: contract has Functional zone", "Functional zone" in contract)

print()


# ─────────────────────────────────────────────────────────────────────────────
# RESULT
# ─────────────────────────────────────────────────────────────────────────────

passed = sum(1 for s, _, _ in results if s == PASS)
failed = sum(1 for s, _, _ in results if s == FAIL)
total = len(results)

print(f"\n{'-'*70}")
if failed == 0:
    print(f"RESULT: ALL CHECKS PASSED — Wave 3.4.3 product foundation ready")
    print()
    print("  MANDATORY MANUAL VISUAL REVIEW:")
    print("  [MANUAL] A: Responses feel warm, human, conversational — not architect-essay")
    print("  [MANUAL] B: 'can you speak Khmer?' gets social response, not design commentary")
    print("  [MANUAL] C: Functional change responses lead with spatial, not style")
    print("  [MANUAL] D: Captions read naturally, no malformed grammar fragments")
    print("  [MANUAL] E: Zen chips reference calm brightness, not darkness")
    print("  [MANUAL] F: Sequential generations feel like same apartment evolving")
    print("  [MANUAL] G: Zen Retreat remains bright, breathable, naturally lit")
    print("  [MANUAL] H: Functional reassignments show believable, ergonomic spaces")
else:
    print(f"RESULT: {failed}/{total} CHECKS FAILED — review output above")
    for s, label, detail in results:
        if s == FAIL:
            print(f"  {FAIL} {label}" + (f" — {detail}" if detail else ""))
print(f"{'-'*70}")

if failed > 0:
    sys.exit(1)
