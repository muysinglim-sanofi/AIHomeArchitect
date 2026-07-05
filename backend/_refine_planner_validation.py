"""Refine Engine V2 — validation du Composant 3 (Smart Planner). OFFLINE, no image.
Run: PYTHONPATH=. python _refine_planner_validation.py"""
import sys

from refine.parser import parse_deterministic
from refine.normalizer import normalize_changes
from refine.planner import plan, ExecutionPlan, _COMBINABLE, STRATEGY_COMBINED_EDIT

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

def pipe(msg):
    return normalize_changes(parse_deterministic(msg))


def main():
    print("=== ORDRE : STRUCTURE → REMOVE → REPLACE → ADD → MODIFY → MOVE ===")
    # message mélangé volontairement dans le désordre
    chs = pipe("move the TV to the left wall, make it warmer, add a rug, "
               "replace the sofa with a leather one, remove the armchair, open the kitchen")
    p = plan(chs)
    order = [c.type for c in p.ordered_changes]
    check(f"ordre correct {order}", order == ["structure","remove","replace","add","modify","move"], str(order))

    print("\n=== EXECUTION STRATEGY (seam) ===")
    check("stratégie = combined_edit", p.strategy.kind == STRATEGY_COMBINED_EDIT, p.strategy.kind)
    check("strategy.prompt == combined_prompt (compat)", p.strategy.prompt == p.combined_prompt)
    check("strategy.changes = ordered_changes", p.strategy.changes == p.ordered_changes)

    print("\n=== PROMPT COMBINÉ ===")
    check("contient 'Apply ALL of these changes'", "Apply ALL of these changes" in p.combined_prompt)
    check("contient la clause préservation (architecture seule)", "Preserve ONLY the architectural" in p.combined_prompt); check("mobilier NON verrouillé (furniture editable)", "furniture is NOT fixed" in p.combined_prompt.lower() or "fully editable" in p.combined_prompt)
    check("contient les 6 items numérotés", all(f"({i})" in p.combined_prompt for i in range(1,7)))
    check("utilise le normalized (remove renforcé)", "leaving that floor area empty" in p.combined_prompt)

    print("\n=== COMPATIBILITÉ (combinable vs isolate) ===")
    check("isolate = structure + move", sorted(c.type for c in p.isolate) == ["move","structure"], str([c.type for c in p.isolate]))
    check("combinable = remove/replace/add/modify", all(c.type in _COMBINABLE for c in p.combinable) and len(p.combinable)==4)

    print("\n=== estimated_success (matrice) ===")
    check("3 ADD → succès élevé (~0.86)", abs(plan(pipe("add flowers, add books, add a rug")).estimated_success - 0.95**3) < 0.01,
          plan(pipe("add flowers, add books, add a rug")).estimated_success)
    es_move = plan(pipe("move the sofa to the left")).estimated_success
    check("MOVE seul → succès bas (~0.45)", abs(es_move - 0.45) < 0.01, es_move)
    es_mix = plan(pipe("move the TV to the left, add flowers, remove the table")).estimated_success
    check("move+add+remove → bas (<0.45, MOVE pénalise)", es_mix < 0.45, es_mix)
    check("1 REMOVE → haut (~0.95)", abs(plan(pipe("remove the table")).estimated_success - 0.95) < 0.01)

    print("\n=== PRÉDICTION 'predicted_partial' ===")
    p_adds = plan(pipe("add flowers, add books, add a rug"))
    check("3 ADD → predicted_partial=False", p_adds.predicted_partial is False)
    p_moves = plan(pipe("move the TV to the left, rotate the sofa, move the table to the corner"))
    check("plusieurs MOVE → predicted_partial=True", p_moves.predicted_partial is True)
    p_struct1 = plan(pipe("open the kitchen"))
    check("1 STRUCTURE seule → predicted_partial=False", p_struct1.predicted_partial is False)

    print("\n=== MODE RETRY (cible les manquants seulement) ===")
    chs2 = pipe("move the TV to the left wall, add flowers, remove the table")
    missing = [c for c in chs2 if c.type == "move"]   # simule : seul le move a manqué
    pr = plan(chs2, mode="retry", missing=missing)
    check("retry mode", pr.mode == "retry")
    check("retry ne cible que le move", len(pr.ordered_changes)==1 and pr.ordered_changes[0].type=="move")
    check("prompt retry ne contient que le manquant", "flowers" not in pr.combined_prompt and "TV" in pr.combined_prompt)

    print("\n=== PROMPT COMBINÉ (cas phare, pour revue) ===")
    ph = plan(pipe("Move the TV to the right wall, rotate the sofa to face it, remove the dining table."))
    print("-----")
    print(ph.combined_prompt)
    print("-----")

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(main())
