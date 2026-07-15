"""
COMMIT 5b — validateur OFFLINE du dispatch webhook RevenueCat (aucun réseau, aucune DB).

Teste le ROUTAGE des événements dans revenuecat_webhook.revenuecat_webhook :
  • CANCELLATION + cancel_reason='CUSTOMER_SUPPORT' → manual_review, 0 mutation ;
  • CANCELLATION + cancel_reason='UNSUBSCRIBE'      → no-op existant ;
  • REFUND_REVERSED                                 → manual_review explicite ;
  • INITIAL_PURCHASE/RENEWAL                        → grant ROUTÉ (billing.grant_purchase_routed) ;
  • TRANSFER (rôle seul)                            → billing.route_role_apply ;
  • EXPIRATION                                      → billing.route_role_apply.
+ assertions structurelles : vrais champs RC (cancel_reason/CUSTOMER_SUPPORT), aucune
  valeur fictive 'REFUNDED', pas de 'cancellation_reason', REFUND_REVERSED reconnu.

Exécution :  python _route_revenuecat_validation.py
"""
from __future__ import annotations
import asyncio
import json
import os
import sys

os.environ.setdefault("REVENUECAT_WEBHOOK_AUTH", "test-secret")
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test")
os.environ.setdefault("OPENAI_API_KEY", "test")

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import billing  # noqa: E402
import revenuecat_webhook as rw  # noqa: E402
from starlette.requests import Request  # noqa: E402

SECRET = os.environ["REVENUECAT_WEBHOOK_AUTH"]
RESULTS = []
CALLS = {"grant_routed": [], "role_apply": []}


def check(name, cond, extra=""):
    RESULTS.append((name, bool(cond)))
    print(f"[{'PASS' if cond else 'FAIL'}] {name}" + (f"  ({extra})" if extra else ""))


# ── Mocks (aucune DB) ────────────────────────────────────────────────────────
class _FakeSupa:
    pass


async def _fake_grant_routed(**kw):
    CALLS["grant_routed"].append(kw)
    return {"effective_user_id": kw.get("original_user_id"), "routing_code": "active",
            "decision": "granted", "granted": True}


async def _fake_role_apply(**kw):
    CALLS["role_apply"].append(kw)
    return {"effective_user_id": kw.get("original_user_id"), "routing_code": "active",
            "decision": "applied"}


async def _raise_routing_changed(**kw):
    raise billing.RoutingChangedRetry()


async def _raise_routing_changed_role(**kw):
    raise billing.RoutingChangedRetry()


rw._get_supa = lambda: _FakeSupa()
billing.grant_purchase_routed = _fake_grant_routed
billing.route_role_apply = _fake_role_apply


def _req(event: dict) -> Request:
    body = json.dumps({"event": event}).encode()
    scope = {
        "type": "http", "method": "POST", "path": "/webhooks/revenuecat",
        "query_string": b"", "headers": [(b"authorization", SECRET.encode())],
    }

    async def receive():
        return {"type": "http.request", "body": body, "more_body": False}

    return Request(scope, receive)


async def _call(event: dict) -> dict:
    CALLS["grant_routed"].clear()
    CALLS["role_apply"].clear()
    return await rw.revenuecat_webhook(_req(event))


PREM = ["premium"]


