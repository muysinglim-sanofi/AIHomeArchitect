"""Refine Engine V2 — MESURE RÉELLE coût & latence par composant LLM.

Mesure (appels API réels, gpt-4o-mini) la latence wall-clock + les tokens (via `usage`)
de chaque brique LLM d'un Refine : Parser · Advisor L2 · Verify. Donne le coût RÉEL
d'un Refine (pas une estimation). Aucune génération d'image (ni images.edit).

Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_cost_probe.py [N]
"""
import asyncio
import base64
import os
import statistics
import sys
import time

from dotenv import load_dotenv
load_dotenv(override=True)

import httpx
from openai import AsyncOpenAI

from refine.parser import _SYS as PARSER_SYS
from refine.advisor import _L2_SYS as ADVISOR_SYS

# Tarifs gpt-4o-mini (USD / token)
IN = 0.15 / 1_000_000
OUT = 0.60 / 1_000_000

N = int(sys.argv[1]) if len(sys.argv) > 1 else 20

client = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"], max_retries=0,
                     timeout=httpx.Timeout(60.0, connect=5.0))

PARSER_MSG = "Move the TV to the right wall, remove the coffee table and add a floor lamp in the corner."
ADVISOR_USER = "Room: bathroom\nRequested change: Add a Ferrari."


def _img_uri(path):
    with open(path, "rb") as f:
        return "data:image/jpeg;base64," + base64.b64encode(f.read()).decode()


async def _one_parser():
    r = await client.chat.completions.create(
        model="gpt-4o-mini", temperature=0, max_tokens=500,
        messages=[{"role": "system", "content": PARSER_SYS},
                  {"role": "user", "content": PARSER_MSG}])
    return r.usage


async def _one_advisor():
    r = await client.chat.completions.create(
        model="gpt-4o-mini", temperature=0, max_tokens=160,
        messages=[{"role": "system", "content": ADVISOR_SYS},
                  {"role": "user", "content": ADVISOR_USER}])
    return r.usage


async def _one_verify(uri):
    user = [
        {"type": "text", "text": "ORIGINAL image:"},
        {"type": "image_url", "image_url": {"url": uri, "detail": "low"}},
        {"type": "text", "text": "EDITED image:"},
        {"type": "image_url", "image_url": {"url": uri, "detail": "low"}},
        {"type": "text", "text": "Requested changes:\n(1) move the TV\n(2) add flowers\n(3) remove the table\n\n"
                                 'Return ONLY JSON: {"applied":[bool,bool,bool],"identity_preserved":bool,"naturalness_ok":bool}.'},
    ]
    r = await client.chat.completions.create(
        model="gpt-4o-mini", temperature=0, max_tokens=200,
        messages=[{"role": "system", "content": "Judge strictly. JSON only."},
                  {"role": "user", "content": user}])
    return r.usage


async def measure(name, fn, n):
    lat, cost, toks_in, toks_out = [], [], [], []
    for i in range(n):
        t0 = time.monotonic()
        u = await fn()
        lat.append(time.monotonic() - t0)
        pi, po = u.prompt_tokens, u.completion_tokens
        toks_in.append(pi); toks_out.append(po)
        cost.append(pi * IN + po * OUT)
        print(f"    {name} {i+1}/{n}  {lat[-1]*1000:6.0f} ms  in={pi} out={po}  ${cost[-1]:.6f}", flush=True)
    return {
        "name": name,
        "lat_avg": statistics.mean(lat), "lat_p50": statistics.median(lat),
        "lat_max": max(lat),
        "in_avg": statistics.mean(toks_in), "out_avg": statistics.mean(toks_out),
        "cost_avg": statistics.mean(cost),
    }


async def main():
    print(f"=== MESURE RÉELLE (N={N} appels/composant, gpt-4o-mini) ===\n")
    uri = _img_uri("benchmarks/source/living_room.jpg")
    print("[Parser]");  p = await measure("parser",  _one_parser, N)
    print("[Advisor L2]"); a = await measure("advisor", _one_advisor, N)
    print("[Verify]");  v = await measure("verify", lambda: _one_verify(uri), N)

    rows = [p, a, v]
    print("\n=== TABLEAU COÛT / LATENCE (réel) ===")
    print(f"{'Composant':<14}{'Lat. moy':>10}{'Lat. p50':>10}{'Lat. max':>10}"
          f"{'tok in':>9}{'tok out':>9}{'Coût moy':>12}")
    for r in rows:
        print(f"{r['name']:<14}{r['lat_avg']*1000:>9.0f}m{r['lat_p50']*1000:>9.0f}m"
              f"{r['lat_max']*1000:>9.0f}m{r['in_avg']:>9.0f}{r['out_avg']:>9.0f}${r['cost_avg']:>10.6f}")

    # Un Refine « défaut » = Parser + Advisor(si escalade) + Verify (1 gen non comptée ici)
    refine_llm_cost = p["cost_avg"] + v["cost_avg"]              # Advisor souvent skip (L1 GREEN)
    refine_llm_cost_esc = p["cost_avg"] + a["cost_avg"] + v["cost_avg"]
    refine_llm_lat = p["lat_avg"] + v["lat_avg"]
    refine_llm_lat_esc = p["lat_avg"] + a["lat_avg"] + v["lat_avg"]
    print("\n=== COÛT LLM d'un REFINE (hors génération image) ===")
    print(f"  cas GREEN (Advisor L1, 0 appel)   : ${refine_llm_cost:.6f}   +{refine_llm_lat*1000:.0f} ms")
    print(f"  cas ESCALADE (Advisor L2 appelé)  : ${refine_llm_cost_esc:.6f}   +{refine_llm_lat_esc*1000:.0f} ms")
    print("  (la génération gpt-image-2 low reste le poste dominant, mesurée à part.)")

sys.exit(asyncio.run(main()))
