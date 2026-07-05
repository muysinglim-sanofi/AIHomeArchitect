"""Re-run CIBLÉ s1 + s5 (installation fonctionnelle corrigée). Pas les 6.
Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_s1s5_rerun.py"""
import asyncio, os, sys, time
from dotenv import load_dotenv
load_dotenv(override=True)
import httpx
from openai import AsyncOpenAI
from refine.engine import refine
from refine.planner import plan

client = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"], max_retries=0, timeout=httpx.Timeout(180.0, connect=5.0))
SRC = "benchmarks/out/living_room__gpt-image-2__low.png"
OUT = "benchmarks/struct_out"
CASES = [("s1_v2", "Remove the right wall and add an open kitchen with an island"),
         ("s5_v2", "Convert the right side of the room into an open kitchen")]

async def main():
    img = open(SRC, "rb").read()
    for sid, msg in CASES:
        t0 = time.monotonic()
        out = await refine(client, img, "image/png", msg, parse_client=client)
        open(f"{OUT}/{sid}.png", "wb").write(out.image)
        p = plan(out.changes)
        print(f"[{sid}] {msg}")
        for c in out.changes: print(f"   {c.type:9} | {c.normalized[:100]}")
        print(f"   verify={out.result.status.value} applied={out.result.applied} identity={'OK' if out.result.identity_preserved else 'DRIFT'} ({time.monotonic()-t0:.0f}s)")
        print(f"   → {OUT}/{sid}.png\n", flush=True)

sys.exit(asyncio.run(main()))
