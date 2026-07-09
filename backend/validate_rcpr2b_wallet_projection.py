"""RC-PR2b (2026-07-09) — la projection wallet est désormais PASS-AWARE et
centralisée dans le RPC SQL `billing_reproject_wallet` (bucket du pass actif,
sinon bucket free planchérisé à 0). Ce test verrouille la couche Python :

  • billing._reproject_wallet DÉLÈGUE au RPC (ne somme plus le ledger en Python) ;
  • il n'accède plus DIRECTEMENT à la table ledger_entries/wallets ;
  • il reste best-effort (une erreur RPC ne remonte jamais → /generate protégé).

La RÈGLE de projection (pass-scope + free floor 0) vit en SQL → vérifiée en E2E
sur la DB réelle (user 1ba1c0f9 : 29 → 60), pas ici.
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


class _R:
    def __init__(self, data=None, exc=None): self._data, self._exc = data, exc
    def execute(self):
        if self._exc: raise self._exc
        return type("X", (), {"data": self._data})()


class FakeSupa:
    def __init__(self, rpc_exc=None):
        self.rpc_calls = []; self.table_calls = []; self._rpc_exc = rpc_exc
    def rpc(self, name, params):
        self.rpc_calls.append((name, params))
        return _R(exc=self._rpc_exc)
    def table(self, name):
        self.table_calls.append(name)
        raise AssertionError("_reproject_wallet ne doit PLUS toucher table() directement")


def run(coro): return asyncio.run(coro)

print("\n=== RC-PR2b · billing._reproject_wallet (délégation SQL) ===")

# 1. délègue au RPC pass-aware avec le bon param, sans toucher les tables
fs = FakeSupa()
run(billing._reproject_wallet(user_id="u1", supa=fs))
check("1 appelle billing_reproject_wallet(p_user_id) et RIEN d'autre",
      fs.rpc_calls == [("billing_reproject_wallet", {"p_user_id": "u1"})] and not fs.table_calls,
      (fs.rpc_calls, fs.table_calls))

# 2. best-effort : une erreur RPC ne remonte jamais (chemin conso fail-open)
fs2 = FakeSupa(rpc_exc=RuntimeError("db down"))
raised = False
try:
    run(billing._reproject_wallet(user_id="u1", supa=fs2))
except Exception:
    raised = True
check("2 erreur RPC swallowed (pas de raise → /generate protégé)", not raised)

# 3. grant_trial reprojette aussi via le même RPC (après le TRIAL)
class _LedgerOK(FakeSupa):
    def table(self, name):
        self.table_calls.append(name)
        class _T:
            def upsert(_s, *a, **k): return _s
            def execute(_s): return type("X", (), {"data": [{"id": 1}]})()  # nouvelle ligne
        return _T()
fs3 = _LedgerOK()
run(billing.grant_trial(user_id="u1", supa=fs3))
check("3 grant_trial → TRIAL inséré puis reproject via RPC pass-aware",
      ("ledger_entries" in fs3.table_calls)
      and fs3.rpc_calls == [("billing_reproject_wallet", {"p_user_id": "u1"})],
      (fs3.table_calls, fs3.rpc_calls))

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
