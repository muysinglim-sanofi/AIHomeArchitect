"""Wave 5.5.10b validation — verify 4 facts now render in STRUCTURAL_IDENTITY.

Confirms:
1. Parser captures 5 facts on user's apartment (sliding door + partition + depth + kitchen + anchor_rel).
2. render_clause now keeps 4 facts (dominant + partition + depth + kitchen) within 460 chars.
3. composer.py V1 prompt budget impact on tight atmospheres (Nordic Warmth).
4. composer_v2 V1 delegation still produces byte-identical prompts (Wave 5.5.6 invariant).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "backend")))

from prompt_engine.structural_identity import (
    extract_from_description, render_clause, render_negative_anchors,
    _MAX_CLAUSE_CHARS, _RENDER_ORDER,
)
from prompt_engine.composer import compose_generation_prompt as compose_py
from prompt_engine.composer_v2 import compose_generation_prompt as compose_v2

ROOM_DESC = (
    "Living room with a large floor-to-ceiling sliding glass door on the "
    "left wall opening to a balcony with vertical louvered shutters visible. "
    "Eye-level single-point perspective, medium spatial depth. Black-framed "
    "glass partition on the right separating the living zone from a rear "
    "room visible through the partition; a window is visible on the rear "
    "wall of the back room. Standard ceiling height. Herringbone wood floor "
    "throughout. Open kitchen visible on the right beyond the partition."
)

print("=" * 80)
print("Wave 5.5.10b validation — _MAX_CLAUSE_CHARS = 460")
print("=" * 80)
print()

# Step 1 — parser extraction
identity = extract_from_description(ROOM_DESC)
print("Step 1: parser fact extraction")
print(f"  dominant_opening    : {identity.dominant_opening!r}")
print(f"  glass_partition     : {identity.glass_partition!r}")
print(f"  room_depth_type     : {identity.room_depth_type!r}")
print(f"  kitchen_visibility  : {identity.kitchen_visibility!r}")
print(f"  anchor_relationships: {identity.anchor_relationships!r}")
print(f"  opening_layout      : {identity.opening_layout!r}")
print()

# Step 2 — rendered clause
clause = render_clause(identity, mode="V1")
print(f"Step 2: rendered clause ({len(clause)} chars, budget {_MAX_CLAUSE_CHARS})")
print(f"  {clause}")
print()

# Verify which facts made it
checks = [
    ("dominant_opening (sliding door)", "sliding glass door" in clause.lower() or
                                         "floor-to-ceiling" in clause.lower()),
    ("glass_partition",                 "partition" in clause.lower()),
    ("room_depth_type",                 "depth" in clause.lower() or "perspective" in clause.lower()),
    ("kitchen_visibility",              "kitchen" in clause.lower()),
    ("anchor_relationships",            "anchor" in clause.lower() or "left wall" in clause.lower()
                                        or "right" in clause.lower() and "partition" not in clause.lower().split("right")[1][:30]),
]
print("Step 3: fact-presence check in rendered clause")
for label, ok in checks:
    mark = "OK" if ok else "MISSING"
    print(f"  [{mark:7}] {label}")
print()

# Step 4 — full V1 prompt size for tight atmosphere
si = clause
neg = render_negative_anchors(identity)


def call_v1(atm, via):
    fn = compose_py if via == "py" else compose_v2
    return fn(
        style_label=f"{atm} · Vision 1",
        room_type="Living Room",
        room_description=ROOM_DESC,
        user_instruction="",
        iteration=1,
        history=[],
        secondary_visible_spaces=["kitchen"],
        compact_prompts=False,
        structural_identity=si,
        source_continuity="",
        structural_negative_anchors=neg,
        authorized_user_changes="",
    )


print("Step 4: V1 prompt size — composer.py vs composer_v2 (delegation)")
print(f"  {'atmosphere':18}  {'py size':8}  {'v2 size':8}  identical?")
print("  " + "-" * 60)
all_identical = True
for atm in ["Nordic Warmth", "Warm Modern", "Japandi Calm", "Bali Sanctuary", "Soft Luxury"]:
    p_py = call_v1(atm, "py")
    p_v2 = call_v1(atm, "v2")
    same = p_py == p_v2
    if not same:
        all_identical = False
    mark = "YES" if same else "NO"
    print(f"  {atm:18}  {len(p_py):7d}  {len(p_v2):7d}  {mark}")
print()
print(f"GATE 1 (Wave 5.5.6 byte-identity invariant): "
      f"{'PASS' if all_identical else 'FAIL'}")
print()

# Step 5 — check what sections composer.py kept on Nordic (tightest budget)
nordic_v1 = call_v1("Nordic Warmth", "py")
section_markers = {
    "ROOM CONTEXT":               "ROOM CONTEXT" in nordic_v1,
    "STRUCTURAL_IDENTITY":        "STRUCTURAL_IDENTITY" in nordic_v1 or si[:30] in nordic_v1,
    "kitchen mention":            "kitchen" in nordic_v1.lower(),
    "sliding door mention":       "sliding" in nordic_v1.lower(),
    "partition mention":          "partition" in nordic_v1.lower(),
    "DESIGN INTEL":               "DESIGN INTEL" in nordic_v1 or "design intel" in nordic_v1.lower(),
    "ATMOSPHERE_DNA_BOUNDARY":    "Atmosphere = these aesthetic" in nordic_v1 or
                                  "NEVER geometry" in nordic_v1,
    "VISIBLE_SPACES":             "VISIBLE_SPACES" in nordic_v1 or
                                  "visible spaces" in nordic_v1.lower(),
    "NATURAL_ENRICHMENT":         "natural" in nordic_v1.lower() and "enrichment" in nordic_v1.lower() or
                                  "enrich" in nordic_v1.lower(),
    "WOW directive":              "transformation" in nordic_v1.lower() and "ambition" in nordic_v1.lower() or
                                  "memorable" in nordic_v1.lower() or
                                  "compositional" in nordic_v1.lower(),
}
print("Step 5: section presence in Nordic Warmth V1 prompt (tight budget)")
print(f"  Total prompt size: {len(nordic_v1)} chars")
for label, present in section_markers.items():
    mark = "PRESENT" if present else "DROPPED"
    print(f"  [{mark:7}] {label}")
