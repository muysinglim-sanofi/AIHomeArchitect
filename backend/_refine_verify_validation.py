"""Refine Engine V2 — validation Composant 5 (Verify) 3 ÉTATS, MOCK (no real vision).
Run: PYTHONPATH=. python _refine_verify_validation.py"""
import asyncio
import json
import sys

from refine.parser import Change
from refine.verify import (verify, build_report, missing_changes,
                           VerifyResult, VerifyStatus)

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
    print("=== VERIFY → INCOMPLETE (certains manquent) ===")
    good = json.dumps({"applied":[False,True,True],"identity_preserved":True,"naturalness_ok":True})
    res = await verify(_FakeVision(good), b"O","image/jpeg", b"E", CH)
    check("status = INCOMPLETE", res.status is VerifyStatus.INCOMPLETE, res.status)
    check("applied parsé [F,T,T]", res.applied == [False,True,True], str(res.applied))
    check("all_applied=False", res.all_applied is False)
    check("available=True", res.available is True)
    miss = missing_changes(res, CH)
    check("missing = [move]", len(miss)==1 and miss[0].type=="move")

    print("\n=== VERIFY → VERIFIED (tout appliqué) ===")
    allok = json.dumps({"applied":[True,True,True],"identity_preserved":True,"naturalness_ok":True})
    resv = await verify(_FakeVision(allok), b"O","image/jpeg", b"E", CH)
    check("status = VERIFIED", resv.status is VerifyStatus.VERIFIED, resv.status)
    check("all_applied=True", resv.all_applied is True)
    check("missing = [] en VERIFIED", missing_changes(resv, CH) == [])

    print("\n=== VERIFY → naturalness KO ===")
    nat_ko = json.dumps({"applied":[True,True,True],"identity_preserved":True,"naturalness_ok":False})
    res2 = await verify(_FakeVision(nat_ko), b"O","image/jpeg", b"E", CH)
    check("naturalness_ok=false → needs_refinement=True", res2.needs_refinement is True)
    check("status reste VERIFIED (changements OK)", res2.status is VerifyStatus.VERIFIED)

    print("\n=== VERIFY → VERIFICATION_UNAVAILABLE (jamais « tout appliqué ») ===")
    res3 = await verify(_FakeVision("not json"), b"O","image/jpeg", b"E", CH)
    check("JSON invalide → status UNAVAILABLE", res3.status is VerifyStatus.VERIFICATION_UNAVAILABLE, res3.status)
    check("all_applied=False (PAS de mensonge)", res3.all_applied is False)
    check("available=False", res3.available is False)
    check("applied vide", res3.applied == [])
    check("missing = [] (on ne SAIT pas)", missing_changes(res3, CH) == [])

    print("\n=== VERIFY → applied tronqué : non confirmé = MANQUANT (pas 'appliqué') ===")
    short = json.dumps({"applied":[False],"identity_preserved":True,"naturalness_ok":True})
    res4 = await verify(_FakeVision(short), b"O","image/jpeg", b"E", CH)
    check("padding = False (non confirmé → manquant)", res4.applied == [False,False,False], str(res4.applied))
    check("status = INCOMPLETE", res4.status is VerifyStatus.INCOMPLETE)

    print("\n=== BUILD_REPORT ===")
    rep_none = build_report(VerifyResult(status=VerifyStatus.VERIFIED, applied=[True,True,True]), CH)
    check("VERIFIED → report=None (image seule)", rep_none is None)
    rep = build_report(VerifyResult(status=VerifyStatus.INCOMPLETE, applied=[False,True,True]), CH)
    check("INCOMPLETE → 'Applied' + 'Still missing'", "Applied" in rep and "Still missing" in rep, rep)
    check("✓ sur appliqués, □ sur manquants", "✓ add flowers" in rep and "□ move the TV" in rep, rep)
    rep_unavail = build_report(VerifyResult(status=VerifyStatus.VERIFICATION_UNAVAILABLE), CH)
    check("UNAVAILABLE → message honnête", rep_unavail == "Ayden couldn't automatically verify this result.", rep_unavail)
    check("UNAVAILABLE ne dit JAMAIS 'Applied'", "Applied" not in (rep_unavail or ""))
    rep_nat = build_report(VerifyResult(status=VerifyStatus.VERIFIED, applied=[True,True,True], needs_refinement=True), CH)
    check("naturalness KO → message doux", rep_nat and "may need refinement" in rep_nat, rep_nat)

    print("\n--- exemples de rapport ---")
    print(build_report(VerifyResult(status=VerifyStatus.INCOMPLETE, applied=[False,True,True]), CH))
    print("···")
    print(build_report(VerifyResult(status=VerifyStatus.VERIFICATION_UNAVAILABLE), CH))
    print("---")

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(asyncio.run(main()))
