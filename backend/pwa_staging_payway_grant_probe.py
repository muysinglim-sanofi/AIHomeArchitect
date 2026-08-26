"""ABA10/11/15/16/17 — the grant chain, with ONE thing simulated and named.

What is real here, and what is not
----------------------------------
    the PayWay transaction    REAL. Signed, sent, and accepted by
                              checkout-sandbox.payway.com.kh via /payments/
                              purchase. A genuine ABA-hosted checkout URL comes
                              back.
    the rail row              REAL, in pwa_staging.payway_transactions.
    the canonical order       REAL, in public.orders, on provider='khqr'.
    the seam                  REAL. `verify_and_settle` and `_grant` are the
                              functions the HTTP route calls.
    the Billing Engine        REAL. `billing.grant_purchase` -> the RPC ->
                              ledger -> pass -> wallet, in staging Postgres.
    the entitlement           REAL. Read back through the same resolver the
                              `/entitlement` endpoint uses.

    the gateway's ANSWER      SIMULATED. `payway.check_transaction` is replaced
                              with the APPROVED envelope, VERBATIM in the shape
                              the sandbox really sends (`data`-nested — the shape
                              that caught a live parser bug on 2026-08-19).

Why simulate exactly that, and nothing else
-------------------------------------------
Paying a KHQR requires a human with the ABA sandbox app, and no code can do it.
That single step is the ONLY thing standing between this repository and a proven
end-to-end purchase, so it is the only thing replaced — and it is replaced with
the gateway's own recorded output rather than with a convenient shape.

This is NOT a substitute for `pwa_staging_payway_e2e.py`. That file reports
ABA10/11/15/16/17 as BLOCKED until real money moves, and it must keep doing so.
This one answers a different question: given that PayWay says APPROVED, does
everything after it actually work? If this passes and the live run still fails,
the fault is in the payment, not in us — which is a genuinely useful thing to
know before asking anyone to stand in front of a QR.

Run:  cd backend && PYTHONPATH=. python pwa_staging_payway_grant_probe.py
Safe: staging only, sandbox merchant, disposable identity, $4.99 never charged.
"""
from __future__ import annotations

import asyncio
import os
import pathlib
import sys
import types
import uuid

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):  # pragma: no cover
        pass

STAGING_REF = "eedcahzekpgxvvfxufbk"
STAGING_URL = f"https://{STAGING_REF}.supabase.co"
ENV = HERE / ".env.pwa-staging.local"

