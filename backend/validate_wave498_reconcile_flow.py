"""Phase 1 — Reconcile RÉEL (point 3). 0 réseau. Faux Supabase.

Prouve, via le VRAI intent_reconciliation.reconcile_once :
  • flux claim→RUNNING→persist(result_ref durable)→CRASH avant SUCCEEDED→reconcile→SUCCEEDED
  • billing refine OFF dans le reconcile (is_free=False)
  • non-régression : RUNNING sans result_ref + vieux → FAILED (timeout) inchangé
"""
import os, sys, asyncio, logging
from types import SimpleNamespace
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import billing
import intent_reconciliation as REC
from refine import orchestrator_adapter as ADP, identity

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(cond)
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")


class FQ:
    def __init__(self, table, store): self.t = table; self.store = store; self.f = {}; self.op = "select"; self.patch = None
    def select(self, *a, **k): self.op = "select"; return self
    def update(self, patch): self.op = "update"; self.patch = patch; return self
    def eq(self, c, v): self.f[c] = v; return self
    def gte(self, *a, **k): return self
    def limit(self, n): return self
    def _rows(self): return self.store.get(self.t, [])
    def _match(self, r):
        return all(r.get(k) == v for k, v in self.f.items())
    def execute(self):
        if self.op == "select":
            rows = [r for r in self._rows() if self._match(r)]
            return SimpleNamespace(data=rows, count=len(rows))
        upd = []
        for r in self._rows():
            if self._match(r):
                r.update(self.patch); upd.append(r)
        return SimpleNamespace(data=upd, count=len(upd))


class FakeSupa:
    def __init__(self, store): self.store = store
    def table(self, name): return FQ(name, self.store)


