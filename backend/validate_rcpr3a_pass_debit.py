"""RC-PR3a (2026-07-09) — un pass ACTIF se décrémente à chaque génération/refine
réussie ; admin/promo/sans-pass ne débitent pas ; le free tier reste inchangé.

Pur (FakeSupa, 0 DB/0 réseau). Vérifie la couche Python d'apply_billing :
  • is_free=False + pass actif → HOLD/COMMIT/RELEASE scoppés au pass_id + reproject
  • is_free=False + PAS de pass → aucune écriture (admin/promo/premium-sans-pass)
  • is_free=True → chemin free inchangé (TRIAL + HOLD, pass_id=None)
La sémantique net (−1 succès / 0 échec) et la projection réelle par pass = E2E DB.
"""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import billing

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(bool(cond))
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")


class _Res:
    def __init__(self, data): self.data = data


class _Query:
    def __init__(self, fake, table): self._f = fake; self._t = table; self._row = None
    def select(self, *a, **k): return self
    def eq(self, *a, **k): return self
    def lte(self, *a, **k): return self
    def gt(self, *a, **k): return self
    def order(self, *a, **k): return self
    def limit(self, *a, **k): return self
    def upsert(self, row, **k): self._row = row; return self
    def execute(self):
        if self._t == "passes":
            self._f.passes_queries += 1
            return _Res(self._f.pass_rows)
        if self._t == "ledger_entries":
            self._f.ledger_inserts.append(self._row)
            return _Res([{"id": len(self._f.ledger_inserts)}])  # simulate NEW row
        if self._t == "generation_intents":
            return _Res([{"user_id": self._f.user_id}])
        return _Res([])


class FakeSupa:
    def __init__(self, pass_rows=None, user_id="u1"):
        self.pass_rows = [] if pass_rows is None else pass_rows
        self.user_id = user_id
        self.ledger_inserts = []
        self.rpc_calls = []
        self.passes_queries = 0
    def table(self, name): return _Query(self, name)
    def rpc(self, name, params):
        self.rpc_calls.append((name, params))
        return _Res(None)


def run(coro): return asyncio.run(coro)

def _apply(fs, status, is_free):
    run(billing.apply_billing_for_intent_transition(
        intent_id="i1", new_status=status, user_id="u1", is_free=is_free, supa=fs))

def _by_key(fs, key):
    return [r for r in fs.ledger_inserts if r.get("idempotency_key") == key]


print("\n=== RC-PR3a · apply_billing (débit du pass mesuré) ===")

# 1. pass actif + RUNNING → HOLD(-1) scoppé au pass_id + reproject
fs = FakeSupa(pass_rows=[{"id": "pass-A"}])
_apply(fs, "RUNNING", is_free=False)
hold = _by_key(fs, "hold:i1")
ok = (len(hold) == 1 and hold[0]["entry_type"] == "HOLD"
      and hold[0]["available_delta"] == -1 and hold[0].get("pass_id") == "pass-A"
      and any(c[0] == "billing_reproject_wallet" for c in fs.rpc_calls))
check("1 pass actif + RUNNING → HOLD(-1) pass_id=pass-A + reproject", ok, fs.ledger_inserts)

# 2. pass actif + SUCCEEDED → COMMIT(0) scoppé au pass (net -1 avec le HOLD)
fs = FakeSupa(pass_rows=[{"id": "pass-A"}])
_apply(fs, "SUCCEEDED", is_free=False)
commit = _by_key(fs, "commit:i1")
check("2 pass actif + SUCCEEDED → COMMIT(0) pass_id=pass-A",
      len(commit) == 1 and commit[0]["entry_type"] == "COMMIT"
      and commit[0]["available_delta"] == 0 and commit[0].get("pass_id") == "pass-A", fs.ledger_inserts)

# 3. pass actif + FAILED → RELEASE(+1) scoppé au pass (net 0 avec le HOLD)
fs = FakeSupa(pass_rows=[{"id": "pass-A"}])
_apply(fs, "FAILED", is_free=False)
rel = _by_key(fs, "release:i1")
check("3 pass actif + FAILED → RELEASE(+1) pass_id=pass-A",
      len(rel) == 1 and rel[0]["entry_type"] == "RELEASE"
      and rel[0]["available_delta"] == 1 and rel[0].get("pass_id") == "pass-A", fs.ledger_inserts)

# 4. is_free=False + AUCUN pass → skip total (admin/promo/premium-sans-pass)
fs = FakeSupa(pass_rows=[])
_apply(fs, "RUNNING", is_free=False)
check("4 entitled sans pass actif → 0 écriture, 0 reproject",
      fs.ledger_inserts == [] and not fs.rpc_calls, (fs.ledger_inserts, fs.rpc_calls))

# 5. is_free=True + RUNNING → chemin free INCHANGÉ : TRIAL + HOLD, aucun pass_id
fs = FakeSupa(pass_rows=[{"id": "pass-A"}])  # même si un pass existe, le free ne le lit pas
_apply(fs, "RUNNING", is_free=True)
trial = _by_key(fs, "trial:u1")
hold = _by_key(fs, "hold:i1")
ok = (len(trial) == 1 and trial[0]["entry_type"] == "TRIAL" and "pass_id" not in trial[0]
      and len(hold) == 1 and hold[0]["entry_type"] == "HOLD" and "pass_id" not in hold[0]
      and fs.passes_queries == 0)  # le chemin free ne fait PAS de lookup pass
check("5 free + RUNNING → TRIAL + HOLD sans pass_id, aucun lookup pass", ok,
      (fs.ledger_inserts, fs.passes_queries))

# 6. idempotence : même clé rejouée → _ledger_insert ON CONFLICT (on vérifie juste que
#    la clé est déterministe hold:<intent_id>, pas d'aléa)
fs = FakeSupa(pass_rows=[{"id": "pass-A"}])
_apply(fs, "RUNNING", is_free=False)
check("6 clé de débit déterministe = hold:i1 (idempotent côté DB)",
      fs.ledger_inserts and fs.ledger_inserts[0]["idempotency_key"] == "hold:i1")

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
