"""P0 Billing Integrity — master suite FakeSupa (logique pure, 0 DB/0 réseau).
Couvre A/B/C/E de docs/P0_BILLING_INTEGRITY_TEST_MATRIX.md :
  • reserve_decision : pass-first ADDITIF, free planché, pass expiré = 0 fantôme.
  • apply_billing    : pass-first STABLE (HOLD/COMMIT/RELEASE même bucket), idempotent.
Le SQL/RPC (reproject additif, grant) + les enchaînements réels = E2E DB.
"""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import billing
from _billing_fakes import FilterSupa

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(bool(cond))
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")
def run(c): return asyncio.run(c)

FUT = "2099-01-01T00:00:00+00:00"
PAST_S = "2020-01-01T00:00:00+00:00"
PAST_E = "2020-01-02T00:00:00+00:00"

def act_pass(pid="pass-A", uid="u1"):
    return {"id": pid, "user_id": uid, "status": "ACTIVE", "starts_at": PAST_S, "ends_at": FUT}
def exp_pass(pid, uid="u1"):
    return {"id": pid, "user_id": uid, "status": "EXPIRED", "starts_at": PAST_S, "ends_at": PAST_E}
def L(delta, pass_id=None, et="HOLD", uid="u1", key=None):
    r = {"user_id": uid, "available_delta": delta, "entry_type": et, "pass_id": pass_id}
    if key: r["idempotency_key"] = key
    return r
def TRIAL(uid="u1"): return L(3, None, "TRIAL", uid, key=f"trial:{uid}")

def decide(fs, *, is_free, tier):
    return run(billing.reserve_decision(user_id="u1", is_free=is_free, tier=tier, supa=fs))
def apply(fs, status, is_free, tier=None):
    run(billing.apply_billing_for_intent_transition(
        intent_id="i1", new_status=status, user_id="u1", is_free=is_free, tier=tier, supa=fs))


print("\n=== P0 · A — Source unique (reserve_decision pass-first additif) ===")

# A1 — déterminisme + reason ∈ ensemble fermé (les 3 gates appellent CETTE fonction)
fs = FilterSupa(tables={"ledger_entries": [TRIAL(), L(-1, None)]})
d1 = decide(fs, is_free=True, tier="free"); d2 = decide(fs, is_free=True, tier="free")
check("A1 3 gates = même fonction : décision déterministe + reason valide",
      d1.allow == d2.allow and d1.total_credits == d2.total_credits
      and d1.reason in ("", "bypass", "insufficient_credits", "pass_exhausted", "no_active_pass"), (d1, d2))

# A2 — additif : pass 5 + free 2 = 7
fs = FilterSupa(tables={"passes": [act_pass()],
                        "ledger_entries": [L(5, "pass-A", "GRANT"), TRIAL(), L(-1, None)]})
d = decide(fs, is_free=False, tier="premium")
check("A2 additif pass=5 + free=2 → total=7", d.total_credits == 7 and d.pass_credits == 5 and d.free_credits == 2, d)

# A3 — free planché à 0 (dette free n'est jamais négative)
fs = FilterSupa(tables={"ledger_entries": [TRIAL()] + [L(-1, None) for _ in range(7)]})  # 3-7=-4
d = decide(fs, is_free=True, tier="free")
check("A3 free net=-4 → free_credits=0 (planché)", d.free_credits == 0 and d.total_credits == 0)

# A4 — 2 passes EXPIRÉS (GRANT +60,+30) + free +3 → total=3 (PAS 93, fin des fantômes)
fs = FilterSupa(tables={"passes": [exp_pass("exp1"), exp_pass("exp2")],
                        "ledger_entries": [L(60, "exp1", "GRANT"), L(30, "exp2", "GRANT"), TRIAL()]})
d = decide(fs, is_free=True, tier="free")
check("A4 passes expirés +60/+30 + free 3 → total=3 (pas 93)", d.total_credits == 3 and d.pass_credits == 0, d)

# A5 — pass actif contribue : bucket 30, free épuisé (trial déjà consommé) → 30
fs = FilterSupa(tables={"passes": [act_pass()],
                        "ledger_entries": [L(30, "pass-A", "GRANT"), TRIAL(), L(-3, None)]})
d = decide(fs, is_free=False, tier="premium")
check("A5 pass actif 30 + free 0 → total=30 + has_active_pass",
      d.total_credits == 30 and d.has_active_pass and d.free_credits == 0, d)

