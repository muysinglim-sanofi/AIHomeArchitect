"""
PR-A routing validation — polite edit commands route to GENERATE, genuine
opinion questions stay DESIGN_ADVICE.

Run:  PYTHONPATH=. python _pr_a_routing_validation.py

Deterministic, offline (no OpenAI/DB). Mirrors main.py's resolution:
classify_intent → PR3-router downgrade (GENERATE + opinion → advice) →
should_generate = (intent == GENERATE). See docs / the PR-A discussion.

Bug fixed: "Can you rotate the sofa?" used to route to DESIGN_ADVICE because
`has_question` (the "can you" frame) dominated the edit intent, and because
"rotate/reverse/flip/face" were absent from the edit lexicon.
"""
import re
import sys

from prompt_engine.intent_classifier import (
    classify_intent,
    ConversationIntent,
    detect_design_opinion_question,
    _LOCAL_EDIT,
)

GEN = ConversationIntent.GENERATE


def resolved(msg: str, iteration: int = 2) -> str:
    """Final routing outcome as main.py resolves it (deterministic part)."""
    ic = classify_intent(msg, iteration)
    intent = ic.intent
    # main.py PR3-router: GENERATE + opinion question (and no product topic) → advice.
    if intent == GEN and detect_design_opinion_question(msg):
        intent = ConversationIntent.DESIGN_DISCUSSION
    return "GEN" if intent == GEN else "ADVICE"


# (message, expected) — "GEN" ⇒ should_generate=True.
CASES = [
    # polite "Can you …" commands — the reported bug → GENERATE
    ("Can you reverse the sofa so it can face the TV?", "GEN"),
    ("Can you rotate the sofa?", "GEN"),
    ("Can you flip the sofa?", "GEN"),
    ("Can you put the TV in front of the sofa?", "GEN"),
    ("Can you make it brighter?", "GEN"),
    ("Can you move the TV?", "GEN"),
    ("Can you add curtains?", "GEN"),
    ("Can you remove the dining table?", "GEN"),
    ("Can you make the sofa face the TV while keeping the window view?", "GEN"),
    # imperatives (already worked) → GENERATE
    ("Put the TV there.", "GEN"),
    ("Reverse the sofa.", "GEN"),
    ("Make the room brighter.", "GEN"),
    ("Move the dining table outside.", "GEN"),
    # could/would you (already worked) → GENERATE
    ("Could you move the TV?", "GEN"),
    ("Would you remove the table?", "GEN"),
    # genuine opinion / advice requests → ADVICE
    ("Where should I put the TV?", "ADVICE"),
    ("Should I move the TV?", "ADVICE"),
    ("Do you think the TV fits here?", "ADVICE"),
    ("What would you recommend?", "ADVICE"),
    ("Round or rectangular?", "ADVICE"),
    ("Should the sofa face the window or the TV?", "ADVICE"),  # choice-Q w/ "face" + "or the X?"
    ("Could the TV go there?", "ADVICE"),
    ("Can you tell me where I should put the TV?", "ADVICE"),
    # polite frame but NOT a modification → ADVICE
    ("Can you explain why wood works?", "ADVICE"),
    ("Can you suggest a color?", "ADVICE"),
    # commands that MENTION "where" but are not advice → GENERATE (over-catch guard)
    ("Move the sofa where the light is.", "GEN"),
    ("Put it where I want.", "GEN"),
]

# The manipulation verbs added in PR-A must NOT be matchable by the pre-PR-A
# lexicon — proving they were genuinely missing (not decorative).
_OLD_LOCAL_EDIT = re.compile(
    r"\b(add\s+(a|an|the|some)?|remove\s+(the|a)?|change\s+(the|a)?|replace\s+(the|a)?|"
    r"swap\s+(the|a)?|move\s+(the|a)?|put\s+(a|an|the)?|take\s+(out|away)|"
    r"get\s+rid\s+of|use\s+(a|an|different)|try\s+(a|an|the))\b",
    re.IGNORECASE,
)
NEW_VERBS = ["rotate the sofa", "reverse the sofa", "flip the sofa", "face the TV"]


def main() -> int:
    fails = 0
    print("── routing matrix ──")
    for msg, exp in CASES:
        got = resolved(msg)
        ok = got == exp
        fails += (not ok)
        print(f"  [{'OK ' if ok else 'FAIL'}] {exp:6}->{got:6}  {msg!r}")

    print("\n── verb necessity (old lexicon must NOT match the new verbs) ──")
    for phrase in NEW_VERBS:
        old = bool(_OLD_LOCAL_EDIT.search(phrase))
        new = bool(_LOCAL_EDIT.search(phrase))
        ok = (not old) and new
        fails += (not ok)
        print(f"  [{'OK ' if ok else 'FAIL'}] old={old} new={new}  {phrase!r}")

    total = len(CASES) + len(NEW_VERBS)
    print(f"\n{'ALL GREEN' if fails == 0 else str(fails) + ' FAILURE(S)'}  ({total - fails}/{total})")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
