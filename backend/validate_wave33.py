"""
validate_wave33.py — Wave 3.3 Response Quality Engine validation.

Tests:
  1. EmotionalContext detection (EN + FR)
  2. ResponseLength calibration
  3. generate_architect_light_response — all contexts, all lengths, bilingual
  4. get_micro_insight — all room types
  5. ToneMode selection with emotional context (regression)
  6. Spec validation examples (the 6 test cases from the spec)
  7. No regression — all prior waves load cleanly

Run with: python validate_wave33.py
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

SEP = "-" * 70

from prompt_engine.response_quality import (
    EmotionalContext, ResponseLength,
    detect_emotional_context, select_response_length,
    generate_architect_light_response, get_micro_insight,
)
from prompt_engine.tone_calibration import ToneMode, select_tone_mode
from prompt_engine.meta_intent import classify_meta_intent, MetaIntent, MetaClassification
from prompt_engine.intent_classifier import SubIntent
from prompt_engine.conversation_memory import build_session_memory

errors: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  [PASS] {label}")
    else:
        msg = f"  [FAIL] {label}" + (f": {detail}" if detail else "")
        print(msg)
        errors.append(label + (f": {detail}" if detail else ""))


# ── Section 1: EmotionalContext detection ────────────────────────────────────

print(SEP)
print("SECTION 1 — EmotionalContext detection")
print(SEP)

EC_CASES = [
    # ACKNOWLEDGMENT — anchored brief reactions
    ("Interesting.",                EmotionalContext.ACKNOWLEDGMENT, "EN brief - interesting"),
    ("Hmm.",                        EmotionalContext.ACKNOWLEDGMENT, "EN brief - hmm"),
    ("Ok.",                         EmotionalContext.ACKNOWLEDGMENT, "EN brief - ok"),
    ("I see.",                      EmotionalContext.ACKNOWLEDGMENT, "EN brief - I see"),
    ("Right.",                      EmotionalContext.ACKNOWLEDGMENT, "EN brief - right"),
    ("Got it.",                     EmotionalContext.ACKNOWLEDGMENT, "EN brief - got it"),
    ("Yeah.",                       EmotionalContext.ACKNOWLEDGMENT, "EN brief - yeah"),
    ("Intéressant.",                EmotionalContext.ACKNOWLEDGMENT, "FR brief - intéressant"),
    ("D'accord.",                   EmotionalContext.ACKNOWLEDGMENT, "FR brief - d'accord"),
    # PRAISE
    ("I love it.",                  EmotionalContext.PRAISE,        "EN praise - love it"),
    ("That's perfect.",             EmotionalContext.PRAISE,        "EN praise - perfect"),
    ("It looks amazing.",           EmotionalContext.PRAISE,        "EN praise - amazing"),
    ("Exactly that.",               EmotionalContext.PRAISE,        "EN praise - exactly"),
    ("J'adore.",                    EmotionalContext.PRAISE,        "FR praise - j'adore"),
    # HESITATION
    ("Not really sure.",            EmotionalContext.HESITATION,    "EN hesitation - not really sure"),
    ("I'm not quite convinced.",    EmotionalContext.HESITATION,    "EN hesitation - not convinced"),
    ("Not entirely sure.",          EmotionalContext.HESITATION,    "EN hesitation - not entirely"),
    ("Pas vraiment sûr.",           EmotionalContext.HESITATION,    "FR hesitation - pas vraiment"),
    # EXPLORATION
    ("Maybe something warmer?",     EmotionalContext.EXPLORATION,   "EN exploration - maybe"),
    ("What if we tried darker?",    EmotionalContext.EXPLORATION,   "EN exploration - what if"),
    ("What about more plants?",     EmotionalContext.EXPLORATION,   "EN exploration - what about"),
    ("How about a rug?",            EmotionalContext.EXPLORATION,   "EN exploration - how about"),
    ("Peut-être quelque chose de plus chaud?", EmotionalContext.EXPLORATION, "FR exploration - peut-être"),
    # CURIOSITY
    ("What do you think about walnut?",   EmotionalContext.CURIOSITY, "EN curiosity - what do you think"),
    ("Why does the room feel small?",     EmotionalContext.CURIOSITY, "EN curiosity - why"),
    ("Would this work here?",             EmotionalContext.CURIOSITY, "EN curiosity - would this"),
    ("How would that look?",              EmotionalContext.CURIOSITY, "EN curiosity - how would"),
    ("Do you think this is right?",       EmotionalContext.CURIOSITY, "EN curiosity - do you think"),
    ("Pourquoi ça paraît petit?",         EmotionalContext.CURIOSITY, "FR curiosity - pourquoi"),
    # NEUTRAL — should NOT match any of the above
    ("Add a floor lamp.",           EmotionalContext.NEUTRAL,       "EN neutral - design instruction"),
    ("Make it darker.",             EmotionalContext.NEUTRAL,       "EN neutral - make it"),
    ("I want a warmer palette.",    EmotionalContext.NEUTRAL,       "EN neutral - want statement"),
    ("Ajoute un tableau.",          EmotionalContext.NEUTRAL,       "FR neutral - design instruction"),
]

for msg, expected_ec, note in EC_CASES:
    ec = detect_emotional_context(msg)
    check(f"{note} | '{msg}'", ec == expected_ec, f"expected {expected_ec.value}, got {ec.value}")


# ── Section 2: ResponseLength calibration ────────────────────────────────────

print()
print(SEP)
print("SECTION 2 — ResponseLength calibration")
print(SEP)

LENGTH_CASES = [
    # ACKNOWLEDGMENT → always SHORT
    ("Interesting.",    EmotionalContext.ACKNOWLEDGMENT, ResponseLength.SHORT,    "ACKNOWLEDGMENT -> SHORT"),
    ("Hmm.",            EmotionalContext.ACKNOWLEDGMENT, ResponseLength.SHORT,    "ACKNOWLEDGMENT hmm -> SHORT"),
    # HESITATION
    ("Not sure.",       EmotionalContext.HESITATION,     ResponseLength.SHORT,    "HESITATION short msg -> SHORT"),
    ("I'm not entirely sure which direction to go with this space.",
                        EmotionalContext.HESITATION,     ResponseLength.MEDIUM,   "HESITATION long msg -> MEDIUM"),
    # PRAISE
    ("Perfect.",        EmotionalContext.PRAISE,         ResponseLength.SHORT,    "PRAISE short -> SHORT"),
    ("I really love how this is coming together.",
                        EmotionalContext.PRAISE,         ResponseLength.MEDIUM,   "PRAISE long -> MEDIUM"),
    # EXPLORATION → MEDIUM
    ("Maybe something warmer?", EmotionalContext.EXPLORATION, ResponseLength.MEDIUM, "EXPLORATION -> MEDIUM"),
    # CURIOSITY
    ("What do you think?",      EmotionalContext.CURIOSITY,   ResponseLength.MEDIUM, "CURIOSITY simple -> MEDIUM"),
    ("Why does the room feel small?",
                                EmotionalContext.CURIOSITY,   ResponseLength.EXTENDED, "CURIOSITY why deep -> EXTENDED"),
    ("How does lighting affect the mood?",
                                EmotionalContext.CURIOSITY,   ResponseLength.EXTENDED, "CURIOSITY how deep -> EXTENDED"),
    # NEUTRAL
    ("Try this.",       EmotionalContext.NEUTRAL,        ResponseLength.SHORT,    "NEUTRAL very short -> SHORT"),
    ("I think we should go warmer overall.",
                        EmotionalContext.NEUTRAL,        ResponseLength.MEDIUM,   "NEUTRAL longer -> MEDIUM"),
]

for msg, ec, expected_len, note in LENGTH_CASES:
    length = select_response_length(msg, ec)
    check(f"{note}", length == expected_len, f"expected {expected_len.value}, got {length.value}")


# ── Section 3: generate_architect_light_response quality ─────────────────────

print()
print(SEP)
print("SECTION 3 — generate_architect_light_response quality")
print(SEP)

LIGHT_CASES = [
    (EmotionalContext.CURIOSITY,     ResponseLength.SHORT,    "en", "living_room",  "EN curiosity SHORT"),
    (EmotionalContext.CURIOSITY,     ResponseLength.MEDIUM,   "en", "bedroom",      "EN curiosity MEDIUM"),
    (EmotionalContext.CURIOSITY,     ResponseLength.EXTENDED, "en", "kitchen",      "EN curiosity EXTENDED"),
    (EmotionalContext.EXPLORATION,   ResponseLength.SHORT,    "en", "",             "EN exploration SHORT"),
    (EmotionalContext.EXPLORATION,   ResponseLength.MEDIUM,   "en", "living_room",  "EN exploration MEDIUM"),
    (EmotionalContext.ACKNOWLEDGMENT, ResponseLength.SHORT,   "en", "",             "EN acknowledgment SHORT"),
    (EmotionalContext.HESITATION,    ResponseLength.SHORT,    "en", "",             "EN hesitation SHORT"),
    (EmotionalContext.HESITATION,    ResponseLength.MEDIUM,   "en", "",             "EN hesitation MEDIUM"),
    (EmotionalContext.PRAISE,        ResponseLength.SHORT,    "en", "",             "EN praise SHORT"),
    (EmotionalContext.PRAISE,        ResponseLength.MEDIUM,   "en", "bedroom",      "EN praise MEDIUM"),
    (EmotionalContext.NEUTRAL,       ResponseLength.SHORT,    "en", "",             "EN neutral SHORT"),
    (EmotionalContext.NEUTRAL,       ResponseLength.MEDIUM,   "en", "home_office",  "EN neutral MEDIUM"),
    # French
    (EmotionalContext.CURIOSITY,     ResponseLength.MEDIUM,   "fr", "salon",        "FR curiosity MEDIUM"),
    (EmotionalContext.EXPLORATION,   ResponseLength.MEDIUM,   "fr", "",             "FR exploration MEDIUM"),
    (EmotionalContext.ACKNOWLEDGMENT, ResponseLength.SHORT,   "fr", "",             "FR acknowledgment SHORT"),
    (EmotionalContext.HESITATION,    ResponseLength.SHORT,    "fr", "",             "FR hesitation SHORT"),
    (EmotionalContext.PRAISE,        ResponseLength.SHORT,    "fr", "",             "FR praise SHORT"),
    (EmotionalContext.NEUTRAL,       ResponseLength.MEDIUM,   "fr", "",             "FR neutral MEDIUM"),
]

for ec, length, lang, room, label in LIGHT_CASES:
    resp = generate_architect_light_response(
        user_message="test",
        atmosphere_id="warm_modern",
        room_type=room,
        emotional_context=ec,
        length=length,
        language=lang,
        seed_extra="validation",
    )
    len_ok = 5 < len(resp) < 400
    check(f"length OK | {label}", len_ok, f"len={len(resp)}: {resp[:80]}")
    print(f"         [{lang}/{ec.value}/{length.value}] {resp}")


# ── Section 4: get_micro_insight ─────────────────────────────────────────────

print()
print(SEP)
print("SECTION 4 — get_micro_insight")
print(SEP)

ROOMS = [
    "living_room", "bedroom", "kitchen", "bathroom",
    "home_office", "dining_room", "entrance_hall", "unknown_room",
]

for room in ROOMS:
    for lang in ("en", "fr"):
        insight = get_micro_insight(room_type=room, language=lang, seed=f"{room}{lang}")
        ok = len(insight) > 10
        check(f"insight [{lang}] | {room}", ok, f"len={len(insight)}")
        if lang == "en":
            print(f"         [{room}] {insight}")


# ── Section 5: ToneMode selection with emotional context ─────────────────────

print()
print(SEP)
print("SECTION 5 — ToneMode selection with emotional context (Wave 3.3 additions)")
print(SEP)

mem = build_session_memory([], detected_language="en")

# ACKNOWLEDGMENT always → ARCHITECT_LIGHT regardless of sub_intent
tone = select_tone_mode(MetaIntent.NONE, SubIntent.GENERAL, 0.7, mem, EmotionalContext.ACKNOWLEDGMENT)
check("ACKNOWLEDGMENT -> ARCHITECT_LIGHT", tone == ToneMode.ARCHITECT_LIGHT, f"got {tone.value}")

tone = select_tone_mode(MetaIntent.NONE, SubIntent.LOCAL_EDIT, 0.85, mem, EmotionalContext.ACKNOWLEDGMENT)
check("ACKNOWLEDGMENT + LOCAL_EDIT -> ARCHITECT_LIGHT", tone == ToneMode.ARCHITECT_LIGHT, f"got {tone.value}")

# HESITATION + GENERAL → ARCHITECT_LIGHT
tone = select_tone_mode(MetaIntent.NONE, SubIntent.GENERAL, 0.6, mem, EmotionalContext.HESITATION)
check("HESITATION + GENERAL -> ARCHITECT_LIGHT", tone == ToneMode.ARCHITECT_LIGHT, f"got {tone.value}")

# HESITATION + LOCAL_EDIT → ARCHITECT_ACTIVE (hesitation doesn't override specific design intent)
tone = select_tone_mode(MetaIntent.NONE, SubIntent.LOCAL_EDIT, 0.85, mem, EmotionalContext.HESITATION)
check("HESITATION + LOCAL_EDIT -> ARCHITECT_ACTIVE", tone == ToneMode.ARCHITECT_ACTIVE, f"got {tone.value}")

# CURIOSITY (emotional context) + QUESTION (sub_intent) → ARCHITECT_LIGHT
tone = select_tone_mode(MetaIntent.NONE, SubIntent.QUESTION, 0.8, mem, EmotionalContext.CURIOSITY)
check("CURIOSITY + QUESTION -> ARCHITECT_LIGHT", tone == ToneMode.ARCHITECT_LIGHT, f"got {tone.value}")

# PRAISE → ARCHITECT_LIGHT (unchanged from Wave 3.2)
tone = select_tone_mode(MetaIntent.NONE, SubIntent.PRAISE, 0.9, mem, EmotionalContext.PRAISE)
check("PRAISE -> ARCHITECT_LIGHT", tone == ToneMode.ARCHITECT_LIGHT, f"got {tone.value}")

# NEUTRAL + REDESIGN → ARCHITECT_ACTIVE (generation path unchanged)
tone = select_tone_mode(MetaIntent.NONE, SubIntent.REDESIGN, 0.95, mem, EmotionalContext.NEUTRAL)
check("NEUTRAL + REDESIGN -> ARCHITECT_ACTIVE", tone == ToneMode.ARCHITECT_ACTIVE, f"got {tone.value}")


# ── Section 6: Spec validation examples ──────────────────────────────────────

print()
print(SEP)
print("SECTION 6 — Spec validation examples")
print(SEP)

# TEST 3: "What do you think about dark walnut?" → CURIOSITY + MEDIUM → ARCHITECT_LIGHT
msg = "What do you think about dark walnut?"
ec = detect_emotional_context(msg)
length = select_response_length(msg, ec)
check("TEST3: curiosity detected", ec == EmotionalContext.CURIOSITY, f"got {ec.value}")
check("TEST3: medium length", length == ResponseLength.MEDIUM, f"got {length.value}")
resp = generate_architect_light_response("", "warm_modern", "living_room", ec, length, "en", "test3")
check("TEST3: response length OK", 10 < len(resp) < 300, f"len={len(resp)}")
print(f"  TEST3 response: {resp}")

# TEST 5: "Interesting." → ACKNOWLEDGMENT + SHORT → ARCHITECT_LIGHT
msg = "Interesting."
ec = detect_emotional_context(msg)
length = select_response_length(msg, ec)
check("TEST5: acknowledgment detected", ec == EmotionalContext.ACKNOWLEDGMENT, f"got {ec.value}")
check("TEST5: short length", length == ResponseLength.SHORT, f"got {length.value}")
resp = generate_architect_light_response("", "warm_modern", "", ec, length, "en", "test5")
check("TEST5: response short", len(resp) < 120, f"len={len(resp)}")
print(f"  TEST5 response: {resp}")

# TEST 6: "Why does the room feel small?" → CURIOSITY + EXTENDED → ARCHITECT_LIGHT
msg = "Why does the room feel small?"
ec = detect_emotional_context(msg)
length = select_response_length(msg, ec)
check("TEST6: curiosity detected", ec == EmotionalContext.CURIOSITY, f"got {ec.value}")
check("TEST6: extended length", length == ResponseLength.EXTENDED, f"got {length.value}")
resp = generate_architect_light_response("", "japandi_calm", "living_room", ec, length, "en", "test6")
check("TEST6: response has substance", len(resp) > 80, f"len={len(resp)}")
print(f"  TEST6 response: {resp}")

# Micro-insight embedded naturally (room type = living_room)
insight = get_micro_insight(room_type="living_room", language="en", seed="test6")
check("TEST6: micro-insight non-empty", len(insight) > 20, f"insight: {insight}")
print(f"  TEST6 micro-insight: {insight}")


# ── Section 7: No regression ─────────────────────────────────────────────────

print()
print(SEP)
print("SECTION 7 — No regression (all waves load cleanly)")
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
    )
    print("  [PASS] All Wave 2.5 + 3.1 + 3.2 + 3.3 exports load cleanly")
except Exception as e:
    print(f"  [FAIL] Import regression: {e}")
    errors.append(f"import regression: {e}")

try:
    from prompt_engine.edit_intent import EditMode
    from prompt_engine.intent_classifier import ConversationIntent, SubIntent
    from prompt_engine.conversation_memory import build_session_memory
    from prompt_engine.tone_calibration import generate_human_soft_response
    from prompt_engine.response_quality import generate_architect_light_response, get_micro_insight
    print("  [PASS] All Wave 3.3 modules accessible")
except Exception as e:
    print(f"  [FAIL] {e}")
    errors.append(str(e))

try:
    assert EmotionalContext.CURIOSITY.value == "curiosity"
    assert EmotionalContext.ACKNOWLEDGMENT.value == "acknowledgment"
    assert ResponseLength.EXTENDED.value == "extended"
    print("  [PASS] EmotionalContext + ResponseLength enum values correct")
except Exception as e:
    print(f"  [FAIL] Enum check: {e}")
    errors.append(str(e))


# ── Summary ───────────────────────────────────────────────────────────────────

print()
print(SEP)
if not errors:
    print("RESULT: ALL CHECKS PASSED — Wave 3.3 is ready")
else:
    print(f"RESULT: {len(errors)} FAILURE(S)")
    for e in errors:
        print(f"  - {e}")
print(SEP)