# A7 — aucun crédit fantôme : chemin free exclut les GRANTs des passes (pass_id renseigné)
fs = FilterSupa(tables={"passes": [exp_pass("exp1")],
                        "ledger_entries": [L(30, "exp1", "GRANT"), TRIAL()]})
d = decide(fs, is_free=True, tier="free")
check("A7 free path exclut GRANT du pass expiré → total=3", d.total_credits == 3)


print("\n=== P0 · B — Free quota (ledger, pass_id IS NULL) ===")

# B1 — new user (ledger vide) → 3 (trial projeté)
fs = FilterSupa()
d = decide(fs, is_free=True, tier="free")
check("B1 new user → total=3 (TRIAL projeté)", d.total_credits == 3 and d.free_credits == 3)

# B5 — free épuisé → deny insufficient_credits
fs = FilterSupa(tables={"ledger_entries": [TRIAL(), L(-3, None)]})
d = decide(fs, is_free=True, tier="free")
check("B5 free 0 → DENY insufficient_credits", (not d.allow) and d.reason == "insufficient_credits")

# B8 — HOLD idempotent (même intent rejoué → 1 seul HOLD)
fs = FilterSupa(tables={"ledger_entries": [TRIAL()]})
apply(fs, "RUNNING", is_free=True, tier="free"); apply(fs, "RUNNING", is_free=True, tier="free")
check("B8 HOLD idempotent hold:i1 (rejeu → 1 seul)", len(fs.ledger_by_key("hold:i1")) == 1)

# B11 — free bucket = pass_id NULL seul (un GRANT de pass n'entre pas dans le free)
fs = FilterSupa(tables={"passes": [act_pass()],
                        "ledger_entries": [L(30, "pass-A", "GRANT"), TRIAL()]})
# is_free=True force le contexte "affichage free" ; free_credits ne doit voir que le +3
d = decide(fs, is_free=False, tier="premium")
check("B11 free_credits ne compte que pass_id IS NULL (=3, pas 33)", d.free_credits == 3)


print("\n=== P0 · C — Pass weekly/annual (pass-first) ===")

# C5 — pass actif 30 + free 2 → 32
fs = FilterSupa(tables={"passes": [act_pass()],
                        "ledger_entries": [L(30, "pass-A", "GRANT"), TRIAL(), L(-1, None)]})
d = decide(fs, is_free=False, tier="premium")
check("C5 pass 30 + free 2 → total=32", d.total_credits == 32)

# C6 — débit PASS-FIRST : RUNNING+SUCCEEDED → HOLD/COMMIT sur le pass, free intact
fs = FilterSupa(tables={"passes": [act_pass()],
                        "ledger_entries": [L(30, "pass-A", "GRANT"), TRIAL()]})
apply(fs, "RUNNING", is_free=False, tier="premium"); apply(fs, "SUCCEEDED", is_free=False, tier="premium")
hold = fs.ledger_by_key("hold:i1"); commit = fs.ledger_by_key("commit:i1")
free_after = decide(fs, is_free=False, tier="premium").free_credits
check("C6 pass-first : HOLD+COMMIT sur pass-A, free intact",
      len(hold) == 1 and hold[0]["pass_id"] == "pass-A"
      and len(commit) == 1 and commit[0]["pass_id"] == "pass-A" and free_after == 3, (hold, commit, free_after))

# C6b — bucket STABLE : HOLD pass puis FAILED → RELEASE sur le MÊME pass
fs = FilterSupa(tables={"passes": [act_pass()], "ledger_entries": [L(30, "pass-A", "GRANT")]})
apply(fs, "RUNNING", is_free=False, tier="premium"); apply(fs, "FAILED", is_free=False, tier="premium")
rel = fs.ledger_by_key("release:i1")
check("C6b HOLD pass → RELEASE pass (bucket stable, jamais free)",
      len(rel) == 1 and rel[0]["pass_id"] == "pass-A")

# C7 — pass ACTIF épuisé (0) + free 2 → allow total=2, débit sur le FREE (pass-first puis free)
fs = FilterSupa(tables={"passes": [act_pass()],
                        "ledger_entries": [L(30, "pass-A", "GRANT"), L(-30, "pass-A"), TRIAL(), L(-1, None)]})
d = decide(fs, is_free=False, tier="premium")
apply(fs, "RUNNING", is_free=False, tier="premium")
hold = fs.ledger_by_key("hold:i1")
check("C7 pass 0 + free 2 → allow total=2, HOLD sur FREE (pass_id None)",
      d.allow and d.total_credits == 2 and len(hold) == 1 and hold[0].get("pass_id") is None, (d, hold))

