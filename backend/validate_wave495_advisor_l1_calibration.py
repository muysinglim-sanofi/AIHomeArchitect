"""Wave 4.9.5 — Advisor L1 : calibration conversion de zone fonctionnelle.
Changes CONSTRUITS (= sortie Parser vérifiée) → advise(client=None) = L1 seul.
0 OpenAI, 0 image. Moteur 2 (advisor.py) uniquement — Parser/Normalizer/Planner intacts.

Contrat :
  - action install + zone fonctionnelle + cible explicite → GREEN
  - install + zone fonctionnelle SANS cible                → YELLOW
  - objet absurde (véhicule/piscine) intérieur            → RED
  - meuble nommé d'après une pièce ("dining table")       → PAS yellow (garde-fou)
"""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

from refine.parser import Change
from refine.advisor import advise, Verdict

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(cond)
    sfx = f"  [{detail}]" if detail and not cond else ""
    print(f"  {PASS if cond else FAIL}  {label}{sfx}")

def C(t, o, d, raw):
    return Change(type=t, object=o, detail=d, raw=raw)

# (label, Change, room, verdict attendu)
CASES = [
    # ── GREEN : zone fonctionnelle + cible explicite ──────────────────────────
    ("add a bedroom in the rear space", C("add", "bedroom", "in the rear space",
        "add a bedroom in the rear space"), "living room", "green"),
    ("convert the dining area into a bedroom", C("structure", "dining area", "into a bedroom",
        "convert the dining area into a bedroom"), "living room", "green"),
    ("instead of the dinner table, create a sleeping area", C("add", "sleeping area", "",
        "instead of the dinner table, create a sleeping area"), "living room", "green"),
    ("add a kitchen on the right side", C("add", "kitchen", "on the right side",
        "add a kitchen on the right side"), "living room", "green"),
    ("turn the corner into a dressing area", C("structure", "dressing area", "",
        "turn the corner into a dressing area"), "living room", "green"),
    # ── YELLOW : zone fonctionnelle SANS cible explicite ──────────────────────
    ("add a bedroom", C("add", "bedroom", "", "add a bedroom"), "living room", "yellow"),
    # ── RED : absurde intérieur (backstop conservé) ───────────────────────────
    ("add a Ferrari in the living room", C("add", "Ferrari", "in the living room",
        "add a Ferrari in the living room"), "living room", "red"),
    ("add a swimming pool in the living room", C("add", "swimming pool", "in the living room",
        "add a swimming pool in the living room"), "living room", "red"),
    # ── Non-régression backstop (cas offline existants) ───────────────────────
    ("add a swimming pool @ bedroom", C("add", "swimming pool", "", "add a swimming pool"),
        "bedroom", "red"),
    ("add a Ferrari @ bathroom", C("add", "Ferrari", "", "add a Ferrari"), "bathroom", "red"),
    # ── Garde-fou anti-meuble : "dining table" n'est PAS une zone → PAS yellow ─
    ("add a dining table (meuble, pas zone)", C("add", "dining table", "", "add a dining table"),
        "living room", "green"),   # offline escalate → green (jamais yellow)
]

async def main():
    print("=== WAVE 4.9.5 — Advisor L1 functional-zone calibration (L1 seul) ===\n")
    for label, ch, room, exp in CASES:
        adv = await advise([ch], room, client=None)
        got = adv.overall.value
        check(f"{label:52} → {exp.upper()}", got == exp, f"got={got}")
    total = len(res); passed = sum(res)
    print(f"\n{'='*64}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
    sys.exit(0 if passed == total else 1)

asyncio.run(main())
