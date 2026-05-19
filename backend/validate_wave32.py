"""
validate_wave32.py — Wave 3.2 Conversational Continuity + Tone Calibration validation.

Tests:
  1. OPEN_CONVERSATION meta intent (EN + FR)
  2. False-positive guard (design messages must NOT be OPEN_CONVERSATION)
  3. SessionMemory extraction from history
  4. ToneMode selection logic
  5. HUMAN_SOFT response quality (length + language)
  6. No regression — all Wave 3.1 + 2.5 imports still clean

Run with: python validate_wave32.py
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

SEP = "-" * 70

from prompt_engine.meta_intent import classify_meta_intent, MetaIntent
from prompt_engine.meta_response import generate_meta_response
from prompt_engine.conversation_memory import build_session_memory, SessionMemory
from prompt_engine.tone_calibration import (
    ToneMode, select_tone_mode, generate_human_soft_response,
)
from prompt_engine.intent_classifier import ConversationIntent, SubIntent, IntentClassification
from prompt_engine.meta_intent import MetaClassification

errors: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  [PASS] {label}")
    else:
        msg = f"  [FAIL] {label}" + (f": {detail}" if detail else "")
        print(msg)
        errors.append(label + (f": {detail}" if detail else ""))


# ── Section 1: OPEN_CONVERSATION classification ──────────────────────────────

print(SEP)
print("SECTION 1 — OPEN_CONVERSATION meta intent")
print(SEP)

OPEN_CONV_CASES = [
    # (message, note)
    ("I just want to talk",                          "EN open - just want to talk"),
    ("I'm just exploring",                           "EN open - just exploring"),
    ("Just exploring",                               "EN open - just exploring short"),
    ("just thinking",                                "EN open - just thinking"),
    ("I don't know yet",                             "EN open - don't know yet"),
    ("not sure yet",                                 "EN open - not sure yet"),
    ("not sure where to start",                      "EN open - not sure where to start"),
    ("Let me think",                                 "EN open - let me think"),
    ("no idea",                                      "EN open - no idea"),
    ("I'm just browsing",                            "EN open - just browsing"),
    ("just looking for ideas",                       "EN open - looking for ideas"),
    ("I just want to chat",                          "EN open - just want to chat"),
    ("je veux juste explorer",                       "FR open - juste explorer (not stop)"),
    ("juste explorer",                               "FR open - juste explorer"),
    ("je ne sais pas encore",                        "FR open - pas encore"),
    ("laisse-moi réfléchir",                         "FR open - réfléchir"),
    ("je réfléchis encore",                          "FR open - réfléchis"),
    ("pas d'idée encore",                            "FR open - pas d'idée"),
]

for msg, note in OPEN_CONV_CASES:
    mc = classify_meta_intent(msg)
    ok = mc.intent == MetaIntent.OPEN_CONVERSATION
    check(f"{note} | '{msg}'", ok, f"got {mc.intent.value}")
    if ok:
        resp = generate_meta_response(mc)
        print(f"         [{mc.language}] {resp}")


# ── Section 2: False-positive guard for OPEN_CONVERSATION ────────────────────

print()
print(SEP)
print("SECTION 2 — OPEN_CONVERSATION false-positive guard")
print(SEP)

NOT_OPEN_CONV = [
    # Design instructions must NOT become OPEN_CONVERSATION
    ("Add a floor lamp",              MetaIntent.NONE),
    ("Make it darker",                MetaIntent.NONE),
    ("I love this look",              MetaIntent.NONE),
    ("What if we added more wood?",   MetaIntent.NONE),
    ("can you explain?",              MetaIntent.CLARIFICATION),
    ("hello",                         MetaIntent.GREETING),
    ("what do you mean?",             MetaIntent.CONFUSION),
    ("that's not what I meant",       MetaIntent.CORRECTION),
    ("this is not right",             MetaIntent.FRUSTRATION),
    ("don't generate yet",            MetaIntent.STOP_GENERATION),
    ("how are you?",                  MetaIntent.SMALL_TALK),
    ("Ajoute un tableau",             MetaIntent.NONE),
    ("Fais-le plus moderne",          MetaIntent.NONE),
    ("I'm not sure I like the color", MetaIntent.CONFUSION),  # unanchored CONFUSION match
]

for msg, expected_intent in NOT_OPEN_CONV:
    mc = classify_meta_intent(msg)
    ok = mc.intent == expected_intent
    check(
        f"not-open | '{msg}'",
        ok,
        f"expected {expected_intent.value}, got {mc.intent.value}",
    )


# ── Section 3: SessionMemory extraction ──────────────────────────────────────

print()
print(SEP)
print("SECTION 3 — SessionMemory extraction")
print(SEP)

# Empty history
mem = build_session_memory([], detected_language="en")
check("empty history -> en", mem.session_language == "en")
check("empty history -> exploring", mem.is_exploring)
check("empty history -> no atmosphere", mem.atmosphere_mentioned == "")
check("empty history -> message_count=0", mem.message_count == 0)

# Single French message
hist1 = [{"role": "user", "content": "Je voudrais un salon japandi"}]
mem = build_session_memory(hist1, detected_language="fr")
check("FR history -> session_lang=fr", mem.session_language == "fr", f"got {mem.session_language}")
check("FR history -> japandi detected", mem.atmosphere_mentioned == "japandi_calm", f"got {mem.atmosphere_mentioned}")
check("FR history -> living_room detected", mem.room_type_mentioned == "living_room", f"got {mem.room_type_mentioned}")
check("FR history -> message_count=1", mem.message_count == 1)

# Keep constraint
hist2 = [
    {"role": "user", "content": "Add a floor lamp"},
    {"role": "ai", "content": "Done."},
    {"role": "user", "content": "Keep the wood tones"},
]
mem = build_session_memory(hist2, detected_language="en")
check("keep constraint extracted", any("Keep the wood tones" in k or "keep" in k.lower() for k in mem.keep_constraints), f"got {mem.keep_constraints}")

# Language override from LANGUAGE_SWITCH
hist3 = [{"role": "user", "content": "Can you speak French?"}]
mem = build_session_memory(hist3, detected_language="en", session_language_override="fr")
check("lang override -> fr", mem.session_language == "fr", f"got {mem.session_language}")

# Exploration signals
hist4 = [{"role": "user", "content": "I'm just looking for ideas"}]
mem = build_session_memory(hist4, detected_language="en")
check("explore signal -> is_exploring", mem.is_exploring)

# Multiple messages — non-exploring with known context
hist5 = [
    {"role": "user", "content": "Make it warm modern"},
    {"role": "ai", "content": "Done."},
    {"role": "user", "content": "Add more plants"},
]
mem = build_session_memory(hist5, detected_language="en")
check("warm_modern detected in history", mem.atmosphere_mentioned == "warm_modern", f"got {mem.atmosphere_mentioned}")
check("message_count=2", mem.message_count == 2)


# ── Section 4: ToneMode selection ────────────────────────────────────────────

print()
print(SEP)
print("SECTION 4 — ToneMode selection")
print(SEP)

meta_none = MetaClassification(MetaIntent.NONE, "en", "en", 0.0)

def make_intent(intent: ConversationIntent, sub: SubIntent, conf: float) -> IntentClassification:
    return IntentClassification(intent=intent, sub_intent=sub, confidence=conf, reasoning="test")

mem_exploring = build_session_memory([], detected_language="en")
mem_with_context = build_session_memory(
    [{"role": "user", "content": "I like warm modern living rooms"}],
    detected_language="en"
)

# GENERAL + low confidence + exploring -> HUMAN_SOFT
tone = select_tone_mode(MetaIntent.NONE, SubIntent.GENERAL, 0.2, mem_exploring)
check("GENERAL + low conf -> HUMAN_SOFT", tone == ToneMode.HUMAN_SOFT, f"got {tone.value}")

# GENERAL + normal confidence -> ARCHITECT_ACTIVE
tone = select_tone_mode(MetaIntent.NONE, SubIntent.GENERAL, 0.7, mem_exploring)
check("GENERAL + high conf -> ARCHITECT_ACTIVE", tone == ToneMode.ARCHITECT_ACTIVE, f"got {tone.value}")

# QUESTION -> ARCHITECT_LIGHT
tone = select_tone_mode(MetaIntent.NONE, SubIntent.QUESTION, 0.8, mem_with_context)
check("QUESTION -> ARCHITECT_LIGHT", tone == ToneMode.ARCHITECT_LIGHT, f"got {tone.value}")

# PRAISE -> ARCHITECT_LIGHT
tone = select_tone_mode(MetaIntent.NONE, SubIntent.PRAISE, 0.9, mem_with_context)
check("PRAISE -> ARCHITECT_LIGHT", tone == ToneMode.ARCHITECT_LIGHT, f"got {tone.value}")

# LOCAL_EDIT -> ARCHITECT_ACTIVE
tone = select_tone_mode(MetaIntent.NONE, SubIntent.LOCAL_EDIT, 0.85, mem_with_context)
check("LOCAL_EDIT -> ARCHITECT_ACTIVE", tone == ToneMode.ARCHITECT_ACTIVE, f"got {tone.value}")

# REFINE_ATMOSPHERE -> ARCHITECT_ACTIVE
tone = select_tone_mode(MetaIntent.NONE, SubIntent.REFINE_ATMOSPHERE, 0.80, mem_with_context)
check("REFINE_ATMOSPHERE -> ARCHITECT_ACTIVE", tone == ToneMode.ARCHITECT_ACTIVE, f"got {tone.value}")

# REDESIGN -> ARCHITECT_ACTIVE
tone = select_tone_mode(MetaIntent.NONE, SubIntent.REDESIGN, 0.95, mem_with_context)
check("REDESIGN -> ARCHITECT_ACTIVE", tone == ToneMode.ARCHITECT_ACTIVE, f"got {tone.value}")


# ── Section 5: HUMAN_SOFT response quality ───────────────────────────────────

print()
print(SEP)
print("SECTION 5 — HUMAN_SOFT response quality")
print(SEP)

SOFT_CASES = [
    (SessionMemory(session_language="en", is_exploring=True, message_count=0),   SubIntent.GENERAL,  "EN exploring + new session"),
    (SessionMemory(session_language="fr", is_exploring=True, message_count=0),   SubIntent.GENERAL,  "FR exploring + new session"),
    (SessionMemory(session_language="en", is_exploring=False, message_count=3,
                   atmosphere_mentioned="warm_modern"),                           SubIntent.GENERAL,  "EN with context"),
    (SessionMemory(session_language="fr", is_exploring=False, message_count=2,
                   room_type_mentioned="living_room"),                            SubIntent.GENERAL,  "FR with context"),
    (SessionMemory(session_language="en", is_exploring=False, message_count=2),  SubIntent.GENERAL,  "EN general soft"),
    (SessionMemory(session_language="fr", is_exploring=False, message_count=2),  SubIntent.GENERAL,  "FR general soft"),
]

for mem, sub, label in SOFT_CASES:
    resp = generate_human_soft_response(mem, sub, seed_extra="test")
    length_ok = 10 < len(resp) < 250
    check(f"length OK | {label}", length_ok, f"len={len(resp)}")
    print(f"         [{mem.session_language}] {resp}")


# ── Section 6: OPEN_CONVERSATION response quality ────────────────────────────

print()
print(SEP)
print("SECTION 6 — OPEN_CONVERSATION response quality")
print(SEP)

OC_RESPONSE_CASES = [
    ("en", "EN open conversation response"),
    ("fr", "FR open conversation response"),
]

for lang, label in OC_RESPONSE_CASES:
    mc = MetaClassification(MetaIntent.OPEN_CONVERSATION, lang, lang, 0.80)
    resp = generate_meta_response(mc, seed_extra="test")
    length_ok = 10 < len(resp) < 200
    check(f"length OK | {label}", length_ok, f"len={len(resp)}")
    print(f"         [{lang}] {resp}")


# ── Section 7: No regression ─────────────────────────────────────────────────

print()
print(SEP)
print("SECTION 7 — No regression (Wave 2.5 + 3.1 + 3.2 imports clean)")
print(SEP)

try:
    from prompt_engine import (
        classify_intent, generate_architect_response,
        generate_chat_response, generate_mixed_response,
        get_suggestion_chips, classify_meta_intent,
        MetaIntent, generate_meta_response,
        build_session_memory, SessionMemory,
        ToneMode, select_tone_mode, generate_human_soft_response,
    )
    print("  [PASS] All Wave 2.5 + 3.1 + 3.2 exports load cleanly")
except Exception as e:
    print(f"  [FAIL] Import regression: {e}")
    errors.append(f"import regression: {e}")

try:
    from prompt_engine.edit_intent import EditMode
    from prompt_engine.intent_classifier import ConversationIntent, SubIntent
    from prompt_engine.conversation_memory import build_session_memory
    from prompt_engine.tone_calibration import generate_human_soft_response
    print("  [PASS] All Wave 3.2 modules accessible")
except Exception as e:
    print(f"  [FAIL] {e}")
    errors.append(str(e))

# Verify OPEN_CONVERSATION in MetaIntent
try:
    assert MetaIntent.OPEN_CONVERSATION.value == "open_conversation"
    print("  [PASS] MetaIntent.OPEN_CONVERSATION exists")
except Exception as e:
    print(f"  [FAIL] MetaIntent.OPEN_CONVERSATION: {e}")
    errors.append(str(e))

# Verify ToneMode enum
try:
    assert ToneMode.HUMAN_SOFT.value == "human_soft"
    assert ToneMode.ARCHITECT_LIGHT.value == "architect_light"
    assert ToneMode.ARCHITECT_ACTIVE.value == "architect_active"
    print("  [PASS] ToneMode enum values correct")
except Exception as e:
    print(f"  [FAIL] ToneMode: {e}")
    errors.append(str(e))


# ── Summary ───────────────────────────────────────────────────────────────────

print()
print(SEP)
if not errors:
    print("RESULT: ALL CHECKS PASSED — Wave 3.2 is ready")
else:
    print(f"RESULT: {len(errors)} FAILURE(S)")
    for e in errors:
        print(f"  - {e}")
print(SEP)