_passed: list[str] = []
_failed: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (_passed if ok else _failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  -- {detail}'}")


def section(title: str) -> None:
    print(f"\n== {title} " + "=" * max(0, 60 - len(title)))


def _load_env() -> None:
    """Seed the process from the ignored staging file. Values never printed."""
    if not ENV.exists():
        raise SystemExit(f"REFUSING: {ENV.name} is missing.")
    for raw in ENV.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ[key.strip()] = value.strip().strip('"').strip("'")
    url = os.environ.get("SUPABASE_URL", "")
    if STAGING_REF not in url or "vtxkciupyafukhdsgxgw" in url:
        raise SystemExit("REFUSING: SUPABASE_URL is not the staging project.")
    # The Web free tier is ONE — the same lever run_pwa_staging.py pins.
    os.environ["ACCOUNT_SYSTEM_ENABLED"] = "true"


def _service_client():
    """A real service-role client, with main.py's own transport hardening."""
    import httpx  # noqa: PLC0415
    from supabase import create_client  # noqa: PLC0415

    supa = create_client(STAGING_URL, os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    session = supa.postgrest.session
    supa.postgrest.session = httpx.Client(
        base_url=session.base_url, headers=session.headers,
        timeout=httpx.Timeout(15.0, connect=5.0),
        follow_redirects=True, http2=False)
    return supa


def _identity(supa) -> str:
    """A disposable anonymous identity, created the way the app creates one."""
    import urllib.request, json  # noqa: PLC0415, E401

    anon = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
    req = urllib.request.Request(
        f"{STAGING_URL}/auth/v1/signup", method="POST",
        data=json.dumps({"data": {}}).encode())
    req.add_header("Content-Type", "application/json")
    req.add_header("apikey", anon)
    with urllib.request.urlopen(req, timeout=30) as r:
        body = json.loads(r.read())
    uid = (body.get("user") or {}).get("id")
    if not uid:
        raise SystemExit("REFUSING: could not create an anonymous identity.")
    del supa
    return uid


async def run() -> int:  # noqa: PLR0915
    _load_env()

    import payway  # noqa: PLC0415

    if not payway.is_configured():
        print("REFUSING: no PayWay sandbox credentials in the staging file.")
        return 2

    # `main` is heavy (it imports the whole engine) but it is also where
    # `billing` resolves its database from, so it is imported for real and its
    # client is replaced with a hardened service-role one.
    supa = _service_client()
    fake_main = types.ModuleType("main")
    fake_main.supa = supa
    sys.modules["main"] = fake_main

    import billing  # noqa: PLC0415
    import pwa_staging_payments as seam  # noqa: PLC0415

    if billing.effective_trial_credits() != 1:
        print("REFUSING: effective trial is not 1 — ACCOUNT_SYSTEM_ENABLED "
              "not honoured.")
        return 2

    cfg = payway.load_config()
    print(f"target      : {STAGING_REF}  +  {cfg.base_url}  (sandbox)")

    user_id = _identity(supa)
    print(f"identity    : {user_id[:8]}...{user_id[-4:]}")

    # ── a REAL transaction at the REAL gateway ─────────────────────────────
    section("a real PayWay transaction")
    attempt = str(uuid.uuid4())
    view = await seam.start_checkout(user_id=user_id, sku="pack_10",
                                     attempt_key=attempt)
    tran_id = view["tran_id"]
    check("the gateway opened a checkout for a canonical Web product",
          view["state"] == seam.AWAITING_PAYMENT
          and "payway.com.kh" in (view["checkout_url"] or ""),
          f"{view['state']} {view['checkout_url'][:48]}")
    check("the checkout is hosted by ABA, not drawn by Ayden",
          (view["checkout_url"] or "").startswith(
              "https://checkout-sandbox.payway.com.kh/"),
          view["checkout_url"][:60])
    check("the amount is the CATALOGUE price", view["amount"] == 4.99,
          str(view["amount"]))
    check("the credits are the CATALOGUE credits", view["credits"] == 10,
          str(view["credits"]))
    print(f"  INFO  tran_id {tran_id} — real, unpaid, and it will stay unpaid")

    # The canonical order exists, PENDING, before anything is granted.
    orders = await asyncio.to_thread(
        lambda: supa.table("orders").select("id, status, provider, amount, currency")
        .eq("idempotency_key", seam.order_key_for(tran_id)).execute())
    order_rows = getattr(orders, "data", None) or []
    check("a canonical PENDING order exists on the khqr rail",
          len(order_rows) == 1 and order_rows[0]["status"] == "PENDING"
          and order_rows[0]["provider"] == "khqr", str(order_rows))

    # ── the ONE simulated step ─────────────────────────────────────────────
    section("SIMULATED: the gateway answers APPROVED")
    print("  Everything else below is real. This replaces `check_transaction`\n"
          "  with the sandbox's OWN approved envelope shape, and nothing else.")

    approved_envelope = {
        # Verbatim nesting, as measured on 2026-08-19.
        "data": {"payment_status_code": 0, "payment_status": "APPROVED",
                 "total_amount": 4.99, "payment_amount": 4.99,
                 "payment_currency": "USD", "apv": "832865",
                 "refund_amount": 0, "discount_amount": 0,
                 "transaction_date": "2026-08-19 02:00:00"},
        "status": {"code": "00", "message": "Success!", "tran_id": tran_id},
    }

    real_post = payway._post  # noqa: SLF001
    calls = {"n": 0}

    async def _approved_post(_cfg, path, _body):  # noqa: ANN001
        if path != payway.PATH_CHECK_TRANSACTION:
            raise AssertionError(f"only check-transaction may be simulated, got {path}")
        calls["n"] += 1
        return approved_envelope

    payway._post = _approved_post  # noqa: SLF001
    try:
        # ── ABA10 ──────────────────────────────────────────────────────────
        section("ABA10  approved -> exactly one grant")
        row = await seam._load(tran_id)  # noqa: SLF001
        settled = await seam.verify_and_settle(row, force=True)
        check("ABA10 the transaction reaches GRANTED",
              settled["state"] == seam.GRANTED, str(settled.get("state")))
        check("ABA10 the approval code is recorded",
              settled.get("approval_code") == "832865",
              str(settled.get("approval_code")))

        ledger = await asyncio.to_thread(
            lambda: supa.table("ledger_entries")
            .select("entry_type, available_delta, pass_id, reference_id")
            .eq("user_id", user_id).eq("entry_type", "GRANT").execute())
        grants = getattr(ledger, "data", None) or []
        check("ABA10 exactly ONE GRANT row exists in the real ledger",
              len(grants) == 1, str(grants))
        check("ABA10 it credited the CATALOGUE credits",
              grants and grants[0]["available_delta"] == 10, str(grants))
        check("ABA10 it is scoped to a pass bucket, not the free one",
              grants and grants[0]["pass_id"], str(grants))

        orders = await asyncio.to_thread(
            lambda: supa.table("orders").select("id, status")
            .eq("idempotency_key", seam.order_key_for(tran_id)).execute())
        order_rows = getattr(orders, "data", None) or []
        check("ABA10 the SAME order moved PENDING -> PAID (one row, not two)",
              len(order_rows) == 1 and order_rows[0]["status"] == "PAID",
              str(order_rows))

        payments = await asyncio.to_thread(
            lambda: supa.table("payments")
            .select("provider, provider_transaction_id, status")
            .eq("provider_transaction_id", tran_id).execute())
        pay_rows = getattr(payments, "data", None) or []
        check("ABA10 a payment row records the real PayWay transaction id",
              len(pay_rows) == 1 and pay_rows[0]["provider"] == "khqr"
              and pay_rows[0]["status"] == "SUCCESS", str(pay_rows))

        # ── ABA11 ──────────────────────────────────────────────────────────
        section("ABA11  duplicate notifications -> still exactly one grant")
        for _ in range(4):
            fresh = await seam._load(tran_id)  # noqa: SLF001
            await seam.verify_and_settle(fresh, force=True)
        ledger = await asyncio.to_thread(
            lambda: supa.table("ledger_entries").select("id")
            .eq("user_id", user_id).eq("entry_type", "GRANT").execute())
        check("ABA11 four more settlements credited NOTHING further",
              len(getattr(ledger, "data", None) or []) == 1,
              str(getattr(ledger, "data", None)))
        check("ABA11 a settled transaction is not re-asked of the gateway",
              calls["n"] == 1, f"{calls['n']} check-transaction calls")

        # ── ABA15/16/17 ────────────────────────────────────────────────────
        section("ABA15/16/17  the entitlement the browser will read")
        import pwa_staging_billing as pwa_billing  # noqa: PLC0415

        decision, gate = await pwa_billing.resolve(user_id=user_id)
        ctx = pwa_billing.PwaBillingContext(
            user_id=user_id, intent_id="", tier=decision.tier,
            is_free=decision.consumes_free_quota,
            watermark=not decision.clean_watermark and not gate.has_active_pass,
            free_credits=gate.free_credits, pass_credits=gate.pass_credits,
            total_credits=gate.total_credits, has_active_pass=gate.has_active_pass)

        check("ABA15 the entitlement now reports an ACTIVE pass",
              ctx.has_active_pass, str(ctx.public_state))
        check("ABA15 the pass carries exactly the credits bought",
              ctx.pass_credits == 10, str(ctx.public_state))
        check("ABA16 generation is allowed", gate.allow, str(gate.reason))
        check("ABA16 the access source is the measured PASS, not a role",
              ctx.access_source == "pass", ctx.access_source)
        check("ABA17 the next render is NOT watermarked", not ctx.watermark,
              str(ctx.public_state))

        # And it is really spendable, through the canonical atomic gate.
        hold = await billing.try_hold(
            user_id=user_id, intent_id=f"payway-probe-{tran_id}",
            tier=ctx.tier, supa=supa)
        check("ABA16 billing_try_hold grants the right to generate",
              hold.get("granted") is True, str(hold))
        check("ABA16 the debit landed on the PURCHASED pass bucket",
              hold.get("bucket") == "pass", str(hold))
        check("ABA16 the balance dropped by exactly one",
              int(hold.get("total_after") or -1) == 9, str(hold))
    finally:
        payway._post = real_post  # noqa: SLF001

    # The transaction stays unpaid at ABA and expires there on its own; the QR
    # was never shown to anyone. Nothing was charged, and nothing needs undoing.
    section("residue")
    print(f"  INFO  one real UNPAID sandbox transaction ({tran_id}) will expire "
          f"at PayWay\n        on its own lifetime. No money moved.")

    print(f"\n{'=' * 72}")
    if _failed:
        print(f"FAILURES {len(_failed)} / {len(_passed) + len(_failed)}")
        for name in _failed:
            print(f"  - {name}")
        return 1
    print(f"GRANT CHAIN PROVEN ({len(_passed)} assertions) — the only unproven "
          f"step is the money itself")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
