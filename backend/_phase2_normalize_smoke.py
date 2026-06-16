"""Phase 2 machine-verification — normalization seam.

Run: .venv/Scripts/python.exe _phase2_normalize_smoke.py

Verifies (no LLM / network needed):
  1. EN / flag-off / empty / unsupported lang  -> STRICT passthrough (identity).
  2. The normalized-English OUTPUT routes correctly through the (untouched)
     classifiers: edit_mode + temporal override. This proves the seam fixes
     FR/KM by handing the engine canonical English, without touching the engine.

The actual FR/KM->EN translation quality is a needs-device-validation item
(requires gpt-4o-mini) and is intentionally NOT asserted here.
"""

import asyncio

from prompt_engine.normalization import normalize_to_english
from prompt_engine.edit_intent import classify_edit_mode, EditMode
from prompt_engine.preservation import _temporal_override_requested

failures = []


def check(name, cond):
    print(("  PASS " if cond else "  FAIL ") + name)
    if not cond:
        failures.append(name)


async def test_passthrough():
    print("[1] strict passthrough (English freeze guard)")
    s = "make the sofa warmer"
    # EN locale -> identity (same object), even with flag enabled
    check("EN locale returns identical object",
          (await normalize_to_english(None, s, "en", enabled=True)) is s)
    # flag off -> identity even for FR
    fr = "rends le canapé plus chaud"
    check("flag off returns identical object (fr)",
          (await normalize_to_english(None, fr, "fr", enabled=False)) is fr)
    # empty -> identity
    check("empty returns identical object",
          (await normalize_to_english(None, "", "fr", enabled=True)) == "")
    # unsupported lang -> identity
    check("unsupported lang returns identical object",
          (await normalize_to_english(None, s, "de", enabled=True)) is s)


def test_routing_on_normalized_english():
    print("[2] normalized-English output routes correctly (engine untouched)")
    # These are the English the seam is expected to produce for FR/KM inputs.
    # iteration=2 so we're past FIRST_VISION.
    check("layout EN -> LAYOUT_CHANGE",
          classify_edit_mode("move the sofa in front of the window", 2)
          == EditMode.LAYOUT_CHANGE)
    check("structural EN -> STRUCTURAL_TRANSFORMATION",
          classify_edit_mode("open up the wall between the rooms", 2)
          == EditMode.STRUCTURAL_TRANSFORMATION)
    check("local edit EN -> LOCAL_EDIT",
          classify_edit_mode("replace the coffee table with a round one", 2)
          == EditMode.LOCAL_EDIT)
    check("style EN -> STYLE_REFINEMENT",
          classify_edit_mode("make it warmer and cozier", 2)
          == EditMode.STYLE_REFINEMENT)
    # Temporal override (FR 'cinematique la nuit' -> EN must keep these words)
    check("temporal EN 'cinematic at night' -> override True",
          _temporal_override_requested("make it cinematic at night") is True)
    check("no temporal -> override False",
          _temporal_override_requested("add a rug") is False)


async def main():
    await test_passthrough()
    test_routing_on_normalized_english()
    print()
    if failures:
        print(f"FAILED: {len(failures)} -> {failures}")
        raise SystemExit(1)
    print("ALL PASS")


if __name__ == "__main__":
    asyncio.run(main())
