"""P0a-bis — logique de billing.try_hold (réservation atomique) via FakeSupa miroir.
Prouve : drain → min(N, bucket) granted, pass-first, deny+reason, trial matérialisé,
idempotence hold:<intent>, bypass. L'ATOMICITÉ RÉELLE (advisory lock sous concurrence
HTTP) = e2e_p0_atomic_hold.py, à tourner APRÈS apply de la migration 20260710_p0a.
"""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__)); logging.disable(logging.CRITICAL)
import billing
from _billing_fakes import FilterSupa

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"; res = []
def check(l, c, d=""):
    res.append(bool(c)); print(f"  {PASS if c else FAIL}  {l}{('  ['+str(d)+']') if d and not c else ''}")
def run(c): return asyncio.run(c)

FUT = "2099-01-01T00:00:00+00:00"; PS = "2020-01-01T00:00:00+00:00"; PE = "2020-01-02T00:00:00+00:00"
def ap(pid="pA"): return {"id": pid, "user_id": "u1", "status": "ACTIVE", "starts_at": PS, "ends_at": FUT}
def ep(pid="e1"): return {"id": pid, "user_id": "u1", "status": "EXPIRED", "starts_at": PS, "ends_at": PE}
def G(d, p): return {"user_id": "u1", "available_delta": d, "entry_type": "GRANT", "pass_id": p,
                     "idempotency_key": f"grant:{p}"}
def hold(fs, intent, tier="premium"):
    return run(billing.try_hold(user_id="u1", intent_id=intent, tier=tier, supa=fs))

print("\n=== P0a-bis · try_hold (réservation atomique — logique) ===")

# 1 DRAIN pass : bucket=5 → 5 granted d'intents distincts, 6e deny
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [G(5, "pA")]})
gr = [hold(fs, f"i{i}") for i in range(6)]
n_granted = sum(1 for g in gr if g["granted"])
check("1 pass=5, 6 intents distincts → 5 granted, 6e deny pass_exhausted",
      n_granted == 5 and not gr[5]["granted"] and gr[5]["reason"] == "pass_exhausted", n_granted)

# 2 INVARIANT concurrence (séquentiel = advisory-lock) : bucket=20, N=60 → exactement 20
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [G(20, "pA")]})
gr = [hold(fs, f"c{i}") for i in range(60)]
n_granted = sum(1 for g in gr if g["granted"])
final = sum(int(r["available_delta"]) for r in fs.tables["ledger_entries"] if r.get("pass_id") == "pA")
check("2 bucket=20, 60 tentatives → exactement 20 granted, 40 deny, solde final 0",
      n_granted == 20 and final == 0, (n_granted, final))

# 3 DRAIN free (new user) : trial matérialisé → 3 granted, 4e deny
fs = FilterSupa()
gr = [hold(fs, f"f{i}", tier="free") for i in range(4)]
n_granted = sum(1 for g in gr if g["granted"])
trial_rows = [r for r in fs.tables.get("ledger_entries", []) if r.get("entry_type") == "TRIAL"]
check("3 free new user → trial(+3) matérialisé, 3 granted, 4e deny insufficient_credits",
      n_granted == 3 and len(trial_rows) == 1 and gr[3]["reason"] == "insufficient_credits", (n_granted, len(trial_rows)))

# 4 PASS-FIRST puis FREE : pass=1 + free=2 → 3 granted (1 pass + 2 free), 4e deny
fs = FilterSupa(tables={"passes": [ap()],
                        "ledger_entries": [G(1, "pA"),
                                           {"user_id": "u1", "entry_type": "TRIAL", "available_delta": 3,
                                            "pass_id": None, "idempotency_key": "trial:u1"},
                                           {"user_id": "u1", "entry_type": "HOLD", "available_delta": -1,
                                            "pass_id": None, "idempotency_key": "seed"}]})  # free=2
g1 = hold(fs, "p1"); g2 = hold(fs, "p2"); g3 = hold(fs, "p3"); g4 = hold(fs, "p4")
buckets = [g1.get("bucket"), g2.get("bucket"), g3.get("bucket")]
check("4 pass=1 + free=2 → 1er=pass, 2e/3e=free, 4e deny",
      g1["granted"] and g2["granted"] and g3["granted"] and not g4["granted"]
      and buckets[0] == "pass" and buckets[1] == "free" and buckets[2] == "free", (buckets, g4))

# 5 IDEMPOTENCE : même intent 10× → 1 seul HOLD, tous granted
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [G(30, "pA")]})
gs = [hold(fs, "same") for _ in range(10)]
holds = [r for r in fs.tables["ledger_entries"] if r.get("idempotency_key") == "hold:same"]
check("5 même intent ×10 → 1 seul HOLD, tous granted",
      all(g["granted"] for g in gs) and len(holds) == 1, len(holds))

# 6 BYPASS admin → granted, AUCUN HOLD
fs = FilterSupa()
g = hold(fs, "adm", tier="admin")
check("6 admin → granted bypass, 0 HOLD", g["granted"] and g["reason"] == "bypass"
      and not fs.tables.get("ledger_entries"))

# 7 pass EXPIRÉ + free 0 (premium) → deny no_active_pass (0 fantôme)
fs = FilterSupa(tables={"passes": [ep()], "ledger_entries": [G(30, "e1")]})
g = hold(fs, "x", tier="premium")
check("7 pass expiré +30 + free 0 → deny no_active_pass (pas de HOLD)",
      not g["granted"] and g["reason"] == "no_active_pass"
      and not any(r.get("entry_type") == "HOLD" for r in fs.tables["ledger_entries"]))

# 8 erreur DB TRANSITOIRE → FAIL-OPEN granted (fiabilité)
class _Boom(FilterSupa):
    def rpc(self, name, params): raise RuntimeError("db down / connection reset")
g = run(billing.try_hold(user_id="u1", intent_id="z", tier="premium", supa=_Boom()))
check("8 erreur DB transitoire → FAIL-OPEN granted", g["granted"] and g["reason"] == "fail_open")

# 9 RPC ABSENTE (PGRST202, SQL pas appliqué) → FAIL-CLOSED (jamais de gen sans HOLD atomique)
class _Missing(FilterSupa):
    def rpc(self, name, params):
        class _C:
            def execute(self):
                raise RuntimeError("PGRST202: Could not find the function public.billing_try_hold in the schema cache")
        return _C()
g = run(billing.try_hold(user_id="u1", intent_id="z2", tier="premium", supa=_Missing()))
check("9 RPC absente (PGRST202) → FAIL-CLOSED granted=false reason=atomic_hold_missing",
      (not g["granted"]) and g["reason"] == "atomic_hold_missing", g)

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  P0a-bis try_hold — TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
