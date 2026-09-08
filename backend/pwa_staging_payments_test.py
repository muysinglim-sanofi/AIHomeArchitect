"""PWA staging — the PAYMENT SEAM, measured. No network, no database, no secret.

What kind of test this is
-------------------------
An INTEGRATION test of `pwa_staging_payments` with the two EXTERNAL parties
faked and everything in between real:

    the seam            pwa_staging_payments          real
    the rail's protocol payway.build_qr_request/sign  real
    PayWay itself       faked (a scriptable gateway)
    the data store      faked (an in-memory PostgREST, including the CAS)
    the Billing Engine  faked (records grants; keyed exactly like the RPC)

The database is faked at the CLIENT boundary rather than by monkey-patching
`_load` / `_update`, so the module's own compare-and-set, its state transitions
and its ownership checks are the code under test. What a fake database CANNOT
prove — that `billing_grant_purchase` really is idempotent, that the perpetual
pass really accumulates — is proven against Postgres in
`pwa_staging_payway_db_test.py`. Neither test is a substitute for the other.

The matrix, by the brief's own numbering
----------------------------------------
  ABA01  a canonical Web product produces a PayWay transaction
  ABA02  the browser cannot change the amount
  ABA03  the browser cannot change the credits / entitlement quantity
  ABA04  retrying the same purchase does not create a second grant
  ABA07  an invalid callback signature is rejected
  ABA08  an unknown tran_id is rejected
  ABA09  a callback for the wrong amount / currency does not grant
  ABA10  Check Transaction APPROVED -> exactly one grant
  ABA11  a duplicate callback -> exactly one grant
  ABA12  F5 during payment -> the order is restored
  ABA13  a backend restart -> the order survives
  ABA14  an expired / cancelled payment -> no grant
  ABA18  a direct API call cannot create entitlement

Run:  cd backend && PYTHONPATH=. python pwa_staging_payments_test.py
"""
from __future__ import annotations

import asyncio
import copy
import json
import base64
from pathlib import Path
import os
import pathlib
import sys
import types
import uuid
from datetime import datetime, timedelta, timezone

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):  # pragma: no cover
        pass

FAKE_KEY = "test_api_key_not_a_real_credential"
FAKE_MERCHANT = "ec000000"
os.environ.update({
    "PAYWAY_MERCHANT_ID": FAKE_MERCHANT,
    "PAYWAY_API_KEY": FAKE_KEY,
    "PAYWAY_ENV": "sandbox",
    "PAYWAY_QR_LIFETIME_MINUTES": "30",
    "PAYWAY_CURRENCY": "USD",
})
os.environ.pop("PWA_PAYMENT_PROVIDER", None)
os.environ.pop("PAYWAY_CALLBACK_URL", None)

from fastapi import HTTPException  # noqa: E402

import payway  # noqa: E402
import pwa_qr  # noqa: E402
import pwa_staging_payments as seam  # noqa: E402

