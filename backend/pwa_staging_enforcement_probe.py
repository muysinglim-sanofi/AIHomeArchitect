"""ENF01-ENF10 — can a determined browser generate without paying?

Brief §17 asks for proof of three things, and proof means TRYING them against
the running backend rather than reading the code and concluding it looks fine:

    * manual route navigation  -> a URL is not permission
    * a direct API call        -> curl is not permission
    * client state tampering   -> a lying request body is not permission

The shape of the argument
-------------------------
The PWA client is a browser. Everything it holds — the route, the Riverpod
state, the entitlement it just read — is editable by whoever owns the tab. So
none of it can be the thing that authorises a paid render. The only durable
answer is that the SERVER refuses, and this file measures that refusal on the
real staging deployment over real HTTP, with a real Supabase identity.

It deliberately does NOT mock the backend: a mocked enforcement test proves the
mock is strict. Nor does it render — every probe here is refused before an image
is made, which is exactly the property under test, so it costs no provider call.

Run:  cd backend && python pwa_staging_enforcement_probe.py
Safe: staging only, disposable identities, no production credential is read.
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
SUPA = f"https://{STAGING_REF}.supabase.co"
API = "http://127.0.0.1:8000"

_PASS: list[str] = []
_FAIL: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (_PASS if ok else _FAIL).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  -- {detail}'}")


def section(title: str) -> None:
    print(f"\n== {title} " + "=" * max(0, 60 - len(title)))


def _secret(name: str) -> str:
    for raw in (HERE / ".env.pwa-staging.local").read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith(name) and "=" in line:
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit(f"REFUSING: {name} missing")


def _http(url: str, *, method: str = "GET", body=None, token: str | None = None,
          apikey: str | None = None, timeout: int = 60) -> tuple[int, dict]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if apikey:
        req.add_header("apikey", apikey)
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw or b"{}")
        except Exception:  # noqa: BLE001
            return e.code, {"raw": raw[:200].decode("utf-8", "replace")}
    except Exception as e:  # noqa: BLE001
        return 0, {"transport": type(e).__name__}


def _detail(payload: dict) -> dict:
    """FastAPI nests HTTPException payloads under `detail`. Normalise both."""
    d = payload.get("detail")
    return d if isinstance(d, dict) else payload


def _source_path(uid: str, project: str) -> str:
    """The one Storage path this caller is allowed to name for this project.

    `_assert_owned_path` accepts nothing else: a forged prefix or a traversal is
    a 403 before any money is considered. Using the legal path is what lets the
    probe reach the billing gate and measure THAT.
    """
    return f"users/{uid}/projects/{project}/source.jpg"


def _seed_project(uid: str, project: str) -> None:
    """A real project row, so /generate reaches the BILLING gate.

    Ownership is checked before money — a request naming a project you do not
    own is refused as PROJECT_NOT_FOUND and never gets as far as the ledger.
    That ordering is correct (both are refusals) but it is not the property
    under test here, so the probe removes the ownership objection in order to
    measure the one that follows it.
    """
    from pwa_staging_db import staging_connection  # noqa: PLC0415

    with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
        # The table stamps the owner from `auth.uid()` and REFUSES a write with
        # no identity — which is itself part of the answer to §17, so the probe
        # presents an identity rather than disabling the trigger.
        cur.execute("select set_config('request.jwt.claims', %s, false)",
                    (json.dumps({"sub": uid, "role": "authenticated"}),))
        cur.execute(
            "insert into pwa_staging.pwa_projects "
            "(id, owner_user_id, title, status, room_id, room_label, "
            " selected_atmosphere_id, selected_atmosphere_label, "
            " original_image_path) values "
            "(%s::uuid, %s::uuid, 'ENF probe', 'active', 'living_room', "
            " 'Living Room', 'warm_modern', 'Warm Modern', %s)",
            (project, uid, _source_path(uid, project)))


def _spend_free_credit(uid: str) -> None:
    """Burn the free bucket through the CANONICAL gate, not by writing rows.

    `billing_try_hold` is the same RPC the generate path calls, so what this
    leaves behind is exactly the state a real first generation leaves: a TRIAL
    credit and a HOLD that consumed it. Hand-inserting a ledger row would prove
    nothing about the gate.
    """
    from pwa_staging_db import staging_connection  # noqa: PLC0415

    with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
        # (user, intent_id, tier, trial_credits) — the SAME four arguments the
        # generate path passes, with the same ON-mode trial of 1 (D1).
        cur.execute(
            "select public.billing_try_hold(%s::uuid, %s, 'free', 1)",
            (uid, f"enf-{uid[:8]}"))
        got = cur.fetchone()[0]
    if not (got or {}).get("granted"):
        raise SystemExit(f"REFUSING: could not spend the free credit: {got}")


def main() -> int:
    anon_key = _secret("SUPABASE_PUBLISHABLE_KEY")
    print(f"target      : {STAGING_REF}.supabase.co  +  {API}  (staging)")

    st, health = _http(f"{API}/pwa/staging/health")
    if st != 200:
        print(f"REFUSING: the staging backend is not up ({st} {health})")
        return 2

    # A real browser identity: an anonymous Supabase user with a real JWT.
    st, sess = _http(f"{SUPA}/auth/v1/signup", method="POST", body={"data": {}},
                     apikey=anon_key)
    token = sess.get("access_token")
    uid = (sess.get("user") or {}).get("id")
    if not token or not uid:
        print(f"REFUSING: no anonymous session ({st} {sess})")
        return 2
    print(f"identity    : {uid[:8]}...{uid[-4:]}")

    project = str(uuid.uuid4())
    _seed_project(uid, project)

    def generate(body_extra: dict | None = None, *, tok: str | None = token,
                 key: str | None = None) -> tuple[int, dict]:
        body = {
            "project_id": project,
            "room_id": "living_room",
            "room_label": "Living Room",
            "atmosphere_id": "warm_modern",
            "atmosphere_label": "Warm Modern",
            "original_image_path": _source_path(uid, project),
            "idempotency_key": key or f"enf-{uuid.uuid4().hex[:12]}",
            "action_type": "initial",
            "vision_number": 1,
            "ui_locale": "en",
        }
        body.update(body_extra or {})
        return _http(f"{API}/pwa/staging/generate", method="POST", body=body,
                     token=tok)

    # ── A. a direct API call, with no identity at all ────────────────────────
    section("A. the API without an identity")

    st, res = generate(tok=None)
    check("ENF01 an unauthenticated /generate is refused",
          st in (401, 403), f"{st} {json.dumps(res)[:160]}")

    st, res = generate(tok="not.a.real.jwt")
    check("ENF02 a forged bearer token is refused",
          st in (401, 403), f"{st} {json.dumps(res)[:160]}")

    st, res = _http(f"{API}/pwa/staging/entitlement")
    check("ENF03 entitlement cannot be read without an identity either",
          st in (401, 403), f"{st} {json.dumps(res)[:160]}")

    # ── B. what the client is TOLD, vs what the server decides ───────────────
    section("B. the entitlement is the server's answer, about the caller")

    st, ent = _http(f"{API}/pwa/staging/entitlement", token=token)
    check("ENF04 an authenticated guest gets an entitlement", st == 200,
          f"{st} {json.dumps(ent)[:160]}")
    check("ENF04 and it is the D1 web free tier: ONE, watermarked",
          ent.get("can_generate") is True and ent.get("free_credits") == 1
          and ent.get("watermarked") is True, json.dumps(ent)[:200])
    check("ENF05 no payment provider is claimed to be configured",
          (ent.get("payment") or {}).get("configured") is False,
          json.dumps(ent.get("payment")))

    # ── C. client state tampering ────────────────────────────────────────────
    #
    # Spend the free credit through the canonical gate, then ask again — lying
    # in every way a tampered client could lie.
    section("C. tampering, after the free vision is spent")
    _spend_free_credit(uid)

    st, ent2 = _http(f"{API}/pwa/staging/entitlement", token=token)
    check("ENF06 the server now reports the paywall state",
          st == 200 and ent2.get("can_generate") is False
          and ent2.get("billing_state") == "FREE_EXHAUSTED",
          json.dumps(ent2)[:200])

    st, res = generate()
    d = _detail(res)
    check("ENF07 a plain retry is refused with the canonical code",
          st == 402 and d.get("error_code") == "QUOTA_EXHAUSTED",
          f"{st} {json.dumps(res)[:200]}")
    check("ENF07 and names the billing state the client must render",
          d.get("billing_state") == "FREE_EXHAUSTED", json.dumps(d)[:200])
    check("ENF07 and says NO render was started",
          d.get("render_started") is False, json.dumps(d)[:200])

    # Every field a tampered client might add to buy itself access. None of
    # them is an input to the decision — the gate reads the LEDGER.
    liars = [
        ("a claimed premium tier", {"tier": "premium"}),
        ("a claimed active pass", {"has_active_pass": True, "pass_credits": 99}),
        ("a claimed credit balance", {"free_credits": 99, "credits_available": 99}),
        ("a claimed access source", {"access_source": "pass"}),
        ("a request to skip the watermark", {"watermark": False,
                                             "watermarked": False}),
        ("a claimed billing state", {"billing_state": "PASS_ACTIVE",
                                     "can_generate": True}),
        ("an injected user id", {"user_id": str(uuid.uuid4())}),
        ("an injected intent id", {"intent_id": "pwa:deadbeef"}),
    ]
    for label, extra in liars:
        st, res = generate(extra)
        d = _detail(res)
        check(f"ENF08 {label} does not buy a generation",
              st == 402 and d.get("error_code") == "QUOTA_EXHAUSTED",
              f"{st} {json.dumps(res)[:170]}")

    # ── D. someone else's identity ───────────────────────────────────────────
    section("D. a second browser cannot spend the first one's access")

    st, sess2 = _http(f"{SUPA}/auth/v1/signup", method="POST", body={"data": {}},
                      apikey=anon_key)
    token2 = sess2.get("access_token")
    uid2 = (sess2.get("user") or {}).get("id")

    st, ent3 = _http(f"{API}/pwa/staging/entitlement", token=token2)
    check("ENF09 the entitlement is per-identity, not per-request-body",
          st == 200 and ent3.get("can_generate") is True
          and ent3.get("free_credits") == 1, json.dumps(ent3)[:180])

    # The exhausted user's own token, but claiming to be the fresh one. The
    # server reads the JWT, never the body.
    st, res = generate({"user_id": uid2, "owner_user_id": uid2})
    d = _detail(res)
    check("ENF10 claiming another user's id in the body changes nothing",
          st == 402 and d.get("error_code") == "QUOTA_EXHAUSTED",
          f"{st} {json.dumps(res)[:180]}")

    # ── E. the route is not the gate ─────────────────────────────────────────
    section("E. routes and read endpoints are not permission")

    # There is no server route that renders without going through /generate.
    # The one adjacent endpoint is a pure READ of a claim that already exists.
    st, res = _http(
        f"{API}/pwa/staging/generation/{uuid.uuid4().hex}", token=token)
    check("ENF11 asking for an unknown generation invents nothing",
          st == 200 and res.get("state") in ("UNKNOWN", "FAILED"),
          f"{st} {json.dumps(res)[:160]}")
    check("ENF11 and returns no image", not res.get("image_path"),
          json.dumps(res)[:160])

    print(f"\n{'=' * 72}\nPASS {len(_PASS)}   FAIL {len(_FAIL)}")
    for f in _FAIL:
        print("  -", f)
    print("=" * 72)
    return 1 if _FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
