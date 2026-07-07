"""Phase 1 — Generation Orchestrator ISOLÉ (mocks, non branché). 0 OpenAI, 0 réseau.

Corrections robustesse : terminal STRICT · persist PROTÉGÉE (retry storage, 0 OpenAI) ·
codes GÉNÉRIQUES dérivés de kind · get-or-create par result_ref durable · versions
déterministes + dédup replay · billing OFF.
"""
import os, sys, asyncio, json, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import httpx
import intent_observer, billing
from generation_orchestrator import run_generation, OrchestratorError, GenContext
from intent_observer import ClaimResult
from refine import orchestrator_adapter as ADP, identity

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(cond)
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")


def install(rec, claim_result, terminal_ok=True):
    async def _claim(**kw): rec["claim"] = kw; return claim_result
    async def _hold(*, intent_id, new_status, is_free, supa=None): rec["holds"].append((new_status, is_free))
    async def _terminal(intent_id, status, *, result_ref=None, error=None, is_free=True, supa=None):
        rec["terminals"].append((status, is_free, result_ref is not None, error is not None))
        return terminal_ok
    async def _js(intent_id, attempt, *a, **k): return f"job{attempt}"
    async def _je(job_id, status, *a, **k): pass
    intent_observer.claim_generation_intent = _claim
    intent_observer.observe_intent_end = _terminal
    intent_observer.observe_job_start = _js
    intent_observer.observe_job_end = _je
    billing.apply_billing_for_intent_transition = _hold


async def fetch_ok(url): return (b"SRC", "image/jpeg")
async def persist_ok(ctx, b):
    return {"generated_image_url": "http://img", "intent_id": ctx.intent_id,
            "result_version_id": "vX", "room_type": ""}
def resp_fn(): return lambda rr: {"status": "completed", "after_image_url": rr.get("generated_image_url", "")}

BASE = dict(kind="refine", user_id="u1", session_id="s1", operation_id="op1",
            intent_id="refine:abc", intent_meta={"operation_id": "op1"}, iteration=2,
            is_free=False, source_image_url="http://src", max_attempts=2,
            fetch_source_fn=fetch_ok, backoff_s=0.0, persist_max_attempts=2)


async def scenario(execute_fn, persist_fn=persist_ok, claim=ClaimResult(won=True),
                   terminal_ok=True, kind="refine"):
    rec = {"claim": None, "holds": [], "terminals": []}
    install(rec, claim, terminal_ok)
    calls = {"exec": 0, "persist": 0}
    async def _exec(ctx):
        calls["exec"] += 1; return await execute_fn(ctx, calls["exec"])
    async def _persist(ctx, b):
        calls["persist"] += 1; return await persist_fn(ctx, b)
    out = err = None
    try:
        out = await run_generation(execute_fn=_exec, persist_result_fn=_persist,
                                   build_response_fn=resp_fn(), **{**BASE, "kind": kind})
    except OrchestratorError as e:
        err = e
    return rec, calls, out, err


