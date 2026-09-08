"""ABA PayWay — the SANDBOX rail adapter. It moves money and knows nothing else.

Scope, deliberately narrow
--------------------------
This module speaks PayWay's protocol and stops there. It does not know what a
product is, what a credit is, who the user is, or what a grant means. Those live
in `pwa_staging_payments` (the seam) and in the canonical Billing Engine (the
authority). Keeping the rail ignorant is what makes it replaceable: a second
Cambodian gateway would be a second file of this shape and nothing else.

Where every protocol fact below comes from
------------------------------------------
The OFFICIAL ABA PayWay Developer Suite, read 2026-08-18. Community
documentation was deliberately not used — `docs/PWA_MONETIZATION_AUDIT.md` §4.2
had been written from a community mirror and flagged as unverified; this module
supersedes it. Sources, one per fact:

  * base URLs                https://developer.payway.com.kh/api-endpoints-984508m0
        sandbox    https://checkout-sandbox.payway.com.kh/
        production https://checkout.payway.com.kh/
        "you can only access the API from a domain or IP address that has been
        whitelisted by PayWay" — this applies to the OUTBOUND call too, which is
        why a fresh merchant gets error code 6 before anything else works.

  * QR API                   https://developer.payway.com.kh/qr-api-14530840e0
        POST /api/payment-gateway/v1/payments/generate-qr
        Content-Type: application/json
        required : req_time, merchant_id, tran_id, payment_option, amount,
                   currency, lifetime, qr_image_template, hash
        payment_option ∈ {abapay_khqr, wechat, alipay}
        amount numeric, min 0.01 USD / 100 KHR
        lifetime in MINUTES, min 3
        hash = base64(hmac_sha512(concat, api_key)) over, IN THIS ORDER:
            req_time, merchant_id, tran_id, amount, items, first_name,
            last_name, email, phone, purchase_type, payment_option,
            callback_url, return_deeplink, currency, custom_fields,
            return_params, payout, lifetime, qr_image_template
        Absent optional fields contribute the EMPTY STRING — the documented PHP
        sample concatenates every field unconditionally, with no null branch.
        response: qrString, qrImage (base64 PNG), abapay_deeplink, app_store,
                  play_store, amount, currency, status{code,message,trace_id}
        status.code 0 = success; 1 = wrong hash; 6 = domain not whitelisted;
                    403 = duplicate transaction; 429 = rate limited.

  * Check Transaction        https://developer.payway.com.kh/check-transaction-14530826e0
        POST /api/payment-gateway/v1/payments/check-transaction-2
        Content-Type: application/json
        body : req_time, merchant_id, tran_id, hash
        hash = base64(hmac_sha512(req_time + merchant_id + tran_id, api_key))
        response: payment_status_code (0 APPROVED/PRE-AUTH, 2 PENDING,
                  3 DECLINED, 4 REFUNDED, 7 CANCELLED), payment_status,
                  total_amount, original_amount, payment_amount,
                  payment_currency, apv, refund_amount, discount_amount,
                  transaction_date, status{code,message,tran_id}
        status.code '00' = success, '5' invalid hash, '6' not found,
                    '8' invalid merchant, '11' server error, '429' rate limit.
        Only transactions younger than 7 days are visible here.

  * Pushback / callback     https://developer.payway.com.kh/ecommerce-checkout-3158159f0
        The callback endpoint "shall accept the HTTP POST method" and
        "Content-Type: application/json".
        body : {tran_id, apv, status, return_params, merchant_ref}
        signature header : X_PAYWAY_HMAC_SHA512  (arrives over the wire as
        `X-PayWay-Hmac-Sha512`; PHP exposes it as HTTP_X_PAYWAY_HMAC_SHA512)
        verification : sort the body fields by key ASCENDING, concatenate the
        values, hmac_sha512 with the api key, base64, compare with
        hash_equals().

What this module refuses to do
------------------------------
  * touch production. `PAYWAY_ENV` must be `sandbox`; anything else raises. The
    production base URL is present as a CONSTANT so the refusal can name it, and
    is unreachable through any code path here.
  * log, return, or format a secret. `PAYWAY_API_KEY` is read once into a local
    and never appears in a log line, an exception message, a response body, or a
    `repr`. `redacted_config()` is what diagnostics may print.
  * decide anything about entitlement. `check_transaction` returns facts; the
    seam decides what they are worth.
  * guess. A missing merchant id or api key raises `PayWayNotConfigured` and the
    paywall shows "payments are not open" — which is the truth, and is better
    than a Buy button that cannot complete.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Optional

import httpx

log = logging.getLogger("aih")

# ── the official endpoints ───────────────────────────────────────────────────

SANDBOX_BASE = "https://checkout-sandbox.payway.com.kh"
# Present so the refusal below can be specific. NOTHING here may dial it.
PRODUCTION_BASE = "https://checkout.payway.com.kh"

#: THE endpoint for the Ayden PWA, confirmed by ABA in writing on 2026-08-19:
#: "For website app or native app integration please use this endpoint to match
#: the guidelines". Everything the browser is sent to now comes from here.
PATH_PURCHASE = "/api/payment-gateway/v1/payments/purchase"

#: DEPRECATED for the PWA. `generate-qr` was how the rail was first proven, and
#: it still works — but it makes AYDEN the checkout, and ABA's guideline is that
#: ABA is. Kept because deleting a proven adapter to prove a point is how you
#: lose the ability to compare two behaviours. Nothing in the PWA path calls it.
PATH_GENERATE_QR = "/api/payment-gateway/v1/payments/generate-qr"
PATH_CHECK_TRANSACTION = "/api/payment-gateway/v1/payments/check-transaction-2"

# The pushback signature header, in the two spellings a real request can carry.
# Starlette lowercases and treats `-`/`_` as distinct, so both are looked up.
SIGNATURE_HEADERS = ("x-payway-hmac-sha512", "x_payway_hmac_sha512")

#: `payment_option` for a KHQR payment on the DEPRECATED generate-qr path.
PAYMENT_OPTION_KHQR = "abapay_khqr"

#: `payment_option` values the Purchase API documents. Sending NOTHING is also
#: documented and is what this integration does by default: PayWay then shows
#: its own payment-option chooser, which is precisely the piece of UI ABA's
#: guideline says belongs to ABA and not to us.
PAYMENT_OPTION_KHQR_DEEPLINK = "abapay_khqr_deeplink"
PAYMENT_OPTIONS = ("", "cards", "abapay_khqr", "abapay_khqr_deeplink",
                   "alipay", "wechat", "google_pay")

#: `view_type` values the Purchase API documents.
#:   hosted_view — PayWay's own checkout page, full navigation
#:   popup       — bottom sheet on mobile, modal on desktop, hosted by PayWay's
#:                 own JavaScript inside the merchant page
VIEW_TYPE_HOSTED = "hosted_view"
VIEW_TYPE_POPUP = "popup"
VIEW_TYPES = (VIEW_TYPE_HOSTED, VIEW_TYPE_POPUP)

#: `payment_gate = 0` selects the Checkout service, per the Purchase page.
PAYMENT_GATE_CHECKOUT = 0

#: How long a PayWay CHECKOUT URL stays usable — measured, not documented.
#:
#: A checkout token is NOT the transaction. The sandbox answered, inside the
#: base64 payload of the checkout URL itself on 2026-08-19:
#:
#:     "token_time": 1787716747, "expire_in": 1787716927, "expire_in_sec": "180"
#:
#: — 180 seconds, on a request that asked for `lifetime = 30` MINUTES. The two
#: numbers measure different things: `lifetime` is how long PayWay will accept a
#: payment for the transaction, and this is how long the LINK to the payment page
#: survives. Confusing them hands a customer a dead URL and calls it a live
#: payment, which looks exactly like a bug in Ayden.
#:
#: The value is not parsed out of the URL: that blob is opaque, undocumented, and
#: not a contract. It is used as an age limit on our own issue time instead, which
#: is conservative in the right direction — a checkout we call stale might still
#: work, and one we call live never surprises the customer.
CHECKOUT_TOKEN_TTL_S = 180

#: `payment_status_code` values from Check Transaction, named.
STATUS_APPROVED = 0
STATUS_PENDING = 2
STATUS_DECLINED = 3
STATUS_REFUNDED = 4
STATUS_CANCELLED = 7

#: `status.code` of a SUCCESSFUL Check Transaction envelope. PayWay sends the
#: two-character form; a bare '0' is accepted because the QR API uses that.
_CHECK_OK = ("00", "0", 0)


class PayWayError(RuntimeError):
    """PayWay answered, and the answer was not usable.

    `code` is PayWay's own status code so the caller can branch on the documented
    vocabulary (6 = not whitelisted, 403 = duplicate tran_id) rather than on a
    message. Never carries a secret: the message is built from PayWay's reply and
    the request's PUBLIC fields only.
    """

    def __init__(self, message: str, *, code: Any = None, trace_id: str = ""):
        self.code = code
        self.trace_id = trace_id
        super().__init__(message)


class PayWayNotConfigured(RuntimeError):
    """No usable sandbox credentials. A refusal, never a fallback."""


class PayWayUnreachable(RuntimeError):
    """The transport failed — PayWay said nothing at all. Retryable."""


# ── configuration ────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class PayWayConfig:
    """Resolved PayWay configuration. Holds the api key; never prints it."""

    merchant_id: str
    api_key: str
    base_url: str
    environment: str
    callback_url: str
    require_callback_signature: bool
    lifetime_minutes: int
    qr_template: str
    currency: str
    #: Purchase API presentation. Empty `payment_option` = PayWay shows its own
    #: chooser, which is the default and what ABA's guideline asks for.
    payment_option: str = ""
    view_type: str = VIEW_TYPE_HOSTED
    #: Where PayWay sends the BROWSER back to. Not a callback: no money decision
    #: is ever made from a redirect. Empty is allowed — the customer then lands
    #: on PayWay's own end page and the PWA reconciles on its next poll.
    return_base_url: str = ""

    @property
    def has_return_target(self) -> bool:
        return bool(self.return_base_url)

    @property
    def has_public_callback(self) -> bool:
        """Whether PayWay can actually reach us.

        False is a supported mode, not a broken one: the grant is driven by
        Check Transaction, which the SERVER calls, so a deployment with no public
        hostname still completes a payment correctly — it just learns about it
        when it asks instead of when it is told. See `pwa_staging_payments`.
        """
        return bool(self.callback_url)

    def __repr__(self) -> str:  # pragma: no cover — belt and braces
        return (f"PayWayConfig(merchant_id={self.merchant_id!r}, "
                f"environment={self.environment!r}, api_key=<redacted>)")


def _env(name: str, default: str = "") -> str:
    return (os.environ.get(name) or default).strip()


def is_configured() -> bool:
    """Can this deployment take money right now? Read-only, never raises."""
    try:
        load_config()
        return True
    except (PayWayNotConfigured, ValueError):
        return False


def load_config() -> PayWayConfig:
    """Resolve the sandbox configuration, or refuse.

    Fail-closed on every axis: absent credentials, a non-sandbox environment, an
    unusable callback URL. There is deliberately no code path that substitutes a
    production credential for a missing sandbox one.
    """
    merchant_id = _env("PAYWAY_MERCHANT_ID")
    api_key = _env("PAYWAY_API_KEY")
    if not merchant_id or not api_key:
        missing = [n for n, v in (("PAYWAY_MERCHANT_ID", merchant_id),
                                  ("PAYWAY_API_KEY", api_key)) if not v]
        raise PayWayNotConfigured(
            "ABA PayWay sandbox credentials are absent: "
            + ", ".join(missing)
            + ". Set them in backend/.env.pwa-staging.local (gitignored).")

    environment = (_env("PAYWAY_ENV", "sandbox")).lower()
    if environment not in ("sandbox", "production"):
        # Named explicitly rather than silently downgraded: an operator who
        # typed something else must see the refusal, not quietly run against a
        # gateway they did not ask for.
        raise PayWayNotConfigured(
            f"PAYWAY_ENV={environment!r} is not a PayWay environment. "
            f"Use 'sandbox' or 'production'.")

    callback_url = _env("PAYWAY_CALLBACK_URL")
    if callback_url:
        _assert_public_callback(callback_url)

    # ── The production gate (2026-09-04) ────────────────────────────────────
    #
    # `production` used to be refused outright, and that was right for as long
    # as no production deployment existed. It is replaced by CONDITIONS rather
    # than by a flag: real money may only move from a process that is itself a
    # production deployment, that can be TOLD about a payment, that refuses an
    # unsigned doorbell, and that knows where to send the browser back. Each
    # condition is its own sentence so a failure names exactly what is missing.
    #
    # What is deliberately NOT relaxed: the authority rule. In production too,
    # the pushback is a doorbell — `check_transaction` decides and the Billing
    # Engine grants.
    if environment == "production":
        import pwa_target  # local: payway.py stays importable on its own

        if not pwa_target.current().is_production:
            raise PayWayNotConfigured(
                "PAYWAY_ENV=production requires PWA_TARGET=production. A "
                "staging deployment may not move real money.")
        if not callback_url:
            raise PayWayNotConfigured(
                "PAYWAY_ENV=production requires PAYWAY_CALLBACK_URL. A rail "
                "that cannot be told about a payment is poll-only, which is "
                "not acceptable for real money.")
        if _env("PAYWAY_CALLBACK_SIGNATURE_MODE", "required").lower() == "optional":
            raise PayWayNotConfigured(
                "PAYWAY_ENV=production refuses "
                "PAYWAY_CALLBACK_SIGNATURE_MODE=optional: an unsigned pushback "
                "must never be accepted in production.")
        if not _env("PAYWAY_RETURN_BASE_URL"):
            raise PayWayNotConfigured(
                "PAYWAY_ENV=production requires PAYWAY_RETURN_BASE_URL so the "
                "browser returns to the production app.")

    try:
        lifetime = int(_env("PAYWAY_QR_LIFETIME_MINUTES", "30"))
    except ValueError as exc:
        raise ValueError("PAYWAY_QR_LIFETIME_MINUTES must be an integer") from exc
    # PayWay's documented floor is 3 minutes. Below it the call is rejected, so
    # this is clamped rather than sent and refused.
    lifetime = max(3, lifetime)

    currency = (_env("PAYWAY_CURRENCY", "USD")).upper()
    if currency not in ("USD", "KHR"):
        raise ValueError(f"PAYWAY_CURRENCY must be USD or KHR (got {currency!r})")

    # Both are validated against the DOCUMENTED sets rather than passed through.
    # An unrecognised value would be signed, sent, and refused by PayWay with a
    # generic error — far harder to read than a refusal at boot that names it.
    payment_option = _env("PAYWAY_PAYMENT_OPTION", "").lower()
    if payment_option not in PAYMENT_OPTIONS:
        raise ValueError(
            f"PAYWAY_PAYMENT_OPTION={payment_option!r} is not documented. "
            f"Use one of {PAYMENT_OPTIONS!r} (empty = PayWay's own chooser).")

    view_type = _env("PAYWAY_VIEW_TYPE", VIEW_TYPE_HOSTED).lower()
    if view_type not in VIEW_TYPES:
        raise ValueError(
            f"PAYWAY_VIEW_TYPE={view_type!r} is not documented. "
            f"Use one of {VIEW_TYPES!r}.")

    return_base_url = _env("PAYWAY_RETURN_BASE_URL")
    if return_base_url:
        _assert_browser_reachable(return_base_url)

    return PayWayConfig(
        merchant_id=merchant_id,
        api_key=api_key,
        base_url=PRODUCTION_BASE if environment == "production" else SANDBOX_BASE,
        environment=environment,
        callback_url=callback_url,
        require_callback_signature=(
            _env("PAYWAY_CALLBACK_SIGNATURE_MODE", "required").lower() != "optional"),
        lifetime_minutes=lifetime,
        qr_template=_env("PAYWAY_QR_TEMPLATE", "template3_color"),
        currency=currency,
        payment_option=payment_option,
        view_type=view_type,
        return_base_url=return_base_url.rstrip("/"),
    )


def _assert_browser_reachable(url: str) -> None:
    """The return target is walked by a BROWSER, not by PayWay's servers.

    So loopback is legitimate here in a way it never is for `callback_url`: the
    person paying is sitting at the machine serving `127.0.0.1:8103`, and PayWay
    only has to hand their browser the address. The check is therefore about
    shape — an absolute http(s) URL with a host — and not about reachability
    from the public internet.
    """
    from urllib.parse import urlparse  # noqa: PLC0415

    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise ValueError(
            f"PAYWAY_RETURN_BASE_URL must be an absolute http(s) URL "
            f"(got {url!r}).")


def _assert_public_callback(url: str) -> None:
    """A callback URL PayWay cannot reach is worse than none.

    None is an honest mode (poll-only). A loopback URL, by contrast, LOOKS
    configured and then silently never fires, which is indistinguishable from a
    payment that never happened — so it is refused at configuration time.
    """
    from urllib.parse import urlparse  # noqa: PLC0415

    parsed = urlparse(url)
    host = (parsed.hostname or "").lower()
    if parsed.scheme != "https":
        raise ValueError(
            f"PAYWAY_CALLBACK_URL must be https (got scheme {parsed.scheme!r}).")
    if not host:
        raise ValueError("PAYWAY_CALLBACK_URL has no host.")
    if host in ("localhost", "127.0.0.1", "::1", "0.0.0.0") or host.endswith(".local"):
        raise ValueError(
            f"PAYWAY_CALLBACK_URL host {host!r} is not reachable from the "
            f"Internet. PayWay pushes server-to-server; leave the variable "
            f"EMPTY to run poll-only instead of configuring a callback that "
            f"can never arrive.")


def redacted_config() -> dict:
    """What diagnostics and health endpoints may say about PayWay.

    Never the api key, and never the merchant id in full — a merchant id is not
    a secret, but it is an identifier of the account being charged and there is
    no reason for a browser to learn it.
    """
    try:
        cfg = load_config()
    except (PayWayNotConfigured, ValueError) as exc:
        return {"configured": False, "environment": "none",
                "reason": type(exc).__name__}
    return {
        "configured": True,
        "environment": cfg.environment,
        "base_url": cfg.base_url,
        "merchant_id_suffix": cfg.merchant_id[-4:],
        "callback_configured": cfg.has_public_callback,
        "callback_signature": (
            "required" if cfg.require_callback_signature else "optional"),
        "lifetime_minutes": cfg.lifetime_minutes,
        "currency": cfg.currency,
        # The ACTIVE acquisition endpoint, stated rather than assumed. A
        # deployment still on `generate-qr` would say so here.
        "acquisition": "purchase",
        "view_type": cfg.view_type,
        # Empty is the normal answer and means "PayWay shows its own chooser".
        "payment_option": cfg.payment_option,
        "return_configured": cfg.has_return_target,
    }


# ── signing ──────────────────────────────────────────────────────────────────


def req_time(now: Optional[datetime] = None) -> str:
    """`req_time` as PayWay defines it: UTC, YYYYMMDDHHmmss."""
    moment = now or datetime.now(timezone.utc)
    return moment.astimezone(timezone.utc).strftime("%Y%m%d%H%M%S")


def sign(payload: str, api_key: str) -> str:
    """base64(hmac_sha512(payload, api_key)) — the ONE signing primitive.

    Every hash PayWay wants is this function over a different concatenation, so
    there is exactly one place where the key touches a digest.
    """
    digest = hmac.new(api_key.encode("utf-8"), payload.encode("utf-8"),
                      hashlib.sha512).digest()
    return base64.b64encode(digest).decode("ascii")


def format_amount(amount: float | int | str, currency: str) -> str:
    """The amount string used in BOTH the body and the hash.

    One function, because the two must be byte-identical: PayWay hashes the
    string it receives, so an amount formatted `7.99` in the body and `7.990` in
    the digest is a wrong-hash rejection that looks like a credentials problem.

    KHR has no minor unit — PayWay's own minimum is `100`, an integer — so it is
    formatted without decimals, and USD with exactly two.
    """
    value = float(amount)
    return f"{value:.0f}" if currency.upper() == "KHR" else f"{value:.2f}"


def _b64(value: str) -> str:
    """PayWay takes several fields base64-encoded (callback_url, items, …)."""
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


#: The QR API hash, in the documented order. Kept as data rather than an f-string
#: so the order is reviewable against the official page in one glance, and so the
#: test can assert the order itself instead of a hard-coded digest.
QR_HASH_FIELDS = (
    "req_time", "merchant_id", "tran_id", "amount", "items", "first_name",
    "last_name", "email", "phone", "purchase_type", "payment_option",
    "callback_url", "return_deeplink", "currency", "custom_fields",
    "return_params", "payout", "lifetime", "qr_image_template",
)


def qr_hash_payload(body: dict) -> str:
    """Concatenate the QR API fields in the documented order.

    Absent fields contribute the empty string — the official PHP sample
    concatenates all nineteen unconditionally, with no null handling.
    """
    return "".join(str(body.get(name, "")) for name in QR_HASH_FIELDS)


def build_qr_request(
    *,
    cfg: PayWayConfig,
    tran_id: str,
    amount: float | int | str,
    currency: str = "",
    lifetime_minutes: Optional[int] = None,
    return_params: str = "",
    now: Optional[datetime] = None,
) -> dict:
    """The signed generate-qr body. Pure — no I/O, so a test can read the hash.

    `return_params` is echoed back verbatim on the pushback. It carries our
    `tran_id`-derived correlation only; never a user id, never a token. The
    server already knows who owns a `tran_id` and reads it from the database, so
    putting identity into a field that travels through a third party would be
    exposure with no benefit.

    Deliberately NOT sent: first_name / last_name / email / phone. PayWay treats
    them as optional and the Cambodian KHQR flow does not need them, so no
    personal data leaves Ayden for a payment that does not require it.
    """
    body: dict[str, Any] = {
        "req_time": req_time(now),
        "merchant_id": cfg.merchant_id,
        "tran_id": tran_id,
        "amount": format_amount(amount, currency or cfg.currency),
        "payment_option": PAYMENT_OPTION_KHQR,
        "currency": (currency or cfg.currency).upper(),
        "lifetime": int(lifetime_minutes or cfg.lifetime_minutes),
        "qr_image_template": cfg.qr_template,
    }
    if cfg.has_public_callback:
        # Base64 per the spec. Absent when no public hostname exists — PayWay
        # then has nowhere to push, and the seam relies on Check Transaction.
        body["callback_url"] = _b64(cfg.callback_url)
    if return_params:
        body["return_params"] = return_params
    body["hash"] = sign(qr_hash_payload(body), cfg.api_key)
    return body


#: The PURCHASE hash, in the documented order — twenty-four fields, and note
#: that it is NOT the QR order with extras appended: `shipping` sits between
#: `items` and `firstname`, the name fields lose their underscores, `type`
#: replaces `purchase_type`, and `skip_success_page` comes LAST, after
#: `google_pay_token`. Reordering any of it yields status code 1, wrong hash.
PURCHASE_HASH_FIELDS = (
    "req_time", "merchant_id", "tran_id", "amount", "items", "shipping",
    "firstname", "lastname", "email", "phone", "type", "payment_option",
    "return_url", "cancel_url", "continue_success_url", "return_deeplink",
    "currency", "custom_fields", "return_params", "payout", "lifetime",
    "additional_params", "google_pay_token", "skip_success_page",
)


def purchase_hash_payload(body: dict) -> str:
    """Concatenate the Purchase fields in the documented order.

    Absent fields contribute the empty string, exactly as for the QR API: the
    official sample builds one string from all twenty-four unconditionally.
    """
    return "".join(str(body.get(name, "")) for name in PURCHASE_HASH_FIELDS)


def build_purchase_request(
    *,
    cfg: PayWayConfig,
    tran_id: str,
    amount: float | int | str,
    currency: str = "",
    lifetime_minutes: Optional[int] = None,
    return_params: str = "",
    continue_success_url: str = "",
    cancel_url: str = "",
    skip_success_page: bool = False,
    now: Optional[datetime] = None,
) -> dict:
    """The signed Purchase body. Pure — no I/O, so a test can read the hash.

    `skip_success_page` (ABA merchant review, 2026-09-08). ABA's reviewer:
    "You already have your own success screen. So you can skip ABA success
    screen by submit parameter: skip_success_page = 1". It is the LAST of the
    twenty-four hashed fields, so it is set before the hash below, as the
    literal "1", and only when asked for — the dormant server-side path keeps
    sending nothing, exactly as before.

    Encoding, and why each field is treated differently
    ---------------------------------------------------
    The Purchase page is specific and inconsistent, so this follows it literally
    rather than tidying it into a rule:

        return_url            "encrypted with Base64"   -> base64
        return_deeplink       "must be base64-encoded"  -> base64
        cancel_url            no encoding stated        -> sent plain
        continue_success_url  no encoding stated        -> sent plain

    Inventing base64 for the last two would be exactly the kind of guess §10 of
    the brief forbids, and the hash is computed over whatever is SENT — so a
    wrong guess is a wrong signature, not a cosmetic difference.

    What is deliberately not sent
    -----------------------------
    firstname / lastname / email / phone. PayWay marks all four optional, the
    KHQR journey does not need them, and a payment is not a reason to hand a
    third party someone's name. They still take part in the hash, as empty
    strings, because the concatenation is positional.
    """
    body: dict[str, Any] = {
        "req_time": req_time(now),
        "merchant_id": cfg.merchant_id,
        "tran_id": tran_id,
        "amount": format_amount(amount, currency or cfg.currency),
        "type": "purchase",
        "currency": (currency or cfg.currency).upper(),
        "lifetime": int(lifetime_minutes or cfg.lifetime_minutes),
        # Documented as "set to 0 to use Checkout service", which is the whole
        # point of this migration: ABA's checkout, not ours.
        "payment_gate": PAYMENT_GATE_CHECKOUT,
    }
    # Empty means "let PayWay show its own chooser" — a documented mode, and the
    # default here. Sending a value narrows the customer's options, so it is a
    # deployment decision rather than something baked into the code.
    if cfg.payment_option:
        body["payment_option"] = cfg.payment_option
    if cfg.view_type:
        body["view_type"] = cfg.view_type
    if cfg.has_public_callback:
        body["return_url"] = _b64(cfg.callback_url)
    if continue_success_url:
        body["continue_success_url"] = continue_success_url
    if cancel_url:
        body["cancel_url"] = cancel_url
    if return_params:
        body["return_params"] = return_params
    if skip_success_page:
        body["skip_success_page"] = "1"
    body["hash"] = sign(purchase_hash_payload(body), cfg.api_key)
    return body


def build_check_request(*, cfg: PayWayConfig, tran_id: str,
                        now: Optional[datetime] = None) -> dict:
    """The signed check-transaction-2 body. Hash = req_time+merchant_id+tran_id."""
    body = {
        "req_time": req_time(now),
        "merchant_id": cfg.merchant_id,
        "tran_id": tran_id,
    }
    body["hash"] = sign(
        f"{body['req_time']}{body['merchant_id']}{body['tran_id']}", cfg.api_key)
    return body


# ── pushback verification ────────────────────────────────────────────────────


def pushback_hash_payload(body: dict) -> str:
    """The pushback digest input: fields sorted by key ASCENDING, values joined.

    Lists and dicts are serialised as compact JSON. PayWay's own sample sends
    scalars only (`tran_id`, `apv`, `status`, `return_params`, `merchant_ref`),
    but a field that ever arrives structured must hash deterministically rather
    than through `str(dict)`, whose ordering is an implementation detail.

    `hash` itself, if PayWay ever put it in the body, is excluded — a signature
    cannot cover itself.
    """
    parts = []
    for key in sorted(k for k in body if k != "hash"):
        value = body[key]
        if isinstance(value, (dict, list)):
            parts.append(json.dumps(value, separators=(",", ":"),
                                    ensure_ascii=False, sort_keys=True))
        elif value is None:
            parts.append("")
        elif isinstance(value, bool):
            parts.append("true" if value else "false")
        else:
            parts.append(str(value))
    return "".join(parts)


def signature_from_headers(headers) -> str:
    """The pushback signature, whichever documented spelling arrived."""
    for name in SIGNATURE_HEADERS:
        value = headers.get(name)
        if value:
            return value.strip()
    return ""


def verify_pushback(body: dict, signature: str, api_key: str) -> bool:
    """True when `signature` is PayWay's over `body`. Constant-time.

    `hmac.compare_digest` is the Python equivalent of the `hash_equals()` the
    official sample uses, and the reason is the same: a byte-by-byte `==` on a
    MAC leaks how much of a forgery was right.
    """
    if not signature:
        return False
    expected = sign(pushback_hash_payload(body), api_key)
    return hmac.compare_digest(expected, signature)


# ── transport ────────────────────────────────────────────────────────────────

#: PayWay is a bank gateway on a Cambodian network; 20 s is generous for a JSON
#: round trip and short enough that a browser polling us is not left hanging.
_TIMEOUT = httpx.Timeout(20.0, connect=10.0)


async def _post(cfg: PayWayConfig, path: str, body: dict) -> dict:
    """POST JSON to PayWay and return the parsed envelope.

    Raises `PayWayUnreachable` on transport failure (retryable) and `PayWayError`
    on a non-2xx or unparseable answer. The `hash` is stripped from anything that
    could be logged: it is derived from the api key, and §2 of the brief forbids
    logging "hashes derived from secret".
    """
    url = cfg.base_url.rstrip("/") + path
    safe = {k: v for k, v in body.items() if k != "hash"}
    log.info("[payway] POST %s tran_id=%s fields=%s", path,
             body.get("tran_id", "-"), sorted(safe))
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            res = await client.post(url, json=body,
                                    headers={"Content-Type": "application/json"})
    except httpx.HTTPError as exc:
        raise PayWayUnreachable(
            f"PayWay {path} unreachable: {type(exc).__name__}") from exc

    if res.status_code >= 500:
        raise PayWayUnreachable(f"PayWay {path} returned {res.status_code}")
    try:
        data = res.json()
    except ValueError as exc:
        raise PayWayError(
            f"PayWay {path} returned non-JSON (HTTP {res.status_code})") from exc
    if not isinstance(data, dict):
        raise PayWayError(f"PayWay {path} returned {type(data).__name__}, not an object")
    return data


async def _post_multipart(cfg: PayWayConfig, path: str,
                          body: dict) -> "httpx.Response":
    """POST `multipart/form-data` and return the RAW response.

    Purchase is not a JSON endpoint. Its page says `multipart/form-data`, and its
    answer is not one shape but three — measured against the sandbox on
    2026-08-19, with a signed request in each mode:

        payment_option=abapay_khqr_deeplink  -> HTTP 200, application/json,
                                                {qr_string, abapay_deeplink,
                                                 checkout_qr_url, status}
        view_type=hosted_view                -> HTTP 302, Location: <checkout>
        view_type=popup                      -> HTTP 302, Location: <checkout>

    So the raw response is what comes back here, redirects deliberately NOT
    followed: the `Location` is the answer. Following it would fetch PayWay's
    checkout HTML into our process, which is both useless and the beginning of
    proxying somebody else's payment page.

    `httpx` sends a multipart body when every part is a `(None, value)` tuple —
    that is what makes these fields form parts rather than file uploads.
    """
    url = cfg.base_url.rstrip("/") + path
    safe = {k: v for k, v in body.items() if k != "hash"}
    log.info("[payway] POST %s tran_id=%s fields=%s", path,
             body.get("tran_id", "-"), sorted(safe))
    files = {key: (None, str(value)) for key, value in body.items()}
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT,
                                     follow_redirects=False) as client:
            return await client.post(url, files=files)
    except httpx.HTTPError as exc:
        raise PayWayUnreachable(
            f"PayWay {path} unreachable: {type(exc).__name__}") from exc


def _status(data: dict) -> tuple[Any, str, str]:
    """(code, message, trace/tran id) from PayWay's `status` envelope."""
    status = data.get("status")
    if not isinstance(status, dict):
        return (None, "", "")
    return (status.get("code"), str(status.get("message") or ""),
            str(status.get("trace_id") or status.get("tran_id") or ""))


