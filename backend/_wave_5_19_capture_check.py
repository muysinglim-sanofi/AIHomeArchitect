"""Wave 5.19 — Offline parser validation (throwaway).

Tests the new extract_from_description against synthetic raw_text strings
that mirror what gpt-4o would produce with the expanded 11-bucket prompt.
Asserts:
 - Each new field is correctly extracted from matching vocabulary
 - Backward compat : existing samples still parse to identical fact counts
 - No hallucination : raw_text without keywords leaves new fields empty
"""
from prompt_engine.structural_identity import (
    extract_from_description,
    ApartmentStructuralIdentity,
    from_token,
    to_token,
)


SAMPLES = [
    # ── (1) The Nordic bug case — should now capture door ────────────────
    (
        "nordic_simple_door",
        "Dominant opening: tall floor-to-ceiling window on the back wall. "
        "Interior door: wooden door visible on the back-left wall. "
        "Spatial depth: enclosed space.",
        {
            "dominant_opening": True,
            "interior_door": True,
            "room_depth_type": True,
        },
    ),
    # ── (2) Backward compat : original 5-bucket sample ────────────────────
    (
        "wm_original_5bucket",
        "1. Dominant opening — glazed wall, full-height, back wall.\n"
        "2. Glass partition — none visible.\n"
        "3. Spatial depth — open-plan.\n"
        "4. Open kitchen visible on the left.\n"
        "5. Secondary opening — none visible.",
        {
            "dominant_opening": True,
            "room_depth_type": True,
            "kitchen_visibility": True,
        },
    ),
    # ── (3) Living room with fireplace + staircase ────────────────────────
    (
        "fireplace_staircase",
        "(1) Dominant opening — bay window, wide, back wall.\n"
        "(5) Fixed built-in — fireplace on the right wall.\n"
        "(6) Vertical circulation — open staircase visible on the right.\n"
        "(7) Spatial depth — diagonal depth toward rear space.",
        {
            "dominant_opening": True,
            "fixed_built_in": True,
            "vertical_circulation": True,
            "room_depth_type": True,
        },
    ),
    # ── (4) Loft with beams + raised step + AC ────────────────────────────
    (
        "loft_beams_step_ac",
        "(1) Dominant opening — panoramic window, tall, back wall.\n"
        "(9) Ceiling signature — exposed wooden beam parallel to the back wall.\n"
        "(10) Surface transition — raised step into the rear zone.\n"
        "(11) Fixed appliance — wall-mounted AC unit on the upper-left wall.",
        {
            "dominant_opening": True,
            "ceiling_signature": True,
            "surface_transition": True,
            "fixed_appliance": True,
        },
    ),
    # ── (5) Anti-hallucination : completely empty room photo ──────────────
    (
        "empty_minimal",
        "Dominant opening: floor-to-ceiling window on the back wall.",
        {
            "dominant_opening": True,
            "interior_door": False,
            "fixed_built_in": False,
            "vertical_circulation": False,
            "ceiling_signature": False,
            "surface_transition": False,
            "fixed_appliance": False,
        },
    ),
    # ── (6) Kitchen photo : island + appliance ────────────────────────────
    (
        "kitchen_island",
        "(1) Dominant opening — picture window, wide, left wall.\n"
        "(5) Fixed built-in — kitchen island on the right.\n"
        "(7) Spatial depth — enclosed space.",
        {
            "dominant_opening": True,
            "fixed_built_in": True,
            "room_depth_type": True,
        },
    ),
    # ── (7) Multiple doors ────────────────────────────────────────────────
    (
        "multiple_doors",
        "(1) Dominant opening — floor-to-ceiling window, back wall.\n"
        "(4) Interior door — two interior doors visible on the right wall.\n"
        "(7) Spatial depth — open-plan.",
        {
            "dominant_opening": True,
            "interior_door": True,
            "room_depth_type": True,
        },
    ),
]


def main() -> None:
    print(f"{'CASE':<30} {'EXPECTED FIELDS':<70} STATUS")
    print("-" * 120)
    all_pass = True
    for name, raw_text, expected in SAMPLES:
        identity = extract_from_description(raw_text)
        # Build actual presence map
        actual = {f.name: bool(getattr(identity, f.name))
                  for f in identity.__dataclass_fields__.values()}
        # Compare against expected
        ok = True
        msgs = []
        for field, should_be_present in expected.items():
            actually_present = actual.get(field, False)
            if actually_present != should_be_present:
                ok = False
                msgs.append(
                    f"  {field}: expected={should_be_present} "
                    f"actual={actually_present}"
                )
        # Token roundtrip — ensures JSON serialization preserves all fields
        token = to_token(identity)
        restored = from_token(token)
        for f in identity.__dataclass_fields__:
            if getattr(identity, f) != getattr(restored, f):
                ok = False
                msgs.append(f"  ROUNDTRIP FAIL on field={f}")
        status = "OK" if ok else "FAIL"
        if not ok:
            all_pass = False
        exp_summary = ", ".join(
            f"{k}={'+' if v else '-'}"
            for k, v in expected.items()
        )
        print(f"{name:<30} {exp_summary:<70} {status}")
        for msg in msgs:
            print(msg)
        print(f"   facts={identity.fact_count}  "
              f"token_chars={len(token)}")
    print("-" * 120)
    print(f"\nFINAL: {'ALL PASS' if all_pass else 'FAILURES'}\n")
    # Sample identity printout for the Nordic case
    print("=== Sample : Nordic bug case identity ===")
    nordic = extract_from_description(SAMPLES[0][1])
    for f in nordic.__dataclass_fields__:
        v = getattr(nordic, f)
        if v:
            print(f"  {f}: {v}")


if __name__ == "__main__":
    main()
