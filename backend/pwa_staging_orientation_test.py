"""Orientation goes through the staging wrapper untouched.

Round 3 (2026-09-02), phone review: "a PORTRAIT room photo came back as a
LANDSCAPE result". The bucket says the render was portrait (720×1280 in,
1024×1536 out); the landscape was the web's FRAME. This test pins the half of
that story that lives here: the staging wrapper hands the canonical size rule
the ORIGINAL bytes and sends the provider whatever that rule says — so a
portrait photo asks for 1024×1536, a landscape one for 1536×1024, and the
wrapper adds no opinion of its own.

It rides on `pwa_staging_adapter_test.py`'s harness (stubbed `main`, recorded
`images.edit` kwargs) but swaps the harness's constant `_detect_output_size`
for the REAL function, lifted from `main.py`'s source by the parser so a
retyped copy cannot drift from what production runs.

    cd backend && .venv/Scripts/python.exe pwa_staging_orientation_test.py
"""
from __future__ import annotations

import ast
import asyncio
import io
import os
import pathlib
import sys
import types

sys.path.insert(0, str(pathlib.Path(__file__).parent))

import pwa_staging_adapter_test as harness  # noqa: E402
from PIL import Image as PilImage  # noqa: E402

FAILS: list[str] = []


def check(label: str, ok: bool, detail: str = "") -> None:
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}" + (f"  ({detail})" if detail else ""))
    if not ok:
        FAILS.append(label)


def _real_detect_output_size():
    """`main._detect_output_size`, from main.py's SOURCE."""
    src = (pathlib.Path(__file__).parent / "main.py").read_text(encoding="utf-8")
    tree = ast.parse(src)
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name == "_detect_output_size":
            ns = {"PilImage": PilImage, "io": io}
            exec(ast.get_source_segment(src, node), ns)  # noqa: S102 — our own file
            return ns["_detect_output_size"]
    raise AssertionError("main._detect_output_size not found")


def _jpeg(w: int, h: int) -> bytes:
    buf = io.BytesIO()
    PilImage.new("RGB", (w, h), (120, 110, 100)).save(buf, format="JPEG", quality=85)
    return buf.getvalue()


