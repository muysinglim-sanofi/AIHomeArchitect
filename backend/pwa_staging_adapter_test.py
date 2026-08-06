"""PWA staging adapter — isolation, tenancy and fail-closed tests.

Deterministic and fully offline: no Supabase, no OpenAI, no key, no network.
`httpx.AsyncClient` is replaced by a recording fake, and the canonical engine is
injected as a stub module, so what is measured is the ADAPTER's behaviour and
nothing else.

What these tests are actually defending
---------------------------------------
The adapter is a second CALLER of the canonical engine, not a second engine. The
risk it carries is not a wrong pixel — it is (a) pointing at production, (b)
serving one tenant's data to another, (c) quietly growing a parallel prompt, and
(d) charging twice for one generation. Each of those has a test below.

Run:  PYTHONIOENCODING=utf-8 PYTHONPATH=. python pwa_staging_adapter_test.py
"""
from __future__ import annotations

import asyncio
import os
import pathlib
import sys
import types

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

STAGING_URL = "https://eedcahzekpgxvvfxufbk.supabase.co"
PRODUCTION_URL = "https://vtxkciupyafukhdsgxgw.supabase.co"
UID = "11111111-1111-4111-8111-111111111111"
OTHER_UID = "22222222-2222-4222-8222-222222222222"
PROJECT = "33333333-3333-4333-8333-333333333333"
TOKEN = "a-user-session-token-that-must-never-be-echoed"

_passed: list[str] = []
_failed: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    (_passed if ok else _failed).append(label)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}{'' if ok else f'  {detail}'}")


# ── a recording stand-in for httpx ──────────────────────────────────────────


class _Resp:
    def __init__(self, status: int, payload=None, content: bytes = b""):
        self.status_code = status
        self._payload = payload
        self.content = content

    def json(self):
        return self._payload


class _FakeClient:
    """Routes by (method, url-fragment). Records every call so a test can prove
    what did NOT happen — which is the interesting half here."""

    def __init__(self, routes: dict, calls: list):
        self._routes = routes
        self.calls = calls

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_):
        return False

    def _resolve(self, method: str, url: str) -> _Resp:
        self.calls.append((method, url))
        for fragment, resp in self._routes.items():
            if fragment in url:
                return resp(url) if callable(resp) else resp
        raise AssertionError(f"unrouted {method} {url}")

    async def get(self, url, **kw):
        return self._resolve("GET", url)

    async def post(self, url, **kw):
        return self._resolve("POST", url)

    async def patch(self, url, **kw):
        return self._resolve("PATCH", url)


def _install_fake_httpx(api, routes: dict, calls: list):
    api.httpx.AsyncClient = lambda *a, **k: _FakeClient(routes, calls)


# ── canonical engine stubs (proving the adapter CALLS them) ─────────────────


def _install_canonical_stubs(record: dict) -> None:
    """Inject the modules the adapter imports for a real render. It imports them
    INSIDE the function, so replacing sys.modules here is what it will bind."""

    class _Img:
        b64_json = None

    fake_main = types.ModuleType("main")
    fake_main.IMAGE_MODEL = "gpt-image-2"
    fake_main._detect_output_size = lambda _b: "1536x1024"

    class _Images:
        async def edit(self, **kwargs):
            record["edit_kwargs"] = kwargs
            import base64
            import io as _io

            from PIL import Image as _Pil

            # A real RGBA PNG, so the adapter's re-encode step (flatten alpha →
            # JPEG q=85) runs for real rather than falling back to raw bytes.
            buf = _io.BytesIO()
            _Pil.new("RGBA", (8, 8), (200, 180, 140, 255)).save(buf, format="PNG")

            r = types.SimpleNamespace()
            img = _Img()
            img.b64_json = base64.b64encode(buf.getvalue()).decode()
            r.data = [img]
            return r

    fake_main.openai = types.SimpleNamespace(images=_Images())

    fake_profiles = types.ModuleType("generation_profiles")
    fake_profiles.get_active_profile = lambda: types.SimpleNamespace(
        compact_prompts=True, size_override=None, quality="high",
        quality_overrides={},
    )

    fake_engine = types.ModuleType("prompt_engine")

    def _compose(**kwargs):
        record["compose_kwargs"] = kwargs
        return "THE CANONICAL PROMPT"

    fake_engine.compose_generation_prompt = _compose

    sys.modules["main"] = fake_main
    sys.modules["generation_profiles"] = fake_profiles
    sys.modules["prompt_engine"] = fake_engine


