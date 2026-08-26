"""PWA STAGING — the PAYMENT SEAM. Between a rail that moves money and an
engine that grants credits, and it owns neither.

The three-part split, and why it is three
-----------------------------------------
    payway.py                 the RAIL. Speaks PayWay's protocol. Knows nothing
                              about products, users, credits or entitlement.
                              Its ACTIVE call is `/payments/purchase`, which ABA
                              confirmed on 2026-08-19 is the endpoint for website
                              integrations. `generate-qr` survives in that module
                              and is reachable from nothing in this one.
    THIS FILE                 the SEAM. Knows what a purchase attempt is, which
                              canonical product it is for, and what has to be
                              true before anything is granted.
    billing.grant_purchase    the ENGINE. The only thing in the system that can
                              make a credit exist. Shared with RevenueCat,
                              unchanged by this file.

Nothing here computes a balance, writes a ledger row, or decides whether a
person may generate. Those answers already exist and have exactly one owner.

WHAT THE BROWSER IS ALLOWED TO SAY
----------------------------------
Two things: a `sku` and an `attempt_key`. That is the whole client input.

    price          read from `public.products`
    currency       read from `public.products` / the deployment's config
    credits        read from `public.products`
    entitlement    decided by `billing_grant_purchase`

A request that carries an amount, a credit count or a product price is not
"validated" — those fields do not exist on the request model, so there is no
code path in which a browser-supplied number can be believed. This is stronger
than checking them, because a check can be forgotten when a field is added.

TRANSACTION IDENTITY
--------------------
    tran_id = 'A' + sha256(f"payway:{user}:{sku}:{attempt}")[:19]

Deterministic, user-scoped, and stable across every accident that repeats a
request: a double-click, an F5, a dropped response, a backend restart, a second
tab. All of them recompute the SAME tran_id, hit the SAME row, and PayWay itself
refuses a duplicate with 403 if our own bookkeeping were ever lost. A NEW
purchase attempt is a NEW `attempt_key` — chosen by the person tapping "try
again", never by a retry.

That id is also what ties the rail to the engine:

    tran_id ──> orders.idempotency_key = 'order:khqr:<tran_id>'
            ──> payments (provider='khqr', provider_transaction_id=tran_id)
            ──> ledger GRANT keyed 'grant:order:<order_id>'

`provider` is 'khqr' — the acquisition RAIL, which is what the canonical column
means. There is no 'aba' and no 'aba_payway' anywhere: PayWay is the gateway
BRAND that operates the KHQR rail, and brands are not a schema concept here.

WHOSE SCREEN THE CUSTOMER PAYS ON
---------------------------------
ABA's. `/payments/purchase` answers with a URL on PayWay's own domain, and the
browser goes there — Ayden's surface ends at "Buy credit pack". The earlier rail
issued a KHQR and drew the payment screen here, which worked and was still the
wrong division of labour: ABA's integration guideline puts the payment UI with
ABA, and a checkout we render is a checkout we would have to keep in step with
theirs forever.

What comes back is `checkout_url`, and on the `abapay_khqr_deeplink` mode also a
KHQR string and an ABA Mobile deeplink. None of it is secret — it is the payment
request itself — and none of it lets the browser conclude anything.

THE GRANT RULE, in one sentence
-------------------------------
A pushback is a DOORBELL, never a receipt: the only thing allowed to justify a
grant is a server-to-server Check Transaction that says APPROVED for this
tran_id, for this amount, in this currency, on this merchant.

That is why this adapter works correctly on a deployment PayWay cannot reach.
The browser polls us, we ask PayWay, PayWay answers. A public callback makes it
FASTER; it is not what makes it CORRECT. A design where the callback were the
only path would be broken by every firewall — and would also be the design in
which forging a callback is worth trying.
"""
from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Optional
from urllib.parse import quote

import httpx
from fastapi import APIRouter, Header, HTTPException, Request
from pydantic import BaseModel, ConfigDict, Field

import payway

log = logging.getLogger("aih")

router = APIRouter(prefix="/pwa/staging/payments", tags=["pwa-staging-payments"])

_SCHEMA = "pwa_staging"
_TABLE = "payway_transactions"

#: The acquisition RAIL, as `public.orders.provider` / `public.payments.provider`
#: already define it. Not the gateway brand.
PROVIDER = "khqr"

#: Rail states. Superset of the order's money states; see 0007 §1.
CREATED = "CREATED"
AWAITING_PAYMENT = "AWAITING_PAYMENT"
PAID_PENDING_VERIFICATION = "PAID_PENDING_VERIFICATION"
VERIFIED = "VERIFIED"
GRANTED = "GRANTED"
FAILED = "FAILED"
EXPIRED = "EXPIRED"
CANCELLED = "CANCELLED"

TERMINAL = (GRANTED, FAILED, EXPIRED, CANCELLED)
OPEN = (CREATED, AWAITING_PAYMENT, PAID_PENDING_VERIFICATION, VERIFIED)

