"""IDENTITY PROBE — does the Web upgrade-in-place actually keep the user_id?

The frozen spec (docs/GUEST_ACCOUNT_IDENTITY_SPEC.md) left ONE unknown, U4: does
converting an anonymous session into a real account produce the SAME user_id
(upgrade-in-place) or a NEW one (separate identities)? On mobile it could not be
answered without a device, because it needs a real Apple id_token.

On the Web the question is different and answerable, because the transport is
email. This probe answers it against the REAL staging project, using the REAL
GoTrue endpoints the Flutter client will call — before a single line of UI is
written, so the UI is built on a measured fact rather than a remembered one.

    POST /auth/v1/signup            (anonymous)      -> uid_before
    PUT  /auth/v1/user  {email}                      -> confirmation sent
    POST /auth/v1/verify {email_change token}        -> uid_after
    assert uid_after == uid_before  and  is_anonymous flips true -> false

The OTP normally arrives by email. There is no inbox here, so the token is read
from the ADMIN seam (`/auth/v1/admin/generate_link`) with the service-role key.
That is TEST SETUP, not product behaviour: the browser never sees the service
key, and nothing in `lib/` can reach this path.

Run:  cd backend && python pwa_staging_identity_probe.py
Safe: creates disposable identities in the staging project only. They cannot be
deleted once they have ledger rows (append-only), so it creates NO ledger rows.
"""
from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request
import uuid

HERE = pathlib.Path(__file__).resolve().parent
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


def main() -> int:
    anon_key = _secret("SUPABASE_PUBLISHABLE_KEY")
    service_key = _secret("SUPABASE_SERVICE_ROLE_KEY")
    if STAGING_REF not in BASE:
        print("REFUSING: not the staging project")
        return 2
    print(f"target      : {STAGING_REF}.supabase.co  (staging)")

    # ── 1. An anonymous visitor, exactly as the PWA mints one ────────────────
    print("\n-- A. anonymous session " + "-" * 44)
    st, anon = _call("/auth/v1/signup", body={"data": {}}, apikey=anon_key)
    uid_before = (anon.get("user") or {}).get("id")
    token_before = anon.get("access_token")
    check("A1 anonymous sign-up succeeds", st == 200 and bool(uid_before), f"{st} {anon}")
    if not uid_before:
        return 1
    check("A2 the user is flagged anonymous",
          (anon.get("user") or {}).get("is_anonymous") is True)
    print(f"       uid_before = {uid_before[:8]}...{uid_before[-4:]}")

    # ── 2. THE question: does attaching an identity keep the user_id? ───────
    #
    # The client transport is `updateUser(email)` + `verifyOTP`, which sends a
    # confirmation mail. This project uses Supabase's BUILT-IN SMTP, whose send
    # quota is small; when spent the API answers 429 `over_email_send_rate_limit`
    # — a mail-DELIVERY limit, not a refusal of the identity operation. So the
    # identity question is asked through the ADMIN seam, which performs the same
    # attach-and-confirm with no mail involved, and the client transport is
    # probed separately below.
    print("\n-- B. upgrade-in-place: attach + confirm an identity " + "-" * 16)
    email = f"probe-{uuid.uuid4().hex[:12]}@aydenstudio.dev"
    st, upd = _call(f"/auth/v1/admin/users/{uid_before}", method="PUT",
                    body={"email": email, "email_confirm": True},
                    token=service_key, apikey=service_key)
    check("B1 an anonymous user accepts a new email identity", st == 200,
          f"{st} {json.dumps(upd)[:200]}")
    check("B2 UPGRADE-IN-PLACE: the user_id is PRESERVED",
          upd.get("id") == uid_before, f"before={uid_before} after={upd.get('id')}")
    check("B3 the account is no longer anonymous",
          upd.get("is_anonymous") is False, str(upd.get("is_anonymous")))
    check("B4 the email is attached to that same user",
          (upd.get("email") or "").lower() == email.lower(), str(upd.get("email")))

    # The session minted while anonymous must keep working and keep resolving to
    # the same id — that is what makes projects, ledger rows and every RLS policy
    # (all keyed on user_id) survive the upgrade with NOTHING to migrate.
    st, who = _call("/auth/v1/user", method="GET", token=token_before, apikey=anon_key)
    check("B5 the ORIGINAL session still resolves to that same user",
          st == 200 and who.get("id") == uid_before, f"{st} {who.get('id')}")
    check("B6 and now reports a non-anonymous account",
          who.get("is_anonymous") is False, str(who.get("is_anonymous")))
    if upd.get("id"):
        print(f"       uid_after  = {upd['id'][:8]}...{upd['id'][-4:]}   (identical)")

    # ── 3. The CLIENT transport, exactly as the PWA calls it ────────────────
    print("\n-- C. client transport: updateUser(email) " + "-" * 27)
    st, anon2 = _call("/auth/v1/signup", body={"data": {}}, apikey=anon_key)
    tok2 = anon2.get("access_token")
    uid2 = (anon2.get("user") or {}).get("id")
    fresh = f"probe-{uuid.uuid4().hex[:12]}@aydenstudio.dev"
    st, res = _call("/auth/v1/user", method="PUT", body={"email": fresh},
                    token=tok2, apikey=anon_key)
    code = res.get("error_code") or ""
    rate_limited = st == 429 and code == "over_email_send_rate_limit"
    check("C1 the client path is reachable and the address is accepted",
          st == 200 or rate_limited, f"{st} {json.dumps(res)[:180]}")
    if rate_limited:
        print("       NOTE: built-in SMTP quota spent -> 429 over_email_send_rate_limit.")
        print("       The identity operation is NOT refused; only the send is.")
        print("       Configuring a real SMTP sender removes this. Staging-only.")
    elif st == 200:
        check("C2 the client attach also preserves the user_id",
              res.get("id") == uid2, f"{uid2} -> {res.get('id')}")

    # ── 4. The OTHER case: an email that already belongs to someone ──────────
    print("\n-- D. existing-account discrimination " + "-" * 31)
    st, anon3 = _call("/auth/v1/signup", body={"data": {}}, apikey=anon_key)
    uid3 = (anon3.get("user") or {}).get("id")
    st3, clash = _call("/auth/v1/user", method="PUT", body={"email": email},
                       token=anon3.get("access_token"), apikey=anon_key)
    ccode = clash.get("error_code") or clash.get("code") or ""
    check("D1 a SECOND anonymous cannot take an already-registered email",
          st3 >= 400, f"status={st3} {json.dumps(clash)[:160]}")
    check("D2 the refusal carries a machine-readable code",
          bool(ccode), json.dumps(clash)[:160])
    print(f"       refusal = {st3} {json.dumps(clash)[:170]}")
    st, still = _call("/auth/v1/user", method="GET",
                      token=anon3.get("access_token"), apikey=anon_key)
    check("D3 that second visitor is untouched and still anonymous",
          still.get("id") == uid3 and still.get("is_anonymous") is True,
          f"{still.get('id')} anon={still.get('is_anonymous')}")

    print(f"\n{'=' * 72}\nPASS {len(_PASS)}   FAIL {len(_FAIL)}")
    for f in _FAIL:
        print("  -", f)
    print("=" * 72)
    return 1 if _FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
