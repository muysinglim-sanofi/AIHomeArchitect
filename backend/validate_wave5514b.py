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


# ── Wave 5.5.14f — boundary-voice drop validation ────────────────────────────

# Phrases that compose into the 3 boundary voices currently shipping in the
# rendered prompt. Voice #2 (ATMOSPHERE BOUNDARY inside _SAME_APARTMENT_V2)
# stays in preserve mode per the locked design decision; we don't test for its
# disappearance.
_VOICE1_TASK_TAIL = (
    "Atmosphere = surfaces, materials, lighting, decor — never geometry"
)
_VOICE1_COMPOSER_V2_TAIL = (
    "Atmosphere = these aesthetic dimensions — NEVER geometry"
)
_VOICE3_DNA_BOUNDARY = (
    "ATMOSPHERE DNA BOUNDARY"
)
_VOICE4_WOW_TAIL = (
    "WOW only through materials, lighting, atmosphere — NOT geometry"
)


def test_creative_mode_with_flag() -> None:
    """Wave 5.5.14d — when BIMODAL_ENABLED=1 + mode=creative, the composer
    should:
      - Use the soft 'SAME SPACE REIMAGINED' framing (vs 'PHOTO-EDIT').
      - DROP the OPENINGS ANCHOR section entirely.
      - DROP the STRUCTURAL NEGATIVE ANCHORS section entirely.
      - SOFTEN the STRUCTURAL IDENTITY clause to 'ARCHITECTURAL MEMORY'.
      - REVIVE the dormant DNA fields (ARCHITECTURAL CHARACTER, ROOM
        EXPRESSION, ATMOSPHERE KEYWORDS) at the end of the DNA block.
      - KEEP the full preservation stack & DNA boundary voices (those are
        the preserve-mode drops — creative wants the full atmosphere
        signal AND the safety voices that anti-rogue the result).

    With BIMODAL_ENABLED unset, creative requests fall through to the
    baseline (production safety invariant)."""
    import os
    from prompt_engine import compose_generation_prompt as v1_compose
    from prompt_engine.structural_identity import extract_from_description, to_token

    print("\n── Creative-mode wiring (Wave 5.5.14d) ──")

    # Build a synthetic identity so STRUCTURAL IDENTITY / NEG ANCHORS are
    # actually emitted (they're "" with no captured identity, which would
    # bypass the creative-mode softening / drop and miss the test). The
    # composer expects the ALREADY-RENDERED clause as a string — main.py
    # is the caller that runs render_clause() / render_negative_anchors()
    # with the mode, so we replicate that here.
    from prompt_engine.structural_identity import (
        render_clause as _render_id,
        render_negative_anchors as _render_neg,
    )
    identity_desc = (
        "Living room with large floor-to-ceiling window dominating the rear "
        "wall and an open kitchen visible on the left, with a glass partition."
    )
    identity = extract_from_description(identity_desc)

    def _build(mode: str):
        id_clause = _render_id(identity, "V1", mode)
        neg_clause = _render_neg(identity, mode)
        return v1_compose(
            style_label="Bali Sanctuary",
            room_type="living_room",
            room_description=identity_desc,
            user_instruction="",
            iteration=1,
            history=[],
            structural_identity=id_clause,
            structural_negative_anchors=neg_clause,
            generation_mode=mode,
        )

    # Flag OFF — creative request falls back to baseline (preserve-equivalent).
    os.environ.pop("BIMODAL_ENABLED", None)
    baseline = _build("creative")
    _check(
        "STRUCTURAL IDENTITY" in baseline,
        "Flag OFF + creative: must still emit hard STRUCTURAL IDENTITY clause",
    )
    _check(
        "OPENINGS ANCHOR" in baseline,
        "Flag OFF + creative: must still emit OPENINGS ANCHOR",
    )
    _check(
        "ARCHITECTURAL MEMORY" not in baseline,
        "Flag OFF: must NOT emit creative soft-identity clause",
    )
    print(f"  flag_off_creative_fallback  OK  ({len(baseline)} chars)")

    # Flag ON + creative — full creative path.
    os.environ["BIMODAL_ENABLED"] = "1"
    creative = _build("creative")
    _check(
        "SAME SPACE REIMAGINED" in creative,
        "Flag ON + creative: must use REIMAGINED framing",
    )
    _check(
        "SAME APARTMENT PHOTO-EDIT" not in creative,
        "Flag ON + creative: must NOT keep PHOTO-EDIT framing",
    )
    _check(
        "OPENINGS ANCHOR" not in creative,
        "Flag ON + creative: OPENINGS ANCHOR must be dropped",
    )
    _check(
        "STRUCTURAL NEGATIVE ANCHORS" not in creative,
        "Flag ON + creative: STRUCTURAL NEGATIVE ANCHORS must be dropped",
    )
    _check(
        "ARCHITECTURAL MEMORY" in creative,
        "Flag ON + creative: must emit softened ARCHITECTURAL MEMORY clause",
    )
    _check(
        "reproduce them exactly" not in creative,
        "Flag ON + creative: hard 'reproduce exactly' phrase must be absent",
    )
    _check(
        "ARCHITECTURAL CHARACTER" in creative,
        "Flag ON + creative: revived architectural_language field must appear",
    )
    _check(
        "ROOM EXPRESSION" in creative,
        "Flag ON + creative: revived room_specific_constraints must appear",
    )
    _check(
        "ATMOSPHERE KEYWORDS" in creative,
        "Flag ON + creative: revived atmosphere_keywords must appear",
    )
    # The DNA itself should still contain Bali's architectural language
    # (the strip is a preserve-only operation).
    _check(
        "pavilion" in creative.lower(),
        "Flag ON + creative: Bali pavilion language must REMAIN (no strip)",
    )
    print(f"  flag_on_creative_v1         OK  ({len(creative)} chars)")

    # Preserve mode unchanged from Wave 5.5.14f expectations.
    preserve = _build("preserve")
    _check(
        "OPENINGS ANCHOR" in preserve,
        "Flag ON + preserve: OPENINGS ANCHOR must REMAIN",
    )
    _check(
        "STRUCTURAL IDENTITY" in preserve,
        "Flag ON + preserve: hard STRUCTURAL IDENTITY must REMAIN",
    )
    _check(
        "ARCHITECTURAL MEMORY" not in preserve,
        "Flag ON + preserve: must NOT emit soft creative clause",
    )
    _check(
        "ARCHITECTURAL CHARACTER" not in preserve,
        "Flag ON + preserve: must NOT revive dormant DNA fields",
    )
    print(f"  flag_on_preserve_unchanged  OK  ({len(preserve)} chars)")

    os.environ.pop("BIMODAL_ENABLED", None)


