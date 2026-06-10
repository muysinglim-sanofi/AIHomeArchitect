"""
atmosphere_dna — room-specific atmosphere intelligence registry.

Import this package to populate the global registry with all 91 DNA entries
(7 atmospheres × 13 room types).

Public API:
  get_room_dna(atmosphere_id, room_type)  → RoomAtmosphereDNA | None
  build_dna_block(dna)                   → str   (~340 chars, replaces style+room blocks)
  build_secondary_space_block(dna)       → str   (~90 chars, for visible secondary rooms)
  label_to_atmosphere_id(style_label)    → str   ("Warm Modern · V2" → "warm_modern")
"""

from ._base import (
    AtmosphereCoreDNA,
    RoomAdaptationDNA,
    RoomAtmosphereDNA,
    register_core,
    get_core,
    get_room_dna,
    build_dna_block,
    build_dna_room_context,             # Wave 5.5.18
    build_dna_room_context_signal,      # Wave 5.5.18 (bimodal-gated wrapper)
    build_secondary_space_block,
    label_to_atmosphere_id,
)

# Import all atmosphere modules to trigger registration into the global registry
from . import warm_modern          # noqa: F401
from . import japandi_calm         # noqa: F401
from . import soft_luxury          # noqa: F401
from . import nordic_warmth        # noqa: F401
# nature_retreat removed 2026-06-04 — see _LEGACY_ALIASES["nature_retreat"] = "warm_modern".
# The DNA module on disk (atmosphere_dna/nature_retreat.py) is kept dormant for
# safe rollback ; not imported here so no registration happens.
# desert_luxe removed 2026-06-03 — see _LEGACY_ALIASES["desert_luxe"] = "warm_modern".
# The DNA module on disk (atmosphere_dna/desert_luxe.py) is kept dormant for
# safe rollback ; not imported here so no registration happens.
from . import tropical_escape      # noqa: F401

__all__ = [
    "AtmosphereCoreDNA",
    "RoomAdaptationDNA",
    "RoomAtmosphereDNA",
    "register_core",
    "get_core",
    "get_room_dna",
    "build_dna_block",
    "build_dna_room_context",
    "build_dna_room_context_signal",
    "build_secondary_space_block",
    "label_to_atmosphere_id",
]
