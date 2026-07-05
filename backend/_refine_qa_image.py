"""QA FINAL Refine V2 — COUCHE IMAGE (échantillon réel curé + RETRY).

Fait tourner le moteur assemblé `engine.refine` (gen réelle gpt-image-2 low + Verify 3 états)
sur un échantillon couvrant toutes les catégories, sur sources MEUBLÉES (vision V1). Sur tout
scénario INCOMPLETE → 1 RETRY (`engine.refine_retry`) sur les manquants, mesuré. Émet stats
par catégorie + retry + coût → benchmarks/qa_image_REPORT.md + images qa_out/.
Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_qa_image.py"""
import asyncio
import os
import statistics
import sys
import time

from dotenv import load_dotenv
load_dotenv(override=True)
import httpx
from openai import AsyncOpenAI

from refine.engine import refine, refine_retry
from refine.verify import VerifyStatus

LIVING = "benchmarks/out/living_room__gpt-image-2__low.png"
KITCHEN = "benchmarks/out/kitchen__gpt-image-2__low.png"
OUT = "benchmarks/qa_out"

# LLM cost mesuré (probe) : parser + verify par refine
LLM_COST_PER_REFINE = 0.00007 + 0.000875
GEN_COST_EST = 0.02   # gpt-image-2 low edit — ESTIMATION (poste dominant, à affiner via télémétrie)

# cat, id, source, room, message
SCEN = [
    ("ADD","qa_a1",LIVING,"living room","Add a floor lamp in the corner beside the armchair"),
    ("ADD","qa_a2",LIVING,"living room","Add a large round mirror on the wall above the sideboard"),
    ("MOVE","qa_m1",LIVING,"living room","Move the armchair to the other side of the sofa"),
    ("MOVE","qa_m2",LIVING,"living room","Move the TV to the left wall"),
    ("MOVE","qa_m3",LIVING,"living room","Rotate the sofa to face the window"),
    ("REMOVE","qa_r1",LIVING,"living room","Remove the coffee table"),
    ("REMOVE","qa_r2",LIVING,"living room","Remove the rug"),
    ("REMOVE","qa_r3",LIVING,"living room","Remove the curtains"),
    ("REPLACE","qa_p1",LIVING,"living room","Replace the beige sofa with a dark leather sofa"),
    ("REPLACE","qa_p2",LIVING,"living room","Replace the coffee table with a glass one"),
    ("COMPLEX","qa_c1",LIVING,"living room","Remove the coffee table and add a vase of flowers"),
    ("COMPLEX","qa_c2",LIVING,"living room","Move the TV to the left and replace the sofa with a leather one"),
    ("COMPLEX","qa_c3",LIVING,"living room","Move the armchair, remove the rug and add a floor lamp"),
    ("STRUCTURE","qa_s1",KITCHEN,"kitchen","Add a large kitchen island in the centre"),
    ("COMPLEX","qa_c4",KITCHEN,"kitchen","Replace the cabinets with darker ones and add pendant lights"),
]

client = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"], max_retries=0,
                     timeout=httpx.Timeout(180.0, connect=5.0))


async def run_one(cat, sid, src, room, msg):
    with open(src, "rb") as f:
        img = f.read()
    rec = {"cat": cat, "id": sid, "msg": msg}
    t0 = time.monotonic()
    try:
        out = await refine(client, img, "image/png", msg, parse_client=client)
    except Exception as e:  # noqa: BLE001
        rec["error"] = repr(e); rec["t_gen"] = time.monotonic() - t0
        return rec
    rec["t_gen"] = time.monotonic() - t0
    with open(f"{OUT}/{sid}.png", "wb") as f:
        f.write(out.image)
    rec["n"] = len(out.changes)
    rec["applied"] = sum(1 for x in out.result.applied if x)
    rec["status"] = out.result.status.value
    rec["identity"] = out.result.identity_preserved
    rec["complete"] = out.complete
    rec["conflicts"] = len(out.conflicts)
    rec["retry"] = None
    # RETRY si incomplet (opt-in simulé) — 1 gen ciblée sur les manquants
    if not out.complete and out.missing:
        t1 = time.monotonic()
        try:
            r2 = await refine_retry(client, out.image, "image/png", out.missing)
            rec["retry"] = {
                "t": time.monotonic() - t1,
                "targeted": [c.type for c in r2.changes],
                "applied": sum(1 for x in r2.result.applied if x),
                "n": len(r2.changes),
                "status": r2.result.status.value,
                "complete_after": r2.complete,
            }
            with open(f"{OUT}/{sid}_retry.png", "wb") as f:
                f.write(r2.image)
        except Exception as e:  # noqa: BLE001
            rec["retry"] = {"error": repr(e)}
    rec["t_total"] = time.monotonic() - t0
    return rec


