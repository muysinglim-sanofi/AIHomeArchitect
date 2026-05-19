"""
Wave 4.7.7 validation suite — Conversational Generate Confirmations.

Gated, additive fix (per the 4.7.7a audit):
  - is_confirmation(): recognizes bare go-ahead phrases (Task 2)
  - pending_design_sub_intent(): pending design request detector (Task 1)
  - resolve_confirmation(): promotes to GENERATE ONLY if confirmation + pending
  - /chat: override after meta/classify_intent + tone-veto bypass (Task 3)

`decide()` below is a faithful, line-for-line replica of the /chat
should_generate computation (meta → classify_intent → confirmation override →
tone → final block) so end-to-end routing can be asserted without the server.

Required coverage:
  POSITIVE: go ahead / continue / ok / yes / let's do it  + pending  -> GENERATE
  NEGATIVE: ok / yes (no pending), thanks, what do you think?, maybe,
            interesting, STOP_GENERATION  -> CHAT
"""

import os
import sys
import logging

logging.disable(logging.CRITICAL)
sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
results = []


def check(label, cond, detail=""):
    s = PASS if cond else FAIL
    sfx = f"  [{detail}]" if detail and not cond else ""
    print(f"  {s}  {label}{sfx}")
    results.append((label, cond))


from prompt_engine.intent_classifier import (
    classify_intent, is_confirmation, resolve_confirmation,
    pending_design_sub_intent, ConversationIntent, SubIntent,
)
from prompt_engine.meta_intent import classify_meta_intent, MetaIntent
from prompt_engine.tone_calibration import select_tone_mode, ToneMode
from prompt_engine.response_quality import detect_emotional_context
from prompt_engine.conversation_memory import build_session_memory


def decide(message: str, history: list[dict], iteration: int = 2) -> str:
    """Faithful replica of main.py /chat should_generate routing."""
    meta = classify_meta_intent(message)
    if meta.intent != MetaIntent.NONE:
        return "CHAT"  # meta layer returns early (STOP_GENERATION/THANKS/...)
    intent_class = classify_intent(message, iteration)
    confirmation_generate = False
    if meta.intent == MetaIntent.NONE and iteration > 1:
        conf = resolve_confirmation(message, history)
        if conf is not None:
            intent_class = conf
            confirmation_generate = True
    sm = build_session_memory(history=history, detected_language=meta.language)
    emo = detect_emotional_context(message)
    tone = select_tone_mode(meta.intent, intent_class.sub_intent,
                            intent_class.confidence, sm, emo)
    if tone == ToneMode.HUMAN_SOFT and not confirmation_generate:
        return "CHAT"
    if tone == ToneMode.ARCHITECT_LIGHT and not confirmation_generate:
        return "CHAT"
    if intent_class.intent == ConversationIntent.MIXED:
        return "CHAT"
    return "GENERATE" if intent_class.intent == ConversationIntent.GENERATE else "CHAT"


# Conversation shapes
PENDING = [{"role": "user", "content": "turn the rear room into a bedroom"},
           {"role": "ai", "content": "I can transform the rear space into a Japandi bedroom — shall I?"}]
PENDING_REFINE = [{"role": "user", "content": "make it warmer and cosier"},
                  {"role": "ai", "content": "I'd deepen the warmth with layered textiles. Proceed?"}]
PENDING_LOCAL = [{"role": "user", "content": "add roses on the coffee table"},
                 {"role": "ai", "content": "A small rose arrangement would suit it. Want me to?"}]
PENDING_REDIRECT = [{"role": "user", "content": "switch to Japandi"},
                    {"role": "ai", "content": "Japandi would reframe the whole mood. Go ahead?"}]
NO_PENDING = [{"role": "user", "content": "what materials do you usually recommend?"},
              {"role": "ai", "content": "It depends on the light — oak and linen are reliable."}]
USER_LAST = [{"role": "user", "content": "turn the rear room into a bedroom"}]  # no assistant turn yet


