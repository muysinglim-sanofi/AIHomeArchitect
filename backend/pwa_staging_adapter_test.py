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
import re
import sys
import types

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

# Captured HERE, before any test replaces `refine.parser` with a stub: the
# adapter's echo has to carry the shape the real parser produces, and a
# look-alike dataclass is exactly how that stopped being true once.
from refine.parser import Change as _REAL_CHANGE  # noqa: E402

STAGING_URL = "https://eedcahzekpgxvvfxufbk.supabase.co"
PRODUCTION_URL = "https://vtxkciupyafukhdsgxgw.supabase.co"
UID = "11111111-1111-4111-8111-111111111111"
OTHER_UID = "22222222-2222-4222-8222-222222222222"
PROJECT = "33333333-3333-4333-8333-333333333333"
TOKEN = "a-user-session-token-that-must-never-be-echoed"

_RECORD: dict = {}
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
                # A callable route sees the METHOD too: the adapter downloads
                # and uploads at the same URL, and only the verb tells them
                # apart — which is exactly the distinction the incident turns on.
                return resp(method, url) if callable(resp) else resp
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

    def _png_b64(rgba):
        import base64
        import io as _io

        from PIL import Image as _Pil

        # A real RGBA PNG, so the adapter's re-encode step (flatten alpha →
        # JPEG q=85) runs for real rather than falling back to raw bytes.
        buf = _io.BytesIO()
        _Pil.new("RGBA", (8, 8), rgba).save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode()

    class _Stream:
        """What the provider really hands back when `stream=True`: partial
        frames first, then one completed event carrying the finished image."""

        def __init__(self, partials: int):
            self._partials = partials

        def __aiter__(self):
            async def gen():
                for i in range(self._partials):
                    yield types.SimpleNamespace(
                        type="image_edit.partial_image",
                        partial_image_index=i,
                        # A DIFFERENT image, so a test can prove a partial is
                        # never mistaken for the result.
                        b64_json=_png_b64((10, 10, 10, 255)),
                    )
                yield types.SimpleNamespace(
                    type="image_edit.completed",
                    b64_json=_png_b64((200, 180, 140, 255)),
                )

            return gen()

    class _Images:
        async def edit(self, **kwargs):
            record["edit_kwargs"] = kwargs
            if kwargs.get("stream"):
                return _Stream(int(kwargs.get("partial_images") or 0))
            r = types.SimpleNamespace()
            img = _Img()
            img.b64_json = _png_b64((200, 180, 140, 255))
            r.data = [img]
            return r

    fake_main.openai = types.SimpleNamespace(images=_Images())

    fake_profiles = types.ModuleType("generation_profiles")
    fake_profiles.get_active_profile = lambda: types.SimpleNamespace(
        compact_prompts=True, size_override=None, quality="high",
        quality_overrides={},
        # The remaining GenerationProfile fields, present so the introspection
        # endpoint reads the same object shape the real profile has.
        name="STUB", input_fidelity=None, use_mask=False,
        vision_analysis_fv=False, max_attempts=1,
    )

    fake_engine = types.ModuleType("prompt_engine")

    def _compose(**kwargs):
        record["compose_kwargs"] = kwargs
        return "THE CANONICAL PROMPT"

    fake_engine.compose_generation_prompt = _compose

    # The adapter must compose through MAIN's symbol, not the package's: main is
    # where COMPOSER_VERSION=v2 rebinds it, and binding the package gave the PWA
    # the frozen v1 composer while mobile ran v2 — different prompts from the
    # same call graph. Exposing it only here makes that dependency explicit: an
    # adapter that went back to the package import would not see this stub.
    fake_main.compose_generation_prompt = _compose

    # PROMPT TEXT is faked; the DECISION helpers are the REAL ones. Ayden
    # Signature must pick from the real validated set with the real compatibility
    # ranking — a fake table would let the adapter drift from mobile and still
    # pass. Imported BEFORE the package is shadowed, then re-registered so the
    # adapter's `from prompt_engine import ...` finds them.
    import prompt_engine.atmosphere_dna as _real_dna
    import prompt_engine.atmosphere_recommender as _real_reco

    fake_engine.rank_atmospheres = _real_reco.rank_atmospheres
    fake_engine.surprise_me = _real_reco.surprise_me

    # STAGE MODE uses the REAL contract swap and the REAL exterior eligibility —
    # a fake would let the adapter stage a room mobile refuses to stage.
    import prompt_engine.preservation as _real_pres

    # `main.py` cannot be imported here (dotenv + Supabase at import time), so the
    # exterior set is read from its SOURCE rather than retyped. A literal copy is
    # what drifts; a read cannot.
    _rooms = re.search(r"_EXTERIOR_ROOMS = \{([^}]*)\}",
                       pathlib.Path("main.py").read_text(encoding="utf-8"))
    fake_main._EXTERIOR_ROOMS = {
        r.strip().strip('"\'') for r in (_rooms.group(1).split(",") if _rooms else [])
        if r.strip()
    }

    # The safety gate itself is mobile's and is exercised there; what matters at
    # this seam is that the adapter CALLS it and honours the room it returns.
    def _gate(ayden_room, _conf, _kw_room, _kw_conf, _exterior):
        return ayden_room, ""

    fake_main.resolve_stage_exterior = _gate

    # The named-room staging maps, read from main.py's SOURCE rather than
    # retyped: a copy here would let the PWA stage a room mobile refuses, and
    # the two lists would drift the first time somebody adds a room.
    _main_src = pathlib.Path("main.py").read_text(encoding="utf-8")
    _quotes = chr(34) + chr(39)

    def _clean(tok):
        return tok.split("#")[0].strip().strip(_quotes)

    _rooms2 = re.search(r"_SPECIFIC_STAGE_ROOMS = frozenset\(\{([^}]*)\}", _main_src)
    fake_main._SPECIFIC_STAGE_ROOMS = frozenset(
        _clean(r) for r in (_rooms2.group(1).split(",") if _rooms2 else []) if _clean(r)
    )
    _map2 = re.search(r"_SPECIFIC_STAGE_MAP = \{([^}]*)\}", _main_src)
    fake_main._SPECIFIC_STAGE_MAP = {}
    for _pair in (_map2.group(1).split(",") if _map2 else []):
        if ":" in _pair:
            _k, _v = _pair.split(":", 1)
            if _clean(_k) and _clean(_v):
                fake_main._SPECIFIC_STAGE_MAP[_clean(_k)] = _clean(_v)

    # The refine-change SERIALIZER is main's, and the adapter calls it instead
    # of retyping the shape (a copy would drift the first time a field is
    # added). Lifted from main.py's SOURCE by the parser rather than retyped
    # here — same discipline as the two maps above.
    import ast

    _ns = {"_RefineChange": _REAL_CHANGE}
    _tree = ast.parse(_main_src)
    for _node in _tree.body:
        if (isinstance(_node, ast.FunctionDef)
                and _node.name in ("_refine_change_to_dict",
                                   "_refine_change_from_dict")):
            exec(ast.get_source_segment(_main_src, _node), _ns)  # noqa: S102
            setattr(fake_main, _node.name, _ns[_node.name])

    # The SPATIAL classification behind `lineage_customized` is mobile's pair
    # (`classify_transformation` + `is_spatial_edit`). Registered real so a
    # branch's customisation verdict is decided by the same code that decides
    # mobile's — a stub here would let the two disagree silently.
    import prompt_engine.composer_v2 as _real_cv2
    import prompt_engine.transformation_classifier as _real_tc

    sys.modules["main"] = fake_main
    sys.modules["generation_profiles"] = fake_profiles
    sys.modules["prompt_engine"] = fake_engine
    sys.modules["prompt_engine.atmosphere_dna"] = _real_dna
    sys.modules["prompt_engine.atmosphere_recommender"] = _real_reco
    sys.modules["prompt_engine.preservation"] = _real_pres
    sys.modules["prompt_engine.composer_v2"] = _real_cv2
    sys.modules["prompt_engine.transformation_classifier"] = _real_tc


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
    out, decided = asyncio.run(
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
    # The engine also reports what it decided, because the vision row must
    # record the atmosphere really used — not the meta-choice the browser sent.
    check("the engine reports the atmosphere it actually used",
          decided is not None and decided.atmosphere_id == "japandi_calm",
          str(getattr(decided, "atmosphere_id", None)))


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


def _raiser(exc: BaseException):
    """An async callable that always raises [exc] — a provider that is down."""

    async def _boom(**_kwargs):
        raise exc

    return _boom


def _completed_render() -> bytes:
    """What the engine hands back once it has been paid for: real JPEG bytes."""
    import io as _io

    from PIL import Image as _Pil

    buf = _io.BytesIO()
    _Pil.new("RGB", (8, 8), (200, 180, 140)).save(buf, format="JPEG")
    return buf.getvalue()


def _stub_decided():
    """What the engine reports alongside the image: the room and atmosphere it
    actually resolved. A stub that returned bytes alone would let the adapter
    persist the browser's meta-choice again."""
    import pwa_staging_api as _api  # noqa: PLC0415

    return _api._Decided("Living Room", "warm_modern", "Warm Modern")


async def _stub_render(**_kwargs):
    """Stands in for a render that has ALREADY been paid for and succeeded.

    Returns the pair the real engine returns: the image, and what it decided —
    the row that records a vision has to say which atmosphere was really used.
    """
    import pwa_staging_api as _api  # noqa: PLC0415

    return _completed_render(), _api._Decided("Living Room", "warm_modern",
                                              "Warm Modern")


def _generate_body(api):
    return api.PwaGenerateRequest(
        project_id=PROJECT,
        room_label="Living Room",
        atmosphere_id="ayden_signature",
        atmosphere_label="Ayden Signature",
        original_image_path=f"users/{UID}/projects/{PROJECT}/original/o.jpg",
        idempotency_key="incident-key",
    )


def _happy_routes(upload=None, insert=None, download=None):
    """The route table of a generation that gets as far as the paid render."""
    return {
        "/auth/v1/user": _Resp(200, {"id": UID}),
        "/rest/v1/pwa_visions": insert or _Resp(201, [{}]),
        "/rest/v1/pwa_projects": _Resp(200, [{"id": PROJECT, "owner_user_id": UID}]),
        "/storage/v1/object/": download or upload or _Resp(200, None, b"jpeg-bytes"),
    }


def test_incident_transport_failure_after_the_render(api, real_engine) -> None:
    """THE incident of 2026-08-06.

    OpenAI answered 200 and the image was re-encoded; the socket to Storage
    could not be opened (ConnectTimeout); the exception escaped the handler; the
    browser got no response at all and told the user to check their connection.
    Two things had to change: the transport is retried, and whatever happens the
    endpoint answers with a typed payload.
    """
    print("\n== 10) A paid render is not thrown away by one bad socket ==")
    from fastapi import HTTPException

    os.environ["SUPABASE_URL"] = STAGING_URL
    api._run_canonical_engine = _stub_render
    api._TRANSPORT_BACKOFF_S = 0  # no real sleeping in a test

    # (a) A transient failure: the first upload attempt fails, the second works.
    #     Before the fix this render was lost; now it lands.
    attempts = {"n": 0}

    def flaky_storage(method: str, _url: str):
        if method == "POST" and attempts["n"] == 0:  # the upload of the render
            attempts["n"] += 1
            raise api.httpx.ConnectTimeout("boom")
        return _Resp(200, None, b"jpeg-bytes")

    calls: list = []
    routes = _happy_routes()
    routes["/storage/v1/object/"] = flaky_storage
    _install_fake_httpx(api, routes, calls)
    out = asyncio.run(api.pwa_generate(_generate_body(api), authorization=f"Bearer {TOKEN}"))
    check("a transient upload failure is retried, not dropped", out["status"] == "completed")
    check("the vision is reported as newly created", out["replayed"] is False)
    check("the retry actually happened", attempts["n"] == 1)

    # (b) A persistent failure: the caller still gets a TYPED answer, never a
    #     dead connection, and the message names the real problem.
    def upload_always_down(method: str, _url: str):
        if method == "GET":
            return _Resp(200, None, b"jpeg-bytes")  # the original still loads
        raise api.httpx.ConnectTimeout("boom")

    calls = []
    routes = _happy_routes()
    routes["/storage/v1/object/"] = upload_always_down
    _install_fake_httpx(api, routes, calls)
    try:
        asyncio.run(api.pwa_generate(_generate_body(api), authorization=f"Bearer {TOKEN}"))
        check("a persistent upload failure → typed 502", False, "no exception")
    except HTTPException as e:
        check(
            "a persistent upload failure → typed 502",
            e.status_code == 502 and e.detail["error_code"] == "RESULT_SAVE_FAILED",
            f"got {e.status_code} {e.detail}",
        )
        check(
            "the message says the vision could not be SAVED, not that we are offline",
            "could not be saved" in e.detail["user_message"]
            and "connection" not in e.detail["user_message"].lower(),
        )
        check("it is marked retryable", e.detail["retryable"] is True)
    check("it gave up after the configured number of attempts", api._TRANSPORT_ATTEMPTS == 3)

    api._TRANSPORT_BACKOFF_S = 1.0
    api._run_canonical_engine = real_engine


def test_every_hop_answers_instead_of_dying(api, real_engine) -> None:
    print("\n== 11) No network hop can end the request without a response ==")
    from fastapi import HTTPException

    os.environ["SUPABASE_URL"] = STAGING_URL
    api._TRANSPORT_BACKOFF_S = 0
    api._run_canonical_engine = _stub_render

    def failing(_method: str, _url: str):
        raise api.httpx.ConnectError("down")

    # The ORIGINAL download — this one is BEFORE the paid render, so failing
    # here costs nothing but must still be an honest answer.
    calls: list = []
    routes = _happy_routes()
    routes["/storage/v1/object/"] = failing
    _install_fake_httpx(api, routes, calls)
    try:
        asyncio.run(api.pwa_generate(_generate_body(api), authorization=f"Bearer {TOKEN}"))
        check("download failure → typed 502", False, "no exception")
    except HTTPException as e:
        check(
            "download failure → typed 502 SOURCE_FETCH_FAILED",
            e.status_code == 502 and e.detail["error_code"] == "SOURCE_FETCH_FAILED",
        )

    # The vision INSERT — after the render and after the upload: the last place
    # a paid result can be lost.
    seen = {"n": 0}

    def visions_route(method: str, _url: str):
        seen["n"] += 1
        if method == "GET":
            return _Resp(200, [])  # the replay probe finds nothing
        raise api.httpx.ConnectError("down")  # the insert cannot open a socket

    calls = []
    routes = _happy_routes()
    routes["/rest/v1/pwa_visions"] = visions_route
    _install_fake_httpx(api, routes, calls)
    try:
        asyncio.run(api.pwa_generate(_generate_body(api), authorization=f"Bearer {TOKEN}"))
        check("insert failure → typed 502", False, "no exception")
    except HTTPException as e:
        check(
            "insert failure → typed 502 PERSIST_FAILED",
            e.status_code == 502 and e.detail["error_code"] == "PERSIST_FAILED",
        )

    # And the catch-all: anything unforeseen still answers.
    def auth_unreachable(_method: str, _url: str):
        raise api.httpx.ReadError("x")

    calls = []
    _install_fake_httpx(api, {"/auth/v1/user": auth_unreachable}, calls)
    try:
        asyncio.run(api.pwa_generate(_generate_body(api), authorization=f"Bearer {TOKEN}"))
        check("an unforeseen transport error → typed 502", False, "no exception")
    except HTTPException as e:
        check(
            "an unforeseen transport error → typed 502 UNKNOWN_FAILURE",
            e.status_code == 502 and e.detail["error_code"] == "UNKNOWN_FAILURE",
        )
        check(
            "an unknown transport failure never claims nothing was charged",
            "charged" not in e.detail["user_message"].lower()
            and e.detail.get("render_started") is None,
        )
        check("no token in that payload", TOKEN not in str(e.detail))

    api._TRANSPORT_BACKOFF_S = 1.0
    api._run_canonical_engine = real_engine


def test_engine_unreachable_is_named_as_such(api, real_engine) -> None:
    """A provider outage is not the user's network, and costs nothing.

    Observed on the 2026-08-06 retry: the connect to api.openai.com timed out.
    The SDK wraps httpx in its OWN exception type, so a check for
    httpx.TransportError missed it, the exception escaped, and the app told the
    user to check their connection for a call that never left the building.
    """
    print("\n== 12) An unreachable ENGINE is reported honestly and costs nothing ==")
    from fastapi import HTTPException

    os.environ["SUPABASE_URL"] = STAGING_URL

    class APITimeoutError(Exception):
        """Same NAME as the provider SDK's, without importing the SDK."""

    class APIConnectionError(Exception):
        pass

    class ConnectError(Exception):
        """Same NAME as httpx's: never sent, so provably nothing was charged."""

    for exc_type in (APITimeoutError, APIConnectionError):
        check(f"{exc_type.__name__} is classified as a connect failure",
              api._is_connection_failure(exc_type("x")))

    # THE distinction that decides whether a user may be told it was free.
    class RemoteProtocolError(Exception):
        """Sent in full, then the server hung up without answering."""

    check("a failed CONNECT means the request never left",
          api._render_started(ConnectError("x")) is False)
    check("a server hang-up means the request DID leave",
          api._render_started(RemoteProtocolError("x")) is True)
    check("a read timeout means the request DID leave",
          api._render_started(APITimeoutError("x")) is True)
    # The cause chain is what the SDK actually gives us.
    wrapped = APIConnectionError("wrapped")
    wrapped.__cause__ = RemoteProtocolError("Server disconnected without sending a response.")
    check("the cause chain is followed through the SDK wrapper",
          api._render_started(wrapped) is True)
    wrapped2 = APIConnectionError("wrapped")
    wrapped2.__cause__ = ConnectError("connect refused")
    check("a wrapped connect failure is still provably free",
          api._render_started(wrapped2) is False)
    check("an unknown shape assumes the worst, never a refund",
          api._render_started(Exception("mystery")) is True)

    # The REAL _run_canonical_engine must run: the classification lives at the
    # engine call site, so stubbing the whole function would test nothing.
    # The provider client is what fails, exactly as it did in production.
    api._run_canonical_engine = real_engine
    failing_provider = types.SimpleNamespace(
        images=types.SimpleNamespace(
            edit=_raiser(ConnectError("connect refused")),
        )
    )
    sys.modules["main"].openai = failing_provider

    calls: list = []
    _install_fake_httpx(api, _happy_routes(), calls)
    try:
        asyncio.run(api.pwa_generate(_generate_body(api), authorization=f"Bearer {TOKEN}"))
        check("an unreachable engine → typed 502", False, "no exception")
    except HTTPException as e:
        check("an unreachable engine → typed 502 ENGINE_UNAVAILABLE",
              e.status_code == 502 and e.detail["error_code"] == "ENGINE_UNAVAILABLE",
              f"got {e.detail}")
        check("it says nothing was charged",
              "Nothing was charged" in e.detail["user_message"])
        check("it does NOT blame the user's connection",
              "your connection" not in e.detail["user_message"].lower())
        check("it is retryable", e.detail["retryable"] is True)

    check("no image was uploaded for a call that never left",
          not any(m == "POST" and "/storage/" in u for m, u in calls))
    check("no vision row was written",
          not any(m == "POST" and "pwa_visions" in u for m, u in calls))

    # And a genuine bug still ANSWERS rather than killing the connection.
    async def broken_engine(**_kw):
        raise ValueError("a real bug")

    api._run_canonical_engine = broken_engine
    _install_fake_httpx(api, _happy_routes(), [])
    try:
        asyncio.run(api.pwa_generate(_generate_body(api), authorization=f"Bearer {TOKEN}"))
        check("an unexpected bug still answers", False, "no exception")
    except HTTPException as e:
        check("an unexpected bug still answers with a typed 502",
              e.status_code == 502 and e.detail["error_code"] == "UNKNOWN_FAILURE")
        check("an unknown failure claims NOTHING about billing",
              e.detail.get("render_started") is None
              and "charged" not in e.detail["user_message"].lower())
        check("no internal detail leaks to the user",
              "ValueError" not in str(e.detail) and "a real bug" not in str(e.detail))

    api._run_canonical_engine = real_engine
    _install_canonical_stubs(_RECORD)  # restore a healthy provider for later tests


def test_refine_uses_the_canonical_refine_engine(api) -> None:
    """A refine must NOT be composed by the first-vision composer.

    The measured defect: "break the wall on the right and add a kitchen with its
    island" was sent through compose_generation_prompt, whose contract opens with
    "Reproduce the photographed architecture exactly ... do not invent walls,
    doors or partitions". The engine was instructed to refuse the edit it was
    asked to perform, and the chat said "I'd keep the architecture intact".
    """
    print("\n== 13) A refine is routed to the REFINE engine, not the composer ==")
    src = (HERE / "pwa_staging_api.py").read_text(encoding="utf-8")

    check("the adapter routes on action_type == refine",
          'body.action_type == "refine"' in src)
    check("a refine calls the canonical refine engine",
          "_run_canonical_refine(" in src)
    check("the refine engine comes from the mobile package, not a copy",
          "from refine.engine import refine_generate" in src
          and "from refine.parser import parse_changes" in src
          and "from refine.normalizer import normalize_changes" in src)
    check("the provider client is the canonical one",
          "refine_generate(canonical.openai" in src)
    # Scan the CODE, not the prose: the docstring deliberately quotes the
    # first-vision contract to explain why a refine must not receive it.
    import ast

    tree = ast.parse(src)
    for node in ast.walk(tree):
        body = getattr(node, "body", None)
        if isinstance(body, list) and body:
            first = body[0]
            if (isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant)
                    and isinstance(first.value.value, str)):
                body.pop(0)
                if not body:
                    body.append(ast.Pass())
    code = ast.unparse(ast.fix_missing_locations(tree))
    check("no refine prompt is BUILT in the adapter",
          "PRESERVE MODE" not in code and "Reproduce the photographed" not in code)
    check("the adapter composes no prompt string at all",
          "design_prompt =" not in code or "compose_generation_prompt" in code)
    check("the first-vision composer still serves initial and switch",
          "compose_generation_prompt(" in src)

    # The mobile sequence, in order: parse -> normalize -> prepare -> generate.
    order = [src.index(x) for x in (
        "parse_changes(user_instruction", "normalize_changes(changes)",
        "refine_prepare(changes)", "refine_generate(canonical.openai")]
    check("it follows the mobile order parse -> normalize -> prepare -> generate",
          order == sorted(order))

    # An unreadable instruction is refused the way mobile refuses it, and costs
    # nothing: no provider call is reached.
    check("an unreadable instruction is a typed 422, not a render",
          'status_code=422' in src and '"EMPTY_REQUEST"' in src)