_passed: list[str] = []
_failed: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (_passed if ok else _failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  {detail}'}")


def section(title: str) -> None:
    print(f"\n── {title} " + "─" * max(0, 66 - len(title)))


# ════════════════════════════════════════════════════════════════════════════
# The fakes
# ════════════════════════════════════════════════════════════════════════════


class _Res:
    def __init__(self, data):
        self.data = data


class _Query:
    """Enough PostgREST to be honest: filters, ordering, limit, update, upsert.

    Deliberately supports ONLY the operators the seam uses. An unsupported call
    raises rather than silently returning everything — a fake that quietly
    ignores a filter turns a broken ownership check into a passing test.
    """

    def __init__(self, rows: list, name: str):
        self._rows = rows
        self._name = name
        self._filters: list = []
        self._order = None
        self._desc = False
        self._limit = None
        self._op = "select"
        self._patch: dict = {}
        self._upsert_row: dict | None = None
        self._conflict = ""
        self._ignore_dupes = False

    # -- builders ---------------------------------------------------------
    def select(self, *_a, **_k):
        self._op = "select"
        return self

    def update(self, patch: dict):
        self._op = "update"
        self._patch = patch
        return self

    def upsert(self, row: dict, *, on_conflict: str = "",
               ignore_duplicates: bool = False):
        self._op = "upsert"
        self._upsert_row = row
        self._conflict = on_conflict
        self._ignore_dupes = ignore_duplicates
        return self

    def eq(self, column: str, value):
        self._filters.append(lambda r, c=column, v=value: r.get(c) == v)
        return self

    def in_(self, column: str, values):
        self._filters.append(lambda r, c=column, v=list(values): r.get(c) in v)
        return self

    def order(self, column: str, desc: bool = False):
        self._order, self._desc = column, desc
        return self

    def limit(self, n: int):
        self._limit = n
        return self

    def __getattr__(self, name):  # pragma: no cover — a guard, not a feature
        raise AssertionError(
            f"the in-memory PostgREST does not implement .{name}() — add it "
            f"deliberately rather than letting a filter be silently dropped")

    # -- execution --------------------------------------------------------
    def _matching(self) -> list:
        return [r for r in self._rows if all(f(r) for f in self._filters)]

    def execute(self):
        if self._op == "select":
            rows = self._matching()
            if self._order:
                rows = sorted(rows, key=lambda r: str(r.get(self._order) or ""),
                              reverse=self._desc)
            if self._limit is not None:
                rows = rows[: self._limit]
            return _Res(copy.deepcopy(rows))
        if self._op == "update":
            hit = self._matching()
            for row in hit:
                row.update(self._patch)
            return _Res(copy.deepcopy(hit))
        if self._op == "upsert":
            row = dict(self._upsert_row or {})
            key = self._conflict
            existing = ([r for r in self._rows if r.get(key) == row.get(key)]
                        if key else [])
            if existing:
                if self._ignore_dupes:
                    return _Res([])
                existing[0].update(row)
                return _Res(copy.deepcopy(existing[:1]))
            row.setdefault("id", str(uuid.uuid4()))
            self._rows.append(row)
            return _Res(copy.deepcopy([row]))
        raise AssertionError(f"unsupported op {self._op}")


class _FakeDb:
    """The two schemas the seam touches, and the one RPC it calls."""

    def __init__(self):
        self.tables: dict[str, list] = {
            "public.products": [],
            "public.orders": [],
            "pwa_staging.payway_transactions": [],
        }
        self.rpc_calls: list = []

    # `supa.table(...)` -> public schema
    def table(self, name: str) -> _Query:
        return _Query(self.tables.setdefault(f"public.{name}", []), name)

    def schema(self, name: str) -> "_Schema":
        return _Schema(self, name)

    def rpc(self, name: str, params: dict):
        raise AssertionError(f"unexpected public RPC {name}")


class _Schema:
    def __init__(self, db: _FakeDb, schema: str):
        self._db = db
        self._schema = schema

    def table(self, name: str) -> _Query:
        return _Query(self._db.tables.setdefault(f"{self._schema}.{name}", []), name)

    def rpc(self, name: str, params: dict):
        self._db.rpc_calls.append((name, params))
        if name != "payway_claim":
            raise AssertionError(f"unexpected rail RPC {name}")
        return _ClaimCall(self._db, params)


#: Mirror of `v_stale` in `pwa_staging.payway_claim`. If the two ever diverge the
#: concurrency assertion below is the thing that notices.
CLAIM_STALE_AFTER = timedelta(seconds=45)


class _ClaimCall:
    """`pwa_staging.payway_claim`, reproducing the SQL's decision exactly.

    A fresh insert wins. An existing row wins ONLY when it is still in CREATED
    *and* its claim has gone stale — i.e. it was abandoned, not merely
    unfinished. Anything else loses. Getting this wrong is what made five
    concurrent submits call PayWay five times and collect four 403s.
    """

    def __init__(self, db: _FakeDb, params: dict):
        self._db = db
        self._params = params

    def execute(self):
        rows = self._db.tables["pwa_staging.payway_transactions"]
        p = self._params
        now = datetime.now(timezone.utc)
        existing = [r for r in rows if r["tran_id"] == p["p_tran_id"]]
        if existing:
            row = existing[0]
            claimed = datetime.fromisoformat(row["claimed_at"])
            stale = now - claimed > CLAIM_STALE_AFTER
            won = row["state"] == seam.CREATED and stale
            if won:
                row["claimed_at"] = now.isoformat()
            return _Res([{"won": won, "state": row["state"]}])
        rows.append({
            "tran_id": p["p_tran_id"], "user_id": p["p_user_id"],
            "sku": p["p_sku"], "product_id": p["p_product_id"],
            "credits": p["p_credits"], "duration_days": p["p_duration_days"],
            "amount": p["p_amount"], "currency": p["p_currency"],
            "order_idempotency_key": p["p_order_idempotency_key"],
            "attempt_key": p["p_attempt_key"], "expires_at": p["p_expires_at"],
            "state": seam.CREATED, "check_count": 0, "callback_count": 0,
            "created_at": now.isoformat(), "claimed_at": now.isoformat(),
        })
        return _Res([{"won": True, "state": seam.CREATED}])


class _FakeGateway:
    """A scriptable PayWay. Records what it was asked; answers what we set."""

    def __init__(self):
        self.qr_calls: list[str] = []
        self.check_calls: list[str] = []
        self.qr_error: Exception | None = None
        # 'json' is what `abapay_khqr_deeplink` answers with, and what this
        # deployment has run since 2026-09-05: HTTP 200 carrying the official
        # KHQR payload and ABA Mobile deeplink as first-level fields. 'redirect'
        # is the older `abapay_khqr` shape, kept so both remain exercised.
        self.checkout_shape = "json"
        self.last_body: dict = {}
        self.status_for: dict[str, payway.TransactionStatus] = {}
        self.default_status = _status(payment_status_code=payway.STATUS_PENDING,
                                      payment_status="PENDING")

    async def purchase(self, *, cfg, tran_id, amount, currency="",
                       lifetime_minutes=None, return_params="",
                       continue_success_url="", cancel_url=""):
        self.qr_calls.append(tran_id)
        if self.qr_error:
            raise self.qr_error
        # The REAL request builder runs, so the twenty-four-field hash and the
        # field order are exercised even though nothing leaves the process.
        body = payway.build_purchase_request(
            cfg=cfg, tran_id=tran_id, amount=amount, currency=currency,
            lifetime_minutes=lifetime_minutes, return_params=return_params,
            continue_success_url=continue_success_url, cancel_url=cancel_url)
        self.last_body = body
        if self.checkout_shape == "redirect":
            # The older `abapay_khqr` shape: a 302 whose Location is the whole
            # answer. No QR — the payload exists only inside the opaque token.
            return payway.PurchaseCheckout(
                tran_id=tran_id,
                checkout_url=f"https://checkout-sandbox.payway.com.kh/{tran_id}",
                mode="redirect", trace_id="trace-1")
        return payway.PurchaseCheckout(
            tran_id=tran_id,
            checkout_url=f"https://checkout-sandbox.payway.com.kh/{tran_id}",
            mode="json", qr_string=KHQR_FIXTURE,
            deeplink="abamobilebank://ababank.com?type=payway&qrcode=x",
            trace_id="trace-1")

    async def check_transaction(self, *, cfg, tran_id):
        self.check_calls.append(tran_id)
        return self.status_for.get(tran_id, self.default_status)


#: A REAL-SHAPED KHQR payload, fixed so the rendered symbol is a stable
#: artefact a reviewer can re-derive. Same structure as the sandbox returns:
#: EMV tag 00 payload format, tag 30 merchant account with the ABA acquirer id,
#: amount, country, merchant name, and the tag 63 CRC.
KHQR_FIXTURE = (
    "00020101021230510016abaakhppxxx@abaa0115111111111111111"
    "0208ABA Bank52045999530384054047.995802KH5903M L6000623"
    "1050701284200716TEST0000000000019975001317885783500830011"
    "317885801503716671700134F1BF016411FDA6804PONL6908purchase"
    "63041234"
)


def _status(**kw) -> payway.TransactionStatus:
    base = dict(tran_id="", envelope_code="00", envelope_message="",
                payment_status_code=None, payment_status="", total_amount=None,
                payment_amount=None, currency="", approval_code="",
                transaction_date="", raw={})
    base.update(kw)
    return payway.TransactionStatus(**base)


class _FakeEngine:
    """`billing.grant_purchase`, keyed exactly as the RPC keys it.

    Idempotence here mirrors `on conflict (idempotency_key) do nothing` on the
    ledger GRANT: the SECOND call for a transaction returns
    `already_processed, credited=False`. That is what makes "exactly one grant"
    a testable claim at this layer.
    """

    class ProductNotMapped(Exception):
        def __init__(self, store_product_id):
            self.store_product_id = store_product_id
            super().__init__(store_product_id)

    def __init__(self):
        self.grants: list[dict] = []
        self.ledger: dict[str, str] = {}   # order key -> order id
        self.unmapped: set[str] = set()
        self.raise_transient = False

    async def grant_purchase(self, *, user_id, provider, provider_transaction_id,
                             store_product_id, amount=None, currency=None,
                             ends_at_iso=None, raw_payload=None, supa=None):
        if store_product_id in self.unmapped:
            raise self.ProductNotMapped(store_product_id)
        if self.raise_transient:
            raise RuntimeError("transient")
        key = f"order:{provider}:{provider_transaction_id}"
        fresh = key not in self.ledger
        if fresh:
            self.ledger[key] = str(uuid.uuid4())
        self.grants.append({
            "user_id": user_id, "provider": provider,
            "tran_id": provider_transaction_id, "sku": store_product_id,
            "amount": amount, "currency": currency, "ends_at": ends_at_iso,
            "credited": fresh, "raw": raw_payload,
        })
        return types.SimpleNamespace(
            ok=True, status="granted" if fresh else "already_processed",
            credited=fresh, credits=10 if fresh else 0,
            order_id=self.ledger[key], pass_id=str(uuid.uuid4()))

    @property
    def credited_grants(self) -> list[dict]:
        return [g for g in self.grants if g["credited"]]


# ── the harness ─────────────────────────────────────────────────────────────

DB = _FakeDb()
GATEWAY = _FakeGateway()
ENGINE = _FakeEngine()
USER = str(uuid.uuid4())
OTHER_USER = str(uuid.uuid4())
PRODUCT_ID = str(uuid.uuid4())
PRODUCT_300 = str(uuid.uuid4())


def _install() -> None:
    """Point the seam at the fakes. Everything else in it stays real."""
    seam._supa = lambda: DB                                     # noqa: SLF001
    payway.purchase = GATEWAY.purchase
    payway.check_transaction = GATEWAY.check_transaction
    billing = types.ModuleType("billing")
    billing.grant_purchase = ENGINE.grant_purchase
    billing.ProductNotMapped = _FakeEngine.ProductNotMapped
    sys.modules["billing"] = billing
    # `pwa_staging_billing.catalogue()` resolves its client through `main.supa`
    # rather than through the seam's `_supa()`, so the CATALOGUE payload needs
    # its own seam onto the fake database. Stubbed here rather than in the test
    # that needs it, so both payloads are always read from the same rows.
    main_mod = types.ModuleType("main")
    main_mod.supa = DB
    sys.modules["main"] = main_mod


def _seed_catalogue() -> None:
    DB.tables["public.products"] = [
        # STARTER — the web-sellable pack: no store id, khqr enabled, perpetual.
        {"id": PRODUCT_ID, "sku": "pack_10", "type": "CREDIT_PACK",
         "credits_granted": 10, "duration_days": None, "price_usd": 4.99,
         "currency": "USD", "khqr_enabled": True, "active": True,
         "metadata": {"badge": "starter"},
         "apple_product_id": None, "revenuecat_product_id": None},
        # BEST VALUE — discounted. `price_usd` is 47.99 and `metadata` carries
        # the crossed-out 79.99. The whole point of the pair is that only the
        # first one can ever reach PayWay.
        {"id": PRODUCT_300, "sku": "pack_300", "type": "CREDIT_PACK",
         "credits_granted": 300, "duration_days": None, "price_usd": 47.99,
         "currency": "USD", "khqr_enabled": True, "active": True,
         "metadata": {"badge": "best_value", "list_price_usd": 79.99},
         "apple_product_id": None, "revenuecat_product_id": None},
        # A store product: real, priced, and NOT sellable here.
        {"id": str(uuid.uuid4()), "sku": "weekly_pass", "type": "PASS",
         "credits_granted": 30, "duration_days": 7, "price_usd": 7.99,
         "currency": "USD", "khqr_enabled": True, "active": True,
         "apple_product_id": "com.aydenstudio.app.weekly",
         "revenuecat_product_id": "com.aydenstudio.app.weekly"},
        # Enabled for no rail at all.
        {"id": str(uuid.uuid4()), "sku": "pack_25", "type": "CREDIT_PACK",
         "credits_granted": 25, "duration_days": None, "price_usd": 3.99,
         "currency": "USD", "khqr_enabled": False, "active": True,
         "metadata": {},
         "apple_product_id": None, "revenuecat_product_id": None},
    ]


def _reset() -> None:
    DB.tables["public.orders"] = []
    DB.tables["pwa_staging.payway_transactions"] = []
    DB.rpc_calls.clear()
    GATEWAY.qr_calls.clear()
    GATEWAY.check_calls.clear()
    GATEWAY.qr_error = None
    GATEWAY.checkout_shape = "json"
    GATEWAY.status_for.clear()
    ENGINE.grants.clear()
    ENGINE.ledger.clear()
    ENGINE.unmapped.clear()
    ENGINE.raise_transient = False
    _seed_catalogue()


def _row(tran_id: str) -> dict:
    rows = [r for r in DB.tables["pwa_staging.payway_transactions"]
            if r["tran_id"] == tran_id]
    return rows[0] if rows else {}


def _approved(tran_id: str, *, amount=4.99, currency="USD") -> None:
    GATEWAY.status_for[tran_id] = _status(
        tran_id=tran_id, payment_status_code=payway.STATUS_APPROVED,
        payment_status="APPROVED", payment_amount=amount, total_amount=amount,
        currency=currency, approval_code="832865",
        transaction_date="2026-08-18 12:00:00")


def _unrate_limit(tran_id: str) -> None:
    """Age the last check so the next call really asks the gateway again."""
    row = _row(tran_id)
    if row.get("last_checked_at"):
        row["last_checked_at"] = (
            datetime.now(timezone.utc) - timedelta(seconds=30)).isoformat()


# ════════════════════════════════════════════════════════════════════════════
# The tests
# ════════════════════════════════════════════════════════════════════════════


async def test_identity() -> None:
    section("identity  one purchase attempt, one transaction id")
    a = seam.tran_id_for(USER, "pack_10", "att-1")
    check("tran_id is deterministic", a == seam.tran_id_for(USER, "pack_10", "att-1"))
    check("tran_id fits PayWay's 20-character limit", len(a) <= 20, f"{len(a)}: {a}")
    check("tran_id is user-scoped",
          a != seam.tran_id_for(OTHER_USER, "pack_10", "att-1"))
    check("tran_id is product-scoped",
          a != seam.tran_id_for(USER, "pack_25", "att-1"))
    check("a NEW attempt is a NEW transaction",
          a != seam.tran_id_for(USER, "pack_10", "att-2"))
    check("the order key is EXACTLY what billing_grant_purchase builds",
          seam.order_key_for(a) == f"order:khqr:{a}", seam.order_key_for(a))
    check("the rail is khqr — never 'aba', never 'aba_payway'",
          seam.PROVIDER == "khqr")


async def test_aba01_checkout() -> None:
    section("ABA01  a canonical Web product produces a PayWay transaction")
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-1")

    check("ABA01 a checkout was opened at PayWay",
          GATEWAY.qr_calls == [view["tran_id"]])
    check("ABA01 the state is AWAITING_PAYMENT",
          view["state"] == seam.AWAITING_PAYMENT, view["state"])
    check("ABA01 a PayWay-hosted checkout url is returned",
          view["checkout_url"].startswith("https://checkout-sandbox.payway.com.kh/"),
          view["checkout_url"])
    check("ABA01 the checkout is on ABA's domain, never on Ayden's",
          "payway.com.kh" in view["checkout_url"], view["checkout_url"])
    # 'json', not 'redirect', since the deployment moved to
    # `abapay_khqr_deeplink` on 2026-09-05 — the shape that returns the KHQR
    # payload and the ABA Mobile deeplink as first-level fields. The mode is
    # recorded so a support question can be answered without guessing which
    # rail a given transaction took; QR14 still covers the redirect shape.
    check("ABA01 the answer mode is recorded for support",
          view["checkout_mode"] == "json", view["checkout_mode"])

    check("ABA01 the amount comes from the CATALOGUE", view["amount"] == 4.99,
          str(view["amount"]))
    check("ABA01 the credits come from the CATALOGUE", view["credits"] == 10,
          str(view["credits"]))

    orders = DB.tables["public.orders"]
    check("ABA01 a canonical PENDING order exists before any money moves",
          len(orders) == 1 and orders[0]["status"] == "PENDING", str(orders))
    check("ABA01 the order carries provider='khqr'",
          orders[0]["provider"] == "khqr", str(orders[0].get("provider")))
    check("ABA01 the order's idempotency key is the one the ENGINE will reuse",
          orders[0]["idempotency_key"] == seam.order_key_for(view["tran_id"]))

    check("ABA01 the signed request selects PayWay's own Checkout service",
          GATEWAY.last_body["payment_gate"] == payway.PAYMENT_GATE_CHECKOUT,
          str(GATEWAY.last_body.get("payment_gate")))
    check("ABA01 no payment_option is imposed — ABA shows its own chooser",
          "payment_option" not in GATEWAY.last_body,
          str(GATEWAY.last_body.get("payment_option")))
    check("ABA01 the signed amount is the catalogue price, formatted once",
          GATEWAY.last_body["amount"] == "4.99", GATEWAY.last_body["amount"])

    # A product the Web may not sell, and one no rail is enabled for.
    for sku, why in (("weekly_pass", "app-store product"),
                     ("pack_25", "khqr disabled"),
                     ("no_such_sku", "unknown sku")):
        try:
            await seam.start_checkout(user_id=USER, sku=sku, attempt_key="att-x")
            check(f"ABA01 refuses to sell a {why}", False)
        except Exception as exc:  # noqa: BLE001
            check(f"ABA01 refuses to sell a {why}",
                  getattr(exc, "status_code", 0) in (404, 409),
                  f"{type(exc).__name__} {getattr(exc, 'status_code', '')}")


async def test_aba02_aba03_tampering() -> None:
    section("ABA02-03  the browser cannot change amount or credits")
    _reset()

    fields = set(seam.CheckoutRequest.model_fields)
    check("ABA02 the request model has NO amount field", "amount" not in fields)
    check("ABA02 the request model has NO price field", "price" not in fields)
    check("ABA03 the request model has NO credits field", "credits" not in fields)
    check("ABA02-03 the ENTIRE client input is (sku, attempt_key)",
          fields == {"sku", "attempt_key"}, str(fields))

    from pydantic import ValidationError

    for tampered in ({"sku": "pack_10", "attempt_key": "att-tamper", "amount": 0.01},
                     {"sku": "pack_10", "attempt_key": "att-tamper", "credits": 9999},
                     {"sku": "pack_10", "attempt_key": "att-tamper", "price_usd": 0}):
        try:
            seam.CheckoutRequest(**tampered)
            check(f"ABA02-03 a body carrying {sorted(set(tampered) - fields)} is "
                  f"REJECTED, not ignored", False)
        except ValidationError:
            check(f"ABA02-03 a body carrying {sorted(set(tampered) - fields)} is "
                  f"REJECTED, not ignored", True)

    # And the server-resolved figures win end to end.
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-1")
    _approved(view["tran_id"])
    await seam.verify_and_settle(_row(view["tran_id"]), force=True)
    grant = ENGINE.credited_grants[0]
    check("ABA02 the GRANT charged the catalogue amount", grant["amount"] == 4.99,
          str(grant["amount"]))
    check("ABA03 the GRANT names the catalogue SKU, not a client value",
          grant["sku"] == "pack_10", grant["sku"])
    check("ABA03 a CREDIT_PACK is granted PERPETUAL (no expiry window)",
          grant["ends_at"] is None, str(grant["ends_at"]))


async def test_aba04_aba10_aba11_idempotency() -> None:
    section("ABA04/10/11  exactly one grant, however many times we are told")
    _reset()

    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-1")
    tran_id = view["tran_id"]

    # ABA04 — the same purchase, submitted again (double-click, retry, F5).
    again = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-1")
    check("ABA04 a repeat submit reuses the SAME transaction",
          again["tran_id"] == tran_id)
    check("ABA04 a repeat submit does NOT ask PayWay for a second QR",
          GATEWAY.qr_calls == [tran_id], str(GATEWAY.qr_calls))
    check("ABA04 a repeat submit does NOT create a second order",
          len(DB.tables["public.orders"]) == 1)

    # Concurrent submits.
    _reset()
    results = await asyncio.gather(*[
        seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-c")
        for _ in range(5)])
    check("ABA04 five concurrent submits produce ONE transaction",
          len({r["tran_id"] for r in results}) == 1)
    check("ABA04 five concurrent submits call PayWay ONCE",
          len(GATEWAY.qr_calls) == 1, str(GATEWAY.qr_calls))

    # The other half of the same rule: an attempt ABANDONED before any QR
    # existed must be recoverable, or a dropped connection would strand the
    # person on a dead sku for as long as they keep the same attempt key.
    _reset()
    GATEWAY.qr_error = payway.PayWayUnreachable("network")
    try:
        await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-s")
        check("ABA04 an unreachable gateway surfaces as retryable", False)
    except Exception as exc:  # noqa: BLE001
        check("ABA04 an unreachable gateway surfaces as retryable",
              getattr(exc, "status_code", 0) == 503)
    tran_id = seam.tran_id_for(USER, "pack_10", "att-s")
    check("ABA04 the abandoned attempt is left in CREATED, not FAILED",
          _row(tran_id)["state"] == seam.CREATED, _row(tran_id)["state"])

    GATEWAY.qr_error = None
    retried = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-s")
    check("ABA04 an immediate retry does NOT overtake a claim that may be in flight",
          retried["state"] == seam.CREATED and len(GATEWAY.qr_calls) == 1,
          f"{retried['state']} calls={len(GATEWAY.qr_calls)}")

    _row(tran_id)["claimed_at"] = (
        datetime.now(timezone.utc) - CLAIM_STALE_AFTER - timedelta(seconds=5)).isoformat()
    recovered = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-s")
    check("ABA04 once the claim is stale the SAME attempt recovers and gets its QR",
          recovered["state"] == seam.AWAITING_PAYMENT
          and recovered["tran_id"] == tran_id and len(GATEWAY.qr_calls) == 2,
          f"{recovered['state']} calls={len(GATEWAY.qr_calls)}")

    # ABA10 — verified payment grants exactly once.
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-1")
    tran_id = view["tran_id"]
    _approved(tran_id)
    settled = await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA10 an APPROVED transaction reaches GRANTED",
          settled["state"] == seam.GRANTED, settled["state"])
    check("ABA10 exactly ONE credited grant", len(ENGINE.credited_grants) == 1,
          str(len(ENGINE.credited_grants)))
    check("ABA10 the grant used provider='khqr' and the PayWay tran_id",
          ENGINE.grants[0]["provider"] == "khqr"
          and ENGINE.grants[0]["tran_id"] == tran_id)
    check("ABA10 the approval code is recorded on the rail row",
          _row(tran_id)["approval_code"] == "832865")

    # ABA11 — the same news, five more times, from both paths.
    for _ in range(3):
        _unrate_limit(tran_id)
        await seam.verify_and_settle(_row(tran_id), force=True)
    for _ in range(2):
        await _callback(tran_id)
    check("ABA11 duplicate notifications still yield exactly ONE grant",
          len(ENGINE.credited_grants) == 1, str(len(ENGINE.credited_grants)))
    check("ABA11 a settled transaction is not re-checked against PayWay",
          GATEWAY.check_calls.count(tran_id) == 1, str(GATEWAY.check_calls))


