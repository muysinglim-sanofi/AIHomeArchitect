"""
Wave 4.7.9 validation suite - Functional Layout Intelligence (Lightweight).

Tiny, NEGATIVE-framed functional realism folded into _COMPACT_REALISM only.
Length-neutral (132 vs 133 chars) -> zero V1 budget impact. No new section,
no room_intelligence activation, no composition authority.

Covers Task 9 areas 1-11 + budget hard requirement (Soft Luxury V1 <= 3550).
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


from prompt_engine.realism_layer import (
    build_compact_realism_block, build_medium_realism_block,
    build_realism_block, build_interior_completeness_rule,
)
logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS, _SECTION_PRIORITY
from prompt_engine.structural_identity import extract_from_description, render_clause, render_negative_anchors
logging.disable(logging.CRITICAL)

CR = build_compact_realism_block()
MID = chr(0xB7)
DESC = ("Open-plan living room, dominant bay window on the rear wall, a "
        "secondary rear window beside it, two windows on the left, deep "
        "diagonal depth, open kitchen on the right.")
ident = extract_from_description(DESC)
SI = render_clause(ident, "V1")
NA = render_negative_anchors(ident)


def fv(label):
    return compose_generation_prompt(label, "living room", "", "", 1, [],
                                     structural_identity=SI,
                                     structural_negative_anchors=NA)


# ── 10. Functional realism wording correctly injected ────────────────────────
print("\n=== 10. functional realism injected ===")
check("10a compact realism has functional usability clause",
      "Furniture stays usable" in CR and "openings and circulation clear" in CR
      and "not camera-staged" in CR)
check("10b mandatory anti-CGI tokens preserved",
      "NOT a CGI render" in CR and "DSLR" in CR)
check("10c mandatory tokens within first 130 chars (wave421 B / wave42 H6/H7)",
      "NOT a CGI render" in CR[:130] and "DSLR" in CR[:130])
check("10d compact realism < 200 chars (wave424 A14)",
      len(CR) < 200, f"len={len(CR)}")
p_sl = fv(f"Soft Luxury {MID} Gold")
check("10e functional clause reaches rendered V1 prompt",
      "Furniture stays usable" in p_sl and "not camera-staged" in p_sl)


# ── 2 / 4-budget. Soft Luxury V1 remains <= 3550 (HARD requirement) ──────────
print("\n=== 2. budget: Soft Luxury V1 <= 3550 ===")
check("2a length-neutral: compact realism <= pre-4.7.9 (133)",
      len(CR) <= 133, f"len={len(CR)}")
check("2b Soft Luxury V1 <= 3550 (hard requirement, Task 4)",
      len(p_sl) <= _MODE_BUDGETS["FIRST_VISION"], f"len={len(p_sl)}")
for L in [f"Japandi {MID} Calm", f"Warm Modern {MID} Oat", f"Zen Retreat {MID} Serenity"]:
    p = fv(L)
    check(f"2-{L[:11]} V1 <= 3550, all critical sections present",
          len(p) <= 3550
          and "TRANSFORMATION AMBITION" in p
          and ("ATMOSPHERE (" in p or "STYLE (" in p)
          and "STRUCTURAL IDENTITY" in p and "STRUCTURAL NEGATIVE ANCHORS" in p
          and "NOT a CGI render" in p,
          f"len={len(p)}")
check("2c no P4 eviction on Soft Luxury (wow + DNA + identity all retained)",
      "TRANSFORMATION AMBITION" in p_sl and ("ATMOSPHERE (" in p_sl or "STYLE (" in p_sl)
      and "STRUCTURAL IDENTITY" in p_sl)


# ── 1. No new prompt section added ───────────────────────────────────────────
print("\n=== 1. no new section ===")
with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()
check("1a no functional-layout section key in _SECTION_PRIORITY",
      not any(k in comp_src for k in
              ('"functional_layout"', '"usability"', '"layout_intelligence"',
               '"functional_realism"', '"room_intelligence"')))
check("1b composer.py NOT modified by 4.7.9 (no Wave 4.7.9 marker there)",
      "Wave 4.7.9" not in comp_src)
check("1c only realism_layer.py carries the change",
      "Wave 4.7.9" in open("prompt_engine/realism_layer.py", encoding="utf-8").read())


# ── 3 / 7. Dormant modules stay dormant ──────────────────────────────────────
print("\n=== 3/7. dormant modules untouched ===")
import subprocess  # noqa: F401  (only used for grep-free static checks below)
check("3a room_intelligence NOT imported/called by composer or main",
      "build_room_context" not in comp_src
      and "build_room_context" not in open("main.py", encoding="utf-8").read()
      and "room_intelligence" not in comp_src)
with open("prompt_engine/atmosphere_dna/_base.py", encoding="utf-8") as f:
    base_src = f.read()
check("4a room_specific_constraints still NOT rendered by build_dna_block",
      "room_specific_constraints" in base_src  # defined
      and base_src.count("room_specific_constraints") == 1)  # only the dataclass field, not rendered
check("7a room_intelligence.py file unchanged in wiring (still standalone)",
      "build_room_context" in open("prompt_engine/room_intelligence.py", encoding="utf-8").read())


# ── 5 / 11. No composition authority / no recomposition increase ────────────
print("\n=== 5/11. no composition authority ===")
_COMP_AUTH = ("conversation grouping", "sofa grouping", "arrange the furniture",
              "symmetrical furniture", "centred on focal", "centered on focal",
              "face the sofa", "position the tv", "seating around",
              "create a conversation", "statement sofa arrangement")
check("5a compact realism contains NO composition-authority phrase",
      not any(x in CR.lower() for x in _COMP_AUTH))
check("5b rendered V1 contains NO composition-authority phrase",
      not any(x in p_sl.lower() for x in _COMP_AUTH))
check("11a functional clause is negative-framed (constraint verbs only)",
      "usable" in CR and "clear" in CR and "not camera-staged" in CR
      and "arrange" not in CR.lower() and "grouping" not in CR.lower())
check("11b recomposition guards intact in rendered V1",
      "do not recompose" in p_sl.lower() or "Restyle only" in p_sl
      or "RESTYLE ONLY" in p_sl.upper())


# ── 6. No topology regression ────────────────────────────────────────────────
print("\n=== 6. topology preserved ===")
check("6a V1 still SAME APARTMENT PHOTO-EDIT + OPENINGS ANCHOR",
      "SAME APARTMENT PHOTO-EDIT" in p_sl and "OPENINGS ANCHOR" in p_sl)
check("6b V1 still CAMERA LOCK + STRUCTURAL IDENTITY + NEGATIVE ANCHORS",
      "CAMERA LOCK" in p_sl and "STRUCTURAL IDENTITY" in p_sl
      and "STRUCTURAL NEGATIVE ANCHORS" in p_sl)
check("6c functional 'openings ... clear' reinforces (not contradicts) openings",
      "openings and circulation clear" in p_sl and "OPENINGS ANCHOR" in p_sl)


# ── 7b / 8. Continuity + orchestration regression ────────────────────────────
print("\n=== 7b/8. continuity + orchestration ===")
h2 = [{"role": "user", "content": "x"}, {"role": "ai", "content": "y"},
      {"role": "user", "content": "warmer"}]
p_v2 = compose_generation_prompt(
    f"Soft Luxury {MID} Gold", "living room", DESC, "warmer", 2, h2,
    structural_identity=render_clause(ident, "V2"),
    source_continuity="CONTINUE FROM CURRENT DESIGN — continue from the provided current design image.",
    structural_negative_anchors=NA)
# NOTE: compact_realism is P3 and (since Wave 4.7.5b) is budget-dropped in the
# tight STYLE_REFINEMENT(2400) budget — pre-4.7.9 behaviour. Functional realism
# rides in compact_realism, so it follows that same P3 budget behaviour (present
# in FIRST_VISION; budget-managed in tight V2/V3). The length-neutral 4.7.9
# change cannot worsen it. V2 must keep P1 continuity + identity (unchanged).
check("7b V2 keeps continuity + identity (P1, unaffected by 4.7.9)",
      "CONTINUE FROM CURRENT DESIGN" in p_v2 and "STRUCTURAL IDENTITY" in p_v2)
from prompt_engine.intent_classifier import is_confirmation, resolve_confirmation
from prompt_engine.refinement_authority import accumulate_refinements, build_authorized_changes_clause
check("8a 4.7.7 confirmation orchestration intact",
      is_confirmation("go ahead") and not is_confirmation("add a lamp"))
check("8b 4.7.8 accumulation intact",
      accumulate_refinements([{"role": "user", "content": "turn rear into a bedroom"},
                              {"role": "ai", "content": "ok"}],
                             "also add roses").append_count == 2)
check("8c AUTHORIZED clause still builds (4.7.5/4.7.8 intact)",
      build_authorized_changes_clause("turn the rear into a bedroom; also add roses", 3)
      .startswith("AUTHORIZED USER CHANGES"))


# ── 9. No prompt-budget overflow (all modes) ─────────────────────────────────
print("\n=== 9. budget across modes ===")
p_v3 = compose_generation_prompt(
    f"Soft Luxury {MID} Gold", "living room", DESC,
    "remove the wall between the kitchen and the living room", 3,
    [{"role": "user", "content": "x"}, {"role": "ai", "content": "y"},
     {"role": "user", "content": "remove the wall"}],
    structural_identity=render_clause(ident, "V3"),
    structural_negative_anchors=NA)
check("9a V2 within STYLE_REFINEMENT hard ceiling (<4000)",
      len(p_v2) < 4000, f"len={len(p_v2)}")
check("9b V3 within STRUCTURAL hard ceiling (<4000); compact_realism is P3/budget-managed (pre-4.7.9)",
      len(p_v3) < 4000, f"len={len(p_v3)}")
check("9c medium / full realism blocks UNCHANGED (only compact touched)",
      "natural light physics" in build_medium_realism_block().lower()
      and "natural light physics" in build_realism_block().lower()
      and "INTERIOR COMPLETENESS" in build_interior_completeness_rule())


# ── Observability (Task 8) ───────────────────────────────────────────────────
print("\n=== Task 8: observability ===")
with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
check("OBS [FunctionalLayout] log present with required fields",
      "[FunctionalLayout]" in main_src
      and "functional_realism_enabled=" in main_src
      and "realism_chars_before=" in main_src
      and "realism_chars_after=" in main_src
      and "budget_safe=" in main_src)

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
  WAVE 4.7.9 - FUNCTIONAL LAYOUT INTELLIGENCE:
  Negative-framed functional realism folded into _COMPACT_REALISM,
  length-neutral (132 vs 133). No new section, no room_intelligence,
  no composition authority. Soft Luxury V1 stays <= 3550.
""")
