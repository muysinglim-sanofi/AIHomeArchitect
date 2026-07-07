"""Refine Engine V2 — test ASGI des endpoints /refine + /refine/verify (ISOLATION).

Prouve : advisory (YELLOW/RED → 0 génération), completed (image immédiate + verify deferred),
/refine/verify (verified/incomplete/unavailable). Prouve l'ISOLATION : le chemin advisory ne
déclenche AUCUNE génération ; /generate reste enregistré et intact. I/O mockées (pas d'appel
réel OpenAI/Supabase/réseau). Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_endpoint_asgi_test.py"""
import asyncio
import json
import os
import sys

# This suite validates the HISTORICAL refine behaviour (token inherited verbatim),
# which is the `double` branch. The kill-switch default is now `off` (empties the
# inherited token), so pin double here to keep testing the inherit path.
os.environ["STRUCTURAL_CAPTURE_MODE"] = "double"

from httpx import ASGITransport, AsyncClient

import main
from refine.parser import Change
from refine.advisor import AdviceResult, ChangeAdvice, Verdict
from refine.engine import GenerateResult
from refine.verify import VerifyResult, VerifyStatus

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

class _FakeUser:
    user_id = "user-123"; is_anonymous = False

_calls = {"gen": 0, "upload": 0, "advise": 0, "verify": 0}

# ── mocks (aucune I/O réelle) ────────────────────────────────────────────────
async def _fake_ownership(*, session_id, user_id): return True
async def _fake_parse(message, client=None):
    # 1 changement par message (raw = message), type déduit grossièrement
    t = "add" if "add" in message.lower() else ("move" if "move" in message.lower() else "modify")
    return [Change(type=t, object="thing", detail="", raw=message)]
async def _fake_fetch(url): return b"SRCIMG", "image/jpeg"
def _fake_upload(session_id, data):
    _calls["upload"] += 1
    assert data == b"GENIMG", "upload doit recevoir l'image du moteur"
    return "https://storage.example/generated/refine123.jpg"
async def _fake_generate(client, image_bytes, mime, changes, *, mode="default"):
    _calls["gen"] += 1
    return GenerateResult(image=b"GENIMG", changes=changes, conflicts=[], estimated_success=0.9)

def _advise_factory(verdict):
    async def _fake_advise(changes, room_type, client=None):
        _calls["advise"] += 1
        adv = [ChangeAdvice(change=c, verdict=verdict, source="rules", confidence=0.9,
                            reason="not plausible here", alternative="place it outside")
               for c in changes]
        return AdviceResult(advices=adv)
    return _fake_advise

def _verify_factory(status):
    async def _fake_verify(client, original, omime, edited, changes):
        _calls["verify"] += 1
        applied = [True] * len(changes) if status == VerifyStatus.VERIFIED else [False] * len(changes)
        return VerifyResult(status=status, applied=applied if status != VerifyStatus.VERIFICATION_UNAVAILABLE else [])
    return _fake_verify


async def _post(client, path, data):
    return await client.post(path, data=data)


