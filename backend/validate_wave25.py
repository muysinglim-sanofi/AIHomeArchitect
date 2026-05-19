"""
validate_wave25.py — Wave 2.5 conversation layer validation.

Tests:
  1. Intent classifier — representative messages at iterations 1 and 2+
  2. Architect response generation — iteration 1 and refinement paths
  3. Chat response generation — QUESTION and PRAISE sub_intents
  4. Mixed response generation
  5. Suggestion chips — iteration 1, local edit, style refinement
  6. Cross-atmosphere coverage — all 10 atmospheres respond without error
  7. Edge cases — empty message, unknown atmosphere, no room

Run with: python validate_wave25.py
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

SEP = "-" * 70
PASS = "PASS"
FAIL = "FAIL"

errors: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  [PASS] {label}")
    else:
        msg = f"  [FAIL] {label}" + (f": {detail}" if detail else "")
        print(msg)
        errors.append(f"{label}" + (f": {detail}" if detail else ""))


# ── Import check ──────────────────────────────────────────────────────────────

print(SEP)
print("SECTION 1 — Import validation")
print(SEP)

try:
    from prompt_engine.intent_classifier import (
        classify_intent,
        ConversationIntent,
        SubIntent,
        IntentClassification,
    )
    print("  [PASS] intent_classifier imports OK")
except Exception as e:
    print(f"  [FAIL] intent_classifier import: {e}")
    errors.append(f"intent_classifier import: {e}")

try:
    from prompt_engine.architect_response import (
        generate_architect_response,
        generate_chat_response,
        generate_mixed_response,
    )
    print("  [PASS] architect_response imports OK")
except Exception as e:
    print(f"  [FAIL] architect_response import: {e}")
    errors.append(f"architect_response import: {e}")

try:
    from prompt_engine.suggestion_engine import get_suggestion_chips
    print("  [PASS] suggestion_engine imports OK")
except Exception as e:
    print(f"  [FAIL] suggestion_engine import: {e}")
    errors.append(f"suggestion_engine import: {e}")

try:
    from prompt_engine import (
        classify_intent,
        generate_architect_response,
        generate_chat_response,
        generate_mixed_response,
        get_suggestion_chips,
        ConversationIntent,
        SubIntent,
    )
    print("  [PASS] prompt_engine __init__ exports OK")
except Exception as e:
    print(f"  [FAIL] prompt_engine __init__ export: {e}")
    errors.append(f"prompt_engine __init__ export: {e}")

try:
    from prompt_engine.edit_intent import EditMode
    from prompt_engine.refinement_memory import parse_history, RefinementState
    from prompt_engine.atmosphere_dna import label_to_atmosphere_id
    print("  [PASS] dependency imports OK")
except Exception as e:
    print(f"  [FAIL] dependency imports: {e}")
    errors.append(f"dependency imports: {e}")


# ── Intent classifier ─────────────────────────────────────────────────────────

print()
print(SEP)
print("SECTION 2 — Intent classifier")
print(SEP)

test_cases = [
    # (iteration, message, expected_intent, expected_sub_intent)
    (1, "make it warm modern", ConversationIntent.GENERATE, SubIntent.REDESIGN),
    (1, "any message iteration 1", ConversationIntent.GENERATE, SubIntent.REDESIGN),
    (2, "I love it!", ConversationIntent.CONVERSATION, SubIntent.PRAISE),
    (2, "This looks amazing", ConversationIntent.CONVERSATION, SubIntent.PRAISE),
    (2, "What if we added a skylight?", ConversationIntent.CONVERSATION, SubIntent.QUESTION),
    (2, "What do you think about the lighting?", ConversationIntent.CONVERSATION, SubIntent.QUESTION),
    (2, "Can we open up the wall?", ConversationIntent.GENERATE, SubIntent.STRUCTURAL_CHANGE),
    (2, "Try japandi instead", ConversationIntent.GENERATE, SubIntent.REDIRECT),
    (2, "Switch to dark contemporary", ConversationIntent.GENERATE, SubIntent.REDIRECT),
    (2, "Make it darker and more dramatic", ConversationIntent.GENERATE, SubIntent.REFINE_ATMOSPHERE),
    (2, "Add a floor lamp", ConversationIntent.GENERATE, SubIntent.LOCAL_EDIT),
    (2, "Change the rug colour", ConversationIntent.GENERATE, SubIntent.LOCAL_EDIT),
    (2, "What do you think about adding more texture?", ConversationIntent.MIXED, None),
    (2, "ok", ConversationIntent.CONVERSATION, SubIntent.GENERAL),
]

for iteration, message, expected_intent, expected_sub in test_cases:
    result = classify_intent(message, iteration)
    intent_ok = result.intent == expected_intent
    sub_ok = expected_sub is None or result.sub_intent == expected_sub
    label = f"iter={iteration} | '{message[:40]}'"
    if intent_ok and sub_ok:
        print(f"  [PASS] {label}")
        print(f"         -> {result.intent.value} / {result.sub_intent.value} (conf={result.confidence:.2f})")
    else:
        detail = f"expected {expected_intent.value}/{expected_sub}, got {result.intent.value}/{result.sub_intent.value}"
        print(f"  [FAIL] {label}: {detail}")
        errors.append(f"classify_intent: {detail}")


# ── Architect response — generation mode ─────────────────────────────────────

print()
print(SEP)
print("SECTION 3 — generate_architect_response()")
print(SEP)

ATM_ROOM_PAIRS = [
    ("warm_modern", "living_room"),
    ("japandi_calm", "master_bedroom"),
    ("soft_luxury", "bathroom"),
    ("zen_retreat", "bathroom"),
    ("nordic_warmth", "living_room"),
    ("dark_contemporary", "kitchen"),
    ("nature_retreat", "terrace"),
    ("desert_luxe", "living_room"),
    ("bali_sanctuary", "master_bedroom"),
    ("tropical_escape", "terrace"),
]

empty_state = RefinementState()

for atm, room in ATM_ROOM_PAIRS:
    try:
        result = generate_architect_response(
            atmosphere_id=atm,
            room_type=room,
            iteration=1,
            edit_mode=EditMode.FIRST_VISION,
            refinement_state=empty_state,
            sub_intent=SubIntent.REDESIGN,
            secondary_spaces=[],
            user_message="design this space",
        )
        check(
            f"Vision 1 | {atm} / {room}",
            len(result) > 20,
            f"response too short: '{result[:50]}'",
        )
        check(
            f"Vision 1 length | {atm} / {room}",
            len(result) < 600,
            f"response too long: {len(result)} chars",
        )
        print(f"         Preview: {result[:100]}...")
    except Exception as e:
        print(f"  [FAIL] Vision 1 | {atm} / {room}: {e}")
        errors.append(f"generate_architect_response Vision1 {atm}/{room}: {e}")

# Test iteration 2+ paths
print()
print("  --- Iteration 2+ paths ---")

for edit_mode, label in [
    (EditMode.LOCAL_EDIT, "local_edit"),
    (EditMode.STYLE_REFINEMENT, "style_refinement"),
    (EditMode.STRUCTURAL_TRANSFORMATION, "structural"),
]:
    atm, room = "warm_modern", "living_room"
    state = RefinementState(
        keep=["the warm oak floor"],
        add=["a floor lamp"],
        remove=[],
        enhance=["indirect lighting"],
        directions=["warmer tone"],
        latest="add a floor lamp near the reading corner",
    )
    try:
        result = generate_architect_response(
            atmosphere_id=atm,
            room_type=room,
            iteration=3,
            edit_mode=edit_mode,
            refinement_state=state,
            sub_intent=SubIntent.LOCAL_EDIT,
            secondary_spaces=["master_bedroom"],
            user_message="add a floor lamp",
        )
        check(
            f"Iter 3 | {label} | {atm}/{room}",
            len(result) > 10,
        )
        print(f"         Preview: {result[:100]}...")
    except Exception as e:
        print(f"  [FAIL] Iter 3 | {label} | {atm}/{room}: {e}")
        errors.append(f"generate_architect_response iter3 {label}: {e}")

# Secondary spaces note
try:
    result = generate_architect_response(
        atmosphere_id="japandi_calm",
        room_type="living_room",
        iteration=1,
        edit_mode=EditMode.FIRST_VISION,
        refinement_state=empty_state,
        sub_intent=SubIntent.REDESIGN,
        secondary_spaces=["master_bedroom", "kitchen"],
        user_message="design this",
    )
    check(
        "Secondary spaces note | japandi_calm / living_room",
        isinstance(result, str) and len(result) > 0,
    )
    print(f"         Preview: {result[:120]}...")
except Exception as e:
    print(f"  [FAIL] Secondary spaces note: {e}")
    errors.append(f"secondary_spaces note: {e}")


# ── Chat response ─────────────────────────────────────────────────────────────

print()
print(SEP)
print("SECTION 4 — generate_chat_response()")
print(SEP)

chat_cases = [
    ("What if we added more texture?", "warm_modern", "living_room", SubIntent.QUESTION),
    ("I love it, looks perfect!", "japandi_calm", "master_bedroom", SubIntent.PRAISE),
    ("What do you think?", "soft_luxury", "bathroom", SubIntent.QUESTION),
    ("Amazing result", "dark_contemporary", "kitchen", SubIntent.PRAISE),
    ("Maybe warmer lighting?", "nordic_warmth", "living_room", SubIntent.GENERAL),
]

for msg, atm, room, sub in chat_cases:
    try:
        result = generate_chat_response(
            user_message=msg,
            atmosphere_id=atm,
            room_type=room,
            sub_intent=sub,
            secondary_spaces=[],
            refinement_state=empty_state,
        )
        check(
            f"chat | '{msg[:30]}' | {atm}",
            len(result) > 10 and len(result) < 500,
            f"length={len(result)}",
        )
        print(f"         Preview: {result[:100]}...")
    except Exception as e:
        print(f"  [FAIL] chat | '{msg[:30]}' | {atm}: {e}")
        errors.append(f"generate_chat_response {atm} {sub}: {e}")


# ── Mixed response ────────────────────────────────────────────────────────────

print()
print(SEP)
print("SECTION 5 — generate_mixed_response()")
print(SEP)

mixed_cases = [
    ("What if we made it warmer?", "warm_modern", "living_room", SubIntent.REFINE_ATMOSPHERE),
    ("Should we add a different chair?", "soft_luxury", "master_bedroom", SubIntent.LOCAL_EDIT),
    ("What do you think about changing the whole feel?", "zen_retreat", "bathroom", SubIntent.GENERAL),
]

for msg, atm, room, sub in mixed_cases:
    try:
        result = generate_mixed_response(
            user_message=msg,
            atmosphere_id=atm,
            room_type=room,
            sub_intent=sub,
        )
        check(
            f"mixed | '{msg[:40]}' | {sub.value}",
            len(result) > 10 and len(result) < 500,
            f"length={len(result)}",
        )
        print(f"         Preview: {result[:100]}...")
    except Exception as e:
        print(f"  [FAIL] mixed | '{msg[:40]}': {e}")
        errors.append(f"generate_mixed_response {sub}: {e}")


# ── Suggestion chips ──────────────────────────────────────────────────────────

print()
print(SEP)
print("SECTION 6 — get_suggestion_chips()")
print(SEP)

chip_cases = [
    ("warm_modern", "living_room", 1, EditMode.FIRST_VISION),
    ("japandi_calm", "master_bedroom", 2, EditMode.LOCAL_EDIT),
    ("soft_luxury", "bathroom", 3, EditMode.STYLE_REFINEMENT),
    ("dark_contemporary", "kitchen", 2, EditMode.STRUCTURAL_TRANSFORMATION),
    ("bali_sanctuary", "terrace", 1, EditMode.FIRST_VISION),
    ("tropical_escape", "", 1, EditMode.FIRST_VISION),      # no room
    ("unknown_atm", "living_room", 2, EditMode.LOCAL_EDIT),  # unknown atmosphere
]

for atm, room, iteration, edit_mode in chip_cases:
    try:
        chips = get_suggestion_chips(
            atmosphere_id=atm,
            room_type=room,
            iteration=iteration,
            edit_mode=edit_mode,
            sub_intent=SubIntent.GENERAL,
            count=4,
        )
        check(
            f"chips | {atm} / {room or '(none)'} | iter={iteration}",
            isinstance(chips, list) and 1 <= len(chips) <= 4,
            f"got {len(chips)} chips",
        )
        check(
            f"chips no duplicates | {atm}",
            len(chips) == len(set(chips)),
            f"duplicates found: {chips}",
        )
        print(f"         Chips: {chips}")
    except Exception as e:
        print(f"  [FAIL] chips | {atm} / {room}: {e}")
        errors.append(f"get_suggestion_chips {atm}/{room}: {e}")


# ── All-atmosphere coverage ───────────────────────────────────────────────────

print()
print(SEP)
print("SECTION 7 — All-atmosphere response coverage")
print(SEP)

ALL_ATMOSPHERES = [
    "warm_modern", "japandi_calm", "soft_luxury", "zen_retreat", "nordic_warmth",
    "dark_contemporary", "nature_retreat", "desert_luxe", "bali_sanctuary", "tropical_escape",
]

for atm in ALL_ATMOSPHERES:
    try:
        # Vision 1
        r1 = generate_architect_response(
            atmosphere_id=atm, room_type="living_room", iteration=1,
            edit_mode=EditMode.FIRST_VISION, refinement_state=empty_state,
            sub_intent=SubIntent.REDESIGN, secondary_spaces=[], user_message="design",
        )
        # Praise
        r2 = generate_chat_response(
            user_message="love it", atmosphere_id=atm, room_type="living_room",
            sub_intent=SubIntent.PRAISE, secondary_spaces=[], refinement_state=empty_state,
        )
        # Question
        r3 = generate_chat_response(
            user_message="what if darker?", atmosphere_id=atm, room_type="living_room",
            sub_intent=SubIntent.QUESTION, secondary_spaces=[], refinement_state=empty_state,
        )
        # Chips
        r4 = get_suggestion_chips(
            atmosphere_id=atm, room_type="living_room", iteration=2,
            edit_mode=EditMode.STYLE_REFINEMENT, sub_intent=SubIntent.REFINE_ATMOSPHERE,
        )
        all_ok = all(len(r) > 5 for r in [r1, r2, r3]) and isinstance(r4, list)
        check(f"Full coverage | {atm}", all_ok)
    except Exception as e:
        print(f"  [FAIL] Coverage | {atm}: {e}")
        errors.append(f"coverage {atm}: {e}")


# ── Edge cases ────────────────────────────────────────────────────────────────

print()
print(SEP)
print("SECTION 8 — Edge cases")
print(SEP)

# Empty user message
try:
    result = classify_intent("", iteration=2)
    check("classify_intent empty message", result.intent is not None)
    print(f"         -> {result.intent.value} / {result.sub_intent.value}")
except Exception as e:
    print(f"  [FAIL] classify_intent empty message: {e}")
    errors.append(f"classify_intent empty: {e}")

# Unknown atmosphere in response generator
try:
    result = generate_architect_response(
        atmosphere_id="unknown_xyz",
        room_type="living_room",
        iteration=1,
        edit_mode=EditMode.FIRST_VISION,
        refinement_state=empty_state,
        sub_intent=SubIntent.REDESIGN,
        secondary_spaces=[],
        user_message="design",
    )
    check("Unknown atmosphere — no crash", isinstance(result, str) and len(result) > 0)
    print(f"         Preview: {result[:80]}...")
except Exception as e:
    print(f"  [FAIL] Unknown atmosphere: {e}")
    errors.append(f"unknown atmosphere: {e}")

# Unknown room type
try:
    result = generate_architect_response(
        atmosphere_id="warm_modern",
        room_type="unknown_room_xyz",
        iteration=1,
        edit_mode=EditMode.FIRST_VISION,
        refinement_state=empty_state,
        sub_intent=SubIntent.REDESIGN,
        secondary_spaces=[],
        user_message="design",
    )
    check("Unknown room — no crash", isinstance(result, str) and len(result) > 0)
    print(f"         Preview: {result[:80]}...")
except Exception as e:
    print(f"  [FAIL] Unknown room: {e}")
    errors.append(f"unknown room: {e}")

# Very long user message — seed truncation edge case
try:
    long_msg = "add a floor lamp " * 50
    result = classify_intent(long_msg, iteration=2)
    check("Long message — no crash", result.intent is not None)
except Exception as e:
    print(f"  [FAIL] Long message: {e}")
    errors.append(f"long message: {e}")

# No secondary spaces
try:
    result = generate_architect_response(
        atmosphere_id="bali_sanctuary",
        room_type="master_bedroom",
        iteration=1,
        edit_mode=EditMode.FIRST_VISION,
        refinement_state=empty_state,
        sub_intent=SubIntent.REDESIGN,
        secondary_spaces=[],
        user_message="design",
    )
    check("No secondary spaces | bali_sanctuary", len(result) > 0)
except Exception as e:
    print(f"  [FAIL] No secondary spaces: {e}")
    errors.append(f"no secondary spaces: {e}")

# Multiple secondary spaces
try:
    result = generate_architect_response(
        atmosphere_id="warm_modern",
        room_type="living_room",
        iteration=1,
        edit_mode=EditMode.FIRST_VISION,
        refinement_state=empty_state,
        sub_intent=SubIntent.REDESIGN,
        secondary_spaces=["master_bedroom", "kitchen", "entrance_hall"],
        user_message="design",
    )
    check("Multiple secondary spaces — no crash", len(result) > 0)
except Exception as e:
    print(f"  [FAIL] Multiple secondary spaces: {e}")
    errors.append(f"multiple secondary spaces: {e}")


# ── Final summary ─────────────────────────────────────────────────────────────

print()
print(SEP)
if not errors:
    print("RESULT: ALL CHECKS PASSED — Wave 2.5 is ready")
else:
    print(f"RESULT: {len(errors)} FAILURE(S)")
    for e in errors:
        print(f"  - {e}")
print(SEP)