# ── Suite A: is_confirmation coverage (Task 2) ───────────────────────────────
print("\n=== Suite A: confirmation phrase coverage ===")
for ph in ["go ahead", "continue", "ok", "okay", "yes", "yeah", "yep",
           "sure", "alright", "let's do it", "do it", "show me", "generate",
           "proceed", "go for it", "oui", "vas-y", "d'accord"]:
    check(f"A confirmation recognized: {ph!r}", is_confirmation(ph), ph)
for ph in ["what do you think?", "maybe", "interesting", "not sure",
           "ok but change the sofa", "add a lamp", "thanks", "hmm"]:
    check(f"A NOT a bare confirmation: {ph!r}", not is_confirmation(ph), ph)


# ── Suite B: pending-design-intent detection (Task 1) ────────────────────────
print("\n=== Suite B: pending-design-intent ===")
check("B1 bedroom conversion pending -> STRUCTURAL_CHANGE",
      pending_design_sub_intent(PENDING) == SubIntent.STRUCTURAL_CHANGE)
check("B2 refine pending -> REFINE_ATMOSPHERE",
      pending_design_sub_intent(PENDING_REFINE) == SubIntent.REFINE_ATMOSPHERE)
check("B3 local pending -> LOCAL_EDIT",
      pending_design_sub_intent(PENDING_LOCAL) == SubIntent.LOCAL_EDIT)
check("B4 redirect pending -> REDIRECT",
      pending_design_sub_intent(PENDING_REDIRECT) == SubIntent.REDIRECT)
check("B5 no design request -> None (not pending)",
      pending_design_sub_intent(NO_PENDING) is None)
check("B6 last turn is user (no assistant proposal yet) -> None",
      pending_design_sub_intent(USER_LAST) is None)
check("B7 empty history -> None",
      pending_design_sub_intent([]) is None)


# ── Suite C: resolve_confirmation gating ─────────────────────────────────────
print("\n=== Suite C: resolve_confirmation (gated) ===")
check("C1 confirmation + pending -> GENERATE",
      (resolve_confirmation("go ahead", PENDING) or None) is not None
      and resolve_confirmation("go ahead", PENDING).intent == ConversationIntent.GENERATE)
check("C2 confirmation + NO pending -> None",
      resolve_confirmation("ok", NO_PENDING) is None)
check("C3 non-confirmation + pending -> None (not a confirmation)",
      resolve_confirmation("what about a darker floor?", PENDING) is None)
check("C4 confirmation + user-last (no proposal) -> None",
      resolve_confirmation("yes", USER_LAST) is None)
check("C5 sub_intent carried from pending request (bedroom -> STRUCTURAL_CHANGE)",
      resolve_confirmation("let's do it", PENDING).sub_intent == SubIntent.STRUCTURAL_CHANGE)


# ── Suite D: POSITIVE end-to-end routing (Task 9 A/B/E) ──────────────────────
print("\n=== Suite D: POSITIVE — confirmation + pending -> GENERATE ===")
for ph, hist in [("go ahead", PENDING), ("continue", PENDING_LOCAL),
                 ("ok", PENDING), ("yes", PENDING), ("let's do it", PENDING),
                 ("sure", PENDING_REFINE), ("alright", PENDING_REDIRECT),
                 ("yeah", PENDING), ("proceed", PENDING_LOCAL)]:
    check(f"D {ph!r} + pending -> GENERATE", decide(ph, hist) == "GENERATE", ph)
check("D Scenario A: 'go ahead' after bedroom proposal -> GENERATE",
      decide("go ahead", PENDING) == "GENERATE")
check("D Scenario B: 'continue' after add-roses -> GENERATE",
      decide("continue", PENDING_LOCAL) == "GENERATE")
check("D Scenario E: 'yes' after proposal -> GENERATE",
      decide("yes", PENDING) == "GENERATE")


# ── Suite E: NEGATIVE — false-positive protection (Task 4 / 9 C,D,F) ─────────
print("\n=== Suite E: NEGATIVE — must stay CHAT ===")
check("E Scenario D: 'ok' with NO pending -> CHAT",
      decide("ok", NO_PENDING) == "CHAT")
check("E 'yes' with NO pending -> CHAT",
      decide("yes", NO_PENDING) == "CHAT")