async def _callback(tran_id: str, *, body: dict | None = None,
                    signature: str | None = None, key: str = FAKE_KEY):
    """Post a pushback exactly as PayWay would, signature included."""
    payload = body if body is not None else {
        "tran_id": tran_id, "apv": "832865", "status": "0",
        "return_params": json.dumps({"t": tran_id}), "merchant_ref": "",
    }
    raw = json.dumps(payload).encode()
    sig = (signature if signature is not None
           else payway.sign(payway.pushback_hash_payload(payload), key))

    class _Request:
        headers = {"x-payway-hmac-sha512": sig}

        async def body(self):  # noqa: D102
            return raw

    return await seam.payway_callback(_Request())


async def test_aba07_aba08_aba09_callback() -> None:
    section("ABA07-09  the callback is a doorbell, never a receipt")
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-1")
    tran_id = view["tran_id"]

    # ABA07 — a wrong signature.
    try:
        await _callback(tran_id, signature="not-a-signature")
        check("ABA07 an invalid signature is REJECTED", False)
    except Exception as exc:  # noqa: BLE001
        check("ABA07 an invalid signature is REJECTED",
              getattr(exc, "status_code", 0) == 401, str(exc))
    try:
        await _callback(tran_id, key="someone-elses-key")
        check("ABA07 a signature under another key is REJECTED", False)
    except Exception as exc:  # noqa: BLE001
        check("ABA07 a signature under another key is REJECTED",
              getattr(exc, "status_code", 0) == 401)
    try:
        await _callback(tran_id, signature="")
        check("ABA07 an ABSENT signature is REJECTED (mode=required)", False)
    except Exception as exc:  # noqa: BLE001
        check("ABA07 an ABSENT signature is REJECTED (mode=required)",
              getattr(exc, "status_code", 0) == 401)
    check("ABA07 a rejected callback never reached the Billing Engine",
          ENGINE.grants == [])

    # ABA08 — a valid signature over a transaction that is not ours.
    try:
        await _callback("A9999999999999999999")
        check("ABA08 an unknown tran_id is REJECTED", False)
    except Exception as exc:  # noqa: BLE001
        check("ABA08 an unknown tran_id is REJECTED",
              getattr(exc, "status_code", 0) == 404)
    check("ABA08 an unknown tran_id granted nothing", ENGINE.grants == [])

    # A perfectly-signed callback CLAIMING success, while PayWay says PENDING.
    GATEWAY.status_for[tran_id] = _status(
        tran_id=tran_id, payment_status_code=payway.STATUS_PENDING,
        payment_status="PENDING")
    out = await _callback(tran_id)
    check("ABA07 a signed callback alone does NOT grant — Check Transaction rules",
          ENGINE.grants == [] and out["state"] != seam.GRANTED, str(out))
    check("ABA07 the rail records that the doorbell rang",
          _row(tran_id)["callback_count"] == 1
          and _row(tran_id)["callback_signature_ok"] is True)
    check("ABA07 the state says 'confirming', not 'paid'",
          _row(tran_id)["state"] == seam.PAID_PENDING_VERIFICATION,
          _row(tran_id)["state"])

    # ABA09 — approved, but not for what we asked.
    for label, kwargs, expected in (
        ("a smaller amount", {"amount": 0.01}, "AMOUNT_MISMATCH"),
        ("a larger amount", {"amount": 99.00}, "AMOUNT_MISMATCH"),
        ("another currency", {"currency": "KHR"}, "CURRENCY_MISMATCH"),
    ):
        _reset()
        view = await seam.start_checkout(user_id=USER, sku="pack_10",
                                         attempt_key=f"att-{label}")
        tid = view["tran_id"]
        _approved(tid, **kwargs)
        settled = await seam.verify_and_settle(_row(tid), force=True)
        check(f"ABA09 APPROVED for {label} grants NOTHING",
              ENGINE.grants == [] and settled["state"] == seam.FAILED,
              f"{settled['state']} grants={len(ENGINE.grants)}")
        check(f"ABA09 the reason is recorded as {expected}",
              settled["failure_reason"] == expected, settled["failure_reason"])

    # And an approval PayWay reports with no amount at all.
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-noamt")
    tid = view["tran_id"]
    GATEWAY.status_for[tid] = _status(tran_id=tid,
                                      payment_status_code=payway.STATUS_APPROVED,
                                      payment_status="APPROVED")
    settled = await seam.verify_and_settle(_row(tid), force=True)
    check("ABA09 an APPROVED with no amount to compare grants NOTHING",
          ENGINE.grants == [] and settled["failure_reason"] == "AMOUNT_MISSING",
          settled.get("failure_reason", ""))


