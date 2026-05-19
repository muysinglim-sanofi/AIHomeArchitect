"""
validate_wave34.py — Wave 3.4 Architectural Stability & Decision Maturity validation.

Covers all 9 spec validation categories:
  1. Atmosphere switching tests
  2. Multi-space preservation tests
  3. Reflection-vs-generation tests
  4. Language continuity tests
  5. Iterative continuity tests
  6. Functional reassignment tests
  7. Small-space realism tests
  8. Suggestion-chip quality tests
  9. "Hello" continuity tests

Run with: python validate_wave34.py
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

SEP = "-" * 70

from prompt_engine.transformation_classifier import (
    TransformationType, classify_transformation, build_spatial_preservation_addendum,
)
from prompt_engine.chip_engine import get_contextual_chips
from prompt_engine.meta_response import generate_project_aware_greeting, generate_meta_response
from prompt_engine.meta_intent import classify_meta_intent, MetaIntent, MetaClassification
from prompt_engine.intent_classifier import classify_intent, ConversationIntent, SubIntent
from prompt_engine.conversation_memory import build_session_memory, SessionMemory
from prompt_engine.response_quality import EmotionalContext
from prompt_engine.tone_calibration import ToneMode, select_tone_mode

errors: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  [PASS] {label}")
    else:
        msg = f"  [FAIL] {label}" + (f": {detail}" if detail else "")
        print(msg)
        errors.append(label + (f": {detail}" if detail else ""))


# ── Section 1: Atmosphere switching tests ────────────────────────────────────

print(SEP)
print("SECTION 1 — Atmosphere switching tests")
print(SEP)

ATMOS_SWITCH_CASES = [
    ("Switch to Zen Retreat",               TransformationType.ATMOSPHERE_SWITCH,  "direct switch"),
    ("Try a japandi style",                 TransformationType.ATMOSPHERE_SWITCH,  "named style"),
    ("Change the atmosphere to nordic",     TransformationType.ATMOSPHERE_SWITCH,  "change to named"),
    ("Go with dark contemporary",           TransformationType.ATMOSPHERE_SWITCH,  "go with"),
    ("Try the warm modern look",            TransformationType.ATMOSPHERE_SWITCH,  "try look"),
    ("Essaie le style zen",                 TransformationType.ATMOSPHERE_SWITCH,  "FR switch"),
]

for msg, expected_type, note in ATMOS_SWITCH_CASES:
    tx = classify_transformation(msg)
    check(f"ATMOS_SWITCH: {note} | '{msg}'", tx == expected_type, f"got {tx.value}")

# Addendum content for atmosphere switch
addendum = build_spatial_preservation_addendum(TransformationType.ATMOSPHERE_SWITCH, [], "living_room")
check("ATMOS_SWITCH: addendum is non-empty", len(addendum) > 50, f"len={len(addendum)}")
check("ATMOS_SWITCH: addendum mentions spatial", "spatial" in addendum.lower(), f"no 'spatial'")
check("ATMOS_SWITCH: addendum mentions material", "material" in addendum.lower(), f"no 'material'")
check("ATMOS_SWITCH: addendum says NO rearrange", "rearrange" in addendum or "preserved" in addendum.lower() or "PRESERVED" in addendum, "no preservation language")
print(f"  Addendum preview: {addendum[:120]}...")


# ── Section 2: Multi-space preservation tests ─────────────────────────────────

print()
print(SEP)
print("SECTION 2 — Multi-space preservation tests")
print(SEP)

# With secondary spaces present, addendum should lock them
addendum_with_spaces = build_spatial_preservation_addendum(
    TransformationType.ATMOSPHERE_SWITCH,
    ["bedroom", "living_room"],
    "kitchen",
)
check("MULTI-SPACE: has lock language", "MULTI-SPACE" in addendum_with_spaces or "PROTECTED" in addendum_with_spaces, "no lock")
check("MULTI-SPACE: mentions bedroom", "bedroom" in addendum_with_spaces, "no bedroom ref")
check("MULTI-SPACE: mentions living room", "living room" in addendum_with_spaces, "no living room ref")
print(f"  Multi-space addendum: {addendum_with_spaces[addendum_with_spaces.find('MULTI'):addendum_with_spaces.find('MULTI')+200]}...")

# Without secondary spaces — no lock section
addendum_no_spaces = build_spatial_preservation_addendum(
    TransformationType.ATMOSPHERE_SWITCH,
    [],
    "living_room",
)
check("MULTI-SPACE: no spaces -> no lock", "MULTI-SPACE" not in addendum_no_spaces, "has lock without spaces")

# OBJECT_EDIT should NOT add multi-space lock even with secondary spaces
addendum_obj_edit = build_spatial_preservation_addendum(
    TransformationType.OBJECT_EDIT,
    ["bedroom"],
    "living_room",
)
check("OBJECT_EDIT: no multi-space lock", "MULTI-SPACE" not in addendum_obj_edit, "has lock on object edit")
check("OBJECT_EDIT: empty or minimal", len(addendum_obj_edit) < 50, f"len={len(addendum_obj_edit)}")


# ── Section 3: Reflection-vs-generation tests ─────────────────────────────────

print()
print(SEP)
print("SECTION 3 — Reflection-vs-generation tests (should_generate=False)")
print(SEP)

REFLECTION_CASES = [
    ("What do you think?",          SubIntent.QUESTION,  "opinion seeking"),
    ("Does this make sense?",       SubIntent.QUESTION,  "logic check"),
    ("Is this right?",              SubIntent.QUESTION,  "validation ask"),
    ("I love this direction",       SubIntent.PRAISE,    "praise"),
    ("That looks perfect",          SubIntent.PRAISE,    "praise short"),
    ("What would you suggest?",     SubIntent.QUESTION,  "suggestion ask"),
]

for msg, expected_sub, note in REFLECTION_CASES:
    intent_cls = classify_intent(msg, iteration=2)
    check(
        f"REFLECT: {note} | '{msg}'",
        intent_cls.sub_intent == expected_sub or intent_cls.intent == ConversationIntent.CONVERSATION,
        f"intent={intent_cls.intent.value} sub={intent_cls.sub_intent.value}",
    )
    # Verify tone mode → not ARCHITECT_ACTIVE for these
    mem = build_session_memory([], "en")
    tone = select_tone_mode(
        meta_intent=MetaIntent.NONE,
        sub_intent=intent_cls.sub_intent,
        confidence=intent_cls.confidence,
        session_memory=mem,
        emotional_context=EmotionalContext.NEUTRAL,
    )
    check(
        f"REFLECT: {note} -> not ACTIVE",
        tone != ToneMode.ARCHITECT_ACTIVE,
        f"got {tone.value}",
    )


# ── Section 4: Language continuity tests ─────────────────────────────────────

print()
print(SEP)
print("SECTION 4 — Language continuity tests")
print(SEP)

# FR history → session language stays FR
fr_history = [
    {"role": "user", "content": "Je voudrais un salon japandi"},
    {"role": "ai", "content": "Bien sûr..."},
    {"role": "user", "content": "Plus de chaleur s'il vous plaît"},
]
mem_fr = build_session_memory(fr_history, detected_language="fr")
check("LANG: FR history -> session_lang=fr", mem_fr.session_language == "fr", f"got {mem_fr.session_language}")

# EN + LANGUAGE_SWITCH override → target is FR
mem_switch = build_session_memory([], "en", session_language_override="fr")
check("LANG: switch override -> fr", mem_switch.session_language == "fr", f"got {mem_switch.session_language}")

# Empty history → defaults to detected
mem_en = build_session_memory([], "en")
check("LANG: empty EN -> en", mem_en.session_language == "en", f"got {mem_en.session_language}")

# Language switch meta intent → target_language propagates
mc_switch = MetaClassification(MetaIntent.LANGUAGE_SWITCH, "en", "fr", 0.95)
resp = generate_meta_response(mc_switch, seed_extra="test")
check("LANG: switch response non-empty", len(resp) > 5)
print(f"  Language switch response: {resp}")


# ── Section 5: Iterative continuity tests ─────────────────────────────────────

print()
print(SEP)
print("SECTION 5 — Iterative continuity tests")
print(SEP)

# Contextual chips change with iteration
chips_iter1 = get_contextual_chips("warm_modern", "living_room", 1)
chips_iter6 = get_contextual_chips("warm_modern", "living_room", 6)
check("ITER: iter 1 has chips", len(chips_iter1) >= 4, f"count={len(chips_iter1)}")
check("ITER: iter 6 has chips", len(chips_iter6) >= 4, f"count={len(chips_iter6)}")
# Late iteration should include "final version" type chip
has_late_chip = any("final" in c.lower() or "version" in c.lower() or "adjust" in c.lower() for c in chips_iter6)
check("ITER: iter 6 has mature chips", has_late_chip, f"chips={chips_iter6}")
print(f"  Iter 1 chips: {chips_iter1}")
print(f"  Iter 6 chips: {chips_iter6}")


# ── Section 6: Functional reassignment tests ─────────────────────────────────

print()
print(SEP)
print("SECTION 6 — Functional reassignment tests")
print(SEP)

FUNCTIONAL_CASES = [
    ("Turn the TV area into a sleeping zone",      TransformationType.FUNCTIONAL_REASSIGNMENT, "EN TV to bed"),
    ("Convert this corner into a reading nook",    TransformationType.FUNCTIONAL_REASSIGNMENT, "EN corner"),
    ("Make the living zone a dining area",          TransformationType.FUNCTIONAL_REASSIGNMENT, "EN living->dining"),
    ("Repurpose the home office as a bedroom",      TransformationType.FUNCTIONAL_REASSIGNMENT, "EN repurpose"),
    ("Transformer le salon en espace bureau",       TransformationType.FUNCTIONAL_REASSIGNMENT, "FR transform"),
]

for msg, expected_type, note in FUNCTIONAL_CASES:
    tx = classify_transformation(msg)
    check(f"FUNC: {note} | '{msg}'", tx == expected_type, f"got {tx.value}")

# Addendum for functional reassignment
addendum_func = build_spatial_preservation_addendum(
    TransformationType.FUNCTIONAL_REASSIGNMENT, [], "living_room"
)
check("FUNC: addendum mentions footprint", "footprint" in addendum_func.lower(), f"no footprint")
check("FUNC: addendum mentions architectural", "architectural" in addendum_func.lower(), f"no architectural")
print(f"  Functional addendum preview: {addendum_func[:150]}...")


# ── Section 7: Small-space realism tests ─────────────────────────────────────

print()
print(SEP)
print("SECTION 7 — Small-space realism tests")
print(SEP)

STRUCTURAL_CASES = [
    ("Open up the kitchen",            TransformationType.STRUCTURAL_CHANGE, "open up"),
    ("Remove the wall between rooms",  TransformationType.STRUCTURAL_CHANGE, "remove wall"),
    ("Knock down the wall",            TransformationType.STRUCTURAL_CHANGE, "knock down"),
    ("Add an opening between spaces",  TransformationType.STRUCTURAL_CHANGE, "add opening"),
]

for msg, expected_type, note in STRUCTURAL_CASES:
    tx = classify_transformation(msg)
    check(f"STRUCT: {note} | '{msg}'", tx == expected_type, f"got {tx.value}")

# Livability constraint appears for ATMOSPHERE_SWITCH
addendum_atm = build_spatial_preservation_addendum(
    TransformationType.ATMOSPHERE_SWITCH, [], "living_room"
)
check("REALISM: atm switch has livability", "LIVABILITY" in addendum_atm or "livab" in addendum_atm.lower(), f"no livability")

# Livability NOT added to simple OBJECT_EDIT
addendum_obj = build_spatial_preservation_addendum(
    TransformationType.OBJECT_EDIT, [], "living_room"
)
check("REALISM: object edit no livability", len(addendum_obj) < 50, f"len={len(addendum_obj)}")


# ── Section 8: Suggestion-chip quality tests ─────────────────────────────────

print()
print(SEP)
print("SECTION 8 — Suggestion-chip quality tests")
print(SEP)

# ATMOSPHERE_SWITCH chips should include spatial preservation chips
chips_switch = get_contextual_chips(
    atmosphere_id="zen_retreat",
    room_type="living_room",
    iteration=2,
    transformation_type=TransformationType.ATMOSPHERE_SWITCH,
    secondary_spaces=["bedroom"],
)
print(f"  ATMOS_SWITCH chips: {chips_switch}")
check("CHIPS: atmosphere switch -> 4 chips", len(chips_switch) == 4, f"count={len(chips_switch)}")
# Should have a spatial/preservation chip
has_spatial_chip = any(
    "spatial" in c.lower() or "layout" in c.lower() or
    "bedroom" in c.lower() or "zone" in c.lower() or
    "open" in c.lower() or "relationship" in c.lower()
    for c in chips_switch
)
check("CHIPS: atmosphere switch has spatial chip", has_spatial_chip, f"chips={chips_switch}")

# FUNCTIONAL_REASSIGNMENT chips should be specific
chips_func = get_contextual_chips(
    atmosphere_id="warm_modern",
    room_type="living_room",
    iteration=3,
    transformation_type=TransformationType.FUNCTIONAL_REASSIGNMENT,
    secondary_spaces=[],
)
print(f"  FUNC_REASSIGN chips: {chips_func}")
check("CHIPS: functional reassignment -> 4 chips", len(chips_func) == 4, f"count={len(chips_func)}")

# Generic chips (no transformation type) still work
chips_generic = get_contextual_chips(
    atmosphere_id="warm_modern",
    room_type="living_room",
    iteration=1,
)
check("CHIPS: generic -> 4 chips", len(chips_generic) == 4, f"count={len(chips_generic)}")

# No duplicate chips
check("CHIPS: no duplicates switch", len(set(chips_switch)) == len(chips_switch), f"dupes")
check("CHIPS: no duplicates func", len(set(chips_func)) == len(chips_func), f"dupes")


# ── Section 9: "Hello" continuity tests ──────────────────────────────────────

print()
print(SEP)
print("SECTION 9 — Hello continuity tests")
print(SEP)

# Greeting with NO session context → standard greeting
mc_greet = MetaClassification(MetaIntent.GREETING, "en", "en", 0.90)
mem_empty = SessionMemory(session_language="en", message_count=0)
resp_standard = generate_project_aware_greeting(mc_greet, mem_empty, "test")
check("HELLO: no context -> non-empty", len(resp_standard) > 5)
print(f"  Standard greeting: {resp_standard}")

# Greeting WITH session context → project-aware
mem_with_ctx = SessionMemory(
    session_language="en",
    atmosphere_mentioned="warm_modern",
    room_type_mentioned="living_room",
    message_count=3,
)
resp_aware = generate_project_aware_greeting(mc_greet, mem_with_ctx, "test")
check("HELLO: with context -> references project",
      "warm" in resp_aware.lower() or "modern" in resp_aware.lower() or "living" in resp_aware.lower(),
      f"response: {resp_aware}")
check("HELLO: aware response non-empty", len(resp_aware) > 20)
print(f"  Project-aware greeting: {resp_aware}")

# FR greeting with context
mc_greet_fr = MetaClassification(MetaIntent.GREETING, "fr", "fr", 0.90)
mem_fr_ctx = SessionMemory(
    session_language="fr",
    atmosphere_mentioned="japandi_calm",
    room_type_mentioned="bedroom",
    message_count=2,
)
resp_fr_aware = generate_project_aware_greeting(mc_greet_fr, mem_fr_ctx, "test")
check("HELLO: FR with context -> non-empty", len(resp_fr_aware) > 10)
print(f"  FR project-aware greeting: {resp_fr_aware}")

# "hello" mid-session should NOT reset context (meta check, no context loss)
meta_hello = classify_meta_intent("hello")
check("HELLO: 'hello' -> GREETING intent", meta_hello.intent == MetaIntent.GREETING)


# ── Section 10: TransformationType classification correctness ─────────────────

print()
print(SEP)
print("SECTION 10 — TransformationType classification")
print(SEP)

TX_CASES = [
    # (message, expected_type, note)
    ("Make it warmer",                           TransformationType.STYLE_REFINEMENT,       "warmer"),
    ("Push it further",                          TransformationType.STYLE_REFINEMENT,       "push further"),
    ("Make it darker",                           TransformationType.STYLE_REFINEMENT,       "darker"),
    ("More dramatic lighting",                   TransformationType.STYLE_REFINEMENT,       "more dramatic"),
    ("Add a floor lamp",                         TransformationType.OBJECT_EDIT,            "add object"),
    ("Remove the rug",                           TransformationType.OBJECT_EDIT,            "remove object"),
    ("Change the curtains",                      TransformationType.OBJECT_EDIT,            "change object"),
    ("Replace the sofa",                         TransformationType.OBJECT_EDIT,            "replace object"),
    ("Switch to Zen Retreat",                    TransformationType.ATMOSPHERE_SWITCH,      "switch to"),
    ("Try a japandi style",                      TransformationType.ATMOSPHERE_SWITCH,      "named style"),
    ("Redesign the layout",                      TransformationType.LAYOUT_REINTERPRETATION,"redesign layout"),
    ("Rearrange everything",                     TransformationType.LAYOUT_REINTERPRETATION,"rearrange"),
    ("Start over with the layout",               TransformationType.LAYOUT_REINTERPRETATION,"start over"),
    ("Turn the TV area into a sleeping zone",    TransformationType.FUNCTIONAL_REASSIGNMENT,"func reassign"),
    ("Convert this into a home office",          TransformationType.FUNCTIONAL_REASSIGNMENT,"convert"),
    ("Remove the wall between rooms",            TransformationType.STRUCTURAL_CHANGE,      "remove wall"),
    ("Open up the kitchen",                      TransformationType.STRUCTURAL_CHANGE,      "open up"),
    # False-positive guards: design instructions that should NOT be atmosphere switches
    ("Add a rug",                                TransformationType.OBJECT_EDIT,            "add rug not switch"),
    ("Show me the space",                        TransformationType.UNKNOWN,                "vague"),
]

for msg, expected_type, note in TX_CASES:
    tx = classify_transformation(msg)
    check(f"TX: {note} | '{msg}'", tx == expected_type, f"expected {expected_type.value}, got {tx.value}")


# ── Section 11: No regression ─────────────────────────────────────────────────

print()
print(SEP)
print("SECTION 11 — No regression (all waves load cleanly)")
print(SEP)

try:
    from prompt_engine import (
        classify_intent, generate_architect_response,
        generate_chat_response, generate_mixed_response,
        get_suggestion_chips, classify_meta_intent,
        MetaIntent, generate_meta_response,
        build_session_memory, SessionMemory,
        ToneMode, select_tone_mode, generate_human_soft_response,
        EmotionalContext, ResponseLength,
        detect_emotional_context, select_response_length,
        generate_architect_light_response, get_micro_insight,
        TransformationType, classify_transformation,
        build_spatial_preservation_addendum,
        get_contextual_chips, generate_project_aware_greeting,
    )
    print("  [PASS] All Wave 2.5 + 3.1 + 3.2 + 3.3 + 3.4 exports load cleanly")
except Exception as e:
    print(f"  [FAIL] Import regression: {e}")
    errors.append(f"import regression: {e}")

try:
    assert TransformationType.ATMOSPHERE_SWITCH.value == "atmosphere_switch"
    assert TransformationType.FUNCTIONAL_REASSIGNMENT.value == "functional_reassignment"
    assert TransformationType.STRUCTURAL_CHANGE.value == "structural_change"
    print("  [PASS] TransformationType enum values correct")
except Exception as e:
    print(f"  [FAIL] Enum check: {e}")
    errors.append(str(e))


# ── Summary ───────────────────────────────────────────────────────────────────

print()
print(SEP)
if not errors:
    print("RESULT: ALL CHECKS PASSED — Wave 3.4 is ready")
else:
    print(f"RESULT: {len(errors)} FAILURE(S)")
    for e in errors:
        print(f"  - {e}")
print(SEP)
