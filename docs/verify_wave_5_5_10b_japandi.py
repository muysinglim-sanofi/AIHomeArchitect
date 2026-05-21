"""Probe Japandi Calm V1 (tightest fit at 3848/3850) for section presence."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "backend")))

from prompt_engine.structural_identity import (
    extract_from_description, render_clause, render_negative_anchors,
)
from prompt_engine.composer import compose_generation_prompt as compose_py

ROOM_DESC = (
    "Living room with a large floor-to-ceiling sliding glass door on the "
    "left wall opening to a balcony with vertical louvered shutters visible. "
    "Eye-level single-point perspective, medium spatial depth. Black-framed "
    "glass partition on the right separating the living zone from a rear "
    "room visible through the partition; a window is visible on the rear "
    "wall of the back room. Standard ceiling height. Herringbone wood floor "
    "throughout. Open kitchen visible on the right beyond the partition."
)
identity = extract_from_description(ROOM_DESC)
si = render_clause(identity, mode="V1")
neg = render_negative_anchors(identity)

prompt = compose_py(
    style_label="Japandi Calm · Vision 1",
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
print(f"Japandi V1 prompt size: {len(prompt)} chars (budget 3850, headroom {3850-len(prompt)})")
print()
canonical = [
    ("photo-edit C2.a",            "SAME APARTMENT PHOTO-EDIT"),
    ("first_vision_task C2.b",     "as aesthetic overlay"),
    ("structural_identity P1",     "STRUCTURAL IDENTITY"),
    ("  sliding door fact",        "sliding glass door"),
    ("  glass partition fact",     "glass partition"),
    ("  kitchen fact",             "open kitchen"),
    ("structural_neg_anchors",     "STRUCTURAL NEGATIVE ANCHORS"),
    ("openings_anchor",            "OPENINGS ANCHOR"),
    ("atmosphere_dna P2",          "ATMOSPHERE (Japandi Calm)"),
    ("design_intel (room DNA)",    "ROOM (Living Room):"),
    ("atmosphere_dna_boundary",    "ATMOSPHERE DNA BOUNDARY"),
    ("wow_directive C1.b",         "TRANSFORMATION AMBITION"),
    ("  WOW not geometry",         "WOW only through"),
    ("natural_enrichment P4",      "NATURAL ENRICHMENT"),
    ("realism tail",               "NOT a CGI render"),
]
print("Section / fact presence in Japandi Calm V1 (tightest fit):")
all_ok = True
for label, needle in canonical:
    found = needle in prompt
    if not found:
        all_ok = False
    mark = "PRESENT" if found else "MISSING"
    print(f"  [{mark:7}] {label}  (probe: {needle!r})")
print()
print(f"OVERALL: {'all critical sections PRESENT' if all_ok else 'SOMETHING DROPPED'}")