async def main():
    os.makedirs(OUT, exist_ok=True)
    print(f"=== QA IMAGE — {len(SCEN)} scénarios (gpt-image-2 low, sources meublées) + retry ===\n", flush=True)
    recs = []
    for i, sc in enumerate(SCEN, 1):
        print(f"[{i}/{len(SCEN)}] {sc[1]} ({sc[0]}) — {sc[4]}", flush=True)
        r = await run_one(*sc)
        recs.append(r)
        if "error" in r:
            print(f"    ERREUR {r['error']} ({r['t_gen']:.1f}s)\n", flush=True); continue
        line = (f"    status={r['status']} applied={r['applied']}/{r['n']} "
                f"identity={'OK' if r['identity'] else 'DRIFT'} complete={r['complete']} "
                f"conflicts={r['conflicts']} gen={r['t_gen']:.0f}s")
        if r["retry"]:
            rt = r["retry"]
            if "error" in rt:
                line += f" | RETRY ERR"
            else:
                line += (f" | RETRY {rt['applied']}/{rt['n']} {rt['status']} "
                         f"complete_after={rt['complete_after']} ({rt['t']:.0f}s)")
        print(line + "\n", flush=True)

    ok = [r for r in recs if "error" not in r]
    # stats globales
    def rate(rs): return (sum(1 for r in rs if r["complete"]) , len(rs))
    total_changes = sum(r["n"] for r in ok)
    applied_changes = sum(r["applied"] for r in ok)
    drift = [r for r in ok if not r["identity"]]
    retried = [r for r in ok if r["retry"] and "error" not in r["retry"]]
    retry_fixed = [r for r in retried if r["retry"]["complete_after"]]
    unavail = [r for r in ok if r["status"] == VerifyStatus.VERIFICATION_UNAVAILABLE.value]

    lines = ["# QA Image Refine V2 — échantillon réel (sources meublées) + retry", ""]
    lines.append(f"- Scénarios : {len(recs)} · erreurs : {len(recs)-len(ok)}")
    c, n = rate(ok)
    lines.append(f"- **Complets 1ʳᵉ passe : {c}/{n}**")
    lines.append(f"- **Changements appliqués 1ʳᵉ passe : {applied_changes}/{total_changes} = "
                 f"{(100*applied_changes/total_changes) if total_changes else 0:.0f}%**")
    lines.append(f"- **Drift identité : {len(drift)}/{len(ok)}**")
    lines.append(f"- Verify indisponible : {len(unavail)}/{len(ok)}")
    lines.append(f"- **Retry : {len(retried)} déclenchés, {len(retry_fixed)} résolus après retry**")
    if ok:
        gens = [r["t_gen"] for r in ok]
        lines.append(f"- Temps gen : moy {statistics.mean(gens):.0f}s · médiane {statistics.median(gens):.0f}s "
                     f"· min {min(gens):.0f}s · max {max(gens):.0f}s")
    if retried:
        rts = [r["retry"]["t"] for r in retried]
        lines.append(f"- Temps retry : moy {statistics.mean(rts):.0f}s")
    lines.append(f"- Coût estimé/refine : gen ~${GEN_COST_EST:.2f} + LLM ${LLM_COST_PER_REFINE:.5f} "
                 f"≈ **${GEN_COST_EST+LLM_COST_PER_REFINE:.3f}** (gen = ESTIMATION low)")

    lines += ["", "## Par catégorie", "", "| cat | n | complets | applied | drift | retries | retry_fixed |", "|---|---|---|---|---|---|---|"]
    for cat in ["ADD","MOVE","REMOVE","REPLACE","STRUCTURE","COMPLEX"]:
        rs = [r for r in ok if r["cat"] == cat]
        if not rs: continue
        cc = sum(1 for r in rs if r["complete"])
        ap = sum(r["applied"] for r in rs); tot = sum(r["n"] for r in rs)
        dr = sum(1 for r in rs if not r["identity"])
        rtc = sum(1 for r in rs if r["retry"] and "error" not in r["retry"])
        rtf = sum(1 for r in rs if r["retry"] and "error" not in r["retry"] and r["retry"]["complete_after"])
        lines.append(f"| {cat} | {len(rs)} | {cc}/{len(rs)} | {ap}/{tot} | {dr} | {rtc} | {rtf} |")

    lines += ["", "## Détail par scénario", "", "| id | cat | status | applied | identity | complete | retry→complete | gen(s) |", "|---|---|---|---|---|---|---|---|"]
    for r in ok:
        rt = "—"
        if r["retry"] and "error" not in r["retry"]:
            rt = f"{r['retry']['applied']}/{r['retry']['n']}→{r['retry']['complete_after']}"
        elif r["retry"]:
            rt = "ERR"
        lines.append(f"| {r['id']} | {r['cat']} | {r['status']} | {r['applied']}/{r['n']} | "
                     f"{'OK' if r['identity'] else 'DRIFT'} | {r['complete']} | {rt} | {r['t_gen']:.0f} |")
    for r in (r for r in recs if "error" in r):
        lines.append(f"| {r['id']} | {r['cat']} | ERROR | — | — | — | — | {r['t_gen']:.0f} |")

    report = "\n".join(lines)
    with open("benchmarks/qa_image_REPORT.md", "w", encoding="utf-8") as f:
        f.write(report + "\n")
    print("\n" + report)
    print(f"\n[écrit] benchmarks/qa_image_REPORT.md + images {OUT}/", flush=True)

sys.exit(asyncio.run(main()))
