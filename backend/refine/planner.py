"""Refine Engine V2 — Composant 3 : SMART PLANNER (déterministe).

`Change[] (normalisés) → ExecutionPlan{strategy}` : ordre (§10) + compatibilité +
une **ExecutionStrategy** (PAS juste un prompt). Aujourd'hui une seule stratégie
(`combined_edit` : 1 génération, prompt combiné) — mais le Planner sort désormais
une *stratégie* pour laisser la porte ouverte SANS re-refactorer :

    combined_edit    (actuel)   1 gen, checklist + Locked elements
    full_redesign    (futur)    « make it a luxury villa » → ré-imagination guidée
    atmosphere_switch(futur)    « transform into Japandi » → route vers le switch existant
    sequential_forced(futur)    changements fragiles éclatés (au sein d'un retry)

Ne touche pas aux images / /generate / composer / DNA / preserve. Le défaut reste
TOUJOURS 1 génération (contrat « 1 action = 1 gen »).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from refine.parser import Change

# Ordre du prompt (§10) : STRUCTURE → REMOVE → REPLACE → ADD → MODIFY → MOVE
_ORDER = {"structure": 0, "remove": 1, "replace": 2, "add": 3, "modify": 4, "move": 5}
# Combinables (bench) : le reste (move/structure) = fragile → « isolate »
_COMBINABLE = {"add", "remove", "modify", "replace"}

# Stratégies d'exécution (seam). Une seule implémentée aujourd'hui.
STRATEGY_COMBINED_EDIT = "combined_edit"
STRATEGY_FULL_REDESIGN = "full_redesign"        # réservé (futur)
STRATEGY_ATMOSPHERE_SWITCH = "atmosphere_switch"  # réservé (futur)
STRATEGY_SEQUENTIAL_FORCED = "sequential_forced"  # réservé (futur)

_LOCKED = (
    "Locked elements — everything not listed above stays exactly as it is: the "
    "architecture, walls, windows, doors, flooring, ceiling, lighting direction, and "
    "every other piece of furniture, material and colour."
)


@dataclass
class ExecutionStrategy:
    """COMMENT exécuter ce plan. `kind` = laquelle ; `prompt` = le prompt pour les
    stratégies à génération unique (combined_edit / retry). Le seam d'extension : une
    nouvelle stratégie ajoute un `kind` + sa donnée, l'orchestrateur branche dessus."""
    kind: str
    prompt: str                          # prompt de la génération (combined_edit / retry)
    changes: list[Change] = field(default_factory=list)
    note: str = ""                       # explication du choix (log / UX)


@dataclass
class ExecutionPlan:
    ordered_changes: list[Change]       # ré-ordonnés (§10)
    strategy: ExecutionStrategy         # COMMENT exécuter (seam) — PAS juste un prompt
    mode: str                           # "default" | "retry"
    combinable: list[Change] = field(default_factory=list)
    isolate: list[Change] = field(default_factory=list)   # move / structure (fragiles)
    predicted_partial: bool = False     # heuristique : 1 gen risque de ne pas tout appliquer

    @property
    def combined_prompt(self) -> str:
        """Compat : le prompt de la stratégie courante (à génération unique)."""
        return self.strategy.prompt


def _order_key(c: Change) -> tuple[int, ...]:
    return (_ORDER.get(c.type, 9),)


def build_combined_prompt(changes: list[Change]) -> str:
    """Assemble le prompt combiné : checklist ordonnée + clause Locked elements."""
    lines = "\n".join(f"({i + 1}) {c.normalized or c.raw}" for i, c in enumerate(changes))
    return f"Apply ALL of these changes to this interior photo:\n{lines}\n\n{_LOCKED}"


def _choose_strategy(ordered: list[Change], mode: str) -> ExecutionStrategy:
    """POINT DE DÉCISION (seam). Aujourd'hui : toujours `combined_edit`.
    Demain, les branches full_redesign / atmosphere_switch / sequential_forced
    s'ajoutent ICI, sans re-refactorer l'orchestrateur ni l'endpoint."""
    return ExecutionStrategy(
        kind=STRATEGY_COMBINED_EDIT,
        prompt=build_combined_prompt(ordered),
        changes=ordered,
        note=("retry ciblé" if mode == "retry" else "1 génération combinée (défaut)"),
    )


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
        strategy=_choose_strategy(ordered, mode),
        mode=mode,
        combinable=combinable,
        isolate=isolate,
        predicted_partial=predicted_partial,
    )