def main() -> int:
    record = harness._RECORD
    harness._install_canonical_stubs(record)
    sys.modules["main"]._detect_output_size = _real_detect_output_size()
    os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
    os.environ.setdefault("SUPABASE_PUBLISHABLE_KEY", "sb_publishable_test_only")
    import pwa_staging_api as api  # noqa: E402

    print("\n== 1) The canonical size rule itself, on real pixels ==")
    detect = sys.modules["main"]._detect_output_size
    check("720x1280 (the phone sample) -> 1024x1536", detect(_jpeg(720, 1280)) == "1024x1536")
    check("1280x860 (the bench photo) -> 1536x1024", detect(_jpeg(1280, 860)) == "1536x1024")
    check("1000x1000 -> 1024x1024", detect(_jpeg(1000, 1000)) == "1024x1024")

    print("\n== 2) The staging wrapper sends that size, from the ORIGINAL bytes ==")
    for (w, h), want in (((720, 1280), "1024x1536"), ((1280, 860), "1536x1024")):
        record.pop("edit_kwargs", None)
        asyncio.run(
            api._run_canonical_engine(
                image_bytes=_jpeg(w, h),
                room_label="Living Room",
                atmosphere_label="Warm Modern",
                atmosphere_id="warm_modern",
                user_instruction="",
                iteration=1,
            )
        )
        got = record.get("edit_kwargs", {}).get("size")
        check(f"{w}x{h} source -> images.edit(size={want})", got == want, f"got {got}")

    print("\n== 3) The wrapper carries no aspect opinion of its own ==")
    src = (pathlib.Path(__file__).parent / "pwa_staging_api.py").read_text(encoding="utf-8")
    check(
        "output_size comes from canonical._detect_output_size(image_bytes)",
        "canonical._detect_output_size(image_bytes)" in src,
    )
    check(
        "no hard-coded landscape/portrait size in the generate path",
        '"size": "1536x1024"' not in src and '"size": "1024x1536"' not in src,
    )

    # ── The refine engine, which used to answer every refine in landscape ──
    import refine.executor as executor
    import refine.engine as engine
    import refine.orchestrator_adapter as adapter
    import refine.parser as parser
    from refine.parser import Change

    changes = [Change(type="modify", object="sofa", detail="dark green",
                      raw="make the sofa dark green")]

    print("\n== 4) A refine keeps the orientation of the vision it edits (staging wrapper) ==")
    for (w, h), want in (((1024, 1536), "1024x1536"), ((1536, 1024), "1536x1024"),
                         ((1024, 1024), "1024x1024")):
        record.pop("edit_kwargs", None)
        asyncio.run(api._run_canonical_refine(
            image_bytes=_jpeg(w, h), mime="image/jpeg",
            user_instruction="make the sofa dark green", changes=list(changes),
            source_ref=f"test-parent-{w}x{h}"))
        got = record.get("edit_kwargs", {}).get("size")
        check(f"parent {w}x{h} -> refine images.edit(size={want})", got == want, f"got {got}")

    print("\n== 5) Advisory -> Continue anyway (confirm=true: nothing pre-parsed) ==")
    real_parse = parser.parse_changes

    async def _parse(message, client=None):  # noqa: ARG001 — the LLM parser, stubbed
        return [Change(type="modify", object="wall", detail="", raw=message)]

    parser.parse_changes = _parse
    try:
        record.pop("edit_kwargs", None)
        asyncio.run(api._run_canonical_refine(
            image_bytes=_jpeg(1024, 1536), mime="image/jpeg",
            user_instruction="break the wall on the right", changes=None))
        got = record.get("edit_kwargs", {}).get("size")
        check("portrait parent, confirm path (re-parsed) -> 1024x1536", got == "1024x1536", f"got {got}")
    finally:
        parser.parse_changes = real_parse

    print("\n== 6) An atmosphere switch from a PORTRAIT vision stays portrait ==")
    record.pop("edit_kwargs", None)
    asyncio.run(api._run_canonical_engine(
        image_bytes=_jpeg(1024, 1536), room_label="Living Room",
        atmosphere_label="Japandi Calm", atmosphere_id="japandi_calm",
        user_instruction="", iteration=2, prev_atmosphere_id="warm_modern"))
    got = record.get("edit_kwargs", {}).get("size")
    check("switch on a 1024x1536 source -> images.edit(size=1024x1536)", got == "1024x1536", f"got {got}")
    record.pop("edit_kwargs", None)
    asyncio.run(api._run_canonical_engine(
        image_bytes=_jpeg(1536, 1024), room_label="Living Room",
        atmosphere_label="Japandi Calm", atmosphere_id="japandi_calm",
        user_instruction="", iteration=2, prev_atmosphere_id="warm_modern"))
    got = record.get("edit_kwargs", {}).get("size")
    check("switch on a 1536x1024 source -> images.edit(size=1536x1024)", got == "1536x1024", f"got {got}")

    print("\n== 7) iOS non-regression: every caller that passes no size gets the OLD default ==")
    client = sys.modules["main"].openai
    check("REFINE_SIZE constant is still the landscape default",
          executor.REFINE_SIZE == "1536x1024", executor.REFINE_SIZE)
    record.pop("edit_kwargs", None)
    asyncio.run(executor.execute(client, _jpeg(1024, 1536), "image/jpeg", "P"))
    check("executor.execute(...) without size, portrait bytes -> 1536x1024 (unchanged)",
          record.get("edit_kwargs", {}).get("size") == "1536x1024")
    record.pop("edit_kwargs", None)
    fn = adapter.build_execute_fn(client, "FROZEN")
    ctx = types.SimpleNamespace(image_bytes=_jpeg(1024, 1536), mime="image/jpeg")
    asyncio.run(fn(ctx))
    check("mobile's build_execute_fn path (POST /refine) -> 1536x1024 (unchanged)",
          record.get("edit_kwargs", {}).get("size") == "1536x1024")
    check("mobile's path sends the frozen prompt untouched",
          record.get("edit_kwargs", {}).get("prompt") == "FROZEN")
    record.pop("edit_kwargs", None)
    asyncio.run(engine.refine_generate(client, _jpeg(1024, 1536), "image/jpeg", list(changes)))
    check("engine.refine_generate(...) without size -> 1536x1024 (unchanged)",
          record.get("edit_kwargs", {}).get("size") == "1536x1024")
    import inspect
    sig = inspect.signature(executor.execute)
    check("`size` is keyword-only with the old value as default",
          sig.parameters["size"].kind is inspect.Parameter.KEYWORD_ONLY
          and sig.parameters["size"].default == "1536x1024")
    src_adapter = (pathlib.Path(__file__).parent / "refine" / "orchestrator_adapter.py").read_text(encoding="utf-8")
    check("orchestrator_adapter (mobile) is untouched by the change: passes no size",
          "size=" not in src_adapter)
    src_api = (pathlib.Path(__file__).parent / "pwa_staging_api.py").read_text(encoding="utf-8")
    check("the wrapper's refine size comes from the canonical rule on the edited bytes",
          "size = canonical._detect_output_size(image_bytes)" in src_api
          and "size=size)" in src_api)

    print()
    if FAILS:
        print(f"FAILED: {len(FAILS)}")
        for f in FAILS:
            print("  -", f)
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
