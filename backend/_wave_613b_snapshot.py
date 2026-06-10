"""Wave 6.13b — non-regression snapshot of every DNA prompt block.

Dumps build_dna_block() for every (atmosphere_id, room_type) registered, as a
stable sorted JSON. Run BEFORE and AFTER the kitchen edits, then diff: only
kitchen rows are allowed to change.
"""
import json
import sys

import prompt_engine.atmosphere_dna  # noqa: F401  triggers registration
from prompt_engine.atmosphere_dna._base import (
    _ADAPTATION_REGISTRY,
    build_dna_block,
    build_dna_room_context,
)

snapshot = {}
for atmo in sorted(_ADAPTATION_REGISTRY):
    for room in sorted(_ADAPTATION_REGISTRY[atmo]):
        dna = _ADAPTATION_REGISTRY[atmo][room]
        # build_dna_block = ATMOSPHERE/ROOM/STYLE/REALISM/AVOID surface.
        # build_dna_room_context = the shipped ROOM CONTEXT (room_specific_
        # constraints[:2]) + VISIBLE CONTINUITY. Concatenate so the snapshot
        # captures BOTH shipped surfaces — otherwise a room_specific_constraints
        # change would be invisible to the non-regression diff.
        snapshot[f"{atmo}::{room}"] = (
            build_dna_block(dna) + "\n---ROOMCTX---\n" + build_dna_room_context(dna)
        )

out_path = sys.argv[1] if len(sys.argv) > 1 else "_wave_613b_before.json"
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(snapshot, fh, ensure_ascii=False, indent=2, sort_keys=True)
print(f"wrote {len(snapshot)} blocks -> {out_path}")
