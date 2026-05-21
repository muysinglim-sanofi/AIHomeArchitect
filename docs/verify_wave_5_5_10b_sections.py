"""Verify exact section headers in Nordic Warmth V1 prompt (Wave 5.5.10b)."""
import os
import sys
import re

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

print(f"Total prompt size: {len(prompt)} chars")
print()
# All-caps headers (≥3 caps run) — heuristic for section markers
headers = re.findall(r"^[A-Z][A-Z _0-9:·•/—-]{3,}$", prompt, re.MULTILINE)
print(f"Section headers detected ({len(headers)}):")
for h in headers:
    print(f"  {h}")
print()
# Now extract block by block to see boundaries
blocks = [b for b in prompt.split("\n\n") if b.strip()]
print(f"Total blocks (split on \\n\\n): {len(blocks)}")
print()
print("First 6 chars of each block (to identify section order):")
for i, b in enumerate(blocks):
    head = b.split("\n")[0][:80]
    print(f"  [{i:2d}] {head}")
