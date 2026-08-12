"""The SHARED operational seam — characterization + incident regression.

These tests exist at the shared layer on purpose. The 2026-08-06 incident was
first read as a PWA bug; the audit showed the mobile `/generate` had the same
hole. Pinning the behaviour here, once, is what stops the two paths drifting
back apart.

Deterministic, offline, no key, no provider call, no Supabase.
Run:  PYTHONIOENCODING=utf-8 PYTHONPATH=. python generation_resilience_test.py
"""
from __future__ import annotations

import asyncio
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from generation_resilience import (  # noqa: E402
    DEFAULT_ATTEMPTS,
    PaidResultLost,
    RetryPolicy,
    save_paid_result,
    with_transport_retries,
)

_passed: list[str] = []
_failed: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (_passed if ok else _failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  {detail}'}")


class Blip(Exception):
    """Stands in for a transport failure (httpx.TransportError, socket error…)."""


class Permanent(Exception):
    """Stands in for an API error: a 403, a quota, a bad request."""


NO_WAIT = RetryPolicy(attempts=3, backoff_s=0)


# ── the retry policy itself ──────────────────────────────────────────────────


def test_retry_semantics() -> None:
    print("\n== 1) Retries are bounded, typed, and never touch a paid call ==")

    calls = {"n": 0}

    async def flaky():
        calls["n"] += 1
        if calls["n"] < 3:
            raise Blip("socket")
        return "stored"

    out = asyncio.run(
        with_transport_retries(flaky, stage="upload_result",
                               retry_on=(Blip,), policy=NO_WAIT)
    )
    check("a transient failure is retried until it succeeds", out == "stored")
    check("it took exactly the attempts it needed", calls["n"] == 3)

    calls["n"] = 0

    async def always_blip():
        calls["n"] += 1
        raise Blip("socket")

    try:
        asyncio.run(with_transport_retries(always_blip, stage="upload_result",
                                           retry_on=(Blip,), policy=NO_WAIT))
        check("a permanent transport failure raises PaidResultLost", False, "no raise")
    except PaidResultLost as lost:
        check("a permanent transport failure raises PaidResultLost", True)
        check("it names the stage that gave up", lost.stage == "upload_result")
        check("it carries the cause", isinstance(lost.cause, Blip))
    check("it is bounded, not infinite", calls["n"] == 3)

    # An API error is a decision, not a blip.
    calls["n"] = 0

    async def forbidden():
        calls["n"] += 1
        raise Permanent("403")

    try:
        asyncio.run(with_transport_retries(forbidden, stage="upload_result",
                                           retry_on=(Blip,), policy=NO_WAIT))
        check("a non-transport error is not retried", False, "no raise")
    except Permanent:
        check("a non-transport error is not retried", calls["n"] == 1)
    except PaidResultLost:
        check("a non-transport error is not retried", False, "wrongly wrapped")

    check("the default budget is three attempts", DEFAULT_ATTEMPTS == 3)
    check("backoff grows", RetryPolicy().delay_for(2) > RetryPolicy().delay_for(1))


def test_save_order_is_storage_then_row() -> None:
    print("\n== 2) The bytes land before the row that points at them ==")
    order: list[str] = []

    async def upload():
        order.append("upload")
        return "users/u/projects/p/generated/v.jpg"

    async def persist(path: str):
        order.append(f"persist:{path}")

    out = asyncio.run(
        save_paid_result(upload=upload, persist=persist,
                         retry_on=(Blip,), policy=NO_WAIT)
    )
    check("storage first, row second", order[0] == "upload" and order[1].startswith("persist:"))
    check("the row is given what storage returned", order[1].endswith("/generated/v.jpg"))
    check("the caller gets the storage result back", out.endswith("/generated/v.jpg"))

    # A row is never written for an object that does not exist.
    wrote = {"n": 0}

    async def bad_upload():
        raise Blip("socket")

    async def counting_persist(_p):
        wrote["n"] += 1

    try:
        asyncio.run(save_paid_result(upload=bad_upload, persist=counting_persist,
                                     retry_on=(Blip,), policy=NO_WAIT))
    except PaidResultLost:
        pass
    check("no row is written when the upload never lands", wrote["n"] == 0)

    # The row itself is retried too — it is also after the money.
    tries = {"n": 0}

    async def ok_upload():
        return "p"

    async def flaky_persist(_p):
        tries["n"] += 1
        if tries["n"] < 2:
            raise Blip("socket")

    asyncio.run(save_paid_result(upload=ok_upload, persist=flaky_persist,
                                 retry_on=(Blip,), policy=NO_WAIT))
    check("a flaky row write is retried as well", tries["n"] == 2)


def test_the_incident_end_to_end() -> None:
    print("\n== 3) THE incident: render paid, first upload times out ==")
    # OpenAI answered 200 and the JPEG exists. The first connect to Storage
    # times out. Before this module that render was discarded.
    render = {"calls": 0}
    uploads = {"n": 0}

    async def provider():  # never retried — a paid call must not be repeated
        render["calls"] += 1
        return b"the-paid-jpeg"

    async def upload():
        uploads["n"] += 1
        if uploads["n"] == 1:
            raise Blip("ConnectTimeout")
        return "users/u/projects/p/generated/v.jpg"

    async def run():
        image = await provider()
        assert image
        return await save_paid_result(upload=upload, retry_on=(Blip,), policy=NO_WAIT)

    path = asyncio.run(run())
    check("the paid render is saved on the retry", path.endswith("/generated/v.jpg"))
    check("the provider was called exactly once", render["calls"] == 1)
    check("the upload was retried once", uploads["n"] == 2)

    # And when Storage is genuinely down: an honest, typed loss — never a
    # silent success, and never a second paid call.
    render["calls"] = 0

    async def dead_upload():
        raise Blip("ConnectTimeout")

    async def run_failing():
        await provider()
        return await save_paid_result(upload=dead_upload, retry_on=(Blip,), policy=NO_WAIT)

    try:
        asyncio.run(run_failing())
        check("a dead Storage is reported, not swallowed", False, "no raise")
    except PaidResultLost as lost:
        check("a dead Storage is reported, not swallowed", lost.stage == "upload_result")
    check("still exactly one paid call", render["calls"] == 1)


# ── both callers really do use it ────────────────────────────────────────────


def test_both_paths_share_this_module() -> None:
    print("\n== 4) Mobile and PWA route through the SAME seam ==")
    mobile = (HERE / "main.py").read_text(encoding="utf-8")
    pwa = (HERE / "pwa_staging_api.py").read_text(encoding="utf-8")

    check("mobile imports the shared module",
          "from generation_resilience import" in mobile)
    check("mobile's Storage upload goes through save_paid_result",
          "await save_paid_result(" in mobile)
    check("PWA imports the shared module",
          "from generation_resilience import" in pwa)
    check("PWA routes its stages through with_transport_retries",
          "with_transport_retries(" in pwa)

    # No second copy of the algorithm. The retry loop lives in exactly one file.
    loop = re.compile(r"for attempt in range\(\s*1\s*,[^)]*attempts")
    check("no retry loop remains in the PWA adapter", not loop.search(pwa))
    check("no retry loop was added to main.py", not loop.search(mobile))

    shared = (HERE / "generation_resilience.py").read_text(encoding="utf-8")
    check("the retry loop exists once, in the shared module", bool(loop.search(shared)))


def _executable_source(path: pathlib.Path) -> str:
    """The file with its comments and docstrings removed.

    The prose in this module deliberately NAMES supabase, httpx and the wallet
    to explain what it does not depend on. Scanning the raw text for those words
    would therefore fail on its own documentation — what has to be checked is
    the code that actually runs.
    """
    import ast

    tree = ast.parse(path.read_text(encoding="utf-8"))
    # Comments never reach the AST; docstrings do, as a leading string
    # statement. Dropping those leaves exactly the code that executes.
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if not isinstance(body, list) or not body:
            continue
        first = body[0]
        if (isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant)
                and isinstance(first.value.value, str)):
            body.pop(0)
            if not body:  # keep the node syntactically valid
                body.append(ast.Pass())
    return ast.unparse(ast.fix_missing_locations(tree))