@dataclass(frozen=True)
class PurchaseCheckout:
    """Where to send the BROWSER, and nothing more.

    The single field that matters is [checkout_url]: an address on PayWay's own
    domain, hosting PayWay's own checkout. Ayden's job ends when it hands that
    over. `qr_string` and `deeplink` are populated only in the
    `abapay_khqr_deeplink` mode and are carried for continuity with the KHQR rail
    — they are the payment request itself, public by nature, and never a reason
    for Ayden to draw its own version of ABA's screen.

    There is deliberately no `paid`, no `status` and no `approved` here. A
    checkout is a place to pay, not a payment; the only thing that may say money
    moved is Check Transaction, called by the server.
    """

    tran_id: str
    checkout_url: str
    mode: str                # 'redirect' | 'json' — how PayWay answered
    qr_string: str = ""
    deeplink: str = ""
    trace_id: str = ""

    @property
    def public(self) -> dict:
        return {
            "checkout_url": self.checkout_url,
            "qr_string": self.qr_string,
            "deeplink": self.deeplink,
        }


async def purchase(
    *,
    cfg: PayWayConfig,
    tran_id: str,
    amount: float | int | str,
    currency: str = "",
    lifetime_minutes: Optional[int] = None,
    return_params: str = "",
    continue_success_url: str = "",
    cancel_url: str = "",
) -> PurchaseCheckout:
    """Open a PayWay checkout for `tran_id`. THE acquisition call for the PWA.

    One call per `tran_id`, ever — PayWay refuses a repeat with "Duplicated
    Transaction ID", which is not an obstacle but the gateway enforcing the same
    exactly-once rule the seam does, one layer lower.

    Three answers are accepted because the gateway gives three, all measured:

      * **302** — the documented `hosted_view` / `popup` path. `Location` is the
        checkout. This is the default mode.
      * **200 + JSON** — the `abapay_khqr_deeplink` path. `checkout_qr_url` is
        the checkout; `qr_string` and `abapay_deeplink` come with it.
      * **200 + HTML** — no checkout URL to extract. Treated as an error rather
        than returned, because the alternative is proxying PayWay's page through
        Ayden, which is exactly what ABA's guideline says not to do.
    """
    body = build_purchase_request(
        cfg=cfg, tran_id=tran_id, amount=amount, currency=currency,
        lifetime_minutes=lifetime_minutes, return_params=return_params,
        continue_success_url=continue_success_url, cancel_url=cancel_url)
    res = await _post_multipart(cfg, PATH_PURCHASE, body)

    if res.status_code in (301, 302, 303, 307, 308):
        location = res.headers.get("location", "")
        if not location:
            raise PayWayError(
                f"PayWay purchase returned {res.status_code} with no Location")
        log.info("[payway] checkout opened tran_id=%s mode=redirect", tran_id)
        return PurchaseCheckout(tran_id=tran_id, checkout_url=location,
                                mode="redirect")

    if res.status_code >= 500:
        raise PayWayUnreachable(f"PayWay purchase returned {res.status_code}")

    content_type = res.headers.get("content-type", "")
    if "json" not in content_type.lower():
        # An HTML body here is usually PayWay rendering an error page. Its text
        # is not a contract, so it is not parsed — only its absence of a URL is
        # reported, and the seam turns that into a refusal the client can act on.
        raise PayWayError(
            f"PayWay purchase returned {content_type or 'no content-type'} "
            f"(HTTP {res.status_code}) — no checkout URL to hand over")

    try:
        data = res.json()
    except ValueError as exc:
        raise PayWayError("PayWay purchase returned unparseable JSON") from exc
    if not isinstance(data, dict):
        raise PayWayError("PayWay purchase returned a non-object")

    code, message, trace = _status(data)
    checkout_url = str(data.get("checkout_qr_url") or "")
    if str(code) not in ("0", "00") or not checkout_url:
        raise PayWayError(
            f"PayWay purchase refused: {message or 'no checkout url'}",
            code=code, trace_id=trace)

    log.info("[payway] checkout opened tran_id=%s mode=json", tran_id)
    return PurchaseCheckout(
        tran_id=tran_id,
        checkout_url=checkout_url,
        mode="json",
        qr_string=str(data.get("qr_string") or ""),
        deeplink=str(data.get("abapay_deeplink") or ""),
        trace_id=trace,
    )