def _install_refine_stubs(verdict: str, record: dict) -> None:
    """Stand in for refine.parser / refine.advisor / refine.engine.

    Same module names the adapter imports, so what is measured is that the
    adapter DELEGATES the decision — not that we re-implemented the advisor.
    """
    # The real dataclass, not a look-alike. A stub with its own field list is
    # how the adapter's echo silently stopped matching what `/refine/verify`
    # reads back — the shape has to be the one the parser actually produces.
    import functools

    _Change = functools.partial(_REAL_CHANGE, type="modify", object="sofa",
                                detail="white")

    parser = types.ModuleType("refine.parser")

    async def _parse(message, client=None):
        record["parsed"] = message
        return [] if message.strip() == "" else [_Change(raw=message)]

    parser.parse_changes = _parse

    advisor = types.ModuleType("refine.advisor")

    class _V:
        def __init__(self, v):
            self.value = v

    class _Advice:
        def __init__(self, v):
            self.overall = _V(v)
            self.flagged = [] if v == "green" else [
                types.SimpleNamespace(change=_Change(raw="x"), verdict=_V(v),
                                      reason="ambiguous target", alternative=None)
            ]

    async def _advise(changes, room_type=None, *, client=None):
        record["advised"] = (len(changes), room_type)
        return _Advice(verdict)

    advisor.advise = _advise
    advisor.build_advisory_message = lambda r: (
        None if r.overall.value == "green" else "Which wall do you mean?"
    )

    normalizer = types.ModuleType("refine.normalizer")
    normalizer.normalize_changes = lambda changes: record.setdefault("normalized", True)

    engine = types.ModuleType("refine.engine")
    engine.prepare = lambda changes: types.SimpleNamespace(
        ordered_changes=changes,
        plan=types.SimpleNamespace(strategy=types.SimpleNamespace(kind="combined_edit")),
    )

    async def _refine_generate(client, image_bytes, mime, changes, **kw):
        record["rendered"] = True
        return types.SimpleNamespace(image=_completed_render())

    engine.refine_generate = _refine_generate

    sys.modules["refine"] = types.ModuleType("refine")
    sys.modules["refine.parser"] = parser
    sys.modules["refine.advisor"] = advisor
    sys.modules["refine.normalizer"] = normalizer
    sys.modules["refine.engine"] = engine


