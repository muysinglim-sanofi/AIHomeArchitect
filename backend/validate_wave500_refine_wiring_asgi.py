"""Phase 1 — /refine RECÂBLÉ sur le Generation Orchestrator (test ASGI d'intégration).
I/O mockées (0 OpenAI, 0 Supabase, 0 réseau). Store d'intents en mémoire.

Couvre : RED/YELLOW (0 claim/gen) · GREEN (1 gen + VersionRecord REFINE) · même op_id
RUNNING (0 gen) · même op_id SUCCEEDED (replay) · FAILED (pas de réouverture) · nouvel
op_id (nouvelle gen) · transient→retry · erreur persist (pas de 2e OpenAI) · /by-id owner.
"""
import os, sys, asyncio, json
os.environ["STRUCTURAL_CAPTURE_MODE"] = "double"   # tester le chemin héritage-verbatim
sys.path.insert(0, os.path.dirname(__file__))

import logging
import httpx
from httpx import ASGITransport, AsyncClient
import main, intent_observer, billing
logging.disable(logging.CRITICAL)
from intent_observer import ClaimResult
from refine.parser import Change
from refine.advisor import AdviceResult, ChangeAdvice, Verdict
from refine import orchestrator_adapter as ADP

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

class _User: user_id = "user-123"; is_anonymous = False

STORE = {}                 # intent_id -> {status, result_ref}
CNT = {"exec": 0}
EXEC_BEHAVIOR = {"fn": None}


async def _claim(**kw):
    iid = kw["intent_id"]
    if iid in STORE:
        row = STORE[iid]
        return ClaimResult(won=False, status=row["status"], result_ref=row.get("result_ref"))
    STORE[iid] = {"status": "RUNNING", "result_ref": None}
    return ClaimResult(won=True, status="RUNNING")

async def _observe_end(iid, status, *, result_ref=None, error=None, is_free=True, supa=None):
    if iid in STORE:
        STORE[iid]["status"] = status
        if result_ref is not None: STORE[iid]["result_ref"] = result_ref
    return True

async def _get_ref(iid, *, supa=None): return (STORE.get(iid) or {}).get("result_ref")
async def _set_ref(iid, ref, *, supa=None):
    if iid in STORE: STORE[iid]["result_ref"] = ref
    return True
async def _job_start(iid, a, *, supa=None): return "job"
async def _job_end(*a, **k): pass
async def _bill(**k): pass
async def _fetch(url): return b"SRC", "image/jpeg"
async def _upload_det(path, data): return "https://storage/x/" + path
async def _msg_idem(*a, **k): return True

async def _exec(ctx):
    CNT["exec"] += 1
    fn = EXEC_BEHAVIOR["fn"]
    return await fn(ctx, CNT["exec"]) if fn else b"GENIMG"

async def _parse(message, client=None):
    return [Change(type="add", object="thing", detail="", raw=message)]

def _advise(verdict):
    async def _f(changes, room_type, client=None):
        return AdviceResult(advices=[ChangeAdvice(change=c, verdict=verdict, source="rules",
                            confidence=0.9, reason="r", alternative="alt") for c in changes])
    return _f


def _reset(exec_fn=None):
    STORE.clear(); CNT["exec"] = 0; EXEC_BEHAVIOR["fn"] = exec_fn


async def _post(c, data):
    return await c.post("/refine", data=data)

BASE = {"session_id": "sess-1", "before_image_url": "https://x/a.jpg", "room_type": "Living Room",
        "iteration": "2", "style_label": "warm_modern", "source_version_id": "vSrc",
        "confirm": "true"}   # confirm=true → advisor sauté (on teste GREEN direct)