#: Minimum seconds between two REAL Check Transaction calls for one tran_id.
#: The browser may poll faster than this; it just gets the stored answer. PayWay
#: allows 600 rps and asks that you "stop checking once a result is returned" —
#: this honours the spirit without making the UI feel slow.
_CHECK_MIN_INTERVAL_S = 3.0

#: How long a QR-less attempt may sit before a sweep calls it expired. Only used
#: when PayWay never answered at all.
_CREATED_GRACE = timedelta(minutes=5)


class PayWayDisabled(HTTPException):
    """The paywall must say "not open yet" rather than offer a broken checkout."""

    def __init__(self, reason: str = "not_configured"):
        super().__init__(
            status_code=503,
            detail={"error_code": "PAYMENTS_UNAVAILABLE",
                    "payment_state": "UNAVAILABLE",
                    "reason": reason,
                    "retryable": False},
        )


# ── identity ─────────────────────────────────────────────────────────────────


def tran_id_for(user_id: str, sku: str, attempt_key: str) -> str:
    """The ONE mapping: (user, product, attempt) -> PayWay transaction id.

    PayWay caps `tran_id` at 20 characters and treats it as globally unique per
    merchant, forever. A truncated sha256 over the three inputs gives 76 bits of
    digest in 19 hex characters — collision-free at any volume this product will
    ever see — and the leading 'A' keeps the id alphanumeric-leading, which is
    the shape every PayWay example uses.

    User-scoped so two people cannot collide on an `attempt_key` a browser chose.
    """
    digest = hashlib.sha256(
        f"payway:{user_id}:{sku}:{attempt_key}".encode("utf-8")).hexdigest()
    return f"A{digest[:19]}"


def order_key_for(tran_id: str) -> str:
    """EXACTLY the key `billing_grant_purchase` builds, so the PENDING order this
    adapter creates and the PAID order the engine writes are ONE row.

    Duplicated here rather than imported because it is a CONTRACT with SQL, not a
    shared implementation — and `payway_transactions.order_idempotency_key`
    stores the result, so a drift is visible in the data, not only in a diff.
    """
    return f"order:{PROVIDER}:{tran_id}"


# ── data access (service-role; the browser never writes payment state) ────────


def _supa():
    from main import supa  # noqa: PLC0415 — the staging service-role client

    return supa


def _rail():
    return _supa().schema(_SCHEMA)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).isoformat()


def _parse_ts(value: Any) -> Optional[datetime]:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


async def _load(tran_id: str) -> Optional[dict]:
    res = await asyncio.to_thread(
        lambda: _rail().table(_TABLE).select("*").eq("tran_id", tran_id)
        .limit(1).execute()
    )
    rows = getattr(res, "data", None) or []
    return rows[0] if rows else None


async def _update(tran_id: str, patch: dict, *, only_if: Optional[tuple] = None) -> bool:
    """Patch a rail row. `only_if` makes it a compare-and-set on `state`.

    The CAS is what keeps a callback and a poll that arrive together from both
    driving a transition. It is NOT what prevents a double grant — that is
    `billing_grant_purchase`'s idempotency key, which holds even if this raced.
    """

    def _run():
        q = _rail().table(_TABLE).update(patch).eq("tran_id", tran_id)
        if only_if:
            q = q.in_("state", list(only_if))
        return q.execute()

    try:
        res = await asyncio.to_thread(_run)
        return bool(getattr(res, "data", None))
    except Exception as exc:  # noqa: BLE001 — a bookkeeping write must not 500 a payment
        log.warning("[payway-seam] rail update failed tran=%s err=%s",
                    tran_id, type(exc).__name__)
        return False


async def open_attempt_for(user_id: str) -> Optional[dict]:
    """The newest attempt this person has that is not finished.

    This is how an F5, a new tab, or a backend restart restores the payment
    sheet: the SERVER remembers, so the browser does not have to, and there is
    nothing in local storage to go stale or to forge.
    """
    res = await asyncio.to_thread(
        lambda: _rail().table(_TABLE).select("*")
        .eq("user_id", user_id).in_("state", list(OPEN))
        .order("created_at", desc=True).limit(1).execute()
    )
    rows = getattr(res, "data", None) or []
    return rows[0] if rows else None


# ── the canonical catalogue is the only price authority ──────────────────────


@dataclass(frozen=True)
class WebProduct:
    """A product the WEB may sell, exactly as `public.products` defines it."""

    id: str
    sku: str
    type: str
    credits: int
    duration_days: Optional[int]
    price: float
    currency: str


