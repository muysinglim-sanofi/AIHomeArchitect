"""ABA01-ABA18 — the KHQR payment path, against the RUNNING backend.

What this file is
-----------------
The live probe. Real HTTP to `127.0.0.1:8000`, real Supabase anonymous
identities, the real Billing Engine on the real staging Postgres. The only thing
it cannot supply is ABA itself, and it says so rather than pretending:

    credentials present  -> the FULL matrix runs, including a real PayWay
                            transaction, a real Check Transaction, and a real
                            grant. The one step no code can automate — a human
                            paying the QR in the ABA sandbox app — is waited for,
                            with a deadline, and reported honestly if it does not
                            happen.
    credentials absent   -> the matrix that does not need ABA still runs
                            (fail-closed, auth, tampering, ownership), and the
                            rest is reported BLOCKED, never PASS.

Why "blocked" and not "skipped"
-------------------------------
A skipped test reads like an absent test. These are neither: they are checks
that CANNOT be answered until ABA whitelists this deployment, and the report is
supposed to make that the visible fact rather than a footnote.

Run:  cd backend && PYTHONPATH=. python pwa_staging_payway_e2e.py
      (the staging backend must already be running: python run_pwa_staging.py)

Safe: staging only, disposable identities, sandbox merchant only. Nothing here
can reach production — `run_pwa_staging` refuses to start against it, and
`payway.load_config` refuses any environment but `sandbox`.
"""
from __future__ import annotations

import json
import pathlib
import sys
import time
import urllib.error
import urllib.request
import uuid

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):  # pragma: no cover
        pass

STAGING_REF = "eedcahzekpgxvvfxufbk"
SUPA = f"https://{STAGING_REF}.supabase.co"
API = "http://127.0.0.1:8000"

#: How long to wait for a human to pay the sandbox QR before reporting BLOCKED.
#: Long enough to open ABA Mobile and scan; short enough that an unattended run
#: still finishes.
_PAY_WAIT_S = 180

_PASS: list[str] = []
_FAIL: list[str] = []
_BLOCKED: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (_PASS if ok else _FAIL).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  -- {detail}'}")


def blocked(label: str, why: str) -> None:
    _BLOCKED.append(f"{label} ({why})")
    print(f"  [BLK ] {label}  -- {why}")


def section(title: str) -> None:
    print(f"\n== {title} " + "=" * max(0, 60 - len(title)))


def _secret(name: str) -> str:
    """Read ONE value from the ignored staging file. Never printed."""
    for raw in (HERE / ".env.pwa-staging.local").read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith(name) and "=" in line:
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return ""


def _http(url: str, *, method: str = "GET", body=None, token: str | None = None,
          apikey: str | None = None, headers: dict | None = None,
          timeout: int = 60) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        req.add_header(key, value)
    if apikey:
        req.add_header("apikey", apikey)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw or b"{}")
        except Exception:  # noqa: BLE001
            return e.code, {"raw": raw[:200].decode("utf-8", "replace")}
    except Exception as e:  # noqa: BLE001
        return 0, {"transport": type(e).__name__}


def _detail(payload: dict) -> dict:
    d = payload.get("detail")
    return d if isinstance(d, dict) else payload


def _identity(anon_key: str) -> tuple[str, str]:
    st, sess = _http(f"{SUPA}/auth/v1/signup", method="POST", body={"data": {}},
                     apikey=anon_key)
    token = sess.get("access_token") or ""
    uid = (sess.get("user") or {}).get("id") or ""
    if not token or not uid:
        raise SystemExit(f"REFUSING: no anonymous session ({st} {sess})")
    return token, uid