async def run():
    main.app.dependency_overrides[main.get_current_user] = lambda: _User()
    main._validate_session_ownership = lambda *, session_id, user_id: _ok_true()
    main._refine_parse = _parse
    main._refine_fetch_bytes = _fetch
    main._refine_upload_deterministic = _upload_det
    main._refine_persist_message_idempotent = _msg_idem
    intent_observer.claim_generation_intent = _claim
    intent_observer.observe_intent_end = _observe_end
    intent_observer.observe_job_start = _job_start
    intent_observer.observe_job_end = _job_end
    intent_observer.get_intent_result_ref = _get_ref
    intent_observer.set_intent_result_ref = _set_ref
    billing.apply_billing_for_intent_transition = _bill
    ADP._executor_execute = lambda client, b, m, prompt: _noop_bytes()   # placeholder; overridden below
    # l'adaptateur build_execute_fn appelle _executor_execute → on route vers notre _exec
    import refine.orchestrator_adapter as _adp
    async def _exec_route(client, b, m, prompt):
        class _C:  # ctx minimal suffisant (image_bytes/mime non utilisés par le mock)
            pass
        return await _exec(_C())
    _adp._executor_execute = _exec_route

    tr = ASGITransport(app=main.app)
    async with AsyncClient(transport=tr, base_url="http://t") as c:
        print("\n=== 1. Advisory RED → 0 claim, 0 gen ===")
        _reset(); main._refine_advise = _advise(Verdict.RED)
        r = await c.post("/refine", data={**BASE, "confirm": "false", "message": "add a Ferrari",
                                          "operation_id": "op-red"})
        j = r.json()
        check("1a status=advisory", j.get("status") == "advisory", j.get("status"))
        check("1b aucun intent claimé, 0 appel image", len(STORE) == 0 and CNT["exec"] == 0)

        main._refine_advise = _advise(Verdict.GREEN)   # GREEN pour la suite

        print("\n=== 2. GREEN → 1 gen + VersionRecord REFINE + contrat complet ===")
        _reset()
        r = await _post(c, {**BASE, "message": "add a TV", "operation_id": "op-1"})
        j = r.json()
        check("2a status=completed, 1 appel image", j.get("status") == "completed" and CNT["exec"] == 1, j.get("status"))
        vr = j.get("version_record") or {}
        check("2b version_record source_mode=REFINE + lineage_customized", vr.get("source_mode_used") == "REFINE"
              and vr.get("lineage_customized") is True, vr)
        vs = json.loads(j.get("versions") or "[]")
        check("2c versions contient la nouvelle version", len(vs) == 1 and vs[0]["source_version_id_used"] == "vSrc")
        check("2d contrat refine complet", j.get("verification") == "deferred" and "estimated_success" in j
              and j.get("ai_message") == "" and j.get("before_image_url") == "https://x/a.jpg"
              and "structural_capture_disabled" in j)

        print("\n=== 3. même op_id pendant RUNNING → 0 nouvelle gen ===")
        _reset()
        STORE["refine_seed"] = {"status": "RUNNING", "result_ref": None}
        # force l'intent_id déterministe à correspondre : on relit celui calculé
        from refine.identity import refine_intent_id
        iid1 = refine_intent_id("user-123", "sess-1", "op-run")
        STORE[iid1] = {"status": "RUNNING", "result_ref": None}
        r = await _post(c, {**BASE, "message": "add a lamp", "operation_id": "op-run"})
        j = r.json()
        check("3a status=running, 0 appel image", j.get("status") == "running" and CNT["exec"] == 0, j)

        print("\n=== 4. même op_id après SUCCEEDED → replay identique, 0 gen ===")
        _reset()
        iid2 = refine_intent_id("user-123", "sess-1", "op-done")
        STORE[iid2] = {"status": "SUCCEEDED", "result_ref": {
            "generated_image_url": "https://done/img.jpg", "result_version_id": "vDONE",
            "intent_id": iid2, "iteration": 2, "source_version_id": "vSrc"}}
        r = await _post(c, {**BASE, "message": "add a lamp", "operation_id": "op-done"})
        j = r.json()
        check("4a replay completed, url du result_ref, 0 gen",
              j.get("status") == "completed" and j.get("after_image_url") == "https://done/img.jpg"
              and CNT["exec"] == 0, j)

        print("\n=== 5. op_id d'un intent FAILED → erreur structurée, pas de réouverture ===")
        _reset()
        iid3 = refine_intent_id("user-123", "sess-1", "op-failed")
        STORE[iid3] = {"status": "FAILED", "result_ref": None}
        r = await _post(c, {**BASE, "message": "add a lamp", "operation_id": "op-failed"})
        check("5a HTTP 502 structuré (pas 500 brut), 0 gen",
              r.status_code == 502 and CNT["exec"] == 0, r.status_code)
        check("5b error_code REFINE_FAILED", (r.json().get("detail") or r.json()).get("error_code") == "REFINE_FAILED"
              if isinstance(r.json(), dict) else False, r.json())

        print("\n=== 6. nouvel op_id → nouvelle génération ===")
        _reset()
        r = await _post(c, {**BASE, "message": "add a rug", "operation_id": "op-NEW"})
        check("6a completed, 1 gen (nouvel intent)", r.json().get("status") == "completed" and CNT["exec"] == 1)

        print("\n=== 7. OpenAI transitoire → retry ===")
        async def _tr(ctx, n):
            if n == 1: raise httpx.RemoteProtocolError("disc")
            return b"GENIMG"
        _reset(exec_fn=_tr)
        r = await _post(c, {**BASE, "message": "add art", "operation_id": "op-tr"})
        check("7a completed après retry, 2 appels image", r.json().get("status") == "completed" and CNT["exec"] == 2)

        print("\n=== 8. erreur de persistance → pas de 2e appel OpenAI ===")
        async def _up_fail(path, data): raise httpx.RemoteProtocolError("storage down")
        main._refine_upload_deterministic = _up_fail
        _reset()
        r = await _post(c, {**BASE, "message": "add books", "operation_id": "op-pf"})
        check("8a 503 PERSIST_FAILED, image générée UNE seule fois (0 re-OpenAI)",
              r.status_code == 503 and CNT["exec"] == 1, (r.status_code, CNT["exec"]))
        main._refine_upload_deterministic = _upload_det   # restore

        print("\n=== 9. /v1/intents/by-id owner check ===")
        async def _gbid(*, user_id, intent_id, supa=None):
            return {"intent_id": intent_id, "status": "SUCCEEDED"} if user_id == "user-123" and intent_id == "mine" else None
        intent_observer.get_intent_by_id = _gbid
        r_ok = await c.get("/v1/intents/by-id/mine")
        r_no = await c.get("/v1/intents/by-id/someone-else")
        check("9a by-id du propriétaire → 200", r_ok.status_code == 200 and r_ok.json().get("status") == "SUCCEEDED")
        check("9b by-id inconnu/autre user → 404", r_no.status_code == 404)

        print("\n=== 10. operation_id manquant → 422 (pas de gen) ===")
        _reset()
        r = await c.post("/refine", data={**BASE, "message": "add a plant"})   # pas d'operation_id
        check("10a 422 MISSING_OPERATION_ID, 0 gen", r.status_code == 422 and CNT["exec"] == 0, r.status_code)

    print(f"\n{'='*60}\n  {'ALL PASS' if _fails == 0 else str(_fails)+' FAILED'}\n{'='*60}")
    sys.exit(1 if _fails else 0)


async def _ok_true(): return True
def _noop_bytes(): return b"GENIMG"
asyncio.run(run())
