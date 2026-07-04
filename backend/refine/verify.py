"""Refine Engine V2 — Composant 5 : VERIFY (GRATUIT, invisible).

Vision gpt-4o-mini (~$0.0001, **PAS une génération**) : compare l'image ORIGINALE
à l'image ÉDITÉE et juge, PAR changement, s'il est appliqué ; + identité préservée
(cadrage IGNORÉ) + naturalness. C'est ce qui permet la transparence sans casser
« 1 action = 1 génération ». Bâtit le rapport Applied/Missing (P3, visible seulement
si incomplet ; P4 message naturalness DOUX). Aucun appel image.
"""
from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from typing import Optional

from refine.parser import Change

_VERIFY_MODEL = "gpt-4o-mini"


@dataclass
class VerifyResult:
    applied: list[bool]          # aligné 1:1 avec la liste de changements
    identity_preserved: bool     # même appartement (cadrage/caméra IGNORÉS)
    needs_refinement: bool       # naturalness KO (artefacts) → message doux

    @property
    def all_applied(self) -> bool:
        return bool(self.applied) and all(self.applied)


def missing_changes(result: VerifyResult, changes: list[Change]) -> list[Change]:
    return [c for c, ok in zip(changes, result.applied) if not ok]


def _uri(b: bytes, mime: str) -> str:
    return f"data:{mime};base64," + base64.b64encode(b).decode()


async def verify(client, original: bytes, original_mime: str, edited: bytes,
                 changes: list[Change]) -> VerifyResult:
    """Vision : renvoie applied[] (len == len(changes)) + identité + naturalness.
    Best-effort : sur erreur, on considère TOUT appliqué (ne bloque pas l'user ;
    fail-open — un doute de vérif ne doit pas transformer une image livrée en échec)."""
    n = len(changes)
    if n == 0:
        return VerifyResult(applied=[], identity_preserved=True, needs_refinement=False)
    lst = "\n".join(f"({i + 1}) {c.raw}" for i, c in enumerate(changes))
    schema = '{"applied":[' + ",".join(["bool"] * n) + '],"identity_preserved":bool,"naturalness_ok":bool}'
    user = [
        {"type": "text", "text": "ORIGINAL image:"},
        {"type": "image_url", "image_url": {"url": _uri(original, original_mime), "detail": "low"}},
        {"type": "text", "text": "EDITED image:"},
        {"type": "image_url", "image_url": {"url": _uri(edited, "image/png"), "detail": "low"}},
        {"type": "text", "text":
            f"Requested changes:\n{lst}\n\n"
            f"Return ONLY JSON: {schema}. "
            '"applied" has EXACTLY one boolean per requested change (true iff that change is '
            "visibly applied in EDITED vs ORIGINAL). "
            "identity_preserved=true if EDITED is still the SAME apartment (same architecture, "
            "walls, windows, floor, overall style, and the furniture NOT asked to change) — "
            "IGNORE camera angle, framing and repositioning (a shifted composition is FINE); "
            "false ONLY if it became a different room/architecture/style. "
            "For STRUCTURE changes require a GENUINE structural change (a real new/removed wall or "
            "opening), not a mere recomposition. "
            "naturalness_ok=false if the edited image has obvious artefacts / broken geometry / "
            "unrealistic rendering."},
    ]
    try:
        r = await client.chat.completions.create(
            model=_VERIFY_MODEL, temperature=0, max_tokens=200,
            messages=[{"role": "system", "content": "Judge strictly. JSON only."},
                      {"role": "user", "content": user}])
        t = (r.choices[0].message.content or "").strip().strip("`")
        data = json.loads(t[t.find("{"):t.rfind("}") + 1])
        applied = [bool(x) for x in (data.get("applied") or [])]
        # aligne la longueur (robustesse) : manquant → True (fail-open), surplus → tronqué
        if len(applied) < n:
            applied += [True] * (n - len(applied))
        applied = applied[:n]
        return VerifyResult(
            applied=applied,
            identity_preserved=bool(data.get("identity_preserved", True)),
            needs_refinement=not bool(data.get("naturalness_ok", True)),
        )
    except Exception:  # noqa: BLE001 — fail-open : ne bloque jamais l'image livrée
        return VerifyResult(applied=[True] * n, identity_preserved=True, needs_refinement=False)


def build_report(result: VerifyResult, changes: list[Change]) -> Optional[str]:
    """Rapport user (P3) : None si tout est appliqué ET pas de souci naturalness
    (dans ce cas on n'affiche QUE l'image). Sinon Applied ✓ / Still missing □."""
    if result.all_applied and not result.needs_refinement:
        return None
    applied = [c for c, ok in zip(changes, result.applied) if ok]
    missing = [c for c, ok in zip(changes, result.applied) if not ok]
    lines: list[str] = []
    if applied:
        lines.append("Applied")
        lines += [f"✓ {c.raw}" for c in applied]
    if missing:
        if lines:
            lines.append("")
        lines.append("Still missing")
        lines += [f"□ {c.raw}" for c in missing]
    if result.needs_refinement:
        if lines:
            lines.append("")
        lines.append("Ayden noticed this version may need refinement.")  # P4 — doux
    return "\n".join(lines)
