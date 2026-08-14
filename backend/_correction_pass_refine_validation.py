"""Correction Pass (Groupe 2026-08-13) — validation A1..A5 : couleurs légitimes,
protection objets absurdes, room_type dégradé, routage conversationnel, finition vs structure.

100% HORS-LIGNE : aucun client OpenAI n'est instancié (advise(..., client=None), les
classifieurs sont purement regex). Aucun appel réseau, aucun appel image.

Chaque check imprime la valeur OBSERVÉE (pas seulement PASS/FAIL) : ce harnais sert
d'abord à ENREGISTRER l'état BEFORE — une partie DOIT échouer avant la correction.

Matrice couverte (§7 du cahier des charges) :
  BLOC 1  couleurs légitimes            → verdict advisor != red
  BLOC 2  objets réellement absurdes    → verdict advisor == red (+ alternative)
  BLOC 3  room_type dégradé             → pas de RED dur sur pièce inconnue
  BLOC 4  routage /chat should_generate → édition exécutable vs question d'avis
  BLOC 5  parser finition vs structure  → type != structure sur une propriété

Run: PYTHONIOENCODING=utf-8 PYTHONPATH=. python _correction_pass_refine_validation.py
"""
import asyncio
import sys

from refine.parser import parse_deterministic, canonicalize_types
from refine.advisor import advise
from prompt_engine.intent_classifier import classify_intent, ConversationIntent

_fails = 0
_total = 0


def check(label, cond, got=""):
    """Un check = 1 ligne. `got` est TOUJOURS imprimé (état BEFORE lisible)."""
    global _fails, _total
    _total += 1
    ok = bool(cond)
    _fails += (not ok)
    print(f"  [{'OK ' if ok else 'FAIL'}] {label}   observed={got!r}")


def note(label, got=""):
    """Ligne informative (ne compte pas dans le score) — contexte de l'état BEFORE."""
    print(f"  [ .. ] {label}   observed={got!r}")


# ── Chaîne advisor complète, hors-ligne ──────────────────────────────────────
async def _advise_msg(message, room_type):
    """parse_deterministic → canonicalize_types → advise(client=None).
    canonicalize_types est ré-appliqué explicitement (idempotent) pour rendre la
    chaîne du cahier des charges visible dans le test."""
    changes = canonicalize_types(parse_deterministic(message))
    res = await advise(changes, room_type, client=None)
    return res, changes


async def _verdict(message, room_type):
    res, changes = await _advise_msg(message, room_type)
    types = "+".join(c.type for c in changes)
    return res.overall.value, types, res


# ═══════════════════════════════════════════════════════════════════════════
async def bloc1():
    """A1 — un NOM DE COULEUR seul ne doit JAMAIS produire un RED.
    Mécanisme visé : advisor.py:98-103 (_ABSURD_INTERIOR contient pool|beach|ocean|
    sea|forest|jungle) + advisor.py:158-167 (règle 1 appliquée AVANT tout test de type)."""
    print("\n=== BLOC 1 — Couleurs légitimes (advisor) : verdict attendu != red ===")
    phrases = [
        "paint the walls forest green",
        "paint the walls ocean blue",
        "make the walls sea green",
        "make the walls ivory white",
        "paint the walls sage green",
        "change the sofa to forest green",
        "change the walls to forest green",
        "change the walls to ivory white",
    ]
    for room in ("Living Room", "Bedroom"):
        print(f"  -- room_type={room!r}")
        for msg in phrases:
            v, types, _ = await _verdict(msg, room)
            check(f"[{room}] {msg!r} != red", v != "red", f"verdict={v} types={types}")
            if v == "yellow":
                note(f"      (friction résiduelle : YELLOW, pas GREEN) {msg!r}", v)


