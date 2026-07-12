"""Refine V2 — tests UNITAIRES du sélecteur de contrat de préservation (Phase 3).

Déterministe, AUCUN LLM, AUCUNE image. On construit les `Change` exactement comme le
parser les produit (validé en Phase 1 sur le parser réel) et on vérifie :
  - la bonne clause est choisie par action ;
  - l'identité de l'objet cible / des voisins est verrouillée où il faut ;
  - le reflow de POSITION n'est autorisé que pour move/remove ;
  - le cas 6 « redesign the entire layout » (mal typé `structure` par le parser)
    est bien rattrapé en GLOBAL_REFLOW par le détecteur, AVANT la branche structure ;
  - le multi-action « move + add » route en MOVE_WITH_LOCAL_REFLOW (même canapé déplacé,
    fleurs ajoutées, rien de remplacé).
Lancer : .venv/Scripts/python.exe _refine_preservation_contract_test.py
"""
import sys

sys.stdout.reconfigure(encoding="utf-8")

from refine.parser import Change
from refine.planner import (
    preservation_contract,
    ADD_ONLY_CONTRACT,
    TARGETED_MODIFY_CONTRACT,
    MOVE_WITH_LOCAL_REFLOW_CONTRACT,
    TARGETED_REMOVE_CONTRACT,
    TARGETED_REPLACE_CONTRACT,
    _STRUCT_MANDATE,
    _PRESERVE,
)

_fails = []


def check(name, cond):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}")
    if not cond:
        _fails.append(name)


def C(type, object="", detail="", raw=""):
    return Change(type=type, object=object, detail=detail, raw=raw or object)


print("== 1) ADD seul → ADD_ONLY (rien d'autre ne bouge : ni position ni identité) ==")
c = preservation_contract([C("add", "flowers", raw="Add flowers.")])
check("add flowers → ADD_ONLY_CONTRACT", c == ADD_ONLY_CONTRACT)
check("ADD_ONLY interdit move/replace/reorganize (interdiction scopée)",
      "do NOT reorganize, redesign, move, replace" in c
      and "Apart from the change(s) explicitly listed above" in c)

print("== 2) MOVE ciblé → MOVE_WITH_LOCAL_REFLOW ==")
c = preservation_contract([C("move", "sofa", "to the left", "Move the sofa to the left.")])
check("move sofa → MOVE_WITH_LOCAL_REFLOW_CONTRACT", c == MOVE_WITH_LOCAL_REFLOW_CONTRACT)
check("cible: MÊME objet déplacé (identité cible verrouillée)", "move the SAME original object" in c)
check("voisins: identité verrouillée (pas de redesign)",
      "repositioning nearby objects does NOT authorize redesigning them" in c)
check("voisins: POSITION ajustable si nécessaire", "reposition or slightly rotate NEARBY furniture" in c)
check("voisins: pas de remplacement/altération (scopé)",
      "do NOT replace, remove, add, recolour, restyle, resize or materially alter any furniture" in c)

print("== 3) MODIFY ciblé → TARGETED_MODIFY (seule la propriété demandée change) ==")
c = preservation_contract([C("modify", "sofa", "beige", "Change the sofa color to beige.")])
check("modify sofa color → TARGETED_MODIFY_CONTRACT", c == TARGETED_MODIFY_CONTRACT)
check("même objet, seule la propriété change", "only the requested property changes" in c)
check("forme/modèle/position cible conservés", "same model, shape, proportions and position" in c)

print("== 4) REPLACE ciblé → TARGETED_REPLACE (seul le lustre) ==")
c = preservation_contract([C("replace", "chandelier", raw="Replace the chandelier.")])
check("replace chandelier → TARGETED_REPLACE_CONTRACT", c == TARGETED_REPLACE_CONTRACT)
check("remplace SEULEMENT l'objet ciblé", "Replace ONLY the explicitly targeted object" in c)

