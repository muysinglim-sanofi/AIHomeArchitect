"""
validate_french_intent.py — French-language intent classification audit.

Tests Wave 2.5 conversation layer against French user messages.
Read-only: no production code is modified.

Run with: python validate_french_intent.py
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

SEP = "-" * 70

from prompt_engine.intent_classifier import classify_intent, ConversationIntent, SubIntent
from prompt_engine.architect_response import (
    generate_architect_response,
    generate_chat_response,
    generate_mixed_response,
)
from prompt_engine.suggestion_engine import get_suggestion_chips
from prompt_engine.edit_intent import EditMode
from prompt_engine.refinement_memory import RefinementState
from prompt_engine.atmosphere_dna import label_to_atmosphere_id

# ── Test context ──────────────────────────────────────────────────────────────
# Simulate a session that is on iteration 2 (post-first-vision)
ATMOSPHERE = "warm_modern"
ROOM_TYPE  = "living_room"
ITERATION  = 2
STYLE_LABEL = "Warm Modern"
EMPTY_STATE = RefinementState()

ATMOSPHERE_ID = label_to_atmosphere_id(STYLE_LABEL)

CASES = [
    {
        "id": 1,
        "message": "Qu'en penses-tu si j'ajoute un tableau sur le mur ?",
        "expected_intent": "conversation or mixed",
        "expected_generate": False,
        "note": "French question — should NOT trigger generation",
    },
    {
        "id": 2,
        "message": "Ajoute un tableau minimaliste sur le mur",
        "expected_intent": "generate",
        "expected_generate": True,
        "note": "French local edit command — should trigger generation",
    },
    {
        "id": 3,
        "message": "Est-ce qu'un canapé plus bas marcherait mieux ?",
        "expected_intent": "conversation or mixed",
        "expected_generate": False,
        "note": "French design question — should NOT trigger generation",
    },
    {
        "id": 4,
        "message": "Ok montre-moi avec un canapé plus bas",
        "expected_intent": "generate or mixed",
        "expected_generate": True,
        "note": "French generation request — should trigger generation",
    },
    {
        "id": 5,
        "message": "Fais-le plus hôtel de luxe",
        "expected_intent": "generate (refine_atmosphere)",
        "expected_generate": True,
        "note": "French refinement — should trigger generation",
    },
]

# ── Run ───────────────────────────────────────────────────────────────────────

print(SEP)
print("Wave 2.5 — French language intent audit")
print(f"Context: atmosphere={ATMOSPHERE_ID}, room={ROOM_TYPE}, iteration={ITERATION}")
print(SEP)

mismatches = []

for case in CASES:
    msg    = case["message"]
    exp_g  = case["expected_generate"]
    cid    = case["id"]

    ic = classify_intent(msg, ITERATION)

    # Determine should_generate (mirrors main.py logic)
    if ic.intent == ConversationIntent.MIXED:
        should_generate = False
    else:
        should_generate = (ic.intent == ConversationIntent.GENERATE)

    # Map sub_intent -> edit_mode for chips (mirrors main.py)
    from prompt_engine.intent_classifier import ConversationIntent as CI, SubIntent as SI
    sub_to_edit = {
        SI.LOCAL_EDIT:         EditMode.LOCAL_EDIT,
        SI.STRUCTURAL_CHANGE:  EditMode.STRUCTURAL_TRANSFORMATION,
        SI.REFINE_ATMOSPHERE:  EditMode.STYLE_REFINEMENT,
    }
    edit_mode = sub_to_edit.get(ic.sub_intent, EditMode.STYLE_REFINEMENT)

    # Generate architect response (mirrors /chat and /generate paths)
    if ic.intent == CI.MIXED:
        ai_message = generate_mixed_response(
            user_message=msg,
            atmosphere_id=ATMOSPHERE_ID,
            room_type=ROOM_TYPE,
            sub_intent=ic.sub_intent,
        )
    else:
        ai_message = generate_chat_response(
            user_message=msg,
            atmosphere_id=ATMOSPHERE_ID,
            room_type=ROOM_TYPE,
            sub_intent=ic.sub_intent,
            secondary_spaces=[],
            refinement_state=EMPTY_STATE,
        )

    chips = get_suggestion_chips(
        atmosphere_id=ATMOSPHERE_ID,
        room_type=ROOM_TYPE,
        iteration=ITERATION,
        edit_mode=edit_mode,
        sub_intent=ic.sub_intent,
        count=4,
    )

    # Outcome verdict
    generate_match = (should_generate == exp_g)
    verdict = "PASS" if generate_match else "FAIL"
    if not generate_match:
        mismatches.append(cid)

    print(f"Test {cid} — {verdict}")
    print(f"  Message      : {msg}")
    print(f"  Expected     : {case['expected_intent']} | generate={exp_g}")
    print(f"  Detected     : {ic.intent.value} / {ic.sub_intent.value} | conf={ic.confidence:.2f}")
    print(f"  Reason       : {ic.reasoning}")
    print(f"  Generate?    : {should_generate}  {'OK' if generate_match else '*** MISMATCH ***'}")
    print(f"  AI message   : {ai_message}")
    print(f"  Chips        : {chips}")
    print(f"  Note         : {case['note']}")
    print()

print(SEP)
if not mismatches:
    print("RESULT: ALL TESTS PASSED")
else:
    print(f"RESULT: {len(mismatches)} MISMATCH(ES) on test(s): {mismatches}")
    print()
    print("DIAGNOSIS:")
    print("  The intent classifier uses English keyword patterns.")
    print("  French messages bypass all regex signals and fall to the")
    print("  length-based fallback at the bottom of classify_intent().")
    print("  French words like 'ajoute', 'montre-moi', 'plus', 'fais'")
    print("  do not match _LOCAL_EDIT, _REFINE, or _QUESTION patterns.")
    print()
    print("RECOMMENDATION:")
    print("  See Wave 2.6 scope — French keyword signal expansion or")
    print("  lightweight normalisation pass before pattern matching.")
print(SEP)
