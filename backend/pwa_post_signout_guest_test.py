"""SIGNOUT-03/04/05 — the guest a sign-out creates does not get a second trial.

THE ABUSE, reproduced on staging (2026-09-16). Nothing fires on account
creation, and the free bucket ADDS the trial for as long as no TRIAL row
exists, so EVERY new anonymous user is projected a fresh one — three successive
fresh guests, three full trials. Sign in, sign out, and the guest you land on
has a full trial again; one provider authorisation per lap, round and round.

The backend cannot tell that guest from a first-ever visitor: one second old,
no history, identical. Only the client that just signed out knows — which is
why the client calls this, and why a first visit, which never calls it, keeps
its trial untouched.

WHAT THIS FILE PROVES
  * the user marked is the one in the TOKEN, never one named by the body;
  * a non-anonymous caller is refused outright;
  * replaying it writes nothing the second time;
  * it grants and debits nothing — one TRIAL(delta 0) row, via the canonical
    function the mobile rail already uses;
  * the generation engine, ABA and the paid ledger were not touched.

Offline: GoTrue and the billing helper are fakes that record every call.

    backend/.venv/Scripts/python.exe pwa_post_signout_guest_test.py
"""
import asyncio
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from fastapi import HTTPException  # noqa: E402

import pwa_staging_auth_api as auth_api  # noqa: E402

passed: list = []
failed: list = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (passed if ok else failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else '  ' + detail}")


ANON = {"id": "11111111-1111-1111-1111-111111111111", "is_anonymous": True,
        "app_metadata": {}, "email": ""}
TELEGRAM = {"id": "22222222-2222-2222-2222-222222222222", "is_anonymous": False,
            "app_metadata": {"providers": ["custom:telegram"]}}

calls: list = []


class _FakeBilling:
    """Stands in for the canonical `billing` module. Records the ONE call it
    is allowed to receive, and refuses every other name."""

    #: the real marker is idempotent on `trial:<uid>` — True first, False after.
    seen: set = set()

    @staticmethod
    async def mark_trial_consumed(*, user_id: str, supa=None) -> bool:
        calls.append(("mark_trial_consumed", user_id))
        new = user_id not in _FakeBilling.seen
        _FakeBilling.seen.add(user_id)
        return new

    def __getattr__(self, name):  # pragma: no cover - a guard, not a path
        raise AssertionError(f"the route reached for billing.{name}")


def run(user, *, boom=False):
    """Call the route with a scripted GoTrue answer."""
    calls.clear()

    async def fake_claims(client, token):
        calls.append(("verify", token))
        if boom:
            raise HTTPException(status_code=401, detail={"error_code": "SESSION_EXPIRED"})
        return user

    original = auth_api._verify_user_claims
    auth_api._verify_user_claims = fake_claims
    sys.modules["billing"] = _FakeBilling()
    try:
        return asyncio.run(auth_api.post_signout_guest(authorization="Bearer tok-xyz"))
    finally:
        auth_api._verify_user_claims = original
        sys.modules.pop("billing", None)


print("\n== SIGNOUT-05  the user is the TOKEN, never the body ==")
import inspect  # noqa: E402

sig = inspect.signature(auth_api.post_signout_guest)
check("SIGNOUT-05 the route takes NO body at all — only the Authorization header",
      list(sig.parameters) == ["authorization"], str(list(sig.parameters)))
_FakeBilling.seen = set()
out = run(ANON)
check("SIGNOUT-05b it marks the id GoTrue returned",
      ("mark_trial_consumed", ANON["id"]) in calls, str(calls))
check("the token was verified before anything was written",
      calls[0][0] == "verify" and calls[1][0] == "mark_trial_consumed", str(calls))

print("\n== SIGNOUT-01/02  a guest created by a sign-out is marked ==")
check("SIGNOUT-01/02 answers ok, whichever account was just left",
      out.get("status") == "ok" and out.get("marked") is True, str(out))
check("exactly ONE billing call, and it is the canonical marker",
      [c[0] for c in calls if c[0] != "verify"] == ["mark_trial_consumed"],
      str(calls))

print("\n== SIGNOUT-03  replaying it writes nothing more ==")
out2 = run(ANON)
check("SIGNOUT-03 a second call still answers ok",
      out2.get("status") == "ok", str(out2))
check("SIGNOUT-03b …but marks nothing new (idempotent on trial:<uid>)",
      out2.get("marked") is False, str(out2))

print("\n== SIGNOUT-04  a real account is refused ==")
try:
    run(TELEGRAM)
    check("SIGNOUT-04 a non-anonymous caller is refused", False, "it returned")
except HTTPException as exc:
    check("SIGNOUT-04 a non-anonymous caller is refused", exc.status_code == 400,
          str(exc.status_code))
    check("SIGNOUT-04b with a machine code the client can act on",
          exc.detail.get("error_code") == "NOT_ANONYMOUS", str(exc.detail))
    check("SIGNOUT-04c and nothing was written for that account",
          not [c for c in calls if c[0] == "mark_trial_consumed"], str(calls))

print("\n== an unreadable session never marks anybody ==")
try:
    run(ANON, boom=True)
    check("a 401 from GoTrue stops the route", False, "it returned")
except HTTPException as exc:
    check("a 401 from GoTrue stops the route", exc.status_code == 401)
    check("…and writes nothing",
          not [c for c in calls if c[0] == "mark_trial_consumed"], str(calls))

print("\n== the source says the same thing ==")
src = (HERE / "pwa_staging_auth_api.py").read_text(encoding="utf-8")
body = src[src.index('@router.post("/post-signout-guest")'):src.index("def _unavailable")]
check("it reuses the canonical marker and writes no ledger row itself",
      "billing.mark_trial_consumed(user_id=user[\"id\"])" in body
      and "_ledger_insert" not in body and "insert(" not in body)
check("it never reads a user id out of a request body",
      "body." not in body and "user_id=body" not in body)
check("it refuses anything that is not anonymous",
      'user.get("is_anonymous") is not True' in body)
check("a failure is retryable, and says so",
      '"retryable": True' in body and "POST_SIGNOUT_UNAVAILABLE" in body)
check("no credit arithmetic anywhere in the route",
      all(w not in body for w in ("available_delta", "credits", "+ 3", "reproject")))

print("\n== SIGNOUT-12  the paid rails were not touched ==")
import subprocess  # noqa: E402

diff = subprocess.run(["git", "diff", "--name-only", "--", "backend"],
                      cwd=str(HERE.parent), capture_output=True, text=True).stdout.split()
for untouched in ("backend/payway.py", "backend/pwa_staging_payments.py",
                  "backend/billing.py", "backend/identity.py", "backend/main.py"):
    check(f"SIGNOUT-12 {untouched} untouched", untouched not in diff, str(diff))

print(f"\n{len(passed)} passed, {len(failed)} failed")
if failed:
    for f in failed:
        print("  FAILED:", f)
    sys.exit(1)
print("ALL GREEN")
