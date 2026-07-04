"""Refine Engine V2 — validation Composant 6 (Orchestrateur), MOCK (no image/vision).
Run: PYTHONPATH=. python _refine_engine_validation.py"""
import asyncio
import sys

import refine.engine as engine
from refine.parser import Change
from refine.verify import VerifyResult

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

# ── mocks (remplacent l'appel image + l'appel vision) ─────────────────────────
_captured = {}
async def _fake_execute(client, image_bytes, mime, prompt):
    _captured["prompt"] = prompt; _captured["src"] = image_bytes
    return b"EDITED_IMAGE_BYTES"
def _fake_verify_factory(applied_by_type):
    async def _fake_verify(client, original, omime, edited, changes):
        applied = [applied_by_type.get(c.type, True) for c in changes]
        return VerifyResult(applied=applied, identity_preserved=True, needs_refinement=False)
    return _fake_verify

engine.execute = _fake_execute


async def main():
    print("=== refine_step (défaut) ===")
    engine.verify = _fake_verify_factory({"remove": True, "add": True, "move": False})
    chs = [Change("move","move the TV","","move the TV to the left"),
           Change("add","flowers","","add flowers"),
           Change("remove","table","","remove the table")]
    out = await engine.refine_step(object(), b"SRC", "image/jpeg", chs, mode="default")
    check("image = sortie de l'executor", out.image == b"EDITED_IMAGE_BYTES")
    check("changes ordonnés remove→add→move", [c.type for c in out.changes] == ["remove","add","move"], str([c.type for c in out.changes]))
    check("missing = [move]", [c.type for c in out.missing] == ["move"])
    check("complete = False", out.complete is False)
    check("report contient '□'", out.report and "□" in out.report)
    check("prompt exécuté = prompt planifié (checklist+Locked)", "Locked elements" in _captured["prompt"] and "Apply ALL" in _captured["prompt"])

    print("\n=== refine (parse déterministe + défaut) ===")
    engine.verify = _fake_verify_factory({})   # tout appliqué
    out2 = await engine.refine(object(), b"SRC", "image/jpeg",
                               "move the TV to the left, add flowers, remove the table")
    check("3 changements parsés+tentés", len(out2.changes) == 3, str([c.type for c in out2.changes]))
    check("tout appliqué → complete=True", out2.complete is True)
    check("report = None (image seule, P3)", out2.report is None)
    check("src transmis à l'executor", _captured["src"] == b"SRC")

    print("\n=== refine_retry (cible les manquants) ===")
    engine.verify = _fake_verify_factory({"move": True})
    missing = [Change("move","TV","","move the TV to the left")]
    out3 = await engine.refine_retry(object(), b"PREV_IMAGE", "image/png", missing)
    check("mode=retry", out3.mode == "retry")
    check("ne cible que le manquant (move)", [c.type for c in out3.changes] == ["move"])
    check("retry sur l'image précédente", _captured["src"] == b"PREV_IMAGE")
    check("complete=True après retry", out3.complete is True)

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(asyncio.run(main()))
