"""Phase 1 (Generation Orchestrator) — Increment 1 : identité déterministe + split prepare().
0 OpenAI, 0 image. Prouve : (A) identité déterministe, message HORS clé ;
(B) prepare() == resolve_conflicts+plan (équivalence avant/après split) ;
(C) refine_generate délègue à prepare()+execute (une seule logique de prep)."""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

from refine.parser import parse_deterministic
from refine.normalizer import normalize_changes
from refine.conflict import resolve_conflicts
from refine.planner import plan
from refine.engine import prepare, refine_generate
import refine.engine as engine
from refine import identity

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(cond)
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")

def build(msg):
    return normalize_changes(parse_deterministic(msg))

MSGS = [
    ("add a TV", "default"),
    ("add a bedroom in the rear space", "default"),
    ("make it warmer, remove the rug and add a plant", "default"),
    ("replace the sofa with a leather one", "retry"),
]

print("\n=== A. Identité déterministe (message HORS clé) ===")
i_a  = identity.refine_intent_id("u1", "s1", "op-A")
i_a2 = identity.refine_intent_id("u1", "s1", "op-A")
i_b  = identity.refine_intent_id("u1", "s1", "op-B")
check("A1 même (user,session,operation_id) → même intent_id", i_a == i_a2, i_a)
check("A2 operation_id différent → intent_id différent", i_a != i_b)
check("A3 intent_id préfixé 'refine:'", i_a.startswith("refine:"))
check("A4 message hors clé (aucun argument message) → 2 actions ≠ = op_id ≠ requis",
      identity.refine_intent_id("u1", "s1", "op-TV") != identity.refine_intent_id("u1", "s1", "op-BED"))
vid  = identity.refine_result_version_id(i_a)
check("A5 result_version_id déterministe depuis intent_id", vid == identity.refine_result_version_id(i_a))
sp1 = identity.refine_storage_path("s1", i_a)
sp2 = identity.refine_storage_path("s1", i_a)
check("A6 storage_path déterministe (upsert = 1 objet), pas d'uuid4", sp1 == sp2 and "refine_" in sp1)
check("A7 storage_path change avec l'intent_id", sp1 != identity.refine_storage_path("s1", i_b))

print("\n=== B. Équivalence prepare() ⟺ resolve_conflicts+plan (avant/après split) ===")
for msg, mode in MSGS:
    ref_changes, ref_conflicts = resolve_conflicts(build(msg))     # référence (ancien chemin)
    ref_plan = plan(ref_changes, mode=mode)
    prepared = prepare(build(msg), mode=mode)                      # nouveau chemin
    ok_prompt = prepared.prompt == ref_plan.strategy.prompt
    ok_order  = [c.raw for c in prepared.ordered_changes] == [c.raw for c in ref_plan.ordered_changes]
    ok_conf   = prepared.conflicts == ref_conflicts
    ok_est    = prepared.estimated_success == ref_plan.estimated_success
    ok_kind   = prepared.plan.strategy.kind == ref_plan.strategy.kind
    check(f"B [{msg[:32]!r:34} mode={mode}] prompt==", ok_prompt)
    check(f"B [{msg[:32]!r:34} mode={mode}] ordered_changes==", ok_order)
    check(f"B [{msg[:32]!r:34} mode={mode}] conflicts==", ok_conf)
    check(f"B [{msg[:32]!r:34} mode={mode}] estimated_success==", ok_est)
    check(f"B [{msg[:32]!r:34} mode={mode}] strategy.kind==", ok_kind)

print("\n=== C. refine_generate délègue à prepare()+execute (mock, 0 OpenAI) ===")
async def _suite_c():
    orig = engine._execute_strategy
    calls = {"n": 0, "prompt": None}
    async def fake_exec(client, image_bytes, mime, p):
        calls["n"] += 1; calls["prompt"] = p.strategy.prompt
        return b"FAKE_IMAGE_BYTES"
    engine._execute_strategy = fake_exec
    try:
        chs = build("add a TV")
        prepared = prepare(build("add a TV"), mode="default")
        r = await refine_generate(None, b"src", "image/jpeg", chs, mode="default")
        check("C1 image = celle de l'executor (délégation)", r.image == b"FAKE_IMAGE_BYTES")
        check("C2 _execute_strategy appelé exactement 1 fois", calls["n"] == 1)
        check("C3 prompt exécuté == prompt figé de prepare()", calls["prompt"] == prepared.prompt)
        check("C4 estimated_success propagé de prepare()", r.estimated_success == prepared.estimated_success)
    finally:
        engine._execute_strategy = orig

asyncio.run(_suite_c())

total = len(res); passed = sum(res)
print(f"\n{'='*60}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*60}")
sys.exit(0 if passed == total else 1)