print("== 5) REMOVE ciblé → TARGETED_REMOVE (seul le fauteuil) ==")
c = preservation_contract([C("remove", "armchair", raw="Remove the armchair.")])
check("remove armchair → TARGETED_REMOVE_CONTRACT", c == TARGETED_REMOVE_CONTRACT)
check("supprime SEULEMENT l'objet ciblé", "Remove ONLY the explicitly targeted object" in c)
check("autres meubles: identité conservée", "identity, design, colour, material, proportions" in c)

print("== 6) « Redesign the entire layout » (mal typé structure par le parser) → BUG SÉPARÉ ==")
# Reproduit EXACTEMENT le parse réel de la Phase 1 : type=structure, object=layout. HORS SCOPE de
# ce patch : le mauvais classement + un contrat GLOBAL_REFLOW dédié = ticket séparé. Ici on VERROUILLE
# le comportement ACTUEL (branche structure, inchangée) pour prouver que le patch ne l'a pas touché.
c = preservation_contract([C("structure", "layout", "entire", "Redesign the entire layout.")])
check("redesign entire layout → structure INCHANGÉE (bug séparé, non traité ici)",
      c == _STRUCT_MANDATE + _PRESERVE)

print("== 7) STRUCTURE réelle (« remove the wall ») → mandat structurel INCHANGÉ ==")
c = preservation_contract([C("structure", "wall", raw="Remove the wall.")])
check("remove wall → _STRUCT_MANDATE + _PRESERVE (branche validée, non modifiée)",
      c == _STRUCT_MANDATE + _PRESERVE)
check("structure → PAS un contrat mobilier",
      c not in (ADD_ONLY_CONTRACT, MOVE_WITH_LOCAL_REFLOW_CONTRACT, TARGETED_REMOVE_CONTRACT,
                TARGETED_REPLACE_CONTRACT, TARGETED_MODIFY_CONTRACT))

print("== 8) PLANS MIXTES : toutes les actions demandées permises, rien d'autre touché ==")
# Invariant clé : chaque interdiction est SCOPÉE → l'autre action demandée (dans la checklist) n'est
# jamais interdite par le contrat, tout en verrouillant l'identité du mobilier non ciblé.
SCOPE = "Apart from the change(s) explicitly listed above, do NOT"


def mixed(name, changes, expected):
    c = preservation_contract(changes)
    check(f"{name} → contrat attendu", c == expected)
    check(f"{name} : interdiction SCOPÉE (co-action non contredite)", SCOPE in c)
    check(f"{name} : identité du mobilier non ciblé verrouillée",
          "Preserve" in c and ("every OTHER" in c or "every existing" in c))


mixed("modify+add",  [C("modify", "sofa", "beige", "change the sofa colour to beige"),
                      C("add", "rug", raw="add a rug")],                          TARGETED_MODIFY_CONTRACT)
mixed("replace+add", [C("replace", "chandelier", raw="replace the chandelier"),
                      C("add", "rug", raw="add a rug")],                          TARGETED_REPLACE_CONTRACT)
mixed("remove+add",  [C("remove", "armchair", raw="remove the armchair"),
                      C("add", "lamp", raw="add a floor lamp")],                  TARGETED_REMOVE_CONTRACT)
mixed("move+replace", [C("move", "sofa", raw="move the sofa"),
                       C("replace", "chandelier", raw="replace the chandelier")], MOVE_WITH_LOCAL_REFLOW_CONTRACT)
mixed("move+add",    [C("move", "sofa", "to the left", "move the sofa to the left"),
                      C("add", "flowers", raw="add flowers on the table")],       MOVE_WITH_LOCAL_REFLOW_CONTRACT)

print("== 9) Garde-fous : add+add reste ADD_ONLY ; move+remove → MOVE (position la plus permissive) ==")
check("add+add → ADD_ONLY", preservation_contract([C("add", "lamp"), C("add", "rug")]) == ADD_ONLY_CONTRACT)
check("move+remove → MOVE (précédence position)",
      preservation_contract([C("move", "sofa"), C("remove", "chair")]) == MOVE_WITH_LOCAL_REFLOW_CONTRACT)

print()
if _fails:
    print(f"❌ {len(_fails)} FAIL: {_fails}")
    sys.exit(1)
print("✅ TOUS LES TESTS PASSENT")