@dataclass(frozen=True)
class QrPayment:
    """What PayWay handed back for a KHQR payment request.

    Nothing here is a secret. `qr_string` and `qr_image` are the payment request
    a payer scans, `deeplink` opens ABA Mobile on the same request — all three
    are meant to be shown to the person paying, which is why they may safely
    reach the browser while the api key never does.
    """

    tran_id: str
    qr_string: str
    qr_image: str            # base64 PNG, as PayWay returns it
    deeplink: str            # abapay_deeplink — opens ABA Mobile
    app_store: str
    play_store: str
    amount: str
    currency: str
    trace_id: str

    @property
    def public(self) -> dict:
        return {
            "qr_string": self.qr_string,
            "qr_image": self.qr_image,
            "deeplink": self.deeplink,
            "app_store": self.app_store,
            "play_store": self.play_store,
        }


async def generate_qr(
    *,
    cfg: PayWayConfig,
    tran_id: str,
    amount: float | int | str,
    currency: str = "",
    lifetime_minutes: Optional[int] = None,
    return_params: str = "",
) -> QrPayment:
    """Create a KHQR payment request. One call per `tran_id`, ever.

    PayWay answers 403 "duplicate transaction" for a `tran_id` it has already
    seen. That is not a problem to work around — it is the rail's own idempotence
    guarantee, and the seam relies on it: a deterministic `tran_id` means a
    replay cannot create a second payment even if our own bookkeeping were lost.
    """
    body = build_qr_request(cfg=cfg, tran_id=tran_id, amount=amount,
                            currency=currency, lifetime_minutes=lifetime_minutes,
                            return_params=return_params)
    data = await _post(cfg, PATH_GENERATE_QR, body)
    code, message, trace = _status(data)
    if str(code) not in ("0", "00"):
        raise PayWayError(f"generate-qr refused (code={code}): {message}",
                          code=code, trace_id=trace)
    return QrPayment(
        tran_id=tran_id,
        qr_string=str(data.get("qrString") or ""),
        qr_image=str(data.get("qrImage") or ""),
        deeplink=str(data.get("abapay_deeplink") or ""),
        app_store=str(data.get("app_store") or ""),
        play_store=str(data.get("play_store") or ""),
        amount=str(data.get("amount") or body["amount"]),
        currency=str(data.get("currency") or body["currency"]),
        trace_id=trace,
    )