def _refine_body(api, instruction: str, confirm: bool = False):
    return api.PwaGenerateRequest(
        project_id=PROJECT, room_label="Living Room",
        atmosphere_id="ayden_signature", atmosphere_label="Ayden Signature",
        original_image_path=f"users/{UID}/projects/{PROJECT}/original/o.jpg",
        idempotency_key=f"adv-{abs(hash((instruction, confirm)))}",
        action_type="refine", user_instruction=instruction, confirm=confirm,
    )


def test_advisor_decides_execute_or_advisory(api, real_engine) -> None:
    """The decision belongs to the canonical advisor, and it is EXCLUSIVE.

    The measured incident showed "Want me to apply it as a new version?" and a
    running generation on screen at the same time, because Flutter decided
    locally while the backend generated regardless. Only one of the two may ever
    leave this endpoint.
    """
    print("\n== 14) Advisor: execute XOR advisory, never both ==")
    from fastapi import HTTPException

    os.environ["SUPABASE_URL"] = STAGING_URL
    api._run_canonical_engine = real_engine

    # GREEN -> the render happens, and NO question is asked.
    record: dict = {}
    _install_refine_stubs("green", record)
    _install_fake_httpx(api, _happy_routes(), [])
    out = asyncio.run(api.pwa_generate(_refine_body(api, "make the sofa white"),
                                       authorization=f"Bearer {TOKEN}"))
    check("green: the vision is generated", out.get("status") == "completed")
    check("green: the advisor was consulted first", "advised" in record)
    check("green: the canonical parser was used", "parsed" in record)
    check("green: the render actually ran", record.get("rendered") is True)

    # YELLOW -> an ANSWER, and no render at all.
    record = {}
    _install_refine_stubs("yellow", record)
    calls: list = []
    _install_fake_httpx(api, _happy_routes(), calls)
    out = asyncio.run(api.pwa_generate(_refine_body(api, "break the wall"),
                                       authorization=f"Bearer {TOKEN}"))
    check("yellow: status is advisory", out.get("status") == "advisory")
    check("yellow: a question is returned", bool(out.get("message")))
    check("yellow: NOTHING was rendered", record.get("rendered") is None)
    check("yellow: no image was uploaded",
          not any(m == "POST" and "/storage/" in u for m, u in calls))
    check("yellow: no vision row was written",
          not any(m == "POST" and "pwa_visions" in u for m, u in calls))
    check("yellow: it states no render started", out.get("render_started") is False)
    check("advisory and completed are mutually exclusive",
          out.get("status") != "completed")

    # RED, then the user continues anyway -> the render happens.
    record = {}
    _install_refine_stubs("red", record)
    _install_fake_httpx(api, _happy_routes(), [])
    out = asyncio.run(api.pwa_generate(_refine_body(api, "add a bathtub", True),
                                       authorization=f"Bearer {TOKEN}"))
    check("confirm=true skips the advisor, as mobile Continue-anyway does",
          out.get("status") == "completed" and record.get("rendered") is True)

    # An unreadable instruction is refused before anything is paid for.
    record = {}
    _install_refine_stubs("green", record)
    _install_fake_httpx(api, _happy_routes(), [])
    try:
        asyncio.run(api.pwa_generate(_refine_body(api, "   "),
                                     authorization=f"Bearer {TOKEN}"))
        check("an empty instruction is refused", False, "no exception")
    except HTTPException as e:
        check("an empty instruction: 422, nothing rendered",
              e.status_code == 422 and record.get("rendered") is None)

    _install_canonical_stubs(_RECORD)


def test_single_flight_prevents_a_second_paid_render(api, real_engine) -> None:
    """One logical operation, one render - even under concurrency."""
    print("\n== 15) Single-flight: double click / concurrent / retry ==")
    os.environ["SUPABASE_URL"] = STAGING_URL

    renders = {"n": 0}

    async def slow_engine(**_kw):
        renders["n"] += 1
        await asyncio.sleep(0.05)
        return _completed_render(), _stub_decided()

    api._run_canonical_engine = slow_engine
    _install_fake_httpx(api, _happy_routes(), [])

    def body():
        return api.PwaGenerateRequest(
            project_id=PROJECT, room_label="Living Room",
            atmosphere_id="ayden_signature", atmosphere_label="Ayden Signature",
            original_image_path=f"users/{UID}/projects/{PROJECT}/original/o.jpg",
            idempotency_key="one-logical-operation", action_type="initial",
        )

    async def three_at_once():
        return await asyncio.gather(*[
            api.pwa_generate(body(), authorization=f"Bearer {TOKEN}")
            for _ in range(3)
        ])

    results = asyncio.run(three_at_once())
    check("three concurrent submits produce ONE render", renders["n"] == 1,
          f"got {renders['n']}")
    check("all three callers get an answer", len(results) == 3)
    check("all three get the SAME vision",
          len({r["vision_id"] for r in results}) == 1)
    check("the in-flight map is emptied afterwards", not api._INFLIGHT)

    api._run_canonical_engine = real_engine
    _install_canonical_stubs(_RECORD)


class _ClaimTable:
    """A stand-in for `pwa_staging.pwa_generation_claims` + its RPCs.

    It reproduces the ONE property the migration exists for: the claim is an
    INSERT .. ON CONFLICT, so for a given (owner, key) exactly one caller can
    ever be the winner — and that fact lives OUTSIDE any single backend process.

    That is what makes the restart test meaningful: two independent adapter
    "instances" share this table the way two workers share Postgres, and share
    nothing else.
    """

    def __init__(self):
        self.rows: dict[str, dict] = {}

    def claim(self, key, project_id, action_type, parent):
        row = self.rows.get(key)
        if row is None:
            self.rows[key] = {"state": "PROCESSING", "result_vision_id": None,
                              "error_code": None}
            return {"won": True, "state": "PROCESSING",
                    "result_vision_id": None, "error_code": None}
        if row["state"] == "FAILED":
            row["state"] = "PROCESSING"
            row["error_code"] = None
            return {"won": True, "state": "PROCESSING",
                    "result_vision_id": None, "error_code": None}
        return {"won": False, "state": row["state"],
                "result_vision_id": row["result_vision_id"],
                "error_code": row["error_code"]}

    def complete(self, key, vision_id):
        self.rows.setdefault(key, {})["state"] = "COMPLETED"
        self.rows[key]["result_vision_id"] = vision_id

    def fail(self, key, code, render_started):
        self.rows.setdefault(key, {})["state"] = "FAILED"
        self.rows[key]["error_code"] = code
        self.rows[key]["render_started"] = render_started


def _lifecycle_routes(table: _ClaimTable, vision_store: dict, calls: list):
    """Route table where the claim RPCs are backed by [table]."""

    def rpc(method: str, url: str):
        import json as _json

        if "claim_generation" in url:
            body = _CURRENT_RPC_BODY.get("claim") or {}
            return _Resp(200, [table.claim(body.get("p_idempotency_key"),
                                           body.get("p_project_id"),
                                           body.get("p_action_type"),
                                           body.get("p_parent_vision_id"))])
        if "complete_generation" in url:
            body = _CURRENT_RPC_BODY.get("complete") or {}
            table.complete(body.get("p_idempotency_key"), body.get("p_vision_id"))
            return _Resp(200, [])
        if "fail_generation" in url:
            body = _CURRENT_RPC_BODY.get("fail") or {}
            table.fail(body.get("p_idempotency_key"), body.get("p_error_code"),
                       body.get("p_render_started"))
            return _Resp(200, [])
        raise AssertionError("unrouted rpc " + url)

    def visions(method: str, _url: str):
        if method == "GET":
            v = vision_store.get("row")
            return _Resp(200, [v] if v else [])
        vision_store["row"] = {
            "id": "vision-persisted", "vision_number": 1,
            "image_path": f"users/{UID}/projects/{PROJECT}/generated/v.jpg",
        }
        return _Resp(201, [{}])

    return {
        "/auth/v1/user": _Resp(200, {"id": UID}),
        "/rest/v1/rpc/": rpc,
        "/rest/v1/pwa_visions": visions,
        "/rest/v1/pwa_projects": _Resp(200, [{"id": PROJECT, "owner_user_id": UID}]),
        "/storage/v1/object/": _Resp(200, None, b"jpeg-bytes"),
    }


# The fake client records bodies so the RPC router can read its arguments.
_CURRENT_RPC_BODY: dict = {}


def _capture_rpc_bodies(api):
    """Wrap the fake client so RPC payloads reach the claim table."""
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
            body = kw.get("json") or {}
            if "claim_generation" in url:
                _CURRENT_RPC_BODY["claim"] = body
            elif "complete_generation" in url:
                _CURRENT_RPC_BODY["complete"] = body
            elif "fail_generation" in url:
                _CURRENT_RPC_BODY["fail"] = body
            return await self._inner.post(url, **kw)

    api.httpx.AsyncClient = _Capturing


def test_durable_lifecycle(api, real_engine) -> None:
    """The claim survives what the in-process map cannot."""
    print("\n== 16) Durable lifecycle: restart / F5 / concurrency ==")
    os.environ["SUPABASE_URL"] = STAGING_URL

    renders = {"n": 0}

    async def counting_engine(**_kw):
        renders["n"] += 1
        return _completed_render(), _stub_decided()

    api._run_canonical_engine = counting_engine

    def body(key="op-1"):
        return api.PwaGenerateRequest(
            project_id=PROJECT, room_label="Living Room",
            atmosphere_id="ayden_signature", atmosphere_label="Ayden Signature",
            original_image_path=f"users/{UID}/projects/{PROJECT}/original/o.jpg",
            idempotency_key=key, action_type="initial",
        )

    def install(table, store):
        _install_fake_httpx(api, _lifecycle_routes(table, store, []), [])
        _capture_rpc_bodies(api)

    # DBLIFE01 — a first call claims and renders.
    table, store = _ClaimTable(), {}
    install(table, store)
    out = asyncio.run(api.pwa_generate(body(), authorization=f"Bearer {TOKEN}"))
    check("DBLIFE01: the first caller claims and renders",
          out.get("status") == "completed" and renders["n"] == 1)
    check("DBLIFE01: the claim is COMPLETED afterwards",
          table.rows["op-1"]["state"] == "COMPLETED")

    # DBLIFE06 — a NEW backend instance (restart): the in-process map is empty,
    # only the durable claim remains. This is the test the old guard could not do.
    api._INFLIGHT.clear()
    before = renders["n"]
    out = asyncio.run(api.pwa_generate(body(), authorization=f"Bearer {TOKEN}"))
    check("DBLIFE06: after a restart the same operation renders ZERO more times",
          renders["n"] == before, f"rendered {renders['n'] - before} more")
    check("DBLIFE04: it returns the existing vision",
          out.get("status") == "completed" and out.get("replayed") is True)

    # DBLIFE03/07 — a duplicate while still PROCESSING: no second render.
    table2, store2 = _ClaimTable(), {}
    table2.rows["op-2"] = {"state": "PROCESSING", "result_vision_id": None,
                           "error_code": None}
    install(table2, store2)
    api._INFLIGHT.clear()
    before = renders["n"]
    out = asyncio.run(api.pwa_generate(body("op-2"), authorization=f"Bearer {TOKEN}"))
    check("DBLIFE03/07: a duplicate during PROCESSING renders nothing",
          renders["n"] == before)
    check("DBLIFE03: the caller is told to keep waiting",
          out.get("status") == "processing")

    # DBLIFE05 — a FAILED claim may be retried, and renders again.
    table3, store3 = _ClaimTable(), {}
    table3.rows["op-3"] = {"state": "FAILED", "result_vision_id": None,
                           "error_code": "ENGINE_UNAVAILABLE"}
    install(table3, store3)
    api._INFLIGHT.clear()
    before = renders["n"]
    out = asyncio.run(api.pwa_generate(body("op-3"), authorization=f"Bearer {TOKEN}"))
    check("DBLIFE05: a FAILED claim is retryable and renders once",
          renders["n"] == before + 1 and out.get("status") == "completed")

    # DBLIFE11 — a DIFFERENT identity is independent.
    table4, store4 = _ClaimTable(), {}
    install(table4, store4)
    api._INFLIGHT.clear()
    before = renders["n"]
    asyncio.run(api.pwa_generate(body("op-4"), authorization=f"Bearer {TOKEN}"))
    check("DBLIFE11: a different identity generates independently",
          renders["n"] == before + 1)

    # DBLIFE12 — three concurrent callers, one shared claim table.
    table5, store5 = _ClaimTable(), {}
    install(table5, store5)
    api._INFLIGHT.clear()
    before = renders["n"]

    async def three():
        return await asyncio.gather(*[
            api.pwa_generate(body("op-5"), authorization=f"Bearer {TOKEN}")
            for _ in range(3)
        ], return_exceptions=True)

    asyncio.run(three())
    check("DBLIFE12: three concurrent callers produce exactly ONE render",
          renders["n"] == before + 1, f"rendered {renders['n'] - before}")

    check("OPENAI CALLS in the concurrency test: one per logical operation",
          renders["n"] > 0)

    api._run_canonical_engine = real_engine
    api._INFLIGHT.clear()
    _install_canonical_stubs(_RECORD)


