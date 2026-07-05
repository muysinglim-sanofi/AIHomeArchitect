"""Mini-bench STRUCTURE — 6 cas explicites, parser LLM réel + vraies générations.
Sauve les images pour INSPECTION VISUELLE (le Verify ne suffit pas à conclure).
Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_struct_bench.py"""
import asyncio
import os
import sys
import time

from dotenv import load_dotenv
load_dotenv(override=True)
import httpx
from openai import AsyncOpenAI

from refine.engine import refine
from refine.planner import plan

client = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"], max_retries=0,
                     timeout=httpx.Timeout(180.0, connect=5.0))
SRC = "benchmarks/out/living_room__gpt-image-2__low.png"
OUT = "benchmarks/struct_out"

# id, message (structure explicite). Source : baie gauche (jardin), fenêtre arrière (repas),
# mur droit plein (TV).
CASES = [
    ("s1", "Remove the right wall and add an open kitchen with an island"),
    ("s2", "Close the back window and replace it with a solid wall"),
    ("s3", "Add a new window on the right wall"),
    ("s4", "Remove the right wall to create a larger opening"),
    ("s5", "Convert the right side of the room into an open kitchen"),
    ("s6", "Add a partition wall in the middle of the room"),
]


async def run_one(sid, msg):
    with open(SRC, "rb") as f:
        img = f.read()
    t0 = time.monotonic()
    try:
        out = await refine(client, img, "image/png", msg, parse_client=client)
    except Exception as e:  # noqa: BLE001
        return {"sid": sid, "msg": msg, "error": repr(e)}
    dt = time.monotonic() - t0
    os.makedirs(OUT, exist_ok=True)
    with open(f"{OUT}/{sid}.png", "wb") as f:
        f.write(out.image)
    p = plan(out.changes)  # re-plan pour voir le prompt réellement structuré
    mandate = "take PRIORITY over preservation" in p.combined_prompt
    return {
        "sid": sid, "msg": msg, "dt": dt,
        "types": [c.type for c in out.changes],
        "has_structure": any(c.type == "structure" for c in out.changes),
        "mandate": mandate,
        "status": out.result.status.value,
        "applied": out.result.applied,
        "identity": out.result.identity_preserved,
        "normalized": [c.normalized for c in out.changes],
    }


async def main():
    print(f"=== MINI-BENCH STRUCTURE — {len(CASES)} cas (parser LLM, gpt-image-2 low) ===\n", flush=True)
    for i, (sid, msg) in enumerate(CASES, 1):
        print(f"[{i}/{len(CASES)}] {sid} — {msg}", flush=True)
        r = await run_one(sid, msg)
        if "error" in r:
            print(f"    ERREUR {r['error']}\n", flush=True); continue
        print(f"    types={r['types']}  structure={r['has_structure']}  mandat={r['mandate']}  "
              f"verify={r['status']} applied={r['applied']} identity={'OK' if r['identity'] else 'DRIFT'}  ({r['dt']:.0f}s)", flush=True)
        for n in r["normalized"]:
            print(f"      • {n}", flush=True)
        print(f"    → {OUT}/{sid}.png\n", flush=True)
    print("[fait] images dans", OUT, "— À INSPECTER VISUELLEMENT", flush=True)

sys.exit(asyncio.run(main()))