@dataclass(frozen=True)
class TransactionStatus:
    """The AUTHORITY on whether money moved. Facts only — no entitlement.

    `approved` is the single predicate the seam is allowed to act on, and it is
    deliberately conjunctive: the envelope must be a success AND the payment
    status must be APPROVED. A `status.code` of 6 ("not found") with a default
    `payment_status_code` must never read as paid.
    """

    tran_id: str
    envelope_code: Any
    envelope_message: str
    payment_status_code: Optional[int]
    payment_status: str
    total_amount: Optional[float]
    payment_amount: Optional[float]
    currency: str
    approval_code: str
    transaction_date: str
    raw: dict

    @property
    def found(self) -> bool:
        return self.envelope_code in _CHECK_OK

    @property
    def approved(self) -> bool:
        return self.found and self.payment_status_code == STATUS_APPROVED

    @property
    def pending(self) -> bool:
        return self.found and self.payment_status_code == STATUS_PENDING

    @property
    def terminal_failure(self) -> bool:
        """Declined / cancelled / refunded — stop asking, this will not become paid."""
        return self.found and self.payment_status_code in (
            STATUS_DECLINED, STATUS_CANCELLED, STATUS_REFUNDED)

    @property
    def paid_amount(self) -> Optional[float]:
        """What was actually charged.

        `payment_amount` is documented as "the amount that customer has paid" and
        is therefore the figure to compare against the order. `total_amount` (the
        amount after discount) is the fallback.

        MEASURED 2026-08-19, sandbox: an UNPAID transaction comes back with
        `payment_amount: 0` and `total_amount: 1.99` — the field is present and
        zero rather than absent. So "absent" cannot be `is None` here: a zero is
        the gateway saying "nothing has been paid yet", and PayWay's own minimum
        is 0.01 USD / 100 KHR, so no legitimate payment is ever 0. Treating it as
        not-reported is what stops an approved transaction whose `payment_amount`
        the gateway did not fill from being refused as an AMOUNT_MISMATCH.
        """
        if self.payment_amount:
            return self.payment_amount
        return self.total_amount


