"""The vision ordinal is the SERVER's — and a 409 never becomes a phantom.

Staging, 2026-09-10 (claim `ac4c6cb8`): a browser holding a stale copy of its
project asked for vision_number 2 while 2 was taken. `UNIQUE (project_id,
vision_number)` refused the row; the refusal was handled as a transport
failure — the image returned anyway, the claim settled COMPLETED, the Space
committed — and the answer named a vision (`b7fe1dea`) that exists nowhere.
Every later switch named that phantom as its parent and was refused
PARENT_FORBIDDEN, which the phone showed as "Something went wrong".

Pinned here, offline, on the adapter's own harness (stubbed `main`, stubbed
billing, a recorded HTTP client that also sees the query and the body):

  1. `_next_vision_number` asks for the max of THIS project and answers max+1;
  2. `_insert_vision_row` tells OUR key's twin from a taken NUMBER, retries the
     number, and never reports a number it did not try;
  3. end to end: a stale client number is stored under the server's, the answer
     carries it, and an ordinal race is never `persisted: False`;
  4. PARENT_FORBIDDEN is logged with both ids before it is refused.

    cd backend && .venv/Scripts/python.exe pwa_staging_vision_ordinal_test.py
"""
from __future__ import annotations

import asyncio
import logging
import os
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import pwa_staging_adapter_test as harness  # noqa: E402

PASSES: list[str] = []
FAILS: list[str] = []


def check(label: str, ok: bool, detail: object = "") -> None:
    (PASSES if ok else FAILS).append(label)
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}" + ("" if ok else f"  ({detail})"))


class _Resp:
    def __init__(self, status: int, payload=None, content: bytes = b""):
        self.status_code = status
        self._payload = payload
        self.content = content
        self.text = "" if payload is None else str(payload)

    def json(self):
        return self._payload


class _Client:
    """httpx.AsyncClient stand-in whose route sees the PARAMS and the BODY: the
    ordinal read, the lineage read, the parent check and the replay probe all
    hit `/rest/v1/pwa_visions`, and only the query tells them apart."""

    def __init__(self, route, calls: list):
        self._route = route
        self.calls = calls

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_):
        return False

    def _go(self, method: str, url: str, kw: dict):
        self.calls.append((method, url, kw))
        out = self._route(method, url, kw.get("params") or {}, kw.get("json"))
        if out is None:
            raise AssertionError(f"unrouted {method} {url}")
        return out

    async def get(self, url, **kw):
        return self._go("GET", url, kw)

    async def post(self, url, **kw):
        return self._go("POST", url, kw)

    async def patch(self, url, **kw):
        return self._go("PATCH", url, kw)


# ── 1) the ordinal read ─────────────────────────────────────────────────────

def test_next_number(api) -> None:
    print("\n== 1) The next ordinal is read from the project's rows ==")
    seen: list[dict] = []

    def route(_m, _u, params, _b):
        seen.append(params)
        return _Resp(200, [{"vision_number": 4}])

    n = asyncio.run(api._next_vision_number(_Client(route, []), "tok", "p1"))
    check("ORD01: highest 4 -> the next is 5", n == 5, n)
    p = seen[-1]
    check("ORD02: it asks for the MAX of THIS project — one row, ordered",
          p.get("project_id") == "eq.p1" and p.get("order") == "vision_number.desc"
          and p.get("limit") == "1", p)
    n = asyncio.run(api._next_vision_number(
        _Client(lambda *_: _Resp(200, []), []), "tok", "p1"))
    check("ORD03: an empty project starts at 1", n == 1, n)
    n = asyncio.run(api._next_vision_number(
        _Client(lambda *_: _Resp(500, {"x": 1}), []), "tok", "p1"))
    check("ORD04: an unreadable project is None (the caller keeps the client's "
          "number; the unique constraint still guards)", n is None, n)


# ── 2) the insert: a key twin is not a taken number ─────────────────────────

