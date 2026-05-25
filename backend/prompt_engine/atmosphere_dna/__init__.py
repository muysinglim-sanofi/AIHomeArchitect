"""
atmosphere_dna — room-specific atmosphere intelligence registry.

Import this package to populate the global registry with all 130 DNA entries
(10 atmospheres × 13 room types).

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
from . import zen_retreat          # noqa: F401
from . import nordic_warmth        # noqa: F401
from . import dark_contemporary    # noqa: F401
from . import nature_retreat       # noqa: F401
from . import desert_luxe          # noqa: F401
from . import bali_sanctuary       # noqa: F401
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
