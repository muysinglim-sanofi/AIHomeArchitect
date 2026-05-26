"""
Wave 5.5.14g — Budget margin diagnostic.

Renders V1 prompts for each of the 10 atmospheres in 3 modes (default /
preserve / creative) and reports the budget margin per render. Use this to
catch any future regression where a section starts dropping under budget
pressure.

Run:
    cd backend
    python validate_wave5514g_margins.py

PASS criteria (currently informational, not enforced):
  - All 30 cells (10 atm × 3 modes) must have margin >= 50 chars.
  - Default (flag-off) margin must equal preserve margin (byte-identical
    invariant since BIMODAL_ENABLED is unset).
  - Creative margin must remain positive (no overflow above hard ceiling).

This script DOES NOT call any model — pure local prompt assembly.
"""

from __future__ import annotations
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

from prompt_engine import compose_generation_prompt
from prompt_engine.composer import _MODE_BUDGETS
from prompt_engine.structural_identity import (
    extract_from_description,
    render_clause,
    render_negative_anchors,
)


_ATMOSPHERES = [
    "Tropical Escape", "Desert Luxe",
    "Japandi Calm", "Warm Modern", "Soft Luxury", "Penthouse Contemporary",
    "Nature Retreat", "Nordic Warmth",
]

# Realistic identity so every P1 anchor block actually emits.
_IDENTITY_DESC = (
    "Living room with large floor-to-ceiling window dominating the rear "
    "wall and an open kitchen visible on the left, with a glass partition."
)
_SECONDARIES = ["kitchen", "dining_room"]

_MIN_SAFE_MARGIN = 50   # below this, a section is one user-description away from dropping


def _build(atm: str, mode_label: str) -> tuple[str, int]:
    """Build a V1 prompt for the (atmosphere, mode) cell and return (prompt, margin)."""
    if mode_label == "default":
        os.environ.pop("BIMODAL_ENABLED", None)
        gm = "preserve"  # default flag-off path
    else:
        os.environ["BIMODAL_ENABLED"] = "1"
        gm = mode_label

    identity = extract_from_description(_IDENTITY_DESC)
    id_clause = render_clause(identity, "V1", gm)
    neg_clause = render_negative_anchors(identity, gm)

    prompt = compose_generation_prompt(
        style_label=atm,
        room_type="living_room",
        room_description=_IDENTITY_DESC,
        user_instruction="",
        iteration=1,
        history=[],
        secondary_visible_spaces=_SECONDARIES,
        structural_identity=id_clause,
        structural_negative_anchors=neg_clause,
        generation_mode=gm,
    )
    margin = _MODE_BUDGETS["FIRST_VISION"] - len(prompt)
    return prompt, margin


def main() -> int:
    budget = _MODE_BUDGETS["FIRST_VISION"]
    print(f"Wave 5.5.14g — Budget margin diagnostic")
    print("=" * 70)
    print(f"FIRST_VISION budget: {budget}  (hard ceiling 4000)")
    print(f"Synthetic identity:  '{_IDENTITY_DESC[:60]}…'")
    print(f"Secondary spaces:    {_SECONDARIES}")
    print()
    header = f"{'Atmosphere':<22} {'mode':<10} {'chars':>6} {'margin':>7} {'flag':<6}"
    print(header)
    print("-" * len(header))

    fail_low_margin: list[str] = []
    fail_default_vs_preserve: list[str] = []
    fail_overflow: list[str] = []

    for atm in _ATMOSPHERES:
        # First sub-loop: render with the flag OFF in 3 mode-arg variants.
        # All three MUST be byte-identical (production safety invariant —
        # without BIMODAL_ENABLED, mode is a no-op everywhere).
        os.environ.pop("BIMODAL_ENABLED", None)
        flag_off_renders = {}
        for gm in ("preserve", "creative"):
            identity = extract_from_description(_IDENTITY_DESC)
            p = compose_generation_prompt(
                style_label=atm,
                room_type="living_room",
                room_description=_IDENTITY_DESC,
                user_instruction="",
                iteration=1,
                history=[],
                secondary_visible_spaces=_SECONDARIES,
                structural_identity=render_clause(identity, "V1", gm),
                structural_negative_anchors=render_negative_anchors(identity, gm),
                generation_mode=gm,
            )
            flag_off_renders[gm] = p
        if flag_off_renders["preserve"] != flag_off_renders["creative"]:
            fail_default_vs_preserve.append(
                f"{atm}: flag-off preserve != creative ({len(flag_off_renders['preserve'])} vs "
                f"{len(flag_off_renders['creative'])}) — production-safety invariant broken"
            )

        # Second sub-loop: report sizes for the 3 active-config combos.
        for mode in ("default", "preserve", "creative"):
            prompt, margin = _build(atm, mode)
            chars = len(prompt)
            flag = "—" if mode == "default" else "OK" if margin > 0 else "OVER"
            print(f"{atm:<22} {mode:<10} {chars:>6} {margin:>+7} {flag:<6}")
            if margin < _MIN_SAFE_MARGIN:
                fail_low_margin.append(f"{atm}/{mode}: margin {margin:+d} < {_MIN_SAFE_MARGIN}")
            if mode == "creative" and margin < 0:
                fail_overflow.append(f"{atm}/creative: OVERFLOW {-margin} chars over budget")
        print()

    os.environ.pop("BIMODAL_ENABLED", None)

    print("=" * 70)
    if not fail_low_margin and not fail_default_vs_preserve and not fail_overflow:
        print("✓ All 30 cells within safe margins; flag-off invariant holds.")
        return 0
    print("FAILURES:")
    for f in fail_overflow:
        print(f"  ✗ OVERFLOW    {f}")
    for f in fail_default_vs_preserve:
        print(f"  ✗ INVARIANT   {f}")
    for f in fail_low_margin:
        print(f"  ⚠ LOW MARGIN  {f}")
    return 1 if (fail_overflow or fail_default_vs_preserve) else 0


if __name__ == "__main__":
    sys.exit(main())
