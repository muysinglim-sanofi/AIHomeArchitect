"""Wave 4.9.4 (PR-1) — Confirmation resolver : composées + 'anyway', veto négation,
détecteur de souhait. Backend-only, conversationnel. 0 OpenAI, 0 image.

Contrat : confirmation reconnue + pending existant → promotion GENERATE (une seule
génération) ; « ok go ahead » ne peut jamais devenir une demande d'éclairage.
"""
import os, sys, logging
sys.path.insert(0, os.path.dirname(__file__))
logging.disable(logging.CRITICAL)

from prompt_engine.intent_classifier import (
    is_confirmation, _has_design_request, pending_design_sub_intent,
    resolve_confirmation, SubIntent, ConversationIntent,
)

PASS = "\033[92mPASS\033[0m"; FAIL = "\033[91mFAIL\033[0m"
res = []
def check(label, cond, detail=""):
    res.append(cond)
    sfx = f"  [{detail}]" if detail and not cond else ""
    print(f"  {PASS if cond else FAIL}  {label}{sfx}")

print("\n=== A. confirmations COMPOSÉES + 'anyway' reconnues (liste user) ===")
for ph in ["ok go ahead", "yes go ahead", "ok do it", "do it anyway",
           "go ahead anyway", "yes do it", "please proceed"]:
    check(f"A confirmation: {ph!r}", is_confirmation(ph), ph)

print("\n=== A'. originaux préservés (non-régression wave477) ===")
for ph in ["go ahead", "continue", "ok", "okay", "yes", "yeah", "yep", "sure",
           "alright", "let's do it", "do it", "show me", "generate", "proceed",
           "go for it", "oui", "vas-y", "d'accord"]:
    check(f"A' preserved: {ph!r}", is_confirmation(ph), ph)

print("\n=== B. NÉGATIONS / différés rejetés (liste user) ===")
for ph in ["ok but don't do it", "do not go ahead", "yes maybe later",
           "I don't want it anyway", "ok explain first"]:
    check(f"B NOT confirmation: {ph!r}", not is_confirmation(ph), ph)

print("\n=== B'. négatifs originaux préservés (non-régression wave477) ===")
for ph in ["what do you think?", "maybe", "interesting", "not sure",
           "ok but change the sofa", "add a lamp", "thanks", "hmm",
           "make it warmer"]:
    check(f"B' NOT confirmation: {ph!r}", not is_confirmation(ph), ph)

print("\n=== C. détecteur de SOUHAIT restreint aux pièces/zones (positifs) ===")
for ph in ["I would like a bedroom in the rear space",
           "I want a kitchen on the right",
           "I'd like a dressing area in that corner",
           "I would like a home office by the window"]:
    check(f"C wish detected: {ph!r}", _has_design_request(ph), ph)

print("\n=== C'. NÉGATIFS obligatoires — jamais de faux pending design (liste user) ===")
for ph in ["I want a refund", "I want a subscription",
           "I would like an explanation", "I need help with my account",
           "I would like to know how branching works"]:
    check(f"C' NOT a design request: {ph!r}", not _has_design_request(ph), ph)

print("\n=== D. CONTRAT — confirmation + pending → GENERATE ; jamais éclairage ===")
# Historique réel : demande design suivie d'une réponse assistant (ici éclairage).
PENDING_BEDROOM = [
    {"role": "user", "content": "add a bedroom in the rear space"},
    {"role": "ai",   "content": "Here are some lighting ideas for that corner…"},
]
PENDING_WISH = [
    {"role": "user", "content": "I would like a bedroom in the rear space"},
    {"role": "ai",   "content": "A sleeping nook there could feel cozy…"},
]
NO_PENDING = [
    {"role": "user", "content": "what do you think of this?"},
    {"role": "ai",   "content": "I like it."},
]

r1 = resolve_confirmation("ok go ahead", PENDING_BEDROOM)
check("D1 'ok go ahead' + pending bedroom → GENERATE (PAS éclairage)",
      r1 is not None and r1.intent == ConversationIntent.GENERATE, r1)
r2 = resolve_confirmation("do it anyway", PENDING_BEDROOM)
check("D2 'do it anyway' + pending → GENERATE",
      r2 is not None and r2.intent == ConversationIntent.GENERATE, r2)
r3 = resolve_confirmation("ok go ahead", NO_PENDING)
check("D3 'ok go ahead' + AUCUN pending → None (ne fabrique rien)",
      r3 is None, r3)
r4 = resolve_confirmation("go ahead", PENDING_WISH)
check("D4 'go ahead' + pending SOUHAIT ('I would like a bedroom') → GENERATE",
      r4 is not None and r4.intent == ConversationIntent.GENERATE, r4)
# pending détecté ?
check("D5 pending_design_sub_intent(PENDING_BEDROOM) non-None",
      pending_design_sub_intent(PENDING_BEDROOM) is not None)
check("D6 pending_design_sub_intent(PENDING_WISH) non-None (via _WISH)",
      pending_design_sub_intent(PENDING_WISH) is not None)

total = len(res); passed = sum(res)
print(f"\n{'='*60}\n  TOTAL {total}  PASSED {passed}  FAILED {total-passed}\n{'='*60}")
sys.exit(0 if passed == total else 1)