def test_the_shared_layer_stays_generic() -> None:
    print("\n== 5) The shared layer knows nothing about either data model ==")
    path = HERE / "generation_resilience.py"
    code = _executable_source(path)
    for leak in ("supabase", "httpx", "fastapi", "openai", "pwa_staging",
                 "prompt_engine", "wallet", "session_id", "IMAGE_MODEL",
                 "pwa_visions", "generation_intents"):
        check(f"no dependency on {leak!r}", leak not in code)

    imports = [
        line.strip() for line in path.read_text(encoding="utf-8").splitlines()
        if line.startswith(("import ", "from "))
    ]
    check("it imports only the standard library",
          all(i.split()[1].split(".")[0] in {"asyncio", "logging", "dataclasses",
                                             "typing", "__future__"}
              for i in imports),
          str(imports))
    # The rule that matters most: nothing in here may wrap the paid call.
    prose = " ".join(path.read_text(encoding="utf-8").split())
    check("the module states the provider is never retried",
          "provider call itself is NEVER retried" in prose)
    check("no code path re-invokes a provider",
          not any(w in code for w in ("images.edit", "openai", "provider(")))


def test_mobile_contract_is_unchanged(mobile_src: str) -> None:
    print("\n== 6) The mobile contract is byte-identical where it matters ==")
    # The extraction may change HOW the upload is attempted; it may not change
    # what a mobile client receives.
    for pin in (
        'error_code="STORAGE_FAILED"',
        'user_message="Your design was generated but couldn\'t be saved. Please try again."',
        "retryable=True",
        "status_code=500",
    ):
        check(f"unchanged: {pin[:48]}", pin in mobile_src)
    check("the refund guard is still in place",
          "if _reservation_id is not None:" in mobile_src
          and "await fail_generation(_reservation_id)" in mobile_src)
    check("the public URL is still what gets returned",
          "get_public_url(path)" in mobile_src)
    # A StorageApiError must still fail on the FIRST attempt.
    check("only transport errors are retried on mobile",
          "retry_on=(httpx.TransportError,)" in mobile_src)


def main() -> int:
    test_retry_semantics()
    test_save_order_is_storage_then_row()
    test_the_incident_end_to_end()
    test_both_paths_share_this_module()
    test_the_shared_layer_stays_generic()
    test_mobile_contract_is_unchanged((HERE / "main.py").read_text(encoding="utf-8"))

    print(f"\n{'=' * 60}")
    if _failed:
        print(f"ECHECS: {len(_failed)} / {len(_passed) + len(_failed)}")
        for f in _failed:
            print(f"  - {f}")
        return 1
    print(f"TOUS LES TESTS PASSENT ({len(_passed)} assertions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
