"""RC-PR2 (2026-07-08) — contrat du chemin ACQUISITION (achat/renouvellement).

Prouve, SANS DB ni réseau (double FakeSupa ; le ledger réel est append-only, on
ne le pollue pas), que :
  • billing.grant_purchase résout le product et lève ProductNotMapped si absent
    (pas de skip muet d'un achat payé) ;
  • les params du RPC billing_grant_purchase sont construits correctement
    (credits/duration issus du product, tx = transaction du cycle, ends_at RC,
    raw_payload = event complet → environment tracé) ;
  • le résultat RPC est fidèlement mappé (granted vs already_processed idempotent) ;
  • un achat SANDBOX crédite normalement (décision RC-PR2), environment conservé ;
  • le webhook _dual_write_grant : non-2xx (HTTPException 500) si product non mappé
    OU si le RPC échoue (PAS de fail-open) ; skip LOUD si champs manquants (pas 500).

L'idempotence/atomicité RÉELLES sont dans le RPC SQL (migration) — vérifiées via
son bloc sanity-check sur un user jetable. Ici on verrouille la couche Python.
"""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import billing
import revenuecat_webhook as rc
from fastapi import HTTPException

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(bool(cond))
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")


# ── Doubles ──────────────────────────────────────────────────────────────────

WEEKLY = {"id": "prod-weekly", "type": "PASS", "credits_granted": 60, "duration_days": 7}


class _Res:
    def __init__(self, data): self.data = data


class _Query:
    def __init__(self, rows): self._rows = rows
    def select(self, *a, **k): return self
    def or_(self, *a, **k): return self
    def eq(self, *a, **k): return self
    def limit(self, *a, **k): return self
    def execute(self): return _Res(self._rows)


class FakeSupa:
    """Mime le sous-ensemble utilisé par billing.grant_purchase."""
    def __init__(self, *, product_rows=None, rpc_data=None, rpc_exc=None):
        self._product_rows = [] if product_rows is None else product_rows
        self._rpc_data = rpc_data
        self._rpc_exc = rpc_exc
        self.rpc_calls = []

    def table(self, name):
        assert name == "products", name
        return _Query(self._product_rows)

    def rpc(self, name, params):
        self.rpc_calls.append((name, params))
        exc, data = self._rpc_exc, self._rpc_data
        class _R:
            def execute(_self):
                if exc:
                    raise exc
                return _Res(data)
        return _R()


GRANTED = {"ok": True, "status": "granted", "credited": True, "credits": 60,
           "order_id": "o1", "pass_id": "p1", "available_credits": 60}
ALREADY = {"ok": True, "status": "already_processed", "credited": False, "credits": 0,
           "order_id": "o1", "pass_id": "p1", "available_credits": 60}


def run(coro):
    return asyncio.run(coro)


print("\n=== RC-PR2 · billing.grant_purchase ===")

# 1. product non mappé (aucune ligne) → ProductNotMapped (pas de skip muet)
def _no_map():
    supa = FakeSupa(product_rows=[], rpc_data=GRANTED)
    try:
        run(billing.grant_purchase(
            user_id="u1", provider="revenuecat", provider_transaction_id="tx1",
            store_product_id="com.unknown.sku", supa=supa))
        return (False, "no raise")
    except billing.ProductNotMapped as e:
        return (e.store_product_id == "com.unknown.sku" and not supa.rpc_calls, "")
    except Exception as e:  # noqa: BLE001
        return (False, f"wrong exc {type(e).__name__}")
ok, d = _no_map(); check("1 product non mappé → ProductNotMapped + RPC jamais appelé", ok, d)

# 2. product mappé → RPC appelé avec les bons params (credits/duration/tx/ends/raw)
def _params():
    supa = FakeSupa(product_rows=[WEEKLY], rpc_data=GRANTED)
    r = run(billing.grant_purchase(
        user_id="u1", provider="revenuecat", provider_transaction_id="tx-cycle-1",
        store_product_id="com.aydenstudio.app.weekly", amount=7.99, currency="USD",
        ends_at_iso="2026-07-15T00:00:00+00:00",
        raw_payload={"environment": "PRODUCTION", "product_id": "com.aydenstudio.app.weekly"},
        supa=supa))
    if len(supa.rpc_calls) != 1:
        return (False, "rpc not called once")
    name, p = supa.rpc_calls[0]
    good = (name == "billing_grant_purchase"
            and p["p_user_id"] == "u1"
            and p["p_provider"] == "revenuecat"
            and p["p_provider_transaction_id"] == "tx-cycle-1"
            and p["p_product_id"] == "prod-weekly"
            and p["p_credits"] == 60
            and p["p_duration_days"] == 7
            and p["p_ends_at"] == "2026-07-15T00:00:00+00:00"
            and p["p_raw_payload"].get("environment") == "PRODUCTION")
    return (good and r.status == "granted" and r.credited and r.credits == 60, p)
