"""
Mini Wave — Conversation Orchestration Fix validation suite.

Tests that explicit generation commands and short approval phrases
reliably trigger GENERATE intent instead of defaulting to CONVERSATION.

Scenarios:
  A — Direct generate commands ("generate", "render", "show me")
  B — Short approval phrases ("ok try", "go ahead", "let's see", "do it")
  C — Prefixed approvals ("yes generate", "ok please go ahead")
  D — French equivalents ("vas-y", "génère", "allons-y")
  E — Non-generation cases must NOT be reclassified (guard tests)
  F — Regression: existing signals still route correctly
"""

import sys
import os
import logging

logging.disable(logging.CRITICAL)
sys.path.insert(0, os.path.dirname(__file__))

from prompt_engine.intent_classifier import classify_intent, ConversationIntent, SubIntent

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

results = []


def check(label: str, condition: bool, detail: str = "") -> None:
    status = PASS if condition else FAIL
    suffix = f"  [{detail}]" if detail and not condition else ""
    print(f"  {status}  {label}{suffix}")
    results.append((label, condition))


def is_generate(msg: str, iteration: int = 2) -> bool:
    return classify_intent(msg, iteration).intent == ConversationIntent.GENERATE


def is_conversation(msg: str, iteration: int = 2) -> bool:
    return classify_intent(msg, iteration).intent == ConversationIntent.CONVERSATION


# ── Suite A: Direct generate commands ────────────────────────────────────────
print("\n=== Suite A: Direct generate commands ===")

check("A1  'generate' -> GENERATE", is_generate("generate"))
check("A2  'Generate' -> GENERATE", is_generate("Generate"))
check("A3  'render' -> GENERATE", is_generate("render"))
check("A4  'show me' -> GENERATE", is_generate("show me"))
check("A5  'show me it' -> GENERATE", is_generate("show me it"))
check("A6  'show me the result' -> GENERATE", is_generate("show me the result"))
check("A7  'show me that' -> GENERATE", is_generate("show me that"))


# ── Suite B: Short approval phrases ──────────────────────────────────────────
print("\n=== Suite B: Short approval phrases ===")

check("B1  'go ahead' -> GENERATE", is_generate("go ahead"))
check("B2  'do it' -> GENERATE", is_generate("do it"))
check("B3  'try it' -> GENERATE", is_generate("try it"))
check("B4  'let's see' -> GENERATE", is_generate("let's see"))
check("B5  'lets see' -> GENERATE", is_generate("lets see"))
check("B6  'let's go' -> GENERATE", is_generate("let's go"))
check("B7  'ok try' -> GENERATE", is_generate("ok try"))
check("B8  'ok go' -> GENERATE", is_generate("ok go"))
check("B9  'proceed' -> GENERATE", is_generate("proceed"))
check("B10 'go for it' -> GENERATE", is_generate("go for it"))
check("B11 'make it' -> GENERATE", is_generate("make it"))
check("B12 'just do it' -> GENERATE", is_generate("just do it"))


# ── Suite C: Prefixed approval phrases ───────────────────────────────────────
print("\n=== Suite C: Prefixed approval phrases ===")

check("C1  'yes generate' -> GENERATE", is_generate("yes generate"))
check("C2  'ok generate' -> GENERATE", is_generate("ok generate"))
check("C3  'please generate' -> GENERATE", is_generate("please generate"))
check("C4  'yes ok generate' -> GENERATE", is_generate("yes ok generate"))
check("C5  'yes let's see' -> GENERATE", is_generate("yes let's see"))
check("C6  'yes please' (praise overlap — should remain GENERATE or CONVERSATION)",
      classify_intent("yes please", 2).intent in (ConversationIntent.GENERATE, ConversationIntent.CONVERSATION))
check("C7  'sure, go ahead' -> GENERATE", is_generate("sure, go ahead"))
check("C8  'alright let's go' -> GENERATE", is_generate("alright let's go"))
check("C9  'sounds good let's see' -> GENERATE", is_generate("sounds good let's see"))
check("C10 'ok can try' -> GENERATE", is_generate("ok can try"),
      detail=classify_intent("ok can try", 2).reasoning)


