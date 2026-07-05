"""Non-régression : conversion fonctionnelle de zone = commande d'EXÉCUTION → generate.
Couvre le bug device « Convert the right side of the room into an open kitchen » (répondu
conversationnel au lieu de générer). Aucune génération. Run:
PYTHONIOENCODING=utf-8 PYTHONPATH=. python _intent_conversion_validation.py"""
import sys
from prompt_engine.intent_classifier import classify_intent, ConversationIntent

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

def is_gen(msg, it=2):
    c = classify_intent(msg, iteration=it)
    return c.intent == ConversationIntent.GENERATE, c

def main():
    print("=== Le cas device exact → GENERATE (execute_refine, pas de tour de confirmation) ===")
    gen, c = is_gen("Convert the right side of the room into an open kitchen")
    check("« Convert the right side of the room into an open kitchen » → GENERATE", gen, f"{c.intent.value}/{c.reasoning}")
    check("  sub_intent = structural_change", c.sub_intent.value == "structural_change", c.sub_intent.value)

    print("\n=== Autres conversions de zone → GENERATE ===")
    for msg in [
        "convert this side into a bathroom",
        "turn the rear room into a dressing area",
        "transform the left side into a home office",
        "repurpose the corner as a walk-in closet",
        "convert the alcove into a home bar",
    ]:
        check(f"« {msg} » → GENERATE", is_gen(msg)[0])

    print("\n=== Non-régression : structure/edit explicites restent GENERATE ===")
    for msg in ["remove the right wall and add an open kitchen with an island",
                "add a partition wall", "move the sofa to the left"]:
        check(f"« {msg} » → GENERATE", is_gen(msg)[0])

    print("\n=== Garde-fous : opinion/appréciation restent CONSEIL (pas de génération) ===")
    for msg in ["should I convert the office into a bedroom?",
                "do you think an open kitchen would work here?",
                "the kitchen looks really nice"]:
        check(f"« {msg} » → PAS generate", not is_gen(msg)[0], is_gen(msg)[1].intent.value)

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(main())
