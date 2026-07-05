"""QA FINAL Refine V2 — COUCHE LOGIQUE, 50 scénarios + cas Advisor (0 génération image).

Mesure exhaustivement Parser → Advisor → Normalizer → Conflict → Planner sur les 50 scénarios
(+ 9 cas Advisor GREEN/YELLOW/RED). Appels LLM réels parser+advisor (cheap), AUCUNE gen image.
Émet un rapport markdown (par catégorie + global + anomalies) → benchmarks/qa_logic_REPORT.md.
Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_qa_logic.py"""
import asyncio
import os
import statistics
import sys
import time

from dotenv import load_dotenv
load_dotenv(override=True)
import httpx
from openai import AsyncOpenAI

from refine.parser import parse_changes
from refine.advisor import advise, build_advisory_message
from refine.normalizer import normalize_changes
from refine.conflict import resolve_conflicts
from refine.planner import plan

client = AsyncOpenAI(api_key=os.environ["OPENAI_API_KEY"], max_retries=0,
                     timeout=httpx.Timeout(60.0, connect=5.0))

# cat, id, room, message, expected_dominant_type, expect_conflict(None=inconnu)
SCEN = [
    # ── ADD (10) : décor / gros objet / mural / au sol ──
    ("ADD","a01","living room","Add a TV","add",False),
    ("ADD","a02","living room","Add flowers","add",False),
    ("ADD","a03","living room","Add a rug","add",False),
    ("ADD","a04","dining room","Add a chandelier","add",False),
    ("ADD","a05","living room","Add artwork","add",False),
    ("ADD","a06","living room","Add a bookshelf","add",False),
    ("ADD","a07","living room","Add a plant","add",False),
    ("ADD","a08","living room","Add a floor lamp","add",False),
    ("ADD","a09","living room","Add an armchair","add",False),
    ("ADD","a10","kitchen","Add a coffee machine","add",False),
    # ── MOVE (10) : avec/sans destination, reposition, rotate ──
    ("MOVE","m01","living room","Move the TV to the left wall","move",False),
    ("MOVE","m02","living room","Move the sofa","move",False),
    ("MOVE","m03","dining room","Move the dining table to the centre","move",False),
    ("MOVE","m04","bedroom","Move the bed","move",False),
    ("MOVE","m05","dining room","Move the chandelier","move",False),
    ("MOVE","m06","living room","Move the armchair next to the window","move",False),
    ("MOVE","m07","living room","Move the coffee table","move",False),
    ("MOVE","m08","office","Move the desk to face the window","move",False),
    ("MOVE","m09","living room","Rotate the sofa","move",False),
    ("MOVE","m10","dining room","Rotate the dining table","move",False),
    # ── REMOVE (10) ──
    ("REMOVE","r01","living room","Remove the TV","remove",False),
    ("REMOVE","r02","living room","Remove the rug","remove",False),
    ("REMOVE","r03","living room","Remove the sofa","remove",False),
    ("REMOVE","r04","dining room","Remove the dining table","remove",False),
    ("REMOVE","r05","living room","Remove the coffee table","remove",False),
    ("REMOVE","r06","living room","Remove the curtains","remove",False),
    ("REMOVE","r07","living room","Remove the artwork","remove",False),
    ("REMOVE","r08","living room","Remove the wall decor","remove",False),
    ("REMOVE","r09","kitchen","Remove the island","remove",False),
    ("REMOVE","r10","dining room","Remove the chandelier","remove",False),
    # ── REPLACE (10) ──
    ("REPLACE","p01","living room","Replace the sofa with a leather sofa","replace",False),
    ("REPLACE","p02","dining room","Replace the dining table","replace",False),
    ("REPLACE","p03","living room","Replace the TV","replace",False),
    ("REPLACE","p04","dining room","Replace the chandelier","replace",False),
    ("REPLACE","p05","kitchen","Replace the kitchen island","replace",False),
    ("REPLACE","p06","bedroom","Replace the bed","replace",False),
    ("REPLACE","p07","bathroom","Replace the vanity","replace",False),
    ("REPLACE","p08","living room","Replace the curtains","replace",False),
    ("REPLACE","p09","living room","Replace the coffee table","replace",False),
    ("REPLACE","p10","kitchen","Replace the cabinets","replace",False),
    # ── COMPLEX (10) : sollicitent tout le pipeline ──
    ("COMPLEX","c01","living room","Move the TV to the left and replace the sofa with a leather one",None,False),
    ("COMPLEX","c02","living room","Remove the coffee table and add a vase of flowers",None,True),   # R-A
    ("COMPLEX","c03","kitchen","Open the kitchen and add an island",None,False),
    ("COMPLEX","c04","dining room","Replace the dining table and move the chandelier",None,False),
    ("COMPLEX","c05","living room","Move the sofa, add a TV and add a rug",None,False),
    ("COMPLEX","c06","living room","Remove the wall and add artwork on the wall",None,True),          # R-E
    ("COMPLEX","c07","bedroom","Replace the bed and add nightstands",None,False),
    ("COMPLEX","c08","dining room","Move the dining table, remove the rug and add a plant",None,False),
    ("COMPLEX","c09","kitchen","Open the kitchen, replace the cabinets and add pendant lights",None,False),
    ("COMPLEX","c10","living room","Move the TV, remove the console and add a bookshelf",None,False),
]

