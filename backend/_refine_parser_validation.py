"""Refine Engine V2 — validation du Composant 1 (Parser). OFFLINE, aucun appel image.
Run: PYTHONPATH=. python _refine_parser_validation.py"""
import asyncio
import sys

from refine.parser import parse_changes, parse_deterministic, Change, TYPES

_fails = 0
def check(name, cond, detail=""):
    global _fails
    ok = bool(cond); _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {name}{('  '+detail) if (detail and not ok) else ''}")


# ── Fake OpenAI client (pour tester le chemin LLM sans réseau) ────────────────
class _Msg:  __slots__=("content");
def _resp(content):
    m=_Msg(); m.content=content
    return type("R",(),{"choices":[type("C",(),{"message":m})()]})()
class _FakeClient:
    def __init__(self, content): self._c=content
    class _Chat:
        pass
    @property
    def chat(self):
        outer=self
        class Comp:
            async def create(self, **kw): return _resp(outer._c)
        return type("Ch",(),{"completions":Comp()})()


def types_of(chs): return [c.type for c in chs]

async def main():
    print("=== DÉTERMINISTE — simple (type attendu) ===")
    simple = [
        ("Move the TV to the right wall.", "move"),
        ("Rotate the sofa.", "move"),
        ("Reverse the sofa so it faces the TV.", "move"),
        ("Add curtains.", "add"),
        ("Add a large plant in the corner.", "add"),
        ("Remove the dining table.", "remove"),
        ("Get rid of the rug.", "remove"),
        ("Replace the sofa with a leather one.", "replace"),
        ("Make it warmer.", "modify"),
        ("Make the walls darker.", "modify"),
        ("Open up the kitchen.", "structure"),
        ("Add a partition wall.", "structure"),
        ("Create an arch in the left wall.", "structure"),
    ]
    for msg, exp in simple:
        chs = parse_deterministic(msg)
        got = chs[0].type if len(chs) == 1 else f"n={len(chs)}"
        check(f"{msg!r} → {exp}", len(chs) == 1 and chs[0].type == exp, f"got={got}")

    print("\n=== DÉTERMINISTE — multi (nombre + types clés) ===")
    m1 = parse_deterministic("Move the TV to the right wall, rotate the sofa to face it, remove the dining table.")
    check("3 changements + move/move/remove", len(m1) == 3 and types_of(m1) == ["move","move","remove"], str(types_of(m1)))
    m2 = parse_deterministic("Add curtains and change the chandelier then remove the table")
    check("3 changements, [0]=add [2]=remove", len(m2) == 3 and m2[0].type=="add" and m2[2].type=="remove", str(types_of(m2)))
    m3 = parse_deterministic("Break the wall and move the bed")
    check("2 changements structure+move", len(m3) == 2 and types_of(m3) == ["structure","move"], str(types_of(m3)))
    m4 = parse_deterministic("Make the room warmer, replace the rug with a darker one, add a floor lamp")
    check("3 changements modify/replace/add", len(m4) == 3 and types_of(m4) == ["modify","replace","add"], str(types_of(m4)))
    check("raw conservé verbatim", m1[0].raw == "Move the TV to the right wall")
    check("object extrait (TV)", m1[0].object.lower().startswith("tv"))

    print("\n=== LLM (fake client) ===")
    good = '{"changes":[{"type":"move","object":"TV","detail":"to the right wall","raw":"Move the TV"},' \
           '{"type":"weird","object":"lamp","detail":"","raw":"add a lamp"}]}'
    chs = await parse_changes("whatever", client=_FakeClient(good))
    check("LLM parse → 2 changements", len(chs) == 2, f"n={len(chs)}")
    check("LLM type valide conservé (move)", chs and chs[0].type == "move")
    check("LLM type invalide → coercition 'modify'", len(chs) == 2 and chs[1].type == "modify")
    check("tous les types ∈ TYPES", all(c.type in TYPES for c in chs))

    bad = await parse_changes("Remove the dining table.", client=_FakeClient("not json at all"))
    check("LLM invalide → fallback déterministe (remove)", len(bad) == 1 and bad[0].type == "remove")

    empty = await parse_changes("   ", client=_FakeClient(good))
    check("message vide → []", empty == [])

    print(f"\n{'ALL GREEN' if not _fails else str(_fails)+' FAILURE(S)'}")
    return 1 if _fails else 0

sys.exit(asyncio.run(main()))
