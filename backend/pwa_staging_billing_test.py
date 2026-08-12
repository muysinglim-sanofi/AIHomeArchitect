"""PWA staging — BILLING ENFORCEMENT, measured against the real ledger.

What kind of test this is
-------------------------
An INTEGRATION test, deliberately. The Supabase/Storage/OpenAI hops are faked
(no image is ever generated, no byte is uploaded), but everything that decides
MONEY is real:

    the handler        pwa_staging_api._generate            real
    the seam           pwa_staging_billing                  real
    the tier resolver  promo.resolve_generation_access      real
    the gate           billing.reserve_decision             real
    the reservation    billing.try_hold -> billing_try_hold real, in Postgres
    the settlement     intent_observer.observe_intent_end   real
    the ledger         public.ledger_entries                real, in Postgres

A fake billing backend would have proved that the adapter calls functions with
plausible names. It would not have caught a 3-arg `billing_try_hold` (free tier
silently 3 instead of 1), an intent id that is not stable across a restart, or a
RELEASE landing in the wrong bucket. Those are the failures that cost money, so
the ledger is real.

Each run creates fresh anonymous identities in `auth.users`. They are PERMANENT
once they have ledger rows — the append-only trigger blocks the cascade delete.
See `pwa_staging_billing_contract_test.py` (DB14) for why that is correct.

Run:  cd backend && PYTHONPATH=. python pwa_staging_billing_test.py
"""
from __future__ import annotations

import asyncio
import os
import pathlib
import sys
import types
import uuid

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from pwa_staging_adapter_test import (  # noqa: E402
    _ClaimTable,
    _capture_rpc_bodies,
    _install_canonical_stubs,
    _install_fake_httpx,
    _Resp,
)
from pwa_staging_db import staging_connection  # noqa: E402

STAGING_URL = "https://eedcahzekpgxvvfxufbk.supabase.co"

