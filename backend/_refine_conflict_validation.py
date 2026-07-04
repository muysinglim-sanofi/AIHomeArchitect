"""Refine Engine V2 — validation Composant 2.5 (Conflict Resolver), 100% offline.
Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_conflict_validation.py"""
import sys

from refine.parser import Change
from refine.normalizer import normalize_changes
from refine.conflict import resolve_conflicts

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

def C(t, obj, raw): return Change(type=t, object=obj, detail="", raw=raw)

def resolve(chs):
    normalize_changes(chs)
    return resolve_conflicts(chs)


def main():
    print("=== R-A : remove coffee table + add flowers (défaut assumé = coffee table) ===")
    kept, conf = resolve([C("remove","coffee table","remove the coffee table"),
                          C("add","flowers","add flowers")])
    add = next(c for c in kept if c.type == "add")
    check("l'ADD ne mentionne plus 'coffee table'", "coffee table" not in add.normalized.lower(), add.normalized)
    check("re-placé sur surface neutre", "main visible surface" in add.normalized.lower(), add.normalized)
    check("conflit journalisé", any("R-A" in x for x in conf), conf)
    check("les 2 changements conservés", len(kept) == 2)

    print("\n=== R-A : add flowers ON the coffee table (lieu explicite) + remove it ===")
    kept, conf = resolve([C("add","flowers","add a vase of flowers on the coffee table"),
                          C("remove","coffee table","remove the coffee table")])
    add = next(c for c in kept if c.type == "add")
    check("locative 'on the coffee table' retirée", "coffee table" not in add.normalized.lower(), add.normalized)
    check("garde bien l'item (flowers)", "flower" in add.normalized.lower(), add.normalized)

    print("\n=== pas de conflit : remove sofa + add flowers (default coffee table OK) ===")
    kept, conf = resolve([C("remove","sofa","remove the sofa"),
                          C("add","flowers","add flowers")])
    add = next(c for c in kept if c.type == "add")
    check("flowers restent sur coffee table (sofa non lié)", "coffee table" in add.normalized.lower(), add.normalized)
    check("aucun conflit", conf == [], conf)

    print("\n=== R-B : remove TV + move TV → le move est droppé ===")
    kept, conf = resolve([C("remove","TV","remove the TV"),
                          C("move","TV","move the TV to the left wall")])
    check("le MOVE est supprimé", all(c.type != "move" for c in kept), [c.type for c in kept])
    check("le REMOVE reste", any(c.type == "remove" for c in kept))
    check("R-B journalisé", any("R-B" in x for x in conf), conf)

    print("\n=== R-C : move sofa left + move sofa right → garder le dernier ===")
    kept, conf = resolve([C("move","sofa","move the sofa to the left"),
                          C("move","sofa","move the sofa to the right")])
    moves = [c for c in kept if c.type == "move"]
    check("un seul MOVE conservé", len(moves) == 1, [c.raw for c in moves])
    check("c'est le dernier (right)", "right" in moves[0].raw, moves[0].raw)
    check("R-C journalisé", any("R-C" in x for x in conf), conf)

    print("\n=== R-D : replace TV + move TV → retirer 'in the same position' ===")
    kept, conf = resolve([C("replace","TV","replace the TV with a fireplace"),
                          C("move","TV","move the TV to the other wall")])
    rep = next(c for c in kept if c.type == "replace")
    check("plus de 'in the same position'", "same position" not in rep.normalized.lower(), rep.normalized)
    check("le MOVE reste (objet non supprimé)", any(c.type == "move" for c in kept))
    check("R-D journalisé", any("R-D" in x for x in conf), conf)

    print("\n=== R-E : structure remove wall + add artwork on that wall ===")
    kept, conf = resolve([C("structure","wall","remove the dividing wall"),
                          C("add","artwork","add artwork on the wall")])
    add = next(c for c in kept if c.type == "add")
    check("artwork re-placé sur un mur restant", "remaining wall" in add.normalized.lower(), add.normalized)
    check("R-A/R-E journalisé", any("R-A" in x or "R-E" in x for x in conf), conf)

    print("\n=== idempotence : re-résoudre ne change plus rien ===")
    chs = [C("remove","coffee table","remove the coffee table"), C("add","flowers","add flowers")]
    normalize_changes(chs)
    k1, _ = resolve_conflicts(chs)
    snap = [c.normalized for c in k1]
    k2, conf2 = resolve_conflicts(k1)
    check("normalized stable après 2e passe", [c.normalized for c in k2] == snap, [c.normalized for c in k2])
    check("aucun nouveau conflit à la 2e passe", conf2 == [], conf2)

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(main())