async def resolve_web_product(sku: str) -> WebProduct:
    """Read the product, or refuse. Never trusts the caller for anything but the sku.

    Three conditions, all from the row itself:
      * `active`      — a withdrawn product cannot be bought;
      * `khqr_enabled`— the catalogue's own statement that this may be sold on
                        the KHQR rail;
      * no store id   — a row carrying an Apple/RevenueCat id exists to be sold
                        IN AN APP STORE. Selling it again on the Web would take
                        money for a subscription the stores, not we, manage. This
                        is the same `store_only` rule the paywall already renders.
    """
    res = await asyncio.to_thread(
        lambda: _supa().table("products")
        .select("id, sku, type, credits_granted, duration_days, price_usd, "
                "currency, khqr_enabled, apple_product_id, revenuecat_product_id")
        .eq("sku", sku).eq("active", True).limit(1).execute()
    )
    rows = getattr(res, "data", None) or []
    if not rows:
        raise HTTPException(
            status_code=404,
            detail={"error_code": "UNKNOWN_PRODUCT", "payment_state": "FAILED",
                    "reason": "unknown_sku", "retryable": False},
        )
    row = rows[0]
    store_only = bool(row.get("apple_product_id") or row.get("revenuecat_product_id"))
    if store_only or not row.get("khqr_enabled"):
        raise HTTPException(
            status_code=409,
            detail={"error_code": "PRODUCT_NOT_WEB_SELLABLE",
                    "payment_state": "FAILED",
                    "reason": "store_only" if store_only else "khqr_disabled",
                    "retryable": False},
        )
    price = row.get("price_usd")
    if price is None or float(price) <= 0:
        raise HTTPException(
            status_code=409,
            detail={"error_code": "PRODUCT_NOT_PRICED", "payment_state": "FAILED",
                    "reason": "no_price", "retryable": False},
        )
    return WebProduct(
        id=str(row["id"]),
        sku=str(row["sku"]),
        type=str(row.get("type") or ""),
        credits=int(row.get("credits_granted") or 0),
        duration_days=(int(row["duration_days"])
                       if row.get("duration_days") is not None else None),
        price=float(price),
        currency=str(row.get("currency") or "USD").upper(),
    )


# ── public projection ────────────────────────────────────────────────────────


def public_view(row: dict) -> dict:
    """What a browser may know about a payment attempt.

    Includes the QR, the deeplink, the amount and the state — everything a person
    paying needs. Excludes the merchant id, every hash, the raw PayWay envelope,
    and the internal order id. `credits` is present because it is what the person
    is buying and it came from the catalogue, not from them.
    """
    state = row.get("state") or CREATED

    # A CHECKOUT URL GOES STALE LONG BEFORE THE TRANSACTION DOES.
    #
    # PayWay's checkout token lives 180 seconds; the transaction it pays for
    # lives `lifetime` minutes. So a person who opens the payment sheet, walks
    # away, and comes back to an F5 four minutes later has a row that is still
    # perfectly payable and a link that is dead. Handing them that link is worse
    # than handing them nothing: they would land on a PayWay error page and
    # reasonably conclude Ayden is broken.
    #
    # This is computed rather than stored so it stays true as time passes — a
    # column would be right when written and wrong a minute later.
    issued = _parse_ts(row.get("qr_issued_at"))
    checkout_url = row.get("checkout_url") or ""
    stale = bool(
        checkout_url and issued
        and (_now() - issued).total_seconds() > payway.CHECKOUT_TOKEN_TTL_S)

    return {
        "tran_id": row.get("tran_id"),
        "state": state,
        "terminal": state in TERMINAL,
        "sku": row.get("sku"),
        "credits": row.get("credits"),
        "amount": (float(row["amount"]) if row.get("amount") is not None else None),
        "currency": row.get("currency"),
        # THE field the browser acts on: PayWay's own checkout page.
        "checkout_url": checkout_url,
        "checkout_mode": row.get("checkout_mode") or "",
        # True once the link is past PayWay's 180-second token life. The payment
        # is NOT dead — the client must offer a fresh attempt rather than a
        # broken link, and must not present this as a failure.
        "checkout_stale": stale,
        "checkout_ttl_s": payway.CHECKOUT_TOKEN_TTL_S,
        # Present only in the `abapay_khqr_deeplink` mode, and never the primary
        # surface: ABA's guideline is that the payment screen is ABA's.
        "qr_string": row.get("qr_string") or "",
        "qr_image": row.get("qr_image") or "",
        "deeplink": row.get("deeplink") or "",
        "app_store": row.get("app_store") or "",
        "play_store": row.get("play_store") or "",
        "expires_at": row.get("expires_at"),
        "failure_reason": row.get("failure_reason") or "",
        # A hint, not an instruction: the client stops polling on `terminal`.
        "poll_interval_ms": 3000,
    }


# ── checkout ─────────────────────────────────────────────────────────────────


class CheckoutRequest(BaseModel):
    """The ENTIRE client input. Note what is absent — deliberately, permanently.

    `extra='forbid'` turns a tampering attempt into a 422 instead of a silently
    ignored field. Both are safe; only one is legible. A request carrying
    `amount`, `credits` or `price` is rejected by name, so the refusal shows up
    in a log and in a test rather than looking like a successful purchase that
    happened to charge the catalogue price.
    """

    model_config = ConfigDict(extra="forbid")

    sku: str = Field(min_length=1, max_length=64)
    #: The person's own "this is a new attempt" token. A retry of the SAME
    #: attempt reuses it and converges on one transaction; a deliberate restart
    #: sends a new one.
    attempt_key: str = Field(min_length=8, max_length=64)