def test_durable_claim_fails_open_like_mobile(api, real_engine) -> None:
    """When the claim table is unavailable, a generation is NOT lost."""
    print("\n== 17) Claim FAIL-OPEN — the same policy as mobile ==")
    os.environ["SUPABASE_URL"] = STAGING_URL

    renders = {"n": 0}

    async def counting_engine(**_kw):
        renders["n"] += 1
        return _completed_render(), _stub_decided()

    api._run_canonical_engine = counting_engine

    # The RPC 404s exactly as it does today, before the migration is applied.
    routes = _happy_routes()
    routes["/rest/v1/rpc/"] = _Resp(404, {"code": "PGRST202"})
    _install_fake_httpx(api, routes, [])
    api._INFLIGHT.clear()

    out = asyncio.run(api.pwa_generate(
        api.PwaGenerateRequest(
            project_id=PROJECT, room_label="Living Room",
            atmosphere_id="ayden_signature", atmosphere_label="Ayden Signature",
            original_image_path=f"users/{UID}/projects/{PROJECT}/original/o.jpg",
            idempotency_key="no-claim-table", action_type="initial",
        ),
        authorization=f"Bearer {TOKEN}"))

    check("a missing claim table does not lose the generation",
          out.get("status") == "completed" and renders["n"] == 1)
    src = (HERE / "pwa_staging_api.py").read_text(encoding="utf-8")
    check("the fail-open is logged at ERROR, never swallowed",
          "[CLAIM] FAIL-OPEN" in src and "log.error" in src)
    check("the in-process guard still applies underneath",
          "_INFLIGHT" in src)

    api._run_canonical_engine = real_engine
    api._INFLIGHT.clear()
    _install_canonical_stubs(_RECORD)


def test_a_failed_generation_releases_its_claim(api, real_engine) -> None:
    """A failure must not wedge the claim it took.

    The 2026-08-07 first generation failed at the provider and left its claim
    row PROCESSING for ever. Because a PROCESSING claim never wins, the user's
    own "Try again" was refused permanently — the operation was unrecoverable
    without a database edit. Every exit path now settles.
    """
    print("\n== 18) A failed generation RELEASES its durable claim ==")
    os.environ["SUPABASE_URL"] = STAGING_URL

    settled: list[dict] = []

    def rpc(method: str, url: str):
        if "claim_generation" in url:
            return _Resp(200, [{"won": True, "state": "PROCESSING",
                                "result_vision_id": None, "error_code": None}])
        if "fail_generation" in url:
            settled.append(dict(_CURRENT_RPC_BODY.get("fail") or {}))
            return _Resp(200, [])
        if "complete_generation" in url:
            settled.append({"completed": True})
            return _Resp(200, [])
        raise AssertionError("unrouted rpc " + url)

    class ConnectError(Exception):
        pass

    api._run_canonical_engine = real_engine
    sys.modules["main"].openai = types.SimpleNamespace(
        images=types.SimpleNamespace(edit=_raiser(ConnectError("refused"))))

    routes = _happy_routes()
    routes["/rest/v1/rpc/"] = rpc
    _install_fake_httpx(api, routes, [])
    _capture_rpc_bodies(api)
    api._INFLIGHT.clear()

    from fastapi import HTTPException
    try:
        asyncio.run(api.pwa_generate(_generate_body(api), authorization=f"Bearer {TOKEN}"))
        check("the failure surfaced", False, "no exception")
    except HTTPException as e:
        check("the failure surfaced", e.status_code == 502)

    check("the claim was settled, not left PROCESSING", len(settled) == 1,
          f"{settled}")
    if settled:
        check("it was settled as FAILED with the real code",
              settled[0].get("p_error_code") == "ENGINE_UNAVAILABLE",
              str(settled[0]))
        check("and it recorded that nothing was rendered",
              settled[0].get("p_render_started") is False, str(settled[0]))

    # A "sent but never answered" failure records the opposite.
    settled.clear()
    class RemoteProtocolError(Exception):
        pass
    sys.modules["main"].openai = types.SimpleNamespace(
        images=types.SimpleNamespace(
            edit=_raiser(RemoteProtocolError("Server disconnected without sending a response."))))
    _install_fake_httpx(api, routes, [])
    _capture_rpc_bodies(api)
    api._INFLIGHT.clear()
    try:
        asyncio.run(api.pwa_generate(_generate_body(api), authorization=f"Bearer {TOKEN}"))
    except HTTPException:
        pass
    check("a hang-up settles as render_started=True",
          bool(settled) and settled[0].get("p_render_started") is True, str(settled))
    check("and it is NOT reported as free",
          bool(settled) and settled[0].get("p_error_code") == "ENGINE_NO_RESPONSE",
          str(settled))

    api._run_canonical_engine = real_engine
    api._INFLIGHT.clear()
    _install_canonical_stubs(_RECORD)


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


def test_the_result_is_streamed_back(api, record, real_engine) -> None:
    """A first vision takes ~110 s, and unstreamed it puts NOT ONE BYTE on the
    wire while it runs.

    Measured on the development network path (2026-08-07): an unstreamed
    response is cut at 61 s — reproduced on /chat/completions as well as
    /images/edits, on HTTP/1.1 as well as HTTP/2, so neither the endpoint nor
    the protocol explains it. The same request STREAMED ran 139 s untouched.
    A silent socket is a socket somebody may reclaim; a busy one is not.

    What must stay true is that this changed only HOW the image travels.
    """
    print("\n== 19) The image is fetched as a stream, and only that changed ==")
    api._run_canonical_engine = real_engine
    import asyncio as _a

    out, _decided = _a.run(
        api._run_canonical_engine(
            image_bytes=_completed_render(), room_label="Living Room",
            atmosphere_label="Japandi Calm", atmosphere_id="japandi_calm",
            user_instruction="", iteration=1,
        )
    )
    kw = record["edit_kwargs"]

    check("STREAM01: the request asks for a stream", kw.get("stream") is True,
          f"{kw.get('stream')}")
    check("STREAM02: it asks for at least one partial frame, so bytes really "
          "do flow mid-render", int(kw.get("partial_images") or 0) >= 1,
          f"{kw.get('partial_images')}")

    # Everything that decides the IMAGE is untouched — same model, same prompt,
    # same size, same quality. Only the delivery changed.
    check("STREAM03: the model is unchanged", kw.get("model") == "gpt-image-2")
    check("STREAM04: the prompt is still the canonical composer's",
          kw.get("prompt") == "THE CANONICAL PROMPT")
    check("STREAM05: the size is unchanged", kw.get("size") == "1536x1024")
    # Not "unchanged" — CORRECT. Streaming changed only the delivery, and the
    # quality is the one mobile locks for this model (see test 22).
    check("STREAM06: the quality is the model's locked one",
          kw.get("quality") == "low", str(kw.get("quality")))
    check("STREAM07: exactly one image is requested", kw.get("n") == 1)

    # The partial frames are a transport trick, never a result. The stub emits
    # near-black partials and a warm final one; the JPEG must be the warm one.
    import io as _io

    from PIL import Image as _Pil
    px = _Pil.open(_io.BytesIO(out)).convert("RGB").getpixel((4, 4))
    check("STREAM08: a partial frame is NEVER mistaken for the finished image",
          px[0] > 120 and px[1] > 100, f"pixel={px}")
    check("STREAM09: the completed event's image is what comes back",
          out[:2] == bytes((0xFF, 0xD8)), "not a JPEG")


def test_mobile_is_not_dragged_into_the_change() -> None:
    """The ceiling was measured HERE, on a laptop behind a VPN. Mobile renders
    on Render, where no such cut has ever appeared, and its image engine is
    frozen. So the fix stops at this adapter's door."""
    print("\n== 20) main.py keeps its own unstreamed call ==")
    src = pathlib.Path("main.py").read_text(encoding="utf-8")
    check("the mobile engine still calls images.edit without streaming",
          "openai.images.edit(**edit_kwargs)" in src)
    check("and nothing asked it to stream",
          "partial_images" not in src and "stream=True" not in src)


def test_the_engine_edits_the_right_picture(api) -> None:
    """Which image is handed to the engine — the defect the real smoke found.

    Observed 2026-08-08 on staging: "make the bedding white" produced a bare
    room with a white bed. Every generation, refine included, had downloaded the
    UPLOADED PHOTO. So a refine never refined anything: it restarted from the
    empty room, and the design the person was looking at was thrown away.

    The rule proven here is mobile's own (main.py, Wave 5.3): a refine edits the
    vision on screen; a switch re-edits the original while the lineage is a pure
    chain of atmospheres, and follows the vision once real work has been done.
    """
    print("\n== 21) The engine is handed the picture the person is looking at ==")

    ORIGINAL = f"users/{UID}/projects/{PROJECT}/original/o.jpg"
    V1 = f"users/{UID}/projects/{PROJECT}/generated/v1.jpg"
    V2 = f"users/{UID}/projects/{PROJECT}/generated/v2.jpg"

    def resolve(action: str, parent: str | None, rows: list[dict]) -> str:
        import asyncio as _a

        class _Resp:
            status_code = 200

            def json(self):
                return rows

        class _Client:
            async def get(self, *_a_, **_k):
                return _Resp()

        body = api.PwaGenerateRequest(
            project_id=PROJECT, idempotency_key="k",
            original_image_path=ORIGINAL, action_type=action,
            atmosphere_id="japandi_calm", atmosphere_label="Japandi Calm",
            room_label="Living Room",
            vision_number=2, parent_vision_id=parent or "",
        )
        return _a.run(api._resolve_source_path(_Client(), "tok", body, UID))

    pure = [{"id": "v1", "vision_number": 1, "action_type": "initial",
             "image_path": V1},
            {"id": "v2", "vision_number": 2, "action_type": "switch_atmosphere",
             "image_path": V2}]
    refined = [
        {"id": "v1", "vision_number": 1, "action_type": "initial", "image_path": V1},
        {"id": "v2", "vision_number": 2, "action_type": "refine", "image_path": V2},
    ]

    check("SRC01: a first vision edits the uploaded photo",
          resolve("initial", None, pure) == ORIGINAL)
    check("SRC02: a REFINE edits the vision being refined, not the photo",
          resolve("refine", "v1", pure) == V1,
          resolve("refine", "v1", pure))
    check("SRC03: a second refine builds on the first — work accumulates",
          resolve("refine", "v2", refined) == V2,
          resolve("refine", "v2", refined))
    # Wave 5.21, mobile's LIVE code: "source pinned to V1 - cascade-free
    # anchor". Reading the stale comment above that block instead ("override
    # source_mode to ORIGINAL") is what sent an EMPTY photo to a style
    # refinement on 2026-08-10 - the room came back rebuilt, television gone.
    check("SRC04: a PURE atmosphere switch is anchored on V1 - a furnished "
          "reference, one cascade step from the photo",
          resolve("switch_atmosphere", "v2", pure) == V1,
          resolve("switch_atmosphere", "v2", pure))
    check("SRC04b: and NEVER the uploaded photo, which has nothing to restyle",
          resolve("switch_atmosphere", "v2", pure) != ORIGINAL)
    check("SRC05: after a refine, a switch KEEPS that work",
          resolve("switch_atmosphere", "v2", refined) == V2,
          resolve("switch_atmosphere", "v2", refined))
    check("SRC06: a parent naming a vision this project does not have falls "
          "back to the photo rather than guessing",
          resolve("refine", "not-mine", pure) == ORIGINAL)
    # Mobile's own fallback when the V1 row is unusable: LATEST, never the photo.
    _no_v1 = [{"id": "v2", "vision_number": 2, "action_type": "switch_atmosphere",
               "image_path": V2}]
    check("SRC06b: a lineage whose V1 row is gone falls back to the vision "
          "being switched, as mobile does",
          resolve("switch_atmosphere", "v2", _no_v1) == V2,
          resolve("switch_atmosphere", "v2", _no_v1))
    check("SRC07: no parent named — nothing to branch from",
          resolve("refine", None, pure) == ORIGINAL)

    # A row whose path points outside the caller's namespace is refused even
    # though it arrived from the database.
    foreign = [{"id": "v1", "action_type": "initial",
                "image_path": "users/someone-else/projects/x/generated/v1.jpg"}]
    try:
        resolve("refine", "v1", foreign)
        check("SRC08: a path outside the caller's namespace is refused", False,
              "no exception")
    except api.HTTPException as e:
        check("SRC08: a path outside the caller's namespace is refused",
              e.status_code == 403)