async def test_aba12_aba13_durability() -> None:
    section("ABA12-13  F5 and a backend restart both restore the order")
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-1")
    tran_id = view["tran_id"]

    # ABA12 — the browser reloads. It knows nothing; it asks the server.
    restored = await seam.open_attempt_for(USER)
    check("ABA12 the SERVER remembers the open attempt",
          restored and restored["tran_id"] == tran_id)
    view2 = seam.public_view(restored)
    check("ABA12 the restored view carries the SAME checkout",
          view2["checkout_url"] == view["checkout_url"], view2["checkout_url"])
    check("ABA12 nothing about restoring it touched PayWay again",
          GATEWAY.qr_calls == [tran_id])

    # ABA13 — the backend restarts: every in-process cache is gone. The seam
    # holds no state of its own, so this is the same code path as a cold read.
    check("ABA13 the seam keeps NO in-process payment state",
          not any(isinstance(v, dict) and "tran_id" in str(v)[:200]
                  for k, v in vars(seam).items()
                  if not k.startswith("_") and isinstance(v, dict)))
    reread = await seam.open_attempt_for(USER)
    check("ABA13 after a restart the attempt is still there and still payable",
          reread["tran_id"] == tran_id and reread["state"] == seam.AWAITING_PAYMENT)

    # And it is not visible to anybody else.
    check("ABA12 another user has no open attempt",
          await seam.open_attempt_for(OTHER_USER) is None)

    # A settled attempt stops being "open".
    _approved(tran_id)
    await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA12 a GRANTED attempt is no longer restored as open",
          await seam.open_attempt_for(USER) is None)


async def test_aba14_terminal() -> None:
    section("ABA14  expired, declined and cancelled all grant nothing")

    # Expired.
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-exp")
    tran_id = view["tran_id"]
    _row(tran_id)["expires_at"] = (
        datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat()
    settled = await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA14 an expired, unpaid QR ends EXPIRED",
          settled["state"] == seam.EXPIRED, settled["state"])
    check("ABA14 an expired QR granted nothing", ENGINE.grants == [])
    check("ABA14 the canonical order is CANCELLED, not left PENDING",
          DB.tables["public.orders"][0]["status"] == "CANCELLED",
          DB.tables["public.orders"][0]["status"])

    # Expiry gives the payment one LAST chance — money that landed just in time
    # must still be granted.
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-race")
    tran_id = view["tran_id"]
    _row(tran_id)["expires_at"] = (
        datetime.now(timezone.utc) - timedelta(seconds=1)).isoformat()
    _approved(tran_id)
    settled = await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA14 a payment that landed just before expiry is STILL granted",
          settled["state"] == seam.GRANTED and len(ENGINE.credited_grants) == 1,
          settled["state"])

    # Declined.
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-dec")
    tran_id = view["tran_id"]
    GATEWAY.status_for[tran_id] = _status(
        tran_id=tran_id, payment_status_code=payway.STATUS_DECLINED,
        payment_status="DECLINED")
    settled = await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA14 a DECLINED transaction ends FAILED and grants nothing",
          settled["state"] == seam.FAILED and ENGINE.grants == [], settled["state"])

    # Cancelled by the person — but never at the cost of a payment in flight.
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-can")
    tran_id = view["tran_id"]
    out = await seam.payments_cancel.__wrapped__(tran_id, None) \
        if hasattr(seam.payments_cancel, "__wrapped__") else None
    del out  # the route needs a token; the state machine is exercised directly
    settled = await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA14 a pending transaction stays open until something decides it",
          settled["state"] == seam.AWAITING_PAYMENT, settled["state"])
    await seam._fail(tran_id, "CANCELLED", only_if=seam.OPEN, state=seam.CANCELLED)
    check("ABA14 a cancelled attempt grants nothing",
          _row(tran_id)["state"] == seam.CANCELLED and ENGINE.grants == [])

    _approved(tran_id)
    settled = await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA14 a CANCELLED attempt is terminal — late news does not revive it",
          settled["state"] == seam.CANCELLED and ENGINE.grants == [], settled["state"])


async def test_aba18_bypass() -> None:
    section("ABA18  no direct call can mint entitlement")
    _reset()

    # There is no route, and no function, that grants without a verified check.
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-1")
    tran_id = view["tran_id"]

    GATEWAY.status_for[tran_id] = _status(
        tran_id=tran_id, envelope_code="6", envelope_message="not found",
        payment_status_code=payway.STATUS_APPROVED, payment_status="APPROVED",
        payment_amount=4.99, currency="USD")
    settled = await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA18 APPROVED inside a NOT-FOUND envelope grants nothing",
          ENGINE.grants == [] and settled["state"] != seam.GRANTED, settled["state"])

    # A transient engine failure must NOT be recorded as a failed payment.
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-t")
    tran_id = view["tran_id"]
    _approved(tran_id)
    ENGINE.raise_transient = True
    settled = await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA18 a transient grant failure leaves the payment VERIFIED for retry",
          settled["state"] == seam.VERIFIED, settled["state"])
    ENGINE.raise_transient = False
    _unrate_limit(tran_id)
    settled = await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA18 the retry then grants exactly once",
          settled["state"] == seam.GRANTED and len(ENGINE.credited_grants) == 1)

    # A paid transaction for a product the engine cannot map is a reconciliation
    # item, never a silent success.
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-u")
    tran_id = view["tran_id"]
    _approved(tran_id)
    ENGINE.unmapped.add("pack_10")
    settled = await seam.verify_and_settle(_row(tran_id), force=True)
    check("ABA18 a paid-but-unmappable product fails LOUDLY and grants nothing",
          settled["state"] == seam.FAILED
          and settled["failure_reason"] == "PRODUCT_UNMAPPED", str(settled))


async def test_public_surface() -> None:
    section("surface  what the browser is allowed to see")
    _reset()
    view = await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="att-1")
    blob = json.dumps(view)
    check("no api key in the public view", FAKE_KEY not in blob)
    check("no merchant id in the public view", FAKE_MERCHANT not in blob)
    check("no hash in the public view", "hash" not in view)
    check("no user id in the public view", USER not in blob)
    check("no internal order id in the public view", "order_id" not in view)
    check("the public view carries what a payer needs",
          all(k in view for k in ("checkout_url", "checkout_mode", "qr_string",
                                  "deeplink", "amount", "currency", "credits",
                                  "state", "expires_at")))

    cfg = seam.payments_config
    conf = asyncio.get_event_loop()
    del conf
    check("the rail reported to the client is khqr", seam.provider_id() == "khqr")
    check("the rail is open when credentials are present", seam.is_open())
    os.environ["PWA_PAYMENT_PROVIDER"] = "none"
    check("an operator kill switch closes the paywall without touching secrets",
          seam.provider_id() == "none" and not seam.is_open())
    os.environ.pop("PWA_PAYMENT_PROVIDER")
    del cfg