async def start_checkout(*, user_id: str, sku: str, attempt_key: str) -> dict:
    """Create (or re-join) a payment attempt and return what the browser renders.

    The product is resolved BEFORE the gateway configuration is checked, and the
    order is deliberate. Both refuse, but they refuse different things, and a
    deployment with no credentials answering "payments are not open" to a request
    for a sku that does not exist is a misleading error that would hide a client
    bug until the day ABA went live. Resolving first costs one catalogue read —
    public information, already served by `/entitlement` — and touches no secret
    and no money.
    """
    product = await resolve_web_product(sku)
    cfg = _config_or_refuse()

    tran_id = tran_id_for(user_id, product.sku, attempt_key)
    existing = await _load(tran_id)
    if existing and existing.get("state") not in (CREATED,):
        # Already live, already paid, or already finished. Re-joining is the
        # normal case for F5 and for a second tab — never a second charge.
        log.info("[payway-seam] rejoin tran=%s state=%s", tran_id, existing.get("state"))
        return public_view(existing)

    expires_at = _now() + timedelta(minutes=cfg.lifetime_minutes)
    won = await _claim(tran_id=tran_id, user_id=user_id, product=product,
                       attempt_key=attempt_key, expires_at=expires_at,
                       currency=cfg.currency)
    if not won:
        # Another request is issuing the QR right now. Hand back whatever the
        # row says; the client polls, which is what it does anyway.
        row = await _load(tran_id)
        if row:
            return public_view(row)
        raise HTTPException(
            status_code=409,
            detail={"error_code": "CHECKOUT_BUSY", "payment_state": CREATED,
                    "reason": "claim_lost", "retryable": True},
        )

    # The canonical PENDING order, under the key the ENGINE will reuse. This is
    # what makes the purchase one order row rather than two.
    await _open_order(user_id=user_id, product=product, tran_id=tran_id,
                      currency=cfg.currency)

    try:
        checkout = await payway.purchase(
            cfg=cfg, tran_id=tran_id, amount=product.price,
            currency=cfg.currency, lifetime_minutes=cfg.lifetime_minutes,
            # Echoed back on the pushback. Correlation only — no identity, no
            # token, no amount. The server reads all of those from its own row.
            return_params=json.dumps({"t": tran_id}, separators=(",", ":")),
            # Where the BROWSER is sent afterwards. Neither URL is trusted for
            # anything: landing on one changes no state, and the PWA's next poll
            # asks the server — which asks PayWay — what actually happened.
            continue_success_url=return_url_for(cfg, tran_id, "success"),
            cancel_url=return_url_for(cfg, tran_id, "cancel"),
        )
    except payway.PayWayError as exc:
        reason = ("DUPLICATE_TRAN_ID" if str(exc.code) == "403"
                  else "CHECKOUT_REFUSED")
        await _fail(tran_id, reason, only_if=(CREATED,))
        log.warning("[payway-seam] purchase refused tran=%s code=%s", tran_id, exc.code)
        raise HTTPException(
            status_code=502,
            detail={"error_code": "PAYMENT_PROVIDER_REFUSED",
                    "payment_state": FAILED, "reason": reason,
                    # A duplicate id can only be resolved by a NEW attempt, and
                    # the client is told exactly that rather than left to guess.
                    "retryable": reason == "CHECKOUT_REFUSED",
                    "new_attempt_required": reason == "DUPLICATE_TRAN_ID"},
        ) from exc
    except payway.PayWayUnreachable as exc:
        # The row stays CREATED, which `payway_claim` allows to be re-claimed:
        # nothing payable was produced, so trying again is safe.
        log.warning("[payway-seam] purchase unreachable tran=%s", tran_id)
        raise HTTPException(
            status_code=503,
            detail={"error_code": "PAYMENT_PROVIDER_UNREACHABLE",
                    "payment_state": CREATED, "reason": "unreachable",
                    "retryable": True},
        ) from exc

    await _update(tran_id, {
        "state": AWAITING_PAYMENT,
        "checkout_url": checkout.checkout_url,
        "checkout_mode": checkout.mode,
        # Populated only in the `abapay_khqr_deeplink` mode. Empty is normal and
        # is not a degraded state: the checkout URL is what the customer needs,
        # and ABA renders the QR on its own page.
        "qr_string": checkout.qr_string,
        "deeplink": checkout.deeplink,
        "qr_issued_at": _iso(_now()),
        "expires_at": _iso(expires_at),
    }, only_if=(CREATED,))

    row = await _load(tran_id)
    log.info("[payway-seam] checkout opened tran=%s sku=%s amount=%s %s "
             "credits=%d mode=%s", tran_id, product.sku, product.price,
             cfg.currency, product.credits, checkout.mode)
    return public_view(row or {"tran_id": tran_id, "state": AWAITING_PAYMENT})