# ── tests ───────────────────────────────────────────────────────────────────


def test_fail_closed_environment(api) -> None:
    print("\n== 1) Fail-closed: the adapter refuses anything that is not staging ==")
    from fastapi import HTTPException

    def refuses(url: str) -> bool:
        os.environ["SUPABASE_URL"] = url
        try:
            api._supabase_url()
            return False
        except HTTPException as e:
            return e.detail.get("error_code") == "STAGING_MISCONFIGURED"

    check("production project ref is refused", refuses(PRODUCTION_URL))
    check("an empty SUPABASE_URL is refused", refuses(""))
    check("an unrelated project is refused", refuses("https://elsewhere.supabase.co"))
    check(
        "a URL merely CONTAINING the prod ref is refused",
        refuses(f"https://eedcahzekpgxvvfxufbk.supabase.co/{'vtxkciupyafukhdsgxgw'}"),
    )
    os.environ["SUPABASE_URL"] = STAGING_URL
    check("the authorized staging project is accepted", api._supabase_url() == STAGING_URL)


def test_token_required(api) -> None:
    print("\n== 2) A caller without a session never reaches the backend ==")
    from fastapi import HTTPException

    for label, header in (
        ("absent", None),
        ("empty", ""),
        ("not a bearer", "Basic abc"),
    ):
        try:
            api._bearer(header)
            check(f"Authorization {label} → 401", False, "no exception")
        except HTTPException as e:
            check(
                f"Authorization {label} → 401",
                e.status_code == 401 and e.detail["error_code"] == "MISSING_TOKEN",
            )
    check("a bearer token is extracted verbatim", api._bearer(f"Bearer {TOKEN}") == TOKEN)


def test_path_ownership(api) -> None:
    print("\n== 3) A Storage path outside the caller's own folder is refused ==")
    from fastapi import HTTPException

    def refused(path: str) -> bool:
        try:
            api._assert_owned_path(path, UID, PROJECT)
            return False
        except HTTPException as e:
            return e.status_code == 403 and e.detail["error_code"] == "PATH_FORBIDDEN"

    api._assert_owned_path(f"users/{UID}/projects/{PROJECT}/original/o.jpg", UID, PROJECT)
    check("the caller's own path is accepted", True)
    check(
        "another user's folder is refused",
        refused(f"users/{OTHER_UID}/projects/{PROJECT}/original/o.jpg"),
    )
    check(
        "another project of the same user is refused",
        refused(f"users/{UID}/projects/{OTHER_UID}/original/o.jpg"),
    )
    check("traversal is refused", refused(f"users/{UID}/projects/{PROJECT}/../../o.jpg"))
    check("a bare relative path is refused", refused("o.jpg"))
    check(
        "a forged prefix is refused",
        refused(f"xusers/{UID}/projects/{PROJECT}/original/o.jpg"),
    )


