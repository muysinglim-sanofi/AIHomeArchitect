"""Refine Engine V2 — validation Composant 1.5 (Request Advisor). L1 offline + L2 mock.
Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_advisor_validation.py"""
import asyncio
import json
import sys

from refine.parser import Change
from refine.advisor import (advise, build_advisory_message, Verdict,
                            AdviceResult, ChangeAdvice)

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

def C(t, obj, raw): return Change(type=t, object=obj, detail="", raw=raw)

class _FakeLLM:
    """Renvoie un verdict fixe (par objet) ; enregistre les appels pour prouver l'escalade."""
    def __init__(self, by_obj):
        self.by_obj = by_obj; self.calls = []
    @property
    def chat(self):
        outer = self
        class Comp:
            async def create(self, **kw):
                user = kw["messages"][1]["content"]; outer.calls.append(user)
                verdict, reason, alt = "GREEN", "", ""
                for key, val in outer.by_obj.items():
                    if key in user.lower():
                        verdict, reason, alt = val; break
                payload = json.dumps({"verdict": verdict, "reason": reason, "alternative": alt})
                m = type("M", (), {"content": payload})()
                return type("R", (), {"choices": [type("Ch", (), {"message": m})()]})()
        return type("C", (), {"completions": Comp()})()


async def main():
    print("=== L1 GREEN fast-path (aucun appel LLM) ===")
    llm = _FakeLLM({})
    res = await advise([C("move","TV","move the TV to the left"),
                        C("remove","rug","remove the rug"),
                        C("modify","sofa","make the sofa darker"),
                        C("add","flowers","add flowers")], "living room", client=llm)
    check("tout GREEN", res.all_green is True, res.overall)
    check("source = rules (L1)", all(a.source == "rules" for a in res.advices))
    check("ZÉRO appel LLM (fast-path)", llm.calls == [], llm.calls)
    check("message = None (aucune friction)", build_advisory_message(res) is None)

    check("confidence GREEN L1 haute", all(a.confidence >= 0.9 for a in res.advices), [a.confidence for a in res.advices])

    print("\n=== L1 RED backstop : Ferrari dans une salle de bain ===")
    res = await advise([C("add","ferrari","add a Ferrari")], "bathroom", client=None)
    check("verdict RED", res.overall == Verdict.RED, res.overall)
    check("confidence RED ≈ 0.9", abs(res.advices[0].confidence - 0.90) < 0.01, res.advices[0].confidence)
    check("source rules (backstop, sans LLM)", res.advices[0].source == "rules")
    check("alternative fournie (jamais un mur)", bool(res.advices[0].alternative), res.advices[0].alternative)
    msg = build_advisory_message(res)
    check("message architecte + 'Would you like to'", msg and "architect" in msg and "Would you like to" in msg, msg)

    print("\n=== EXTÉRIEUR : voiture sur une allée n'est PAS RED ===")
    res = await advise([C("add","car","add a car")], "driveway", client=None)
    check("driveway + car → PAS RED (escalate→GREEN sans client)", res.overall != Verdict.RED, res.overall)
    res_pool = await advise([C("add","pool","add a swimming pool")], "garden", client=None)
    check("garden + pool → PAS RED", res_pool.overall != Verdict.RED, res_pool.overall)

    print("\n=== ESCALADE L2 : objet non-trivial → appel LLM ===")
    llm = _FakeLLM({"tv": ("YELLOW", "there is barely any free wall", ""),
                    "ferrari": ("RED", "a car cannot fit indoors", "place it on the driveway")})
    res = await advise([C("add","TV","add a TV")], "bathroom", client=llm)
    check("1 appel LLM (escaladé)", len(llm.calls) == 1, llm.calls)
    check("verdict YELLOW (de L2)", res.overall == Verdict.YELLOW, res.overall)
    check("source = llm", res.advices[0].source == "llm")
    check("raison remontée", "free wall" in res.advices[0].reason, res.advices[0].reason)

    print("\n=== confidence : escalade sans client = basse (non jugé) ===")
    res_nc = await advise([C("add","TV","add a TV")], "bathroom", client=None)  # ni décor ni fonctionnel ni structure
    check("escalade fail-open GREEN, confidence basse (0.5)", abs(res_nc.advices[0].confidence - 0.5) < 0.01, res_nc.advices[0].confidence)

    print("\n=== CALIBRATION STRUCTURE / INSTALLATION FONCTIONNELLE (L1, canonicalisé) ===")
    from refine.parser import parse_deterministic
    async def verdict(msg, room="living room"):
        return (await advise(parse_deterministic(msg), room, client=None)).overall.value
    # structure explicite + ciblée/ajout → GREEN
    for msg in ["remove the right wall", "close the back window", "add a new window on the right wall",
                "add a partition wall", "knock down the dividing wall"]:
        check(f"GREEN structure: {msg}", await verdict(msg) == "green")
    # installation fonctionnelle explicite + plausible → GREEN
    for msg in ["add an open kitchen with an island", "create a dressing area",
                "convert this side into a bathroom", "convert the right side into an open kitchen"]:
        check(f"GREEN fonctionnel: {msg}", await verdict(msg) == "green")
    # structure AMBIGUË (cible non identifiable) → YELLOW
    for msg in ["remove this wall", "remove the wall", "close the window"]:
        check(f"YELLOW ambigu: {msg}", await verdict(msg) == "yellow", await verdict(msg))
    # ── Correction Pass 2026-08-13 — ASSERTION RÉÉCRITE, NE PAS LA REMETTRE À L'ENVERS ──
    # AVANT, ce bloc s'intitulait « absurde → RED même si structure/typé » et n'assertait
    # que les deux lignes RED : il verrouillait donc l'IMPLÉMENTATION (un .search() de
    # sous-chaîne sur _ABSURD_INTERIOR, appliqué avant tout test de type). Or ce mécanisme
    # produisait un faux RED sur « paint the walls forest green » — forest/ocean/sea sont
    # AUSSI des noms de couleur — c'est-à-dire un véto esthétique sur une demande de
    # peinture banale, en contradiction avec le contrat anti-paternalisme du composant
    # (advisor.py, docstring l.15-16). L'assertion teste désormais l'INTENTION :
    #   « un ADD d'objet réellement absurde dans un INTÉRIEUR CONNU reste RED »,
    # et pas « la sous-chaîne pool/forest déclenche RED ». Les contre-exemples ci-dessous
    # font partie de l'assertion : ils empêchent de « recorriger » le composant en
    # rétablissant le véto par sous-chaîne, qui les repasserait tous au rouge.
    check("RED absurde: add a swimming pool (bedroom)", await verdict("add a swimming pool", "bedroom") == "red")
    check("RED absurde: add a Ferrari (bathroom)", await verdict("add a Ferrari", "bathroom") == "red")
    # A1-b — le terme absurde en QUALIFICATIF de couleur n'introduit aucun objet.
    for msg in ["paint the walls forest green", "paint the walls ocean blue",
                "make the walls sea green"]:
        check(f"PAS RED (couleur, pas un objet): {msg}", await verdict(msg) != "red", await verdict(msg))
    # A1-a — une modification de PROPRIÉTÉ ne peut pas faire entrer une piscine.
    check("PAS RED (propriété): change the sofa to forest green",
          await verdict("change the sofa to forest green") != "red")
    # A2 — pièce INCONNUE (libellé produit / localisé / absent) : plus de véto dur.
    for room in ["", "Your space", "Salon"]:
        check(f"PAS RED (pièce inconnue {room!r}): add a swimming pool",
              await verdict("add a swimming pool", room) != "red",
              await verdict("add a swimming pool", room))
    # non-régression mobilier
    check("GREEN mobilier: move the TV to the left", await verdict("move the TV to the left") == "green")
    check("GREEN décor: add flowers", await verdict("add flowers") == "green")

    print("\n=== FAIL-OPEN L2 : panne LLM → GREEN (jamais bloquer) ===")
    class _BoomLLM:
        @property
        def chat(self):
            class Comp:
                async def create(self, **kw): raise RuntimeError("LLM down")
            return type("C", (), {"completions": Comp()})()
    res = await advise([C("add","fireplace","add a fireplace")], "living room", client=_BoomLLM())
    check("panne L2 → GREEN", res.overall == Verdict.GREEN, res.overall)

    print("\n=== MIXTE : move TV (green) + Ferrari (red) → per-change ===")
    llm = _FakeLLM({})
    res = await advise([C("move","TV","move the TV to the right"),
                        C("add","ferrari","add a Ferrari")], "bathroom", client=llm)
    check("overall = RED (pire verdict)", res.overall == Verdict.RED, res.overall)
    check("green_changes = [move TV]", [c.type for c in res.green_changes] == ["move"], [c.raw for c in res.green_changes])
    check("1 seul flagged (Ferrari)", len(res.flagged) == 1 and res.flagged[0].verdict == Verdict.RED)
    msg = build_advisory_message(res)
    check("D-c : PAS de drop implicite ('do the rest' absent)", msg and "do the rest" not in msg, msg)
    check("green_changes calculé (donnée) mais pas proposé en bouton", [c.type for c in res.green_changes] == ["move"])
    check("Ferrari n'a PAS déclenché d'appel LLM (RED en L1)", all("ferrari" not in c.lower() for c in llm.calls), llm.calls)

    print("\n--- exemples de messages ---")
    print(build_advisory_message(await advise([C("add","swimming pool","add a swimming pool")], "bedroom")))
    print("···")
    print(msg)
    print("---")

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(asyncio.run(main()))
