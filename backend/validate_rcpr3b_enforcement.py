"""RC-PR3b regression (MIS À JOUR P0 2026-07-10) — reserve_decision pass-first ADDITIF.
Le rôle premium n'est PAS l'autorité de génération ; total = pass + free (planché) ;
jamais unlimited silencieux ; pass expiré = 0 fantôme. FilterSupa pass_id-aware.
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
def L(d, p=None, et="HOLD", key=None):
    r = {"user_id": "u1", "available_delta": d, "entry_type": et, "pass_id": p}
    if key: r["idempotency_key"] = key
    return r
def TR(): return L(3, None, "TRIAL", key="trial:u1")
def dec(fs, is_free, tier): return run(billing.reserve_decision(user_id="u1", is_free=is_free, tier=tier, supa=fs))

print("\n=== RC-PR3b (P0) · reserve_decision — enforcement pass mesuré ===")

fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [L(30, "pA", "GRANT"), L(-1, "pA"), TR(), L(-3, None)]})
d = dec(fs, False, "premium")
check("1 premium pass 29 (free 0) → allow total=29", d.allow and d.total_credits == 29 and d.pass_credits == 29, d)

fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [L(30, "pA", "GRANT"), L(-30, "pA"), TR(), L(-3, None)]})
d = dec(fs, False, "premium")
check("2 premium pass 0 + free 0 → DENY pass_exhausted", (not d.allow) and d.reason == "pass_exhausted", d)

fs = FilterSupa(tables={"ledger_entries": [TR(), L(-3, None)]})
d = dec(fs, False, "premium")
check("3 premium SANS pass SANS free → DENY no_active_pass (jamais unlimited)", (not d.allow) and d.reason == "no_active_pass", d)

fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [L(0, "pA")]})
d = dec(fs, False, "admin")
check("4 admin → bypass, 0 lookup pass/ledger", d.allow and d.bypass and fs.passes_queries == 0 and fs.ledger_queries == 0)

check("5 promo_unlimited → bypass", (lambda x: x.allow and x.bypass)(dec(FilterSupa(), False, "promo_unlimited")))
check("6 promo_limited → bypass", (lambda x: x.allow and x.bypass)(dec(FilterSupa(), False, "promo_limited")))

fs = FilterSupa(tables={"ledger_entries": [TR(), L(-1, None)]})
d = dec(fs, True, "free"); check("7 free 2 → allow total=2", d.allow and d.total_credits == 2)

fs = FilterSupa(tables={"ledger_entries": [TR(), L(-3, None)]})
d = dec(fs, True, "free"); check("8 free 0 → DENY insufficient_credits", (not d.allow) and d.reason == "insufficient_credits")

d = dec(FilterSupa(), True, "free"); check("9 free neuf → total=3 (trial projeté)", d.allow and d.total_credits == 3)

fs = FilterSupa(tables={"passes": [ep()], "ledger_entries": [L(60, "e1", "GRANT"), TR()]})
d = dec(fs, True, "free"); check("10 pass EXPIRÉ +60 + free 3 → total=3 (0 fantôme)", d.total_credits == 3)

# 11 pass-first indépendant du rôle : pass actif + tier=free (webhook rôle manqué) → allow
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [L(30, "pA", "GRANT"), TR(), L(-3, None)]})
d = dec(fs, True, "free")
check("11 pass actif SANS rôle (tier=free) → allow via pass (pass-first)", d.allow and d.pass_credits == 30 and d.has_active_pass)

# 12 fail-open : lecture free KO → allow
class _Boom(FilterSupa):
    def table(self, name):
        if name == "ledger_entries":
            class _B:
                def select(s, *a, **k): return s
                def eq(s, *a, **k): return s
                def is_(s, *a, **k): return s
                def execute(s): raise RuntimeError("db down")
            return _B()
        return super().table(name)
d = dec(_Boom(), True, "free"); check("12 lecture free KO → FAIL-OPEN allow", d.allow)

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  RC-PR3b (P0) — TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
