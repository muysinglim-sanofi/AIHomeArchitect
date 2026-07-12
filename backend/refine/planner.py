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

# PHILOSOPHIE REFINE (user 2026-07-12) — DISTINGUER *identité* et *position* du mobilier.
# Régression observée : un refine « add flowers » redessinait le canapé. La cause = l'ancienne
# clause `_PRESERVE` autorisait le modèle à « freely move, rotate, remove, replace and reorganize
# the furniture — including the OTHER pieces ». Elle avait été introduite pour un vrai besoin (un
# MOVE peut exiger de recentrer table/fauteuil/tapis) mais confondait « réorganiser les positions »
# avec « remplacer / redessiner les meubles ». Règle correcte : **préserver l'IDENTITÉ de tous les
# meubles ; n'autoriser que les DÉPLACEMENTS nécessaires ; ne redessiner que ce qui est demandé.**
# Le contrat de préservation est désormais choisi DYNAMIQUEMENT selon l'action (voir
# `preservation_contract`). Chaque contrat reste ciblé PAR OBJET (jamais un hardcode par mot).
# PÉRIMÈTRE DE CE PATCH : ADD / MOVE / MODIFY / REMOVE / REPLACE uniquement. Le mauvais classement
# de « Redesign the entire layout » (parser → `structure`) et un contrat GLOBAL_REFLOW dédié sont
# un BUG SÉPARÉ (ticket à part) → hors scope ici ; la branche `structure` reste INCHANGÉE.

# Suffixe partagé — cohérence de la pièce (identique dans tous les contrats).
_SAME_ROOM = (" Keep it the SAME room: same architecture, same overall style and same lighting mood.")

# Interdiction SCOPÉE — préfixe partagé : tout ce qui n'est PAS explicitement listé reste verrouillé,
# MAIS les actions co-demandées de la checklist (plans mixtes) ne sont jamais contredites.
_EXCEPT = " Apart from the change(s) explicitly listed above, do NOT "

# `_PRESERVE` — base HISTORIQUE (mobilier libre). CONSERVÉE UNIQUEMENT pour la branche `structure`
# (validée 6/6 sur les benchs muraux — non re-benchée ici, donc inchangée à dessein).
_PRESERVE = (
    "Preserve ONLY the architectural identity of the room — the walls, windows, doors, "
    "openings, ceiling and overall structure and volume — unless a change above explicitly "
    "alters it. The furniture is NOT fixed: its layout, positions and the functional "
    "arrangement are fully editable. Freely move, rotate, remove, replace and reorganize the "
    "furniture and decor — including the OTHER pieces — as needed to realize the changes above "
    "coherently and realistically." + _SAME_ROOM
)

# ── Contrats de préservation par action (ciblés PAR OBJET) ───────────────────────────────────
# Chaque interdiction est SCOPÉE (`_EXCEPT`) → sur un plan mixte, l'autre action demandée reste
# permise (elle figure dans la checklist), mais aucun meuble NON demandé n'est touché.
# ADD : ajoute seulement ce qui est demandé — rien d'autre ne bouge (ni position ni identité).
ADD_ONLY_CONTRACT = (
    "ADD-ONLY CONTRACT. Add ONLY the object(s) or decoration explicitly requested above. "
    "Preserve every existing furniture item, object, architectural element, material, colour, "
    "position, design, proportion and count EXACTLY as they are." + _EXCEPT +
    "reorganize, redesign, move, replace, recolour, resize, add or remove anything." + _SAME_ROOM
)

# MODIFY ciblé : même objet, seule la propriété demandée change ; le reste verrouillé.
TARGETED_MODIFY_CONTRACT = (
    "TARGETED MODIFY CONTRACT. For each explicitly targeted object, apply ONLY the requested change, "
    "altering only the specified property (e.g. colour, material or finish); that object stays the "
    "SAME object — same model, shape, proportions and position — only the requested property changes. "
    "Preserve the exact identity, design, position and count of every OTHER furniture item, object "
    "and architectural element." + _EXCEPT +
    "move, replace, restyle, resize, add or remove anything." + _SAME_ROOM
)