def _insert(api, answers: list, *, winner=None, max_after=None):
    posts: list[dict] = []
    answers = list(answers)

    def route(method, _u, params, body):
        if method == "POST":
            posts.append(dict(body))
            return answers.pop(0)
        if "idempotency_key" in params:
            return _Resp(200, [winner] if winner else [])
        if params.get("order") == "vision_number.desc":
            return _Resp(200, [{"vision_number": max_after}] if max_after else [])
        return None

    row = {"id": "new", "project_id": "p1", "vision_number": 2,
           "idempotency_key": "k"}
    r, won = asyncio.run(api._insert_vision_row(
        _Client(route, []), "tok", row, idempotency_key="k", project_id="p1"))
    return r, won, posts, row


def test_insert(api) -> None:
    print("\n== 2) A 409 is either our own twin or a taken NUMBER — never a phantom ==")
    api._TRANSPORT_BACKOFF_S = 0

    r, won, posts, row = _insert(api, [_Resp(201, [{}])])
    check("ORD05: a free number is written once, as asked",
          r.status_code == 201 and won is None and len(posts) == 1
          and row["vision_number"] == 2, (r.status_code, won, posts))

    r, won, posts, row = _insert(api, [_Resp(409, {"code": "23505"}),
                                       _Resp(201, [{}])], max_after=3)
    check("ORD06: a taken number is re-read and retried under the next one",
          r.status_code == 201 and won is None
          and [p["vision_number"] for p in posts] == [2, 4]
          and row["vision_number"] == 4, [p["vision_number"] for p in posts])

    twin = {"id": "won", "vision_number": 2, "image_path": "users/u/x.jpg"}
    r, won, posts, _row = _insert(api, [_Resp(409, {"code": "23505"})], winner=twin)
    check("ORD07: our OWN key already stored -> that row is the answer, no retry",
          won == twin and len(posts) == 1, (won, len(posts)))

    r, won, posts, row = _insert(api, [_Resp(409, {}), _Resp(409, {}),
                                       _Resp(409, {})])
    check("ORD08: it gives up after three offers — each a new number",
          r.status_code == 409 and won is None
          and [p["vision_number"] for p in posts] == [2, 3, 4],
          [p["vision_number"] for p in posts])
    check("ORD09: and reports the number it tried LAST, not one it never tried",
          row["vision_number"] == 4, row["vision_number"])


# ── 3) end to end, through the real endpoint ────────────────────────────────

def _project_rows():
    base = f"users/{harness.UID}/projects/{harness.PROJECT}/generated"
    common = {"atmosphere_label": "Warm Modern", "lineage_customized": False,
              "room_label": "Living Room", "prompt_text": None,
              "project_id": harness.PROJECT}
    return [
        {"id": "v1", "vision_number": 1, "parent_vision_id": None,
         "action_type": "initial", "image_path": f"{base}/v1.jpg",
         "atmosphere_id": "warm_modern", **common},
        {"id": "v2", "vision_number": 2, "parent_vision_id": "v1",
         "action_type": "switch_atmosphere", "image_path": f"{base}/v2.jpg",
         "atmosphere_id": "soft_luxury", **common},
    ]


def _run_generate(api, *, parent: str, races: int = 0):
    rows = _project_rows()
    inserted: list[dict] = []
    calls: list = []
    race = {"n": races}

    def route(method, url, params, body):
        if "/auth/v1/user" in url:
            return _Resp(200, {"id": harness.UID})
        if "/rest/v1/pwa_projects" in url:
            return _Resp(200, [{"id": harness.PROJECT, "owner_user_id": harness.UID}])
        if "/storage/v1/object/" in url:
            return _Resp(200, None, b"jpeg-bytes")
        if "/rest/v1/pwa_visions" not in url:
            return None
        if method == "POST":
            if race["n"] > 0:
                # Another vision lands on this number between the read and the write.
                race["n"] -= 1
                rows.append({**rows[-1], "id": f"elsewhere-{race['n']}",
                             "vision_number": body["vision_number"]})
                return _Resp(409, {"code": "23505", "message": "duplicate key"})
            inserted.append(dict(body))
            rows.append(dict(body))
            return _Resp(201, [dict(body)])
        if "idempotency_key" in params:
            return _Resp(200, [])
        if "id" in params:  # the parent check
            vid = params["id"].removeprefix("eq.")
            return _Resp(200, [r for r in rows if r["id"] == vid][:1])
        if params.get("order") == "vision_number.desc":
            top = max(r["vision_number"] for r in rows)
            return _Resp(200, [{"vision_number": top}])
        return _Resp(200, list(rows))  # the lineage read

    api.httpx.AsyncClient = lambda *a, **k: _Client(route, calls)
    body = api.PwaGenerateRequest(
        project_id=harness.PROJECT, room_label="Living Room",
        atmosphere_id="japandi_calm", atmosphere_label="Japandi Calm",
        original_image_path=f"users/{harness.UID}/projects/{harness.PROJECT}/original/o.jpg",
        idempotency_key=f"stale-client-{parent}-{races}",
        action_type="switch_atmosphere",
        vision_number=2,  # STALE: the project already holds 1 and 2
        parent_vision_id=parent,
    )
    out = asyncio.run(api.pwa_generate(body, authorization=f"Bearer {harness.TOKEN}"))
    return out, inserted