ok, d = _params(); check("2 params RPC corrects + résultat 'granted' mappé", ok, d)

# 3. RPC renvoie already_processed (redélivrance) → credited False (idempotence surfacée)
def _idem():
    supa = FakeSupa(product_rows=[WEEKLY], rpc_data=ALREADY)
    r = run(billing.grant_purchase(
        user_id="u1", provider="revenuecat", provider_transaction_id="tx-cycle-1",
        store_product_id="com.aydenstudio.app.weekly", supa=supa))
    return (r.status == "already_processed" and not r.credited and r.credits == 0, r)
ok, d = _idem(); check("3 already_processed → credited=False, credits=0", ok, d)

# 4. RPC data wrappé dans une liste (variante PostgREST) → mappé pareil
def _listwrap():
    supa = FakeSupa(product_rows=[WEEKLY], rpc_data=[GRANTED])
    r = run(billing.grant_purchase(
        user_id="u1", provider="revenuecat", provider_transaction_id="tx2",
        store_product_id="com.aydenstudio.app.weekly", supa=supa))
    return (r.credited and r.credits == 60, r)
ok, d = _listwrap(); check("4 data en liste 1-élément → mappé correctement", ok, d)


print("\n=== RC-PR2 · webhook _dual_write_grant ===")

def _event(**over):
    e = {"type": "INITIAL_PURCHASE", "product_id": "com.aydenstudio.app.weekly",
         "transaction_id": "tx-w-1", "environment": "SANDBOX",
         "price": 7.99, "currency": "USD"}
    e.update(over); return e

# 5. SANDBOX + product mappé → crédite normalement, environment tracé dans raw_payload
def _sandbox():
    supa = FakeSupa(product_rows=[WEEKLY], rpc_data=GRANTED)
    info = run(rc._dual_write_grant(supa=supa, event=_event(),
                                    user_id="u1", expires_iso="2026-07-15T00:00:00+00:00"))
    name, p = supa.rpc_calls[0]
    return (info["credited"] and info["environment"] == "SANDBOX"
            and p["p_raw_payload"].get("environment") == "SANDBOX", info)
ok, d = _sandbox(); check("5 achat SANDBOX crédite + environment dans raw_payload", ok, d)

# 6. product non mappé → HTTPException(500) (non-2xx pour retry RC, pas de skip)
def _webhook_nomap():
    supa = FakeSupa(product_rows=[], rpc_data=GRANTED)
    try:
        run(rc._dual_write_grant(supa=supa, event=_event(product_id="com.unknown"),
                                 user_id="u1", expires_iso="x"))
        return (False, "no raise")
    except HTTPException as e:
        return (e.status_code == 500 and e.detail == "product_not_mapped", e.detail)
ok, d = _webhook_nomap(); check("6 product non mappé → HTTPException 500 (retry RC)", ok, d)

# 7. RPC échoue → HTTPException(500) (PAS de fail-open sur le chemin argent)
def _webhook_rpcfail():
    supa = FakeSupa(product_rows=[WEEKLY], rpc_exc=RuntimeError("db down"))
    try:
        run(rc._dual_write_grant(supa=supa, event=_event(),
                                 user_id="u1", expires_iso="x"))
        return (False, "no raise")
    except HTTPException as e:
        return (e.status_code == 500 and e.detail == "grant_failed", e.detail)
ok, d = _webhook_rpcfail(); check("7 RPC échoue → HTTPException 500 (pas de fail-open)", ok, d)

# 8. champs manquants (pas de tx) → skip LOUD, PAS de 500 (retry ne corrigerait pas)
def _webhook_missing():
    supa = FakeSupa(product_rows=[WEEKLY], rpc_data=GRANTED)
    info = run(rc._dual_write_grant(supa=supa, event=_event(transaction_id=""),
                                    user_id="u1", expires_iso="x"))
    return (not info["credited"] and info["reason"] == "missing_fields"
            and not supa.rpc_calls, info)
ok, d = _webhook_missing(); check("8 champs manquants → skip loud (pas de 500, pas de RPC)", ok, d)

# 9. modules importés = câblage compile (dual-write + constant scope)
check("9 _CREDIT_GRANTING_EVENTS = INITIAL_PURCHASE + RENEWAL seulement",
      rc._CREDIT_GRANTING_EVENTS == frozenset({"INITIAL_PURCHASE", "RENEWAL"}),
      rc._CREDIT_GRANTING_EVENTS)

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