# Cas Advisor dédiés : id, room, message, verdict attendu
ADV = [
    ("g1","living room","Move the TV to the left","green"),
    ("y1","bathroom","Add a large flat-screen TV","yellow_or_red"),
    ("y2","small living room","Add a huge sectional sofa","yellow_or_red"),
    ("y3","small kitchen","Add a large kitchen island","yellow_or_red"),
    ("d1","bathroom","Add a Ferrari","red"),
    ("d2","bedroom","Add a swimming pool","red"),
    ("d3","living room","Add a boat","red"),
    ("d4","kitchen","Add a giant tree","red"),
    ("d5","bedroom","Add a helicopter","red"),
]


async def run_scenario(cat, sid, room, msg, exp_type, exp_conf):
    rec = {"cat": cat, "id": sid, "room": room, "msg": msg, "anomalies": []}
    t0 = time.monotonic()
    changes = await parse_changes(msg, client=client)
    rec["t_parse"] = time.monotonic() - t0
    rec["types"] = [c.type for c in changes]
    rec["n"] = len(changes)
    if not changes:
        rec["anomalies"].append("PARSER: 0 changement")
    if exp_type and exp_type not in rec["types"]:
        rec["anomalies"].append(f"PARSER: type '{exp_type}' attendu absent ({rec['types']})")
    if cat == "COMPLEX" and rec["n"] < 2:
        rec["anomalies"].append(f"PARSER: COMPLEX attendu >=2 changements ({rec['n']})")

    t1 = time.monotonic()
    advice = await advise(changes, room, client=client)
    rec["t_advise"] = time.monotonic() - t1
    rec["verdict"] = advice.overall.value
    rec["min_conf"] = round(advice.min_confidence, 2)
    rec["adv_msg"] = build_advisory_message(advice)
    rec["escalated"] = any(a.source == "llm" for a in advice.advices)
    if advice.overall.value == "red":
        rec["anomalies"].append(f"ADVISOR: RED sur un edit normal (over-block?) — {[a.verdict.value for a in advice.advices]}")

    normalize_changes(changes)
    rec["normalized"] = [c.normalized for c in changes]
    if any(not c.normalized for c in changes):
        rec["anomalies"].append("NORMALIZER: instruction vide")

    kept, conflicts = resolve_conflicts(changes)
    rec["conflicts"] = conflicts
    rec["n_conflicts"] = len(conflicts)
    if exp_conf is True and not conflicts:
        rec["anomalies"].append("CONFLICT: conflit attendu NON détecté")
    if exp_conf is False and conflicts:
        rec["anomalies"].append(f"CONFLICT: conflit INATTENDU ({conflicts})")

    p = plan(kept)
    rec["planned"] = [c.type for c in p.ordered_changes]
    rec["est_success"] = p.estimated_success
    ranks = ["structure","remove","replace","add","modify","move"]
    order_idx = [ranks.index(c.type) if c.type in ranks else 9 for c in p.ordered_changes]
    if order_idx != sorted(order_idx):
        rec["anomalies"].append(f"PLANNER: ordre §10 violé ({rec['planned']})")
    if not p.combined_prompt or "Locked elements" not in p.combined_prompt:
        rec["anomalies"].append("PLANNER: prompt combiné mal formé")
    rec["t_total"] = time.monotonic() - t0
    return rec