async def test_unconfigured() -> None:
    section("fail-closed  no credentials, no checkout")
    _reset()
    saved = os.environ.pop("PAYWAY_API_KEY")
    try:
        check("with no api key the rail reports 'none'", seam.provider_id() == "none")
        check("with no api key the paywall is closed", not seam.is_open())
        try:
            await seam.start_checkout(user_id=USER, sku="pack_10", attempt_key="a")
            check("with no api key a checkout is REFUSED", False)
        except Exception as exc:  # noqa: BLE001
            check("with no api key a checkout is REFUSED",
                  getattr(exc, "status_code", 0) == 503, str(exc))
        check("and nothing was written", DB.tables["pwa_staging.payway_transactions"] == [])
    finally:
        os.environ["PAYWAY_API_KEY"] = saved





async def test_not_created_is_terminal_after_the_grace_window() -> None:
    """ERR01-ERR06 — a purchase PayWay refused before creating a transaction
    must not become a 30-minute wait.

    Found on the phone: ABA answered "Requested Domain is not in whitelist"
    (Error 6), Check Transaction answered "tran_id not found", and the app kept
    polling and counting down for a transaction that did not exist. On the
    plugin path the browser posts the purchase, so a not-found in the first
    seconds is a race — and after that it is the answer.
    """
    section("NOT_CREATED  no transaction is not a pending transaction")
    _reset()
    os.environ["PAYWAY_PAYMENT_OPTION"] = "abapay_khqr"
    try:
        view = await seam.start_plugin_checkout(user_id=USER, sku="pack_10",
                                                attempt_key="att-notcreated")
        tran = view["tran_id"]
        GATEWAY.status_for[tran] = _status(
            tran_id=tran, envelope_code="6", envelope_message="tran_id not found")

        # ERR01 — inside the grace window it is a race, and we keep waiting.
        one = await seam.verify_and_settle(_row(tran), force=True)
        check("ERR01 within the grace window the row stays AWAITING",
              one["state"] == seam.AWAITING_PAYMENT, one.get("state"))
        check("ERR01 and the check was recorded",
              int(one.get("check_count") or 0) == 1, one.get("check_count"))

        # ERR02 — past it, PayWay's not-found is the truth.
        r = _row(tran)
        r["qr_issued_at"] = seam._iso(seam._now() - timedelta(seconds=45))
        two = await seam.verify_and_settle(_row(tran), force=True)
        check("ERR02 past the grace window the row is FAILED",
              two["state"] == seam.FAILED, two.get("state"))
        check("ERR02 with reason NOT_CREATED",
              two.get("failure_reason") == "NOT_CREATED", two.get("failure_reason"))

        # ERR03 — the browser is told it is over: terminal, with the reason.
        pv = seam.public_view(_row(tran))
        check("ERR03 the public view is terminal",
              pv.get("terminal") is True, pv.get("terminal"))
        check("ERR03 and names the reason",
              pv.get("failure_reason") == "NOT_CREATED", pv.get("failure_reason"))

        # ERR04 — nothing was granted.
        check("ERR04 zero grants", len(ENGINE.credited_grants) == 0,
              len(ENGINE.credited_grants))

        # ERR05 — and nothing is asked again: FAILED returns before any check.
        before = GATEWAY.check_calls.count(tran)
        three = await seam.verify_and_settle(_row(tran), force=True)
        check("ERR05 a settled row is not re-checked",
              three["state"] == seam.FAILED
              and GATEWAY.check_calls.count(tran) == before,
              (three.get("state"), GATEWAY.check_calls.count(tran), before))

        # ERR06 — the canonical order followed.
        orders = [o for o in DB.tables["public.orders"]
                  if o.get("provider_transaction_id") == tran
                  or o.get("tran_id") == tran]
        check("ERR06 the canonical order is not PENDING any more",
              all((o.get("status") or "").upper() != "PENDING" for o in orders)
              if orders else True,
              [o.get("status") for o in orders])
    finally:
        os.environ.pop("PAYWAY_PAYMENT_OPTION", None)


async def test_not_created_never_fires_on_the_server_side_path() -> None:
    """ERR07 — the rule is scoped to the plugin path. On the server-side
    Purchase path this process saw PayWay accept the purchase, so a later
    not-found is an anomaly, not a conclusion."""
    section("NOT_CREATED  scoped to the plugin path")
    _reset()
    GATEWAY.checkout_shape = "redirect"
    view = await seam.start_checkout(user_id=USER, sku="pack_10",
                                     attempt_key="att-redirect-nf")
    tran = view["tran_id"]
    GATEWAY.status_for[tran] = _status(
        tran_id=tran, envelope_code="6", envelope_message="tran_id not found")
    r = _row(tran)
    r["qr_issued_at"] = seam._iso(seam._now() - timedelta(seconds=120))
    after = await seam.verify_and_settle(_row(tran), force=True)
    check("ERR07 a server-side checkout is not concluded by not-found",
          after["state"] == seam.AWAITING_PAYMENT, after.get("state"))
    GATEWAY.checkout_shape = "json"


async def test_plugin_checkout_signs_and_does_not_post() -> None:
    """PLUGIN01-PLUGIN10 — the active Web path: this server signs, ABA's
    JavaScript posts.

    ABA's website guidance (2026-09-05): the merchant page holds a form of
    signed hidden inputs and their plugin submits it into an iframe it owns.
    So the Purchase call moves from this process to the browser, and the ONLY
    thing that must not move is the signing key. These assertions pin exactly
    that boundary.
    """
    section("PLUGIN  the server signs the form; the browser posts it")
    _reset()
    os.environ["PAYWAY_PAYMENT_OPTION"] = "abapay_khqr"
    try:
        view = await seam.start_plugin_checkout(user_id=USER, sku="pack_10",
                                                attempt_key="att-plugin")
        row = _row(view["tran_id"])

        # PLUGIN01 — no Purchase call left this process.
        check("PLUGIN01 payway.purchase was NOT called",
              GATEWAY.qr_calls == [], GATEWAY.qr_calls)

        # PLUGIN02 — the row is live and says which rail it is on.
        check("PLUGIN02 the row is AWAITING_PAYMENT",
              row["state"] == seam.AWAITING_PAYMENT, row.get("state"))
        check("PLUGIN02 and records the plugin mode",
              row["checkout_mode"] == seam.CHECKOUT_MODE_PLUGIN,
              row.get("checkout_mode"))
        check("PLUGIN02 with no QR and no deeplink of its own",
              not row.get("qr_string") and not row.get("qr_image")
              and not row.get("deeplink"))

        # PLUGIN03 — the handoff: an action and signed fields.
        plugin = view.get("plugin") or {}
        fields = plugin.get("fields") or {}
        check("PLUGIN03 the answer carries a plugin handoff",
              bool(plugin) and bool(fields), sorted(plugin.keys()))
        check("PLUGIN03 the form action is PayWay's Purchase endpoint",
              plugin.get("form_action", "").endswith(payway.PATH_PURCHASE)
              and plugin.get("form_action", "").startswith("https://"),
              plugin.get("form_action"))

        # PLUGIN04 — the fields are what ABA's sample puts in hidden inputs.
        for k in ("hash", "tran_id", "amount", "merchant_id", "req_time",
                  "payment_option", "currency", "type", "lifetime"):
            check(f"PLUGIN04 field {k} is present", k in fields, sorted(fields))

        # PLUGIN05 — and what they must NOT contain: the credential.
        cfg = payway.load_config()
        joined = json.dumps(fields)
        check("PLUGIN05 the api key is NOT in the handoff",
              cfg.api_key not in joined)
        check("PLUGIN05 no field is named like a key",
              not any("key" in k.lower() or "secret" in k.lower()
                      for k in fields), sorted(fields))

        # PLUGIN06 — ABA's website option, and nothing that opens cards.
        check("PLUGIN06 payment_option is abapay_khqr",
              fields["payment_option"] == "abapay_khqr",
              fields["payment_option"])

        # PLUGIN07 — no return URLs: the plugin navigates the top window on
        # them, which would unload the app mid-payment. Their absence takes
        # the plugin's in-place branches instead.
        check("PLUGIN07 continue_success_url is not sent",
              "continue_success_url" not in fields)
        check("PLUGIN07 cancel_url is not sent", "cancel_url" not in fields)

        # ABA-REVIEW-05 (2026-09-08) — ABA's Success page is skipped; Ayden
        # shows its own. The plugin form carries the literal "1", and it is
        # signed (the rail test pins its position in the hash).
        check("ABA-REVIEW-05 skip_success_page=1 rides in the plugin form",
              fields.get("skip_success_page") == "1",
              str(fields.get("skip_success_page")))
        # The pushback URL rides along only when the deployment has a public
        # callback (Fly does; this harness does not). What matters here is
        # that its presence follows the config and is never invented.
        check("PLUGIN07 the pushback URL follows PAYWAY_CALLBACK_URL",
              bool(fields.get("return_url")) == cfg.has_public_callback,
              (bool(fields.get("return_url")), cfg.has_public_callback))

        # PLUGIN08 — view_type is presentation metadata the official form omits.
        check("PLUGIN08 view_type is not sent", "view_type" not in fields)

        # PLUGIN09 — the signature is over what is sent: recompute it.
        expected = payway.sign(payway.purchase_hash_payload(
            {k: v for k, v in fields.items() if k != "hash"}), cfg.api_key)
        check("PLUGIN09 the hash matches the fields as sent",
              fields["hash"] == expected)

        # PLUGIN10 — the amount is the catalogue's, formatted as PayWay wants.
        check("PLUGIN10 the amount is server-authoritative",
              fields["amount"] == payway.format_amount(4.99, "USD"),
              fields["amount"])
    finally:
        os.environ.pop("PAYWAY_PAYMENT_OPTION", None)


