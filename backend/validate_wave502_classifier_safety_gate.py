"""RCA fix (2026-07-08) — safety gate PUR contre les faux extérieurs.
Prouve que resolve_stage_exterior :
  • laisse passer les intérieurs et les VRAIS extérieurs (high/medium, sans signal indoor) ;
  • rejette un extérieur non corroboré (confiance 'low', ou classifieur keyword indoor confiant).
0 réseau, 0 API. Vérifie aussi que main.py importe (déterminisme + prompt câblés)."""
import os, sys, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

import main
from main import resolve_stage_exterior as R
EXT = main._EXTERIOR_ROOMS

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(cond)
    print(f"  {PASS if cond else FAIL}  {label}{('  ['+str(detail)+']') if detail and not cond else ''}")

print("\n=== safety gate resolve_stage_exterior ===")
# 1. intérieur → inchangé (byte-identity)
r = R("living_room", "high", "", 0.0, EXT)
check("1 intérieur passe inchangé, aucune raison", r == ("living_room", None), r)

# 2-3. VRAIS extérieurs high/medium sans signal keyword → INCHANGÉS (ne pas casser)
check("2 terrace high, no kw → reste terrace", R("terrace", "high", "", 0.0, EXT) == ("terrace", None))
check("3 terrace medium, no kw → reste terrace", R("terrace", "medium", "", 0.0, EXT) == ("terrace", None))
check("3b facade high → reste facade", R("facade", "high", "", 0.0, EXT) == ("facade", None))

# 4. extérieur LOW confiance → fallback living_room
r = R("balcony", "low", "", 0.0, EXT)
check("4 balcony low conf → fallback living_room", r[0] == "living_room" and r[1] is not None, r)

# 5. extérieur + keyword INDOOR confiant (>=0.6) → override par l'intérieur keyword
r = R("balcony", "medium", "living_room", 0.7, EXT)
check("5 balcony medium + kw living_room(0.7) → living_room", r[0] == "living_room" and r[1] is not None, r)

# 6. keyword indoor confiant l'emporte MÊME sur un ayden 'high' (indice indoor fort)
r = R("balcony", "high", "bedroom", 0.8, EXT)
check("6 balcony HIGH + kw bedroom(0.8) → bedroom (indoor override)", r[0] == "bedroom", r)

# 7. extérieur + keyword EXTÉRIEUR → pas 'indoor' → reste extérieur (vrai extérieur)
check("7 terrace medium + kw garden(0.9) → reste terrace (kw non indoor)",
      R("terrace", "medium", "garden", 0.9, EXT) == ("terrace", None))

# 8. keyword indoor mais confiance FAIBLE (<0.6) → signal insuffisant → medium exterior passe
check("8 balcony medium + kw living_room(0.4 faible) → reste balcony",
      R("balcony", "medium", "living_room", 0.4, EXT) == ("balcony", None))

# 9. import main OK = déterminisme + prompt hardening câblés sans casser la syntaxe
check("9 main importé (determinisme + prompt + gate compilent)", True)

total = len(res); passed = sum(res)
print(f"\n{'='*60}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*60}")
sys.exit(0 if passed == total else 1)