# C8 — pass EXPIRÉ + free 2 → total=2
fs = FilterSupa(tables={"passes": [exp_pass("exp1")],
                        "ledger_entries": [L(30, "exp1", "GRANT"), TRIAL(), L(-1, None)]})
d = decide(fs, is_free=True, tier="free")
check("C8 pass expiré + free 2 → total=2", d.total_credits == 2)

# C9 — pass EXPIRÉ + free 0 → deny
fs = FilterSupa(tables={"passes": [exp_pass("exp1")],
                        "ledger_entries": [L(30, "exp1", "GRANT"), TRIAL(), L(-3, None)]})
d = decide(fs, is_free=True, tier="free")
check("C9 pass expiré + free 0 → DENY", (not d.allow) and d.total_credits == 0)

# C10 — pass EXPIRÉ GRANT+30, free 0 → total 0 (jamais +30 fantôme)
fs = FilterSupa(tables={"passes": [exp_pass("exp1")],
                        "ledger_entries": [L(30, "exp1", "GRANT")]})
d = decide(fs, is_free=False, tier="premium")
check("C10 pass expiré +30 + free 0 → total=0 (no fantôme)", d.total_credits == 0)

# C11 — 2 passes expirés ne polluent pas le free
fs = FilterSupa(tables={"passes": [exp_pass("exp1"), exp_pass("exp2")],
                        "ledger_entries": [L(60, "exp1", "GRANT"), L(30, "exp2", "GRANT"), TRIAL()]})
d = decide(fs, is_free=True, tier="free")
check("C11 2 passes expirés + free 3 → free_credits=3", d.free_credits == 3 and d.total_credits == 3)

# C12 — reproject appelé après HOLD
fs = FilterSupa(tables={"passes": [act_pass()], "ledger_entries": [L(30, "pass-A", "GRANT")]})
apply(fs, "RUNNING", is_free=False, tier="premium")
check("C12 reproject (billing_reproject_wallet) appelé après HOLD",
      any(c[0] == "billing_reproject_wallet" for c in fs.rpc_calls))


print("\n=== P0 · E — Rôle premium / pass ===")

# E1 — rôle seul sans pass ni free → deny, JAMAIS bypass
fs = FilterSupa(tables={"ledger_entries": [TRIAL(), L(-3, None)]})  # free 0, aucun pass
d = decide(fs, is_free=False, tier="premium")
check("E1 rôle premium sans pass sans free → DENY no_active_pass (jamais unlimited)",
      (not d.allow) and d.reason == "no_active_pass" and not d.bypass, d)

# E3 — pass SANS rôle (tier=free) + pass actif → allow via pass (pass-first, indépendant du rôle)
fs = FilterSupa(tables={"passes": [act_pass()],
                        "ledger_entries": [L(30, "pass-A", "GRANT"), TRIAL(), L(-3, None)]})  # free 0
d = decide(fs, is_free=True, tier="free")   # tier=free (webhook rôle manqué) mais pass actif
check("E3 pass actif SANS rôle (tier=free) → allow via pass (pass-first)",
      d.allow and d.pass_credits == 30 and d.has_active_pass, d)

# E5 — promo_unlimited → bypass
fs = FilterSupa()
d = decide(fs, is_free=False, tier="promo_unlimited")
check("E5 promo_unlimited → bypass allow", d.allow and d.bypass and d.reason == "bypass")

# E6 — admin → bypass, AUCUN lookup pass/ledger
fs = FilterSupa(tables={"passes": [act_pass()], "ledger_entries": [L(0, "pass-A")]})
d = decide(fs, is_free=False, tier="admin")
check("E6 admin → bypass, 0 lookup", d.allow and d.bypass and fs.passes_queries == 0 and fs.ledger_queries == 0)

# E5b — promo_limited → bypass (borné par le resolver)
fs = FilterSupa()
d = decide(fs, is_free=False, tier="promo_limited")
check("E5b promo_limited → bypass allow", d.allow and d.bypass)

# fail-open : lecture free KO → allow
class _Boom(FilterSupa):
    def table(self, name):
        if name == "ledger_entries":
            class _B:
                def select(s,*a,**k): return s
                def eq(s,*a,**k): return s
                def is_(s,*a,**k): return s
                def execute(s): raise RuntimeError("db down")
            return _B()
        return super().table(name)
fs = _Boom()
d = decide(fs, is_free=True, tier="free")
check("FAIL-OPEN : lecture free KO → allow (fiabilité > double rare)", d.allow)

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  P0 MASTER — TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