async def bloc2():
    """A2 — la protection « objet réellement inapproprié » doit RESTER active.
    Choix d'assertion : verdict == 'red' STRICT (et non « non-GREEN »), pour deux
    raisons documentées :
      1. contrat écrit du composant (advisor.py:15-16) : RED = absurde pour cette
         pièce, toujours assorti d'une alternative + override ; YELLOW = « je ne sais
         pas DE QUEL élément tu parles » (ambiguïté de cible), ce qui n'est pas le cas ici ;
      2. non-régression : le harnais légataire _refine_advisor_validation.py:97-98
         asserte déjà == 'red' sur exactement ces formes. Relâcher en « non-GREEN »
         masquerait une bascule RED→YELLOW qui casserait ce harnais.
    On asserte AUSSI la présence de l'alternative (anti-paternalisme : jamais un mur)."""
    print("\n=== BLOC 2 — Objets réellement inappropriés (Bedroom) : verdict attendu == red ===")
    for msg in [
        "add a swimming pool in the bedroom",
        "put a Ferrari in the bedroom",
        "add an ocean inside the living room",
        "add a horse in the bedroom",
    ]:
        v, types, res = await _verdict(msg, "Bedroom")
        check(f"{msg!r} == red", v == "red", f"verdict={v} types={types}")
        alts = [a.alternative for a in res.advices if a.verdict.value == "red"]
        check(f"{msg!r} → alternative fournie (jamais un mur)",
              bool(alts) and all(alts), alts)


async def bloc3():
    """A3 — room_type dégradé (vide / None / libellé produit / FR / KM).
    Mécanisme visé : advisor.py:130-138 — _room_is_interior('') retourne True
    (« défaut prudent »), donc le set absurde s'applique à une pièce INCONNUE."""
    print("\n=== BLOC 3 — room_type dégradé : pas de RED dur sur pièce inconnue ===")
    rooms = ["", None, "Your space", "Salon", "Chambre principale", "បន្ទប់ទទួលភ្ញៀវ"]
    for room in rooms:
        for msg in ("add a swimming pool", "add a car in the driveway"):
            v, types, _ = await _verdict(msg, room)
            check(f"room={room!r} + {msg!r} != red", v != "red",
                  f"verdict={v} types={types}")
    print("  -- contrôle inverse (la protection reste entière sur une pièce CONNUE)")
    v, types, _ = await _verdict("add a swimming pool", "Bedroom")
    check("room='Bedroom' + 'add a swimming pool' == red", v == "red",
          f"verdict={v} types={types}")


def bloc4():
    """A4 — routage conversationnel. Fonction réellement utilisée par /chat :
    main.py:2426 `intent_class = classify_intent(message_en, iteration)` puis
    main.py:2653 `should_generate = (intent_class.intent == ConversationIntent.GENERATE)`.
    On appelle donc classify_intent TELLE QUELLE, iteration=2 (iteration 1 génère
    toujours par construction, intent_classifier.py:966-972 → non discriminant).
    Mécanisme visé : intent_classifier.py:144-160 (_LOCAL_EDIT SANS paint/repaint/peins)
    vs edit_intent.py:59-69 (_LOCAL_EDIT_SIGNALS AVEC paint|colour|color)."""
    print("\n=== BLOC 4 — Routage /chat (classify_intent, iteration=2) ===")
    print("  -- éditions exécutables attendues : should_generate == True")
    for msg in [
        "Paint the walls ivory white.",
        "Repaint the wall white.",
        "Make the walls forest green.",
        "Peins les murs en blanc ivoire.",
        "Mets les murs en blanc ivoire.",
        "Repeins le mur en blanc.",
    ]:
        ic = classify_intent(msg, 2)
        sg = (ic.intent == ConversationIntent.GENERATE)
        check(f"{msg!r} → should_generate", sg,
              f"intent={ic.intent.value} sub={ic.sub_intent.value} why={ic.reasoning}")

    print("  -- contrôles : questions d'avis, PAS de génération automatique")
    for msg in [
        "Should I paint the walls white?",
        "Est-ce que je devrais peindre les murs en blanc ?",
    ]:
        ic = classify_intent(msg, 2)
        sg = (ic.intent == ConversationIntent.GENERATE)
        check(f"{msg!r} → PAS de génération", not sg,
              f"intent={ic.intent.value} sub={ic.sub_intent.value} why={ic.reasoning}")


