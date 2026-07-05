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

# Prior de réussite par type EN 1 GÉNÉRATION (ancré benchmark : ADD/REMOVE ~3/3,
# MODIFY ok, REPLACE 2/3, MOVE 1/3, STRUCTURE 5/5 solo). Sert estimated_success.
_SUCCESS_PRIOR = {"add": 0.95, "remove": 0.95, "modify": 0.92,
                  "replace": 0.78, "structure": 0.80, "move": 0.45}

# Stratégies d'exécution (seam). Une seule implémentée aujourd'hui.
STRATEGY_COMBINED_EDIT = "combined_edit"
STRATEGY_FULL_REDESIGN = "full_redesign"        # réservé (futur)
STRATEGY_ATMOSPHERE_SWITCH = "atmosphere_switch"  # réservé (futur)
STRATEGY_SEQUENTIAL_FORCED = "sequential_forced"  # réservé (futur)

# PHILOSOPHIE REFINE (user 2026-07-05) : préserver UNIQUEMENT l'identité ARCHITECTURALE ;
# le mobilier n'est JAMAIS verrouillé par défaut — il est librement déplaçable / réorganisable
# / supprimable / remplaçable. Un « déplacer le canapé à l'autre bout » n'est PAS une entorse à
# la préservation : c'est exactement ce que Refine doit permettre. (L'ancienne clause verrouillait
# « every other piece of furniture » → elle étranglait tout MOVE majeur.)
_PRESERVE = (
    "Preserve ONLY the architectural identity of the room — the walls, windows, doors, "
    "openings, ceiling and overall structure and volume — unless a change above explicitly "
    "alters it. The furniture is NOT fixed: its layout, positions and the functional "
    "arrangement are fully editable. Freely move, rotate, remove, replace and reorganize the "
    "furniture and decor — including the OTHER pieces — as needed to realize the changes above "
    "coherently and realistically. Keep it the SAME room: same architecture, same overall style "
    "and same lighting mood."
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
    estimated_success: float = 1.0      # [0,1] proba que TOUT s'applique en 1 gen (matrice)

    @property
    def combined_prompt(self) -> str:
        """Compat : le prompt de la stratégie courante (à génération unique)."""
        return self.strategy.prompt


def _order_key(c: Change) -> tuple[int, ...]:
    return (_ORDER.get(c.type, 9),)


def _estimated_success(ordered: list[Change]) -> float:
    """Proba (approx. matrice) que TOUS les changements passent en 1 gen = produit des
    priors par type (indépendance approchée). Purement matriciel — permettra plus tard
    `estimated_success < seuil → Advisor YELLOW` sans re-architecturer."""
    if not ordered:
        return 1.0
    p = 1.0
    for c in ordered:
        p *= _SUCCESS_PRIOR.get(c.type, 0.80)
    return round(p, 3)


# Mandat structurel — ajouté à la clause de préservation UNIQUEMENT quand le plan contient
# un `type=structure` (piloté par les Change[], pas par des phrases). Généralise le principe :
# on ne préserve jamais l'élément que l'utilisateur demande explicitement de modifier.
_STRUCT_MANDATE = (
    "The structural change(s) above are EXPLICIT and take PRIORITY over preservation: realize "
    "them as REAL architectural modifications — the targeted wall, window or opening is genuinely "
    "removed, added or closed. Do NOT preserve the element being changed; preserve only the REST "
    "of the architecture. "
)


def _preserve_clause(changes: list[Change]) -> str:
    """Clause de préservation DYNAMIQUE : architecture seule + mobilier libre, et si un
    changement `structure` est présent, on préfixe le mandat structurel (priorité + exclusion
    de l'élément ciblé). Aucune règle basée sur des formulations particulières."""
    if any(c.type == "structure" for c in changes):
        return _STRUCT_MANDATE + _PRESERVE
    return _PRESERVE


def build_combined_prompt(changes: list[Change]) -> str:
    """Assemble le prompt combiné : checklist ordonnée + clause de préservation dynamique
    (architecture seule ; mobilier libre ; mandat structurel si structure explicite)."""
    lines = "\n".join(f"({i + 1}) {c.normalized or c.raw}" for i, c in enumerate(changes))
    return f"Apply ALL of these changes to this interior photo:\n{lines}\n\n{_preserve_clause(changes)}"


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
        estimated_success=_estimated_success(ordered),
    )
