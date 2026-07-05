"""Refine V2 — validation du CANONICALIZER de type (post-Parser), 100% offline.
Un objet architectural + action add/remove/replace/open/close → STRUCTURE (générique).
Pièges gardés : wall-as-adjective, cabinet door, destinations, paint/state. NO gen.
Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _refine_canonicalize_validation.py"""
import sys
from refine.parser import Change, canonicalize_types, parse_deterministic

_fails = 0
def check(name, cond, got=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  got='+repr(got)) if (got and not ok) else ''}")

def canon(type_, object_, raw):
    c = Change(type=type_, object=object_, detail="", raw=raw)
    canonicalize_types([c])
    return c.type

# (type LLM initial, object, raw, type attendu après canonicalisation)
# ── DOIT devenir STRUCTURE (objet architectural + action structurelle) ──
SHOULD_STRUCTURE = [
    ("remove", "right wall", "remove the right wall"),
    ("remove", "left wall", "knock down the left wall"),
    ("remove", "dividing wall", "take down the dividing wall"),
    ("remove", "partition wall", "demolish the partition wall"),
    ("remove", "back window", "remove the back window"),
    ("replace", "window", "replace the window with a bigger one"),
    ("remove", "window", "close the back window"),          # LLM a dit remove
    ("modify", "window", "board up the window"),            # LLM a dit modify → verbe board up
    ("add",    "window", "add a new window on the right wall"),
    ("add",    "bay window", "add a bay window"),
    ("add",    "skylight", "add a skylight in the ceiling"),
    ("add",    "opening", "create a larger opening"),
    ("remove", "opening", "close this opening"),
    ("modify", "doorway", "widen the doorway"),             # verbe widen
    ("add",    "doorway", "add a doorway to the kitchen"),
    ("remove", "archway", "remove the archway"),
    ("modify", "ceiling", "lower the ceiling"),             # verbe lower
    ("replace", "partition", "replace the partition with a glass one"),
    ("add",    "partition", "add a partition"),
    ("remove", "the wall", "remove the wall"),              # article dans l'objet
]

# ── NE DOIT PAS devenir structure ──
SHOULD_KEEP = [
    ("move",   "TV", "move the TV to the right wall", "move"),          # destination, objet=TV
    ("move",   "sofa", "move the sofa against the wall", "move"),
    ("modify", "wall", "paint the wall blue", "modify"),                # action=modify (hors gate)
    ("modify", "wall", "make the wall darker", "modify"),
    ("remove", "wall art", "remove the wall art", "remove"),            # wall = adjectif
    ("remove", "wall clock", "remove the wall clock", "remove"),
    ("add",    "wall shelves", "add wall shelves", "add"),
    ("add",    "mirror", "hang a mirror on the wall", "add"),
    ("remove", "cabinet door", "remove the cabinet door", "remove"),    # porte de meuble
    ("remove", "fridge door", "remove the fridge door", "remove"),
    ("replace", "sofa", "replace the sofa with a leather one", "replace"),
    ("add",    "coffee table", "add a coffee table", "add"),
    ("remove", "rug", "remove the rug", "remove"),
    ("add",    "flowers", "add flowers", "add"),
    ("add",    "kitchen", "add a kitchen", "add"),                      # zone fonctionnelle ≠ élément archi
    ("modify", "curtains", "close the curtains", "modify"),             # objet=curtains, pas archi
    ("move",   "window seat", "move the window seat", "move"),          # 'window seat' = meuble (tête=seat)
]


def main():
    print("=== DOIT devenir STRUCTURE ===")
    for t, o, raw in SHOULD_STRUCTURE:
        got = canon(t, o, raw)
        check(f"[{t:8}|{o:14}] {raw}", got == "structure", got)

    print("\n=== NE DOIT PAS changer ===")
    for t, o, raw, exp in SHOULD_KEEP:
        got = canon(t, o, raw)
        check(f"[{t:8}|{o:14}] {raw} → {exp}", got == exp, got)

    print("\n=== ADVERSARIAL (edges découverts par le workflow, figés) ===")
    # DOIT être structure
    for t, o, raw in [
        ("modify", "open staircase", "wall off the open staircase to make a hallway"),  # verbe fort
        ("modify", "kitchen", "open up the kitchen to the living room"),                 # zone-open
        ("add", "glass partition", "add a glass partition to split the room"),
        ("remove", "half-wall", "knock through the half-wall"),
        ("replace", "French doors", "replace the French doors with a glass wall"),
        ("add", "clerestory window", "add a clerestory window above the doors"),
        ("modify", "windows", "enlarge the windows along the facade"),
    ]:
        check(f"[adv+] {raw}", canon(t, o, raw) == "structure", canon(t, o, raw))
    # NE doit PAS être structure
    for t, o, raw, exp in [
        ("add", "kitchen", "add a kitchen to the open area", "add"),          # 'open' adjectif
        ("add", "ceiling beams", "add decorative ceiling beams", "add"),
        ("add", "wall panelling", "add decorative wall panelling", "add"),
        ("replace", "wall sconce", "replace the wall sconce", "replace"),
        ("add", "room divider", "add a room divider screen", "add"),
    ]:
        check(f"[adv-] {raw} → {exp}", canon(t, o, raw) == exp, canon(t, o, raw))

    print("\n=== bout-en-bout (parse_deterministic déjà canonicalisé) ===")
    check("'remove the right wall' → structure", parse_deterministic("remove the right wall")[0].type == "structure")
    check("'close the back window' → structure", parse_deterministic("close the back window")[0].type == "structure")
    check("'add a new window on the right wall' → structure", parse_deterministic("add a new window on the right wall")[0].type == "structure")
    check("'move the TV to the right wall' → move", parse_deterministic("move the TV to the right wall")[0].type == "move")
    check("'remove the wall art' → remove (pas structure)", parse_deterministic("remove the wall art")[0].type != "structure")
    check("idempotent (2e passe)", (lambda cs: (canonicalize_types(cs), [c.type for c in cs])[1])(parse_deterministic("remove the right wall")) == ["structure"])

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(main())
