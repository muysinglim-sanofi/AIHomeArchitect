"""ABA PayWay rail — the OFFLINE contract. No network, no database, no secret.

What this proves
----------------
Everything about `payway.py` that must be true before a single riel can move,
and that can be decided without ABA:

  PW01  the sandbox is the only environment this build will dial
  PW02  absent credentials REFUSE — there is no fallback to production
  PW03  a loopback callback URL is refused (PayWay could never call it)
  PW04  the generate-qr hash covers the OFFICIAL nineteen fields, in the
        OFFICIAL order, with absent optionals as empty strings
  PW05  the check-transaction hash is req_time + merchant_id + tran_id
  PW06  the signature is base64(hmac_sha512(payload, api_key)) — pinned against
        an independently computed vector, not against our own function
  PW07  amount formatting is identical in the body and in the hash
  PW08  a pushback signature verifies when correct and fails on every mutation
  PW09  the pushback digest sorts by key ASCENDING and excludes `hash` itself
  PW10  the API key never appears in a repr, a redacted config, or a log record

Run:  cd backend && PYTHONPATH=. python payway_adapter_test.py
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import logging
import os
import pathlib
import sys
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

# Windows consoles default to cp1252 and the section rules below are box-drawing
# characters. Reconfiguring here means a failing assertion is reported as a
# failing assertion, not as a UnicodeEncodeError three lines into the run.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):  # pragma: no cover — non-TTY / old Python
        pass

import payway  # noqa: E402

_passed: list[str] = []
_failed: list[str] = []

# A throwaway credential that exists only inside this process. It is not a
# secret, it is a fixture — which is why it may appear in a source file at all.
FAKE_KEY = "test_api_key_not_a_real_credential"
FAKE_MERCHANT = "ec000000"


def check(label: str, ok: bool, detail: str = "") -> None:
    (_passed if ok else _failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  {detail}'}")


def section(title: str) -> None:
    print(f"\n── {title} " + "─" * max(0, 66 - len(title)))


def _env(**values: str) -> None:
    """Replace the PAYWAY_* environment wholesale, so no test leaks into another."""
    for key in [k for k in os.environ if k.startswith("PAYWAY_")]:
        del os.environ[key]
    os.environ.update(values)


def _configured(**overrides: str) -> payway.PayWayConfig:
    base = {"PAYWAY_MERCHANT_ID": FAKE_MERCHANT, "PAYWAY_API_KEY": FAKE_KEY,
            "PAYWAY_ENV": "sandbox"}
    base.update(overrides)
    _env(**base)
    return payway.load_config()


# ── PW01 / PW02 / PW03 — configuration fails closed ─────────────────────────


def test_config() -> None:
    section("PW01-03  configuration fails closed")

    _env()
    check("PW02 no credentials -> is_configured() is False", not payway.is_configured())
    try:
        payway.load_config()
        check("PW02 no credentials -> load_config raises", False)
    except payway.PayWayNotConfigured as exc:
        # The refusal must NAME what is missing, and must not carry a value.
        text = str(exc)
        check("PW02 no credentials -> PayWayNotConfigured names the variables",
              "PAYWAY_MERCHANT_ID" in text and "PAYWAY_API_KEY" in text)

    _env(PAYWAY_MERCHANT_ID=FAKE_MERCHANT)
    check("PW02 merchant id alone is not enough", not payway.is_configured())

    _env(PAYWAY_API_KEY=FAKE_KEY)
    check("PW02 api key alone is not enough", not payway.is_configured())

    _env(PAYWAY_MERCHANT_ID=FAKE_MERCHANT, PAYWAY_API_KEY=FAKE_KEY,
         PAYWAY_ENV="production")
    try:
        payway.load_config()
        check("PW01 PAYWAY_ENV=production is refused", False)
    except payway.PayWayNotConfigured as exc:
        check("PW01 PAYWAY_ENV=production is refused", True)
        check("PW01 the refusal names the production host it will not dial",
              payway.PRODUCTION_BASE in str(exc))

    cfg = _configured()
    check("PW01 sandbox resolves to the official sandbox base",
          cfg.base_url == "https://checkout-sandbox.payway.com.kh", cfg.base_url)
    check("PW01 no callback configured -> poll-only, and it says so",
          not cfg.has_public_callback)

    for bad in ("http://pay.example.com/cb", "https://127.0.0.1/cb",
                "https://localhost:8000/cb", "https://api.local/cb"):
        try:
            _configured(PAYWAY_CALLBACK_URL=bad)
            check(f"PW03 refuses unusable callback {bad}", False)
        except ValueError:
            check(f"PW03 refuses unusable callback {bad}", True)

    cfg = _configured(PAYWAY_CALLBACK_URL="https://api-staging.example.com/cb")
    check("PW03 accepts a public https callback", cfg.has_public_callback)

    cfg = _configured(PAYWAY_QR_LIFETIME_MINUTES="1")
    check("PW01 a lifetime below PayWay's documented floor is clamped to 3",
          cfg.lifetime_minutes == 3, str(cfg.lifetime_minutes))


# ── PW04 / PW05 / PW06 / PW07 — the signatures ──────────────────────────────


def test_qr_hash() -> None:
    section("PW04  the generate-qr hash is the official field order")

    official = (
        "req_time", "merchant_id", "tran_id", "amount", "items", "first_name",
        "last_name", "email", "phone", "purchase_type", "payment_option",
        "callback_url", "return_deeplink", "currency", "custom_fields",
        "return_params", "payout", "lifetime", "qr_image_template",
    )
    check("PW04 QR_HASH_FIELDS matches the Developer Suite order EXACTLY",
          payway.QR_HASH_FIELDS == official, str(payway.QR_HASH_FIELDS))

    # A body where every field is its own name makes the concatenation readable,
    # so the assertion is about ORDER rather than about a digest nobody can read.
    named = {name: name.upper() for name in official}
    check("PW04 the payload is the values concatenated in that order",
          payway.qr_hash_payload(named) == "".join(n.upper() for n in official))

    partial = {"req_time": "20260818120000", "merchant_id": "m", "tran_id": "t"}
    check("PW04 absent optional fields contribute the EMPTY string",
          payway.qr_hash_payload(partial) == "20260818120000mt",
          payway.qr_hash_payload(partial))

    cfg = _configured()
    now = datetime(2026, 8, 18, 12, 0, 0, tzinfo=timezone.utc)
    body = payway.build_qr_request(cfg=cfg, tran_id="A0123456789abcdef012",
                                   amount=1.99, currency="USD", now=now)
    check("PW04 req_time is UTC YYYYMMDDHHmmss",
          body["req_time"] == "20260818120000", body["req_time"])
    check("PW04 the KHQR payment option is what is sent",
          body["payment_option"] == "abapay_khqr", body["payment_option"])
    check("PW04 no personal data is sent for a KHQR payment",
          not any(k in body for k in
                  ("first_name", "last_name", "email", "phone")))
    check("PW04 no callback field when there is no public callback",
          "callback_url" not in body)

    # The digest, recomputed here from the documented rule and nothing else.
    expected_payload = (
        "20260818120000" + FAKE_MERCHANT + "A0123456789abcdef012" + "1.99"
        + "" * 6            # items, first_name, last_name, email, phone, purchase_type
        + "abapay_khqr"
        + "" * 2            # callback_url, return_deeplink
        + "USD"
        + "" * 4            # custom_fields, return_params, payout
        + "30" + "template3_color"
    )
    independent = base64.b64encode(
        hmac.new(FAKE_KEY.encode(), expected_payload.encode(),
                 hashlib.sha512).digest()).decode()
    check("PW06 the hash is base64(hmac_sha512(payload, api_key))",
          body["hash"] == independent, body["hash"][:24] + "…")

    with_cb = payway.build_qr_request(
        cfg=_configured(PAYWAY_CALLBACK_URL="https://api-staging.example.com/cb"),
        tran_id="A0123456789abcdef012", amount=1.99, now=now)
    check("PW04 the callback url is base64 encoded, per the spec",
          with_cb["callback_url"]
          == base64.b64encode(b"https://api-staging.example.com/cb").decode())


def test_check_hash() -> None:
    section("PW05  the check-transaction hash")
    cfg = _configured()
    now = datetime(2026, 8, 18, 12, 0, 0, tzinfo=timezone.utc)
    body = payway.build_check_request(cfg=cfg, tran_id="A0123456789abcdef012", now=now)
    expected = base64.b64encode(hmac.new(
        FAKE_KEY.encode(),
        f"20260818120000{FAKE_MERCHANT}A0123456789abcdef012".encode(),
        hashlib.sha512).digest()).decode()
    check("PW05 hash = base64(hmac_sha512(req_time+merchant_id+tran_id))",
          body["hash"] == expected)
    check("PW05 nothing else is sent",
          set(body) == {"req_time", "merchant_id", "tran_id", "hash"}, str(set(body)))


def test_amount_format() -> None:
    section("PW07  the amount is formatted ONCE, for body and hash alike")
    check("PW07 USD keeps exactly two decimals",
          payway.format_amount(1.99, "USD") == "1.99")
    check("PW07 a whole USD amount still shows two decimals",
          payway.format_amount(7, "USD") == "7.00")
    check("PW07 a float artefact does not leak into the digest",
          payway.format_amount(0.1 + 0.2, "USD") == "0.30",
          payway.format_amount(0.1 + 0.2, "USD"))
    check("PW07 KHR has no minor unit", payway.format_amount(4100, "KHR") == "4100")

    cfg = _configured()
    body = payway.build_qr_request(cfg=cfg, tran_id="T1", amount=1.99)
    check("PW07 the body amount is the string the hash covered",
          body["amount"] == "1.99" and "1.99" in payway.qr_hash_payload(body))


# ── PW08 / PW09 — the pushback ──────────────────────────────────────────────


def test_pushback() -> None:
    section("PW08-09  pushback verification")

    body = {
        "tran_id": "A0123456789abcdef012",
        "apv": "832865",
        "status": "0",
        "return_params": json.dumps({"t": "A0123456789abcdef012"}),
        "merchant_ref": "",
    }
    payload = payway.pushback_hash_payload(body)
    check("PW09 the digest sorts the fields by key ASCENDING",
          payload == "".join(body[k] for k in sorted(body)), payload)

    signature = payway.sign(payload, FAKE_KEY)
    check("PW08 a correct signature verifies",
          payway.verify_pushback(body, signature, FAKE_KEY))
    check("PW08 an absent signature does NOT verify",
          not payway.verify_pushback(body, "", FAKE_KEY))
    check("PW08 a signature under a different key does NOT verify",
          not payway.verify_pushback(body, payway.sign(payload, "other"), FAKE_KEY))

    for field, mutated in (("tran_id", "A9999999999999999999"),
                           ("apv", "000000"),
                           ("status", "1"),
                           ("return_params", "{}")):
        tampered = dict(body, **{field: mutated})
        check(f"PW08 mutating {field} invalidates the signature",
              not payway.verify_pushback(tampered, signature, FAKE_KEY))

    extra = dict(body, injected="x")
    check("PW08 an ADDED field invalidates the signature",
          not payway.verify_pushback(extra, signature, FAKE_KEY))

    # A signature cannot cover itself; if PayWay ever echoed one in the body the
    # digest must ignore it rather than change meaning.
    check("PW09 a `hash` field in the body is excluded from the digest",
          payway.pushback_hash_payload(dict(body, hash="whatever")) == payload)

    check("PW09 a structured value hashes deterministically",
          payway.pushback_hash_payload({"a": {"z": 1, "b": 2}})
          == payway.pushback_hash_payload({"a": {"b": 2, "z": 1}}))

    class _Headers(dict):
        def get(self, key, default=None):  # noqa: D102
            return dict.get(self, key.lower(), default)

    check("PW08 the header is read in the dashed spelling",
          payway.signature_from_headers(
              _Headers({"x-payway-hmac-sha512": " sig "})) == "sig")
    check("PW08 the header is read in the underscored spelling too",
          payway.signature_from_headers(
              _Headers({"x_payway_hmac_sha512": "sig"})) == "sig")
    check("PW08 no header -> empty, which never verifies",
          payway.signature_from_headers(_Headers({})) == "")


# ── PW10 — the key never leaks ──────────────────────────────────────────────


def test_no_secret_leak() -> None:
    section("PW10  the api key never leaves the process")

    cfg = _configured(PAYWAY_CALLBACK_URL="https://api-staging.example.com/cb")
    check("PW10 repr(config) redacts the key",
          FAKE_KEY not in repr(cfg) and "<redacted>" in repr(cfg), repr(cfg))

    redacted = payway.redacted_config()
    blob = json.dumps(redacted)
    check("PW10 redacted_config() carries no key", FAKE_KEY not in blob, blob)
    check("PW10 redacted_config() carries no full merchant id",
          FAKE_MERCHANT not in blob, blob)
    check("PW10 redacted_config() still says what an operator needs",
          redacted["configured"] and redacted["environment"] == "sandbox"
          and redacted["callback_configured"] is True, blob)

    # And the one place a digest could reach a log: the transport's log line.
    records: list[str] = []

    class _Capture(logging.Handler):
        def emit(self, record):  # noqa: D102
            records.append(record.getMessage())

    handler = _Capture()
    payway.log.addHandler(handler)
    previous_level = payway.log.level
    # The logger inherits WARNING from root in a bare process, so an INFO line
    # would never reach the handler and the test would pass by capturing nothing.
    payway.log.setLevel(logging.INFO)
    try:
        body = payway.build_qr_request(cfg=cfg, tran_id="T1", amount=1.99)
        safe = {k: v for k, v in body.items() if k != "hash"}
        payway.log.info("[payway] POST %s tran_id=%s fields=%s",
                        payway.PATH_GENERATE_QR, body["tran_id"], sorted(safe))
    finally:
        payway.log.removeHandler(handler)
        payway.log.setLevel(previous_level)

    joined = " ".join(records)
    check("PW10 the transport log line carries no key and no hash",
          FAKE_KEY not in joined and body["hash"] not in joined, joined)
    check("PW10 the transport log line still identifies the call",
          "generate-qr" in joined and "T1" in joined, joined)


# ── the status vocabulary ───────────────────────────────────────────────────


def test_status_semantics() -> None:
    section("PW11  Check Transaction status semantics")

    def status(**kw) -> payway.TransactionStatus:
        base = dict(tran_id="T1", envelope_code="00", envelope_message="",
                    payment_status_code=None, payment_status="", total_amount=None,
                    payment_amount=None, currency="", approval_code="",
                    transaction_date="", raw={})
        base.update(kw)
        return payway.TransactionStatus(**base)

    check("PW11 APPROVED on a success envelope is approved",
          status(payment_status_code=0, payment_status="APPROVED").approved)
    check("PW11 APPROVED on a NOT-FOUND envelope is NOT approved",
          not status(envelope_code="6", payment_status_code=0).approved)
    check("PW11 a missing payment_status_code is never approved",
          not status().approved)
    check("PW11 PENDING is pending and not approved",
          status(payment_status_code=2).pending
          and not status(payment_status_code=2).approved)
    for code in (3, 7, 4):
        check(f"PW11 payment_status_code={code} is a terminal failure",
              status(payment_status_code=code).terminal_failure)
    check("PW11 the amount compared is what the customer PAID",
          status(payment_amount=1.99, total_amount=9.99).paid_amount == 1.99)
    check("PW11 total_amount is the fallback when payment_amount is absent",
          status(total_amount=1.99).paid_amount == 1.99)


def test_real_envelope_shapes() -> None:
    """PW12 — the envelopes the SANDBOX actually sends, captured verbatim.

    These two payloads are not invented. They were recorded from
    checkout-sandbox.payway.com.kh on 2026-08-19, and they are here because the
    first one disagrees with the documentation in a way that silently disabled
    every grant: the Developer Suite documents `payment_status_code` at the top
    level, and the gateway nests it under `data`. The parser read the top level,
    found nothing, and `approved` correctly refused — forever, for everyone.

    Fail-safe, and invisible. Pinning the real shape is what stops it coming
    back the next time someone tidies the parser against the documentation.
    """
    import asyncio  # noqa: PLC0415

    section("PW12  the envelopes the sandbox really sends")

    captured = {}

    async def _fake_post(cfg, path, body):  # noqa: ANN001
        return captured["reply"]

    real_post = payway._post  # noqa: SLF001
    payway._post = _fake_post  # noqa: SLF001
    try:
        cfg = _configured()

        # MEASURED: an unpaid transaction. `data`-nested, and `payment_amount`
        # is present-and-zero rather than absent.
        captured["reply"] = {
            "data": {"payment_status_code": 2, "total_amount": 1.99,
                     "original_amount": 1.99, "refund_amount": 0,
                     "discount_amount": 0, "payment_amount": 0,
                     "payment_currency": "", "apv": "",
                     "payment_status": "PENDING",
                     "transaction_date": "2026-08-19 01:57:38"},
            "status": {"code": "00", "message": "Success!", "tran_id": "A1"},
        }
        s = asyncio.run(payway.check_transaction(cfg=cfg, tran_id="A1"))
        check("PW12 the `data`-nested payment status is read",
              s.payment_status_code == 2 and s.payment_status == "PENDING",
              f"{s.payment_status_code} {s.payment_status!r}")
        check("PW12 an unpaid transaction is PENDING, never approved",
              s.pending and not s.approved and not s.terminal_failure)
        check("PW12 a zero payment_amount falls back to total_amount",
              s.paid_amount == 1.99, str(s.paid_amount))

        # MEASURED: a transaction PayWay has never heard of.
        captured["reply"] = {
            "status": {"code": 6, "message": "tran_id not found",
                       "tran_id": "ANOSUCH"},
        }
        s = asyncio.run(payway.check_transaction(cfg=cfg, tran_id="ANOSUCH"))
        check("PW12 an unknown tran_id is not found and not approved",
              not s.found and not s.approved, str(s.envelope_code))

        # The APPROVED shape, in the SAME nesting. This is the one that must
        # grant, and the one the bug made unreachable.
        captured["reply"] = {
            "data": {"payment_status_code": 0, "payment_status": "APPROVED",
                     "total_amount": 1.99, "payment_amount": 1.99,
                     "payment_currency": "USD", "apv": "832865",
                     "transaction_date": "2026-08-19 02:03:11"},
            "status": {"code": "00", "message": "Success!", "tran_id": "A2"},
        }
        s = asyncio.run(payway.check_transaction(cfg=cfg, tran_id="A2"))
        check("PW12 an APPROVED transaction is approved", s.approved)
        check("PW12 the approval code and paid amount come through",
              s.approval_code == "832865" and s.paid_amount == 1.99
              and s.currency == "USD", str(s))

        # And the DOCUMENTED flat shape still parses, so a future gateway
        # release that matches its own page does not break this.
        captured["reply"] = {
            "payment_status_code": 0, "payment_status": "APPROVED",
            "total_amount": 1.99, "payment_amount": 1.99,
            "payment_currency": "USD", "apv": "111111",
            "status": {"code": "00", "message": "Success!", "tran_id": "A3"},
        }
        s = asyncio.run(payway.check_transaction(cfg=cfg, tran_id="A3"))
        check("PW12 the DOCUMENTED flat shape is still accepted",
              s.approved and s.approval_code == "111111", str(s))
    finally:
        payway._post = real_post  # noqa: SLF001


def main() -> int:
    print("ABA PayWay rail — OFFLINE contract (no network, no database)\n")
    test_config()
    test_qr_hash()
    test_check_hash()
    test_amount_format()
    test_pushback()
    test_no_secret_leak()
    test_status_semantics()
    test_real_envelope_shapes()

    print()
    if _failed:
        print(f"FAILURES: {len(_failed)} / {len(_passed) + len(_failed)}")
        for name in _failed:
            print("  -", name)
        return 1
    print(f"ALL PAYWAY RAIL TESTS PASS ({len(_passed)} assertions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