def _as_float(value: Any) -> Optional[float]:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _as_int(value: Any) -> Optional[int]:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


async def check_transaction(*, cfg: PayWayConfig, tran_id: str) -> TransactionStatus:
    """Ask PayWay what really happened to `tran_id`.

    This is the verification the brief requires before any grant, and it is also
    what makes a deployment without a public callback correct rather than broken:
    the answer does not depend on PayWay being able to reach us.
    """
    body = build_check_request(cfg=cfg, tran_id=tran_id)
    envelope = await _post(cfg, PATH_CHECK_TRANSACTION, body)
    code, message, _ = _status(envelope)

    # WHERE THE PAYMENT FIELDS REALLY LIVE.
    #
    # The Developer Suite documents `payment_status_code`, `total_amount`, `apv`
    # and the rest at the TOP LEVEL of the response. The sandbox does not put
    # them there. Measured 2026-08-19, verbatim:
    #
    #   {"data": {"payment_status_code": 2, "total_amount": 1.99,
    #             "payment_amount": 0, "payment_currency": "", "apv": "",
    #             "payment_status": "PENDING",
    #             "transaction_date": "2026-08-19 01:57:38"},
    #    "status": {"code": "00", "message": "Success!", "tran_id": "A2342..."}}
    #
    # Reading the top level therefore yielded `payment_status_code = None` for
    # every transaction, which `approved` correctly refuses — so the failure mode
    # was fail-SAFE (nothing would ever have been granted) and completely silent
    # (a paid customer would have waited forever). Only a real gateway call could
    # have found it; no amount of reading the page would have.
    #
    # Both shapes are accepted, `data` first, because the documentation may
    # describe an older or a future response and neither should break this.
    payload = envelope.get("data")
    payload = payload if isinstance(payload, dict) else envelope

    status = TransactionStatus(
        tran_id=tran_id,
        envelope_code=code,
        envelope_message=message,
        payment_status_code=_as_int(payload.get("payment_status_code")),
        payment_status=str(payload.get("payment_status") or ""),
        total_amount=_as_float(payload.get("total_amount")),
        payment_amount=_as_float(payload.get("payment_amount")),
        currency=str(payload.get("payment_currency") or ""),
        approval_code=str(payload.get("apv") or ""),
        transaction_date=str(payload.get("transaction_date") or ""),
        raw={k: v for k, v in envelope.items() if k != "hash"},
    )
    log.info("[payway] check tran_id=%s envelope=%s payment_status=%s(%s) "
             "amount=%s %s", tran_id, code, status.payment_status,
             status.payment_status_code, status.paid_amount, status.currency)
    return status