async def run():
    # 1. Remboursement : CANCELLATION + CUSTOMER_SUPPORT → manual_review, aucun billing appelé
    r = await _call({"type": "CANCELLATION", "id": "e1", "app_user_id": "userA1234",
                     "cancel_reason": "CUSTOMER_SUPPORT", "entitlement_ids": PREM})
    check("1. refund (CANCELLATION+CUSTOMER_SUPPORT) → acknowledged_manual_review",
          r.get("action") == "acknowledged_manual_review" and r.get("decision") == "RC_REFUND_MANUAL_REVIEW",
          str(r))
    check("1b. refund → aucune mutation (grant/role non appelés)",
          not CALLS["grant_routed"] and not CALLS["role_apply"])

    # 2. Résiliation simple : CANCELLATION + UNSUBSCRIBE → no-op existant
    r = await _call({"type": "CANCELLATION", "id": "e2", "app_user_id": "userA1234",
                     "cancel_reason": "UNSUBSCRIBE", "entitlement_ids": PREM})
    check("2. CANCELLATION+UNSUBSCRIBE → noop (comportement existant)",
          r.get("action") == "noop", str(r))

    # 3. REFUND_REVERSED → manual_review explicite
    r = await _call({"type": "REFUND_REVERSED", "id": "e3", "app_user_id": "userA1234",
                     "entitlement_ids": PREM})
    check("3. REFUND_REVERSED → acknowledged_manual_review",
          r.get("action") == "acknowledged_manual_review" and r.get("decision") == "RC_REFUND_REVERSED_MANUAL_REVIEW",
          str(r))
    check("3b. REFUND_REVERSED → aucune mutation", not CALLS["grant_routed"] and not CALLS["role_apply"])

    # 4. INITIAL_PURCHASE → grant ROUTÉ (billing.grant_purchase_routed avec original=app_user_id)
    r = await _call({"type": "INITIAL_PURCHASE", "id": "e4", "app_user_id": "userA1234",
                     "entitlement_ids": PREM, "product_id": "weekly", "transaction_id": "tx4",
                     "expiration_at_ms": 9999999999999})
    check("4. INITIAL_PURCHASE → premium_granted_routed",
          r.get("action") == "premium_granted_routed", str(r))
    check("4b. INITIAL_PURCHASE → grant_purchase_routed appelé (original=app_user_id)",
          len(CALLS["grant_routed"]) == 1 and CALLS["grant_routed"][0].get("original_user_id") == "userA1234")

    # 5. TRANSFER (rôle seul) → route_role_apply
    r = await _call({"type": "TRANSFER", "id": "e5", "app_user_id": "userA1234",
                     "entitlement_ids": PREM, "expiration_at_ms": 9999999999999})
    check("5. TRANSFER → premium_role_routed via route_role_apply",
          r.get("action") == "premium_role_routed" and len(CALLS["role_apply"]) == 1
          and not CALLS["grant_routed"], str(r))

    # 6. EXPIRATION → route_role_apply
    r = await _call({"type": "EXPIRATION", "id": "e6", "app_user_id": "userA1234",
                     "expiration_at_ms": 1000})
    check("6. EXPIRATION → premium_expire_routed via route_role_apply",
          r.get("action") == "premium_expire_routed" and len(CALLS["role_apply"]) == 1, str(r))

    # 7. RENEWAL → grant routé (crédit)
    r = await _call({"type": "RENEWAL", "id": "e7", "app_user_id": "userA1234",
                     "entitlement_ids": PREM, "product_id": "weekly", "transaction_id": "tx7",
                     "expiration_at_ms": 9999999999999})
    check("7. RENEWAL → premium_granted_routed", r.get("action") == "premium_granted_routed"
          and len(CALLS["grant_routed"]) == 1, str(r))

    # ── Assertions structurelles (source) ────────────────────────────────────
    wh = open(os.path.join(HERE, "revenuecat_webhook.py"), encoding="utf-8").read()
    check("8. utilise le VRAI champ cancel_reason (pas cancellation_reason)",
          "cancel_reason" in wh and "cancellation_reason" not in wh)
    check("9. valeur RC réelle CUSTOMER_SUPPORT présente, aucune valeur fictive REFUNDED",
          "CUSTOMER_SUPPORT" in wh and "REFUNDED" not in wh)
    check("10. REFUND_REVERSED reconnu explicitement (hors fallback unknown)",
          "REFUND_REVERSED" in wh)
    check("11. codes sûrs présents",
          "RC_REFUND_MANUAL_REVIEW" in wh and "RC_REFUND_REVERSED_MANUAL_REVIEW" in wh)
    bl = open(os.path.join(HERE, "billing.py"), encoding="utf-8").read()
    check("12. billing.py : grant_purchase_routed + route_role_apply",
          "async def grant_purchase_routed" in bl and "async def route_role_apply" in bl)
    mig = open(os.path.join(HERE, "..", "supabase", "migrations",
                            "20260716_billing_route_revenuecat.sql"), encoding="utf-8").read()
    check("13. migration : 4 fonctions routées",
          all(s in mig for s in ["function public.billing_route_target",
                                 "function public.billing_upsert_premium_role",
                                 "function public.billing_grant_purchase_routed",
                                 "function public.billing_route_role_apply"]))
    check("14. migration : garde anti-ancien (GREATEST + NULL préservé)",
          "greatest(public.user_roles.expires_at" in mig and "is null then null" in mig)

    # ── Course de prélecture : ROUTING_CHANGED_RETRY → HTTP 503 (RC retry, pas manual_review) ──
    from fastapi import HTTPException  # noqa: PLC0415

    async def _expect_503(event):
        try:
            await _call(event)
            return None
        except HTTPException as e:
            return e.status_code

    billing.grant_purchase_routed = _raise_routing_changed
    code = await _expect_503({"type": "INITIAL_PURCHASE", "id": "e15", "app_user_id": "userA1234",
                              "entitlement_ids": PREM, "product_id": "weekly", "transaction_id": "tx15",
                              "expiration_at_ms": 9999999999999})
    check("15. crédit : ROUTING_CHANGED_RETRY → HTTP 503 (pas 200/manual_review)", code == 503, f"code={code}")
    billing.grant_purchase_routed = _fake_grant_routed  # restore

    billing.route_role_apply = _raise_routing_changed_role
    code = await _expect_503({"type": "EXPIRATION", "id": "e16", "app_user_id": "userA1234",
                              "expiration_at_ms": 1000})
    check("16. rôle/expiration : ROUTING_CHANGED_RETRY → HTTP 503", code == 503, f"code={code}")
    billing.route_role_apply = _fake_role_apply  # restore

    # ── Structurels : garde de race + helper privé ────────────────────────────
    check("17. migration : garde de race (is distinct from hint + errcode 40001 ROUTING_CHANGED_RETRY)",
          "is distinct from v_hint" in mig and "40001" in mig and "ROUTING_CHANGED_RETRY" in mig)
    check("18. billing.py : RoutingChangedRetry + détection",
          "class RoutingChangedRetry" in bl and "_is_routing_changed" in bl)
    check("19. webhook : mappe RoutingChangedRetry → 503",
          "RoutingChangedRetry" in wh and "routing_changed_retry" in wh and "status_code=503" in wh)
    check("20. migration : helper billing_upsert_premium_role PRIVÉ (revoke ... service_role, aucun grant)",
          "from public, anon, authenticated, service_role" in mig
          and "grant  execute on function public.billing_upsert_premium_role" not in mig)
    check("21. migration : « statut le plus récent gagne » (order by started_at desc, merge_id desc ; "
          "pas de filtre de statut qui ignorerait une ligne récente)",
          "order by m.started_at desc, m.merge_id desc" in mig
          and "and m.status in ('running'" not in mig)

    # 22. Crédit à champs manquants → rôle routé SEUL (parité _upsert_premium), pas de grant crédit
    r = await _call({"type": "INITIAL_PURCHASE", "id": "e22", "app_user_id": "userA1234",
                     "entitlement_ids": PREM, "transaction_id": "", "expiration_at_ms": 9999999999999})
    check("22. crédit champs manquants → rôle routé seul (route_role_apply, aucun grant crédit)",
          len(CALLS["role_apply"]) == 1 and not CALLS["grant_routed"], str(r))

    # 23. Crédit PAYÉ routé en manual_review → 200 acquitté + routing manual_review VISIBLE
    async def _fake_grant_manual(**kw):
        CALLS["grant_routed"].append(kw)
        return {"effective_user_id": None, "routing_code": "manual_merge_status",
                "decision": "manual_review", "granted": False}

    billing.grant_purchase_routed = _fake_grant_manual
    r = await _call({"type": "RENEWAL", "id": "e23", "app_user_id": "userA1234",
                     "entitlement_ids": PREM, "product_id": "weekly", "transaction_id": "tx23",
                     "expiration_at_ms": 9999999999999})
    check("23. crédit → manual_review : 200 acquitté + routing.decision=manual_review",
          r.get("action") == "premium_granted_routed"
          and r.get("routing", {}).get("decision") == "manual_review", str(r))
    billing.grant_purchase_routed = _fake_grant_routed  # restore
    check("24. webhook : crédit manual_review VISIBLE (_warn_if_credit_manual + RC_CREDIT_MANUAL_REVIEW)",
          "_warn_if_credit_manual" in wh and "RC_CREDIT_MANUAL_REVIEW" in wh)
    check("25. webhook : _dual_write_grant marqué LEGACY / non-routé (anti-réintroduction)",
          "LEGACY" in wh and "NE PLUS UTILISER" in wh)


def main():
    print("=" * 62)
    print("COMMIT 5b — VALIDATION OFFLINE DISPATCH WEBHOOK")
    print("=" * 62)
    asyncio.run(run())
    print("-" * 62)
    failed = [n for n, ok in RESULTS if not ok]
    print(f"RÉSULTAT : {len(RESULTS) - len(failed)}/{len(RESULTS)} PASS")
    for n in failed:
        print("  KO:", n)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
