"""
Extract every AtmosphereCoreDNA + RoomAdaptationDNA entry from the registry
and write a structured Markdown document grouped by atmosphere → core → rooms.

Read-only: nothing in the registry is mutated. Run from project root.
"""

from __future__ import annotations
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.abspath(os.path.join(HERE, "..", "backend"))
sys.path.insert(0, BACKEND)

# Importing the package triggers all 10 atmosphere modules to register.
from prompt_engine.atmosphere_dna import (  # noqa: E402
    get_core,
    get_room_dna,
)
from prompt_engine.atmosphere_dna._base import (  # noqa: E402
    _CORE_REGISTRY,
    _ADAPTATION_REGISTRY,
)


# Render rooms in a stable, human-friendly order.
_ROOM_ORDER = [
    "living_room", "master_bedroom", "kitchen", "bathroom",
    "home_office", "dining_room", "entrance_hall",
    "facade", "garden", "pool_area", "terrace", "balcony", "driveway",
]


def _h2(s: str) -> str: return f"\n## {s}\n"
def _h3(s: str) -> str: return f"\n### {s}\n"
def _h4(s: str) -> str: return f"\n#### {s}\n"

def _li_bullets(items: list[str]) -> str:
    if not items:
        return "_(empty)_\n"
    return "\n".join(f"- {i}" for i in items) + "\n"

def _kv(label: str, value: str) -> str:
    return f"- **{label}**: {value}\n"


def _render_core(atm_id: str, core) -> str:
    out = io.StringIO()
    out.write(_h3("Core DNA"))
    out.write(_kv("atmosphere_id", f"`{core.atmosphere_id}`"))
    out.write(_kv("philosophy", core.philosophy))
    out.write(_kv("emotional_intent", core.emotional_intent))
    out.write(_kv("architectural_language", core.architectural_language))
    out.write(_kv("lighting_behavior", core.lighting_behavior))
    out.write(_kv("luxury_level", core.luxury_level))
    out.write(_kv("atmosphere_keywords", ", ".join(core.atmosphere_keywords)))
    out.write(f"- **material_palette** ({len(core.material_palette)}):\n")
    out.write(_li_bullets([f"  {m}" for m in core.material_palette]))
    out.write(f"- **forbidden_elements** ({len(core.forbidden_elements)}):\n")
    out.write(_li_bullets([f"  {x}" for x in core.forbidden_elements]))
    return out.getvalue()


def _render_room(dna) -> str:
    out = io.StringIO()
    out.write(_h4(f"Room: `{dna.room_type}`"))
    out.write(f"- **furniture_language** ({len(dna.furniture_language)}):\n")
    out.write(_li_bullets([f"  {x}" for x in dna.furniture_language]))
    out.write(f"- **material_palette** ({len(dna.material_palette)}):\n")
    out.write(_li_bullets([f"  {x}" for x in dna.material_palette]))
    out.write(_kv("lighting_behavior", dna.lighting_behavior))
    out.write(f"- **decor_language** ({len(dna.decor_language)}):\n")
    out.write(_li_bullets([f"  {x}" for x in dna.decor_language]))
    out.write(f"- **realism_constraints** ({len(dna.realism_constraints)}):\n")
    out.write(_li_bullets([f"  {x}" for x in dna.realism_constraints]))
    out.write(f"- **room_specific_constraints** ({len(dna.room_specific_constraints)}):\n")
    out.write(_li_bullets([f"  {x}" for x in dna.room_specific_constraints]))
    out.write(_kv("visible_transition_logic", dna.visible_transition_logic))
    out.write(f"- **negative_rules** ({len(dna.negative_rules)}):\n")
    out.write(_li_bullets([f"  {x}" for x in dna.negative_rules]))
    return out.getvalue()


def main() -> None:
    out = io.StringIO()
    out.write("# Atmosphere DNA — Full Registry Export\n\n")
    out.write("All 10 atmospheres × 13 room types, extracted directly from the in-memory registry "
              "after importing `prompt_engine.atmosphere_dna`.\n")

    atmospheres = sorted(_CORE_REGISTRY.keys())
    out.write(f"\n**Atmospheres registered**: {len(atmospheres)} — {', '.join(f'`{a}`' for a in atmospheres)}\n")
    total_rooms = sum(len(rooms) for rooms in _ADAPTATION_REGISTRY.values())
    out.write(f"\n**Room adaptations registered**: {total_rooms}\n")
    out.write("\n---\n")

    for atm_id in atmospheres:
        core = get_core(atm_id)
        out.write(_h2(f"Atmosphere: `{atm_id}`"))

        if core:
            out.write(_render_core(atm_id, core))
        else:
            out.write("_(no core registered)_\n")

        rooms = _ADAPTATION_REGISTRY.get(atm_id, {})
        out.write(_h3(f"Room adaptations ({len(rooms)})"))
        ordered = [r for r in _ROOM_ORDER if r in rooms] + sorted(set(rooms) - set(_ROOM_ORDER))
        for room_type in ordered:
            dna = rooms[room_type]
            out.write(_render_room(dna))
        out.write("\n---\n")

    path = os.path.join(HERE, "ATMOSPHERE_DNA_EXPORT.md")
    with open(path, "w", encoding="utf-8") as f:
        f.write(out.getvalue())
    print(f"Wrote {path}  ({os.path.getsize(path):,} bytes)  "
          f"— {len(atmospheres)} atmospheres, {total_rooms} room adaptations.")


if __name__ == "__main__":
    main()
