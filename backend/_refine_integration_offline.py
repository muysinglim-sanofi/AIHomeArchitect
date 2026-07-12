"""Refine Engine V2 — INTÉGRATION OFFLINE (chaîne complète, 0 image, 0 LLM, gratuit).

Fait passer 20 scénarios canoniques dans TOUTE la chaîne logique assemblée :
   Parser → Request Advisor(L1) → Normalizer → Conflict Resolver → Planner
et vérifie qu'elles composent : l'Advisor laisse passer le normal / bloque l'absurde,
le Conflict Resolver résout sans casser, le Planner reçoit des données ordonnées & un
prompt bien formé. (La partie image/Verify = benchmark réel séparé.)
Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_integration_offline.py"""
import asyncio
import sys

from refine.parser import parse_deterministic
from refine.advisor import advise, build_advisory_message, Verdict
from refine.normalizer import normalize_changes
from refine.conflict import resolve_conflicts
from refine.planner import plan, STRATEGY_COMBINED_EDIT

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"    [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

_ORDER_RANK = {"structure": 0, "remove": 1, "replace": 2, "add": 3, "modify": 4, "move": 5}

# (id, message, room, attendu_advisor, attend_conflit)
SCENARIOS = [
    ("mv1", "move the TV to the left wall", "bedroom", "green", False),
    ("rm1", "remove the coffee table", "living room", "green", False),
    ("ad1", "add a floor lamp in the corner", "living room", "green", False),
    ("rp1", "replace the sofa with a leather one", "living room", "green", False),
    ("md1", "make the room warmer", "bedroom", "green", False),
    ("st1", "open the kitchen", "kitchen", "green", False),
    ("mx1", "move the TV to the right and add flowers", "living room", "green", False),  # pas de remove → pas de conflit
    ("mx2", "remove the dining table and add a rug", "dining room", "green", False),
    ("cf1", "remove the coffee table and add flowers", "living room", "green", True),    # R-A
    ("cf2", "move the sofa to the left and move the sofa to the right", "living room", "green", True),  # R-C
    ("cf3", "remove the TV and move the TV to the wall", "living room", "green", True),   # R-B
    ("cf4", "replace the TV with a fireplace and move the TV", "living room", "green", True),  # R-D
    ("ad2", "add artwork, add books and add a plant", "living room", "green", False),
    ("mix", "make it brighter, add cushions and remove the rug", "bedroom", "green", False),
    ("st2", "open the kitchen, remove the clock, add an island and move the fridge", "kitchen", "green", False),
    ("mv2", "rotate the armchair", "living room", "green", False),
    ("es1", "add a kitchen island", "kitchen", "green", False),   # escalate→green (offline)
    ("rd1", "add a swimming pool", "bedroom", "red", False),      # advisor backstop
    ("rd2", "add a Ferrari", "bathroom", "red", False),           # advisor backstop
    ("ex1", "add a car", "driveway", "green", False),             # extérieur → PAS red
]


async def run(msg, room):
    changes = parse_deterministic(msg)
    advice = await advise(changes, room, client=None)     # L1 seul (offline)
    normalize_changes(changes)
    kept, conflicts = resolve_conflicts(changes)
    p = plan(kept)
    return changes, advice, kept, conflicts, p


async def main():
    print("=== INTÉGRATION OFFLINE — chaîne complète sur 20 scénarios ===\n")
    crashes = 0
    for sid, msg, room, exp_adv, exp_conf in SCENARIOS:
        print(f"[{sid}] ({room}) “{msg}”")
        try:
            changes, advice, kept, conflicts, p = await run(msg, room)
        except Exception as e:  # noqa: BLE001
            crashes += 1; _fails_local = True
            check(f"{sid} NE CRASHE PAS", False, repr(e)); print()
            continue

        # 1) l'Advisor rend le verdict attendu
        check(f"advisor overall = {exp_adv}", advice.overall.value == exp_adv, advice.overall.value)

        if advice.overall == Verdict.GREEN:
            # 2) la chaîne aval produit un plan exploitable
            check("≥1 changement planifié", len(p.ordered_changes) >= 1, len(p.ordered_changes))
            # 3) ordre §10 respecté (non décroissant)
            ranks = [_ORDER_RANK.get(c.type, 9) for c in p.ordered_changes]
            check("ordre §10 (non décroissant)", ranks == sorted(ranks), ranks)
            # 4) stratégie = combined_edit + prompt bien formé
            check("strategy = combined_edit", p.strategy.kind == STRATEGY_COMBINED_EDIT)
            npc = len(p.ordered_changes)
            if npc >= 2:
                # FIX 2026-07-12 : la clause de préservation est désormais choisie par action
                # (contrats ciblés). Invariant commun à TOUS les contrats = le suffixe "SAME room".
                check("prompt multi = 'Apply ALL' + contrat de préservation",
                      "Apply ALL of these changes" in p.combined_prompt and "Keep it the SAME room" in p.combined_prompt)
            check("chaque changement normalisé (non vide)", all(c.normalized for c in p.ordered_changes))
            # 5) pas de message advisory quand tout est GREEN
            check("aucun message advisory (GREEN)", build_advisory_message(advice) is None)
        else:
            # advisory : message présent, aucune image (on n'a pas planifié)
            check("message advisory présent", bool(build_advisory_message(advice)))

        # 6) conflits détectés là où attendu
        if exp_conf:
            check("conflit(s) résolu(s) détecté(s)", len(conflicts) >= 1, conflicts)

        # trace compacte
        print(f"      types={[c.type for c in changes]}  →  planned={[c.type for c in p.ordered_changes] if advice.overall==Verdict.GREEN else '—(advisory)'}"
              f"{('  conflicts='+str(len(conflicts))) if conflicts else ''}")
        print()

    check("aucun crash sur les 20 scénarios", crashes == 0, crashes)

    # regard ciblé sur les conflits (contenu, pas juste présence)
    print("=== VÉRIFS CIBLÉES CONFLITS ===")
    _, _, _, conf_cf1, p_cf1 = await run("remove the coffee table and add flowers", "living room")
    add_cf1 = next(c for c in p_cf1.ordered_changes if c.type == "add")
    check("cf1 : flowers re-placés hors 'coffee table'", "coffee table" not in add_cf1.normalized.lower(), add_cf1.normalized)
    _, _, kept_cf3, _, _ = await run("remove the TV and move the TV to the wall", "living room")
    check("cf3 : le MOVE du TV supprimé (R-B)", all(c.type != "move" for c in kept_cf3), [c.type for c in kept_cf3])

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(asyncio.run(main()))