def bloc5():
    """A5 — finition (propriété) vs structure (géométrie).
    Mécanisme visé : parser.py:143-145 — promotion en 'structure' dès que
    action_ok(add|remove|replace|_STRUCT_VERB) and _is_arch_object(objet) ;
    'change the walls to X' est typé 'replace' (parser.py:45-47) donc promu."""
    print("\n=== BLOC 5 — Parser : finition vs structure ===")
    print("  -- modification de PROPRIÉTÉ : type attendu != structure")
    for msg in [
        "change the walls to ivory white",
        "paint the walls ivory white",
        "repaint the wall white",
    ]:
        chs = parse_deterministic(msg)
        types = [c.type for c in chs]
        objs = [c.object for c in chs]
        check(f"{msg!r} type != structure", all(t != "structure" for t in types),
              f"types={types} objects={objs}")

    print("  -- contrôles à NE PAS casser : type attendu == structure")
    for msg in [
        "remove the wall",
        "open the wall",
        "break the wall",
        "build a wall",
        "enlarge the window opening",
    ]:
        chs = parse_deterministic(msg)
        types = [c.type for c in chs]
        objs = [c.object for c in chs]
        check(f"{msg!r} type == structure", any(t == "structure" for t in types),
              f"types={types} objects={objs}")


async def bloc6():
    """BLOC 6 — les 13 libellés RÉELLEMENT envoyés par l'UI doivent être RÉSOLUS.

    Trouvé en revue adversariale (2026-08-13) : A2 remplace le « défaut prudent »
    par trois états, ce qui est voulu — mais toute pièce intérieure ABSENTE de
    _INTERIOR_ROOMS bascule alors en `unknown` et PERD le véto intérieur. C'était
    le cas d'« Entrance Hall » (RoomTypeImages.interiorIds : entranceHall), qui ne
    matchait ni "hallway" ni "entryway" : « add a swimming pool » y passait de RED
    à GREEN. Ce bloc verrouille les 13 libellés de production contre toute
    évolution ultérieure du set.
    """
    from refine.advisor import _room_kind
    print("\n=== BLOC 6 — résolution des 13 libellés canoniques de l'UI ===")
    expected = {
        # RoomTypeImages.interiorIds
        "Living Room": "interior", "Master Bedroom": "interior", "Kitchen": "interior",
        "Bathroom": "interior", "Home Office": "interior", "Dining Room": "interior",
        "Entrance Hall": "interior",
        # RoomTypeImages.exteriorIds
        "House Facade": "exterior", "Garden": "exterior", "Pool Area": "exterior",
        "Terrace": "exterior", "Balcony": "exterior", "Driveway": "exterior",
    }
    for label, exp in expected.items():
        got = _room_kind(label)
        check(f"_room_kind({label!r}) == {exp!r}", got == exp, f"obtenu={got!r}")

    print("  -- conséquence : le véto intérieur doit s'appliquer dans un hall d'entrée")
    chs = canonicalize_types(parse_deterministic("add a swimming pool"))
    res = await advise(chs, "Entrance Hall", client=None)
    verdicts = [str(getattr(a.verdict, "value", a.verdict)) for a in res.advices]
    check("'add a swimming pool' en Entrance Hall reste RED",
          any(v == "red" for v in verdicts), f"verdicts={verdicts}")


async def main():
    print("=== CORRECTION PASS — validation offline (état BEFORE si lancé avant le fix) ===")
    await bloc1()
    await bloc2()
    await bloc3()
    bloc4()
    bloc5()
    await bloc6()
    passed = _total - _fails
    print(f"\n=== RÉCAPITULATIF : {passed}/{_total} PASS "
          f"({_fails} FAILURE(S)) ===")
    return 1 if _fails else 0


sys.exit(asyncio.run(main()))