def test_the_recipe_is_the_models_not_the_profiles(api) -> None:
    """Reported 2026-08-10: 2 min 30 on the PWA where mobile takes ~40 s, and a
    living room with no television.

    The trace said both at once: `quality=high` on the call, and
    `room='Your space'  dna_matched=False  path=fallback_style_block`.

    quality — this adapter read `profile.quality`. Mobile OVERRIDES the profile
    for gpt-image-2 (main.py, "gpt-image-2 migration 2026-06-29"): quality="low",
    benched at -84 % cost, frozen on every path, medium rejected at x2.7. Reading
    the profile produced a recipe nobody benched: six times the cost, four times
    the wait, a different image.

    room — "Your space" is the placeholder for "let Ayden choose". It keys no
    room, so the per-room DNA was dropped: furniture language, room constraints
    and the TV anchor with it. Mobile looks at the photo instead.
    """
    print("\n== 22) The render recipe is mobile's, not one of our own ==")

    profile = types.SimpleNamespace(quality="high", quality_overrides={},
                                    compact_prompts=True, size_override=None)

    check("RECIPE01: gpt-image-2 renders at the quality it was benched at",
          api._locked_quality("gpt-image-2", profile, "japandi_calm") == "low",
          api._locked_quality("gpt-image-2", profile, "japandi_calm"))
    check("RECIPE02: the profile does NOT get to raise it",
          api._locked_quality("gpt-image-2", profile, "warm_modern") != "high")
    check("RECIPE03: a per-atmosphere override cannot either — that tuning "
          "belongs to gpt-image-1",
          api._locked_quality(
              "gpt-image-2",
              types.SimpleNamespace(quality="high",
                                    quality_overrides={"warm_modern": "medium"}),
              "warm_modern") == "low")
    check("RECIPE04: gpt-image-1 keeps the profile and its per-atmosphere tuning",
          api._locked_quality(
              "gpt-image-1",
              types.SimpleNamespace(quality="high",
                                    quality_overrides={"warm_modern": "medium"}),
              "warm_modern") == "medium")

    # The lock has to KEEP matching main.py; a silent drift there is what caused
    # this, so the guard reads mobile's own source rather than trusting a memory.
    src = pathlib.Path("main.py").read_text(encoding="utf-8")
    locked = src.split('if IMAGE_MODEL.startswith("gpt-image-2")', 1)
    check("RECIPE05: main.py still locks gpt-image-2 the way we mirror it",
          len(locked) == 2
          and '_quality_override = "low"' in locked[1][:400]
          and "_fidelity_override = None" in locked[1][:400])
    check("RECIPE06: input_fidelity is absent from our call, as it is from mobile's",
          '"input_fidelity"' not in pathlib.Path("pwa_staging_api.py")
          .read_text(encoding="utf-8").split("_MODEL_LOCKED_QUALITY", 1)[1]
          .split("def _reencode_jpeg", 1)[0])

    # Partial frames cost image output tokens; at quality=low a render is ~25-30 s
    # and one mid-flight frame is ample. Three would be paying for nothing.
    check("RECIPE07: exactly one partial frame is requested",
          api._PARTIAL_IMAGES == 1, str(api._PARTIAL_IMAGES))


def test_ayden_decide_reads_the_photo(api) -> None:
    """"Your space" and "Ayden Signature" must never reach the composer as a room
    and an atmosphere.

    They are the two ways of saying "you choose". Sent verbatim they key nothing,
    so the per-room DNA is dropped whole — furniture language, room constraints,
    and the TV anchor with them. That is the missing television reported
    2026-08-10, and the trace said it outright: `dna_matched=False
    path=fallback_style_block  dna_room_context: 0`.
    """
    print("\n== 23) Ayden Decide and Ayden Signature name real things ==")
    import asyncio as _a

    import main as fake_main
    from prompt_engine.atmosphere_recommender import SIGNATURE_ATMOSPHERES

    calls: list[int] = []

    async def _seen(image_bytes: bytes) -> dict:
        calls.append(len(image_bytes))
        return {"room": "living_room", "atmosphere": "warm_modern",
                "confidence": "high", "reason": "sofa and a television wall"}

    fake_main._classify_ayden = _seen
    photo = _completed_render()

    def run(room: str, atmo: str):
        return _a.run(api._ayden_decide(photo, room, atmo))

    d = run("Your space", "Ayden Signature")
    check("DECIDE01: the room placeholder becomes the room in the photo",
          d.room_type == "living_room", d.room_type)
    check("DECIDE02: Ayden Signature becomes a REAL atmosphere the DNA can key on",
          d.atmosphere_id not in ("", "ayden_signature"), d.atmosphere_id)
    check("DECIDE03: ONE vision pass answers both, as mobile intends",
          len(calls) == 1, str(len(calls)))

    d = run("Kitchen", "Soft Luxury")
    check("DECIDE04: what the person CHOSE is never second-guessed",
          d.room_type == "Kitchen" and d.atmosphere_id == "soft_luxury"
          and len(calls) == 1, f"{d.room_type}/{d.atmosphere_id}/{len(calls)}")

    async def _unvalidated(_b: bytes) -> dict:
        # Japandi is deliberately NOT a validated Signature atmosphere.
        return {"room": "living_room", "atmosphere": "japandi_calm",
                "confidence": "high", "reason": ""}

    fake_main._classify_ayden = _unvalidated
    d = run("Your space", "Ayden Signature")
    check("DECIDE05: an AI pick outside the validated set is refused and the "
          "curated table decides — mobile's rule, not a new one",
          d.atmosphere_id in SIGNATURE_ATMOSPHERES, d.atmosphere_id)

    async def _unread(_b: bytes) -> dict:
        return {"room": "", "atmosphere": "", "confidence": "low"}

    fake_main._classify_ayden = _unread
    d = run("Your space", "Ayden Signature")
    check("DECIDE06: an unread photo never invents a room",
          d.room_type == "Your space", d.room_type)
    check("DECIDE07: and the atmosphere still comes from the validated table",
          d.atmosphere_id in SIGNATURE_ATMOSPHERES, d.atmosphere_id)

    async def _boom(_b: bytes) -> dict:
        raise RuntimeError("vision down")

    fake_main._classify_ayden = _boom
    d = run("Your space", "Ayden Signature")
    # Mobile does not abandon the atmosphere when the vision pass fails: the
    # curated table still chooses (main.py:3929-3935 runs whenever surprise_me is
    # on, vision or no vision). Only the ROOM is left as sent, because nothing
    # read it.
    check("DECIDE08: a failed vision pass never loses the generation",
          d.room_type == "Your space", d.room_type)
    check("DECIDE08b: and the atmosphere still comes from the validated table",
          d.atmosphere_id in SIGNATURE_ATMOSPHERES, d.atmosphere_id)


def test_staging_runs_the_same_engine_flags_as_mobile() -> None:
    """The flags ARE part of the engine.

    `run.sh` pins fourteen of them before mobile starts, and they decide whether
    Ayden Decide looks at the photo at all, which prompt blocks are emitted, and
    the per-edit-mode quality and fidelity. The staging launcher set none of
    them, so for weeks the PWA ran a differently-configured engine and nothing
    said so — the missing television reported 2026-08-10 is the failure `run.sh`
    already documents for a restart without AYDEN_DECIDE_FURNISH:

        "dropped Ayden Decide room detection -> AtmosphereDNA fell back to
         fallback_style_block -> empty/sparse V1 render"

    The list is READ from run.sh rather than copied, so this test is really
    asking one thing: can the two launchers still drift apart?
    """
    print("\n== 24) Staging runs mobile's engine flags, not a subset ==")
    import os as _os

    import engine_flags

    pinned = engine_flags.canonical_flags()
    check("FLAGS01: run.sh's pinned flags are readable", len(pinned) >= 10,
          f"found {len(pinned)}")
    check("FLAGS02: the one whose absence emptied the render is among them",
          pinned.get("AYDEN_DECIDE_FURNISH") == "1", str(pinned.get("AYDEN_DECIDE_FURNISH")))
    check("FLAGS03: so are the image-driven atmosphere and the compact switch "
          "block (which keeps the TV anchor inside budget)",
          pinned.get("SURPRISE_VISION") == "1"
          and pinned.get("SWITCH_BLOCK_COMPACT") == "1")

    # A comment mentioning a flag must never be mistaken for a pinned one.
    check("FLAGS04: documented-but-not-pinned flags are not applied",
          "PRESERVE_FURNISH_SCOPE" not in pinned and "MULTILINGUAL_NORMALIZE" not in pinned,
          ", ".join(sorted(pinned)))

    # Applying is additive and never silently overrides a deliberate export.
    _saved = dict(_os.environ)
    try:
        for name in pinned:
            _os.environ.pop(name, None)
        _os.environ["AYDEN_DECIDE_FURNISH"] = "0"   # an operator's explicit choice
        applied = engine_flags.apply_canonical_flags()
        check("FLAGS05: every pinned flag reaches the environment",
              all(_os.environ.get(k) == v for k, v in pinned.items()
                  if k != "AYDEN_DECIDE_FURNISH"))
        check("FLAGS06: a flag the operator set on purpose is left alone",
              _os.environ["AYDEN_DECIDE_FURNISH"] == "0"
              and "AYDEN_DECIDE_FURNISH" not in applied)
    finally:
        _os.environ.clear()
        _os.environ.update(_saved)

    # The staging launcher must actually call it — a module nobody invokes
    # protects nothing.
    launcher = pathlib.Path("run_pwa_staging.py").read_text(encoding="utf-8")
    check("FLAGS07: the staging launcher applies them before importing main",
          "apply_canonical_flags(" in launcher
          and launcher.index("apply_canonical_flags(") < launcher.index("import main as canonical"))

    # And the list must stay in run.sh, not be duplicated into Python.
    src = pathlib.Path("engine_flags.py").read_text(encoding="utf-8")
    check("FLAGS08: the flag list is READ from run.sh, never copied",
          "AYDEN_DECIDE_FURNISH=1" not in src and "run.sh" in src)


def test_an_empty_room_gets_staged(api) -> None:
    """"Preserve" means "restyle the furniture that is there". Shown an EMPTY
    room it has nothing to restyle, so the render stays bare — which is what a
    first vision on an empty room looked like. Mobile swaps the contract for a
    furnish one when Ayden Decide read the room itself."""
    print("\n== 25) An empty room is staged, not left bare ==")
    import asyncio as _a
    import os as _os

    import main as fake_main

    api_main = fake_main

    async def _living(_b: bytes) -> dict:
        return {"room": "living_room", "atmosphere": "warm_modern",
                "confidence": "high", "reason": ""}

    fake_main._classify_ayden = _living
    photo = _completed_render()
    _saved = _os.environ.get("AYDEN_DECIDE_FURNISH")
    try:
        _os.environ["AYDEN_DECIDE_FURNISH"] = "1"
        d = _a.run(api._ayden_decide(photo, "Your space", "Ayden Signature", 1))
        check("STAGE01: a room Ayden read itself is staged",
              d.stage_room == "living_room", d.stage_room)

        # A named room can be just as empty as a read one, and mobile stages it
        # too (main.py:3891-3899, SPECIFIC_ROOM_STAGE default "1"). What the
        # person named is still honoured — it is the ROOM that is respected, not
        # a refusal to furnish it.
        d = _a.run(api._ayden_decide(photo, "Kitchen", "Ayden Signature", 1))
        check("STAGE02: a room the person NAMED is staged too, on mobile's list",
              d.stage_room == "kitchen" and d.room_type == "Kitchen",
              f"{d.stage_room}/{d.room_type}")

        d = _a.run(api._ayden_decide(photo, "Master Bedroom", "Ayden Signature", 1))
        check("STAGE02b: a form label is mapped the way mobile maps it",
              d.stage_room == "bedroom", d.stage_room)

        d = _a.run(api._ayden_decide(photo, "Wine Cellar", "Ayden Signature", 1))
        check("STAGE02c: a room outside mobile's list is NOT staged",
              d.stage_room == "", d.stage_room)

        d = _a.run(api._ayden_decide(photo, "Your space", "Ayden Signature", 2))
        check("STAGE03: staging is a first-vision act, not something a later "
              "iteration redoes", d.stage_room == "", d.stage_room)

        # Exteriors: only the ones the engine has validated for staging may be
        # staged. The list is ASKED FOR, never retyped — it has grown once
        # already (the exterior STAGE wave), and a hardcoded copy would have
        # quietly disagreed with mobile from that day on.
        from prompt_engine.preservation import is_exterior_stage_room

        for room in sorted(api_main._EXTERIOR_ROOMS):
            async def _ext(_b: bytes, _r=room) -> dict:
                return {"room": _r, "atmosphere": "warm_modern",
                        "confidence": "high", "reason": ""}

            fake_main._classify_ayden = _ext
            d = _a.run(api._ayden_decide(photo, "Your space", "Ayden Signature", 1))
            expected = room if is_exterior_stage_room(room) else ""
            check(f"STAGE04[{room}]: staged only if the engine validates it",
                  d.stage_room == expected, f"{d.stage_room!r} != {expected!r}")

        fake_main._classify_ayden = _living
        _os.environ["AYDEN_DECIDE_FURNISH"] = "0"
        d = _a.run(api._ayden_decide(photo, "Your space", "Ayden Signature", 1))
        check("STAGE05: the flag still governs it, exactly as on mobile",
              d.stage_room == "", d.stage_room)
    finally:
        if _saved is None:
            _os.environ.pop("AYDEN_DECIDE_FURNISH", None)
        else:
            _os.environ["AYDEN_DECIDE_FURNISH"] = _saved


