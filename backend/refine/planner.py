"""Refine Engine V2 — Composant 3 : SMART PLANNER (déterministe).

`Change[] (normalisés) → ExecutionPlan` : ordre (§10) + compatibilité + le PROMPT
COMBINÉ unique (défaut) ou ciblé (retry). Ne touche pas aux images / /generate /
composer / DNA / preserve. Le défaut reste TOUJOURS 1 génération (contrat).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from refine.parser import Change

# Ordre du prompt (§10) : STRUCTURE → REMOVE → REPLACE → ADD → MODIFY → MOVE
_ORDER = {"structure": 0, "remove": 1, "replace": 2, "add": 3, "modify": 4, "move": 5}
# Combinables (bench) : le reste (move/structure) = fragile → « isolate »
_COMBINABLE = {"add", "remove", "modify", "replace"}

_LOCKED = (
    "Locked elements — everything not listed above stays exactly as it is: the "
    "architecture, walls, windows, doors, flooring, ceiling, lighting direction, and "
    "every other piece of furniture, material and colour."
)


@dataclass
class ExecutionPlan:
    ordered_changes: list[Change]       # ré-ordonnés (§10)
    combined_prompt: str                # LE prompt de la génération (défaut ou retry ciblé)
    mode: str                           # "default" | "retry"
    combinable: list[Change] = field(default_factory=list)
    isolate: list[Change] = field(default_factory=list)   # move / structure (fragiles)
    predicted_partial: bool = False     # heuristique : 1 gen risque de ne pas tout appliquer


def _order_key(c: Change) -> tuple[int, ...]:
    return (_ORDER.get(c.type, 9),)


def build_combined_prompt(changes: list[Change]) -> str:
    """Assemble le prompt combiné : checklist ordonnée + clause Locked elements."""
    lines = "\n".join(f"({i + 1}) {c.normalized or c.raw}" for i, c in enumerate(changes))
    return f"Apply ALL of these changes to this interior photo:\n{lines}\n\n{_LOCKED}"


def plan(changes: list[Change], *, mode: str = "default",
         missing: Optional[list[Change]] = None) -> ExecutionPlan:
    """Construit l'ExecutionPlan. En mode 'retry', ne cible que les `missing`."""
    src = missing if (mode == "retry" and missing is not None) else changes
    ordered = sorted(src, key=_order_key)
    isolate = [c for c in ordered if c.type not in _COMBINABLE]
    combinable = [c for c in ordered if c.type in _COMBINABLE]
    # Prédiction : >1 changement « isolate » (plusieurs moves, ou structure+move) →
    # 1 gen risque d'être partielle (le Verify tranchera ; sert au log / à l'UX).
    predicted_partial = len(isolate) > 1
    return ExecutionPlan(
        ordered_changes=ordered,
        combined_prompt=build_combined_prompt(ordered),
        mode=mode,
        combinable=combinable,
        isolate=isolate,
        predicted_partial=predicted_partial,
    )
