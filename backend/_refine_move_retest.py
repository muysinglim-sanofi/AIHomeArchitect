"""Re-test décisif : le prompt 'mobilier libre' débloque-t-il le MOVE majeur du canapé ?
Compare l'ancien vs le nouveau prompt sur la MÊME source meublée. Run:
PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_move_retest.py"""
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
from refine.parser import parse_deterministic
from refine.normalizer import normalize_changes

client = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"], max_retries=0,
                     timeout=httpx.Timeout(180.0, connect=5.0))

SRC = "benchmarks/out/living_room__gpt-image-2__low.png"
MSG = "Move the sofa to the left along the floor-to-ceiling window so the seating faces the TV"


async def main():
    # montrer le prompt réellement envoyé (nouvelle clause ?)
    chs = normalize_changes(parse_deterministic(MSG))
    p = plan(chs)
    print("=== PROMPT ENVOYÉ À GPT-IMAGE ===")
    print(p.combined_prompt)
    print(f"\nest_success={p.estimated_success}  types={[c.type for c in p.ordered_changes]}\n")

    img = open(SRC, "rb").read()
    t0 = time.monotonic()
    out = await refine(client, img, "image/png", MSG, parse_client=client)
    dt = time.monotonic() - t0
    os.makedirs("benchmarks/qa_out", exist_ok=True)
    open("benchmarks/qa_out/move_retest.png", "wb").write(out.image)
    print(f"=== RÉSULTAT ({dt:.0f}s) ===")
    print(f"status={out.result.status.value}  applied={out.result.applied}  "
          f"identity_preserved={out.result.identity_preserved}  complete={out.complete}")
    print("→ benchmarks/qa_out/move_retest.png")

sys.exit(asyncio.run(main()))