def return_url_for(cfg: payway.PayWayConfig, tran_id: str, outcome: str) -> str:
    """Where PayWay hands the browser back, or "" when nowhere is configured.

    THE RULE THIS ENCODES: these URLs are navigation, not evidence.

    The `tran_id` is in the query string so the PWA can re-open the right
    payment sheet immediately instead of guessing — and that is the whole of its
    authority. `?outcome=success` is what PayWay was asked to append on a
    completed payment, and the client may use it to choose a spinner rather than
    a QR. It may not use it to say "paid", it may not unlock anything, and the
    server never reads it at all: an attacker typing the success URL by hand
    gets the same answer as everyone else, which is whatever Check Transaction
    says.

    Empty when `PAYWAY_RETURN_BASE_URL` is unset. PayWay then shows its own end
    page and the customer navigates back on their own; the payment still
    completes, because completion was never the browser's job.
    """
    if not cfg.has_return_target:
        return ""
    # A PATH, not a fragment. The PWA's history bridge reads
    # `location.pathname + location.search` and ignores `#` entirely, so a
    # hash-routed return URL would arrive as a bare "/" with the tran_id lost —
    # recoverable (the server still remembers the attempt) but needlessly blind.
    return (f"{cfg.return_base_url}/?pay_return=1"
            f"&tran_id={quote(tran_id, safe='')}&outcome={quote(outcome, safe='')}")


def _config_or_refuse() -> payway.PayWayConfig:
    try:
        return payway.load_config()
    except (payway.PayWayNotConfigured, ValueError) as exc:
        log.info("[payway-seam] refusing checkout: %s", type(exc).__name__)
        raise PayWayDisabled(type(exc).__name__) from exc


async def _claim(*, tran_id: str, user_id: str, product: WebProduct,
                 attempt_key: str, expires_at: datetime, currency: str) -> bool:
    res = await asyncio.to_thread(
        lambda: _rail().rpc("payway_claim", {
            "p_tran_id": tran_id,
            "p_user_id": user_id,
            "p_sku": product.sku,
            "p_product_id": product.id,
            "p_credits": product.credits,
            "p_duration_days": product.duration_days,
            "p_amount": product.price,
            "p_currency": currency,
            "p_order_idempotency_key": order_key_for(tran_id),
            "p_attempt_key": attempt_key,
            "p_expires_at": _iso(expires_at),
        }).execute()
    )
    data = getattr(res, "data", None)
    if isinstance(data, list):
        data = data[0] if data else None
    return bool((data or {}).get("won"))


async def _open_order(*, user_id: str, product: WebProduct, tran_id: str,
                      currency: str) -> None:
    """The canonical order, PENDING, before a single riel moves.

    Rule R1 of the Billing Engine: a payment never grants credits directly; it
    settles an order the engine already knows about. Best-effort — if this write
    fails the grant still creates the row, because it upserts on the same key.
    """
    try:
        await asyncio.to_thread(
            lambda: _supa().table("orders").upsert({
                "user_id": user_id,
                "product_id": product.id,
                "status": "PENDING",
                "provider": PROVIDER,
                "amount": product.price,
                "currency": currency,
                "idempotency_key": order_key_for(tran_id),
            }, on_conflict="idempotency_key", ignore_duplicates=True).execute()
        )
    except Exception as exc:  # noqa: BLE001
        log.warning("[payway-seam] PENDING order write failed tran=%s err=%s",
                    tran_id, type(exc).__name__)


async def _fail(tran_id: str, reason: str, *, only_if: Optional[tuple] = None,
                state: str = FAILED) -> None:
    await _update(tran_id, {"state": state, "failure_reason": reason},
                  only_if=only_if or OPEN)
    # The order follows the rail into a terminal money state. EXPIRED and
    # CANCELLED are not order statuses — the canonical column has five values —
    # so both land on the one that means "this order will never be paid".
    try:
        await asyncio.to_thread(
            lambda: _supa().table("orders")
            .update({"status": "CANCELLED" if state in (EXPIRED, CANCELLED) else "FAILED"})
            .eq("idempotency_key", order_key_for(tran_id))
            .eq("status", "PENDING").execute()
        )
    except Exception as exc:  # noqa: BLE001
        log.warning("[payway-seam] order terminalise failed tran=%s err=%s",
                    tran_id, type(exc).__name__)


# ── verification and grant — the only path to a credit ───────────────────────