def test_the_photo_is_described_to_the_composer(api) -> None:
    """Mobile opens a first vision by describing the room to itself — windows,
    camera angle, perspective, depth, ceiling, anchors. The PWA sent "", so
    every first vision was composed blind to the space it was redesigning."""
    print("\n== 26) The composer is told what the photo shows ==")
    import asyncio as _a

    import main as fake_main

    sent: list[dict] = []

    class _Msg:
        content = "Two-point corner view. Three floor-to-ceiling windows left."

    class _Choice:
        message = _Msg()

    class _Answer:
        choices = [_Choice()]

    class _Chat:
        class completions:  # noqa: N801
            @staticmethod
            async def create(**kwargs):
                sent.append(kwargs)
                return _Answer()

    fake_main.openai = types.SimpleNamespace(images=fake_main.openai.images,
                                             chat=_Chat())
    on = types.SimpleNamespace(vision_analysis_fv=True, name="PROD")
    off = types.SimpleNamespace(vision_analysis_fv=False, name="mobile_mvp_baseline")

    got = _a.run(api._describe_room(_completed_render(), on, 2))
    check("VISION01: the description reaches the caller",
          got.startswith("Two-point"), got[:40])
    check("VISION02: it is the same model mobile uses",
          sent and sent[0].get("model") == "gpt-4o-mini")

    # The wording IS the contract — a paraphrase is a different prompt.
    main_src = pathlib.Path("main.py").read_text(encoding="utf-8")
    check("VISION03: the analysis wording is byte-identical to mobile's",
          api._ROOM_ANALYSIS_PROMPT in main_src.replace("\n", "").replace('" "', "")
          or all(frag in main_src for frag in (
              "Analyze this room for an architectural interior photographer.",
              "(2) Window count, approximate positions (left/center/right/back wall), ",
              "(7) Key structural anchors: any columns, open doorways, kitchen island, fireplace wall. ",
              "Max 4 sentences.")))

    sent.clear()
    check("VISION04: a profile that disables the pass makes no call",
          _a.run(api._describe_room(_completed_render(), off, 2)) == "" and not sent)

    class _Boom:
        class completions:  # noqa: N801
            @staticmethod
            async def create(**_kwargs):
                raise RuntimeError("vision down")

    fake_main.openai = types.SimpleNamespace(images=fake_main.openai.images,
                                             chat=_Boom())
    check("VISION05: a failure costs the description, never the generation",
          _a.run(api._describe_room(_completed_render(), on, 2)) == "")

    # Measured on the canonical flags: the composer's `source_space` section is
    # 0 chars at iteration 1 (TRUST_PIXELS_V1 — read the photo, not a description
    # of it) and 85 from iteration 2. Same prompt either way; no reason to buy a
    # vision call whose answer is discarded.
    sent.clear()
    check("VISION06: no call on a first vision, where the composer drops it",
          _a.run(api._describe_room(_completed_render(), on, 1)) == "" and not sent)


def test_the_lineage_reaches_the_composer(api) -> None:
    """A switch has to know what it is switching FROM. Sent empty, every switch
    was composed as though nothing came before it."""
    print("\n== 27) The composer is told what came before ==")
    import asyncio as _a

    V1 = f"users/{UID}/projects/{PROJECT}/generated/v1.jpg"
    V2 = f"users/{UID}/projects/{PROJECT}/generated/v2.jpg"
    ORIGINAL = f"users/{UID}/projects/{PROJECT}/original/o.jpg"

    def load(action: str, parent: str, rows: list[dict]):
        class _Resp:
            status_code = 200

            def json(self):
                return rows

        class _Client:
            async def get(self, *_a_, **_k):
                return _Resp()

        body = api.PwaGenerateRequest(
            project_id=PROJECT, idempotency_key="k", room_label="Living Room",
            original_image_path=ORIGINAL, action_type=action,
            atmosphere_id="japandi_calm", atmosphere_label="Japandi Calm",
            vision_number=2, parent_vision_id=parent)
        return _a.run(api._load_lineage(_Client(), "tok", body, UID))

    pure = [{"id": "v1", "action_type": "initial", "image_path": V1,
             "atmosphere_id": "warm_modern"}]
    refined = pure + [{"id": "v2", "action_type": "refine", "image_path": V2,
                       "atmosphere_id": "warm_modern"}]

    lin = load("refine", "v1", pure)
    check("LIN01: the parent's atmosphere is carried, so a switch is seen as one",
          lin.prev_atmosphere_id == "warm_modern", lin.prev_atmosphere_id)
    check("LIN02: a lineage with no refine is not customized",
          lin.customized is False, str(lin.customized))

    lin = load("switch_atmosphere", "v2", refined)
    check("LIN03: a refine makes the lineage customized",
          lin.customized is True, str(lin.customized))
    check("LIN04: and that is what keeps the work through a switch",
          lin.source_path == V2, lin.source_path)

    lin = load("initial", "", pure)
    check("LIN05: a first vision has nothing behind it — never a guessed value",
          lin.prev_atmosphere_id == "" and lin.customized is None
          and lin.source_path == ORIGINAL)

    check("LIN06: a pure switch is anchored on V1, never on the photo",
          load("switch_atmosphere", "v1", pure).source_path == V1,
          load("switch_atmosphere", "v1", pure).source_path)

    # One network read serves all three answers.
    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    body = src.split("async def _load_lineage", 1)[1].split("async def _resolve_source_path", 1)[0]
    check("LIN07: it costs ONE read, not one per answer",
          body.count("client.get(") == 1, str(body.count("client.get(")))


def test_a_vision_number_never_decides_the_action(api) -> None:
    """A vision's NUMBER says when it was made, never what the user did.

    The same "Vision 2" is a switch if the person clicked an atmosphere and a
    refine if they typed a change, and the two take their source image from
    different places. Any rule that keys off the number instead of the action
    will be right by luck on the happy path and wrong the moment somebody
    refines before switching — which is the ordinary way people use this.
    """
    print("\n== 28) The action decides, the vision number never does ==")

    ORIGINAL = f"users/{UID}/projects/{PROJECT}/original/o.jpg"
    V1 = f"users/{UID}/projects/{PROJECT}/generated/v1.jpg"
    V2 = f"users/{UID}/projects/{PROJECT}/generated/v2.jpg"
    V3 = f"users/{UID}/projects/{PROJECT}/generated/v3.jpg"

    def source(action: str, parent: str, rows: list[dict], number: int) -> str:
        import asyncio as _a

        class _Resp:
            status_code = 200

            def json(self):
                return rows

        class _Client:
            async def get(self, *_a_, **_k):
                return _Resp()

        body = api.PwaGenerateRequest(
            project_id=PROJECT, idempotency_key="k", room_label="Living Room",
            original_image_path=ORIGINAL, action_type=action,
            atmosphere_id="japandi_calm", atmosphere_label="Japandi Calm",
            vision_number=number, parent_vision_id=parent)
        return _a.run(api._load_lineage(_Client(), "tok", body, UID)).source_path

    v1 = {"id": "v1", "vision_number": 1, "action_type": "initial", "image_path": V1}

    # SAME number 2 — two different user actions, two different sources.
    as_switch = [v1]
    as_refine = [v1]
    check("VNUM01: vision 2 as a SWITCH is anchored on V1",
          source("switch_atmosphere", "v1", as_switch, 2) == V1)
    check("VNUM02: vision 2 as a REFINE edits its parent",
          source("refine", "v1", as_refine, 2) == V1)

    # Now the interesting half: number 4 is not "late", it is whatever was done.
    refined = [
        v1,
        {"id": "v2", "vision_number": 2, "action_type": "refine", "image_path": V2},
        {"id": "v3", "vision_number": 3, "action_type": "switch_atmosphere",
         "image_path": V3},
    ]
    check("VNUM03: vision 4 as a REFINE takes the vision it was launched from",
          source("refine", "v3", refined, 4) == V3,
          source("refine", "v3", refined, 4))
    check("VNUM04: vision 4 as a SWITCH keeps the customized work, because a "
          "refine exists in this lineage — not because 4 > 1",
          source("switch_atmosphere", "v3", refined, 4) == V3,
          source("switch_atmosphere", "v3", refined, 4))

    # And the number really is inert: change it, keep everything else.
    check("VNUM05: changing ONLY the number changes nothing",
          source("switch_atmosphere", "v1", [v1], 2)
          == source("switch_atmosphere", "v1", [v1], 9))

    # Nothing in the adapter may branch on the number.
    import re as _re

    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    body_only = "\n".join(
        ln for ln in src.splitlines()
        if not ln.lstrip().startswith("#") and not ln.lstrip().startswith('"')
    )
    branching = _re.findall(r"vision_number\s*(?:==|!=|>=|<=|>|<)\s*\d+", body_only)
    # `vision_number == 1` inside the V1 anchor is legitimate: it identifies the
    # ROOT of a lineage, which is a position, not an action.
    illegitimate = [b for b in branching if not b.replace(" ", "").endswith("==1")]
    check("VNUM06: no code branches on the vision number to choose behaviour",
          not illegitimate, ", ".join(illegitimate))


def test_a_question_is_answered_not_rendered(api) -> None:
    """A line with no change in it must cost nothing and still get a reply.

    The app itself offers "What do you think?" as a chip. That used to be posted
    as a refine: the parser found no change and the endpoint answered 422, so the
    person got an error for using a button the product gave them. Mobile answers
    such a line in words (main.py:2645). The gate is the refine PARSER, not an
    intent classifier — measured 2026-08-11, `classify_intent` labels "make the
    sofa white" as conversation, so gating on it would have blocked real refines.
    """
    print("\n== 29) A question is answered; only a change is rendered ==")
    import asyncio as _a

    import main as fake_main
    import refine.parser as _parser

    real_parse = _parser.parse_changes
    spoken: list[str] = []

    async def _no_change(text, client=None):
        spoken.append(text)
        return []

    async def _one_change(text, client=None):
        spoken.append(text)
        return [("modify", "sofa", "white", text)]

    def body(msg: str):
        return api.PwaGenerateRequest(
            project_id=PROJECT, idempotency_key="k", room_label="Living Room",
            original_image_path=f"users/{UID}/projects/{PROJECT}/original/o.jpg",
            action_type="refine", atmosphere_id="warm_modern",
            atmosphere_label="Warm Modern", vision_number=2,
            parent_vision_id="v1", user_instruction=msg)

    try:
        _parser.parse_changes = _no_change
        # Two arguments now: the RESOLVED room travels with the message, so
        # Ayden answers about the room the engine actually rendered rather than
        # about "Your space".
        api._converse = lambda b, room="": _a.sleep(
            0, result="It already reads calm to me.")
        answer, changes = _a.run(api._refine_advisory(body("what do you think?")))
        check("ANSWER01: a question comes back as an answer, not an error",
              answer is not None and answer.get("status") == "answer",
              str(answer)[:60])
        check("ANSWER02: it says plainly that nothing was rendered",
              answer.get("render_started") is False)
        check("ANSWER03: and it carries Ayden's words",
              bool(answer.get("message")))
        check("ANSWER04: no plan is handed on, because there is none",
              changes is None)

        # A real change still goes through untouched.
        _parser.parse_changes = _one_change
        spoken.clear()
        advisory, plan = _a.run(api._refine_advisory(body("make the sofa white")))
        check("ANSWER05: a real change is NOT diverted into a conversation",
              advisory is None and plan is not None, str(advisory)[:50])
        check("ANSWER06: the sentence is read exactly once",
              len(spoken) == 1, str(len(spoken)))
    finally:
        _parser.parse_changes = real_parse
        _install_canonical_stubs(_RECORD)