def test_voice_drops_with_flag() -> None:
    """Wave 5.5.14f — when BIMODAL_ENABLED=1 + mode=preserve, voices 1/3/4
    must disappear from the rendered prompt; mode=creative keeps them; with
    the flag unset, all three modes are byte-identical (the safety invariant
    that protects the production path)."""
    import os
    from prompt_engine import compose_generation_prompt as v1_compose
    from prompt_engine.composer_v2 import compose_generation_prompt as v2_compose

    print("\n── Voice-drop activation (Wave 5.5.14f) ──")

    def _build(atm: str, mode: str, iteration: int = 1):
        compose = v1_compose if iteration == 1 else v2_compose
        return compose(
            style_label=atm,
            room_type="living_room",
            room_description="",
            user_instruction="",
            iteration=iteration,
            history=[],
            generation_mode=mode,
        )

    # Flag OFF: invariant — all 3 modes byte-identical for V1.
    os.environ.pop("BIMODAL_ENABLED", None)
    a = _build("Tropical Escape", "preserve")
    b = _build("Tropical Escape", "creative")
    c = _build("Tropical Escape", "preserve")  # default keyword path
    _check(a == b == c, "Flag OFF: V1 prompt must be byte-identical across modes")
    # The voices must be present (we kept them).
    _check(_VOICE1_TASK_TAIL in a, "Flag OFF: voice #1 (task tail) must remain")
    _check(_VOICE3_DNA_BOUNDARY in a, "Flag OFF: voice #3 (DNA boundary) must remain")
    _check(_VOICE4_WOW_TAIL in a, "Flag OFF: voice #4 (WOW tail) must remain")
    print("  flag_off_v1_invariant   OK")

    # Flag ON + preserve: voices 1, 3, 4 drop.
    os.environ["BIMODAL_ENABLED"] = "1"
    p = _build("Tropical Escape", "preserve")
    _check(
        _VOICE1_TASK_TAIL not in p,
        "Flag ON + preserve: voice #1 task tail must be DROPPED",
    )
    _check(
        _VOICE3_DNA_BOUNDARY not in p,
        "Flag ON + preserve: voice #3 DNA boundary section must be DROPPED",
    )
    _check(
        _VOICE4_WOW_TAIL not in p,
        "Flag ON + preserve: voice #4 WOW tail must be DROPPED",
    )
    print(
        f"  flag_on_preserve_v1     OK  ({len(p)} chars; -{len(a) - len(p)} vs flag-off)"
    )

    # Flag ON + creative: voice #1 is REPLACED by the Wave 5.5.14d creative
    # framing entirely (no PHOTO-EDIT task → the C2.b tail can't exist on
    # this path). Voices #3 and #4 are still emitted as DNA-vs-photo
    # arbiters because creative mode kept the full DNA + revives the
    # dormant architectural fields — the boundary voices help anchor the
    # generation.
    cr = _build("Tropical Escape", "creative")
    _check(
        "SAME SPACE REIMAGINED" in cr,
        "Flag ON + creative: must use REIMAGINED task framing",
    )
    _check(
        "SAME APARTMENT PHOTO-EDIT" not in cr,
        "Flag ON + creative: must NOT keep PHOTO-EDIT framing",
    )
    _check(_VOICE3_DNA_BOUNDARY in cr, "Flag ON + creative: voice #3 must remain")
    _check(_VOICE4_WOW_TAIL in cr, "Flag ON + creative: voice #4 must remain")
    print(f"  flag_on_creative_v1     OK  ({len(cr)} chars)")

    # V2 path (composer_v2) — same expectations on the propagated voices.
    p2 = _build("Tropical Escape", "preserve", iteration=2)
    cr2 = _build("Tropical Escape", "creative", iteration=2)
    _check(
        _VOICE1_COMPOSER_V2_TAIL not in p2 or _VOICE1_TASK_TAIL not in p2,
        "Flag ON + preserve: V2 CORE C2.b head tail must be DROPPED",
    )
    _check(
        _VOICE3_DNA_BOUNDARY not in p2,
        "Flag ON + preserve: V2 voice #3 must be DROPPED",
    )
    _check(
        _VOICE4_WOW_TAIL not in p2,
        "Flag ON + preserve: V2 voice #4 must be DROPPED",
    )
    _check(_VOICE3_DNA_BOUNDARY in cr2, "Flag ON + creative: V2 voice #3 must remain")
    _check(_VOICE4_WOW_TAIL in cr2, "Flag ON + creative: V2 voice #4 must remain")
    print(f"  flag_on_v2_paths        OK")

    # Restore flag-off baseline for any subsequent test.
    os.environ.pop("BIMODAL_ENABLED", None)


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> int:
    print("Wave 5.5.14b.1 — Bimodal classifier validation")
    print("=" * 60)
    test_per_atmosphere()
    test_unknown_atmosphere_passthrough()
    test_empty_input_passthrough()
    test_idempotency()
    test_whitespace_hygiene()
    test_voice_drops_with_flag()
    test_creative_mode_with_flag()

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