async def verify_and_settle(row: dict, *, force: bool = False) -> dict:
    """Ask PayWay what happened, and grant if — and only if — it says APPROVED.

    Idempotent and safe to call from anywhere: the poll endpoint, the pushback
    handler, and a future reconciliation worker all call THIS. Whichever arrives
    first does the work; the others find `GRANTED` and return it.

    `force` skips the rate limit. The pushback sets it: a doorbell we trust
    enough to answer immediately, while still trusting nothing it says.
    """
    tran_id = row["tran_id"]
    state = row.get("state") or CREATED

    if state == GRANTED:
        return row
    if state in (FAILED, CANCELLED):
        return row

    expires_at = _parse_ts(row.get("expires_at"))
    created_at = _parse_ts(row.get("created_at"))
    expired = bool(expires_at and _now() > expires_at)
    if state == CREATED and not expired:
        # No QR ever reached the person. Nothing can have been paid — unless the
        # attempt is simply old and abandoned.
        if created_at and _now() - created_at > _CREATED_GRACE:
            await _fail(tran_id, "NO_QR_ISSUED", only_if=(CREATED,), state=EXPIRED)
            return await _load(tran_id) or row
        return row

    if not force and not _may_check(row):
        return row

    cfg = _config_or_refuse()
    try:
        status = await payway.check_transaction(cfg=cfg, tran_id=tran_id)
    except payway.PayWayUnreachable:
        # Say nothing rather than something wrong. The person keeps waiting, the
        # next poll asks again, and an unreachable gateway never expires a
        # payment that may have succeeded.
        log.warning("[payway-seam] check unreachable tran=%s", tran_id)
        return row
    except payway.PayWayError as exc:
        log.warning("[payway-seam] check refused tran=%s code=%s", tran_id, exc.code)
        return row

    patch: dict[str, Any] = {
        "last_checked_at": _iso(_now()),
        "check_count": int(row.get("check_count") or 0) + 1,
        "payment_status": status.payment_status,
        "payment_status_code": status.payment_status_code,
        "approval_code": status.approval_code or None,
        "paid_amount": status.paid_amount,
        "paid_currency": status.currency or None,
    }

    if status.approved:
        mismatch = _mismatch(row, status)
        if mismatch:
            # PayWay says money moved, but not the money we asked for. Refusing
            # to grant is the only safe answer, and the reason is recorded so it
            # is a reconciliation item rather than a silent loss.
            log.error("[payway-seam] APPROVED but %s tran=%s expected=%s %s got=%s %s",
                      mismatch, tran_id, row.get("amount"), row.get("currency"),
                      status.paid_amount, status.currency)
            patch.update({"state": FAILED, "failure_reason": mismatch})
            await _update(tran_id, patch, only_if=OPEN)
            await _fail(tran_id, mismatch)
            return await _load(tran_id) or row

        patch["state"] = VERIFIED
        await _update(tran_id, patch, only_if=OPEN)
        return await _grant(await _load(tran_id) or {**row, **patch}, status)

    if status.terminal_failure:
        patch.update({"state": FAILED,
                      "failure_reason": (status.payment_status or "DECLINED").upper()})
        await _update(tran_id, patch, only_if=OPEN)
        await _fail(tran_id, patch["failure_reason"])
        return await _load(tran_id) or row

    if expired:
        # PayWay does not say paid, and the QR's own lifetime is over. This is
        # the LAST word: the check above already gave the payment its final
        # chance to have landed.
        patch.update({"state": EXPIRED, "failure_reason": "EXPIRED"})
        await _update(tran_id, patch, only_if=OPEN)
        await _fail(tran_id, "EXPIRED", state=EXPIRED)
        return await _load(tran_id) or row

    await _update(tran_id, patch, only_if=OPEN)
    return await _load(tran_id) or row


def _may_check(row: dict) -> bool:
    """Rate-limit the REAL PayWay call, not the browser's question."""
    last = _parse_ts(row.get("last_checked_at"))
    if last is None:
        return True
    return (_now() - last).total_seconds() >= _CHECK_MIN_INTERVAL_S


def _mismatch(row: dict, status: payway.TransactionStatus) -> str:
    """'' when what was paid is what was asked. A code when it is not.

    Compared against the row, which was written from the CATALOGUE — never
    against anything a client sent. A field PayWay omits is not a mismatch (there
    is nothing to compare) but it is not a pass either: the amount is the field
    that decides, and it is always present on an approved transaction.
    """
    expected_amount = float(row.get("amount") or 0)
    paid = status.paid_amount
    if paid is None:
        return "AMOUNT_MISSING"
    # Half a cent: the two sides are decimal money, and a float round-trip
    # through JSON must not be able to fail a legitimate payment.
    if abs(paid - expected_amount) > 0.005:
        return "AMOUNT_MISMATCH"
    expected_currency = str(row.get("currency") or "").upper()
    got_currency = (status.currency or "").upper()
    if got_currency and expected_currency and got_currency != expected_currency:
        return "CURRENCY_MISMATCH"
    return ""


