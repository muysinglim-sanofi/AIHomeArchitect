"""Wave 5.24 — Parallel Structural Capture Union validation (offline).

Confirms the safe_union_merge logic is correct on synthetic fixtures
covering every decision branch :
  - both empty
  - one empty (additive)
  - both identical
  - contradiction with same base, different position (strip position)
  - contradiction with different base (drop entirely)
"""
import os
import sys
import logging

logging.disable(logging.CRITICAL)
sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
results = []


def check(label, cond, detail=""):
    s = PASS if cond else FAIL
    sfx = f"  [{detail}]" if detail and not cond else ""
    print(f"  {s}  {label}{sfx}")
    results.append((label, cond))


from prompt_engine.structural_identity import (
    ApartmentStructuralIdentity,
    safe_union_merge,
    _strip_position,
    _POSITION_BEARING_FIELDS,
)


# ── A. _strip_position regex behavior ─────────────────────────────────────
print("\n=== A. _strip_position helper ===")
check("A1  strip 'on the left wall'",
      _strip_position("floor-to-ceiling window as the apartment's primary opening on the left wall")
      == "floor-to-ceiling window as the apartment's primary opening")
check("A2  strip 'on the right'",
      _strip_position("wooden door visible on the right") == "wooden door visible")
check("A3  strip 'on the back wall'",
      _strip_position("glazed wall on the back wall") == "glazed wall")
check("A4  strip 'on the upper-left wall' (Wave 5.21d variant)",
      _strip_position("painted door visible on the upper-left wall")
      == "painted door visible")
check("A5  no-op when no position present",
      _strip_position("glass partition as a fixed structural divider")
      == "glass partition as a fixed structural divider")


# ── B. Decision matrix per field ──────────────────────────────────────────
print("\n=== B. merge decision matrix ===")

empty = ApartmentStructuralIdentity()

# B1 — both empty (every field)
merged, decisions = safe_union_merge(empty, empty)
check("B1  both empty → all 'identical'",
      all(v == "identical" for v in decisions.values())
      and not merged.is_present)

# B2 — only A has dominant_opening → additive_a
a_only = ApartmentStructuralIdentity(
    dominant_opening="floor-to-ceiling window as the apartment's primary opening on the left wall"
)
merged, decisions = safe_union_merge(a_only, empty)
check("B2  additive_a on dominant_opening",
      decisions["dominant_opening"] == "additive_a"
      and merged.dominant_opening == a_only.dominant_opening)

# B3 — only B has dominant_opening → additive_b
merged, decisions = safe_union_merge(empty, a_only)
check("B3  additive_b on dominant_opening",
      decisions["dominant_opening"] == "additive_b"
      and merged.dominant_opening == a_only.dominant_opening)

# B4 — both identical → identical, value preserved
both_same = ApartmentStructuralIdentity(
    dominant_opening="sliding glass door as the apartment's primary opening on the left wall",
    glass_partition="glass partition as a fixed structural divider",
)
merged, decisions = safe_union_merge(both_same, both_same)
check("B4  both identical → all 'identical' + value preserved",
      decisions["dominant_opening"] == "identical"
      and decisions["glass_partition"] == "identical"
      and merged.dominant_opening == both_same.dominant_opening)

# B5 — position-bearing : same base, different position → strip position
a_left = ApartmentStructuralIdentity(
    dominant_opening="sliding glass door as the apartment's primary opening on the left wall"
)
b_right = ApartmentStructuralIdentity(
    dominant_opening="sliding glass door as the apartment's primary opening on the right wall"
)
merged, decisions = safe_union_merge(a_left, b_right)
check("B5  position-bearing same base different position → 'contradict_position_stripped'",
      decisions["dominant_opening"] == "contradict_position_stripped"
      and "on the left wall" not in merged.dominant_opening
      and "on the right wall" not in merged.dominant_opening
      and "primary opening" in merged.dominant_opening)

# B6 — position-bearing : different base, position info → KEEP longer
#       (Wave 5.24 post-empirical-fix : dropping entirely caused 6/8 walls.
#       Better to keep an imperfect descriptor than lose architectural anchor.)
a_door = ApartmentStructuralIdentity(
    dominant_opening="sliding glass door as the apartment's primary opening on the left wall"
)
b_window = ApartmentStructuralIdentity(
    dominant_opening="bay window as the apartment's primary opening on the left wall"
)
merged, decisions = safe_union_merge(a_door, b_window)
check("B6  position-bearing different base → 'kept_*_longer' (NOT dropped)",
      decisions["dominant_opening"] in ("kept_a_longer", "kept_b_longer")
      and merged.dominant_opening != "")

# B7 — non-position-bearing field different → KEEP longer (NOT drop)
a_depth = ApartmentStructuralIdentity(
    room_depth_type="spatial depth defining the spatial volume"
)
b_depth = ApartmentStructuralIdentity(
    room_depth_type="open-plan spatial volume"
)
merged, decisions = safe_union_merge(a_depth, b_depth)
check("B7  non-position-bearing different → 'kept_*_longer' (NOT dropped)",
      decisions["room_depth_type"] in ("kept_a_longer", "kept_b_longer")
      and merged.room_depth_type != "")

