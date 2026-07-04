"""Refine Engine V2 — Composant 2.5 : CONFLICT RESOLVER (100% déterministe).

Position dans le pipeline :  Normalizer → **Conflict Resolver** → Planner.

Le smoke a prouvé que ce n'est PAS un cas rare : « remove coffee table + add flowers »
fait écrire au Normalizer « add flowers on the coffee table » — une contradiction.
On résout ces incohérences AU NIVEAU DU PIPELINE, plus jamais en cas particulier.

Règles (par objet, déterministes) :
  R-A  REMOVE/REPLACE **X** + ADD *sur X*   → re-placer l'ADD sur une surface non supprimée
  R-B  REMOVE **X** + MOVE **X**            → droppe le MOVE (on ne déplace pas un objet supprimé)
  R-C  MOVE **X** →A  +  MOVE **X** →B       → garde le dernier
  R-D  REPLACE **X** (in the same position) + MOVE **X** → retire « in the same position »
  R-E  STRUCTURE remove **wall** + ADD *sur ce mur* → re-placer l'ADD (mur supprimé)

Entrée : Change[] déjà normalisés (`.normalized` posé). Sortie : (Change[] nettoyés,
conflicts_resolved: list[str]) pour log/transparence. AUCUN LLM, AUCUN appel image.
Ne touche JAMAIS /generate, le composer, la DNA, la préservation.
"""
from __future__ import annotations

import re

from refine.parser import Change

_LOCATIVE = r"(?:on|onto|in|into|above|over|under|beneath|against|by|near|next\s+to|beside|atop)"

# Un STRUCTURE qui SUPPRIME (par opposition à ajouter un mur/une ouverture).
_STRUCT_REMOVES = re.compile(
    r"\b(remove|knock\s+down|take\s+down|demolish|break|tear\s+down|open\s+up|open)\b", re.I)

_WALL_ITEM = re.compile(
    r"\b(art|artwork|painting|mirror|frame|picture|poster|shelf|shelves|"
    r"bookshelf|bookcase|sconce|clock|tapestry)\b", re.I)


def _clean(s: str) -> str:
    return (s or "").strip().rstrip(". ").strip()


def _cap(s: str) -> str:
    s = _clean(s)
    return (s[0].upper() + s[1:]) if s else s


def _period(s: str) -> str:
    s = _clean(s)
    return (s + ".") if s else s


def _noun(change: Change) -> str:
    """Nom canonique de l'objet visé (minuscules, sans article)."""
    o = _clean(change.object).lower()
    if not o or len(o) < 2:
        m = re.search(r"\bthe\s+([a-z][a-z\s]{1,24}?)(\s+(?:to|on|with|in|into|for|near|"
                      r"toward|towards|against|next|above|below|under)\b.*)?$",
                      _clean(change.raw), re.I)
        o = (m.group(1).strip().lower() if m else _clean(change.raw).lower())
    o = re.sub(r"^(the|a|an)\s+", "", o).strip()
    return o


def _same_object(a: str, b: str) -> bool:
    if not a or not b:
        return False
    if a == b:
        return True
    return len(a) >= 3 and len(b) >= 3 and (a in b or b in a)


def _is_removal(change: Change) -> bool:
    return change.type == "remove" or (
        change.type == "structure" and bool(_STRUCT_REMOVES.search(change.raw or "")))


def _placement_conflict(text: str, noun: str) -> bool:
    """Vrai si `text` place quelque chose SUR/DANS `noun` (locative + noun, jusqu'à
    2 mots intercalés : « on the coffee table » pour noun=table)."""
    if not noun:
        return False
    pat = rf"{_LOCATIVE}\s+(?:the\s+|a\s+|an\s+)?(?:\w+\s+){{0,2}}{re.escape(noun)}\b"
    return bool(re.search(pat, text or "", re.I))


def _strip_conflicting_locative(text: str, nouns: list[str]) -> str:
    """Retire du texte toute phrase locative « <prep> ... <noun_supprimé> ... »."""
    out = text
    for n in nouns:
        out = re.sub(rf"[,;]?\s*{_LOCATIVE}\s+(?:the\s+|a\s+|an\s+)?(?:\w+\s+){{0,2}}"
                     rf"{re.escape(n)}\b[\w\s]*", "", out, flags=re.I)
    return _clean(out)


def _safe_placement(change: Change, wall_removed: bool) -> str:
    """Surface de repli qui NE nomme aucun meuble supprimé."""
    if _WALL_ITEM.search(change.raw or "") or _WALL_ITEM.search(change.object or ""):
        return "on a remaining wall" if wall_removed else "on the main wall"
    return "on the main visible surface"


def resolve_conflicts(changes: list[Change]) -> tuple[list[Change], list[str]]:
    """Détecte + résout les conflits. Retourne (changes nettoyés, notes de conflit).
    Idempotent : re-passer un résultat déjà résolu ne change rien."""
    conflicts: list[str] = []
    if not changes:
        return changes, conflicts

    removals = [c for c in changes if _is_removal(c)]
    removed_nouns = [_noun(c) for c in removals]
    removed_keys = [n for n in removed_nouns if n]
    # nouns dont le nom ne désigne plus une surface fiable pour un ADD (supprimés + remplacés)
    surface_lost = list(removed_keys) + [_noun(c) for c in changes if c.type == "replace"]
    surface_lost = [n for n in surface_lost if n]
    wall_removed = any("wall" in n or "partition" in n for n in removed_keys)
    move_keys = [_noun(c) for c in changes if c.type == "move"]

    # R-D : REPLACE X (in the same position) + MOVE X → retirer « in the same position »
    for c in changes:
        if c.type == "replace" and any(_same_object(_noun(c), mk) for mk in move_keys):
            if "same position" in (c.normalized or "").lower():
                c.normalized = _period(re.sub(r",?\s*in the same position", "",
                                              c.normalized, flags=re.I))
                conflicts.append(f"R-D: replace '{_noun(c)}' will move → dropped « in the same position »")

    kept: list[Change] = []
    last_move_idx: dict[str, int] = {}
    for c in changes:
        if c.type == "move":
            k = _noun(c)
            # R-B : objet supprimé → on ne déplace pas un fantôme
            if any(_same_object(k, rk) for rk in removed_keys):
                conflicts.append(f"R-B: dropped MOVE of '{k}' (it is being removed)")
                continue
            # R-C : deux moves du même objet → garder le dernier
            for prev_k, idx in list(last_move_idx.items()):
                if _same_object(k, prev_k) and kept[idx] is not None:
                    conflicts.append(f"R-C: MOVE of '{k}' superseded by a later MOVE")
                    kept[idx] = None
            last_move_idx[k] = len(kept)
            kept.append(c)
            continue

        if c.type == "add":
            hit = [n for n in surface_lost if _placement_conflict(c.normalized, n)
                   or _placement_conflict(c.raw, n)]
            if hit:
                head = _strip_conflicting_locative(c.raw, hit)
                if not re.match(r"(?i)^\s*(add|place|introduce|include|hang|install|put)\b", head):
                    head = f"add {head}".strip()
                c.normalized = _period(f"{_cap(head)} {_safe_placement(c, wall_removed)}")
                conflicts.append(f"R-A/R-E: re-placed ADD away from removed « {', '.join(hit)} » "
                                 f"→ {c.normalized}")
            kept.append(c)
            continue

        kept.append(c)

    kept = [c for c in kept if c is not None]
    return kept, conflicts