async def main():
    # patch billing (refine OFF) — on enregistre is_free vu par le reconcile
    seen = {"is_free": None, "n": 0}
    async def _bill(*, intent_id, new_status, is_free, supa=None):
        seen["is_free"] = is_free; seen["n"] += 1
    billing.apply_billing_for_intent_transition = _bill

    print("\n=== 1. flux réel : persist écrit result_ref → CRASH avant SUCCEEDED → reconcile → SUCCEEDED ===")
    iid = identity.refine_intent_id("u1", "s1", "op1")
    store = {"generation_intents": [
        {"intent_id": iid, "status": "RUNNING", "session_id": "s1",
         "started_at": "2020-01-01T00:00:00+00:00", "created_at": "2020-01-01T00:00:00+00:00",
         "result_ref": None, "iteration": 2,
         "intent": {"engine": "refine", "billing_enabled": False}}],
        "messages": []}
    supa = FakeSupa(store)

    # persist RÉEL de l'adaptateur, IO branché sur le faux store
    async def upload_fn(path, data): return "http://" + path
    async def get_ref(i):
        row = next((r for r in store["generation_intents"] if r["intent_id"] == i), None)
        return (row or {}).get("result_ref")
    async def set_ref(i, ref):
        for r in store["generation_intents"]:
            if r["intent_id"] == i: r["result_ref"] = ref
        return True
    async def msg(*a, **k): pass
    persist = ADP.build_persist_result_fn(upload_fn=upload_fn, get_result_ref_fn=get_ref,
        set_result_ref_fn=set_ref, persist_message_fn=msg, source_image_url="http://src",
        atmosphere="warm", room_type="Living Room")

    class Ctx:
        intent_id = iid; operation_id = "op1"; session_id = "s1"; iteration = 2
        meta = {"source_version_id": "vSrc"}
    ref = await persist(Ctx(), b"IMG")           # écrit result_ref (statut reste RUNNING)
    # ── CRASH : on N'appelle PAS observe_intent_end(SUCCEEDED) ──
    row = store["generation_intents"][0]
    check("1a après persist : intent encore RUNNING mais result_ref DURABLE présent",
          row["status"] == "RUNNING" and row["result_ref"] is not None)

    counts = await REC.reconcile_once(supa=supa)      # LE VRAI worker
    check("1b reconcile repare l'intent → SUCCEEDED", row["status"] == "SUCCEEDED" and counts["repaired"] == 1, counts)
    check("1c result_ref intact (récupérable) après finalisation",
          row["result_ref"]["result_version_id"] == identity.refine_result_version_id(iid))
    check("1d billing refine OFF (métadonnée) : le reconcile NE facture PAS (0 appel billing)",
          seen["n"] == 0, seen)

    print("\n=== 2. non-régression : RUNNING sans result_ref + vieux → FAILED (timeout) ===")
    store2 = {"generation_intents": [
        {"intent_id": "refine:old", "status": "RUNNING", "session_id": "s9",
         "started_at": "2020-01-01T00:00:00+00:00", "created_at": "2020-01-01T00:00:00+00:00",
         "result_ref": None, "iteration": 1}],
        "messages": []}
    counts2 = await REC.reconcile_once(supa=FakeSupa(store2))
    check("2a intent sans result_ref, ancien, sans image → FAILED (timeout)",
          store2["generation_intents"][0]["status"] == "FAILED" and counts2["timeout_failed"] == 1, counts2)

    print("\n=== 3. non-régression : image_result présent (landed) → SUCCEEDED ===")
    store3 = {"generation_intents": [
        {"intent_id": "refine:landed", "status": "RUNNING", "session_id": "s3",
         "started_at": "2020-01-01T00:00:00+00:00", "created_at": "2020-01-01T00:00:00+00:00",
         "result_ref": None, "iteration": 1}],
        "messages": [{"session_id": "s3", "message_type": "image_result", "created_at": "2020-06-01T00:00:00+00:00"}]}
    counts3 = await REC.reconcile_once(supa=FakeSupa(store3))
    check("3a landed (message image_result) → SUCCEEDED (corrélation inchangée)",
          store3["generation_intents"][0]["status"] == "SUCCEEDED" and counts3["repaired"] == 1, counts3)

    print("\n=== 4. NON-RÉGRESSION V1 : RUNNING + result_ref PARTIEL/non-finalizable → PAS finalisé ===")
    from datetime import datetime, timezone
    recent = datetime.now(timezone.utc).isoformat()
    # (a) result_ref présent SANS finalizable, engine=generate, RÉCENT → ne doit PAS devenir SUCCEEDED
    store4 = {"generation_intents": [
        {"intent_id": "v1intent", "status": "RUNNING", "session_id": "s4",
         "started_at": recent, "created_at": recent, "iteration": 1,
         "result_ref": {"generated_image_url": "http://partial"},   # JSON partiel, pas de finalizable
         "intent": {"engine": "generate"}}],
        "messages": []}
    counts4 = await REC.reconcile_once(supa=FakeSupa(store4))
    check("4a V1 result_ref partiel (no finalizable) + engine=generate → RESTE RUNNING (jamais SUCCEEDED)",
          store4["generation_intents"][0]["status"] == "RUNNING" and counts4["repaired"] == 0, counts4)
    # (b) même result_ref finalizable MAIS engine=generate → toujours pas finalisé par cette règle (scopée refine)
    store4b = {"generation_intents": [
        {"intent_id": "v1intent2", "status": "RUNNING", "session_id": "s4b",
         "started_at": recent, "created_at": recent, "iteration": 1,
         "result_ref": {"finalizable": True, "generated_image_url": "http://x"},
         "intent": {"engine": "generate"}}],
        "messages": []}
    counts4b = await REC.reconcile_once(supa=FakeSupa(store4b))
    check("4b finalizable=True MAIS engine=generate → RESTE RUNNING (règle scopée refine)",
          store4b["generation_intents"][0]["status"] == "RUNNING" and counts4b["repaired"] == 0, counts4b)

    total = len(res); passed = sum(res)
    print(f"\n{'='*60}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*60}")
    sys.exit(0 if passed == total else 1)


asyncio.run(main())
