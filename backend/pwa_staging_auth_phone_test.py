"""AUTH26 — a stale `phone_change` must never attach a number to the wrong user.

What is REPRODUCED here, against the real staging project
---------------------------------------------------------
GoTrue resolves a `phone_change` verification by NUMBER (`verify.go`:
`FindUserByPhoneChangeAndAudience` → `findUser(...).First(obj)`), and the
column is not unique. So the ambiguity is a DATABASE fact, and it can be shown
without an SMS provider:

    1. two disposable users, A (stale) and B (live), both with
       phone_change = X — A's attempt 20 minutes old, B's 30 seconds old;
    2. the exact predicate GoTrue runs returns TWO rows for X, and the FIRST
       row is whichever the planner likes — for A the verification would then
       be checked against A's token, and with a project TEST OTP it would
       return A's session to B's browser (verify.go:754);
    3. `pwa_staging.auth_phone_change_release(X, B)` (migration 0010) clears
       A's expired attempt and leaves B's live one, and reports contested = 0
       for B — so B's `updateUser` runs against an unambiguous table;
    4. a THIRD user C, still inside the window, is reported as contested = 1
       for B and is NOT cleared — the function never cancels a live attempt;
    5. the function is unreachable for `anon` / `authenticated` (grants), and
       is SECURITY DEFINER.

What is NOT claimed
-------------------
The end-to-end wrong-session outcome needs the phone provider enabled on the
project (it is not, today) and a test OTP. That run is `CARRIER/OTP =
UNVERIFIED` in the implementation report until Mike enables the provider; the
client-side guard (user id before/after `verifyOTP`, session restored on
mismatch) is covered by the Dart tests.

Safe: disposable users in STAGING only, deleted at the end, no ledger rows.
Run:  cd backend && python pwa_staging_auth_phone_test.py
"""
from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request
import uuid

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from pwa_staging_db import redacted, resolve_staging_url, staging_connection  # noqa: E402

STAGING_REF = "eedcahzekpgxvvfxufbk"
BASE = f"https://{STAGING_REF}.supabase.co"

_PASS: list[str] = []
_FAIL: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (_PASS if ok else _FAIL).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  -- {detail}'}")


def _secret(name: str) -> str:
    for raw in (HERE / ".env.pwa-staging.local").read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith(name) and "=" in line:
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit(f"REFUSING: {name} missing")


def _call(path: str, *, method: str = "POST", body=None, token: str | None = None,
          apikey: str | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{BASE}{path}", data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("apikey", apikey or "")
    if path.startswith("/rest/"):
        # The function lives in `pwa_staging`, exactly as the backend addresses it.
        req.add_header("Content-Profile", "pwa_staging")
        req.add_header("Accept-Profile", "pwa_staging")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw or b"{}")
        except Exception:  # noqa: BLE001
            return e.code, {"raw": raw[:200].decode("utf-8", "replace")}


def _admin_user(svc: str, tag: str) -> str:
    st, u = _call("/auth/v1/admin/users", body={
        "email": f"auth26-{tag}@aydenstudio.dev", "email_confirm": True,
    }, token=svc, apikey=svc)
    if st != 200:
        raise SystemExit(f"could not mint probe user ({st}): {u}")
    return u["id"]


def _delete_user(svc: str, uid: str) -> None:
    _call(f"/auth/v1/admin/users/{uid}", method="DELETE", token=svc, apikey=svc)


# GoTrue's own predicate, verbatim from models/user.go (instance_id = nil uuid).
GOTRUE_LOOKUP = """
    select id from auth.users
     where instance_id = '00000000-0000-0000-0000-000000000000'
       and phone_change = %s and aud = 'authenticated' and is_sso_user = false
"""