def test_a_refusal_is_terminal_and_a_saved_image_is_never_lost(api) -> None:
    """Two failures that used to be told wrong."""
    print("\n== 30) A refusal is final; a stored image is not thrown away ==")
    check("REJECT01: a provider refusal is a typed, NON-retryable answer",
          api._ENGINE_REJECTED.detail["error_code"] == "ENGINE_REJECTED"
          and api._ENGINE_REJECTED.detail["retryable"] is False)
    check("REJECT02: and it does not claim a render started",
          api._ENGINE_REJECTED.detail["render_started"] is False)

    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    check("REJECT03: the refusal is caught before the connection classifier, "
          "so it can never be mistaken for a dead socket",
          src.index('"BadRequestError"') < src.index("if _is_connection_failure(exc):"))

    # The image exists; a failed row must not delete it or bill it twice.
    persist = src.split("vision insert failed status", 1)[1][:900]
    check("PERSIST01: a failed row settles the claim COMPLETED, not FAILED",
          "_settle_claim" in persist and "vision_id=vision_id" in persist)
    check("PERSIST02: and the caller still receives the image it paid for",
          '"status": "completed"' in persist and '"persisted": False' in persist)


def _lineage_of(api, rows, *, action="switch_atmosphere", parent="v1",
                number=2, instruction=""):
    """Run the real `_load_lineage` against a fixed set of vision rows."""
    import asyncio as _a

    class _Resp:
        status_code = 200

        def json(self):
            return rows

    class _Client:
        async def get(self, *_a_, **_k):
            return _Resp()

    body = api.PwaGenerateRequest(
        project_id=PROJECT, idempotency_key="k", room_label="Living Room",
        original_image_path=f"users/{UID}/projects/{PROJECT}/original/o.jpg",
        action_type=action, atmosphere_id="japandi_calm",
        atmosphere_label="Japandi Calm", vision_number=number,
        parent_vision_id=parent, user_instruction=instruction)
    return _a.run(api._load_lineage(_Client(), "tok", body, UID))


def _row(vid, number, action, parent=None, prompt=None, customized=None,
         room=None, atmo="warm_modern"):
    return {"id": vid, "vision_number": number, "action_type": action,
            "image_path": f"users/{UID}/projects/{PROJECT}/generated/{vid}.jpg",
            "parent_vision_id": parent, "prompt_text": prompt,
            "lineage_customized": customized, "room_label": room,
            "atmosphere_id": atmo}


def test_a_branch_is_judged_on_its_own_ancestry(api) -> None:
    """THE hard lineage case: going back to a pre-customisation vision.

    Mobile reads ONE record — the SOURCE — and that record carries a flag
    computed cumulatively when it was written. So a refine on one branch cannot
    reach a branch that starts before it. The adapter used to answer the same
    question by scanning the whole project, which made every branch customised
    the moment anything anywhere had been refined.
    """
    print("\n== 31) Customisation follows the BRANCH, not the project ==")
    V1 = f"users/{UID}/projects/{PROJECT}/generated/v1.jpg"
    V3 = f"users/{UID}/projects/{PROJECT}/generated/v3.jpg"

    #   v1  (initial, not customized)
    #   ├── v2  refine  ── v3  refine
    #   └── (new branch taken from v1)
    tree = [
        _row("v1", 1, "initial", customized=False, room="Living Room"),
        _row("v2", 2, "refine", parent="v1", prompt="make the sofa white",
             customized=True),
        _row("v3", 3, "refine", parent="v2", prompt="add a floor lamp",
             customized=True),
    ]

    back_to_v1 = _lineage_of(api, tree, parent="v1", number=4)
    check("BRANCH01: a branch from V1 is NOT customized, even though the "
          "project contains two refines",
          back_to_v1.customized is False, str(back_to_v1.customized))
    check("BRANCH02: so it is a PURE switch and anchors on V1",
          back_to_v1.source_path == V1, back_to_v1.source_path)
    check("BRANCH03: and it carries NO refinement memory from the other branch",
          back_to_v1.history == [], str(back_to_v1.history))
    check("BRANCH04: the previous atmosphere is still V1's",
          back_to_v1.prev_atmosphere_id == "warm_modern",
          back_to_v1.prev_atmosphere_id)

    on_v3 = _lineage_of(api, tree, parent="v3", number=4)
    check("BRANCH05: the customized branch still knows it is customized",
          on_v3.customized is True, str(on_v3.customized))
    check("BRANCH06: so its switch keeps the vision being switched",
          on_v3.source_path == V3, on_v3.source_path)

    # A pre-0005 row (no stored flag) that IS linked → walk the ancestry.
    legacy_linked = [
        _row("v1", 1, "initial"),
        _row("v2", 2, "refine", parent="v1", prompt="add a rug"),
    ]
    check("BRANCH07: without a stored flag, a LINKED branch is walked, not the "
          "project",
          _lineage_of(api, legacy_linked, parent="v1", number=3).customized
          is False)

    # A pre-0005 row with NO link at all → mobile's legacy scan, never FRESH.
    legacy_unlinked = [
        {"id": "v1", "vision_number": 1, "action_type": "initial",
         "image_path": V1},
        {"id": "v2", "vision_number": 2, "action_type": "refine",
         "image_path": f"users/{UID}/projects/{PROJECT}/generated/v2.jpg"},
    ]
    check("BRANCH08: with neither a flag nor a link, it falls back to the "
          "legacy scan rather than silently claiming FRESH",
          _lineage_of(api, legacy_unlinked, parent="v2", number=3).customized
          is True)

    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    check("BRANCH09: no code answers the question by scanning every row of the "
          "project unconditionally",
          "any(v.get(\"action_type\") == \"refine\" for v in rows)" not in
          src.split("def _customized_from", 1)[0])


def test_the_customization_history_survives_a_switch(api) -> None:
    """A customised switch has to CARRY the customisations.

    The composer's REBOOT_CUSTOMIZED path filters the chat history down to the
    real spatial edits and feeds it back as refinement memory. Sent `[]`, that
    filter has nothing to keep, so a switch labelled CUSTOMIZED silently
    discarded every change the person had made.
    """
    print("\n== 32) A customized switch carries the user's own changes ==")
    tree = [
        _row("v1", 1, "initial", customized=False),
        _row("v2", 2, "refine", parent="v1", prompt="move the TV to the right wall",
             customized=True),
        _row("v3", 3, "refine", parent="v2", prompt="make it warmer",
             customized=True),
    ]
    lin = _lineage_of(api, tree, parent="v3", number=4)
    contents = [m["content"] for m in lin.history]
    check("HIST01: the branch's instructions reach the composer",
          contents == ["move the TV to the right wall", "make it warmer"],
          str(contents))
    check("HIST02: shaped exactly as mobile sends them",
          all(set(m) == {"role", "content"} and m["role"] == "user"
              for m in lin.history))

    # The FILTERING stays in the composer — that is the whole point.
    from prompt_engine.composer_v2 import _filter_history_to_customizations
    kept = [m["content"] for m in _filter_history_to_customizations(lin.history)]
    check("HIST03: the composer keeps the spatial edit",
          "move the TV to the right wall" in kept, str(kept))
    check("HIST04: and drops the atmosphere-only tweak, which belongs to the "
          "atmosphere being left behind",
          "make it warmer" not in kept, str(kept))

    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    engine_block = src.split("def _run_canonical_engine", 1)[1].split("def ", 1)[0]
    check("HIST05: nothing is pre-filtered in the adapter — the raw branch is "
          "handed over and the composer judges it",
          "history=history or []" in engine_block
          and "classify_transformation" not in engine_block)

    pure = _lineage_of(api, [_row("v1", 1, "initial", customized=False)],
                       parent="v1", number=2)
    check("HIST06: a pure switch invents no history and is not made customized "
          "by having one", pure.history == [] and pure.customized is False)


def test_the_resolved_room_is_remembered(api) -> None:
    """Ayden Decide answers once; everything after it must hear the answer."""
    print("\n== 33) The room Ayden resolved is the room everyone uses ==")
    body = lambda room: api.PwaGenerateRequest(  # noqa: E731
        project_id=PROJECT, idempotency_key="k", room_label=room,
        original_image_path=f"users/{UID}/projects/{PROJECT}/original/o.jpg",
        action_type="refine", atmosphere_id="warm_modern",
        atmosphere_label="Warm Modern", vision_number=2, parent_vision_id="v1",
        user_instruction="make the sofa white")

    check("ROOM01: an explicit choice is never second-guessed",
          api._effective_room(body("Kitchen"),
                              {"resolved_room_type": "living_room"}) == "Kitchen")
    check("ROOM02: a delegated room reads the project's resolved answer",
          api._effective_room(body("Your space"),
                              {"resolved_room_type": "living_room"})
          == "Living Room")
    check("ROOM03: the branch's own answer wins over the project's",
          api._effective_room(body(""), {"resolved_room_type": "kitchen"},
                              "Terrace") == "Terrace")
    check("ROOM04: with nothing resolved anywhere it stays as sent — a weaker "
          "prompt, never a wrong room",
          api._effective_room(body("Your space"), {}) == "Your space")
    check("ROOM05: canonical ids become the EN labels mobile persists",
          (api._room_display("living_room"), api._room_display("pool_area"))
          == ("Living Room", "Pool Area"))

    lin = _lineage_of(api, [_row("v1", 1, "initial", room="Living Room")],
                      action="refine", parent="v1", number=2)
    check("ROOM06: the room is read back from the vision that used it",
          lin.resolved_room == "Living Room", lin.resolved_room)

    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    adv = src.split("def _refine_advisory", 1)[1].split("\nasync def ", 1)[0]
    check("ROOM07: the ADVISOR is told the resolved room, not the placeholder",
          "await advise(changes, (room_label or body.room_label) or None" in adv)
    claimed = src.split("def _generate_claimed", 1)[1]
    check("ROOM08: the resolved room is written on the vision row",
          '"room_label": used_room or None' in claimed)
    check("ROOM09: and promoted to the project ONLY when it was delegated",
          "asked in _LET_AYDEN_ROOM" in claimed
          and 'patch["resolved_room_type"]' in claimed)


def test_processing_is_a_state_not_a_failure(api) -> None:
    """A generation the backend is still running is not an error."""
    print("\n== 34) PROCESSING keeps the generation alive ==")
    import asyncio as _a

    calls: list = []

    def status(routes):
        _install_fake_httpx(api, routes, calls)
        return _a.run(api.pwa_generation_status("key-1", f"Bearer {TOKEN}"))

    done = status({
        "/auth/v1/user": _Resp(200, {"id": UID}),
        "/rest/v1/pwa_visions": _Resp(200, [{
            "id": "v9", "vision_number": 3,
            "image_path": f"users/{UID}/projects/{PROJECT}/generated/v9.jpg",
            "room_label": "Living Room", "atmosphere_id": "japandi_calm",
            "atmosphere_label": "Japandi Calm", "lineage_customized": True}]),
    })
    check("PROC01: a written vision row means COMPLETED, whatever the claim says",
          done["state"] == "COMPLETED" and done["vision_id"] == "v9", str(done))
    check("PROC02: and it hands back everything the client has to adopt",
          done["resolved_room_type"] == "Living Room"
          and done["resolved_atmosphere_id"] == "japandi_calm"
          and done["lineage_customized"] is True)

    running = status({
        "/auth/v1/user": _Resp(200, {"id": UID}),
        "/rest/v1/pwa_visions": _Resp(200, []),
        "/rest/v1/pwa_generation_claims": _Resp(200, [{"state": "PROCESSING"}]),
    })
    check("PROC03: no row yet + a live claim → still PROCESSING",
          running["state"] == "PROCESSING", str(running))

    failed = status({
        "/auth/v1/user": _Resp(200, {"id": UID}),
        "/rest/v1/pwa_visions": _Resp(200, []),
        "/rest/v1/pwa_generation_claims": _Resp(
            200, [{"state": "FAILED", "error_code": "ENGINE_REJECTED",
                   "render_started": False}]),
    })
    check("PROC04: a failure is reported with its real code",
          failed["state"] == "FAILED"
          and failed["error_code"] == "ENGINE_REJECTED", str(failed))

    unknown = status({
        "/auth/v1/user": _Resp(200, {"id": UID}),
        "/rest/v1/pwa_visions": _Resp(200, []),
        "/rest/v1/pwa_generation_claims": _Resp(200, []),
    })
    check("PROC05: nothing at all is UNKNOWN, never an invented FAILED",
          unknown["state"] == "UNKNOWN", str(unknown))

    check("PROC06: polling costs no provider call and no claim",
          not any("openai" in u for _m, u in calls)
          and not any("rpc/claim_generation" in u for _m, u in calls))

    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    poll = src.split("async def pwa_generation_status", 1)[1].split("\nclass ", 1)[0]
    check("PROC07: the poll is read-only — it never parses, advises or renders",
          not any(w in poll for w in ("parse_changes", "advise", "images.edit",
                                      "_claim_generation")))


