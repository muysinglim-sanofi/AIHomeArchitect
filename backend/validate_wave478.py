"""
Wave 4.7.8 validation suite — Conversational Refinement Accumulation.

Recent unresolved refinement requests + the current one merge into ONE ordered
request fed to AUTHORIZED USER CHANGES (Task 10). Deterministic, bounded,
history-only. APPEND stacks; FULL_REDIRECT/confirmation reset; atmosphere
switches leave modifications intact; latest conflicting instruction wins.

Suites:
  A  accumulate_refinements — APPEND stacking (Task 2/3/4/12 A,B)
  B  REPLACE / full-redirect semantics (Task 4/8/12 D)
  C  atmosphere-switch preserves modifications (Task 5/12 C)
  D  boundaries: confirmation reset, window bound, no cross-gen carry (Task 3/12 E)
  E  prompt integration — accumulated reaches AUTHORIZED USER CHANGES (Task 10)
  F  topology / orchestration / regression preserved (Task 6/7)
  G  main.py wiring + observability (Task 9)
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


from prompt_engine.refinement_authority import (
    accumulate_refinements, build_authorized_changes_clause, _MAX_SECTION,
)
logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS
from prompt_engine.structural_identity import extract_from_description, render_clause, render_negative_anchors
logging.disable(logging.CRITICAL)


def U(c):
    return {"role": "user", "content": c}


def A(c):
    return {"role": "ai", "content": c}


# ── Suite A: APPEND stacking ─────────────────────────────────────────────────
print("\n=== Suite A: APPEND accumulation ===")

# Scenario A: bedroom + roses + warmer, then "go ahead"
histA = [U("turn the rear room into a bedroom"), A("Sounds good — add more texture?"),
         U("also add roses on the coffee table"), A("Lovely. Anything else?"),
         U("make it warmer"), A("Warmer it is. Ready?")]
accA = accumulate_refinements(histA, "go ahead")
check("A1 bedroom retained", any("bedroom" in i for i in accA.items))
check("A2 roses retained", any("roses" in i for i in accA.items))
check("A3 warmer retained", any("warmer" in i for i in accA.items))
check("A4 all three accumulated, ordered", accA.append_count == 3 and accA.items[0].lower().startswith("turn"))
check("A5 confirmation 'go ahead' not added as an item", "go ahead" not in accA.text.lower())

# Scenario B: add window + add plants
histB = [U("add a window in the rear room"), A("Got it.")]
accB = accumulate_refinements(histB, "also add plants")
check("B1 window + plants both present",
      any("window" in i for i in accB.items) and any("plants" in i for i in accB.items))
check("B2 count == 2", accB.append_count == 2)

check("A6 single request unchanged (no history) -> just the prompt",
      accumulate_refinements([], "add a floor lamp").text == "add a floor lamp")
check("A7 empty everything -> empty text (fallback to prompt handled by caller)",
      accumulate_refinements([], "").text == "")


# ── Suite B: REPLACE / full-redirect ─────────────────────────────────────────
print("\n=== Suite B: REPLACE semantics ===")
histR = [U("turn the rear room into a bedroom"), A("Ok."),
         U("also add roses"), A("Sure.")]
accR = accumulate_refinements(histR, "instead remove the bedroom")
check("B3 full-redirect 'instead' resets prior context (replace_detected)",
      accR.replace_detected is True)
check("B4 prior bedroom/roses dropped after 'instead'",
      not any("roses" in i for i in accR.items)
      and accR.items == ("instead remove the bedroom",))
accR2 = accumulate_refinements([U("make it warmer"), A("ok")], "actually start over with a darker palette")
check("B5 'actually/start over' -> replace_detected, only new request",
      accR2.replace_detected is True and "warmer" not in accR2.text.lower())

# Conflict (Task 8): add roses -> remove flowers ; latest wins via ordering
histC = [U("add roses on the coffee table"), A("Done conceptually.")]
accC = accumulate_refinements(histC, "remove the flowers")
check("B6 conflict: both kept, removal LAST (latest-wins by order)",
      accC.items and accC.items[-1].lower().startswith("remove")
      and any("roses" in i for i in accC.items))


# ── Suite C: atmosphere switch preserves modifications (Task 5) ──────────────
print("\n=== Suite C: atmosphere switch ===")
histAt = [U("turn the rear room into a bedroom"), A("Warm Modern bedroom — nice.")]
accAt = accumulate_refinements(histAt, "switch to Japandi")
check("C1 atmosphere switch NOT collected as a modification item",
      "japandi" not in accAt.text.lower())
check("C2 bedroom modification persists across atmosphere switch",
      any("bedroom" in i for i in accAt.items))
check("C3 not flagged as a destructive replace",
      accAt.replace_detected is False)


# ── Suite D: boundaries / no uncontrolled accumulation ──────────────────────
print("\n=== Suite D: boundaries ===")
# Confirmation boundary -> previous batch resolved; new request does not carry it
histE = [U("make it warmer"), A("ok"), U("go ahead"), A("Generated."),
         U("now add a rug")]
accE = accumulate_refinements(histE, "go ahead")
check("D1 prior 'make it warmer' before a 'go ahead' is NOT carried over",
      "warmer" not in accE.text.lower())
check("D2 only post-confirmation request accumulates ('add a rug')",
      accE.items == ("now add a rug",))
# Window bound
many = []
for i in range(12):
    many += [U(f"add item{i}"), A("ok")]
accW = accumulate_refinements(many, "go ahead")
check("D3 accumulation window bounded (<= 6 turns scanned)",
      accW.append_count <= 6, f"count={accW.append_count}")
check("D4 non-actionable chatter not accumulated",
      accumulate_refinements([U("what do you think?"), A("It depends.")],
                             "go ahead").append_count == 0)


# ── Suite E: prompt integration — accumulated reaches AUTHORIZED ─────────────
print("\n=== Suite E: AUTHORIZED USER CHANGES integration ===")
acc_src = accA.text  # bedroom; roses; warmer
clause = build_authorized_changes_clause(acc_src, 3)
check("E1 AUTHORIZED clause built from accumulated text",
      clause.startswith("AUTHORIZED USER CHANGES"))
check("E2 clause carries bedroom + roses (accumulated, not just latest)",
      "bedroom" in clause.lower() and "roses" in clause.lower())
check("E3 clause within section ceiling (Task 8 bounded)",
      len(clause) <= _MAX_SECTION, f"len={len(clause)}")
check("E4 V1 still gets NO AUTHORIZED clause (iteration<=1, Task 7)",
      build_authorized_changes_clause(acc_src, 1) == "")

# End-to-end V3 prompt: accumulated request present, topology intact
ident = extract_from_description(
    "Open-plan living room, wide bay window on the rear wall, black glass "
    "partition on the left, diagonal depth, open kitchen on the right.")
na = render_negative_anchors(ident)
# Route to STRUCTURAL_TRANSFORMATION (Path C) so AUTHORIZED/identity/negatives
# inject. (Per Wave 4.7.5, AUTHORIZED is Path B/C only — LOCAL_EDIT uses
# build_local_edit_prompt. The accumulated `clause` is independent of routing.)
h3 = [U("turn the rear room into a bedroom"), A("ok"), U("also add roses"), A("sure")]
p_v3 = compose_generation_prompt(
    "Soft Luxury · Gold", "living room",
    "Open-plan living room, wide bay window...",
    "remove the wall between the kitchen and the living room", 3, h3,
    structural_identity=render_clause(ident, "V3"),
    structural_negative_anchors=na,
    authorized_user_changes=clause)
check("E5 V3 prompt carries the accumulated AUTHORIZED section",
      "AUTHORIZED USER CHANGES" in p_v3 and "bedroom" in p_v3.lower()
      and "roses" in p_v3.lower())
check("E6 V3 prompt < 4000 hard ceiling (accumulated section bounded)",
      len(p_v3) < 4000, f"len={len(p_v3)}")


# ── Suite F: topology / orchestration regression ────────────────────────────
print("\n=== Suite F: regression ===")
check("F1 STRUCTURAL IDENTITY still present (Task 6)",
      "STRUCTURAL IDENTITY" in p_v3)
check("F2 STRUCTURAL NEGATIVE ANCHORS still present (Task 6)",
      "STRUCTURAL NEGATIVE ANCHORS" in p_v3)
check("F3 no-pending -> falls back to current prompt (zero regression vs 4.7.5)",
      accumulate_refinements([], "add a lamp").text == "add a lamp")
check("F4 V1 path unaffected (iteration 1 clause empty regardless of accumulation)",
      build_authorized_changes_clause(accumulate_refinements(histA, "x").text, 1) == "")
from prompt_engine.intent_classifier import is_confirmation
check("F5 4.7.7 confirmation detection intact (is_confirmation unchanged)",
      is_confirmation("go ahead") and is_confirmation("ok") and not is_confirmation("add a lamp"))
check("F6 refinement_authority provider-agnostic (no model/SDK)",
      all(s not in open("prompt_engine/refinement_authority.py", encoding="utf-8").read()
          for s in ("import openai", "from openai", "anthropic", "httpx", ".create(")))


# ── Suite G: main.py wiring + observability ─────────────────────────────────
print("\n=== Suite G: wiring + observability ===")
with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
check("G1 accumulate_refinements imported + called",
      "accumulate_refinements" in main_src
      and "accumulate_refinements(history_messages, prompt)" in main_src)
check("G2 accumulated text feeds AUTHORIZED (not raw prompt)",
      "build_authorized_changes_clause(_acc_src, iteration)" in main_src)
check("G3 [RefinementAccumulation] log with required fields (Task 9)",
      "[RefinementAccumulation]" in main_src
      and "append_detected=" in main_src
      and "replace_detected=" in main_src
      and "accumulated_refinement_count=" in main_src
      and "final_accumulated_request=" in main_src)
check("G4 fallback to current prompt preserved (_acc.text or prompt)",
      "_acc.text or prompt" in main_src)

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
  WAVE 4.7.8 - CONVERSATIONAL REFINEMENT ACCUMULATION:
  Recent unresolved refinements stack into ONE ordered request reaching
  AUTHORIZED USER CHANGES. Confirmation/full-redirect reset; atmosphere
  switches keep modifications; latest conflicting instruction wins.
""")