def test_end_to_end(api) -> None:
    print("\n== 3) End to end: a stale number is stored under the server's ==")
    os.environ["SUPABASE_URL"] = harness.STAGING_URL
    real_engine = api._run_canonical_engine
    api._run_canonical_engine = harness._stub_render
    api._TRANSPORT_BACKOFF_S = 0
    try:
        out, inserted = _run_generate(api, parent="v1")
        check("ORD10: the render completes", out.get("status") == "completed", out)
        check("ORD11: the row is stored as 3, not the 2 the stale client asked",
              inserted and inserted[-1]["vision_number"] == 3,
              [r["vision_number"] for r in inserted])
        check("ORD12: and the answer says 3, so the client shows what is stored",
              out.get("vision_number") == 3, out.get("vision_number"))
        check("ORD13: the vision is real — never `persisted: False`",
              out.get("persisted") is not False and out.get("vision_id")
              == inserted[-1]["id"], out)

        out, inserted = _run_generate(api, parent="v1", races=1)
        check("ORD14: a number taken DURING the write is retried under the next",
              [r["vision_number"] for r in inserted] == [4]
              and out.get("vision_number") == 4,
              ([r["vision_number"] for r in inserted], out.get("vision_number")))
        check("ORD15: an ordinal race is never answered as an unsaved image",
              out.get("persisted") is not False, out)
    finally:
        api._run_canonical_engine = real_engine


# ── 4) the phantom parent is named in the log ───────────────────────────────

class _Capture(logging.Handler):
    def __init__(self):
        super().__init__()
        self.lines: list[str] = []

    def emit(self, record):
        self.lines.append(record.getMessage())


def test_parent_forbidden_is_logged(api) -> None:
    print("\n== 4) PARENT_FORBIDDEN says which vision and which project ==")
    from fastapi import HTTPException

    os.environ["SUPABASE_URL"] = harness.STAGING_URL
    cap = _Capture()
    api.log.addHandler(cap)
    try:
        _run_generate(api, parent="b7fe1dea-0000-phantom")
        check("ORD16: a parent that is not in the project is refused", False,
              "no exception")
    except HTTPException as e:
        check("ORD16: a parent that is not in the project is refused",
              e.status_code == 403 and e.detail["error_code"] == "PARENT_FORBIDDEN",
              (e.status_code, e.detail))
    finally:
        api.log.removeHandler(cap)
    hit = [ln for ln in cap.lines if "PARENT_FORBIDDEN" in ln]
    check("ORD17: and the log names the phantom and the project",
          bool(hit) and "b7fe1dea" in hit[0] and harness.PROJECT[:8] in hit[0],
          cap.lines[-3:])


def main() -> int:
    harness._install_canonical_stubs(harness._RECORD)
    os.environ["SUPABASE_URL"] = harness.STAGING_URL
    os.environ.setdefault("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_test_only")
    import pwa_staging_api as api  # noqa: PLC0415

    harness._install_billing_stub(api)
    original_client = api.httpx.AsyncClient
    try:
        test_next_number(api)
        test_insert(api)
        test_end_to_end(api)
        test_parent_forbidden_is_logged(api)
    finally:
        api.httpx.AsyncClient = original_client

    print(f"\n{'=' * 60}")
    if FAILS:
        print(f"FAILED: {len(FAILS)} / {len(PASSES) + len(FAILS)}")
        for f in FAILS:
            print(f"  - {f}")
        return 1
    print(f"ALL PASS ({len(PASSES)} checks)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