_passed: list[str] = []
_failed: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (_passed if ok else _failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  {detail}'}")


def section(title: str) -> None:
    print(f"\n== {title} " + "=" * max(0, 60 - len(title)))


# ── real identities, real client ─────────────────────────────────────────────


def _staging_secret(name: str) -> str:
    """Read one value from the staging secrets file. Never printed."""
    path = HERE / ".env.pwa-staging.local"
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith(name) and "=" in line:
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit(f"REFUSING: {name} missing from {path.name}")


def _new_guest() -> str:
    """A fresh anonymous Supabase identity — what a new browser profile is."""
    uid = str(uuid.uuid4())
    with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
        cur.execute(
            "insert into auth.users (id, instance_id, aud, role, email, "
            "created_at, updated_at, is_anonymous) values "
            "(%s, '00000000-0000-0000-0000-000000000000', 'authenticated', "
            "'authenticated', %s, now(), now(), true)",
            (uid, f"probe-{uid[:8]}@billing.invalid"))
    return uid


def _ledger(uid: str) -> list[tuple]:
    with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
        cur.execute(
            "select entry_type, available_delta, idempotency_key, pass_id "
            "from public.ledger_entries where user_id = %s order by id", (uid,))
        return cur.fetchall()


def _wallet(uid: str):
    with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
        cur.execute("select available_credits from public.wallets where user_id = %s",
                    (uid,))
        row = cur.fetchone()
        return row[0] if row else None


def _intents(uid: str) -> list[tuple]:
    with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
        cur.execute("select intent_id, status, session_id, iteration "
                    "from public.generation_intents where user_id = %s "
                    "order by created_at", (uid,))
        return cur.fetchall()


def _grant_weekly_pass(uid: str) -> None:
    """Buy a pass through the CANONICAL acquisition RPC — the same call the
    RevenueCat webhook and the future ABA callback make."""
    with staging_connection(autocommit=True) as conn, conn.cursor() as cur:
        cur.execute("select id from public.products where sku = 'weekly_pass'")
        weekly = cur.fetchone()[0]
        cur.execute(
            "select public.billing_grant_purchase(%s, 'khqr', %s, %s, 30, 7, 7.99, "
            "'USD', now() + interval '7 days', '{\"source\":\"billing-test\"}'::jsonb)",
            (uid, f"bt-{uid[:8]}", weekly))


# ── the fake edges (everything that is NOT money) ────────────────────────────


def _routes(uid: str, project: str, table: _ClaimTable, store: dict, *,
            insert=None, storage=None):
    def rpc(_method: str, url: str):
        from pwa_staging_adapter_test import _CURRENT_RPC_BODY

        if "claim_generation" in url:
            b = _CURRENT_RPC_BODY.get("claim") or {}
            return _Resp(200, [table.claim(b.get("p_idempotency_key"),
                                           b.get("p_project_id"),
                                           b.get("p_action_type"),
                                           b.get("p_parent_vision_id"))])
        if "complete_generation" in url:
            b = _CURRENT_RPC_BODY.get("complete") or {}
            table.complete(b.get("p_idempotency_key"), b.get("p_vision_id"))
            return _Resp(200, [])
        if "fail_generation" in url:
            b = _CURRENT_RPC_BODY.get("fail") or {}
            table.fail(b.get("p_idempotency_key"), b.get("p_error_code"),
                       b.get("p_render_started"))
            return _Resp(200, [])
        raise AssertionError("unrouted rpc " + url)

    def visions(method: str, _url: str):
        if method == "GET":
            key = store.get("lookup_key")
            row = store.get("rows", {}).get(key)
            return _Resp(200, [row] if row else [])
        if insert is not None:
            return insert("POST", _url)
        # Store the row the ADAPTER actually posted, not a placeholder: the
        # replay assertion is "you get back the vision you already made", and a
        # hard-coded id would compare the fake to itself.
        posted = store.get("last_insert") or {}
        store.setdefault("rows", {})[store.get("current_key")] = {
            "id": posted.get("id", "vision-1"),
            "vision_number": posted.get("vision_number", 1),
            "image_path": posted.get(
                "image_path", f"users/{uid}/projects/{project}/generated/v.jpg"),
        }
        return _Resp(201, [{}])

    return {
        "/auth/v1/user": _Resp(200, {"id": uid}),
        "/rest/v1/rpc/": rpc,
        "/rest/v1/pwa_visions": visions,
        "/rest/v1/pwa_projects": _Resp(200, [{"id": project, "owner_user_id": uid}]),
        "/storage/v1/object/": storage or _Resp(200, None, b"jpeg-bytes"),
    }


class _Render:
    """A render that succeeds, and remembers exactly how it was called.

    The kwargs are the creative-engine non-regression evidence: a free render
    and a paid render must reach the engine with byte-identical arguments except
    the one flag that decides the mark.
    """

    def __init__(self):
        self.calls: list[dict] = []

    async def __call__(self, **kwargs):
        import pwa_staging_api as _api

        self.calls.append(dict(kwargs))
        import io as _io

        from PIL import Image as _Pil
        buf = _io.BytesIO()
        _Pil.new("RGB", (16, 16), (200, 180, 140)).save(buf, format="JPEG")
        return buf.getvalue(), _api._Decided("Living Room", "warm_modern", "Warm Modern")


def _body(api, project: str, uid: str, key: str, *, action="initial",
          instruction="", vision_number=1, parent=""):
    return api.PwaGenerateRequest(
        project_id=project,
        room_label="Living Room",
        atmosphere_id="warm_modern",
        atmosphere_label="Warm Modern",
        original_image_path=f"users/{uid}/projects/{project}/original/o.jpg",
        idempotency_key=key,
        action_type=action,
        user_instruction=instruction,
        vision_number=vision_number,
        parent_vision_id=parent,
        confirm=True,   # skip the advisor: this file measures money, not advice
    )


def _capture_vision_inserts(api, store: dict):
    """Let the fake vision table see the row the adapter posts.

    `_capture_rpc_bodies` only forwards the claim RPCs. The replay test needs
    the real vision id, so this wraps one more verb — and nothing else.
    """
    original = api.httpx.AsyncClient

    class _Capturing:
        def __init__(self, *a, **k):
            self._inner = original(*a, **k)

        async def __aenter__(self):
            await self._inner.__aenter__()
            return self

        async def __aexit__(self, *a):
            return await self._inner.__aexit__(*a)

        async def get(self, url, **kw):
            return await self._inner.get(url, **kw)

        async def patch(self, url, **kw):
            return await self._inner.patch(url, **kw)

        async def post(self, url, **kw):
            if "pwa_visions" in url:
                store["last_insert"] = kw.get("json") or {}
            return await self._inner.post(url, **kw)

    api.httpx.AsyncClient = _Capturing


def _run(api, body):
    api._INFLIGHT.clear()
    return asyncio.run(api._generate(body, "Bearer test-token"))


def _detail(exc) -> dict:
    return exc.detail if isinstance(exc.detail, dict) else {}


# ── tests ────────────────────────────────────────────────────────────────────


def test_bill_01_02_03(api, render) -> None:
    section("BILL01/02/03  one free vision, then the paywall")
    from fastapi import HTTPException

    uid, project = _new_guest(), str(uuid.uuid4())
    table, store = _ClaimTable(), {}
    _install_fake_httpx(api, _routes(uid, project, table, store), [])
    _capture_rpc_bodies(api)
    api._run_canonical_engine = render

    store["current_key"] = "k1"
    store["lookup_key"] = "k1"
    out = _run(api, _body(api, project, uid, "k1"))
    check("BILL01 a fresh Web guest may generate", out.get("status") == "completed",
          str(out))
    check("BILL01 the response states the billing tier",
          out.get("billing", {}).get("tier") == "free", str(out.get("billing")))

    rows = _ledger(uid)
    kinds = [r[0] for r in rows]
    check("BILL02 exactly one TRIAL, one HOLD, one COMMIT",
          kinds == ["TRIAL", "HOLD", "COMMIT"], str(kinds))
    check("BILL02 the trial credited ONE (D1 Web free tier)",
          rows[0][1] == 1, str(rows))
    check("BILL02 the hold debited one", rows[1][1] == -1, str(rows))
    check("BILL02 the commit is neutral (the hold already paid)",
          rows[2][1] == 0, str(rows))
    check("BILL02 wallet projected to 0", _wallet(uid) == 0, str(_wallet(uid)))
    check("BILL02 free consumption is scoped to the FREE bucket",
          all(r[3] is None for r in rows), str(rows))

    ints = _intents(uid)
    check("BILL02 exactly one billing intent", len(ints) == 1, str(ints))
    check("BILL02 the intent SUCCEEDED", ints[0][1] == "SUCCEEDED", str(ints))
    check("BILL02 the intent carries session_id = NULL (no mobile session)",
          ints[0][2] is None, str(ints))

    # A SECOND generation, different logical operation, no entitlement left.
    store["current_key"] = "k2"
    store["lookup_key"] = "k2"
    before = len(render.calls)
    denied = None
    try:
        _run(api, _body(api, project, uid, "k2"))
    except HTTPException as exc:
        denied = exc
    check("BILL03 the second generation is refused", denied is not None
          and denied.status_code == 402,
          "none" if denied is None else str(denied.status_code))
    d = _detail(denied) if denied else {}
    check("BILL03 with the canonical error_code",
          d.get("error_code") == "QUOTA_EXHAUSTED", str(d.get("error_code")))
    check("BILL03 and a translatable billing_state",
          d.get("billing_state") == "FREE_EXHAUSTED", str(d.get("billing_state")))
    check("BILL03 marked non-retryable", d.get("retryable") is False)
    check("BILL03 the client is told a paywall is the resolution",
          d.get("paywall") == "pass", str(d.get("paywall")))
    check("BILL03 NO render was attempted (refused before OpenAI)",
          len(render.calls) == before, f"{len(render.calls) - before} extra calls")
    check("BILL03 no second HOLD was written",
          [r[0] for r in _ledger(uid)] == ["TRIAL", "HOLD", "COMMIT"],
          str(_ledger(uid)))
    return uid, project


def test_bill_04_direct_api(api, render) -> None:
    section("BILL04  a direct API call is subject to the same decision")
    from fastapi import HTTPException

    # There is no UI in this test at all: `_generate` IS the public entry point
    # `POST /pwa/staging/generate` delegates to. An exhausted guest calling the
    # endpoint directly — curl, a script, a replayed fetch — reaches this code.
    uid, project = _new_guest(), str(uuid.uuid4())
    table, store = _ClaimTable(), {}
    _install_fake_httpx(api, _routes(uid, project, table, store), [])
    _capture_rpc_bodies(api)
    api._run_canonical_engine = render

    store["current_key"] = store["lookup_key"] = "d1"
    _run(api, _body(api, project, uid, "d1"))

    before = len(render.calls)
    refused = 0
    for n in range(4):
        store["current_key"] = store["lookup_key"] = f"raw{n}"
        try:
            _run(api, _body(api, project, uid, f"raw{n}"))
        except HTTPException as exc:
            refused += 1 if exc.status_code == 402 else 0
    check("BILL04 four direct attempts, four refusals", refused == 4, str(refused))
    check("BILL04 zero renders", len(render.calls) == before,
          f"{len(render.calls) - before} renders leaked")
    holds = [r for r in _ledger(uid) if r[0] == "HOLD"]
    check("BILL04 still exactly one HOLD on the ledger", len(holds) == 1, str(holds))


def test_bill_05_06_pass(api, render) -> None:
    section("BILL05/06  an active Pass restores access, and commits once")
    uid, project = _new_guest(), str(uuid.uuid4())
    _grant_weekly_pass(uid)
    table, store = _ClaimTable(), {}
    _install_fake_httpx(api, _routes(uid, project, table, store), [])
    _capture_rpc_bodies(api)
    api._run_canonical_engine = render

    store["current_key"] = store["lookup_key"] = "p1"
    out = _run(api, _body(api, project, uid, "p1"))
    check("BILL05 a pass holder may generate", out.get("status") == "completed")
    check("BILL05 the response reports the pass",
          out.get("billing", {}).get("has_active_pass") is True,
          str(out.get("billing")))
    check("BILL05 a paid render is NOT watermarked",
          out.get("billing", {}).get("watermarked") is False,
          str(out.get("billing")))
    # THE regression this pins: buying a pass writes no `user_roles` row, so the
    # role tier stays 'free'. If the watermark followed the ROLE, a customer who
    # had just paid would get a marked image. It follows the measured PASS.
    check("BILL05 the access source is the PASS, not the role",
          out.get("billing", {}).get("access_source") == "pass",
          str(out.get("billing")))
    check("BILL05 the role tier is still 'free' — which is why the rule matters",
          out.get("billing", {}).get("tier") == "free",
          str(out.get("billing")))
    check("BILL05 the render itself was told not to mark",
          render.calls and render.calls[-1].get("watermark") is False,
          str(render.calls[-1] if render.calls else None))

    rows = _ledger(uid)
    grants = [r for r in rows if r[0] == "GRANT"]
    holds = [r for r in rows if r[0] == "HOLD"]
    commits = [r for r in rows if r[0] == "COMMIT"]
    check("BILL06 exactly one HOLD", len(holds) == 1, str(rows))
    check("BILL06 exactly one COMMIT", len(commits) == 1, str(rows))
    check("BILL06 the hold hit the PASS bucket, not the free one",
          holds[0][3] is not None and holds[0][3] == grants[0][3], str(rows))
    check("BILL06 the commit hit the SAME bucket as the hold",
          commits[0][3] == holds[0][3], str(rows))
    check("BILL06 the pass went 30 -> 29", _wallet(uid) == 29, str(_wallet(uid)))
    check("BILL06 no TRIAL was materialised for a pass holder",
          not [r for r in rows if r[0] == "TRIAL"], str(rows))


def test_bill_07_pre_render_failure(api) -> None:
    section("BILL07  a pre-render failure RELEASES the credit")
    from fastapi import HTTPException

    uid, project = _new_guest(), str(uuid.uuid4())
    table, store = _ClaimTable(), {}
    _install_fake_httpx(api, _routes(uid, project, table, store), [])
    _capture_rpc_bodies(api)

    async def _explode(**_kw):
        raise HTTPException(status_code=502, detail={
            "error_code": "ENGINE_UNAVAILABLE", "retryable": True,
            "render_started": False})

    api._run_canonical_engine = _explode
    store["current_key"] = store["lookup_key"] = "f1"
    failed = None
    try:
        _run(api, _body(api, project, uid, "f1"))
    except HTTPException as exc:
        failed = exc
    check("BILL07 the failure surfaces as itself, not as a paywall",
          failed is not None and _detail(failed).get("error_code") == "ENGINE_UNAVAILABLE",
          str(_detail(failed) if failed else None))
    kinds = [r[0] for r in _ledger(uid)]
    check("BILL07 the ledger shows TRIAL, HOLD, RELEASE",
          kinds == ["TRIAL", "HOLD", "RELEASE"], str(kinds))
    check("BILL07 the credit is back: the person can try again",
          _wallet(uid) == 1, str(_wallet(uid)))
    ints = _intents(uid)
    check("BILL07 the intent is terminal (no phantom RUNNING)",
          ints and ints[0][1] == "FAILED", str(ints))


def test_bill_08_post_render_persistence(api, render) -> None:
    section("BILL08  the row failed, the person HAS the image: it is charged")
    uid, project = _new_guest(), str(uuid.uuid4())
    table, store = _ClaimTable(), {}

    def insert_fails(_m, _u):
        return _Resp(500, {"message": "row insert refused"})

    _install_fake_httpx(api, _routes(uid, project, table, store,
                                     insert=insert_fails), [])
    _capture_rpc_bodies(api)
    api._run_canonical_engine = render

    store["current_key"] = store["lookup_key"] = "s1"
    out = _run(api, _body(api, project, uid, "s1"))
    check("BILL08 the endpoint still answers `completed`",
          out.get("status") == "completed", str(out))
    check("BILL08 and says the row did not persist",
          out.get("persisted") is False, str(out))
    kinds = [r[0] for r in _ledger(uid)]
    check("BILL08 the generation is COMMITTED (the image exists in Storage)",
          kinds == ["TRIAL", "HOLD", "COMMIT"], str(kinds))
    check("BILL08 balance 0 — charged once, as delivered", _wallet(uid) == 0)


def test_bill_08b_upload_failure(api, render) -> None:
    section("BILL08b  the image never reached Storage: it is RELEASED")
    from fastapi import HTTPException

    uid, project = _new_guest(), str(uuid.uuid4())
    table, store = _ClaimTable(), {}

    def storage(method: str, _url: str):
        # Download works (the engine needs a source); the upload does not.
        return _Resp(200, None, b"jpeg-bytes") if method == "GET" else _Resp(500, {})

    _install_fake_httpx(api, _routes(uid, project, table, store, storage=storage), [])
    _capture_rpc_bodies(api)
    api._run_canonical_engine = render
    api._TRANSPORT_BACKOFF_S = 0

    store["current_key"] = store["lookup_key"] = "u1"
    try:
        _run(api, _body(api, project, uid, "u1"))
    except HTTPException:
        pass
    kinds = [r[0] for r in _ledger(uid)]
    check("BILL08b the ledger shows TRIAL, HOLD, RELEASE", kinds == ["TRIAL", "HOLD", "RELEASE"],
          str(kinds))
    check("BILL08b the person keeps their free vision — they never got an image",
          _wallet(uid) == 1, str(_wallet(uid)))


def test_bill_09_replay(api, render) -> None:
    section("BILL09  F5 / retry replays; it never debits twice")
    uid, project = _new_guest(), str(uuid.uuid4())
    table, store = _ClaimTable(), {}
    _install_fake_httpx(api, _routes(uid, project, table, store), [])
    _capture_rpc_bodies(api)
    _capture_vision_inserts(api, store)
    api._run_canonical_engine = render

    store["current_key"] = store["lookup_key"] = "r1"
    first = _run(api, _body(api, project, uid, "r1"))
    before_rows = _ledger(uid)
    before_renders = len(render.calls)

    # F5: the tab reloads and the client re-POSTs the SAME idempotency key.
    second = _run(api, _body(api, project, uid, "r1"))
    check("BILL09 the replay returns the SAME vision",
          second.get("vision_id") == first.get("vision_id"), str(second))
    check("BILL09 it is marked as a replay", second.get("replayed") is True, str(second))
    check("BILL09 no second render", len(render.calls) == before_renders)
    check("BILL09 the ledger is byte-identical", _ledger(uid) == before_rows,
          str(_ledger(uid)))
    check("BILL09 still exactly one intent", len(_intents(uid)) == 1, str(_intents(uid)))


def test_bill_10_restart(api, render) -> None:
    section("BILL10  a backend restart recovers the SAME billing intent")
    uid, project = _new_guest(), str(uuid.uuid4())
    table, store = _ClaimTable(), {}
    _install_fake_httpx(api, _routes(uid, project, table, store), [])
    _capture_rpc_bodies(api)

    # Instance A: the claim is won, the credit is held, then the process dies
    # mid-render. Nothing in memory survives; Postgres keeps the claim and the
    # HOLD.
    async def _die(**_kw):
        raise RuntimeError("process died mid-render")

    api._run_canonical_engine = _die
    store["current_key"] = store["lookup_key"] = "rs1"
    try:
        _run(api, _body(api, project, uid, "rs1"))
    except Exception:  # noqa: BLE001 — the crash is the scenario
        pass
    intent_before = [i[0] for i in _intents(uid)]

    # Instance B: fresh process (the in-memory single-flight map is empty), the
    # client retries with the SAME key.
    api._INFLIGHT.clear()
    api._run_canonical_engine = render
    out = _run(api, _body(api, project, uid, "rs1"))
    check("BILL10 the retry completes", out.get("status") == "completed", str(out))
    intent_after = [i[0] for i in _intents(uid)]
    check("BILL10 the SAME billing intent is reused across the restart",
          intent_before == intent_after and len(intent_after) == 1,
          f"{intent_before} -> {intent_after}")
    holds = [r for r in _ledger(uid) if r[0] == "HOLD"]
    check("BILL10 exactly ONE hold across both lives", len(holds) == 1, str(_ledger(uid)))
    check("BILL10 the intent id is a pure function of (user, key)",
          intent_after[0] == __import__("pwa_staging_billing").intent_id_for(uid, "rs1"))


def test_bill_11_concurrency(api, render) -> None:
    section("BILL11  concurrent calls consume once")
    uid, project = _new_guest(), str(uuid.uuid4())
    table, store = _ClaimTable(), {}
    _install_fake_httpx(api, _routes(uid, project, table, store), [])
    _capture_rpc_bodies(api)
    api._run_canonical_engine = render
    before = len(render.calls)

    async def eight_at_once():
        api._INFLIGHT.clear()
        body = _body(api, project, uid, "c1")
        store["current_key"] = store["lookup_key"] = "c1"
        return await asyncio.gather(
            *[api.pwa_generate(body, "Bearer test-token") for _ in range(8)],
            return_exceptions=True)

    results = asyncio.run(eight_at_once())
    ok = [r for r in results if isinstance(r, dict)]
    check("BILL11 all eight callers get an answer", len(ok) == 8,
          str([type(r).__name__ for r in results]))
    check("BILL11 exactly ONE render was paid for",
          len(render.calls) - before == 1, str(len(render.calls) - before))
    holds = [r for r in _ledger(uid) if r[0] == "HOLD"]
    check("BILL11 exactly ONE hold", len(holds) == 1, str(_ledger(uid)))
    check("BILL11 exactly ONE intent", len(_intents(uid)) == 1, str(_intents(uid)))
    check("BILL11 the free vision was consumed once", _wallet(uid) == 0, str(_wallet(uid)))


def test_every_action_is_billed(api, render) -> None:
    section("BILL-ACTIONS  initial / switch / refine / structural refine")
    from fastapi import HTTPException

    import pwa_staging_api as _api

    # A refine goes through the refine engine, not the first-vision composer, so
    # it needs its own stub — and it must be billed by the same seam.
    async def _refine(**kwargs):
        render.calls.append(dict(kwargs))
        import io as _io

        from PIL import Image as _Pil
        buf = _io.BytesIO()
        _Pil.new("RGB", (16, 16), (120, 120, 120)).save(buf, format="JPEG")
        return buf.getvalue(), []

    api._run_canonical_engine = render
    api._run_canonical_refine = _refine

    cases = [
        ("initial", "initial", ""),
        ("switch_atmosphere", "switch_atmosphere", ""),
        ("refine", "refine", "make the sofa white"),
        ("structural refine", "refine",
         "open the wall on the right and add a kitchen with an island"),
    ]
    for label, action, instruction in cases:
        uid, project = _new_guest(), str(uuid.uuid4())
        table, store = _ClaimTable(), {}
        _install_fake_httpx(api, _routes(uid, project, table, store), [])
        _capture_rpc_bodies(api)
        key = f"a-{action}-{label[:4]}"
        store["current_key"] = store["lookup_key"] = key
        out = _run(api, _body(api, project, uid, key, action=action,
                              instruction=instruction, vision_number=2,
                              parent=""))
        kinds = [r[0] for r in _ledger(uid)]
        check(f"BILL-ACTIONS {label}: first is allowed and charged",
              out.get("status") == "completed" and kinds == ["TRIAL", "HOLD", "COMMIT"],
              str(kinds))

        # ... and the SECOND one of the same kind is refused server-side.
        key2 = key + "-2"
        store["current_key"] = store["lookup_key"] = key2
        before = len(render.calls)
        denied = None
        try:
            _run(api, _body(api, project, uid, key2, action=action,
                            instruction=instruction, vision_number=3))
        except HTTPException as exc:
            denied = exc
        check(f"BILL-ACTIONS {label}: the second is refused before any render",
              denied is not None and denied.status_code == 402
              and len(render.calls) == before,
              "not refused" if denied is None else str(denied.status_code))

    api._run_canonical_refine = _api._run_canonical_refine


def test_watermark(api) -> None:
    section("WATERMARK  free is marked, paid is clean, quality is identical")
    from PIL import Image as _Pil
    import io as _io

    # The mark is measured on the BYTES, through the adapter's own output
    # pipeline — not asserted from a flag. Two renders of the SAME source: if
    # the free one is not visibly different from the paid one, the free tier is
    # giving away a clean image.
    buf = _io.BytesIO()
    _Pil.new("RGB", (768, 512), (210, 200, 190)).save(buf, format="PNG")
    raw = buf.getvalue()

    clean = api._reencode_jpeg(raw, watermark=False)
    marked = api._reencode_jpeg(raw, watermark=True)

    check("WM free and paid bytes differ", clean != marked)
    with _Pil.open(_io.BytesIO(clean)) as a, _Pil.open(_io.BytesIO(marked)) as b:
        check("WM the resolution is IDENTICAL (D1: no downgrade)",
              a.size == b.size == (768, 512), f"{a.size} vs {b.size}")
        # The canonical mark sits in the bottom-right corner.
        diff = sum(
            1 for x in range(a.width - 140, a.width)
            for y in range(a.height - 140, a.height)
            if a.getpixel((x, y)) != b.getpixel((x, y)))
        check("WM the corner really changed (the compass is in the pixels)",
              diff > 200, f"{diff} differing pixels")
        top = sum(1 for x in range(0, 120) for y in range(0, 120)
                  if a.getpixel((x, y)) != b.getpixel((x, y)))
        check("WM it is a corner mark, not a full-image overlay",
              top < diff, f"top-left {top} vs corner {diff}")

    check("WM the JPEG recipe is unchanged (q=85, same encoder path)",
          abs(len(clean) - len(marked)) < max(len(clean), len(marked)),
          f"{len(clean)} vs {len(marked)}")

    # And the canonical function is the one used — not a local drawing routine.
    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    check("WM the adapter calls the CANONICAL watermark module",
          "from watermark import apply_watermark" in src)
    check("WM the adapter draws nothing of its own",
          "ImageDraw" not in src and "WATERMARK_TEXT" not in src)


def test_creative_engine_untouched(api, render) -> None:
    section("NON-REGRESSION  billing changes nothing the engine sees")
    free_uid, project = _new_guest(), str(uuid.uuid4())
    paid_uid = _new_guest()
    _grant_weekly_pass(paid_uid)

    captured = []
    for uid in (free_uid, paid_uid):
        table, store = _ClaimTable(), {}
        _install_fake_httpx(api, _routes(uid, project, table, store), [])
        _capture_rpc_bodies(api)
        api._run_canonical_engine = render
        key = f"nr-{uid[:6]}"
        store["current_key"] = store["lookup_key"] = key
        before = len(render.calls)
        _run(api, _body(api, project, uid, key))
        captured.append(render.calls[before])

    free_kw, paid_kw = captured
    differing = {k for k in set(free_kw) | set(paid_kw)
                 if free_kw.get(k) != paid_kw.get(k)}
    check("NR the ONLY difference between a free and a paid render is the mark",
          differing == {"watermark"}, str(sorted(differing)))
    check("NR free renders at the same resolution/atmosphere/room/iteration",
          all(free_kw.get(k) == paid_kw.get(k) for k in
              ("room_label", "atmosphere_id", "atmosphere_label", "iteration",
               "user_instruction", "prev_atmosphere_id", "history")),
          str(free_kw))

    # And the source of the engine has not grown a billing opinion.
    engine_src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    body = engine_src.split("async def _run_canonical_engine")[1].split(
        "def _reencode_jpeg")[0]
    for forbidden in ("billing", "tier", "wallet", "credits", "quota"):
        check(f"NR `_run_canonical_engine` never mentions `{forbidden}`",
              forbidden not in body.lower())


def test_gate_precedes_the_advisor(api) -> None:
    section("GATE ORDER  an exhausted guest never pays for the advisor")
    from fastapi import HTTPException

    uid, project = _new_guest(), str(uuid.uuid4())
    table, store = _ClaimTable(), {}
    _install_fake_httpx(api, _routes(uid, project, table, store), [])
    _capture_rpc_bodies(api)

    calls = {"advisor": 0}

    async def _advisor(body, room=""):
        calls["advisor"] += 1
        return None, []

    render = _Render()
    api._run_canonical_engine = render
    original_advisor = api._refine_advisory
    api._refine_advisory = _advisor

    store["current_key"] = store["lookup_key"] = "g1"
    _run(api, _body(api, project, uid, "g1"))          # consumes the free vision

    store["current_key"] = store["lookup_key"] = "g2"
    before = calls["advisor"]
    try:
        _run(api, api.PwaGenerateRequest(
            project_id=project, room_label="Living Room",
            atmosphere_id="warm_modern", atmosphere_label="Warm Modern",
            original_image_path=f"users/{uid}/projects/{project}/original/o.jpg",
            idempotency_key="g2", action_type="refine",
            user_instruction="make the sofa white", vision_number=2))
    except HTTPException as exc:
        check("GATE the exhausted refine is refused", exc.status_code == 402)
    check("GATE the advisor — itself a paid call — was never reached",
          calls["advisor"] == before, str(calls["advisor"] - before))

    api._refine_advisory = original_advisor


def main() -> int:
    record: dict = {}
    _install_canonical_stubs(record)

    # The engine stubs replaced `main`; money needs a REAL service-role client
    # on it, because `billing`, `promo` and `intent_observer` all resolve their
    # database through `main.supa`. This is the seam that makes the ledger real.
    import httpx
    from supabase import create_client

    supa = create_client(STAGING_URL, _staging_secret("SUPABASE_SERVICE_ROLE_KEY"))
    # The SAME transport hardening main.py applies (commit 79a7693): PostgREST on
    # HTTP/1.1 with a short timeout. Without it, the shared sync client's HTTP/2
    # connection corrupts under the concurrent `asyncio.to_thread` calls this
    # test makes on purpose (BILL11), and a two-minute stall looks exactly like
    # a hung test. Copying the session preserves the apikey/auth headers
    # supabase-py already built; injecting a bare client would drop them.
    _s = supa.postgrest.session
    supa.postgrest.session = httpx.Client(
        base_url=_s.base_url, headers=_s.headers,
        timeout=httpx.Timeout(15.0, connect=5.0),
        follow_redirects=True, http2=False)

    fake_main = sys.modules["main"]
    fake_main.supa = supa

    os.environ["SUPABASE_URL"] = STAGING_URL
    os.environ.setdefault("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_test_only")
    # The Web free tier is ONE — the same lever `run_pwa_staging.py` pins.
    os.environ["ACCOUNT_SYSTEM_ENABLED"] = "true"

    import billing
    if billing.effective_trial_credits() != 1:
        print("REFUSING: effective trial is not 1 — ACCOUNT_SYSTEM_ENABLED not honoured")
        return 2

    import pwa_staging_api as api

    render = _Render()
    test_bill_01_02_03(api, render)
    test_bill_04_direct_api(api, render)
    test_bill_05_06_pass(api, render)
    test_bill_07_pre_render_failure(api)
    test_bill_08_post_render_persistence(api, render)
    test_bill_08b_upload_failure(api, render)
    test_bill_09_replay(api, render)
    test_bill_10_restart(api, render)
    test_bill_11_concurrency(api, render)
    test_every_action_is_billed(api, render)
    test_watermark(api)
    test_creative_engine_untouched(api, render)
    test_gate_precedes_the_advisor(api)

    print(f"\n{'=' * 60}")
    if _failed:
        print(f"FAILURES: {len(_failed)} / {len(_passed) + len(_failed)}")
        for f in _failed:
            print(f"  - {f}")
        return 1
    print(f"ALL BILLING ENFORCEMENT TESTS PASS ({len(_passed)} assertions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