async def main():
    print("\n=== 1. transient→succès ===")
    async def ex_1(ctx, n):
        if n == 1: raise httpx.RemoteProtocolError("disc")
        return b"IMG"
    rec, calls, out, err = await scenario(ex_1)
    check("1a 2 appels image (1 retry)", calls["exec"] == 2, calls)
    check("1b completed", out and out.get("status") == "completed")
    check("1c terminal SUCCEEDED(is_free=False, result_ref)", ("SUCCEEDED", False, True, False) in rec["terminals"])
    check("1d HOLD (RUNNING, is_free=False)", rec["holds"] == [("RUNNING", False)])

    print("\n=== 2. transitoire épuisé → 503 structuré ===")
    async def ex_2(ctx, n): raise httpx.RemoteProtocolError("down")
    rec, calls, out, err = await scenario(ex_2)
    check("2a max_attempts appels", calls["exec"] == 2)
    check("2b 503 retryable, code générique dérivé de kind", err and err.status_code == 503
          and err.retryable and err.error_code == "REFINE_UNAVAILABLE", err and err.error_code)
    check("2c terminal FAILED", ("FAILED", False, False, True) in rec["terminals"])

    print("\n=== 3. 4xx → aucun retry, 502 ===")
    async def ex_3(ctx, n):
        raise httpx.HTTPStatusError("bad", request=httpx.Request("POST", "http://x"),
                                    response=httpx.Response(400))
    rec, calls, out, err = await scenario(ex_3)
    check("3a 1 seul appel image", calls["exec"] == 1)
    check("3b 502 non-retryable REFINE_REJECTED", err and err.status_code == 502
          and not err.retryable and err.error_code == "REFINE_REJECTED")
    check("3c terminal FAILED_TERMINAL", ("FAILED_TERMINAL", False, False, True) in rec["terminals"])

    print("\n=== 4. double-claim → une seule exécution ===")
    async def ex_never(ctx, n): raise AssertionError("execute ne doit PAS tourner")
    rec, calls, out, err = await scenario(ex_never, claim=ClaimResult(won=False, status="RUNNING"))
    check("4a RUNNING → running, 0 exec, 0 persist", out and out.get("status") == "running"
          and calls["exec"] == 0 and calls["persist"] == 0)
    rr = {"generated_image_url": "http://done"}
    rec, calls, out, err = await scenario(ex_never, claim=ClaimResult(won=False, status="SUCCEEDED", result_ref=rr))
    check("4b SUCCEEDED → replay, 0 exec, 0 persist", out and out.get("after_image_url") == "http://done"
          and calls["exec"] == 0 and calls["persist"] == 0)
    rec, calls, out, err = await scenario(ex_never, claim=ClaimResult(won=False, status="FAILED"))
    check("4c FAILED terminal → erreur, pas de réouverture, 0 exec",
          err and err.error_code == "REFINE_FAILED" and calls["exec"] == 0)

    print("\n=== 5. TERMINAL STRICT : SUCCEEDED non persisté → pas de 'completed' ===")
    async def ex_ok(ctx, n): return b"IMG"
    rec, calls, out, err = await scenario(ex_ok, terminal_ok=False)
    check("5a observe_intent_end False → OrchestratorError récupérable (pas completed)",
          out is None and err is not None and err.retryable and err.error_code == "REFINE_FINALIZE_PENDING",
          err and err.error_code)
    check("5b persist bien exécuté (image durable) avant l'échec du flip", calls["persist"] == 1)

    print("\n=== 6. PERSIST PROTÉGÉE (retry storage transitoire, JAMAIS OpenAI) ===")
    async def ex_once(ctx, n): return b"IMG"
    pstate = {"n": 0}
    async def persist_flaky(ctx, b):
        pstate["n"] += 1
        if pstate["n"] == 1: raise httpx.RemoteProtocolError("storage blip")
        return {"generated_image_url": "http://ok", "intent_id": ctx.intent_id, "result_version_id": "vX"}
    rec, calls, out, err = await scenario(ex_once, persist_fn=persist_flaky)
    check("6a persist retenté (2), image NON régénérée (1 seul appel OpenAI)",
          pstate["n"] == 2 and calls["exec"] == 1 and out and out.get("status") == "completed")
    async def persist_dead(ctx, b): raise httpx.RemoteProtocolError("storage down")
    rec, calls, out, err = await scenario(ex_once, persist_fn=persist_dead)
    check("6b persist échec final → 503 PERSIST_FAILED, terminal FAILED, 1 seul OpenAI",
          err and err.status_code == 503 and err.error_code == "REFINE_PERSIST_FAILED"
          and calls["exec"] == 1 and ("FAILED", False, False, True) in rec["terminals"])

    print("\n=== 7. codes GÉNÉRIQUES dérivés de kind (pas 'refine' codé en dur) ===")
    rec, calls, out, err = await scenario(ex_3, kind="generate")
    check("7 kind='generate' → GENERATE_REJECTED (shell générique)", err and err.error_code == "GENERATE_REJECTED")

    print("\n=== 8. billing OFF (is_free=False propagé HOLD + terminal) ===")
    rec, calls, out, err = await scenario(ex_ok)
    check("8 HOLD ET terminal is_free=False (0 écriture ledger)",
          rec["holds"] == [("RUNNING", False)] and all(t[1] is False for t in rec["terminals"]))

    # ── Adaptateur : get-or-create (3 fenêtres de crash) + versions déterministes ──
    print("\n=== 9. adaptateur persist get-or-create : 3 fenêtres, message idempotent, finalizable ===")
    class Store:
        def __init__(self): self.ref=None; self.uploads=[]; self.sets=0; self.msg_intents=[]
        async def upload(self, path, data): self.uploads.append(path); return "http://"+path
        async def get_ref(self, iid): return self.ref
        async def set_ref(self, iid, ref): self.sets += 1; self.ref = ref; return True
        async def msg(self, *, session_id, before_url, after_url, style_label, intent_id, result_version_id):
            if intent_id not in self.msg_intents:                 # IDEMPOTENT par intent_id
                self.msg_intents.append(intent_id)
    class Ctx:
        kind="refine"; intent_id="refine:abc"; operation_id="op1"; session_id="s1"
        iteration=2; meta={"source_version_id": "vSrc"}
    st = Store()
    persist = ADP.build_persist_result_fn(upload_fn=st.upload, get_result_ref_fn=st.get_ref,
        set_result_ref_fn=st.set_ref, persist_message_fn=st.msg, source_image_url="http://src",
        atmosphere="warm", room_type="Living Room", user_request="add a tv", structural_permission=True)
    det_path = identity.refine_storage_path("s1", "refine:abc")
    det_ver = identity.refine_result_version_id("refine:abc")
    r1 = await persist(Ctx(), b"IMG")
    check("9a upload=1(det), set_ref=1, msg=1, version det, finalizable=True (marqueur EN DERNIER)",
          st.uploads == [det_path] and st.sets == 1 and st.msg_intents == ["refine:abc"]
          and r1["result_version_id"] == det_ver and r1["finalizable"] is True)
    st.ref=None; st.uploads=[]; st.sets=0                              # fenêtre : crash avant set_ref
    r2 = await persist(Ctx(), b"IMG")
    check("9b fenêtre 'avant set_ref' : ré-upload MÊME path (upsert), 1 set, message NON dupliqué",
          st.uploads == [det_path] and st.sets == 1 and st.msg_intents == ["refine:abc"])
    st.uploads=[]; st.sets=0                                          # fenêtre : result_ref finalizable présent
    r3 = await persist(Ctx(), b"IMG")
    check("9c fenêtre 'result_ref finalizable présent' : 0 ré-upload, 0 ré-set, réutilise",
          st.uploads == [] and st.sets == 0 and r3["result_version_id"] == det_ver)
    check("9d result_version_id STABLE + 1 seul message logique (idempotent)",
          r1["result_version_id"] == r2["result_version_id"] == r3["result_version_id"]
          and st.msg_intents == ["refine:abc"])

    print("\n=== 11. GOLDEN VersionRecord : ancien chemin refine vs adaptateur (champs métier ==) ===")
    from version_state import VersionRecord as VR
    # Reconstruction à l'ancienne (cf. /refine endpoint main.py:4969-4983) pour la MÊME entrée
    _msg = "add a bedroom in the rear space"
    _changes_struct = True
    old = VR(version_id="v_OLD_random", vision_number=3, source_mode_used="REFINE",
             source_version_id_used="vSrc", source_image_url_used="http://before",
             generated_image_url="http://gen", atmosphere="warm_modern", user_request=_msg[:240],
             structural_permission=_changes_struct, structural_identity_token="tok", lineage_customized=True)
    rr_g = ADP._result_ref(intent_id="refine:g", operation_id="opg", session_id="sg",
        source_version_id="vSrc", source_image_url="http://before", result_version_id="v_DET",
        storage_path="sg/x.jpg", generated_image_url="http://gen", iteration=3,
        room_type="Living Room", atmosphere="warm_modern", user_request=_msg,
        structural_permission=_changes_struct, structural_identity_token="tok", finalizable=True)
    new = ADP._version_record(rr_g)
    biz = lambda v: (v.vision_number, v.source_mode_used, v.source_version_id_used,
                     v.source_image_url_used, v.generated_image_url, v.atmosphere, v.user_request,
                     v.structural_permission, v.structural_identity_token, v.lineage_customized)
    check("11a champs MÉTIER identiques (tout sauf version_id)", biz(old) == biz(new), (biz(old), biz(new)))
    check("11b seul le version_id diffère (déterministe)", new.version_id == "v_DET" and old.version_id != new.version_id)

    print("\n=== 10. versions déterministes + dédup replay + reconstruct ===")
    rr = ADP._result_ref(intent_id="refine:z", operation_id="opZ", session_id="s2",
        source_version_id="vSrc", source_image_url="http://src", result_version_id="vDET",
        storage_path="s2/refine_z.jpg", generated_image_url="http://z", iteration=3,
        room_type="Kitchen", atmosphere="warm", user_request="add island",
        structural_permission=False, structural_identity_token="tok")
    out1 = ADP.build_response_fn(prior_versions_json="")(rr)
    vs1 = json.loads(out1["versions"])
    check("10a versions contient la NOUVELLE version déterministe (source_mode=REFINE)",
          len(vs1) == 1 and vs1[0]["version_id"] == "vDET" and vs1[0]["source_mode_used"] == "REFINE"
          and vs1[0]["source_version_id_used"] == "vSrc", vs1)
    out2 = ADP.build_response_fn(prior_versions_json=out1["versions"])(rr)   # replay
    vs2 = json.loads(out2["versions"])
    check("10b replay SUCCEEDED → MÊME version, AUCUNE duplication",
          len(vs2) == 1 and out2["version_id"] == "vDET")
    rk = ADP.reconstruct_result_ref({"intent_id": "refine:z", "result_version_id": "vDET",
                                     "generated_image_url": "http://z", "iteration": 3})
    check("10c reconstruct_result_ref fidèle (durable, sans base64)",
          rk["generated_image_url"] == "http://z" and rk["result_version_id"] == "vDET"
          and "b64" not in str(rk).lower())

    total = len(res); passed = sum(res)
    print(f"\n{'='*64}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
    sys.exit(0 if passed == total else 1)


asyncio.run(main())