async def run_advisor_case(sid, room, msg, exp):
    changes = await parse_changes(msg, client=client)
    advice = await advise(changes, room, client=client)
    v = advice.overall.value
    ok = (v == "green") if exp == "green" else (v == "red") if exp == "red" else (v in ("yellow","red"))
    return {"id": sid, "room": room, "msg": msg, "expected": exp, "verdict": v,
            "min_conf": round(advice.min_confidence, 2), "msg_out": build_advisory_message(advice),
            "ok": ok}


def stats_block(recs):
    def agg(rs):
        ts = [r["t_total"] for r in rs]
        return {
            "n": len(rs),
            "anomalies": sum(1 for r in rs if r["anomalies"]),
            "green": sum(1 for r in rs if r["verdict"] == "green"),
            "yellow": sum(1 for r in rs if r["verdict"] == "yellow"),
            "red": sum(1 for r in rs if r["verdict"] == "red"),
            "avg_est": round(statistics.mean(r["est_success"] for r in rs), 3),
            "t_parse_avg": round(statistics.mean(r["t_parse"] for r in rs), 2),
            "t_advise_avg": round(statistics.mean(r["t_advise"] for r in rs), 2),
        }
    return agg


async def main():
    print("=== QA LOGIQUE — 50 scénarios (parser+advisor réels, 0 gen) ===\n", flush=True)
    recs = []
    for sc in SCEN:
        r = await run_scenario(*sc)
        recs.append(r)
        flag = "  ⚠ " + " | ".join(r["anomalies"]) if r["anomalies"] else ""
        print(f"[{r['id']}] {r['cat']:<8} {r['verdict']:<6} est={r['est_success']:.2f} "
              f"types={r['types']} conf={r['n_conflicts']} ({r['t_total']:.1f}s){flag}", flush=True)

    print("\n=== CAS ADVISOR ===", flush=True)
    advs = []
    for a in ADV:
        r = await run_advisor_case(*a)
        advs.append(r)
        print(f"[{r['id']}] exp={r['expected']:<14} got={r['verdict']:<6} conf={r['min_conf']} "
              f"{'OK' if r['ok'] else 'MISMATCH'}  « {(r['msg_out'] or '')[:70]} »", flush=True)

    # ── agrégats ──
    cats = ["ADD","MOVE","REMOVE","REPLACE","COMPLEX"]
    lines = ["# QA Logique Refine V2 — 50 scénarios (couche logique, 0 génération)", ""]
    lines.append("| Catégorie | n | anomalies | green | yellow | red | est_succ moy | t_parse | t_advise |")
    lines.append("|---|---|---|---|---|---|---|---|---|")
    agg = stats_block(recs)
    for cat in cats:
        rs = [r for r in recs if r["cat"] == cat]
        a = agg(rs)
        lines.append(f"| {cat} | {a['n']} | {a['anomalies']} | {a['green']} | {a['yellow']} | {a['red']} "
                     f"| {a['avg_est']} | {a['t_parse_avg']}s | {a['t_advise_avg']}s |")
    ga = agg(recs)
    lines.append(f"| **TOTAL** | {ga['n']} | **{ga['anomalies']}** | {ga['green']} | {ga['yellow']} | {ga['red']} "
                 f"| {ga['avg_est']} | {ga['t_parse_avg']}s | {ga['t_advise_avg']}s |")

    lines += ["", "## Anomalies détectées", ""]
    any_anom = False
    for r in recs:
        if r["anomalies"]:
            any_anom = True
            lines.append(f"- **[{r['id']}]** « {r['msg']} » → " + " ; ".join(r["anomalies"]))
    if not any_anom:
        lines.append("- Aucune anomalie sur la couche logique (50/50).")

    lines += ["", "## Cas Advisor", "", "| id | attendu | obtenu | conf | OK | message |", "|---|---|---|---|---|---|"]
    for r in advs:
        lines.append(f"| {r['id']} | {r['expected']} | {r['verdict']} | {r['min_conf']} | "
                     f"{'OK' if r['ok'] else 'MISMATCH'} | {(r['msg_out'] or '—')[:80]} |")

    adv_ok = sum(1 for r in advs if r["ok"])
    lines += ["", f"**Advisor : {adv_ok}/{len(advs)} verdicts conformes.**",
              f"**Logique : {ga['n']-ga['anomalies']}/{ga['n']} scénarios sans anomalie.**"]

    report = "\n".join(lines)
    with open("benchmarks/qa_logic_REPORT.md", "w", encoding="utf-8") as f:
        f.write(report + "\n")
    print("\n" + report)
    print("\n[écrit] benchmarks/qa_logic_REPORT.md", flush=True)

sys.exit(asyncio.run(main()))