# ── Suite D: French approval phrases ─────────────────────────────────────────
print("\n=== Suite D: French approval phrases ===")

check("D1  'vas-y' -> GENERATE", is_generate("vas-y"))
check("D2  'allez' -> GENERATE", is_generate("allez"))
check("D3  'génère' -> GENERATE", is_generate("génère"))
check("D4  'affiche-le' -> GENERATE", is_generate("affiche-le"))
check("D5  'montre-moi' -> GENERATE", is_generate("montre-moi"))
check("D6  'allons-y' -> GENERATE", is_generate("allons-y"))
check("D7  'oui vas-y' -> GENERATE", is_generate("oui vas-y"))
check("D8  'ok vas-y' -> GENERATE", is_generate("ok vas-y"))
check("D9  'ça marche' -> GENERATE", is_generate("ça marche"))
check("D10 'd'accord vas-y' -> GENERATE", is_generate("d'accord vas-y"))


# ── Suite E: Guard tests — must NOT trigger GENERATE ─────────────────────────
print("\n=== Suite E: Guard tests (must stay CONVERSATION) ===")

check("E1  'what do you think?' -> CONVERSATION",
      is_conversation("what do you think?"))
check("E2  'give me options' -> CONVERSATION",
      is_conversation("give me options"))
check("E3  'what would look good here?' -> CONVERSATION",
      is_conversation("what would look good here?"))
check("E4  'I love it' -> CONVERSATION",
      is_conversation("I love it"))
check("E5  'that looks perfect' -> CONVERSATION",
      is_conversation("that looks perfect"))
check("E6  'any suggestions?' -> CONVERSATION",
      is_conversation("any suggestions?"))
check("E7  'do you think this works?' -> CONVERSATION",
      is_conversation("do you think this works?"))


# ── Suite F: Regression — existing signals still route correctly ──────────────
print("\n=== Suite F: Regression (existing signals) ===")

check("F1  Structural still GENERATE", is_generate("open up the wall between rooms"))
check("F2  Redirect still GENERATE", is_generate("switch to Zen Retreat"))
check("F3  Refine still GENERATE", is_generate("make it warmer and more minimal"))
check("F4  Local edit still GENERATE", is_generate("add a floor lamp near the sofa"))
check("F5  Iteration 1 always GENERATE",
      classify_intent("what do you think?", 1).intent == ConversationIntent.GENERATE)
check("F6  Empty message on iteration 2 -> GENERATE",
      classify_intent("", 2).intent == ConversationIntent.GENERATE)
check("F7  Confidence for explicit generate >= 0.85",
      classify_intent("go ahead", 2).confidence >= 0.85)


# ── Results ───────────────────────────────────────────────────────────────────

passed = sum(1 for _, ok in results if ok)
total = len(results)
failed = [(label, ok) for label, ok in results if not ok]

print(f"\n{'=' * 60}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if failed:
    print(f"\n  FAILING CHECKS:")
    for label, _ in failed:
        print(f"    - {label}")
print(f"{'=' * 60}")

print("""
  INTENT ROUTING MATRIX (Mini Wave — Conversation Orchestration Fix):

  Message                     | Before fix    | After fix
  ----------------------------|---------------|----------
  "generate"                  | CONVERSATION  | GENERATE
  "go ahead"                  | CONVERSATION  | GENERATE
  "ok try"                    | CONVERSATION  | GENERATE
  "let's see"                 | CONVERSATION  | GENERATE
  "do it"                     | CONVERSATION  | GENERATE
  "show me"                   | CONVERSATION  | GENERATE
  "yes generate"              | CONVERSATION  | GENERATE
  "vas-y"                     | CONVERSATION  | GENERATE
  "what do you think?"        | CONVERSATION  | CONVERSATION (unchanged)
  "I love it"                 | CONVERSATION  | CONVERSATION (unchanged)
  "make it warmer"            | GENERATE      | GENERATE (unchanged)

  MANUAL VALIDATION REQUIRED:
  [MANUAL] Open app, iterate to Vision 2, type "go ahead" — confirm image generates
  [MANUAL] Type "let's see" after architect proposal — confirm generation starts
  [MANUAL] Type "what do you think?" — confirm text reply only (no image)
""")
