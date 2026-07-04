"""Refine Engine V2 — Composant 6 : ORCHESTRATEUR.

Compose Planner → Executor → Verify en **UNE étape = UNE génération** (R1).
La même étape sert le DÉFAUT (tous les changements) et le RETRY (les manquants).
Le « séquentiel » du benchmark émerge ENTRE les clics (chaque retry cible moins).

Contrat : 1 appel = 1 génération = 1 image (toujours renvoyée, même incomplète).
Moteur 2 isolé : n'importe NI main NI le composer/DNA/preserve.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from refine.parser import Change, parse_changes
from refine.normalizer import normalize_changes
from refine.conflict import resolve_conflicts
from refine.planner import plan, STRATEGY_COMBINED_EDIT
from refine.executor import execute
from refine.verify import verify, build_report, missing_changes, VerifyResult


@dataclass
class RefineOutcome:
    image: bytes                 # l'image générée — TOUJOURS affichée
    changes: list[Change]        # les changements tentés à cette étape (ordonnés)
    result: VerifyResult
    report: Optional[str]        # None si complet (P3 : image seule)
    mode: str                    # "default" | "retry"
    conflicts: list[str]         # incohérences résolues par le Conflict Resolver (log/transparence)

    @property
    def missing(self) -> list[Change]:
        return missing_changes(self.result, self.changes)

    @property
    def complete(self) -> bool:
        # complet = vérif réussie ET tout appliqué ET pas de souci naturalness.
        # VERIFICATION_UNAVAILABLE ⇒ jamais complet (on ne prétend pas au succès).
        return self.result.all_applied and not self.result.needs_refinement

    @property
    def verification_available(self) -> bool:
        return self.result.available

    @property
    def retry_targets(self) -> list[Change]:
        """Ce que le bouton Retry re-tente : les manquants en INCOMPLETE ;
        TOUT en VERIFICATION_UNAVAILABLE (on ignore ce qui manque) ; rien si complet."""
        if not self.result.available:
            return list(self.changes)
        return self.missing


async def _execute_strategy(client, image_bytes: bytes, mime: str, p) -> bytes:
    """Seam d'exécution : branche sur `p.strategy.kind`. Aujourd'hui une seule
    stratégie (combined_edit → 1 génération). Les futures (full_redesign,
    atmosphere_switch, sequential_forced) s'ajoutent ici sans toucher le reste."""
    if p.strategy.kind == STRATEGY_COMBINED_EDIT:
        return await execute(client, image_bytes, mime, p.strategy.prompt)
    raise NotImplementedError(f"execution strategy not implemented: {p.strategy.kind}")


async def refine_step(client, image_bytes: bytes, mime: str, changes: list[Change],
                      *, mode: str = "default") -> RefineOutcome:
    """UNE génération : resolve(conflits) → plan → execute → verify → report. = 1 crédit."""
    changes, conflicts = resolve_conflicts(changes)   # Normalizer → Conflict Resolver → Planner
    p = plan(changes, mode=mode)
    edited = await _execute_strategy(client, image_bytes, mime, p)
    result = await verify(client, image_bytes, mime, edited, p.ordered_changes)
    report = build_report(result, p.ordered_changes)
    return RefineOutcome(image=edited, changes=p.ordered_changes, result=result,
                         report=report, mode=mode, conflicts=conflicts)


async def refine(client, image_bytes: bytes, mime: str, message: str,
                 *, parse_client=None) -> RefineOutcome:
    """DÉFAUT : parse+normalize le message → 1 génération sur tous les changements.
    `parse_client` (optionnel) = client LLM pour le Parser ; sinon fallback déterministe."""
    changes = normalize_changes(await parse_changes(message, client=parse_client))
    if not changes:
        # rien de parsable → on tente quand même le message brut comme 1 modify
        changes = normalize_changes([Change(type="modify", object="", detail="", raw=message.strip())])
    return await refine_step(client, image_bytes, mime, changes, mode="default")


async def refine_retry(client, prev_image: bytes, mime: str,
                       missing: list[Change]) -> RefineOutcome:
    """RETRY (opt-in) : 1 génération CIBLÉE sur les seuls changements manquants,
    sur l'image précédente. = +1 crédit consenti. Même contrat 1 clic = 1 gen."""
    return await refine_step(client, prev_image, mime, missing, mode="retry")