# MOVE ciblé + REFLOW LOCAL : le MÊME objet déplacé ; voisins repositionnables SI nécessaire,
# jamais redessinés. (Reprend le contrat recommandé par l'user.)
MOVE_WITH_LOCAL_REFLOW_CONTRACT = (
    "PRESERVATION AND LOCAL REFLOW CONTRACT. Preserve the exact identity, design, shape, colour, "
    "material, proportions, style and count of every existing furniture item. Apply the requested "
    "change(s) to the explicitly targeted object(s). For a MOVE, move the SAME original object — do "
    "NOT generate a different version of it. When a requested change requires space, you MAY "
    "reposition or slightly rotate NEARBY furniture only as necessary to create a coherent, "
    "physically realistic layout; repositioning nearby objects does NOT authorize redesigning them." +
    _EXCEPT + "replace, remove, add, recolour, restyle, resize or materially alter any furniture "
    "or architectural element." + _SAME_ROOM
)

# REMOVE ciblé : seul l'objet ciblé disparaît ; voisins recentrables mais jamais remplacés.
TARGETED_REMOVE_CONTRACT = (
    "TARGETED REMOVE CONTRACT. Remove ONLY the explicitly targeted object(s), leaving the freed "
    "floor/wall area coherent and empty. Preserve the exact identity, design, colour, material, "
    "proportions and count of every OTHER furniture item and architectural element; you MAY recentre "
    "or slightly reposition nearby objects only if the freed space would otherwise look unnatural." +
    _EXCEPT + "replace, redesign, recolour, resize, add or remove any item." + _SAME_ROOM
)

# REPLACE ciblé : seul l'objet ciblé est remplacé, même position ; le reste verrouillé.
TARGETED_REPLACE_CONTRACT = (
    "TARGETED REPLACE CONTRACT. Replace ONLY the explicitly targeted object(s) with the requested "
    "one(s), in the same position; you MAY adjust the new object's size, height and lighting as "
    "needed for realism. Preserve the exact identity, design, colour, material, proportions, "
    "position and count of every OTHER furniture item and architectural element." + _EXCEPT +
    "move, replace, restyle, recolour, resize, add or remove anything." + _SAME_ROOM
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


def preservation_contract(changes: list[Change]) -> str:
    """SÉLECTEUR PUR (Phase 2) — choisit le contrat de préservation selon le PLAN, ciblé PAR
    OBJET. Ordre = précédence (le plus permissif-en-POSITION gagne quand plusieurs types
    coexistent, sans jamais autoriser le remplacement/redesign d'un meuble NON ciblé) :

      1. structure présente   → _STRUCT_MANDATE + _PRESERVE  (INCHANGÉ — validé 6/6, hors scope)
      2. ADD seul             → ADD_ONLY_CONTRACT
      3. MOVE présent         → MOVE_WITH_LOCAL_REFLOW_CONTRACT
      4. REMOVE présent       → TARGETED_REMOVE_CONTRACT
      5. REPLACE présent      → TARGETED_REPLACE_CONTRACT
      6. sinon (MODIFY ciblé) → TARGETED_MODIFY_CONTRACT

    Plans MIXTES : la précédence choisit le contrat dont la liberté de POSITION couvre le plan ;
    chaque interdiction étant scopée (`_EXCEPT`), les autres actions demandées restent permises.
    N'est JAMAIS « ADD=verrouillé / le reste=tout libre » : chaque branche verrouille l'IDENTITÉ
    du mobilier non ciblé et n'autorise le reflow de POSITION que là où l'action l'exige."""
    if not changes:
        return ADD_ONLY_CONTRACT           # sûr : rien à faire → tout verrouillé (garde-fou)
    types = [c.type for c in changes]
    if "structure" in types:
        return _STRUCT_MANDATE + _PRESERVE  # branche structure validée séparément — inchangée
    if all(t == "add" for t in types):
        return ADD_ONLY_CONTRACT
    if "move" in types:
        return MOVE_WITH_LOCAL_REFLOW_CONTRACT
    if "remove" in types:
        return TARGETED_REMOVE_CONTRACT
    if "replace" in types:
        return TARGETED_REPLACE_CONTRACT
    return TARGETED_MODIFY_CONTRACT


# Compat : `build_combined_prompt` appelle toujours `_preserve_clause` (point d'intégration inchangé).
def _preserve_clause(changes: list[Change]) -> str:
    return preservation_contract(changes)


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
