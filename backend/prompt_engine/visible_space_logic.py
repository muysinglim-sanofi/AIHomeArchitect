"""
visible_space_logic.py — Multi-space visible scene intelligence.

When a photo contains a primary room plus visible secondary spaces (bedroom
behind glass, kitchen in background, terrace through door), this module
generates per-room atmosphere DNA blocks for each visible space.

The primary room gets the full DNA block via the composer.
Secondary rooms get compact ~90-char treatment lines that maintain
atmosphere coherence across the entire visible scene.

Prompt size budget: each secondary block ~90 chars. Cap at 2 secondary rooms.
Total additional prompt cost: ~200 chars max.
"""

from __future__ import annotations
from .atmosphere_dna._base import get_room_dna, build_secondary_space_block


def build_visible_spaces_block(
    atmosphere_id: str,
    secondary_rooms: list[str],
    max_rooms: int = 2,
) -> str:
    """
    Build a compact prompt section describing how visible secondary rooms
    should be treated under the selected atmosphere.

    Args:
        atmosphere_id: e.g. "warm_modern"
        secondary_rooms: list of canonical room type keys
        max_rooms: cap at 2 to control prompt size

    Returns:
        Multiline string of VISIBLE [ROOM]: ... lines, or empty string.
    """
    if not secondary_rooms:
        return ""

    lines: list[str] = []
    seen: set[str] = set()

    for room_type in secondary_rooms[:max_rooms]:
        if room_type in seen:
            continue
        seen.add(room_type)

        dna = get_room_dna(atmosphere_id, room_type)
        if dna:
            lines.append(build_secondary_space_block(dna))
        else:
            # Fallback: generic atmosphere coherence instruction
            room_label = room_type.replace("_", " ").upper()
            lines.append(
                f"VISIBLE {room_label}: maintain {atmosphere_id.replace('_', ' ')} "
                f"atmosphere coherence — matching materials and lighting temperature."
            )

    if not lines:
        return ""

    header = "VISIBLE SPACES (maintain atmosphere across entire scene):"
    return header + "\n" + "\n".join(lines)
