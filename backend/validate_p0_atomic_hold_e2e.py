"""P0a-bis — E2E CONCURRENCE RÉELLE (advisory-lock Postgres). VERSIONNÉ.
À tourner APRÈS apply des migrations :
  20260710_billing_p0_additive_projection.sql  PUIS  20260710_billing_p0a_atomic_hold.sql
Fire N appels billing_try_hold CONCURRENTS (ThreadPool → N transactions HTTP simultanées)
→ prouve granted == min(N, bucket) (l'advisory-lock sérialise ; sans lui on aurait N granted).

Nécessite SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (backend/.env). Users jetables : le
ledger étant append-only (hardening), le résidu 'e2e-atomic-*' n'est PAS supprimable via
l'API → purge SQL dashboard (cf. docs/P0_BILLING_INTEGRITY_TEST_MATRIX.md).

Usage :  python validate_p0_atomic_hold_e2e.py
Exit : 0 = 4/4 · 3 = RPC pas encore appliqué (abort propre, 0 résidu) · 1 = un test a échoué.
"""
import os, sys, uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone, timedelta

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
from dotenv import load_dotenv
load_dotenv(os.path.join(_HERE, ".env"), override=True)
import logging; logging.disable(logging.CRITICAL)
from supabase import create_client

URL = os.environ["SUPABASE_URL"]; KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
supa = create_client(URL, KEY)
PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"; res = []
def check(l, c, d=""):
    res.append(bool(c)); print(f"  {PASS if c else FAIL}  {l}{('  ['+str(d)+']') if d and not c else ''}")

NOW = datetime.now(timezone.utc)
FUT = (NOW + timedelta(days=7)).isoformat()
PAST_S = (NOW - timedelta(days=8)).isoformat()
_W = supa.table("products").select("id").eq("sku", "weekly_pass").limit(1).execute().data
WID = _W[0]["id"] if _W else None
_users = []

def mkuser():
    s = uuid.uuid4().hex[:10]
    u = supa.auth.admin.create_user({"email": f"e2e-atomic-{s}@example.invalid",
                                     "password": uuid.uuid4().hex, "email_confirm": True})
    _users.append(u.user.id); return u.user.id

def mkpass(uid, credits):
    p = supa.table("passes").insert({"user_id": uid, "product_id": WID, "status": "ACTIVE",
                                     "starts_at": PAST_S, "ends_at": FUT}).execute().data[0]
    supa.table("ledger_entries").insert({"user_id": uid, "entry_type": "GRANT", "available_delta": credits,
        "pass_id": p["id"], "idempotency_key": f"e2e-grant-{p['id']}"}).execute()
    return p["id"]

def try_hold_rpc(uid, intent, tier):
    """1 appel HTTP concurrent = 1 transaction Postgres (advisory-lock actif)."""
    c = create_client(URL, KEY)  # client par thread (pool HTTP/1.1 sûr)
    r = c.rpc("billing_try_hold", {"p_user_id": uid, "p_intent_id": intent, "p_tier": tier}).execute()
    return bool((r.data or {}).get("granted"))

def fire(uid, n, tier, prefix):
    with ThreadPoolExecutor(max_workers=min(n, 32)) as ex:
        return list(ex.map(lambda i: try_hold_rpc(uid, f"{prefix}-{i}", tier), range(n)))

print("\n=== P0a-bis · E2E concurrence réelle (advisory-lock) ===")
try:
    if not WID:
        print("  !! weekly_pass introuvable — abort"); sys.exit(2)
    try:
        supa.rpc("billing_try_hold", {"p_user_id": str(uuid.uuid4()),
                                      "p_intent_id": "probe", "p_tier": "admin"}).execute()
    except Exception as e:
        if any(t in str(e).lower() for t in ("pgrst202", "could not find the function", "does not exist", "schema cache")):
            print("  !! billing_try_hold PAS ENCORE APPLIQUÉ (migration 20260710_p0a) — abort (0 résidu)")
            sys.exit(3)

    # A — CONCURRENCE PASS : bucket=20, 80 concurrents → EXACTEMENT 20 granted
    u = mkuser(); pid = mkpass(u, 20)
    n = sum(fire(u, 80, "premium", "A"))
    final = sum(int(r["available_delta"]) for r in
               supa.table("ledger_entries").select("available_delta").eq("user_id", u).eq("pass_id", pid).execute().data)
    check("A pass=20, 80 concurrents → EXACTEMENT 20 granted, solde final 0", n == 20 and final == 0, (n, final))

    # B — CONCURRENCE FREE : new user, 20 concurrents → EXACTEMENT 3 granted
    u = mkuser()
    n = sum(fire(u, 20, "free", "B"))
    free_final = sum(int(r["available_delta"]) for r in
                    supa.table("ledger_entries").select("available_delta").eq("user_id", u).is_("pass_id", "null").execute().data)
    check("B free new user, 20 concurrents → EXACTEMENT 3 granted, free final 0", n == 3 and free_final == 0, (n, free_final))

    # C — IDEMPOTENCE concurrente : même intent 10× → 1 HOLD, tous granted
    u = mkuser(); mkpass(u, 30)
    with ThreadPoolExecutor(max_workers=10) as ex:
        gr = list(ex.map(lambda _: try_hold_rpc(u, "same-intent", "premium"), range(10)))
    holds = supa.table("ledger_entries").select("id").eq("idempotency_key", "hold:same-intent").execute().data
    check("C même intent ×10 concurrents → 1 seul HOLD, tous granted", all(gr) and len(holds) == 1, len(holds))

    # D — pass-first puis free sous concurrence : pass=1 + free(trial 3) → EXACTEMENT 4 granted
    u = mkuser(); mkpass(u, 1)
    supa.table("ledger_entries").insert({"user_id": u, "entry_type": "TRIAL", "available_delta": 3,
        "pass_id": None, "idempotency_key": f"trial:{u}"}).execute()
    n = sum(fire(u, 15, "premium", "D"))
    check("D pass=1 + free=3, 15 concurrents → EXACTEMENT 4 granted (pass-first puis free)", n == 4, n)

finally:
    print(f"  résidu : {len(_users)} users e2e-atomic-* (inertes, purge SQL dashboard)")

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  E2E ATOMIC — TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