async def main_test():
    main.app.dependency_overrides[main.get_current_user] = lambda: _FakeUser()
    main._validate_session_ownership = _fake_ownership
    main._refine_parse = _fake_parse
    main._refine_fetch_bytes = _fake_fetch
    main._refine_upload = _fake_upload
    main._refine_generate = _fake_generate
    _persist_calls = []
    def _fake_persist(session_id, before_url, after_url, style_label):
        _persist_calls.append((session_id, after_url, style_label)); return True
    main._refine_persist_message = _fake_persist

    transport = ASGITransport(app=main.app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        # ── 1) ADVISORY (RED) → 0 génération ────────────────────────────────
        main._refine_advise = _advise_factory(Verdict.RED)
        _calls.update(gen=0, upload=0, advise=0)
        r = await _post(c, "/refine", {"session_id": "s1", "message": "add a Ferrari",
                                       "before_image_url": "https://x/a.jpg", "room_type": "bathroom"})
        j = r.json()
        check("advisory: HTTP 200", r.status_code == 200, r.status_code)
        check("advisory: status=advisory", j.get("status") == "advisory", j)
        check("advisory: message présent", bool(j.get("advice", {}).get("message")))
        check("advisory: flagged non vide", len(j.get("advice", {}).get("flagged", [])) == 1)
        check("advisory: echo.changes présent (relance stateless)", "changes" in j.get("echo", {}))
        check("ISOLATION: AUCUNE génération sur advisory", _calls["gen"] == 0, _calls["gen"])
        check("ISOLATION: AUCUN upload sur advisory", _calls["upload"] == 0, _calls["upload"])

        # ── 2) COMPLETED (GREEN) → image immédiate + verification deferred + LEDGER ──
        main._refine_advise = _advise_factory(Verdict.GREEN)
        _calls.update(gen=0, upload=0, advise=0)
        r = await _post(c, "/refine", {"session_id": "s1", "message": "move the sofa left",
                                       "before_image_url": "https://x/a.jpg", "room_type": "living room",
                                       "structural_identity": "TOKEN_ABC", "versions": "[]",
                                       "style_label": "Warm Modern", "iteration": "3"})
        j = r.json()
        check("completed: status=completed", j.get("status") == "completed", j)
        check("completed: after_image_url (contrat /generate)", j.get("after_image_url", "").startswith("https://"))
        check("completed: image_url alias", j.get("image_url", "").startswith("https://"))
        check("completed: verification=deferred (async)", j.get("verification") == "deferred", j.get("verification"))
        check("completed: estimated_success présent", isinstance(j.get("estimated_success"), (int, float)))
        check("completed: changes echo présent", len(j.get("changes", [])) == 1)
        check("completed: 1 génération", _calls["gen"] == 1, _calls["gen"])
        check("completed: 1 upload", _calls["upload"] == 1, _calls["upload"])
        # LEDGER adapter (orchestration) — refine = version 1re classe
        check("ledger: structural_identity HÉRITÉ (echo verbatim)", j.get("structural_identity") == "TOKEN_ABC", j.get("structural_identity"))
        check("ledger: version_id présent", isinstance(j.get("version_id"), str) and j.get("version_id").startswith("v_"))
        check("ledger: version_record.generated_image_url = image", (j.get("version_record") or {}).get("generated_image_url") == j.get("image_url"))
        check("ledger: version_record hérite le token", (j.get("version_record") or {}).get("structural_identity_token") == "TOKEN_ABC")
        check("ledger: version_record.vision_number = iteration", (j.get("version_record") or {}).get("vision_number") == 3)
        check("ledger: versions sérialisé non vide", isinstance(j.get("versions"), str) and len(j.get("versions")) > 2)
        check("ledger: source_mode_used = REFINE", (j.get("version_record") or {}).get("source_mode_used") == "REFINE")
        # Q1 fix — persistance serveur du message (ferme la fenêtre kill post-gen/pré-insert)
        check("Q1: message persisté serveur (message_persisted=True)", j.get("message_persisted") is True, j.get("message_persisted"))
        check("Q1: persist appelé avec l'after_image_url", len(_persist_calls) == 1 and _persist_calls[0][1] == j.get("image_url"))

        # ── 3) CONFIRM=true → saute l'Advisor (Continue anyway) ─────────────
        main._refine_advise = _advise_factory(Verdict.RED)
        _calls.update(gen=0, upload=0, advise=0)
        r = await _post(c, "/refine", {"session_id": "s1", "message": "add a Ferrari",
                                       "before_image_url": "https://x/a.jpg", "room_type": "bathroom",
                                       "confirm": "true"})
        j = r.json()
        check("confirm: status=completed (advisor sauté)", j.get("status") == "completed", j)
        check("confirm: Advisor NON appelé", _calls["advise"] == 0, _calls["advise"])
        check("confirm: génération faite", _calls["gen"] == 1, _calls["gen"])

        # ── 4) /refine/verify (stateless) ──────────────────────────────────
        main._refine_verify = _verify_factory(VerifyStatus.INCOMPLETE)
        changes_json = json.dumps([{"type": "move", "object": "sofa", "detail": "", "raw": "move the sofa left"}])
        r = await _post(c, "/refine/verify", {"before_image_url": "https://x/a.jpg",
                                              "after_image_url": "https://x/b.jpg", "changes": changes_json})
        j = r.json()
        check("verify: verification=incomplete", j.get("verification") == "incomplete", j)
        check("verify: report présent", bool(j.get("report")))
        check("verify: missing = [move]", len(j.get("missing", [])) == 1 and j["missing"][0]["type"] == "move")

        main._refine_verify = _verify_factory(VerifyStatus.VERIFIED)
        r = await _post(c, "/refine/verify", {"before_image_url": "https://x/a.jpg",
                                              "after_image_url": "https://x/b.jpg", "changes": changes_json})
        j = r.json()
        check("verify: verified → report None + missing []", j.get("verification") == "verified" and j.get("report") is None and j.get("missing") == [], j)

        r = await _post(c, "/refine/verify", {"before_image_url": "https://x/a.jpg",
                                              "after_image_url": "https://x/b.jpg", "changes": "[]"})
        j = r.json()
        check("verify: changes vide → unavailable honnête", j.get("verification") == "unavailable", j)

    # ── 5) ISOLATION structurelle : /generate intact ───────────────────────
    routes = {getattr(r, "path", None) for r in main.app.routes}
    check("ISOLATION: /refine enregistré", "/refine" in routes)
    check("ISOLATION: /refine/verify enregistré", "/refine/verify" in routes)
    check("ISOLATION: /generate toujours présent (inchangé)", "/generate" in routes)

    main.app.dependency_overrides.clear()
    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(asyncio.run(main_test()))
