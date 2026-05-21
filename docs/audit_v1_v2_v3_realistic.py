"""V1 vs V2 vs V3 realistic byte-identity audit.

Simulates the EXACT data flow from main.py for the user's apartment:
  V1: iteration=1, prompt="", history=[]
  V2: iteration=2, prompt="Redesign this space in the X style.", history=[V1 ai response]
  V3: iteration=3, prompt="Redesign this space in the Y style.", history=[V1 ai, V2 user redesign, V2 ai]

Reproduces main.py's per-iteration logic:
  - structural_identity_clause = render_clause(id, _gen_mode)  where _gen_mode∈{V1,V2,V3}
  - edit_mode = classify_edit_mode(user_instruction, iteration)
  - _gen_mode derived from edit_mode (V3 only if STRUCTURAL_TRANSFORMATION)
  - history fed verbatim to composer_v2
"""
import os
import sys
import difflib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "backend")))

from prompt_engine.structural_identity import (
    extract_from_description, render_clause, render_negative_anchors,
)
from prompt_engine.edit_intent import classify_edit_mode, EditMode
from prompt_engine.transformation_classifier import classify_transformation
from prompt_engine.composer_v2 import (
    compose_generation_prompt as compose_v2,
    resolve_switch_strategy,
    detect_history_customizations,
)

ROOM_DESC = (
    "Living room with a large floor-to-ceiling sliding glass door on the "
    "left wall opening to a balcony with vertical louvered shutters visible. "
    "Eye-level single-point perspective, medium spatial depth. Black-framed "
    "glass partition on the right separating the living zone from a rear "
    "room visible through the partition; a window is visible on the rear "
    "wall of the back room. Standard ceiling height. Herringbone wood floor "
    "throughout. Open kitchen visible on the right beyond the partition."
)
identity = extract_from_description(ROOM_DESC)
neg = render_negative_anchors(identity)


def derive_gen_mode(iteration, user_instruction):
    """Reproduce main.py:951-957 logic."""
    if iteration <= 1:
        return "V1"
    edit_mode = classify_edit_mode(user_instruction, iteration)
    if edit_mode == EditMode.STRUCTURAL_TRANSFORMATION:
        return "V3"
    return "V2"


def compose_for_iteration(atm_label, iteration, user_instruction, history):
    """Full main.py simulation of the compose_generation_prompt call."""
    gen_mode = derive_gen_mode(iteration, user_instruction)
    si_clause = render_clause(identity, gen_mode)
    return compose_v2(
        style_label=f"{atm_label} · Vision {iteration}",
        room_type="Living Room",
        room_description=ROOM_DESC,
        user_instruction=user_instruction,
        iteration=iteration,
        history=history,
        secondary_visible_spaces=["kitchen"],
        compact_prompts=False,
        structural_identity=si_clause,
        source_continuity="",
        structural_negative_anchors=neg,
        authorized_user_changes="",
    ), gen_mode, si_clause


def build_history_after_v1(atm_v1):
    """What main.py would have in history when V2 is called."""
    return [
        {"role": "ai", "content": f"Your space is ready. Generating your first {atm_v1} vision now."},
        {"role": "ai", "content": f"Here's your {atm_v1} transformation — Vision 1."},
    ]


def build_history_after_v2(atm_v1, atm_v2):
    """What main.py would have in history when V3 is called (after a pure-switch V2)."""
    return build_history_after_v1(atm_v1) + [
        {"role": "user", "content": f"Redesign this space in the {atm_v2} style."},
        {"role": "ai", "content": f"Vision 2 — applied your direction toward {atm_v2}."},
    ]


# ─────────────────────────────────────────────────────────────────────────────
# AUDIT: simulate real V1 / V2 / V3 trio on a fixed atmosphere
# ─────────────────────────────────────────────────────────────────────────────
atm_test_pairs = [
    ("Warm Modern",     "Bali Sanctuary"),  # V1 then switch to V2 then to V3
    ("Nordic Warmth",   "Japandi Calm"),
    ("Soft Luxury",     "Dark Contemporary"),
]

print("=" * 90)
print("REALISTIC V1 vs V2 vs V3 audit — exact main.py runtime simulation")
print("=" * 90)
print()
print("Per-iteration analysis:")
print()