async def _grant(row: dict, status: payway.TransactionStatus) -> dict:
    """Hand the verified payment to the canonical Billing Engine. Nothing else.

    `store_product_id` is the SKU: a Web product has no Apple or RevenueCat id by
    construction — that absence is exactly what makes it web-sellable — so its
    canonical identifier is its sku, and `billing._resolve_product` matches on it.

    `ends_at_iso` is left None on purpose for a CREDIT_PACK. The RPC reads that,
    together with a null `duration_days`, as PERPETUAL and grants into the user's
    accumulating pack pass (migration 0007 §5). Passing a window here would
    quietly turn bought credits into expiring ones.
    """
    import billing  # noqa: PLC0415

    tran_id = row["tran_id"]
    ends_at_iso = None
    if row.get("duration_days"):
        ends_at_iso = _iso(_now() + timedelta(days=int(row["duration_days"])))

    try:
        result = await billing.grant_purchase(
            user_id=row["user_id"],
            provider=PROVIDER,
            provider_transaction_id=tran_id,
            store_product_id=row["sku"],
            amount=float(row.get("amount") or 0),
            currency=row.get("currency"),
            ends_at_iso=ends_at_iso,
            raw_payload={
                "rail": PROVIDER,
                "gateway": "payway",
                "environment": "sandbox",
                "tran_id": tran_id,
                "apv": status.approval_code,
                "payment_status": status.payment_status,
                "transaction_date": status.transaction_date,
            },
            supa=_supa(),
        )
    except billing.ProductNotMapped:
        log.error("[payway-seam] PAID but product unmapped tran=%s sku=%s — "
                  "money taken, nothing granted. Reconciliation required.",
                  tran_id, row.get("sku"))
        await _fail(tran_id, "PRODUCT_UNMAPPED")
        return await _load(tran_id) or row
    except Exception as exc:  # noqa: BLE001
        # Leave the row VERIFIED, not FAILED. A verified payment whose grant hit
        # a transient error must be retried by the next poll — marking it failed
        # would be the one way to actually lose a paid credit.
        log.error("[payway-seam] grant failed tran=%s err=%s — stays VERIFIED for retry",
                  tran_id, type(exc).__name__)
        return await _load(tran_id) or row

    log.info("[payway-seam] GRANT tran=%s status=%s credited=%s credits=%d order=%s",
             tran_id, result.status, result.credited, result.credits, result.order_id)
    await _update(tran_id, {
        "state": GRANTED,
        "granted_order_id": result.order_id,
        "granted_at": _iso(_now()),
    }, only_if=(VERIFIED, PAID_PENDING_VERIFICATION, AWAITING_PAYMENT))
    return await _load(tran_id) or {**row, "state": GRANTED}


# ── routes ───────────────────────────────────────────────────────────────────


async def _caller(authorization: str | None) -> str:
    """The authenticated user, verified against Supabase — never claimed by the
    body. Reuses the adapter's own verification so there is one token path."""
    import pwa_staging_api as api  # noqa: PLC0415

    token = api._bearer(authorization)
    async with httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=10.0)) as client:
        return await api._verify_user(client, token)


@router.get("/config")
async def payments_config() -> dict:
    """What this deployment can do, as the SERVER sees it. No secret, ever."""
    cfg = payway.redacted_config()
    return {
        "provider": PROVIDER if cfg.get("configured") else "none",
        "gateway": "payway" if cfg.get("configured") else "none",
        "configured": bool(cfg.get("configured")),
        "environment": cfg.get("environment", "none"),
        "callback_configured": cfg.get("callback_configured", False),
        "callback_signature": cfg.get("callback_signature", "required"),
        # WHICH acquisition endpoint is live. Named so a support question can be
        # answered without reading the source, and so a deployment still running
        # the deprecated rail is visible rather than assumed.
        "acquisition": cfg.get("acquisition", "none"),
        "view_type": cfg.get("view_type", ""),
        "payment_option": cfg.get("payment_option", ""),
        "return_configured": cfg.get("return_configured", False),
    }