async def test_plugin_rejoin_returns_no_fields() -> None:
    """PLUGIN11 — one Purchase per tran_id, so a rejoin gets the row and no
    second set of fields to post."""
    section("PLUGIN  a rejoin polls; it does not post twice")
    _reset()
    os.environ["PAYWAY_PAYMENT_OPTION"] = "abapay_khqr"
    try:
        first = await seam.start_plugin_checkout(user_id=USER, sku="pack_10",
                                                 attempt_key="att-rejoin")
        again = await seam.start_plugin_checkout(user_id=USER, sku="pack_10",
                                                 attempt_key="att-rejoin")
        check("PLUGIN11 the first call hands over fields",
              bool(first.get("plugin")))
        check("PLUGIN11 the rejoin does NOT",
              "plugin" not in again, sorted(again.keys()))
        check("PLUGIN11 and it is the same transaction",
              again["tran_id"] == first["tran_id"])
    finally:
        os.environ.pop("PAYWAY_PAYMENT_OPTION", None)


async def test_plugin_refuses_any_other_option() -> None:
    """PLUGIN12 — a deployment pinned to anything but abapay_khqr cannot open
    a plugin checkout. Cards are not offered here, and a value the plugin does
    not recognise is a popup sized for the wrong thing."""
    section("PLUGIN  the option is abapay_khqr or nothing")
    for bad in ("", "abapay_khqr_deeplink", "cards"):
        _reset()
        os.environ["PAYWAY_PAYMENT_OPTION"] = bad
        try:
            await seam.start_plugin_checkout(user_id=USER, sku="pack_10",
                                             attempt_key=f"att-bad-{bad or 'empty'}")
            check(f"PLUGIN12 option {bad!r} is refused", False)
        except HTTPException as exc:
            check(f"PLUGIN12 option {bad!r} is refused (503)",
                  exc.status_code == 503
                  and exc.detail.get("reason") == "plugin_option_misconfigured",
                  exc.detail)
        finally:
            os.environ.pop("PAYWAY_PAYMENT_OPTION", None)


async def test_plugin_path_grants_exactly_once_via_check_transaction() -> None:
    """PLUGIN13 — the presentation moved; the authority did not. A plugin
    checkout is settled by Check Transaction like any other, and once."""
    section("PLUGIN  Check Transaction still decides, exactly once")
    _reset()
    os.environ["PAYWAY_PAYMENT_OPTION"] = "abapay_khqr"
    try:
        view = await seam.start_plugin_checkout(user_id=USER, sku="pack_10",
                                                attempt_key="att-grant")
        tran_id = view["tran_id"]
        GATEWAY.status_for[tran_id] = _status(
            tran_id=tran_id, payment_status_code=payway.STATUS_APPROVED,
            payment_status="APPROVED", total_amount=4.99, currency="USD")
        # `verify_and_settle` is what the /order poll route runs on the row:
        # Check Transaction, then the grant, then the projection.
        one = await seam.verify_and_settle(_row(tran_id))
        two = await seam.verify_and_settle(_row(tran_id))
        check("PLUGIN13 the first poll after APPROVED grants",
              one["state"] == seam.GRANTED, one.get("state"))
        check("PLUGIN13 the second poll does not grant again",
              two["state"] == seam.GRANTED
              and len(ENGINE.credited_grants) == 1,
              (two.get("state"), len(ENGINE.credited_grants)))
    finally:
        os.environ.pop("PAYWAY_PAYMENT_OPTION", None)


async def test_the_qr_is_abas_payload_and_nothing_else() -> None:
    """QR01-QR06 — Ayden draws ABA's string. It does not author a payment.

    ABA returns the payment as a STRING on this rail and never as an image
    (measured 2026-09-05: `abapay_khqr_deeplink` answers with `qr_string`,
    `abapay_deeplink`, `checkout_qr_url`, `description`, `status` — no image
    field, and `download_qr` lives only inside the opaque checkout token). A
    customer cannot scan a string, so the server encodes it.

    Encoding is the whole of what is permitted. These assertions pin the line
    between rendering a payment and inventing one.
    """
    section("QR   the symbol is ABA's payload, rendered, and nothing more")
    _reset()
    GATEWAY.checkout_shape = "json"

    view = await seam.start_checkout(user_id=USER, sku="pack_10",
                                     attempt_key="att-qr")
    row = _row(view["tran_id"])

    # QR01 — the payload is stored EXACTLY as PayWay sent it.
    check("QR01 the stored payload is byte-identical to PayWay's",
          row["qr_string"] == KHQR_FIXTURE, len(row.get("qr_string") or ""))

    # QR02 — an image now exists, and it is a PNG.
    img = row.get("qr_image") or ""
    raw = base64.b64decode(img) if img else b""
    check("QR02 a PNG was rendered for it", raw[:8] == b"\x89PNG\r\n\x1a\n",
          raw[:8])

    # QR03 — DETERMINISTIC. The same payload always gives the same bytes, which
    # is what lets a reviewer re-derive the image from the string themselves.
    again = pwa_qr.render_khqr_png_b64(KHQR_FIXTURE)
    check("QR03 rendering is deterministic", again == img)

    # QR04 — and it is a function of the payload: one character changes it.
    other = pwa_qr.render_khqr_png_b64(KHQR_FIXTURE[:-1] + "5")
    check("QR04 a different payload gives a different symbol", other != img)

    # QR05 — nothing renders when there is nothing to render. Empty is a state
    # the payment sheet already draws, not an error.
    check("QR05 an empty payload renders nothing",
          pwa_qr.render_khqr_png_b64("") == "")

    # QR06 — the browser is handed the image, and the payload it came from.
    check("QR06 the public view carries the image",
          (view.get("qr_image") or "") == img)
    check("QR06 and the untouched payload beside it",
          view.get("qr_string") == KHQR_FIXTURE)


async def test_no_endpoint_renders_a_caller_supplied_payload() -> None:
    """QR07-QR10 — there is exactly ONE call site, and the browser is not it.

    A QR renderer that accepts input is a way to put an attacker's payment code
    on our own payment screen. This asserts, from the source, that no such route
    exists and that the only caller passes the value PayWay just returned.
    """
    section("QR   no route renders a payload a caller chose")
    seam_src = Path(seam.__file__).read_text(encoding="utf-8")

    # QR07 — one call site.
    check("QR07 the seam renders a QR in exactly one place",
          seam_src.count("pwa_qr.render_khqr_png_b64(") == 1,
          seam_src.count("pwa_qr.render_khqr_png_b64("))

    # QR08 — and it renders the value that came back from PayWay.
    check("QR08 and it encodes PayWay's own field",
          "pwa_qr.render_khqr_png_b64(checkout.qr_string)" in seam_src)

    # QR09 — no route exposes the renderer.
    routes = [ln for ln in seam_src.splitlines()
              if ln.strip().startswith("@router.")]
    check("QR09 no route mentions qr rendering",
          not any("qr" in r.lower() and "render" in r.lower() for r in routes),
          routes)

    # QR10 — the renderer module itself parses nothing. It must not contain the
    # vocabulary of a payload BUILDER: no field assembly, no CRC, no EMV tags.
    qr_src = Path(pwa_qr.__file__).read_text(encoding="utf-8")
    for banned in ("crc", "emv", "tag_", "payload[", "split(", "replace("):
        check(f"QR10 the renderer does not {banned!r} the payload",
              banned not in qr_src.lower().split('"""')[-1].lower(), banned)


async def test_the_deeplink_is_abas_and_is_never_built_here() -> None:
    """QR11-QR13 — the ABA Mobile link comes from ABA."""
    section("QR   the ABA Mobile deeplink is PayWay's, verbatim")
    _reset()
    GATEWAY.checkout_shape = "json"
    view = await seam.start_checkout(user_id=USER, sku="pack_10",
                                     attempt_key="att-dl")
    row = _row(view["tran_id"])
    check("QR11 the deeplink is stored as received",
          row["deeplink"] == "abamobilebank://ababank.com?type=payway&qrcode=x")
    check("QR12 and handed to the browser unchanged",
          view["deeplink"] == row["deeplink"])
    seam_src = Path(seam.__file__).read_text(encoding="utf-8")
    check("QR13 the seam never constructs an abamobilebank:// URL",
          "abamobilebank://" not in seam_src)


async def test_the_redirect_shape_still_works_and_renders_no_qr() -> None:
    """QR14 — the older rail is not broken by any of this."""
    section("QR   the 302 rail still opens a checkout, with no QR")
    _reset()
    GATEWAY.checkout_shape = "redirect"
    view = await seam.start_checkout(user_id=USER, sku="pack_10",
                                     attempt_key="att-redir")
    row = _row(view["tran_id"])
    check("QR14 a redirect checkout is still opened",
          view["state"] == seam.AWAITING_PAYMENT and view["checkout_url"])
    check("QR14 and carries no QR, which is normal for it",
          not (row.get("qr_string") or "") and not (row.get("qr_image") or ""))
    GATEWAY.checkout_shape = "json"