for atm_a, atm_b in atm_test_pairs:
    print(f"── Scenario: V1 {atm_a}  →  V2 {atm_b}  →  V3 {atm_a} (chain) ──")

    # V1 — fresh, no history
    p_v1, mode_v1, clause_v1 = compose_for_iteration(atm_a, 1, "", [])

    # V2 — pure switch to atm_b
    hist_v2 = build_history_after_v1(atm_a)
    instr_v2 = f"Redesign this space in the {atm_b} style."
    p_v2, mode_v2, clause_v2 = compose_for_iteration(atm_b, 2, instr_v2, hist_v2)

    # Strategy that composer_v2 will pick
    from prompt_engine.atmosphere_dna import label_to_atmosphere_id
    atm_b_id = label_to_atmosphere_id(atm_b)
    strat_v2, prev_id_v2, has_cust_v2 = resolve_switch_strategy(hist_v2, atm_b_id, 2)
    has_cust_in_hist_v2 = detect_history_customizations(hist_v2)

    # V3 — pure switch back to atm_a, after V2 pure switch
    hist_v3 = build_history_after_v2(atm_a, atm_b)
    instr_v3 = f"Redesign this space in the {atm_a} style."
    p_v3, mode_v3, clause_v3 = compose_for_iteration(atm_a, 3, instr_v3, hist_v3)

    atm_a_id = label_to_atmosphere_id(atm_a)
    strat_v3, prev_id_v3, has_cust_v3 = resolve_switch_strategy(hist_v3, atm_a_id, 3)
    has_cust_in_hist_v3 = detect_history_customizations(hist_v3)

    # V1 reference re-composed for atm_a (what V3 SHOULD match if delegation works)
    p_v1_ref_a, _, clause_v1_ref_a = compose_for_iteration(atm_a, 1, "", [])

    # Same for atm_b (V2 reference)
    p_v1_ref_b, _, clause_v1_ref_b = compose_for_iteration(atm_b, 1, "", [])

    print(f"  V1 {atm_a:20}  mode={mode_v1}  size={len(p_v1):5d}  clause={len(clause_v1)} chars  facts={clause_v1.count(';')+1}")
    print(f"  V2 {atm_b:20}  mode={mode_v2}  size={len(p_v2):5d}  clause={len(clause_v2)} chars  facts={clause_v2.count(';')+1}")
    print(f"     strategy={strat_v2.value}  prev_atm={prev_id_v2!r}  cust_in_hist={has_cust_in_hist_v2}")
    print(f"  V3 {atm_a:20}  mode={mode_v3}  size={len(p_v3):5d}  clause={len(clause_v3)} chars  facts={clause_v3.count(';')+1}")
    print(f"     strategy={strat_v3.value}  prev_atm={prev_id_v3!r}  cust_in_hist={has_cust_in_hist_v3}")
    print()
    print(f"  GATE check — V2 == V1({atm_b})  ?  {p_v2 == p_v1_ref_b}")
    print(f"  GATE check — V3 == V1({atm_a})  ?  {p_v3 == p_v1_ref_a}")

    if p_v2 != p_v1_ref_b:
        diff_lines = list(difflib.unified_diff(
            p_v1_ref_b.splitlines(), p_v2.splitlines(),
            fromfile="V1_ref", tofile="V2", lineterm="",
        ))
        print(f"  V2 DIFF (first 10 lines):")
        for ln in diff_lines[:10]:
            print(f"    {ln}")

    if p_v3 != p_v1_ref_a:
        diff_lines = list(difflib.unified_diff(
            p_v1_ref_a.splitlines(), p_v3.splitlines(),
            fromfile="V1_ref", tofile="V3", lineterm="",
        ))
        print(f"  V3 DIFF (first 10 lines):")
        for ln in diff_lines[:10]:
            print(f"    {ln}")
    print()

# ─────────────────────────────────────────────────────────────────────────────
# CRITICAL CHECK: does the clause text contain "kitchen" in all 3 visions?
# ─────────────────────────────────────────────────────────────────────────────
print("=" * 90)
print("KITCHEN-PRESENCE CHECK per iteration")
print("=" * 90)
print()
print(f"  V1 clause ({len(clause_v1_ref_a)} chars) contains 'kitchen': {'kitchen' in clause_v1_ref_a.lower()}")
print(f"     {clause_v1_ref_a[:200]}...")
print()
# Compute V2 and V3 clauses for the same atmosphere on the user's apartment
clause_mode_v1 = render_clause(identity, "V1")
clause_mode_v2 = render_clause(identity, "V2")
clause_mode_v3 = render_clause(identity, "V3")
print(f"  render_clause(V1 mode) [{len(clause_mode_v1)} chars]  kitchen={('kitchen' in clause_mode_v1.lower())}")
print(f"  render_clause(V2 mode) [{len(clause_mode_v2)} chars]  kitchen={('kitchen' in clause_mode_v2.lower())}")
print(f"  render_clause(V3 mode) [{len(clause_mode_v3)} chars]  kitchen={('kitchen' in clause_mode_v3.lower())}")
print()
print(f"  V1 mode == V2 mode (clause text)?  {clause_mode_v1 == clause_mode_v2}")
print(f"  V1 mode == V3 mode (clause text)?  {clause_mode_v1 == clause_mode_v3}")
if clause_mode_v1 != clause_mode_v3:
    print(f"  V3 clause delta: +{len(clause_mode_v3) - len(clause_mode_v1)} chars")
    # Compare facts
    facts_v1 = clause_mode_v1.split(": ")[1].rsplit(".", 1)[0].split("; ") if ": " in clause_mode_v1 else []
    facts_v3 = clause_mode_v3.split(": ")[1].rsplit(".", 1)[0].split("; ") if ": " in clause_mode_v3 else []
    print(f"  V1 facts ({len(facts_v1)}): {facts_v1}")
    print(f"  V3 facts ({len(facts_v3)}): {facts_v3}")