def main() -> int:  # noqa: PLR0915 — one linear narrative
    anon_key = _secret("SUPABASE_PUBLISHABLE_KEY")
    if not anon_key:
        print("REFUSING: SUPABASE_PUBLISHABLE_KEY missing from the staging file.")
        return 2

    print(f"target      : {STAGING_REF}.supabase.co  +  {API}  (staging)")
    st, health = _http(f"{API}/pwa/staging/health")
    if st != 200:
        print(f"REFUSING: the staging backend is not up ({st} {health}). "
              f"Start it with: python run_pwa_staging.py")
        return 2

    st, cfg = _http(f"{API}/pwa/staging/payments/config")
    configured = bool(cfg.get("configured"))
    print(f"payments    : provider={cfg.get('provider')} gateway={cfg.get('gateway')} "
          f"env={cfg.get('environment')} configured={configured} "
          f"callback={'yes' if cfg.get('callback_configured') else 'POLL-ONLY'}")

    token, uid = _identity(anon_key)
    print(f"identity    : {uid[:8]}...{uid[-4:]}")

    # ── the seam the client reads ───────────────────────────────────────────
    section("ABA00  the server owns the answer to 'can I buy?'")
    st, ent = _http(f"{API}/pwa/staging/entitlement", token=token)
    check("ABA00 the entitlement carries a SERVER-owned payment block",
          st == 200 and isinstance(ent.get("payment"), dict), json.dumps(ent)[:180])
    payment_block = ent.get("payment") or {}
    check("ABA00 the client is told the RAIL, not the gateway brand",
          payment_block.get("provider") in ("khqr", "none"),
          str(payment_block))
    check("ABA00 `configured` agrees with the payments endpoint",
          bool(payment_block.get("configured")) == configured, str(payment_block))

    products = ent.get("products") or []
    web = [p for p in products if p.get("web_enabled")]
    store = [p for p in products if p.get("store_only")]
    check("ABA00 the canonical catalogue offers web-sellable credit packs",
          len(web) >= 1 and all(p.get("duration_days") is None for p in web),
          json.dumps(web)[:200])
    check("ABA00 the subscription passes stay app-store products",
          len(store) == 2, json.dumps([p.get("sku") for p in store]))
    sku = (web[0] if web else {}).get("sku") or "pack_10"
    price = (web[0] if web else {}).get("price_usd")
    credits = (web[0] if web else {}).get("credits")
    print(f"  INFO  buying {sku}: {credits} spaces for ${price}")

    # ── everything that does not need ABA ───────────────────────────────────
    section("ABA02/03/18  the browser cannot name a price or an entitlement")

    def checkout(body: dict, *, tok: str | None = token) -> tuple[int, dict]:
        return _http(f"{API}/pwa/staging/payments/checkout", method="POST",
                     body=body, token=tok)

    st, res = checkout({"sku": sku, "attempt_key": "x"})
    check("ABA02 a too-short attempt key is rejected by the model", st == 422,
          f"{st} {json.dumps(res)[:140]}")

    for field, value in (("amount", 0.01), ("credits", 99999),
                         ("price_usd", 0), ("currency", "KHR")):
        st, res = checkout({"sku": sku, "attempt_key": str(uuid.uuid4()),
                            field: value})
        check(f"ABA02/03 a body carrying `{field}` is REJECTED, not ignored",
              st == 422, f"{st} {json.dumps(res)[:140]}")

    st, res = checkout({"sku": "weekly_pass", "attempt_key": str(uuid.uuid4())})
    check("ABA18 an app-store product cannot be bought on the web",
          st == 409 and _detail(res).get("error_code") == "PRODUCT_NOT_WEB_SELLABLE",
          f"{st} {json.dumps(res)[:160]}")

    st, res = checkout({"sku": "not_a_product", "attempt_key": str(uuid.uuid4())})
    check("ABA18 an invented sku cannot be bought",
          st == 404 and _detail(res).get("error_code") == "UNKNOWN_PRODUCT",
          f"{st} {json.dumps(res)[:160]}")

    st, res = checkout({"sku": sku, "attempt_key": str(uuid.uuid4())}, tok=None)
    check("ABA18 an unauthenticated checkout is refused", st == 401, str(st))

    st, res = _http(f"{API}/pwa/staging/payments/order/A0000000000000000000",
                    token=token)
    check("ABA08 an unknown transaction id is refused", st == 404, str(st))

    section("ABA07/08  the callback is not a way in")
    st, res = _http(f"{API}/pwa/staging/payments/payway/callback", method="POST",
                    body={"tran_id": "A0000000000000000000", "apv": "000000",
                          "status": "0"})
    if configured:
        check("ABA07 an UNSIGNED pushback is rejected", st == 401,
              f"{st} {json.dumps(res)[:160]}")
        st, res = _http(f"{API}/pwa/staging/payments/payway/callback",
                        method="POST",
                        body={"tran_id": "A0000000000000000000", "apv": "000000",
                              "status": "0"},
                        headers={"X-PayWay-Hmac-Sha512": "bm90LWEtc2lnbmF0dXJl"})
        check("ABA07 a WRONG signature is rejected", st == 401,
              f"{st} {json.dumps(res)[:160]}")
    else:
        check("ABA07 with no credentials the callback endpoint refuses outright",
              st == 503, f"{st} {json.dumps(res)[:160]}")

    # ── the part that needs ABA ─────────────────────────────────────────────
    if not configured:
        section("ABA01/05/06/10-17  BLOCKED — no sandbox credentials")
        print("  The adapter is fail-closed and says so: `/payments/config` "
              "reports configured=false,\n  the paywall renders 'payments are "
              "not open yet', and a checkout answers 503.")
        st, res = checkout({"sku": sku, "attempt_key": str(uuid.uuid4())})
        check("ABA-FC a checkout with no credentials is 503, never a fake checkout",
              st == 503 and _detail(res).get("error_code") == "PAYMENTS_UNAVAILABLE",
              f"{st} {json.dumps(res)[:160]}")
        for label in ("ABA01 PayWay transaction created",
                      "ABA05 a PayWay-hosted checkout url came back",
                      "ABA06 the answer mode is recorded",
                      "ABA10 Check Transaction approved -> exactly one grant",
                      "ABA11 duplicate callback -> exactly one grant",
                      "ABA15 the entitlement refreshes after the grant",
                      "ABA16 the purchased pass allows the next generation",
                      "ABA17 the paid generation is not watermarked"):
            blocked(label, "PAYWAY_MERCHANT_ID / PAYWAY_API_KEY absent")
        return _report()

    section("ABA01/05/06  a real PayWay transaction")
    attempt = str(uuid.uuid4())
    st, order = checkout({"sku": sku, "attempt_key": attempt})
    if st != 200:
        detail = _detail(order)
        check("ABA01 a canonical Web product produces a PayWay transaction",
              False, f"{st} {json.dumps(detail)[:220]}")
        if detail.get("reason") in ("QR_REFUSED",) or st == 502:
            print("\n  NOTE  PayWay refused the request. Error code 6 in the "
                  "gateway log means this\n        machine's egress IP is not "
                  "whitelisted on the sandbox merchant — that is an\n        "
                  "ABA-side action, not a code defect.")
        return _report()

    tran_id = order.get("tran_id") or ""
    check("ABA01 a canonical Web product produces a PayWay transaction",
          bool(tran_id) and order.get("state") == "AWAITING_PAYMENT",
          json.dumps({k: v for k, v in order.items()
                      if k not in ("qr_image", "qr_string")})[:260])
    check("ABA01 the tran_id fits PayWay's 20-character limit",
          len(tran_id) <= 20, f"{len(tran_id)}: {tran_id}")
    check("ABA02 the amount the server opened is the CATALOGUE price",
          abs(float(order.get("amount") or 0) - float(price)) < 0.005,
          f"{order.get('amount')} vs {price}")
    check("ABA03 the credits are the CATALOGUE credits",
          int(order.get("credits") or 0) == int(credits),
          f"{order.get('credits')} vs {credits}")
    checkout_url = order.get("checkout_url") or ""
    check("ABA05 a PayWay-hosted checkout url came back",
          checkout_url.startswith("https://"), checkout_url or "empty")
    check("ABA05 the checkout is on ABA's own domain, never on Ayden's",
          "payway.com.kh" in checkout_url, checkout_url)
    check("ABA05 it is the SANDBOX checkout host",
          "checkout-sandbox.payway.com.kh" in checkout_url, checkout_url)
    check("ABA06 the answer mode is recorded",
          order.get("checkout_mode") in ("redirect", "json"),
          str(order.get("checkout_mode")))
    # ABA renders the payment options — including ABA Mobile — on its own page.
    # A deeplink is only returned when this deployment pins abapay_khqr_deeplink,
    # so its absence is a configuration fact, not a failure.
    check("ABA06 Ayden does not draw ABA's payment screen itself",
          not order.get("qr_image"),
          "a QR image came back — the deprecated rail is still live")

    print(f"\n  OPEN THIS to continue the live matrix (ABA's own checkout, sandbox only):")
    print(f"    {checkout_url}")
    if order.get("deeplink"):
        print(f"    {order.get('deeplink')}")

    section("ABA04/12/13  the same purchase, again and again")
    st, again = checkout({"sku": sku, "attempt_key": attempt})
    check("ABA04 a repeat submit returns the SAME transaction",
          again.get("tran_id") == tran_id, str(again.get("tran_id")))
    check("ABA04 the repeat did NOT issue a second QR",
          again.get("qr_string") == order.get("qr_string"))

    st, open_order = _http(f"{API}/pwa/staging/payments/open", token=token)
    check("ABA12 an F5 restores the order from the SERVER",
          open_order.get("open") is True and open_order.get("tran_id") == tran_id,
          json.dumps({k: v for k, v in open_order.items()
                      if k != 'qr_image'})[:200])
    check("ABA13 the order is durable — nothing about it lives in a process",
          open_order.get("qr_string") == order.get("qr_string"))

    other_token, _ = _identity(anon_key)
    st, res = _http(f"{API}/pwa/staging/payments/order/{tran_id}",
                    token=other_token)
    check("ABA18 another identity cannot even SEE this transaction", st == 404,
          str(st))
    st, res = _http(f"{API}/pwa/staging/payments/open", token=other_token)
    check("ABA18 another identity has no open order", res.get("open") is False,
          str(res))

    section("ABA10/14  waiting for the real payment")
    print(f"  Polling for up to {_PAY_WAIT_S}s. Pay the QR above in the ABA "
          f"sandbox app.")
    deadline = time.time() + _PAY_WAIT_S
    state = order.get("state")
    polls = 0
    while time.time() < deadline:
        time.sleep(3)
        polls += 1
        st, now = _http(f"{API}/pwa/staging/payments/order/{tran_id}", token=token)
        state = now.get("state")
        if now.get("terminal"):
            break
        if polls % 5 == 0:
            print(f"    ...{int(deadline - time.time())}s left, state={state}")

    if state != "GRANTED":
        blocked("ABA10 Check Transaction approved -> exactly one grant",
                f"the sandbox QR was not paid within {_PAY_WAIT_S}s "
                f"(last state {state})")
        for label in ("ABA11 duplicate callback -> exactly one grant",
                      "ABA15 the entitlement refreshes after the grant",
                      "ABA16 the purchased pass allows the next generation",
                      "ABA17 the paid generation is not watermarked"):
            blocked(label, "depends on a paid sandbox transaction")
        check("ABA14 an unpaid transaction granted NOTHING",
              (_http(f"{API}/pwa/staging/entitlement", token=token)[1]
               .get("has_active_pass") is False), "a pass appeared without payment")
        return _report()

    check("ABA10 a paid transaction reaches GRANTED", True)

    section("ABA11/15/16/17  one grant, and an entitlement that moved")
    for _ in range(3):
        _http(f"{API}/pwa/staging/payments/order/{tran_id}", token=token)
    st, ent2 = _http(f"{API}/pwa/staging/entitlement", token=token)
    check("ABA15 the entitlement now reports an active pass",
          ent2.get("has_active_pass") is True, json.dumps(ent2)[:200])
    check("ABA15 the credits granted are the CATALOGUE credits, once",
          int(ent2.get("pass_credits") or 0) == int(credits),
          f"{ent2.get('pass_credits')} vs {credits}")
    check("ABA11 re-polling a settled payment does not credit again",
          int(ent2.get("pass_credits") or 0) == int(credits))
    check("ABA16 generation is allowed again", ent2.get("can_generate") is True,
          json.dumps(ent2)[:200])
    check("ABA17 the next render is NOT watermarked",
          ent2.get("watermarked") is False, json.dumps(ent2)[:200])
    check("ABA16 the access source is the measured PASS, not a role",
          ent2.get("access_source") == "pass", str(ent2.get("access_source")))

    return _report()


def _report() -> int:
    print(f"\n{'=' * 72}")
    print(f"PASS {len(_PASS)}   FAIL {len(_FAIL)}   BLOCKED {len(_BLOCKED)}")
    for name in _FAIL:
        print(f"  FAIL    - {name}")
    for name in _BLOCKED:
        print(f"  BLOCKED - {name}")
    print("=" * 72)
    return 1 if _FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