def test_idempotent_replay_costs_nothing(api) -> None:
    print("\n== 4) A replay returns the existing vision and generates nothing ==")
    os.environ["SUPABASE_URL"] = STAGING_URL
    calls: list = []
    prior = {
        "id": "vision-1",
        "vision_number": 1,
        "image_path": f"users/{UID}/projects/{PROJECT}/generated/vision-1.jpg",
    }
    _install_fake_httpx(
        api,
        {
            "/auth/v1/user": _Resp(200, {"id": UID}),
            "/rest/v1/pwa_visions": _Resp(200, [prior]),
        },
        calls,
    )
    engine_calls = []
    api._run_canonical_engine = lambda **kw: engine_calls.append(kw)

    body = api.PwaGenerateRequest(
        project_id=PROJECT,
        room_label="Living Room",
        atmosphere_id="ayden_signature",
        atmosphere_label="Ayden Signature",
        original_image_path=f"users/{UID}/projects/{PROJECT}/original/o.jpg",
        idempotency_key="the-same-key",
    )
    out = asyncio.run(api.pwa_generate(body, authorization=f"Bearer {TOKEN}"))

    check("the existing vision is returned", out["vision_id"] == "vision-1")
    check("it is reported as a replay", out["replayed"] is True)
    check("the engine was NOT called", engine_calls == [])
    check(
        "no image was uploaded",
        not any(m == "POST" and "/storage/" in u for m, u in calls),
    )
    check(
        "no second vision row was inserted",
        not any(m == "POST" and "pwa_visions" in u for m, u in calls),
    )


def test_foreign_project_is_refused(api) -> None:
    print("\n== 5) A project owned by someone else is refused before any work ==")
    from fastapi import HTTPException

    os.environ["SUPABASE_URL"] = STAGING_URL
    calls: list = []
    _install_fake_httpx(
        api,
        {
            "/auth/v1/user": _Resp(200, {"id": UID}),
            "/rest/v1/pwa_visions": _Resp(200, []),
            "/rest/v1/pwa_projects": _Resp(200, [{"id": PROJECT, "owner_user_id": OTHER_UID}]),
        },
        calls,
    )
    engine_calls = []
    api._run_canonical_engine = lambda **kw: engine_calls.append(kw)

    body = api.PwaGenerateRequest(
        project_id=PROJECT,
        room_label="Living Room",
        atmosphere_id="ayden_signature",
        atmosphere_label="Ayden Signature",
        original_image_path=f"users/{UID}/projects/{PROJECT}/original/o.jpg",
        idempotency_key="k",
    )
    try:
        asyncio.run(api.pwa_generate(body, authorization=f"Bearer {TOKEN}"))
        check("a foreign project → 403", False, "no exception")
    except HTTPException as e:
        check(
            "a foreign project → 403",
            e.status_code == 403 and e.detail["error_code"] == "PROJECT_FORBIDDEN",
        )
    check("nothing was generated for it", engine_calls == [])


def test_uses_the_canonical_engine(api, record: dict, real_engine) -> None:
    print("\n== 6) The render goes through the CANONICAL composer and client ==")
    # The endpoint tests above stubbed this out to prove it was NOT reached;
    # restore the real one, which is what this test is about.
    api._run_canonical_engine = real_engine
    out = asyncio.run(
        api._run_canonical_engine(
            image_bytes=b"original-bytes",
            room_label="Living Room",
            atmosphere_label="Japandi Calm",
            atmosphere_id="japandi_calm",
            user_instruction="warmer lighting",
            iteration=2,
        )
    )
    compose = record.get("compose_kwargs", {})
    edit = record.get("edit_kwargs", {})

    check("prompt_engine.compose_generation_prompt was called", bool(compose))
    check("the room reached the composer", compose.get("room_type") == "Living Room")
    check("the atmosphere reached the composer", compose.get("style_label") == "Japandi Calm")
    check(
        "the user instruction reached the composer",
        compose.get("user_instruction") == "warmer lighting",
    )
    check("the iteration reached the composer", compose.get("iteration") == 2)
    check("main.openai.images.edit was called", bool(edit))
    check("the model is the canonical one", edit.get("model") == "gpt-image-2")
    check(
        "the prompt sent is the COMPOSER's, not the adapter's",
        edit.get("prompt") == "THE CANONICAL PROMPT",
    )
    check("a JPEG came back out", out[:2] == b"\xff\xd8")


