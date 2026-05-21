"""Dump full Nordic Warmth V1 prompt to verify all sections survive."""
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
    style_label="Nordic Warmth · Vision 1",
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

# Section-presence probes — known canonical strings from each composer.py block
probes = [
    ("STRUCTURAL_IDENTITY (P1)", "STRUCTURAL IDENTITY"),
    ("  sliding door fact",      "sliding glass door"),
    ("  glass partition fact",   "glass partition"),
    ("  kitchen fact",           "open kitchen"),
    ("structural_negative_anchors","Do NOT add"),
    ("first_vision_task (C2.b)", "as aesthetic overlay"),
    ("atmosphere_dna (P2)",      "Nordic Warmth"),
    ("atmosphere_dna_boundary",  "Atmosphere = these aesthetic"),
    ("design_intel (P3)",        "DESIGN INTEL"),
    ("natural_enrichment (P4)",  "Allow naturally"),
    ("visible_spaces (P5)",      "visible adjacent"),
    ("wow_directive (C1.b)",     "WOW only through"),
    ("photo-edit framing (C2.a)","SAME APARTMENT PHOTO-EDIT"),
    ("preserve floor",           "preserve the herringbone"),
]

print(f"Nordic Warmth V1 prompt size: {len(prompt)} chars (budget 3850)")
print()
print("Section / fact presence:")
for label, needle in probes:
    found = needle.lower() in prompt.lower()
    mark = "PRESENT" if found else "MISSING"
    print(f"  [{mark:7}] {label}  (probe: {needle!r})")
print()
print("=" * 80)
print("FULL PROMPT:")
print("=" * 80)
print(prompt)
