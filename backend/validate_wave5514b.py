"""
Wave 5.5.14b.1 — Bimodal classifier validation.

Verifies that `strip_architecture_tokens` correctly removes the architectural
phrases identified in docs/WAVE_5_5_14a_BIMODAL_CLASSIFICATION.md from the
rendered DNA blocks of each atmosphere, while leaving decoration content
intact.

Run:
    cd backend
    python validate_wave5514b.py

Exit code 0 = all checks pass. Non-zero = failure with line-level diagnostic.

This is purely a unit test of the strip module. It does NOT exercise the
composer wiring (that's Wave 5.5.14c), nor does it call any model. Local,
deterministic, fast.
"""

from __future__ import annotations
import sys

# Make sure the backend package is importable when running directly.
import os
_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

from prompt_engine.atmosphere_dna import build_dna_block, get_room_dna
from prompt_engine.atmosphere_dna.bimodal_classifier import (
    strip_architecture_tokens,
    architecture_token_count,
)


# Each entry: (atmosphere_id, room, phrases_that_MUST_be_gone_after_strip,
# phrases_that_MUST_remain_after_strip)
_CASES: list[tuple[str, str, list[str], list[str]]] = [
    (
        "tropical_escape",
        "living_room",
        # Must disappear
        ["Open-air tropical", "Breezy, "],
        # Must remain (decoration anchors). Note "Tropical living…" has a
        # capital T because the strip removes "Open-air " prefix only.
        ["white render", "rattan", "natural rattan or cane",
         "Tropical living with relaxed contemporary luxury"],
    ),
    (
        "zen_retreat",
        "living_room",
        ["architectural silence", "floor space dominant"],
        ["Meditative silence", "grey slate floor", "wabi plaster"],
    ),
    (
        "bali_sanctuary",
        "living_room",
        ["and ceiling structure"],
        ["volcanic grey stone", "reclaimed teak joinery", "handwoven"],
    ),
    (
        "desert_luxe",
        "living_room",
        ["Sculptural,", "monumental,"],
        ["tadelakt", "sandstone", "polished tadelakt floor"],
    ),
    (
        "japandi_calm",
        "living_room",
        ["breathable", "empty floor space is deliberate, not absent"],
        ["pale ash", "wabi-sabi plaster", "Paper lantern pendant"],
    ),
    (
        "warm_modern",
        "living_room",
        [],  # no strips defined
        ["European oak", "travertine", "warm sand plaster"],
    ),
    (
        "soft_luxury",
        "living_room",
        [],
        ["fluted ivory plaster", "honed cream marble", "bouclé"],
    ),
    (
        "dark_contemporary",
        "living_room",
        ["Architectural sophistication", "architecturally confident"],
        ["Sophistication", "dark charcoal plaster", "smoked oak"],
    ),
    (
        "nature_retreat",
        "living_room",
        ["architectural realism"],
        ["reclaimed oak", "rammed earth", "rough-cut stone",
         "Biophilic calm integrated with earthy luxury"],
    ),
    (
        "nordic_warmth",
        "living_room",
        [],  # 🟨 left as-is — benchmark candidate
        ["birch", "wool", "amber"],
    ),
]


# ── Tests ─────────────────────────────────────────────────────────────────────

_PASS = 0
_FAIL: list[str] = []


def _check(condition: bool, msg: str) -> None:
    global _PASS
    if condition:
        _PASS += 1
    else:
        _FAIL.append(msg)


def test_per_atmosphere() -> None:
    print("\n── Per-atmosphere round-trip tests ──")
    for atm, room, must_drop, must_keep in _CASES:
        dna = get_room_dna(atm, room)
        if dna is None:
            _FAIL.append(f"[{atm}/{room}] DNA not registered")
            continue
        rendered = build_dna_block(dna)
        stripped = strip_architecture_tokens(rendered, atm)

        for phrase in must_drop:
            present_before = phrase in rendered
            present_after = phrase in stripped
            if not present_before:
                # If the source DNA doesn't even contain the phrase we expected
                # to strip, the test data is stale — flag it.
                _FAIL.append(
                    f"[{atm}/{room}] expected phrase '{phrase}' not present "
                    f"in rendered DNA — test data is stale"
                )
                continue
            _check(
                not present_after,
                f"[{atm}/{room}] phrase '{phrase}' STILL present after strip",
            )

        for phrase in must_keep:
            _check(
                phrase in stripped,
                f"[{atm}/{room}] decoration phrase '{phrase}' was LOST during strip",
            )

        n_strips = architecture_token_count(atm)
        delta = len(rendered) - len(stripped)
        print(
            f"  {atm:20s} | strips={n_strips:2d} | "
            f"rendered={len(rendered):4d}c | "
            f"stripped={len(stripped):4d}c | delta={delta:+d}c"
        )


def test_unknown_atmosphere_passthrough() -> None:
    print("\n── Unknown atmosphere → no change ──")
    text = "Anything goes — Open-air tropical living."
    out = strip_architecture_tokens(text, "completely_unknown_atm")
    _check(
        out == text,
        f"unknown atmosphere should pass through; got {out!r}",
    )
    print("  unknown_atmosphere    OK")


def test_empty_input_passthrough() -> None:
    print("\n── Empty input → no change ──")
    for empty in ["", None]:
        out = strip_architecture_tokens(empty, "tropical_escape")  # type: ignore[arg-type]
        _check(
            out == empty,
            f"empty input {empty!r} should pass through; got {out!r}",
        )
    print("  empty_input           OK")


def test_idempotency() -> None:
    print("\n── Idempotency: strip(strip(x)) == strip(x) ──")
    for atm, room, _, _ in _CASES:
        dna = get_room_dna(atm, room)
        if dna is None:
            continue
        once = strip_architecture_tokens(build_dna_block(dna), atm)
        twice = strip_architecture_tokens(once, atm)
        _check(
            once == twice,
            f"[{atm}] not idempotent: 2nd pass changed output",
        )
    print("  idempotency           OK across all 10 atmospheres")


def test_whitespace_hygiene() -> None:
    print("\n── No orphan whitespace / double punctuation post-strip ──")
    for atm, room, _, _ in _CASES:
        dna = get_room_dna(atm, room)
        if dna is None:
            continue
        out = strip_architecture_tokens(build_dna_block(dna), atm)
        _check("  " not in out, f"[{atm}] double space found")
        _check(",," not in out, f"[{atm}] double comma found")
        _check(";;" not in out, f"[{atm}] double semicolon found")
        _check(" ," not in out, f"[{atm}] space-before-comma found")
        _check(" ;" not in out, f"[{atm}] space-before-semicolon found")
    print("  whitespace_hygiene    OK")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    print("Wave 5.5.14b.1 — Bimodal classifier validation")
    print("=" * 60)
    test_per_atmosphere()
    test_unknown_atmosphere_passthrough()
    test_empty_input_passthrough()
    test_idempotency()
    test_whitespace_hygiene()

    print("\n" + "=" * 60)
    print(f"Passed: {_PASS}")
    print(f"Failed: {len(_FAIL)}")
    if _FAIL:
        print("\nFailures:")
        for msg in _FAIL:
            print(f"  ✗ {msg}")
        return 1
    print("\n✓ All bimodal classifier checks pass.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
