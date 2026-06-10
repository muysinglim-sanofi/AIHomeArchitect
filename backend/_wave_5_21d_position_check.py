"""Wave 5.21d — Position-capture validation for dominant_opening.

Wave 5.21d enriches extract_from_description so that the wall position
(left/right/back/front) reported by gpt-4o for the dominant opening is
preserved in the rendered STRUCTURAL IDENTITY clause instead of being
silently dropped. This validates :

 - back wall   → "...as the apartment's primary opening on the back wall"
 - left wall   → "...as the apartment's primary opening on the left wall"
 - right wall  → "...as the apartment's primary opening on the right wall"
 - front wall  → "...as the apartment's primary opening on the front wall"
 - no position → unchanged from Wave 5.19 baseline
 - position belonging to a NEIGHBOURING bucket (interior_door, fixed
   appliance) must NOT bleed into the dominant_opening clause.
"""
from prompt_engine.structural_identity import extract_from_description


SAMPLES = [
    # ── Back wall (gpt-4o "on the back wall" phrasing) ────────────────────
    (
        "back_wall_on_the",
        "Dominant opening: tall floor-to-ceiling window on the back wall. "
        "Spatial depth: enclosed space.",
        "tall floor-to-ceiling window as the apartment's primary opening on the back wall",
    ),
    # ── Back wall (gpt-4o comma-separated phrasing) ───────────────────────
    (
        "back_wall_comma",
        "(1) Dominant opening — glazed wall, full-height, back wall.\n"
        "(7) Spatial depth — open-plan.",
        "full-height glazed wall as the apartment's primary opening on the back wall",
    ),
    # ── Left wall ─────────────────────────────────────────────────────────
    (
        "left_wall",
        "(1) Dominant opening — picture window, wide, left wall.\n"
        "(7) Spatial depth — enclosed space.",
        "wide picture window as the apartment's primary opening on the left wall",
    ),
    # ── Right wall ────────────────────────────────────────────────────────
    (
        "right_wall",
        "Dominant opening: large bay window on the right wall.",
        "large bay window as the apartment's primary opening on the right wall",
    ),
    # ── Front wall (rare but allowed by parser) ───────────────────────────
    # NOTE : qualifier "dominant " is picked up by the pre-existing
    # qualifier loop (`q in low` substring match) from the "Dominant
    # opening" header. Pre-existing Wave 5.13g behaviour, unchanged by
    # 5.21d. Tests assert the *current* baseline, not a fix to that quirk.
    (
        "front_wall",
        "Dominant opening: floor-to-ceiling window on the front wall.",
        "dominant floor-to-ceiling window as the apartment's primary opening on the front wall",
    ),
    # ── No position (Wave 5.19 baseline behaviour preserved) ──────────────
    (
        "no_position",
        "Dominant opening: floor-to-ceiling window.",
        "dominant floor-to-ceiling window as the apartment's primary opening",
    ),
    # ── Neighbour-bucket bleed guard ──────────────────────────────────────
    # The window has NO position ; a downstream interior_door bucket DOES
    # say "left wall". The dominant_opening clause must NOT inherit the
    # door's "left wall" — sentence-bounded search stops at the first
    # period after the key, keeping positions bucket-local.
    (
        "no_bleed_from_door",
        "Dominant opening: floor-to-ceiling window. "
        "Interior door: wooden door visible on the left wall.",
        "dominant floor-to-ceiling window as the apartment's primary opening",
    ),
    # ── Backward compat : Wave 5.19's Nordic-bug sample ───────────────────
    # Same input as `_wave_5_19_capture_check.SAMPLES[0]`, now asserts the
    # *enriched* expected output. Confirms 5.21d strictly improves the
    # existing facts without dropping them.
    (
        "nordic_simple_door_v521d",
        "Dominant opening: tall floor-to-ceiling window on the back wall. "
        "Interior door: wooden door visible on the back-left wall. "
        "Spatial depth: enclosed space.",
        "tall floor-to-ceiling window as the apartment's primary opening on the back wall",
    ),
]


def main() -> None:
    print(f"{'CASE':<28} {'EXPECTED':<82} STATUS")
    print("-" * 130)
    all_pass = True
    for name, raw_text, expected_dom in SAMPLES:
        identity = extract_from_description(raw_text)
        actual = identity.dominant_opening
        ok = actual == expected_dom
        status = "OK" if ok else "FAIL"
        if not ok:
            all_pass = False
        print(f"{name:<28} {expected_dom[:80]:<82} {status}")
        if not ok:
            print(f"   actual: {actual}")
    print("-" * 130)
    print(f"\nFINAL: {'ALL PASS' if all_pass else 'FAILURES'}\n")


if __name__ == "__main__":
    main()
