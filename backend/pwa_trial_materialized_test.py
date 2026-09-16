"""`trial_materialized` — a read, and provably nothing else.

WHY THE FIELD EXISTS. The Spaces a fresh account displays are a PROJECTION:
nothing fires on account creation (production has no trigger on `auth.users`,
and 96 accounts hold zero ledger rows), and `_free_bucket_available` ADDS the
trial for exactly as long as no TRIAL row exists. So a guest that started a
generation and had it released is back at the same displayed balance as a guest
that never touched anything — and only one of them is safe to abandon. This
boolean is the difference, and it is reported, never applied.

WHAT THIS FILE PROVES
  1. the helper only ever SELECTs — no insert, update, delete or RPC;
  2. it answers True when the read throws (fail-closed for its caller);
  3. it answers from the presence of a TRIAL row, delta irrelevant — the
     sign-out marker is TRIAL(+0) and must count as materialised;
  4. the entitlement route reports it without branching on it;
  5. no billing, ledger, wallet, pass or payment logic was touched.

Offline: the Supabase client is a fake that records every call.

    backend/.venv/Scripts/python.exe pwa_trial_materialized_test.py
"""
import asyncio
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pwa_staging_billing as pwa_billing  # noqa: E402

passed: list = []
failed: list = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (passed if ok else failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else '  ' + detail}")


class _Result:
    def __init__(self, data):
        self.data = data


class _Table:
    """Records every method reached. Anything that writes is a failure."""

    def __init__(self, log, rows, raises=False):
        self._log, self._rows, self._raises = log, rows, raises

    def select(self, *a, **k):
        self._log.append(("select", a))
        return self

    def eq(self, col, val):
        self._log.append(("eq", col, val))
        return self

    def limit(self, n):
        self._log.append(("limit", n))
        return self

    def execute(self):
        self._log.append(("execute",))
        if self._raises:
            raise RuntimeError("network")
        return _Result(self._rows)

    # Every mutation the client could offer. None may ever be called.
    def insert(self, *a, **k):
        self._log.append(("insert",))
        raise AssertionError("WROTE")

    def update(self, *a, **k):
        self._log.append(("update",))
        raise AssertionError("WROTE")

    def upsert(self, *a, **k):
        self._log.append(("upsert",))
        raise AssertionError("WROTE")

    def delete(self, *a, **k):
        self._log.append(("delete",))
        raise AssertionError("WROTE")


class _Supa:
    def __init__(self, rows, raises=False):
        self.log = []
        self._rows, self._raises = rows, raises

    def table(self, name):
        self.log.append(("table", name))
        return _Table(self.log, self._rows, self._raises)

    def rpc(self, *a, **k):
        self.log.append(("rpc",))
        raise AssertionError("CALLED AN RPC")


def run(rows, raises=False):
    """Call the helper against a fake client; return (answer, call log)."""
    supa = _Supa(rows, raises=raises)
    import billing
    original = billing._get_supa
    billing._get_supa = lambda: supa
    try:
        answer = asyncio.run(pwa_billing.trial_materialized("u-1234abcd"))
    finally:
        billing._get_supa = original
    return answer, supa.log


print("\n== what it answers ==")
answer, log = run([{"entry_type": "TRIAL"}])
check("TM01 a TRIAL row present -> True", answer is True)

answer, _ = run([])
check("TM02 no TRIAL row -> False (a virgin account)", answer is False)

# The sign-out marker is TRIAL with delta 0. It IS materialisation: the
# projection stops the moment the row exists, whatever its amount.
answer, _ = run([{"entry_type": "TRIAL", "available_delta": 0}])
check("TM03 the TRIAL(+0) sign-out marker also counts as materialised",
      answer is True)

print("\n== it fails CLOSED ==")
answer, _ = run([], raises=True)
check("TM04 a read that throws answers True, never False", answer is True,
      "the caller's conservative side")

print("\n== it only ever reads ==")
_, log = run([{"entry_type": "TRIAL"}])
verbs = [c[0] for c in log]
check("TM05 the only table touched is ledger_entries",
      [c for c in log if c[0] == "table"] == [("table", "ledger_entries")],
      str([c for c in log if c[0] == "table"]))
check("TM06 the calls are select/eq/limit/execute and nothing else",
      set(verbs) == {"table", "select", "eq", "limit", "execute"}, str(set(verbs)))
for forbidden in ("insert", "update", "upsert", "delete", "rpc"):
    check(f"TM07 never calls {forbidden}()", forbidden not in verbs)
check("TM08 it filters on the user AND on entry_type=TRIAL",
      ("eq", "user_id", "u-1234abcd") in log and ("eq", "entry_type", "TRIAL") in log,
      str([c for c in log if c[0] == "eq"]))
check("TM09 it reads at most one row", ("limit", 1) in log)

print("\n== the source says the same thing ==")
src = (HERE / "pwa_staging_billing.py").read_text(encoding="utf-8")
body = src[src.index("async def trial_materialized"):src.index("async def open_gate")]
for forbidden in ("insert(", "update(", "upsert(", "delete(", ".rpc(",
                  "reproject", "grant_", "mark_trial", "_ledger_insert"):
    check(f"TM10 the helper's source contains no {forbidden}",
          forbidden not in body, forbidden)

api = (HERE / "pwa_staging_api.py").read_text(encoding="utf-8")
check("TM11 the entitlement route reports it and branches on nothing",
      '"trial_materialized": await pwa_billing.trial_materialized(user_id),' in api)
route = api[api.index("async def pwa_entitlement"):api.index("async def pwa_health")]
check("TM12 the route never tests the value",
      "if await pwa_billing.trial_materialized" not in route
      and "trial_materialized(user_id)\n" not in route.replace(
          '"trial_materialized": await pwa_billing.trial_materialized(user_id),\n', ""))

print("\n== nothing else in the billing surface moved ==")
import subprocess
diff = subprocess.run(
    ["git", "diff", "--name-only", "--", "backend"],
    cwd=str(HERE.parent), capture_output=True, text=True).stdout.split()
# Test files are not a production surface — and this file editing itself would
# otherwise make the check circular.
diff = [p for p in diff if not p.endswith("_test.py")]
# The auth adapter joined the set when the post-sign-out marker route was
# added. What matters is unchanged and asserted by TM14 below: the billing
# CORE, the payment rail and the mobile identity route are untouched.
allowed = {"backend/pwa_staging_api.py", "backend/pwa_staging_billing.py",
           "backend/pwa_staging_auth_api.py"}
check("TM13 only the adapter and its route changed",
      set(diff) <= allowed, str(sorted(set(diff) - allowed)))
for untouched in ("backend/billing.py", "backend/pwa_staging_payments.py",
                  "backend/payway.py", "backend/identity.py"):
    check(f"TM14 {untouched} untouched", untouched not in diff)

print(f"\n{len(passed)} passed, {len(failed)} failed")
if failed:
    for f in failed:
        print("  FAILED:", f)
    sys.exit(1)
print("ALL GREEN")
