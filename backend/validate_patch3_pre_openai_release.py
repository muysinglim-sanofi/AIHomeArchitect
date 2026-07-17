"""PATCH 3 (2026-07-16) — RELEASE du HOLD sur erreur PRÉ-OpenAI.

Anomalie prouvée : /generate pose un HOLD atomique (billing.try_hold) AVANT OpenAI ; si une
erreur survient APRÈS le HOLD et AVANT le 1er appel OpenAI (ex. IMAGE_FETCH_FAILED, image source
Supabase supprimée), aucune transition terminale n'était émise → le HOLD(-1) restait ORPHELIN
(compteur premium décrémenté) jusqu'au reconciler ~12 min. Le fix émet, au site d'échec source,
EXACTEMENT la même paire terminale que la voie « OpenAI épuisé » (fail_generation +
observe_intent_end 'FAILED') — dont le cœur billing est apply_billing_for_intent_transition.

Ce validateur prouve, sans DB/réseau (FilterSupa), le CONTRAT du billing sur lequel repose le fix :
  • HOLD posé puis transition 'FAILED' (pré-OpenAI) → RELEASE(+1) → NET 0 (compteur intact) ;
  • rejeu de la transition 'FAILED' → toujours net 0 (aucun double-RELEASE) ;
  • succès normal → transition 'SUCCEEDED' → COMMIT une seule fois → net -1 (débit légitime).
"""
import os, sys, asyncio, logging
sys.path.insert(0, os.path.dirname(__file__)); logging.disable(logging.CRITICAL)
import billing
from _billing_fakes import FilterSupa

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"; res = []
def check(l, c, d=""):
    res.append(bool(c)); print(f"  {PASS if c else FAIL}  {l}{('  ['+str(d)+']') if d and not c else ''}")
def run(c): return asyncio.run(c)

FUT = "2099-01-01T00:00:00+00:00"; PS = "2020-01-01T00:00:00+00:00"
def ap(pid="pA"): return {"id": pid, "user_id": "u1", "status": "ACTIVE", "starts_at": PS, "ends_at": FUT}
def G(d, p): return {"user_id": "u1", "available_delta": d, "entry_type": "GRANT", "pass_id": p,
                     "idempotency_key": f"grant:{p}"}
def bucket(fs, pid="pA"):
    return sum(int(r.get("available_delta") or 0)
               for r in fs.tables.get("ledger_entries", []) if r.get("pass_id") == pid)

print("\n=== PATCH 3 · RELEASE du HOLD sur erreur pré-OpenAI (net 0) ===")

# 1. HOLD posé (pré-OpenAI) puis erreur pré-OpenAI → transition FAILED → RELEASE → NET 0.
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [G(30, "pA")]})
run(billing.try_hold(user_id="u1", intent_id="gen1", tier="premium", supa=fs))
check("1a HOLD posé → bucket débité à 29 (réservation)", bucket(fs) == 29, bucket(fs))
run(billing.apply_billing_for_intent_transition(
    intent_id="gen1", new_status="FAILED", user_id="u1", is_free=False, supa=fs))
check("1b erreur pré-OpenAI → FAILED → RELEASE → NET 0 (compteur premium intact = 30)",
      bucket(fs) == 30, bucket(fs))

# 2. Rejeu de la transition terminale FAILED → toujours net 0 (aucun double-RELEASE).
run(billing.apply_billing_for_intent_transition(
    intent_id="gen1", new_status="FAILED", user_id="u1", is_free=False, supa=fs))
check("2 rejeu FAILED (idempotent) → toujours 30 (pas de double-RELEASE)", bucket(fs) == 30, bucket(fs))

# 3. Succès normal → SUCCEEDED → COMMIT une seule fois → net -1 (débit LÉGITIME conservé).
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [G(30, "pA")]})
run(billing.try_hold(user_id="u1", intent_id="gen2", tier="premium", supa=fs))
run(billing.apply_billing_for_intent_transition(
    intent_id="gen2", new_status="SUCCEEDED", user_id="u1", is_free=False, supa=fs))
check("3a succès → COMMIT → net -1 (30→29, débit conservé sur vraie génération)", bucket(fs) == 29, bucket(fs))
run(billing.apply_billing_for_intent_transition(
    intent_id="gen2", new_status="SUCCEEDED", user_id="u1", is_free=False, supa=fs))
check("3b rejeu SUCCEEDED (idempotent) → toujours 29 (COMMIT une seule fois)", bucket(fs) == 29, bucket(fs))

# 4. Deny (HOLD jamais accordé) → aucune ligne HOLD → rien à relâcher (pré-OpenAI deny propre).
fs = FilterSupa(tables={"passes": [ap()], "ledger_entries": [G(0, "pA")]})
g = run(billing.try_hold(user_id="u1", intent_id="gen3", tier="premium", supa=fs))
holds = [r for r in fs.tables.get("ledger_entries", []) if r.get("entry_type") == "HOLD"]
check("4 solde 0 → deny, AUCUN HOLD posé (rien à relâcher, net 0)",
      not g["granted"] and len(holds) == 0 and bucket(fs) == 0, (g, len(holds)))

total = len(res); passed = sum(res)
print(f"\n{'='*64}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*64}")
sys.exit(0 if passed == total else 1)
