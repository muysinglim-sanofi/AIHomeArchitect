"""
validate_wave31.py — Wave 3.1 meta conversation intelligence validation.

Tests all spec cases plus edge cases (French variants, false-positive guards).
Read-only: no production code is modified.

Run with: python validate_wave31.py
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

SEP = "-" * 70

from prompt_engine.meta_intent import classify_meta_intent, MetaIntent
from prompt_engine.meta_response import generate_meta_response

errors: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  [PASS] {label}")
    else:
        msg = f"  [FAIL] {label}" + (f": {detail}" if detail else "")
        print(msg)
        errors.append(label + (f": {detail}" if detail else ""))


# ── Section 1: Spec-required cases ───────────────────────────────────────────

SPEC_CASES = [
    # (message, expected_intent, expected_generate, note)
    ("hello",                             MetaIntent.GREETING,        False, "EN greeting"),
    ("thanks",                            MetaIntent.THANKS,          False, "EN thanks"),
    ("thank you",                         MetaIntent.THANKS,          False, "EN thanks long"),
    ("can you speak French?",             MetaIntent.LANGUAGE_SWITCH, False, "EN->FR switch"),
    ("answer in English",                 MetaIntent.LANGUAGE_SWITCH, False, "switch to EN"),
    ("that's not what I meant",           MetaIntent.CORRECTION,      False, "EN correction"),
    ("don't generate yet",                MetaIntent.STOP_GENERATION, False, "stop generation"),
    ("what do you mean?",                 MetaIntent.CONFUSION,       False, "EN confusion"),
    ("let's discuss first",               MetaIntent.STOP_GENERATION, False, "stop + discuss"),
    ("Peux-tu répondre en français ?",    MetaIntent.LANGUAGE_SWITCH, False, "FR->FR switch"),
    ("bonjour",                           MetaIntent.GREETING,        False, "FR greeting"),
    ("merci",                             MetaIntent.THANKS,          False, "FR thanks"),
    ("je ne comprends pas",               MetaIntent.CONFUSION,       False, "FR confusion"),
    ("tu m'as mal compris",               MetaIntent.CORRECTION,      False, "FR correction"),
    ("discutons d'abord",                 MetaIntent.STOP_GENERATION, False, "FR stop"),
]

print(SEP)
print("SECTION 1 — Spec-required cases")
print(SEP)

for msg, expected_intent, expected_gen, note in SPEC_CASES:
    mc = classify_meta_intent(msg)
    intent_ok = mc.intent == expected_intent
    gen_ok = (mc.intent == MetaIntent.NONE) == expected_gen  # NONE -> would generate
    check(
        f"{note} | '{msg}'",
        intent_ok and gen_ok,
        f"expected {expected_intent.value}, got {mc.intent.value} (lang={mc.language}->target={mc.target_language})",
    )
    if intent_ok:
        response = generate_meta_response(mc)
        print(f"         lang={mc.language}->target={mc.target_language} | response: {response}")


# ── Section 2: Language switch details ───────────────────────────────────────

print()
print(SEP)
print("SECTION 2 — Language switch target language")
print(SEP)

lang_cases = [
    ("can you speak French?",                "en", "fr"),
    ("speak French please",                  "en", "fr"),
    ("switch to French",                     "en", "fr"),
    ("respond in French",                    "en", "fr"),
    ("Peux-tu répondre en français ?",       "fr", "fr"),
    ("parle en français",                    "fr", "fr"),
    ("réponds en français s'il te plaît",    "fr", "fr"),
    ("answer in English",                    "en", "en"),
    ("speak English please",                 "en", "en"),
    ("back to English",                      "en", "en"),
    ("réponds en anglais",                   "fr", "en"),
]

for msg, expected_input_lang, expected_target in lang_cases:
    mc = classify_meta_intent(msg)
    intent_ok = mc.intent == MetaIntent.LANGUAGE_SWITCH
    target_ok = mc.target_language == expected_target
    input_ok = mc.language == expected_input_lang
    check(
        f"lang switch | '{msg}'",
        intent_ok and target_ok,
        f"intent={mc.intent.value} target={mc.target_language} (expected {expected_target})",
    )
    if intent_ok:
        response = generate_meta_response(mc)
        print(f"         response [{mc.target_language}]: {response}")


# ── Section 3: False-positive guard (design messages must NOT match meta) ────

print()
print(SEP)
print("SECTION 3 — False-positive guard (design messages must be NONE)")
print(SEP)

DESIGN_MESSAGES = [
    "Add a floor lamp",
    "Make it darker",
    "Change the rug",
    "Can you try a japandi style?",
    "What if we added more wood?",
    "I love the warm tones",
    "Push it further",
    "Remove the painting",
    "Show me the space at night",
    "Make it more hotel-like",
    "Try a darker palette",
    "What do you think about the lighting?",
    "Ajoute un tableau minimaliste",
    "Fais-le plus hôtel de luxe",
    "Montre-moi avec un canapé plus bas",
    "Can you show me with less furniture?",
    "Please add some plants",
]

for msg in DESIGN_MESSAGES:
    mc = classify_meta_intent(msg)
    check(
        f"design -> NONE | '{msg}'",
        mc.intent == MetaIntent.NONE,
        f"got {mc.intent.value}",
    )


# ── Section 4: Additional meta cases ─────────────────────────────────────────

print()
print(SEP)
print("SECTION 4 — Additional meta variants")
print(SEP)

EXTRA_CASES = [
    ("hi",                                   MetaIntent.GREETING,        "EN greeting short"),
    ("hey",                                  MetaIntent.GREETING,        "EN greeting hey"),
    ("salut",                                MetaIntent.GREETING,        "FR greeting"),
    ("bonsoir",                              MetaIntent.GREETING,        "FR evening greeting"),
    ("thank you so much",                    MetaIntent.NONE,            "thanks with extra words -> NONE (not anchored)"),
    ("cheers",                               MetaIntent.THANKS,          "EN cheers"),
    ("merci beaucoup",                       MetaIntent.THANKS,          "FR thanks extended"),
    ("I don't understand",                   MetaIntent.CONFUSION,       "EN confusion alt"),
    ("What does that mean?",                 MetaIntent.CONFUSION,       "EN confusion meaning"),
    ("You misunderstood me",                 MetaIntent.CORRECTION,      "EN correction alt"),
    ("This is not right",                    MetaIntent.FRUSTRATION,     "EN frustration"),
    ("That's wrong",                         MetaIntent.FRUSTRATION,     "EN frustration short"),
    ("no no no",                             MetaIntent.FRUSTRATION,     "EN frustration repeated"),
    ("Don't generate, let's talk first",     MetaIntent.STOP_GENERATION, "stop verbose"),
    ("no image yet",                         MetaIntent.STOP_GENERATION, "stop no image"),
    ("can you explain?",                     MetaIntent.CLARIFICATION,   "EN clarification"),
    ("please elaborate",                     MetaIntent.CLARIFICATION,   "EN clarification elaborate"),
    ("tell me more",                         MetaIntent.CLARIFICATION,   "EN tell me more"),
    ("how are you?",                         MetaIntent.SMALL_TALK,      "EN small talk"),
    ("ça va?",                               MetaIntent.SMALL_TALK,      "FR small talk"),
    ("c'est vraiment pas ça",                MetaIntent.FRUSTRATION,     "FR frustration"),
    ("tu ne comprends rien",                 MetaIntent.FRUSTRATION,     "FR frustration rien"),
    ("ce n'est pas ce que je voulais dire",  MetaIntent.CORRECTION,      "FR correction verbose"),
    ("pas d'image pour l'instant",           MetaIntent.STOP_GENERATION, "FR stop no image"),
    ("peux-tu expliquer?",                   MetaIntent.CLARIFICATION,   "FR clarification"),
    ("réponds en anglais s'il te plaît",     MetaIntent.LANGUAGE_SWITCH, "FR->EN switch polite"),
]

for msg, expected_intent, note in EXTRA_CASES:
    mc = classify_meta_intent(msg)
    check(
        f"{note} | '{msg}'",
        mc.intent == expected_intent,
        f"expected {expected_intent.value}, got {mc.intent.value}",
    )


# ── Section 5: Response quality checks ───────────────────────────────────────

print()
print(SEP)
print("SECTION 5 — Response quality (length + language)")
print(SEP)

RESPONSE_CASES = [
    (MetaIntent.GREETING,        "en", "fr", False,  "EN greeting -> EN response"),
    (MetaIntent.GREETING,        "fr", "fr", False,  "FR greeting -> FR response"),
    (MetaIntent.LANGUAGE_SWITCH, "en", "fr", True,   "EN->FR switch -> FR response"),
    (MetaIntent.LANGUAGE_SWITCH, "fr", "en", False,  "FR->EN switch -> EN response"),
    (MetaIntent.THANKS,          "en", "en", False,  "EN thanks"),
    (MetaIntent.THANKS,          "fr", "fr", False,  "FR thanks"),
    (MetaIntent.CORRECTION,      "en", "en", False,  "EN correction"),
    (MetaIntent.FRUSTRATION,     "fr", "fr", False,  "FR frustration"),
    (MetaIntent.STOP_GENERATION, "en", "en", False,  "EN stop"),
    (MetaIntent.STOP_GENERATION, "fr", "fr", False,  "FR stop"),
    (MetaIntent.CLARIFICATION,   "en", "en", False,  "EN clarify"),
    (MetaIntent.SMALL_TALK,      "en", "en", False,  "EN small talk"),
]

from prompt_engine.meta_intent import MetaClassification

for intent, input_lang, target_lang, check_fr, label in RESPONSE_CASES:
    mc = MetaClassification(
        intent=intent,
        language=input_lang,
        target_language=target_lang,
        confidence=0.9,
    )
    resp = generate_meta_response(mc, seed_extra="test")
    length_ok = 10 < len(resp) < 300
    check(f"length OK | {label}", length_ok, f"len={len(resp)}")
    if check_fr:
        # LANGUAGE_SWITCH to FR: response must be in French
        has_fr = any(c in resp for c in 'àâæçéèêëîïôœùûüÿÀÂÆÇÉÈÊËÎÏÔŒÙÛÜŸ') or \
                 any(w in resp.lower() for w in ['oui', 'bien', 'sûr', 'parfait', 'continuer'])
        check(f"FR response | {label}", has_fr, f"response: {resp}")
    print(f"         [{target_lang}] {resp}")


# ── Section 6: No regressions — import check ─────────────────────────────────

print()
print(SEP)
print("SECTION 6 — No regression (Wave 2.5 imports still clean)")
print(SEP)

try:
    from prompt_engine import (
        classify_intent, generate_architect_response,
        generate_chat_response, generate_mixed_response,
        get_suggestion_chips, classify_meta_intent,
        MetaIntent, generate_meta_response,
    )
    print("  [PASS] All Wave 2.5 + 3.1 exports load cleanly")
except Exception as e:
    print(f"  [FAIL] Import regression: {e}")
    errors.append(f"import regression: {e}")

try:
    from prompt_engine.edit_intent import EditMode
    from prompt_engine.intent_classifier import ConversationIntent, SubIntent
    print("  [PASS] EditMode / ConversationIntent / SubIntent accessible")
except Exception as e:
    print(f"  [FAIL] {e}")
    errors.append(str(e))


# ── Summary ───────────────────────────────────────────────────────────────────

print()
print(SEP)
if not errors:
    print("RESULT: ALL CHECKS PASSED — Wave 3.1 is ready")
else:
    print(f"RESULT: {len(errors)} FAILURE(S)")
    for e in errors:
        print(f"  - {e}")
print(SEP)
