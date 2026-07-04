"""Refine Engine V2 — Composant 5 : VERIFY (GRATUIT, invisible).

Vision gpt-4o-mini (~$0.0001, **PAS une génération**) : compare l'image ORIGINALE
à l'image ÉDITÉE et juge, PAR changement, s'il est appliqué ; + identité préservée
(cadrage IGNORÉ) + naturalness. C'est ce qui permet la transparence sans casser
« 1 action = 1 génération ». Bâtit le rapport Applied/Missing (P3, visible seulement
si incomplet ; P4 message naturalness DOUX). Aucun appel image.

3 ÉTATS (honnêteté — jamais « fail-open menteur ») :
  • VERIFIED                 → tous les changements sont visiblement appliqués
  • INCOMPLETE               → la vérif a réussi, certains changements manquent
  • VERIFICATION_UNAVAILABLE → la vérif elle-même a échoué → on NE prétend JAMAIS
                               « tout appliqué » ; message honnête à l'utilisateur
Un changement non confirmé (vision tronquée) est compté MANQUANT, jamais « appliqué ».
"""
from __future__ import annotations

import base64
import json
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

from refine.parser import Change

_VERIFY_MODEL = "gpt-4o-mini"


class VerifyStatus(str, Enum):
    VERIFIED = "verified"                              # tout appliqué
    INCOMPLETE = "incomplete"                          # vérif OK, il manque des changements
    VERIFICATION_UNAVAILABLE = "verification_unavailable"  # la vérif a échoué (aucune prétention)


@dataclass
class VerifyResult:
    status: VerifyStatus
    applied: list[bool] = field(default_factory=list)  # aligné 1:1 (vide si UNAVAILABLE)
    identity_preserved: bool = True                    # même appartement (cadrage/caméra IGNORÉS)
    needs_refinement: bool = False                     # naturalness KO (artefacts) → message doux

    @property
    def all_applied(self) -> bool:
        """Vrai UNIQUEMENT si la vérif a réussi ET que tout est appliqué.
        VERIFICATION_UNAVAILABLE ⇒ False (on ne prétend jamais avoir tout appliqué)."""
        return self.status == VerifyStatus.VERIFIED

    @property
    def available(self) -> bool:
        return self.status != VerifyStatus.VERIFICATION_UNAVAILABLE


def missing_changes(result: VerifyResult, changes: list[Change]) -> list[Change]:
    """Changements à re-tenter en INCOMPLETE. En UNAVAILABLE on ne SAIT pas ce qui
    manque → [] ici (l'appelant fait « retry all » avec la liste complète)."""
    if result.status != VerifyStatus.INCOMPLETE:
        return []
    return [c for c, ok in zip(changes, result.applied) if not ok]


def _uri(b: bytes, mime: str) -> str:
    return f"data:{mime};base64," + base64.b64encode(b).decode()


async def verify(client, original: bytes, original_mime: str, edited: bytes,
                 changes: list[Change]) -> VerifyResult:
    """Vision : renvoie un VerifyResult à 3 états.
    Sur erreur/JSON invalide → VERIFICATION_UNAVAILABLE (jamais « tout appliqué »).
    L'image est TOUJOURS livrée par l'orchestrateur — un doute de vérif ne la bloque
    pas, mais il ne la déguise pas non plus en succès."""
    n = len(changes)
    if n == 0:
        return VerifyResult(status=VerifyStatus.VERIFIED, applied=[])
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
        if not applied:
            raise ValueError("no 'applied' array")
        # non confirmé (vision tronquée) → compté MANQUANT (jamais « appliqué »), surplus tronqué
        if len(applied) < n:
            applied += [False] * (n - len(applied))
        applied = applied[:n]
        status = VerifyStatus.VERIFIED if all(applied) else VerifyStatus.INCOMPLETE
        return VerifyResult(
            status=status,
            applied=applied,
            identity_preserved=bool(data.get("identity_preserved", True)),
            needs_refinement=not bool(data.get("naturalness_ok", True)),
        )
    except Exception:  # noqa: BLE001 — vérif indisponible : honnête, jamais « tout appliqué »
        return VerifyResult(status=VerifyStatus.VERIFICATION_UNAVAILABLE, applied=[])


def build_report(result: VerifyResult, changes: list[Change]) -> Optional[str]:
    """Rapport user (P3).
      • VERIFICATION_UNAVAILABLE → message honnête (image montrée quand même).
      • VERIFIED sans souci naturalness → None (on n'affiche QUE l'image).
      • sinon → Applied ✓ / Still missing □ (+ P4 naturalness doux)."""
    if result.status == VerifyStatus.VERIFICATION_UNAVAILABLE:
        return "Ayden couldn't automatically verify this result."
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