@router.post("/checkout")
async def payments_checkout(
    body: CheckoutRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    user_id = await _caller(authorization)
    return await start_checkout(user_id=user_id, sku=body.sku,
                                attempt_key=body.attempt_key)


@router.get("/order/{tran_id}")
async def payments_order(
    tran_id: str,
    authorization: str | None = Header(default=None),
) -> dict:
    """The state of one attempt, verified server-side. THE polling endpoint.

    Every call may trigger a real Check Transaction (rate-limited), so a payment
    completes even where PayWay cannot reach us. The browser learns the outcome
    from the Billing Engine's own record — never from a redirect, a reopened tab,
    or a timer.
    """
    user_id = await _caller(authorization)
    row = await _load(tran_id)
    # Ownership is checked before existence is admitted: a wrong tran_id and
    # someone else's tran_id must be indistinguishable from outside.
    if not row or row.get("user_id") != user_id:
        raise HTTPException(
            status_code=404,
            detail={"error_code": "UNKNOWN_TRANSACTION", "retryable": False},
        )
    return public_view(await verify_and_settle(row))


@router.get("/open")
async def payments_open(
    authorization: str | None = Header(default=None),
) -> dict:
    """The attempt to restore after a refresh, a new tab, or a restart."""
    user_id = await _caller(authorization)
    row = await open_attempt_for(user_id)
    if not row:
        return {"open": False}
    return {"open": True, **public_view(await verify_and_settle(row))}


@router.post("/order/{tran_id}/cancel")
async def payments_cancel(
    tran_id: str,
    authorization: str | None = Header(default=None),
) -> dict:
    """The person closed the sheet. Cancels the ATTEMPT, never a payment.

    Deliberately verifies first: if the money arrived while they were reaching
    for the close button, the grant wins and the cancel is a no-op. Losing a paid
    credit because of a click is not a trade this system makes.
    """
    user_id = await _caller(authorization)
    row = await _load(tran_id)
    if not row or row.get("user_id") != user_id:
        raise HTTPException(
            status_code=404,
            detail={"error_code": "UNKNOWN_TRANSACTION", "retryable": False},
        )
    settled = await verify_and_settle(row, force=True)
    if settled.get("state") in TERMINAL:
        return public_view(settled)
    await _fail(tran_id, "CANCELLED", only_if=OPEN, state=CANCELLED)
    return public_view(await _load(tran_id) or settled)


@router.post("/payway/callback")
async def payway_callback(request: Request) -> dict:
    """PayWay's pushback. A DOORBELL — it is never believed, only answered.

    Contract (official Developer Suite): POST, `application/json`, body
    `{tran_id, apv, status, return_params, merchant_ref}`, signed in the
    `X-PayWay-Hmac-Sha512` header over the body fields sorted by key.

    What this does, in order:
      1. verify the signature (rejects 401 when required and wrong/absent);
      2. find OUR row for that tran_id — an unknown id is rejected, so a valid
         signature over an invented transaction still grants nothing;
      3. record that the doorbell rang;
      4. call Check Transaction and let THAT decide.

    Note what is NOT read from the body: no amount, no currency, no product, no
    user. The body's `status` field is not even consulted — a forged "status: 0"
    changes nothing, because the grant is decided by a call we make outbound.

    Always answers 200 on a legitimately-signed, known transaction, whatever the
    verification concludes: PayWay retries on a non-2xx, and re-notifying us
    about a payment we have already settled correctly would be noise.
    """
    raw = await request.body()
    try:
        body = json.loads(raw or b"{}")
    except ValueError:
        log.warning("[payway-callback] rejected: body is not JSON")
        raise HTTPException(status_code=400, detail={"error_code": "BAD_REQUEST"})
    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail={"error_code": "BAD_REQUEST"})

    cfg = _config_or_refuse()
    signature = payway.signature_from_headers(request.headers)
    signature_ok = payway.verify_pushback(body, signature, cfg.api_key)
    if not signature_ok and cfg.require_callback_signature:
        # Nothing about WHY, and nothing about the expected value: an attacker
        # gets one bit, and the operator gets the detail from the log.
        log.warning("[payway-callback] REJECTED bad/absent signature tran=%s present=%s",
                    body.get("tran_id"), bool(signature))
        raise HTTPException(status_code=401, detail={"error_code": "BAD_SIGNATURE"})

    tran_id = str(body.get("tran_id") or "")
    row = await _load(tran_id) if tran_id else None
    if not row:
        log.warning("[payway-callback] REJECTED unknown tran_id=%r", tran_id[:32])
        raise HTTPException(status_code=404, detail={"error_code": "UNKNOWN_TRANSACTION"})

    await _update(tran_id, {
        "callback_received_at": _iso(_now()),
        "callback_signature_ok": signature_ok,
        "callback_count": int(row.get("callback_count") or 0) + 1,
    })
    # A doorbell moves the rail to "someone says this is paid" — a state that
    # grants nothing and exists so the UI can say "confirming your payment".
    await _update(tran_id, {"state": PAID_PENDING_VERIFICATION},
                  only_if=(CREATED, AWAITING_PAYMENT))

    settled = await verify_and_settle(await _load(tran_id) or row, force=True)
    log.info("[payway-callback] tran=%s signature_ok=%s -> %s",
             tran_id, signature_ok, settled.get("state"))
    return {"received": True, "state": settled.get("state")}


# ── what the entitlement endpoint reports ────────────────────────────────────


def provider_id() -> str:
    """The rail this deployment sells on, or 'none'. SERVER-owned.

    `PWA_PAYMENT_PROVIDER` still wins when set, so an operator can force the
    paywall closed without removing credentials — a useful kill switch that does
    not require editing a secrets file.
    """
    forced = (os.environ.get("PWA_PAYMENT_PROVIDER") or "").strip().lower()
    if forced:
        return forced
    return PROVIDER if payway.is_configured() else "none"


def is_open() -> bool:
    """Whether a purchase can actually be completed right now."""
    return provider_id() not in ("", "none") and payway.is_configured()
