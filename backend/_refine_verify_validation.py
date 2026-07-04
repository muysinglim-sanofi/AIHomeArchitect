"""Refine Engine V2 — validation Composant 5 (Verify), MOCK (no real vision call).
Run: PYTHONPATH=. python _refine_verify_validation.py"""
import asyncio
import json
import sys

from refine.parser import Change
from refine.verify import verify, build_report, missing_changes, VerifyResult

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

def C(t, raw): return Change(type=t, object="", detail="", raw=raw)

class _FakeVision:
    def __init__(self, content): self._c = content
    @property
    def chat(self):
        outer = self
        class Comp:
            async def create(self, **kw):
                m = type("M", (), {"content": outer._c})()
                return type("R", (), {"choices": [type("C", (), {"message": m})()]})()
        return type("Ch", (), {"completions": Comp()})()

CH = [C("move","move the TV"), C("add","add flowers"), C("remove","remove the table")]

async def main():
    print("=== VERIFY (mock vision) ===")
    good = json.dumps({"applied":[False,True,True],"identity_preserved":True,"naturalness_ok":True})
    res = await verify(_FakeVision(good), b"O","image/jpeg", b"E", CH)
    check("applied parsé [F,T,T]", res.applied == [False,True,True], str(res.applied))
    check("identity=True", res.identity_preserved is True)
    check("needs_refinement=False", res.needs_refinement is False)
    check("all_applied=False", res.all_applied is False)
    miss = missing_changes(res, CH)
    check("missing = [move]", len(miss)==1 and miss[0].type=="move")

    naturalness_ko = json.dumps({"applied":[True,True,True],"identity_preserved":True,"naturalness_ok":False})
    res2 = await verify(_FakeVision(naturalness_ko), b"O","image/jpeg", b"E", CH)
    check("naturalness_ok=false → needs_refinement=True", res2.needs_refinement is True)

    print("\n=== FAIL-OPEN (vision KO / longueur) ===")
    res3 = await verify(_FakeVision("not json"), b"O","image/jpeg", b"E", CH)
    check("JSON invalide → tout appliqué (fail-open)", res3.applied == [True,True,True])
    short = json.dumps({"applied":[False],"identity_preserved":True,"naturalness_ok":True})
    res4 = await verify(_FakeVision(short), b"O","image/jpeg", b"E", CH)
    check("applied trop court → padding True", res4.applied == [False,True,True], str(res4.applied))

    print("\n=== BUILD_REPORT (P3 : rien si complet) ===")
    rep_none = build_report(VerifyResult(applied=[True,True,True], identity_preserved=True, needs_refinement=False), CH)
    check("tout appliqué → report=None (image seule)", rep_none is None)
    rep = build_report(VerifyResult(applied=[False,True,True], identity_preserved=True, needs_refinement=False), CH)
    check("incomplet → 'Applied' + 'Still missing'", "Applied" in rep and "Still missing" in rep, rep)
    check("✓ sur appliqués, □ sur manquants", "✓ add flowers" in rep and "□ move the TV" in rep, rep)
    rep_nat = build_report(VerifyResult(applied=[True,True,True], identity_preserved=True, needs_refinement=True), CH)
    check("naturalness KO → message doux", rep_nat and "may need refinement" in rep_nat, rep_nat)

    print("\n--- exemple de rapport (incomplet) ---")
    print(build_report(VerifyResult(applied=[False,True,True], identity_preserved=True, needs_refinement=False), CH))
    print("---")

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(asyncio.run(main()))
