"""RC-PR3a regression (MIS À JOUR P0 2026-07-10) — apply_billing PASS-FIRST STABLE.
Débit du pass mesuré (HOLD/COMMIT/RELEASE scoppés, même bucket sur tout le cycle) ;
bypass (admin/promo) = 0 écriture ; free = TRIAL + HOLD bucket free ; idempotent.
FilterSupa pass_id-aware (idempotence ledger + reproject additif modélisés).
"""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__)); logging.disable(logging.CRITICAL)
import billing
from _billing_fakes import FilterSupa

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"; res = []
def check(l, c, d=""):
    res.append(bool(c)); print(f"  {PASS if c else FAIL}  {l}{('  ['+str(d)+']') if d and not c else ''}")
def run(c): return asyncio.run(c)

FUT = "2099-01-01T00:00:00+00:00"; PS = "2020-01-01T00:00:00+00:00"
def ap(pid="pA"): return {"id": pid, "user_id": "u1", "status": "ACTIVE", "starts_at": PS, "ends_at": FUT}
def L(d, p=None, et="GRANT", key=None):
    r = {"user_id": "u1", "available_delta": d, "entry_type": et, "pass_id": p}
    if key: r["idempotency_key"] = key
    return r
def apply(fs, status, is_free, tier=None):
    run(billing.apply_billing_for_intent_transition(
        intent_id="i1", new_status=status, user_id="u1", is_free=is_free, tier=tier, supa=fs))
def by(fs, k): return fs.ledger_by_key(k)

print("\n=== RC-PR3a (P0) · apply_billing — débit pass-first stable ===")

# 1 pass actif + RUNNING → HOLD(-1) pass + reproject
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [L(30, "pA")]})
apply(fs, "RUNNING", is_free=False, tier="premium")
h = by(fs, "hold:i1")
check("1 pass actif + RUNNING → HOLD(-1) pass_id=pA + reproject",
      len(h) == 1 and h[0]["entry_type"] == "HOLD" and h[0]["available_delta"] == -1
      and h[0]["pass_id"] == "pA" and any(c[0] == "billing_reproject_wallet" for c in fs.rpc_calls), h)

# 2 cycle complet RUNNING→SUCCEEDED → net -1 (HOLD-1 + COMMIT 0), même bucket
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [L(30, "pA")]})
apply(fs, "RUNNING", is_free=False, tier="premium"); apply(fs, "SUCCEEDED", is_free=False, tier="premium")
c = by(fs, "commit:i1")
check("2 SUCCEEDED → COMMIT(0) pass_id=pA (net -1 sur le pass)",
      len(c) == 1 and c[0]["entry_type"] == "COMMIT" and c[0]["available_delta"] == 0 and c[0]["pass_id"] == "pA", c)

# 3 cycle RUNNING→FAILED → net 0 (HOLD-1 + RELEASE+1), même bucket
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [L(30, "pA")]})
apply(fs, "RUNNING", is_free=False, tier="premium"); apply(fs, "FAILED", is_free=False, tier="premium")
r = by(fs, "release:i1")
check("3 FAILED → RELEASE(+1) pass_id=pA (net 0)",
      len(r) == 1 and r[0]["entry_type"] == "RELEASE" and r[0]["available_delta"] == 1 and r[0]["pass_id"] == "pA", r)

# 4 bypass (admin) sans pass → 0 écriture, 0 reproject
fs = FilterSupa()
apply(fs, "RUNNING", is_free=False, tier="admin")
check("4 admin (bypass) sans pass → 0 écriture", fs.tables.get("ledger_entries", []) == [] and not fs.rpc_calls)

# 4b terminal SANS HOLD (bypass) → COMMIT/RELEASE no-op (auto-correction via hold lookup)
fs = FilterSupa()
apply(fs, "SUCCEEDED", is_free=False, tier="admin")
check("4b terminal sans HOLD → COMMIT no-op", by(fs, "commit:i1") == [])

# 5 free + RUNNING → TRIAL + HOLD bucket free (pass_id absent), pas de pass utilisé
fs = FilterSupa()
apply(fs, "RUNNING", is_free=True, tier="free")
tr = by(fs, "trial:u1"); h = by(fs, "hold:i1")
check("5 free + RUNNING → TRIAL + HOLD sans pass_id",
      len(tr) == 1 and tr[0]["entry_type"] == "TRIAL" and h[0].get("pass_id") is None, (tr, h))

# 6 idempotence : RUNNING rejoué → 1 seul HOLD (clé hold:i1)
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [L(30, "pA")]})
apply(fs, "RUNNING", is_free=False, tier="premium"); apply(fs, "RUNNING", is_free=False, tier="premium")
check("6 HOLD idempotent hold:i1 (rejeu → 1 seul)", len(by(fs, "hold:i1")) == 1)

# 7 refine billing-OFF (tier=None, is_free=False) → 0 écriture (compat préservée)
fs = FilterSupa()
apply(fs, "RUNNING", is_free=False, tier=None)
check("7 refine billing-OFF (tier=None, entitled) → 0 écriture", fs.tables.get("ledger_entries", []) == [])

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  RC-PR3a (P0) — TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
