"""Phase 1 — Terminal STRICT (point 1). 0 réseau. Faux Supabase contrôlable.

Prouve : observe_intent_end / set_intent_result_ref ne renvoient True que si une ligne
a RÉELLEMENT transité, OU si un read-back confirme l'état cible. Un execute() sans
exception mais 0 ligne modifiée ⇒ False (pas de 'completed' fantôme)."""
import os, sys, asyncio, logging
from types import SimpleNamespace
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import billing, intent_observer

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(cond)
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")


class FQ:
    def __init__(self, s): self.s = s; self.f = {}; self.op = "s"; self.patch = None
    def select(self, *a, **k): self.op = "s"; return self
    def update(self, p): self.op = "u"; self.patch = p; return self
    def eq(self, c, v): self.f[c] = v; return self
    def neq(self, c, v): self.f["_neq_" + c] = v; return self
    def limit(self, n): return self
    def _match(self, r):
        for k, v in self.f.items():
            if k.startswith("_neq_"):
                if r.get(k[5:]) == v: return False
            elif r.get(k) != v:
                return False
        return True
    def execute(self):
        matched = [r for r in self.s.rows if self._match(r)]
        if self.op == "u":
            if self.s.apply:
                for r in matched: r.update(self.patch)
            return SimpleNamespace(data=(matched if self.s.urd else []))
        return SimpleNamespace(data=matched)


class Supa:
    def __init__(self, rows, urd=True, apply=True):
        self.rows = rows; self.urd = urd; self.apply = apply
    def table(self, name): return FQ(self)


async def main():
    async def _noop(**k): pass
    billing.apply_billing_for_intent_transition = _noop

    print("\n=== observe_intent_end(SUCCEEDED) STRICT ===")
    s1 = Supa([{"intent_id": "i", "status": "RUNNING"}], urd=True, apply=True)
    ok1 = await intent_observer.observe_intent_end("i", "SUCCEEDED", result_ref={"result_version_id": "v"}, supa=s1)
    check("A1 1 ligne modifiée → True", ok1 is True)

    s2 = Supa([{"intent_id": "i", "status": "RUNNING"}], urd=False, apply=True)  # représentation minimale
    ok2 = await intent_observer.observe_intent_end("i", "SUCCEEDED", result_ref={"result_version_id": "v"}, supa=s2)
    check("A2 0 ligne renvoyée mais read-back SUCCEEDED+result_ref → True", ok2 is True)

    s3 = Supa([{"intent_id": "i", "status": "RUNNING"}], urd=False, apply=False)  # rien n'a transité
    ok3 = await intent_observer.observe_intent_end("i", "SUCCEEDED", result_ref={"result_version_id": "v"}, supa=s3)
    check("A3 0 ligne ET read-back RUNNING → False (pas de completed fantôme)", ok3 is False)

    s4 = Supa([], urd=False, apply=False)   # intent inexistant
    ok4 = await intent_observer.observe_intent_end("absent", "SUCCEEDED", result_ref={"result_version_id": "v"}, supa=s4)
    check("A4 intent inexistant → False", ok4 is False)

    print("\n=== set_intent_result_ref STRICT ===")
    b1 = Supa([{"intent_id": "i", "status": "RUNNING"}], urd=True, apply=True)
    r1 = await intent_observer.set_intent_result_ref("i", {"result_version_id": "v"}, supa=b1)
    check("B1 1 ligne modifiée → True", r1 is True)

    b2 = Supa([{"intent_id": "i", "status": "RUNNING"}], urd=False, apply=True)
    r2 = await intent_observer.set_intent_result_ref("i", {"result_version_id": "v"}, supa=b2)
    check("B2 0 ligne mais read-back result_version_id match → True", r2 is True)

    b3 = Supa([{"intent_id": "i", "status": "RUNNING"}], urd=False, apply=False)
    r3 = await intent_observer.set_intent_result_ref("i", {"result_version_id": "v"}, supa=b3)
    check("B3 0 ligne ET read-back sans result_ref → False", r3 is False)

    total = len(res); passed = sum(res)
    print(f"\n{'='*60}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*60}")
    sys.exit(0 if passed == total else 1)


asyncio.run(main())
