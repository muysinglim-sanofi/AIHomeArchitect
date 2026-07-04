"""Refine Engine V2 — GOLDEN BENCHMARK (réel, générations gpt-image-2 low + Verify).

Fait tourner le MOTEUR ASSEMBLÉ `refine.engine.refine()` (parse LLM → normalize →
Conflict Resolver → Planner(Strategy) → 1 gen réelle → Verify 3 états) sur un golden
set curé couvrant toutes les catégories + un vrai cas de conflit, sur les 5 sources
réelles. Régression permanente : le taux (complets, % changements, drift identité) ne
doit jamais baisser. Défaut = 1 génération/scénario (pas de retry — mesure le PLANCHER).

Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python qa_refine_benchmark.py
Sorties : benchmarks/refine_out/<sid>.png + REPORT.md
"""
import asyncio
import os
import sys
import time

from dotenv import load_dotenv
load_dotenv(override=True)

import httpx
from openai import AsyncOpenAI

from refine.engine import refine
from refine.verify import VerifyStatus

OUT = "benchmarks/refine_out"

# MÉTHODOLOGIE : en prod /refine opère sur une VISION GÉNÉRÉE (meublée), pas sur la photo
# vide. On utilise donc les générations V1 meublées `gpt-image-2 low` comme sources pour
# les manipulations de meubles (source A+, contenu connu). Extérieurs = ajout sur vide (valide).
LIVING = "benchmarks/out/living_room__gpt-image-2__low.png"   # sofa, table basse, TV, tapis, fauteuil, lampes, plantes, artwork
KITCHEN = "benchmarks/out/kitchen__gpt-image-2__low.png"
# (sid, catégorie, source, room_type, message)
SCENARIOS = [
    ("add1", "ADD",       LIVING,  "living room", "Add a large round mirror on the wall above the sideboard and a floor pouf near the armchair."),
    ("rm1",  "REMOVE",    LIVING,  "living room", "Remove the coffee table."),
    ("rp1",  "REPLACE",   LIVING,  "living room", "Replace the beige sofa with a dark leather sofa."),
    ("md1",  "MODIFY",    LIVING,  "living room", "Make the room cooler, with a lighter and more airy palette."),
    ("mv1",  "MOVE",      LIVING,  "living room", "Move the armchair to the other side of the sofa."),
    ("mix1", "MIXED",     LIVING,  "living room", "Move the TV to the left wall, add a bowl of fruit on the coffee table and remove the rug."),
    ("cf1",  "CONFLICT",  LIVING,  "living room", "Remove the coffee table and add a vase of flowers."),
    ("st1",  "STRUCTURE", KITCHEN, "kitchen",     "Open the kitchen by removing the dividing wall."),
    ("st2",  "STRUCTURE", KITCHEN, "kitchen",     "Add a large kitchen island in the centre."),
    ("ext1", "ADD-EXT",   "benchmarks/source/terrace.jpg", "terrace", "Add an outdoor dining set and string lights."),
    ("ext2", "ADD-EXT",   "benchmarks/source/garden.jpg",  "garden",  "Add a lounge sofa and a fire pit."),
]

client = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"], max_retries=0,
                     timeout=httpx.Timeout(180.0, connect=5.0))


async def run_one(sid, cat, src, room, msg):
    with open(src, "rb") as f:
        img = f.read()
    mime = "image/png" if src.lower().endswith(".png") else "image/jpeg"
    t0 = time.monotonic()
    try:
        out = await refine(client, img, mime, msg, parse_client=client)
    except Exception as e:  # noqa: BLE001
        return {"sid": sid, "cat": cat, "error": repr(e), "dt": time.monotonic() - t0}
    dt = time.monotonic() - t0
    with open(f"{OUT}/{sid}.png", "wb") as f:
        f.write(out.image)
    n = len(out.changes)
    applied = sum(1 for x in out.result.applied) if out.result.applied else 0
    applied_ok = sum(1 for x in out.result.applied if x)
    return {
        "sid": sid, "cat": cat, "msg": msg, "room": room, "dt": dt,
        "status": out.result.status.value,
        "n": n, "applied_ok": applied_ok, "applied_total": applied,
        "identity": out.result.identity_preserved,
        "complete": out.complete,
        "conflicts": len(out.conflicts),
        "changes": [c.type for c in out.changes],
        "report": out.report,
    }


async def main():
    os.makedirs(OUT, exist_ok=True)
    print(f"=== GOLDEN BENCHMARK RÉEL — {len(SCENARIOS)} scénarios (gpt-image-2 low) ===\n")
    results = []
    for i, sc in enumerate(SCENARIOS, 1):
        print(f"[{i}/{len(SCENARIOS)}] {sc[0]} ({sc[1]}) — {sc[4]}", flush=True)
        r = await run_one(*sc)
        results.append(r)
        if "error" in r:
            print(f"    ERREUR: {r['error']}  ({r['dt']:.1f}s)\n", flush=True)
        else:
            print(f"    status={r['status']}  applied={r['applied_ok']}/{r['n']}  "
                  f"identity={'OK' if r['identity'] else 'DRIFT'}  conflicts={r['conflicts']}  "
                  f"complete={r['complete']}  ({r['dt']:.1f}s)", flush=True)
            if r["report"]:
                print("    report: " + r["report"].replace("\n", " | "), flush=True)
            print(flush=True)

    ok = [r for r in results if "error" not in r]
    complete = [r for r in ok if r["complete"]]
    total_changes = sum(r["n"] for r in ok)
    applied_changes = sum(r["applied_ok"] for r in ok)
    drift = [r for r in ok if not r["identity"]]
    unavail = [r for r in ok if r["status"] == VerifyStatus.VERIFICATION_UNAVAILABLE.value]

    summary = [
        "# Golden Benchmark Refine V2 — moteur assemblé (Conflict Resolver + Verify 3 états)",
        "",
        f"- Scénarios : {len(results)}  ·  erreurs : {len(results)-len(ok)}",
        f"- **Complets (tout appliqué) : {len(complete)}/{len(ok)}**",
        f"- **Changements appliqués : {applied_changes}/{total_changes}"
        f" = {(100*applied_changes/total_changes) if total_changes else 0:.0f}%**",
        f"- **Drift identité : {len(drift)}/{len(ok)}**",
        f"- Verify indisponible : {len(unavail)}/{len(ok)}",
        "",
        "| sid | cat | status | applied | identity | conflicts | complete | dt |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for r in ok:
        summary.append(f"| {r['sid']} | {r['cat']} | {r['status']} | {r['applied_ok']}/{r['n']} | "
                       f"{'OK' if r['identity'] else 'DRIFT'} | {r['conflicts']} | {r['complete']} | {r['dt']:.0f}s |")
    for r in (r for r in results if "error" in r):
        summary.append(f"| {r['sid']} | {r['cat']} | ERROR | — | — | — | — | {r['dt']:.0f}s |")

    report = "\n".join(summary)
    with open(f"{OUT}/REPORT.md", "w", encoding="utf-8") as f:
        f.write(report + "\n")
    print("\n" + report)
    print(f"\n[écrit] {OUT}/REPORT.md  + {len(ok)} images")

sys.exit(asyncio.run(main()))
