"""GUARD09/GUARD10/GUARD13 — a paid ABA checkout is never opened for a browser.

THE JOURNEY THIS CLOSES. An anonymous guest buys a pack; the payment succeeds;
the ledger is exactly right; then the browser storage goes and the session with
it. The entitlement is now attached to a user id nobody can ever sign into
again. From where the customer stands they paid and received nothing — and the
first real production purchase demonstrated it.

Hiding the Buy button is not enough, which is why this file exists: a stale
bundle, a replayed request, a second tab racing a half-finished link, or plain
curl must all be refused at the moment the transaction would be created.

Offline. `caller_is_secured` is the whole decision — GoTrue's own user payloads
in, one boolean out — plus a source-level check that the guard is wired to the
two CHECKOUT routes and to nothing else.

    backend/.venv/Scripts/python.exe pwa_payment_account_guard_test.py
"""
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pwa_staging_payments as pay  # noqa: E402

passed: list = []
failed: list = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (passed if ok else failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else '  ' + detail}")


# The shapes below are not invented: they were read off production on
# 2026-09-15 against the live project.
ANON = {"id": "96599d92-2f25-4679-a3da-6f214aa575ee", "is_anonymous": True,
        "role": "authenticated", "app_metadata": {}, "email": ""}
TELEGRAM = {"id": "fb8a748f-90f4-419c-9da4-fb0386210621", "is_anonymous": False,
            "role": "authenticated", "email": "",
            "app_metadata": {"provider": "custom:telegram",
                             "providers": ["custom:telegram"]}}
FACEBOOK = {"id": "u", "is_anonymous": False,
            "app_metadata": {"provider": "facebook", "providers": ["facebook"]}}
EMAIL = {"id": "u", "is_anonymous": False, "email": "someone@example.com",
         "app_metadata": {"provider": "email", "providers": ["email"]}}

print("\n== who may open a paid checkout ==")
check("GUARD09 an ANONYMOUS caller is refused",
      pay.caller_is_secured(ANON) is False)
check("GUARD15 the Telegram account is allowed — the existing flow is unchanged",
      pay.caller_is_secured(TELEGRAM) is True)
check("GUARD16 a Facebook account is allowed, the day Facebook is enabled",
      pay.caller_is_secured(FACEBOOK) is True)
check("an e-mail account is allowed",
      pay.caller_is_secured(EMAIL) is True)

print("\n== a missing signal is not a yes ==")
# `is_anonymous` absent: decide on the identities, and refuse when there are
# none. Fail CLOSED, because the cost of a false yes is a purchase that cannot
# be recovered and the cost of a false no is one sentence asking someone to
# sign in.
check("GUARD10 no is_anonymous and NO identities -> refused",
      pay.caller_is_secured({"id": "u", "app_metadata": {}}) is False)
check("no is_anonymous but a real identity -> allowed",
      pay.caller_is_secured(
          {"id": "u", "app_metadata": {"providers": ["custom:telegram"]}}) is True)
check("no is_anonymous, providers says literally 'anonymous' -> refused",
      pay.caller_is_secured(
          {"id": "u", "app_metadata": {"providers": ["anonymous"]}}) is False)
check("no is_anonymous, empty provider strings -> refused",
      pay.caller_is_secured(
          {"id": "u", "app_metadata": {"providers": ["", "  "]}}) is False)
check("no is_anonymous but a verified e-mail -> allowed",
      pay.caller_is_secured({"id": "u", "email": "a@b.c"}) is True)
check("no is_anonymous but a verified phone -> allowed",
      pay.caller_is_secured({"id": "u", "phone": "+85512345678"}) is True)

print("\n== nonsense is refused, never trusted ==")
for label, value in [("None", None), ("a string", "yes"), ("a list", []),
                     ("an int", 1), ("empty dict", {})]:
    check(f"GUARD10 {label} -> refused", pay.caller_is_secured(value) is False)
check("a STRING 'false' is not the boolean False",
      pay.caller_is_secured({"id": "u", "is_anonymous": "false"}) is False,
      "a truthy string must not be read as 'secured'")

print("\n== the guard is wired where money is CREATED, and nowhere else ==")
src = (HERE / "pwa_staging_payments.py").read_text(encoding="utf-8")


def route_body(decorator: str) -> str:
    """The source from one route decorator to the next."""
    start = src.index(decorator)
    rest = src[start + len(decorator):]
    end = rest.find("@router.")
    return rest if end < 0 else rest[:end]


for decorator in ['@router.post("/checkout/plugin")', '@router.post("/checkout")']:
    body = route_body(decorator)
    check(f"GUARD09 {decorator} calls _caller_secured",
          "_caller_secured(authorization)" in body)
    check(f"{decorator} does not fall back to the unguarded caller",
          "await _caller(authorization)" not in body)

# Settling an attempt that ALREADY exists must keep working for whoever has
# one — including the anonymous account that made the first real purchase.
# Guarding these would strand paid money, which is the opposite of the point.
for decorator in ['@router.get("/order/{tran_id}")', '@router.get("/open")',
                  '@router.post("/order/{tran_id}/cancel")']:
    body = route_body(decorator)
    check(f"GUARD17 {decorator} is NOT guarded — a paid attempt still settles",
          "_caller_secured" not in body and "await _caller(authorization)" in body)

print("\n== it is a prerequisite, not a financial failure ==")
check("GUARD14 the refusal is ACCOUNT_REQUIRED",
      '"error_code": "ACCOUNT_REQUIRED"' in src)
check("GUARD14 it is a 403, not a payment state",
      "status_code=403" in src.split("ACCOUNT_REQUIRED")[0][-400:])
check("GUARD14 the word FAILED appears nowhere in the refusal",
      "FAILED" not in src[src.index("ACCOUNT_REQUIRED") - 600:
                          src.index("ACCOUNT_REQUIRED") + 400])

print(f"\n{len(passed)} passed, {len(failed)} failed")
if failed:
    for f in failed:
        print("  FAILED:", f)
    sys.exit(1)
print("ALL GREEN")
