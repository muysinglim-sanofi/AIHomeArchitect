"""P0 (2026-07-10) — reconcile_pass_from_subscriber : restore/sync → pass MESURÉ.

Pur (FakeSupa + spy sur grant_purchase, 0 DB/0 réseau). Vérifie les GARDE-FOUS et
l'idempotence PAR CONSTRUCTION (la clé de GRANT = store_transaction_id du cycle,
jamais original_transaction_id → grant_purchase ON CONFLICT dédup → 5x = 1 GRANT,
même cycle que le webhook = pas de double). Le dédup réel en base est prouvé par
grant_purchase (RC-PR2 + E2E). Ici on prouve QUE reconcile appelle grant_purchase
avec le bon tx, et sinon renvoie restore_required sans jamais créer de pass arbitraire.
"""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import billing
from billing import GrantResult, ProductNotMapped

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(bool(cond))
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")

# ── spy sur grant_purchase (le chemin idempotent réel) ──────────────────────
calls = []
async def _spy_grant(**kw):
    calls.append(kw)
    if kw["store_product_id"] == "com.unmapped":
        raise ProductNotMapped(kw["store_product_id"])
    return GrantResult(ok=True, status="granted", credited=True, credits=30,
                       order_id="order-1", pass_id="pass-1")
billing.grant_purchase = _spy_grant   # reconcile appelle le global du module → patché

FUTURE = "2099-01-01T00:00:00Z"
PAST = "2000-01-01T00:00:00Z"
WEEKLY = "com.aydenstudio.app.weekly"

def _sub(*, product=WEEKLY, expires=FUTURE, store_tx="TX-CYCLE-123",
         original_tx="ORIG-999", with_ent=True, with_sub=True):
    ent = {"expires_date": expires, "product_identifier": product} if with_ent else {}
    subs = {}
    if with_sub and product:
        s = {}
        if store_tx is not None:
            s["store_transaction_id"] = store_tx
        s["original_transaction_id"] = original_tx
        subs[product] = s
    return {"entitlements": {"premium": ent}, "subscriptions": subs}

def recon(subscriber):
    calls.clear()
    return asyncio.run(billing.reconcile_pass_from_subscriber(
        user_id="user-1", subscriber=subscriber, supa=object()))


print("\n=== P0 · reconcile_pass_from_subscriber ===")

# 1. active weekly + store_tx + expires → grant appelé → pass
r = recon(_sub())
check("1 active weekly + store_tx + expires → state=pass + grant appelé 1x",
      r["state"] == "pass" and r["has_measurable_pass"] and len(calls) == 1, (r, calls))

# 2. clé = store_transaction_id (CYCLE), JAMAIS original_transaction_id
r = recon(_sub(store_tx="TX-CYCLE-123", original_tx="ORIG-999"))
c = calls[0] if calls else {}
check("2 grant provider_transaction_id = store_transaction_id (cycle), pas original",
      c.get("provider_transaction_id") == "TX-CYCLE-123"
      and c.get("provider_transaction_id") != "ORIG-999"
      and c.get("store_product_id") == WEEKLY, c)

# 3. 5x reconcile → 5x grant avec le MÊME tx (ancre idempotente → RPC ON CONFLICT dédup)
txs = []
for _ in range(5):
    recon(_sub(store_tx="TX-SAME"))
    txs.append(calls[0]["provider_transaction_id"] if calls else None)
check("3 5x reconcile → même provider_transaction_id à chaque fois (=> 1 GRANT au niveau RPC)",
      txs == ["TX-SAME"] * 5, txs)

# 4. store_transaction_id absent → restore_required, AUCUN grant
r = recon(_sub(store_tx=None))
check("4 store_transaction_id absent → restore_required + AUCUN grant",
      r["state"] == "restore_required" and r["reason"] == "insufficient_rc_data"
      and len(calls) == 0, (r, calls))

# 5. produit non mappé → grant lève ProductNotMapped → restore_required
r = recon(_sub(product="com.unmapped"))
check("5 produit non mappé → restore_required (reason=product_not_mapped)",
      r["state"] == "restore_required" and r["reason"] == "product_not_mapped", r)

# 6. expiration absente (None = lifetime) → restore_required (pas de pass sans période)
r = recon(_sub(expires=None))
check("6 expires_date absent → restore_required + AUCUN grant",
      r["state"] == "restore_required" and r["reason"] == "insufficient_rc_data"
      and len(calls) == 0, (r, calls))

# 7. active + (rôle premium sans pass) → reconcile crée le pass (indépendant du rôle)
r = recon(_sub())
check("7 abo actif (rôle sans pass) → reconcile CRÉE le pass mesuré",
      r["state"] == "pass" and r["has_measurable_pass"], r)

# 8. pas d'abo actif (entitlement expiré) → free, AUCUN grant, jamais premium
r = recon(_sub(expires=PAST))
check("8 entitlement expiré → state=free, AUCUN grant, jamais premium",
      r["state"] == "free" and not r["has_measurable_pass"] and len(calls) == 0, (r, calls))

# 8b. pas d'entitlement du tout → free
r = recon(_sub(with_ent=False))
check("8b aucun entitlement premium → state=free", r["state"] == "free" and len(calls) == 0)

# 9. annual → grant appelé avec le produit annual (mapping distinct)
r = recon(_sub(product="com.aydenstudio.app.annual"))
check("9 active annual → grant appelé (store_product_id=annual)",
      r["state"] == "pass" and calls and calls[0]["store_product_id"] == "com.aydenstudio.app.annual", r)

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