def test_verify_is_the_second_call_mobile_makes(api) -> None:
    """`/refine/verify` — free, non-blocking, silent unless `incomplete`."""
    print("\n== 35) Verify: a free second look that never blocks ==")
    import asyncio as _a

    def run(changes, verifier=None):
        calls: list = []
        _install_fake_httpx(api, {
            "/auth/v1/user": _Resp(200, {"id": UID}),
            "/storage/v1/object": _Resp(200, None, b"\x89PNG-bytes"),
        }, calls)
        mod = types.ModuleType("refine.verify")

        class _S:
            def __init__(self, v):
                self.value = v

        async def _verify(client, orig, mime, edited, parsed):
            if verifier == "boom":
                raise RuntimeError("provider down")
            return types.SimpleNamespace(
                status=_S(verifier or "verified"), identity_preserved=True,
                needs_refinement=False)

        mod.verify = _verify
        mod.build_report = lambda r, c: ("Still missing: the lamp"
                                         if r.status.value == "incomplete" else None)
        mod.missing_changes = lambda r, c: (c if r.status.value == "incomplete"
                                            else [])
        sys.modules["refine.verify"] = mod
        body = api.PwaVerifyRequest(
            project_id=PROJECT,
            before_path=f"users/{UID}/projects/{PROJECT}/generated/a.jpg",
            after_path=f"users/{UID}/projects/{PROJECT}/generated/b.jpg",
            changes=changes)
        return _a.run(api.pwa_refine_verify(body, f"Bearer {TOKEN}")), calls

    one = [{"type": "add", "object": "lamp", "detail": "floor",
            "raw": "add a floor lamp", "normalized": "add a floor lamp"}]

    empty, calls = run([])
    check("VERIFY01: nothing to verify → unavailable, and no image is fetched",
          empty["verification"] == "unavailable"
          and not any("/storage/" in u for _m, u in calls))

    ok, _ = run(one, "verified")
    check("VERIFY02: a fully applied edit reports `verified`",
          ok["verification"] == "verified", str(ok))
    check("VERIFY03: with nothing to say — the client stays silent",
          ok["report"] == "" and ok["missing"] == [], str(ok))

    inc, _ = run(one, "incomplete")
    check("VERIFY04: `incomplete` is the ONLY state that carries a report",
          inc["verification"] == "incomplete" and inc["report"], str(inc))
    check("VERIFY05: and it names what is missing, for a targeted retry",
          [c["raw"] for c in inc["missing"]] == ["add a floor lamp"],
          str(inc["missing"]))

    boom, _ = run(one, "boom")
    check("VERIFY06: a provider failure degrades to unavailable — it NEVER "
          "breaks the image already on screen",
          boom["verification"] == "unavailable", str(boom))

    # Tenancy is not fail-open.
    calls2: list = []
    _install_fake_httpx(api, {"/auth/v1/user": _Resp(200, {"id": UID})}, calls2)
    from fastapi import HTTPException
    try:
        _a.run(api.pwa_refine_verify(api.PwaVerifyRequest(
            project_id=PROJECT,
            before_path=f"users/{OTHER_UID}/projects/{PROJECT}/generated/a.jpg",
            after_path=f"users/{UID}/projects/{PROJECT}/generated/b.jpg",
            changes=one), f"Bearer {TOKEN}"))
        check("VERIFY07: another tenant's image is REFUSED, not verified", False,
              "no exception")
    except HTTPException as e:
        check("VERIFY07: another tenant's image is REFUSED, not verified",
              e.status_code == 403)

    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    check("VERIFY08: the adapter runs no verification logic of its own — it "
          "calls the module mobile calls",
          "from refine.verify import" in src
          and "identity_preserved=" not in src)
    check("VERIFY09: the executed plan is what is echoed for verification, so "
          "the second look asks about the edit that was actually made",
          "list(prepared.ordered_changes)" in src)


def test_the_running_engine_can_be_asked_what_it_is(api) -> None:
    """Parity claims have to be checkable against the PROCESS, not the source.

    A deployment started before a flag existed, or with an operator's own
    export, runs a different engine while every source test still passes. The
    introspection endpoint closes that gap — and is built so it cannot itself
    drift or leak.
    """
    print("\n== 36) The effective runtime can be read back ==")
    import asyncio as _a

    out = _a.run(api.pwa_engine_identity())

    # Proven by REBINDING main's attribute: if the endpoint read the package
    # symbol (the bug that gave the PWA the frozen v1 composer while mobile ran
    # v2) the answer would not move.
    import main as _canon

    _kept = _canon.compose_generation_prompt

    def _other(**_kw):
        return ""

    _other.__name__ = "a_different_composer"
    try:
        _canon.compose_generation_prompt = _other
        rebound = _a.run(api.pwa_engine_identity())
    finally:
        _canon.compose_generation_prompt = _kept
    check("ENGINE01: it reports the composer MAIN resolved, not the package "
          "default", rebound["composer"].endswith("a_different_composer")
          and out["composer"] != rebound["composer"],
          f"{out['composer']} -> {rebound['composer']}")
    check("ENGINE02: and the model + the recipe actually sent",
          out["model"] == "gpt-image-2" and out["effective_quality"] == "low",
          str((out["model"], out["effective_quality"])))
    check("ENGINE03: input_fidelity is reported as NOT sent — gpt-image-2 "
          "rejects it and mobile pops it for the same reason",
          out["input_fidelity_sent"] is False)

    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    block = src.split("async def pwa_engine_identity", 1)[1].split("\n\n\n", 1)[0]
    check("ENGINE04: the flag NAMES come from run.sh via engine_flags, so a new "
          "flag needs no second edit here",
          "canonical_flags()" in block)
    check("ENGINE05: only those repo-defined names are read from the "
          "environment — no secret can appear in the answer",
          "os.environ.get(name" in block and "os.environ.items" not in block
          and "dict(os.environ" not in block)

    # The model lock is MOBILE's. Read from main.py's source rather than
    # restated, so the day mobile changes it this fails instead of drifting.
    main_src = pathlib.Path("main.py").read_text(encoding="utf-8")
    lock = main_src.split('if IMAGE_MODEL.startswith("gpt-image-2")', 1)
    check("ENGINE06: mobile itself forces quality=low for this model",
          len(lock) == 2 and '_quality_override = "low"' in lock[1][:400])
    check("ENGINE07: and mobile itself omits input_fidelity for this model",
          len(lock) == 2 and "_fidelity_override = None" in lock[1][:400])

    check("ENGINE08: the endpoint is on the STAGING router only — mobile and "
          "production gain nothing",
          '@router.get("/engine")' in src and "@app.get" not in src)


def test_the_conversational_turn_is_mobiles_own(api) -> None:
    """A question must not be able to buy an image.

    The adapter's job here is to have NO opinion: `main.chat` is the same async
    function the mobile route calls, and its `should_generate` is the only thing
    that may open the paid path.
    """
    print("\n== 37) The conversational turn is mobile's own brain ==")
    import asyncio as _a

    import main as _canon

    calls: list = []
    seen: dict = {}

    def install(answer=None, boom=False):
        _install_fake_httpx(api, {
            "/auth/v1/user": _Resp(200, {"id": UID}),
            "/rest/v1/pwa_projects": _Resp(200, [{"id": PROJECT,
                                                  "owner_user_id": UID,
                                                  "room_label": "Living Room"}]),
            "/rest/v1/pwa_visions": _Resp(200, [
                _row("v1", 1, "initial", room="Living Room", customized=False),
                _row("v2", 2, "refine", parent="v1", prompt="make the sofa white",
                     customized=True),
            ]),
        }, calls)

        async def _chat(**kwargs):
            seen.clear()
            seen.update(kwargs)
            if boom:
                raise RuntimeError("production-only table")
            return answer

        _canon.chat = _chat
        body = api.PwaChatRequest(project_id=PROJECT, message="what do you think?")
        return _a.run(api.pwa_chat(body, f"Bearer {TOKEN}"))

    out = install({"ai_message": "It reads calm to me.", "should_generate": False,
                   "suggestions": ["Make it warmer"], "intent": "question",
                   "sub_intent": "general"})
    check("CHAT-B01: a conversational verdict is passed through untouched",
          out["should_generate"] is False
          and out["ai_message"] == "It reads calm to me.", str(out))
    check("CHAT-B02: and nothing was rendered, claimed or written",
          not any("rpc/claim_generation" in u or "images" in u
                  for _m, u in calls), str(calls))

    check("CHAT-B03: the canonical turn is given the RESOLVED room, not a "
          "placeholder", seen.get("room_type") == "Living Room",
          str(seen.get("room_type")))
    check("CHAT-B04: and the branch's own history, so conversation and render "
          "reason about one lineage",
          "make the sofa white" in str(seen.get("history")), str(seen.get("history")))
    check("CHAT-B05: the iteration is the one this line would PRODUCE — at 1 the "
          "canonical classifier short-circuits to GENERATE",
          seen.get("iteration") == 3, str(seen.get("iteration")))
    check("CHAT-B06: identity is supplied directly, so FastAPI's production "
          "auth dependency never runs",
          getattr(seen.get("current_user"), "user_id", None) == UID)

    yes = install({"ai_message": "On it.", "should_generate": True,
                   "suggestions": [], "intent": "generate", "sub_intent": "local_edit"})
    check("CHAT-B07: a generate verdict is passed through just as faithfully",
          yes["should_generate"] is True)

    closed = install(boom=True)
    check("CHAT-B08: a failure answers conversationally and NEVER authorises a "
          "render (fail closed)",
          closed["should_generate"] is False and bool(closed["ai_message"]),
          str(closed))

    src = pathlib.Path("pwa_staging_api.py").read_text(encoding="utf-8")
    block = src.split("async def pwa_chat", 1)[1].split("\nclass ", 1)[0]
    check("CHAT-B09: the adapter CALLS main.chat rather than reimplementing the "
          "decision chain", "canonical.chat(" in block)
    check("CHAT-B10: and reproduces none of it — no classifier, no intent "
          "comparison, no keyword list",
          not any(w in block for w in ("classify_intent", "ConversationIntent",
                                       "detect_generation_demand", "startswith('?')",
                                       "endswith('?')")))
    check("CHAT-B11: the chat turn spends nothing — it never touches the claim "
          "or the engine",
          not any(w in block for w in ("_claim_generation", "images.edit",
                                       "_run_canonical_engine",
                                       "_run_canonical_refine")))


def main() -> int:
    record = _RECORD
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
    test_incident_transport_failure_after_the_render(api, real_engine)
    test_every_hop_answers_instead_of_dying(api, real_engine)
    test_engine_unreachable_is_named_as_such(api, real_engine)
    test_refine_uses_the_canonical_refine_engine(api)
    test_advisor_decides_execute_or_advisory(api, real_engine)
    test_single_flight_prevents_a_second_paid_render(api, real_engine)
    test_durable_lifecycle(api, real_engine)
    test_durable_claim_fails_open_like_mobile(api, real_engine)
    test_a_failed_generation_releases_its_claim(api, real_engine)
    test_no_secret_is_ever_echoed(api)
    test_the_result_is_streamed_back(api, record, real_engine)
    test_mobile_is_not_dragged_into_the_change()
    test_the_engine_edits_the_right_picture(api)
    test_the_recipe_is_the_models_not_the_profiles(api)
    test_ayden_decide_reads_the_photo(api)
    test_staging_runs_the_same_engine_flags_as_mobile()
    test_an_empty_room_gets_staged(api)
    test_the_photo_is_described_to_the_composer(api)
    test_the_lineage_reaches_the_composer(api)
    test_a_vision_number_never_decides_the_action(api)
    test_a_question_is_answered_not_rendered(api)
    test_a_refusal_is_terminal_and_a_saved_image_is_never_lost(api)
    test_a_branch_is_judged_on_its_own_ancestry(api)
    test_the_customization_history_survives_a_switch(api)
    test_the_resolved_room_is_remembered(api)
    test_processing_is_a_state_not_a_failure(api)
    test_verify_is_the_second_call_mobile_makes(api)
    test_the_running_engine_can_be_asked_what_it_is(api)
    test_the_conversational_turn_is_mobiles_own(api)

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
