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

    print("\n=== L1 RED backstop : Ferrari dans une salle de bain ===")
    res = await advise([C("add","ferrari","add a Ferrari")], "bathroom", client=None)
    check("verdict RED", res.overall == Verdict.RED, res.overall)
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
    check("message mentionne 'I can do the rest'", msg and "do the rest" in msg, msg)
    check("Ferrari n'a PAS déclenché d'appel LLM (RED en L1)", all("ferrari" not in c.lower() for c in llm.calls), llm.calls)

    print("\n--- exemples de messages ---")
    print(build_advisory_message(await advise([C("add","swimming pool","add a swimming pool")], "bedroom")))
    print("···")
    print(msg)
    print("---")

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(asyncio.run(main()))