def main() -> int:
    svc = _secret("SUPABASE_SERVICE_ROLE_KEY")
    anon = _secret("SUPABASE_PUBLISHABLE_KEY")
    url = resolve_staging_url()
    print(f"target : {redacted(url)}   project: {STAGING_REF} (STAGING)")

    # A number nobody owns: a Cambodian shape with an impossible prefix block.
    phone = "855" + uuid.uuid4().int.__str__()[:9]
    tag = uuid.uuid4().hex[:8]
    a = b = c = None
    try:
        a = _admin_user(svc, f"a-{tag}")
        b = _admin_user(svc, f"b-{tag}")
        c = _admin_user(svc, f"c-{tag}")
        print(f"users  : A(stale)={a[:8]}…  B(live)={b[:8]}…  C(live)={c[:8]}…  X=+{phone}")

        with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
            # 1. The ambiguity, as GoTrue would meet it.
            cur.execute("""
                update auth.users
                   set phone_change = %s, phone_change_token = 'stale-a',
                       phone_change_sent_at = now() - interval '20 minutes'
                 where id = %s""", (phone, a))
            cur.execute("""
                update auth.users
                   set phone_change = %s, phone_change_token = 'live-b',
                       phone_change_sent_at = now() - interval '30 seconds'
                 where id = %s""", (phone, b))
            cur.execute(GOTRUE_LOOKUP, (phone,))
            rows = [r[0] for r in cur.fetchall()]
            check("AUTH26.1 two users hold the same phone_change (the ambiguity exists)",
                  len(rows) == 2 and set(map(str, rows)) == {a, b}, f"rows={rows}")
            cur.execute(GOTRUE_LOOKUP + " limit 1", (phone,))
            first = str(cur.fetchone()[0])
            print(f"         GoTrue's First() would resolve X to {'A (STALE)' if first == a else 'B'}"
                  " — row order, not the session, decides")

            # 2. Anon / authenticated cannot call the function.
            cur.execute("select has_function_privilege('anon', "
                        "'pwa_staging.auth_phone_change_release(text, uuid, integer)', 'execute')")
            check("AUTH26.2 anon cannot execute the release function", cur.fetchone()[0] is False)
            cur.execute("select has_function_privilege('authenticated', "
                        "'pwa_staging.auth_phone_change_release(text, uuid, integer)', 'execute')")
            check("AUTH26.3 authenticated cannot execute the release function",
                  cur.fetchone()[0] is False)
            cur.execute("select p.prosecdef from pg_proc p join pg_namespace n on n.oid=p.pronamespace"
                        " where n.nspname='pwa_staging' and p.proname='auth_phone_change_release'")
            check("AUTH26.4 the function is SECURITY DEFINER", cur.fetchone()[0] is True)

        # 3. The backend's call, exactly as pwa_staging_auth_api makes it
        #    (service key, PostgREST RPC, Content-Profile pwa_staging).
        st, res = _call("/rest/v1/rpc/auth_phone_change_release", body={
            "p_phone": phone, "p_caller": b, "p_grace_seconds": 600,
        }, token=svc, apikey=svc)
        row = res[0] if isinstance(res, list) and res else res
        check("AUTH26.5 the RPC answers 200 with a service key", st == 200, f"{st} {res}")
        check("AUTH26.6 the stale attempt (A) was released", int(row.get("cleared", 0)) >= 1,
              f"row={row}")
        check("AUTH26.7 nothing contests X for B any more", int(row.get("contested", -1)) == 0,
              f"row={row}")

        with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
            cur.execute(GOTRUE_LOOKUP, (phone,))
            rows = [str(r[0]) for r in cur.fetchall()]
            check("AUTH26.8 GoTrue's lookup now finds ONLY B", rows == [b], f"rows={rows}")
            cur.execute("select phone_change, phone_change_token, phone_change_sent_at "
                        "from auth.users where id = %s", (a,))
            pc, tok, at = cur.fetchone()
            check("AUTH26.9 A's row is fully cleared (value, token, sent_at)",
                  (pc or "") == "" and (tok or "") == "" and at is None, f"{pc!r} {tok!r} {at}")

            # 4. A LIVE attempt by a third user is reported, never cleared.
            cur.execute("""
                update auth.users
                   set phone_change = %s, phone_change_token = 'live-c',
                       phone_change_sent_at = now() - interval '45 seconds'
                 where id = %s""", (phone, c))
        st, res = _call("/rest/v1/rpc/auth_phone_change_release", body={
            "p_phone": phone, "p_caller": b, "p_grace_seconds": 600,
        }, token=svc, apikey=svc)
        row = res[0] if isinstance(res, list) and res else res
        check("AUTH26.10 a live attempt on another user is reported as contested",
              st == 200 and int(row.get("contested", 0)) == 1, f"{st} {row}")
        with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
            cur.execute("select phone_change from auth.users where id = %s", (c,))
            check("AUTH26.11 …and it is NOT cleared (no cancelling a stranger's flow)",
                  cur.fetchone()[0] == phone)
            cur.execute("select phone_change from auth.users where id = %s", (b,))
            check("AUTH26.12 the caller's own row is never touched",
                  cur.fetchone()[0] == phone)

        # 5. The anon key cannot reach the function through PostgREST either.
        st, _ = _call("/rest/v1/rpc/auth_phone_change_release", body={
            "p_phone": phone, "p_caller": b, "p_grace_seconds": 600,
        }, token=anon, apikey=anon)
        check("AUTH26.13 the publishable key is refused by PostgREST", st in (401, 403, 404),
              f"status={st}")
    finally:
        for uid in (a, b, c):
            if uid:
                _delete_user(svc, uid)
        print("cleanup: probe users deleted")

    print(f"\nPASS {len(_PASS)} / FAIL {len(_FAIL)}")
    return 0 if not _FAIL else 1


if __name__ == "__main__":
    sys.exit(main())
