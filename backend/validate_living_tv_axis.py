"""RC-LIVING-TV-AXIS (2026-07-09) — garde-fou PERMANENT de la règle TV-axis.

Vérifie, pour les 5 atmosphères Living Room, que :
  1. la règle axis est FUSIONNÉE dans la phrase TV (même item room_specific_constraints)
     ET dans les 2 premiers items → survit au `[:2]` de build_dna_room_context_signal ;
  2. compose_generation_prompt(living_room, <atmo>) contient bien
     "television axis has priority" dans le prompt FINAL (preuve qu'elle atteint le modèle) ;
  3. le prompt V1 (description vide) reste sous le budget FIRST_VISION (4300) — sinon
     dna_room_context (P3, le TV anchor) serait droppé entièrement par l'assembleur.

0 réseau, 0 API. Régression si un futur changement re-sépare l'axis (→ coupé par [:2])
ou fait exploser le budget. Scope : auto-gen V1 (room_description="").
"""
import os, sys, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

# CONFIG PROD OBLIGATOIRE : le composer ne révèle dna_room_context (le TV anchor +
# la règle TV-axis) qu'avec BIMODAL_ENABLED=1 (+ APP_ENV). Sans .env chargé, la
# section disparaît (config non-benchée) et l'axis n'atteint pas le prompt. Le
# backend prod tourne AVEC (run.sh + .env). On reproduit donc la config prod.
from dotenv import load_dotenv
load_dotenv(override=True)

from prompt_engine.atmosphere_dna._base import get_room_dna
from prompt_engine.composer import compose_generation_prompt

assert os.environ.get("BIMODAL_ENABLED") == "1", (
    "BIMODAL_ENABLED != 1 — sans lui la DNA room context (TV-axis) est inactive ; "
    "ce test doit tourner en config prod (voir .env / run.sh)."
)

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(bool(cond))
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")

ATMOS = [
    ("warm_modern", "Warm Modern"), ("soft_luxury", "Soft Luxury"),
    ("japandi_calm", "Japandi Calm"), ("nordic_warmth", "Nordic Warmth"),
    ("tropical_escape", "Tropical Escape"),
]
AXIS = "television axis has priority"
FOCAL = "television as the living-room focal point"
BUDGET = 4300  # _MODE_BUDGETS["FIRST_VISION"]

print("\n=== Living Room TV-axis — garde-fou permanent ===")
for aid, label in ATMOS:
    # 1. DNA source : axis + focal dans le MÊME item, présent dans les 2 premiers (anti-[:2])
    rd = get_room_dna(aid, "living_room")
    cons = list(rd.room_specific_constraints) if rd and rd.room_specific_constraints else []
    merged_first2 = any((FOCAL in c and AXIS in c) for c in cons[:2])
    check(f"{aid:15} axis fusionné à la phrase TV & dans room_specific_constraints[:2]",
          merged_first2, cons[:2])

    # 2. compose : la règle atteint le prompt FINAL (survit [:2] + assembleur budget)
    p = compose_generation_prompt(
        style_label=label, room_type="living_room", room_description="",
        user_instruction="", iteration=1, history=[],
        generation_mode="preserve", edit_mode=None)
    check(f"{aid:15} 'television axis has priority' dans le prompt composé", AXIS in p, len(p))

    # 3. budget V1 (description vide) : dna_room_context (TV anchor) ne doit pas être droppé
    check(f"{aid:15} prompt V1 = {len(p)} <= budget {BUDGET}", len(p) <= BUDGET, len(p))

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