# B8 — position-bearing : same base, A has position, B doesn't → take A's
a_pos = ApartmentStructuralIdentity(
    dominant_opening="sliding glass door as the apartment's primary opening on the left wall"
)
b_nopos = ApartmentStructuralIdentity(
    dominant_opening="sliding glass door as the apartment's primary opening"
)
merged, decisions = safe_union_merge(a_pos, b_nopos)
# Since the strings differ (one has position suffix, one doesn't), they're
# treated as a contradiction. Strip both → both equal → keep base.
check("B8  same base, only A has position → strip (keep base only)",
      decisions["dominant_opening"] == "contradict_position_stripped"
      and "on the left wall" not in merged.dominant_opening
      and "primary opening" in merged.dominant_opening)


# ── C. Realistic empirical scenario ───────────────────────────────────────
print("\n=== C. realistic merge scenario (WM-1 vs WM-4) ===")
# WM-1 captured 3 facts (minimal — wall invention prone)
wm1 = ApartmentStructuralIdentity(
    dominant_opening="full-height sliding glass door as the apartment's primary opening on the left wall",
    glass_partition="glass partition as a fixed structural divider",
    room_depth_type="spatial depth defining the spatial volume",
    anchor_relationships="the primary opening and the glass divider hold fixed relative positions",
)
# WM-4 captured 5 facts (rich — no wall invention)
wm4 = ApartmentStructuralIdentity(
    dominant_opening="full-height sliding glass door as the apartment's primary opening on the left wall",
    glass_partition="glass partition as a fixed structural divider",
    room_depth_type="spatial depth defining the spatial volume",
    kitchen_visibility="open kitchen visible on the right",
    interior_door="interior doors as a fixed wall feature",
    anchor_relationships="the primary opening and the glass divider hold fixed relative positions",
)
merged, decisions = safe_union_merge(wm1, wm4)
check("C1  merged inherits WM-4's interior_door (additive)",
      decisions["interior_door"] == "additive_b"
      and merged.interior_door == wm4.interior_door)
check("C2  merged inherits WM-4's kitchen_visibility (additive)",
      decisions["kitchen_visibility"] == "additive_b"
      and merged.kitchen_visibility == wm4.kitchen_visibility)
check("C3  merged fact_count >= max(WM-1, WM-4)",
      merged.fact_count >= max(wm1.fact_count, wm4.fact_count))


# ── D. Contradiction scenario (orientation flip) ──────────────────────────
print("\n=== D. orientation contradiction (LEFT vs RIGHT) ===")
left_capture = ApartmentStructuralIdentity(
    dominant_opening="sliding glass door as the apartment's primary opening on the left wall",
    glass_partition="glass partition as a fixed structural divider",
)
right_capture = ApartmentStructuralIdentity(
    dominant_opening="sliding glass door as the apartment's primary opening on the right wall",
    glass_partition="glass partition as a fixed structural divider",
)
merged, decisions = safe_union_merge(left_capture, right_capture)
check("D1  contradictory orientation → position stripped (kept base)",
      decisions["dominant_opening"] == "contradict_position_stripped"
      and merged.dominant_opening
      and "left wall" not in merged.dominant_opening
      and "right wall" not in merged.dominant_opening)
check("D2  glass_partition identical → preserved",
      decisions["glass_partition"] == "identical"
      and merged.glass_partition == left_capture.glass_partition)


# ── E. main.py wiring ─────────────────────────────────────────────────────
print("\n=== E. main.py wiring ===")
with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
check("E1  safe_union_merge imported in main.py",
      "safe_union_merge" in main_src)
check("E2  Wave 5.24 marker present",
      "Wave 5.24" in main_src)
check("E3  parallel asyncio.gather of 2 captures on V1 path",
      "asyncio.gather(" in main_src
      and main_src.count("_capture_structural_text(image_bytes)") >= 2)
check("E4  V1 capture path uses merge",
      "safe_union_merge(" in main_src)
check("E5  [Wave5.24] logging markers present (additive + position stripped + non-position kept)",
      "[Wave5.24] capture_A facts=" in main_src
      and "[Wave5.24] additive merged fields" in main_src
      and "[Wave5.24] contradict position stripped" in main_src
      and "[Wave5.24] non-position disagreement, kept longer" in main_src)


# ── F. Wave 5.23 / Wave 5.19 / Wave 5.21d intact ─────────────────────────
print("\n=== F. existing waves preserved ===")
check("F1  Wave 5.19 11-bucket prompt still present",
      "(11) Fixed appliance" in main_src
      and "(9) Ceiling signature" in main_src)
check("F2  Wave 5.21d position regex still in structural_identity",
      "_POSITION_BEARING_FIELDS" in open("prompt_engine/structural_identity.py", encoding="utf-8").read())
check("F3  Wave 5.23 functions still defined (rollback assets)",
      "_capture_orientation_mini" in main_src
      and "_resolve_orientation_consensus" in main_src)


logging.disable(logging.NOTSET)
passed = sum(1 for _, ok in results if ok)
total = len(results)
failed = [l for l, ok in results if not ok]
print(f"\n{'=' * 60}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if failed:
    print("\n  FAILING CHECKS:")
    for l in failed:
        print(f"    - {l}")
print(f"{'=' * 60}")
