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

PATH_GENERATE_QR = "/api/payment-gateway/v1/payments/generate-qr"
PATH_CHECK_TRANSACTION = "/api/payment-gateway/v1/payments/check-transaction-2"

# The pushback signature header, in the two spellings a real request can carry.
# Starlette lowercases and treats `-`/`_` as distinct, so both are looked up.
SIGNATURE_HEADERS = ("x-payway-hmac-sha512", "x_payway_hmac_sha512")

#: `payment_option` for a KHQR payment. The one value this integration sends —
#: it is what makes the response carry both a KHQR string and an ABA deeplink.
PAYMENT_OPTION_KHQR = "abapay_khqr"

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
    if environment != "sandbox":
        # Named explicitly rather than silently downgraded: an operator who
        # typed `production` must see that this build refuses, not quietly run
        # against a sandbox they did not ask for.
        raise PayWayNotConfigured(
            f"PAYWAY_ENV={environment!r} is refused by this build. Only "
            f"'sandbox' is implemented; {PRODUCTION_BASE} is out of scope until "
            f"the productionization phase.")

    callback_url = _env("PAYWAY_CALLBACK_URL")
    if callback_url:
        _assert_public_callback(callback_url)

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

    return PayWayConfig(
        merchant_id=merchant_id,
        api_key=api_key,
        base_url=SANDBOX_BASE,
        environment=environment,
        callback_url=callback_url,
        require_callback_signature=(
            _env("PAYWAY_CALLBACK_SIGNATURE_MODE", "required").lower() != "optional"),
        lifetime_minutes=lifetime,
        qr_template=_env("PAYWAY_QR_TEMPLATE", "template3_color"),
        currency=currency,
    )


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


def _status(data: dict) -> tuple[Any, str, str]:
    """(code, message, trace/tran id) from PayWay's `status` envelope."""
    status = data.get("status")
    if not isinstance(status, dict):
        return (None, "", "")
    return (status.get("code"), str(status.get("message") or ""),
            str(status.get("trace_id") or status.get("tran_id") or ""))


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
        amount after discount) is the fallback for a sandbox reply that omits it.
        """
        return self.payment_amount if self.payment_amount is not None else self.total_amount


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
    data = await _post(cfg, PATH_CHECK_TRANSACTION, body)
    code, message, _ = _status(data)
    status = TransactionStatus(
        tran_id=tran_id,
        envelope_code=code,
        envelope_message=message,
        payment_status_code=_as_int(data.get("payment_status_code")),
        payment_status=str(data.get("payment_status") or ""),
        total_amount=_as_float(data.get("total_amount")),
        payment_amount=_as_float(data.get("payment_amount")),
        currency=str(data.get("payment_currency") or ""),
        approval_code=str(data.get("apv") or ""),
        transaction_date=str(data.get("transaction_date") or ""),
        raw={k: v for k, v in data.items() if k != "hash"},
    )
    log.info("[payway] check tran_id=%s envelope=%s payment_status=%s(%s) "
             "amount=%s %s", tran_id, code, status.payment_status,
             status.payment_status_code, status.paid_amount, status.currency)
    return status