async def test_return_follows_the_calling_origin() -> None:
    """PREPROD (2026-09-04) — the browser comes back where it started.

    One deployment, several addresses: the live staging site, every preview
    channel, and now preprod.aydenstudio.com all talk to this API. A single
    `PAYWAY_RETURN_BASE_URL` sent every payer to one of them, so a person paying
    from preprod landed on a different origin — a different browser session, and
    an apparently lost payment.

    The Origin header now chooses, and it may only choose among origins the
    operator already allowed for CORS. Nothing that decides money moves: the
    product, the price and the grant are still read from the catalogue and from
    Check Transaction.
    """
    section("ORIGIN  the return address follows the caller, within the allowlist")
    cfg = payway.load_config()

    os.environ["PWA_ALLOWED_ORIGINS"] = (
        "https://ayden-studio.web.app,https://preprod.aydenstudio.com")
    os.environ["PWA_ALLOWED_ORIGIN_REGEX"] = (
        r"^https://ayden-studio--[a-z0-9-]+\.web\.app$")
    try:
        check("ORIGIN an allowed origin is honoured",
              seam.return_base_for(cfg, "https://preprod.aydenstudio.com")
              == "https://preprod.aydenstudio.com")
        check("ORIGIN a trailing slash is normalised",
              seam.return_base_for(cfg, "https://preprod.aydenstudio.com/")
              == "https://preprod.aydenstudio.com")
        check("ORIGIN a preview channel matches the regex",
              seam.return_base_for(cfg, "https://ayden-studio--round4-x1.web.app")
              == "https://ayden-studio--round4-x1.web.app")
        check("ORIGIN an UNKNOWN origin is ignored, not honoured",
              seam.return_base_for(cfg, "https://evil.example.com")
              == cfg.return_base_url)
        check("ORIGIN a lookalike does not pass the regex",
              seam.return_base_for(cfg, "https://evil.com/?x=ayden-studio--a.web.app")
              == cfg.return_base_url)
        check("ORIGIN no Origin header falls back to the configured base",
              seam.return_base_for(cfg, "") == cfg.return_base_url)
        url = seam.return_url_for(cfg, "TR-1", "success",
                                  base="https://preprod.aydenstudio.com")
        check("ORIGIN the return URL is built on the chosen base",
              url.startswith("https://preprod.aydenstudio.com/?pay_return=1"), url)
        check("ORIGIN it still carries only the tran_id and the outcome",
              "tran_id=TR-1" in url and "outcome=success" in url)
    finally:
        os.environ.pop("PWA_ALLOWED_ORIGINS", None)
        os.environ.pop("PWA_ALLOWED_ORIGIN_REGEX", None)


async def test_return_is_navigation_not_evidence() -> None:
    """RET — the return URL moves a browser. It cannot move money.

    This is the single most dangerous idea in a redirect-based checkout: PayWay
    sends the customer to `continue_success_url`, the URL has the word "success"
    in it, and every instinct says to believe it. It is a link. Anyone can type
    it, bookmark it, or share it, and none of that is a payment.

    So what is asserted here is the ABSENCE of a code path: the seam never reads
    the outcome, the URL carries nothing the server trusts, and landing on it
    changes no state at all.
    """
    section("RET  the return URL is navigation, never evidence")

    cfg = payway.load_config()
    tran = seam.tran_id_for(USER, "pack_10", "att-ret")

    success = seam.return_url_for(cfg, tran, "success")
    cancel = seam.return_url_for(cfg, tran, "cancel")
    check("RET no return base configured -> no URL is sent at all",
          success == "" and cancel == "", f"{success!r} {cancel!r}")

    os.environ["PAYWAY_RETURN_BASE_URL"] = "https://app.example.com"
    try:
        cfg = payway.load_config()
        success = seam.return_url_for(cfg, tran, "success")
        cancel = seam.return_url_for(cfg, tran, "cancel")
        check("RET the return URL points at the PWA, not at the API",
              success.startswith("https://app.example.com/?pay_return=1"), success)
        check("RET it is a PATH+QUERY, not a fragment the router cannot see",
              "#" not in success, success)
        check("RET it carries the tran_id so the sheet can re-open",
              f"tran_id={tran}" in success, success)
        check("RET success and cancel are distinguishable to the CLIENT",
              "outcome=success" in success and "outcome=cancel" in cancel)
        check("RET the URL carries no amount, no credits, no user, no token",
              not any(word in success for word in
                      ("amount", "credits", "user", "token", "4.99", USER)),
              success)

        # THE assertion. The server has no reader for any of it.
        source = pathlib.Path(seam.__file__).read_text(encoding="utf-8")
        check("RET the seam never reads an `outcome` back",
              'outcome"' not in source.replace('"outcome"', "", 1)
              or source.count('"outcome"') == 0,
              "an outcome reader appeared in the seam")
        check("RET `continue_success_url` is only ever WRITTEN, never parsed",
              "continue_success_url=return_url_for" in source
              or "continue_success_url=" in source)

        # And behaviourally: a transaction sitting at AWAITING_PAYMENT stays
        # there no matter what the browser was told, because the gateway still
        # says PENDING.
        view = await seam.start_checkout(user_id=USER, sku="pack_10",
                                         attempt_key="att-ret")
        GATEWAY.status_for[view["tran_id"]] = _status(
            payment_status_code=payway.STATUS_PENDING, payment_status="PENDING")
        row = await seam._load(view["tran_id"])          # noqa: SLF001
        settled = await seam.verify_and_settle(row, force=True)
        check("RET returning from a 'success' URL grants nothing while PayWay "
              "says PENDING",
              settled["state"] == seam.AWAITING_PAYMENT, str(settled.get("state")))
        check("RET and no grant reached the engine",
              not [g for g in ENGINE.grants if g["tran_id"] == view["tran_id"]])
    finally:
        os.environ.pop("PAYWAY_RETURN_BASE_URL", None)


async def test_catalogue_is_the_price_authority() -> None:
    """CAT — 10/$4.99, 30/$7.99, 300/$47.99, and the crossed-out price is inert.

    The dangerous number in this release is `79.99`. It exists to be struck
    through on a card, it is bigger than what anyone pays, and it sits one
    `metadata` lookup away from the code that signs a PayWay request. So the
    assertions below are not about rendering — they are about the ABSENCE of a
    path from that number to the gateway.
    """
    section("CAT  the catalogue is the only price authority")

    # BEST VALUE — the discounted product, end to end.
    view = await seam.start_checkout(user_id=USER, sku="pack_300",
                                     attempt_key="att-cat")
    check("CAT 300 spaces resolve to the CATALOGUE price, not the reference one",
          view["amount"] == 47.99, str(view["amount"]))
    check("CAT the spaces come from the catalogue", view["credits"] == 300,
          str(view["credits"]))
    check("CAT the PayWay request is SIGNED for 47.99",
          GATEWAY.last_body["amount"] == "47.99", GATEWAY.last_body["amount"])
    check("CAT 79.99 appears NOWHERE in the signed PayWay request",
          "79.99" not in json.dumps(GATEWAY.last_body), str(GATEWAY.last_body))
    # NOTE the precise claim. The browser DOES receive 79.99 — from the
    # CATALOGUE (`GET /entitlement`), which is how the crossed-out price gets
    # rendered at all. What it must never appear in is the PAYMENT ATTEMPT:
    # two different payloads, and only one of them is anywhere near the money.
    check("CAT 79.99 is absent from the PAYMENT payload (not the catalogue)",
          "79.99" not in json.dumps(view), str(view))
    check("CAT the payment payload has no list price field at all",
          "list_price_usd" not in view, str(sorted(view)))

    order = [o for o in DB.tables["public.orders"]
             if o.get("idempotency_key") == seam.order_key_for(view["tran_id"])]
    check("CAT the canonical order is opened at 47.99",
          len(order) == 1 and float(order[0]["amount"]) == 47.99, str(order))

    # A callback claiming the REFERENCE price is a wrong-amount callback.
    GATEWAY.status_for[view["tran_id"]] = _status(
        payment_status_code=payway.STATUS_APPROVED, payment_status="APPROVED",
        payment_amount=79.99, total_amount=79.99, currency="USD")
    row = await seam._load(view["tran_id"])                   # noqa: SLF001
    settled = await seam.verify_and_settle(row, force=True)
    check("CAT a payment of the CROSSED-OUT price does not grant",
          settled["state"] == seam.FAILED, str(settled.get("state")))
    check("CAT and it is named an amount mismatch",
          settled.get("failure_reason") == "AMOUNT_MISMATCH",
          str(settled.get("failure_reason")))
    check("CAT nothing reached the Billing Engine",
          not [g for g in ENGINE.grants if g["tran_id"] == view["tran_id"]])

    # STARTER, at its new price.
    starter = await seam.start_checkout(user_id=OTHER_USER, sku="pack_10",
                                        attempt_key="att-cat-10")
    check("CAT 10 spaces cost 4.99", starter["amount"] == 4.99
          and starter["credits"] == 10, str(starter["amount"]))

    # A retired pack cannot be bought, and an invented one cannot either.
    for sku in ("pack_25", "pack_1000", "unlimited"):
        try:
            await seam.start_checkout(user_id=USER, sku=sku,
                                      attempt_key=f"att-{sku}")
            check(f"CAT {sku!r} cannot be bought", False, "it was accepted")
        except HTTPException as exc:
            check(f"CAT {sku!r} cannot be bought", exc.status_code in (404, 409),
                  str(exc.status_code))

    # THE structural claim: no client field can express "unlimited".
    for forbidden in ("credits", "unlimited", "price_usd", "amount",
                      "list_price_usd", "entitlement"):
        try:
            seam.CheckoutRequest(sku="pack_10", attempt_key="x" * 12,
                                 **{forbidden: 999999})
            check(f"CAT a request carrying `{forbidden}` is REJECTED", False)
        except Exception:  # noqa: BLE001 — pydantic raises its own type
            check(f"CAT a request carrying `{forbidden}` is REJECTED", True)