def test_no_parallel_engine_in_source() -> None:
    print("\n== 7) The adapter holds no engine and no prompt of its own ==")
    src = (HERE / "pwa_staging_api.py").read_text(encoding="utf-8")
    for banned in ("AsyncOpenAI(", "OpenAI(", "openai.Client(", "api_key="):
        check(f"no provider construction: {banned!r}", banned not in src)
    check(
        "the canonical composer is imported, not reimplemented",
        "from prompt_engine import compose_generation_prompt" in src,
    )
    check("the canonical module is imported", "import main as canonical" in src)
    check(
        "the model comes from the canonical module",
        "canonical.IMAGE_MODEL" in src,
    )
    # A prompt lives in prompt_engine. Anything long and prose-like here would be
    # the beginning of a second one.
    for marker in ("You are an", "interior design", "photorealistic", "Preserve the"):
        check(f"no prompt text in the adapter: {marker!r}", marker not in src)


def test_launcher_is_fail_closed() -> None:
    print("\n== 8) The launcher refuses to start against production ==")
    import run_pwa_staging as launcher

    def dies(url: str) -> bool:
        try:
            launcher._assert_staging(url, "test")
            return False
        except SystemExit as e:
            return e.code == 2

    check("production URL → refuses to start", dies(PRODUCTION_URL))
    check("empty URL → refuses to start", dies(""))
    check("an unrelated project → refuses to start", dies("https://other.supabase.co"))
    launcher._assert_staging(STAGING_URL, "test")
    check("the staging URL starts", True)

    src = (HERE / "run_pwa_staging.py").read_text(encoding="utf-8")
    # It patches its own process, never a file on disk: no writer of any kind.
    for writer in ("write_text(", "writelines(", "shutil.", "'w'", '"w"'):
        check(f"the launcher writes no file: {writer!r}", writer not in src)
    check(
        "the adapter is mounted by the LAUNCHER, not by main.py",
        "canonical.app.include_router(pwa_staging_api.router)" in src,
    )
    check("no --reload (stale-DNA rule)", "reload=True" not in src)


def test_no_secret_is_ever_echoed(api) -> None:
    print("\n== 9) No error path echoes a token or a key ==")
    from fastapi import HTTPException

    os.environ["SUPABASE_URL"] = PRODUCTION_URL
    messages = []
    try:
        api._supabase_url()
    except HTTPException as e:
        messages.append(str(e.detail))
    os.environ["SUPABASE_URL"] = STAGING_URL
    try:
        api._bearer("Bearer " + TOKEN) and api._assert_owned_path("nope", UID, PROJECT)
    except HTTPException as e:
        messages.append(str(e.detail))

    blob = " ".join(messages)
    check("no session token in any error payload", TOKEN not in blob)
    check("no URL in any error payload", "supabase.co" not in blob)

    src = (HERE / "pwa_staging_api.py").read_text(encoding="utf-8")
    check("the module logs no token", "log.info(token" not in src and "%s\", token" not in src)
    check(
        "the rejected-path log names no path",
        'log.warning("[pwa-staging] rejected storage path outside' in src
        and "%s\", path" not in src,
    )


def main() -> int:
    record: dict = {}
    _install_canonical_stubs(record)
    os.environ["SUPABASE_URL"] = STAGING_URL
    os.environ.setdefault("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_test_only")

    import pwa_staging_api as api

    # Kept before the endpoint tests replace it, so test 6 can exercise the real
    # one rather than a leftover stub.
    real_engine = api._run_canonical_engine

    test_fail_closed_environment(api)
    test_token_required(api)
    test_path_ownership(api)
    test_idempotent_replay_costs_nothing(api)
    test_foreign_project_is_refused(api)
    test_uses_the_canonical_engine(api, record, real_engine)
    test_no_parallel_engine_in_source()
    test_launcher_is_fail_closed()
    test_no_secret_is_ever_echoed(api)

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
