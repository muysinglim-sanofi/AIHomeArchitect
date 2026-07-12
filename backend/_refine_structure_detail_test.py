"""Refine V2 — tests UNITAIRES : le normalizer STRUCTURE ne jette JAMAIS `detail` (fix 2026-07-12).
Déterministe, AUCUN LLM. Construit les Change comme le parser les produit (object + detail) et
vérifie que le qualificatif spatial survit dans le texte normalisé — pour tous les qualificatifs
(right/left/rear/front/between…/next to…/opposite…), pas seulement « right ».
Lancer : PYTHONIOENCODING=utf-8 PYTHONPATH=. .venv/Scripts/python.exe _refine_structure_detail_test.py
"""
import sys
sys.stdout.reconfigure(encoding="utf-8")

from refine.parser import Change
from refine.normalizer import normalize

_fails = []


def check(name, cond, got=""):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}{('  got=' + repr(got)) if (got and not cond) else ''}")
    if not cond:
        _fails.append(name)


def S(object, detail, raw):
    return normalize(Change(type="structure", object=object, detail=detail, raw=raw))


print("== CAS DE BUG EXACT (parser réel : object=wall, detail=right) ==")
n = S("wall", "right", "break the wall on the right")
check("« break the wall on the right » → normalized contient « right wall »", "right wall" in n.lower(), n)
check("  … et NE dit PAS juste « the wall » sans côté", "the wall " not in n.lower() or "right wall" in n.lower(), n)

print("== ORIENTATION (adjectif avant le nom), verbe REMOVE ==")
for det, raw in [("right", "remove the wall on the right"),
                 ("left", "remove the left wall"),
                 ("rear", "knock down the rear wall"),
                 ("back", "demolish the back wall"),
                 ("front", "remove the front wall")]:
    n = S("wall", det, raw)
    check(f"remove + {det!r} → « {det} wall » dans normalized", f"{det} wall" in n.lower(), n)

print("== CLOSE / OPEN gardent aussi le côté ==")
n = S("window", "left", "close the left window")
check("close + left window → « left window »", "left window" in n.lower(), n)
n = S("wall", "right", "wall off the right side")  # 'wall off' = close
check("close(wall off) + right → « right » présent", "right" in n.lower(), n)
n = S("opening", "between the kitchen and the living room", "open up the opening between the kitchen and the living room")
check("open + « between … » → relation conservée", "between the kitchen" in n.lower(), n)

print("== RELATIONNEL (après le nom) ==")
for det, raw in [("next to the sofa", "remove the wall next to the sofa"),
                 ("opposite the window", "remove the wall opposite the window"),
                 ("between kitchen and living room", "remove the wall between kitchen and living room")]:
    n = S("wall", det, raw)
    check(f"remove + {det!r} → qualificatif conservé", det.split()[0] in n.lower() and det.split()[-1] in n.lower(), n)

print("== IDEMPOTENCE : detail déjà dans object → pas de doublon ==")
n = S("right wall", "right", "remove the right wall")
check("object='right wall' + detail='right' → pas de « right right »", "right right" not in n.lower(), n)
check("  … « right wall » toujours présent", "right wall" in n.lower(), n)

print("== SANS detail : pas de régression, pas de dangling ==")
n = S("wall", "", "remove the wall")
check("detail vide → « the wall » normal, pas de crash", "the wall" in n.lower() and n.endswith("."), n)

print("== NON-STRUCTURE inchangé (le fix ne touche que la branche structure) ==")
from refine.normalizer import normalize as _nz
nm = _nz(Change(type="move", object="sofa", detail="to the left", raw="Move the sofa to the left"))
check("move « to the left » toujours normalisé sans casse", "left" in nm.lower(), nm)

print()
if _fails:
    print(f"❌ {len(_fails)} FAIL: {_fails}")
    sys.exit(1)
print("✅ TOUS LES TESTS PASSENT")