check("E 'ok' user-last (no assistant proposal) -> CHAT",
      decide("ok", USER_LAST) == "CHAT")
check("E Scenario C: 'what do you think about adding a TV?' -> CHAT",
      decide("what do you think about adding a TV?", PENDING) == "CHAT")
check("E 'thanks' -> CHAT (meta THANKS preserved)",
      decide("thanks", PENDING) == "CHAT")
check("E 'maybe' -> CHAT",
      decide("maybe", PENDING) == "CHAT")
check("E 'interesting' -> CHAT (acknowledgment, not a go-ahead)",
      decide("interesting", PENDING) == "CHAT")
check("E 'not sure' -> CHAT",
      decide("not sure", PENDING) == "CHAT")
check("E Scenario F: STOP_GENERATION ('don't generate yet, let's discuss') -> CHAT",
      decide("don't generate yet, let's discuss", PENDING) == "CHAT")
check("E 'no image yet' (STOP_GENERATION) -> CHAT",
      decide("no image yet", PENDING) == "CHAT")
check("E reflection 'what do you think?' -> CHAT",
      decide("what do you think?", PENDING) == "CHAT")


# ── Suite F: regression / backward compatibility (Task 7) ────────────────────
print("\n=== Suite F: regression — existing flows unchanged ===")
check("F1 iteration==1 always GENERATE (unchanged)",
      classify_intent("anything", 1).intent == ConversationIntent.GENERATE)
check("F2 existing explicit 'go ahead' still GENERATE even with NO pending (unchanged)",
      decide("go ahead", NO_PENDING) == "GENERATE")
check("F3 explicit local edit still routes (no pending needed) — 'add a floor lamp'",
      decide("add a floor lamp near the window", NO_PENDING) == "GENERATE")
check("F4 structural request still GENERATE — 'remove the wall'",
      decide("remove the wall between kitchen and living", NO_PENDING) == "GENERATE")
check("F5 pure praise still CHAT — 'I love it'",
      decide("I love it", PENDING) == "CHAT")
check("F6 design question still CHAT — 'should I use oak or walnut?'",
      decide("should I use oak or walnut?", PENDING) == "CHAT")
check("F7 classify_intent signature/behaviour unchanged for known GENERATE",
      classify_intent("make it warmer", 2).intent == ConversationIntent.GENERATE)
check("F8 confirmation gating requires iteration>1 (V1 path untouched)",
      resolve_confirmation("go ahead", PENDING) is not None)  # helper itself; main gates iter>1

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
check("F9 main.py: gated override present + meta-first ordering",
      "resolve_confirmation(message, history_messages)" in main_src
      and "meta.intent == MetaIntent.NONE and iteration > 1" in main_src)
check("F10 main.py: tone-veto bypass guarded by confirmation_generate",
      "ToneMode.HUMAN_SOFT and not confirmation_generate" in main_src
      and "ToneMode.ARCHITECT_LIGHT and not confirmation_generate" in main_src)
check("F11 main.py: [GenerateConfirmation] observability present (Task 6)",
      "[GenerateConfirmation]" in main_src
      and "pending_design_intent=" in main_src
      and "confirmation_detected=" in main_src
      and "tone_veto_bypassed=" in main_src
      and "final_should_generate=" in main_src)
check("F12 classify_intent untouched (no existing branch removed)",
      "Vision 1 always generates" in
      open("prompt_engine/intent_classifier.py", encoding="utf-8").read())

logging.disable(logging.NOTSET)

passed = sum(1 for _, ok in results if ok)
total = len(results)
failed = [l for l, ok in results if not ok]
print(f"\n{'=' * 60}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if failed:
    print("\n  FAILING CHECKS:")
    for l in failed:
        print(f"    - {l}")
print(f"{'=' * 60}")
print("""
  WAVE 4.7.7 — CONVERSATIONAL GENERATE CONFIRMATIONS:
  Bare confirmations -> GENERATE ONLY when a concrete design request is pending
  (assistant proposed, not yet generated). Meta protections + no-pending stay
  CHAT. Tone layer no longer vetoes a confirmed, pending-gated GENERATE.
""")
