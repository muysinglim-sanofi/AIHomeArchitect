"""BUG 2 (Sign out anti-abus) — validation OFFLINE du marqueur TRIAL delta 0.

Prouve, sans DB, via FilterSupa (idempotence ledger + billing_try_hold fidèle) :
  1. anon frais → Free 3 (comportement inchangé) ;
  2. mark_trial_consumed → écrit UNE ligne TRIAL(delta 0, trial:<uid>, PROMO/post_signout), idempotent ;
  3. après marqueur → Free 0 ;
  4. après marqueur → /generate (billing_try_hold) DENY avant OpenAI, aucun HOLD, aucun +3 ;
  5. contrôle : un vrai anon frais (sans marqueur) reçoit toujours son +3 puis Free 2.

Non auto-régressant : n'écrit rien de réel. Lancer : python _signout_trial_marker_validation.py
"""
import asyncio
import io
import sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

import billing  # noqa: E402
from _billing_fakes import FilterSupa  # noqa: E402

_passed = _failed = 0


def check(name, cond, detail=""):
    global _passed, _failed
    ok = bool(cond)
    _passed += ok
    _failed += (not ok)
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f"  ({detail})" if detail and not ok else ""))


def run(coro):
    return asyncio.run(coro)


UID = "anon-post-signout"

print("=" * 60)
print("BUG 2 — MARQUEUR TRIAL(0) POST-SIGN-OUT — VALIDATION OFFLINE")
print("=" * 60)

# 1) anon frais → Free 3
supa = FilterSupa()
free = run(billing._free_bucket_available(supa, UID))
check("1. anon frais → Free 3", free == 3, f"got {free}")

# 2) mark_trial_consumed : écrit le marqueur, idempotent
supa = FilterSupa()
new1 = run(billing.mark_trial_consumed(user_id=UID, supa=supa))
new2 = run(billing.mark_trial_consumed(user_id=UID, supa=supa))
marks = supa.ledger_by_key(f"trial:{UID}")
check("2a. 1 ligne TRIAL trial:<uid>", len(marks) == 1, f"got {len(marks)}")
check("2b. available_delta == 0", bool(marks) and marks[0].get("available_delta") == 0)
check("2c. entry_type=TRIAL / ref=PROMO/post_signout",
      bool(marks) and marks[0].get("entry_type") == "TRIAL"
      and marks[0].get("reference_type") == "PROMO"
      and marks[0].get("reference_id") == "post_signout")
check("2d. idempotent (1er=nouveau, 2e=no-op)", new1 is True and new2 is False)

# 3) après marqueur → Free 0
free = run(billing._free_bucket_available(supa, UID))
check("3. après marqueur → Free 0", free == 0, f"got {free}")

# 4) après marqueur → /generate (billing_try_hold) bloqué, aucun HOLD, aucun +3
res = supa.rpc("billing_try_hold",
               {"p_user_id": UID, "p_intent_id": "intent-x", "p_tier": "free"}).execute().data
check("4a. Generate → granted=False", res.get("granted") is False, f"got {res}")
check("4b. reason insufficient_credits", res.get("reason") == "insufficient_credits", f"got {res.get('reason')}")
check("4c. aucun HOLD posé", len(supa.ledger_by_key("hold:intent-x")) == 0)
trials = supa.ledger_by_key(f"trial:{UID}")
check("4d. aucun +3 (marqueur bloque le grant)",
      all(int(r.get("available_delta") or 0) == 0 for r in trials), f"deltas={[r.get('available_delta') for r in trials]}")

# 5) contrôle : vrai anon frais SANS marqueur → +3 accordé, puis Free 2
supa2 = FilterSupa()
res2 = supa2.rpc("billing_try_hold",
                 {"p_user_id": "genuine-new", "p_intent_id": "i1", "p_tier": "free"}).execute().data
check("5a. genuine fresh → granted=True (+3, 1 gen)", res2.get("granted") is True, f"got {res2}")
free2 = run(billing._free_bucket_available(supa2, "genuine-new"))
check("5b. genuine fresh après 1 gen → Free 2", free2 == 2, f"got {free2}")

print("-" * 60)
print(f"RÉSULTAT : {_passed}/{_passed + _failed} PASS")
sys.exit(0 if _failed == 0 else 1)
