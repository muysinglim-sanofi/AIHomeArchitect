"""Refine Engine V2 — validation du Composant 2 (Normalizer). OFFLINE, déterministe, no image.
Run: PYTHONPATH=. python _refine_normalizer_validation.py"""
import sys

from refine.parser import Change, parse_deterministic
from refine.normalizer import normalize, normalize_changes

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

def C(t, raw, obj="", det=""):
    return Change(type=t, object=obj, detail=det, raw=raw)

def norm(t, raw, obj="", det=""):
    return normalize(C(t, raw, obj, det))


def main():
    print("=== MOVE (cible injectée si absente — N2) ===")
    m = norm("move", "move the TV")
    check("move sans cible → 'onto a different wall'", "onto a different wall" in m, m)
    r = norm("move", "rotate the sofa")
    check("rotate sans cible → 'face the opposite direction'", "face the opposite direction" in r, r)
    mt = norm("move", "move the TV to the right wall")
    check("move AVEC cible → conservée, PAS de cible injectée",
          "right wall" in mt and "onto a different wall" not in mt, mt)

    print("\n=== REMOVE / REPLACE (renforts — N3) ===")
    rm = norm("remove", "remove the coffee table")
    check("remove → 'Completely remove' + 'leaving that floor area empty'",
          "Completely remove" in rm and "leaving that floor area empty" in rm, rm)
    rm2 = norm("remove", "get rid of the rug")
    check("get rid of → 'leaving that floor area empty'", "leaving that floor area empty" in rm2, rm2)
    rp = norm("replace", "replace the sofa with a leather one")
    check("replace → 'in the same position'", "in the same position" in rp, rp)

    print("\n=== ADD (placement par objet ; défaut coffee table) ===")
    fl = norm("add", "add flowers")
    check("add flowers → 'on the coffee table or main visible surface'",
          "on the coffee table or main visible surface" in fl, fl)
    rg = norm("add", "add a rug")
    check("add rug → 'on the floor under the main seating'", "on the floor under the main seating" in rg, rg)
    pl = norm("add", "add a large plant")
    check("add plant → 'in a corner'", "in a corner" in pl, pl)
    art = norm("add", "add a mirror")
    check("add mirror → 'on the main wall'", "on the main wall" in art, art)
    loc = norm("add", "add a lamp in the corner")
    check("add AVEC lieu → conservé, PAS de placement par défaut ajouté",
          "in the corner" in loc and "coffee table" not in loc, loc)

    print("\n=== MODIFY / STRUCTURE ===")
    w = norm("modify", "make it warmer")
    check("modify warmer → 'warmer tones'", "warmer tones" in w, w)
    ok = norm("structure", "open the kitchen")
    check("structure open kitchen → 'removing the dividing wall'", "removing the dividing wall" in ok, ok)
    pw = norm("structure", "add a partition wall")
    check("structure partition → conservé", "partition wall" in pw.lower(), pw)

    print("\n=== INSTALLATION FONCTIONNELLE (zone ≠ décoratif ≠ open-wall) ===")
    fk = norm("add", "add an open kitchen with an island")
    check("kitchen add → zone fonctionnelle (PAS coffee table)",
          "functional installation" in fk.lower() and "coffee table" not in fk.lower(), fk)
    ck = norm("structure", "convert the right side into a kitchen")
    check("convert→kitchen → zone (PAS 'removing the wall')",
          "functional installation" in ck.lower() and "removing the wall" not in ck.lower(), ck)
    ff = norm("add", "add a fireplace")
    check("fireplace add → zone fonctionnelle (PAS 'on the main wall')",
          "functional installation" in ff.lower() and "on the main wall" not in ff.lower(), ff)
    okk = norm("structure", "open the kitchen")
    check("open the kitchen → reste STRUCTUREL (dividing wall)", "removing the dividing wall" in okk.lower(), okk)

    print("\n=== IDEMPOTENCE ===")
    idem = norm("remove", "Completely remove the coffee table, leaving that floor area empty")
    check("remove déjà normalisé → pas de double 'leaving'", idem.lower().count("leaving") == 1, idem)
    idem2 = norm("replace", "Replace the sofa with a leather one, in the same position")
    check("replace déjà normalisé → pas de double 'in the same position'",
          idem2.lower().count("in the same position") == 1, idem2)

    print("\n=== INTÉGRATION Parser → Normalizer (cas phare) ===")
    chs = normalize_changes(parse_deterministic(
        "Move the TV to the right wall, rotate the sofa to face it, remove the dining table."))
    check("3 changements normalisés", len(chs) == 3 and all(c.normalized for c in chs))
    check("[2] remove renforcé", "leaving that floor area empty" in chs[2].normalized, chs[2].normalized)
    for c in chs:
        print(f"       {c.type:9} → {c.normalized!r}")

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(main())