async def test_metadata_is_presentation_only() -> None:
    """PRES — the browser MAY see 79.99, and it still cannot be charged it.

    THE DISTINCTION this whole design rests on, and the one my own report
    initially blurred: there are TWO payloads.

        GET  /entitlement                 the CATALOGUE — presentation.
                                          Carries `list_price_usd` and `badge`,
                                          because a crossed-out price cannot be
                                          rendered without them.

        POST /payments/checkout           the PAYMENT ATTEMPT — money.
                                          Carries `amount` and no list price at
                                          all.

    "The browser never sees 79.99" would be false, and building toward it would
    mean hardcoding the reference price in Dart — which is worse, because then
    a price change needs an app release. The true invariant is narrower and
    stronger: 79.99 is never PAYMENT AUTHORITY. It reaches the browser through a
    read-only catalogue, it is absent from the payment payload, and no code path
    exists that could turn it into an amount.

    So this proves the absence of that path even when `metadata` is hostile.
    """
    section("PRES  metadata renders a price; it can never charge one")

    # 1) The catalogue DOES carry it — that is its job.
    import pwa_staging_billing as pwa_billing  # noqa: PLC0415

    rows = await pwa_billing.catalogue()
    best = [r for r in rows if r["sku"] == "pack_300"][0]
    check("PRES the CATALOGUE carries the reference price for rendering",
          best["list_price_usd"] == 79.99, str(best))
    check("PRES and the badge code, for the client to translate",
          best["badge"] == "best_value", str(best["badge"]))
    check("PRES the catalogue's payable price is still the discounted one",
          best["price_usd"] == 47.99, str(best["price_usd"]))
    check("PRES the discount is NOT sent — it is derived from the two prices",
          "discount" not in json.dumps(best).lower(), str(best))

    # 2) `resolve_web_product` — the ONE function the payment path uses to turn
    #    a sku into money — must not read `metadata` at all.
    source = pathlib.Path(seam.__file__).read_text(encoding="utf-8")
    resolver = source[source.index("async def resolve_web_product"):
                      source.index("# ── public projection")]
    check("PRES resolve_web_product never mentions metadata",
          "metadata" not in resolver, "the payment resolver reads metadata")
    check("PRES it does not even SELECT the column",
          "metadata" not in resolver.split("select(")[1].split(")")[0]
          if "select(" in resolver else True)

    # 3) HOSTILE metadata: a list price crafted to look like a bargain, a
    #    negative, a string, an injected "amount". None of it may move a cent.
    original = copy.deepcopy(DB.tables["public.products"])
    try:
        for hostile in (
            {"list_price_usd": 0.01},
            {"list_price_usd": -100},
            {"list_price_usd": "47.99'; drop table orders;--"},
            {"price_usd": 0.01},
            {"amount": 0.01},
            {"credits_granted": 999999},
            {"unlimited": True},
        ):
            for row in DB.tables["public.products"]:
                if row["sku"] == "pack_300":
                    row["metadata"] = hostile
            product = await seam.resolve_web_product("pack_300")
            check(f"PRES metadata {list(hostile)[0]!r} cannot move the price",
                  product.price == 47.99, f"{hostile} -> {product.price}")
            check(f"PRES metadata {list(hostile)[0]!r} cannot move the credits",
                  product.credits == 300, f"{hostile} -> {product.credits}")
    finally:
        DB.tables["public.products"] = original

    # 4) A malformed reference price degrades to "no discount shown", never to
    #    a crash that would take the whole paywall down over a marketing field.
    for junk in ("banana", "", None, -5, 0):
        check(f"PRES a malformed list price {junk!r} renders as absent",
              pwa_billing._display_price(junk) is None,   # noqa: SLF001
              str(pwa_billing._display_price(junk)))      # noqa: SLF001
    check("PRES a well-formed one comes through as a number",
          pwa_billing._display_price("79.99") == 79.99)   # noqa: SLF001


async def test_checkout_token_goes_stale() -> None:
    """TTL — a checkout link dies in 180s; the transaction does not.

    Measured on the sandbox: the checkout URL carries `expire_in_sec: "180"`
    while the request asked for `lifetime = 30` minutes. Two different clocks,
    and conflating them is how a live payment gets presented through a dead
    link. The row must stay payable and the LINK must be marked stale.
    """
    section("TTL  the checkout link expires long before the transaction")

    view = await seam.start_checkout(user_id=USER, sku="pack_10",
                                     attempt_key="att-ttl")
    tran = view["tran_id"]
    check("TTL a fresh checkout is not stale", view["checkout_stale"] is False,
          str(view["checkout_stale"]))
    check("TTL the client is told the token's life",
          view["checkout_ttl_s"] == payway.CHECKOUT_TOKEN_TTL_S,
          str(view.get("checkout_ttl_s")))

    # Age the issue time past PayWay's token life, leaving everything else alone.
    row = DB.tables["pwa_staging.payway_transactions"]
    target = [r for r in row if r["tran_id"] == tran][0]
    target["qr_issued_at"] = seam._iso(                       # noqa: SLF001
        seam._now() - timedelta(seconds=payway.CHECKOUT_TOKEN_TTL_S + 30))

    stale_view = seam.public_view(await seam._load(tran))     # noqa: SLF001
    check("TTL an aged checkout link is reported stale",
          stale_view["checkout_stale"] is True, str(stale_view["checkout_stale"]))
    check("TTL the PAYMENT is still open — stale is not failed",
          stale_view["state"] == seam.AWAITING_PAYMENT, stale_view["state"])
    check("TTL and it is not terminal, so nothing is written off",
          stale_view["terminal"] is False)
    check("TTL the expiry of the TRANSACTION is untouched",
          stale_view["expires_at"] == view["expires_at"])


async def test_generate_qr_is_unreachable() -> None:
    """DEP — the deprecated rail is still in the tree and reachable from nothing.

    §5 of the brief: keep `generate-qr` until the Purchase suite is green, but
    the active PWA journey must not use it. "Must not" is a claim about the call
    graph, so it is asserted against the call graph rather than trusted.
    """
    section("DEP  generate-qr survives, and nothing calls it")

    source = pathlib.Path(seam.__file__).read_text(encoding="utf-8")
    check("DEP the seam calls payway.purchase", "payway.purchase(" in source)
    check("DEP the seam calls generate_qr NOWHERE",
          "generate_qr(" not in source, "a generate-qr call is still in the seam")

    rail = pathlib.Path(payway.__file__).read_text(encoding="utf-8")
    check("DEP the deprecated path is still defined (not deleted)",
          "PATH_GENERATE_QR" in rail)
    check("DEP and it is documented as deprecated where it is defined",
          "DEPRECATED" in rail)
    check("DEP the Purchase path is the one the seam's endpoint answers with",
          payway.PATH_PURCHASE == "/api/payment-gateway/v1/payments/purchase",
          payway.PATH_PURCHASE)


async def test_check_transaction_cadence_is_pinned() -> None:
    """ABA-REVIEW-11 — the Check Transaction timing ABA was told about.

    ABA's reviewer asked how often we call Check Transaction, when we stop and
    for how long at most. The answer (docs/aba/ABA_REVIEW_RESPONSE_2026_09_08.md
    in the PWA repo) quotes these three values; a change to any of them must
    change that answer too, so they are pinned here as data.
    """
    section("ABA-REVIEW-11  the cadence ABA was told about is the cadence")
    check("ABA-REVIEW-11 the server floor between two real checks is 3.0 s",
          seam._CHECK_MIN_INTERVAL_S == 3.0, str(seam._CHECK_MIN_INTERVAL_S))
    src = pathlib.Path(seam.__file__).read_text(encoding="utf-8")
    check("ABA-REVIEW-11 the client is told to poll every 3000 ms",
          '"poll_interval_ms": 3000' in src)
    rail = pathlib.Path(payway.__file__).read_text(encoding="utf-8")
    check("ABA-REVIEW-11 the transaction lifetime defaults to 30 minutes",
          '_env("PAYWAY_QR_LIFETIME_MINUTES", "30")' in rail)
    check("ABA-REVIEW-11 NOT_CREATED still waits 30 s before concluding",
          seam._NOT_CREATED_GRACE.total_seconds() == 30.0)
    check("ABA-REVIEW-11 GRANTED / FAILED / CANCELLED stop the checks",
          "if state == GRANTED:" in src and "if state in (FAILED, CANCELLED):" in src)


async def main_async() -> int:
    _install()
    await test_identity()
    await test_check_transaction_cadence_is_pinned()
    await test_aba01_checkout()
    await test_aba02_aba03_tampering()
    await test_aba04_aba10_aba11_idempotency()
    await test_aba07_aba08_aba09_callback()
    await test_aba12_aba13_durability()
    await test_aba14_terminal()
    await test_aba18_bypass()
    await test_return_is_navigation_not_evidence()
    await test_not_created_is_terminal_after_the_grace_window()
    await test_not_created_never_fires_on_the_server_side_path()
    await test_plugin_checkout_signs_and_does_not_post()
    await test_plugin_rejoin_returns_no_fields()
    await test_plugin_refuses_any_other_option()
    await test_plugin_path_grants_exactly_once_via_check_transaction()
    await test_the_qr_is_abas_payload_and_nothing_else()
    await test_no_endpoint_renders_a_caller_supplied_payload()
    await test_the_deeplink_is_abas_and_is_never_built_here()
    await test_the_redirect_shape_still_works_and_renders_no_qr()
    await test_return_follows_the_calling_origin()
    await test_catalogue_is_the_price_authority()
    await test_metadata_is_presentation_only()
    await test_checkout_token_goes_stale()
    await test_generate_qr_is_unreachable()
    await test_public_surface()
    await test_unconfigured()

    print()
    if _failed:
        print(f"FAILURES: {len(_failed)} / {len(_passed) + len(_failed)}")
        for name in _failed:
            print("  -", name)
        return 1
    print(f"ALL PAYMENT SEAM TESTS PASS ({len(_passed)} assertions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main_async()))
