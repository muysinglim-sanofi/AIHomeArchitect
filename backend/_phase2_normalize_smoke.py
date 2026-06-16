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

from prompt_engine.normalization import (
    normalize_to_english,
    normalize_history_to_english,
    _TRANSLATION_CACHE,
)
from prompt_engine.edit_intent import classify_edit_mode, EditMode
from prompt_engine.preservation import _temporal_override_requested
from prompt_engine.refinement_memory import parse_history

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


async def test_history_passthrough():
    print("[3] Phase 3 — history passthrough (English freeze guard)")
    hist = [
        {"role": "user", "content": "make it warmer"},
        {"role": "ai", "content": "Done."},
    ]
    # EN locale -> identical object (no rebuild)
    check("EN history returns identical object",
          (await normalize_history_to_english(None, hist, "en", enabled=True)) is hist)
    # flag off -> identical object
    check("flag-off history returns identical object",
          (await normalize_history_to_english(None, hist, "fr", enabled=False)) is hist)
    # empty -> identical
    check("empty history returns identical object",
          (await normalize_history_to_english(None, [], "fr", enabled=True)) == [])


async def test_history_fr_multiturn():
    print("[4] Phase 3 — FR multi-turn -> English history -> correct refinement_state")
    # Pre-seed the cache so no LLM/client is needed (client=None).
    _TRANSLATION_CACHE[("fr", "ajoute une plante")] = "add a plant"
    fr_hist = [
        {"role": "user", "content": "ajoute une plante"},
        {"role": "ai", "content": "Bien reçu."},
    ]
    out = await normalize_history_to_english(None, fr_hist, "fr", enabled=True)
    check("FR user message translated in history",
          out[0]["content"] == "add a plant")
    check("assistant message left untouched (same object)",
          out[1] is fr_hist[1])
    # Normalized English now parses correctly; raw FR did not.
    rs_en = parse_history(out, 2)
    rs_raw = parse_history(fr_hist, 2)
    check("refinement_state.add populated on normalized EN history",
          len(rs_en.add) > 0)
    check("refinement_state.add EMPTY on raw FR (proves the fix matters)",
          len(rs_raw.add) == 0)


async def main():
    await test_passthrough()
    test_routing_on_normalized_english()
    await test_history_passthrough()
    await test_history_fr_multiturn()
    print()
    if failures:
        print(f"FAILED: {len(failures)} -> {failures}")
        raise SystemExit(1)
    print("ALL PASS")


if __name__ == "__main__":
    asyncio.run(main())
