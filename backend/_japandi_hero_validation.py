# -*- coding: utf-8 -*-
"""JAPANDI HERO — contrat sémantique du bloc HERO FURNISHING. Zéro appel fournisseur.

Le défaut corrigé : le HERO Japandi du Pure Switch ne nommait que 3 rôles (assise,
table basse, éclairage) et ne portait quasiment aucun vocabulaire de FORME. Un
WM→Japandi se réduisait donc à un changement de matériaux — mêmes volumes pleins,
mêmes coussins rebondis — au lieu d'une silhouette Japandi (ossature apparente,
assises fines). Mesure de départ : seuls 2 mots de forme du HERO Japandi étaient
absents du HERO Warm Modern (« frame », « minimalist »).

Ce banc épingle les DEUX faces :
  - ce qui doit changer  : couverture des 7 rôles (C1) + distinction vs WM (C2) ;
  - ce qui ne doit PAS bouger : pas de hardcoding de paire (C3), V1 byte-identique
    (C4), règle TV intacte (C5), 9 clauses de préservation intactes (C6), budget
    FIRST_VISION tenu (C7), 4 autres atmosphères byte-identiques (C8).

C1 et C2 échouent volontairement sur l'arbre PROD (3f03d6d) : c'est la preuve que
le banc mesure bien la chose qu'on corrige. C3→C8 passent sur les DEUX arbres.

C1 ne teste AUCUNE phrase exacte : il teste des FAMILLES de termes (rôle) et un
vocabulaire de CONSTRUCTION, clause par clause — le wording reste libre de bouger.

Lancement :  python _japandi_hero_validation.py            (arbre courant)
             python _japandi_hero_validation.py <backend>  (autre arbre)
"""
from __future__ import annotations

import contextlib
import hashlib
import inspect
import io
import logging
import os
import pathlib
import re
import sys

# ---------------------------------------------------------------- environnement
# Config PROD obligatoire : sans BIMODAL_ENABLED=1 le composer ne revele pas
# dna_room_context (l'ancre TV de C5) ; sans SWITCH_BLOCK_COMPACT=1 c'est la table
# PLEINE qui partirait, pas la compacte servie sur Render. Voir run.sh.
_ARG = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else __file__).resolve()
TREE = _ARG if _ARG.is_dir() else _ARG.parent

_ENVF = pathlib.Path(r"C:/Projects/AIHomeArchitect-staging/backend/.env.mobile-staging.local")
if _ENVF.exists():
    for _raw in _ENVF.read_text(encoding="utf-8").splitlines():
        _l = _raw.strip()
        if _l and not _l.startswith("#") and "=" in _l:
            _k, _, _v = _l.partition("=")
            os.environ.setdefault(_k.strip(), _v.strip())

os.environ["APP_ENV"] = "mobile_mvp_baseline"
os.environ["BIMODAL_ENABLED"] = "1"
os.environ["SWITCH_BLOCK_COMPACT"] = "1"
os.environ.setdefault("SWITCH_REDESIGN_PILOT", "1")
os.environ.pop("AYDEN_FACADE_DESIGN", None)
os.environ.setdefault("OPENAI_API_KEY", "sk-not-used")
os.environ.setdefault("SUPABASE_URL", "https://placeholder.supabase.co")
for _k in ("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_ANON_KEY", "SUPABASE_KEY",
           "SUPABASE_JWT_SECRET"):
    os.environ.setdefault(_k, "ph")

sys.path.insert(0, str(TREE))
os.chdir(TREE)
with contextlib.redirect_stdout(io.StringIO()):
    import main  # noqa: F401
logging.disable(logging.CRITICAL)

from prompt_engine.composer_v2 import compose_generation_prompt as C  # noqa: E402
from prompt_engine.switch_redesign import build_switch_hero_block as HERO  # noqa: E402

# ------------------------------------------------------------------- affichage
_OK, _KO = "\033[92mPASS\033[0m", "\033[91mFAIL\033[0m"
_res: list[tuple[bool, str]] = []


def check(label: str, cond, detail="") -> None:
    cond = bool(cond)
    _res.append((cond, label))
    tail = "   [" + str(detail) + "]" if detail and not cond else ""
    print("  " + (_OK if cond else _KO) + "  " + label + tail)


def sha(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


# ------------------------------------------------------------------ vocabulaire
# CONSTRUCTION : ossature / assemblage / epaisseur — le vocabulaire qui dit
# COMMENT un meuble est bati. Volontairement SANS « low » ni « minimalist » :
# trop generiques, et « low table » se validerait lui-meme (tautologie).
CONSTRUCTION = {
    "frame", "open-frame", "post-and-rail", "rail", "slab", "plinth", "spindle",
    "trestle", "slatted", "slat", "inset", "squared", "flush", "recessed",
    "slim", "thin", "cane", "paper-cord", "joinery", "tub", "plump", "rolled",
    "rounded", "pad", "tapered", "panelled", "boxy",
}

# FORME (C2) : vocabulaire plus large de silhouette / proportion, celui qui sert
# a COMPARER deux atmospheres. Il inclut ce que porte le HERO Warm Modern (low,
# modular, chunky, block, arched, clean, straight, leg, flat) et « minimalist ».
FORM = CONSTRUCTION | {
    "low", "high", "deep", "flat", "chunky", "block", "base", "leg", "curved",
    "tufted", "channel", "modular", "clean", "straight", "arched", "sculptural",
    "minimalist", "live-edge", "cushioned", "upright", "backed",
}


def _tokens(text: str) -> set[str]:
    """Tokens minuscules, composes eclates (open-frame -> open-frame/open/frame)
    et pluriels reduits (frames -> frame). Pas de sous-chaine : « grounded » ne
    produit PAS « round »."""
    out: set[str] = set()
    for raw in re.split(r"[^a-z0-9\-]+", text.lower()):
        raw = raw.strip("-")
        if not raw:
            continue
        parts = {raw} | {p for p in raw.split("-") if p}
        for p in list(parts):
            if p.endswith("s") and len(p) > 3:
                parts.add(p[:-1])
        out |= parts
    return out


def form_words(text: str) -> set[str]:
    return _tokens(text) & FORM


def construction_words(text: str) -> set[str]:
    return _tokens(text) & CONSTRUCTION


def clauses(text: str) -> list[str]:
    """Le HERO est ecrit en clauses « role -> forme » separees par ; . :"""
    return [c.strip() for c in re.split(r"[;.:]", text) if c.strip()]


def has_role(clause: str, patterns: tuple[str, ...]) -> bool:
    return any(re.search(p, clause, re.I) for p in patterns)


# 7 roles x familles de synonymes (regex a frontieres de mots, pluriel tolere).
# \bchairs?\b ne matche PAS « armchairs » — pas de collision entre les 2 roles.
ROLES: list[tuple[str, tuple[str, ...]]] = [
    ("sofa", (r"\bsofas?\b", r"\bcouch(es)?\b", r"\bsettees?\b", r"\bseating\b")),
    ("armchair", (r"\barmchairs?\b", r"\blounge chairs?\b", r"\beasy chairs?\b",
                  r"\baccent chairs?\b")),
    ("coffee/low table", (r"\blow tables?\b", r"\bcoffee tables?\b",
                          r"\bcocktail tables?\b")),
    ("dining table", (r"\bdining tables?\b", r"\bdining slabs?\b",
                      r"\bdining tops?\b")),
    ("dining chairs", (r"\bdining chairs?\b", r"\bchairs\b", r"\bdining seats?\b")),
    ("media/TV console", (r"\bmedia consoles?\b", r"\btv consoles?\b",
                          r"\bconsoles?\b", r"\bmedia cabinets?\b",
                          r"\bmedia units?\b")),
]

# L'ECLAIRAGE N'EST PAS DANS CETTE LISTE, ET C'EST VOULU. Il n'a jamais fait
# partie de la sous-specification : il se transformait deja 6/6 sur 3f03d6d, et
# la DNA d'atmosphere ship sa propre ligne LIGHT dans le MEME prompt. Le nommer
# aussi dans le HERO ne gagnait rien et coutait 32 caracteres de la marge
# budgetaire qui protege dna_room_context. C9 verifie donc l'inverse : que la
# consigne d'eclairage EXISTE toujours dans le prompt compose (via la DNA) et
# que le HERO ne la duplique PAS.
LIGHTING_PATTERNS = (r"\blighting\b", r"\bpendants?\b", r"\bfloor lamps?\b",
                     r"\blamps?\b", r"\blanterns?\b")

VARIANTS = (("pleine", False), ("compacte", True))

# ------------------------------------------------------ constantes de reference
# Relevees sur l'arbre BASE = C:/Projects/ayden-switch-fix/backend (commit 3f03d6d
# = PROD), config APP_ENV=mobile_mvp_baseline / BIMODAL_ENABLED=1 /
# SWITCH_BLOCK_COMPACT=1.
HERO_BASE_SHA = {
    ("warm_modern", False):     "77899543b3d9654f8a03ea167e37b22a89fcff989db5ba131912c46e60d54eef",
    ("warm_modern", True):      "3859870ee633079e21a8f2b2eafb4e0bae088056495729f42595529b84f1ce0a",
    ("soft_luxury", False):     "26f1e9c56fd74bfdd79be35ac2e1800f73bb44ae0cf86413910a99ec99c6d10b",
    ("soft_luxury", True):      "008397318680f37d8ca89e2707ecc4a81124e2156a9ba7c3fab6d444c7ac8474",
    ("nordic_warmth", False):   "6bef4949a72b5c3bd77113c6425c8acd738eafc4ae9694988ceab13aa879735b",
    ("nordic_warmth", True):    "9a78a9f01b08b07f25bce3557df42b6686ed3dfa9c9f105ecfaf312979dddab1",
    ("tropical_escape", False): "46a71be1e5a8256473584eeb9474d91bdfbde057d36af1ed98e1aaed91a1dcc3",
    ("tropical_escape", True):  "d09a1f9c8613ddd45703678d56c707080a970cdc6261233b0b0c605a9ae19832",
}

# HERO japandi_calm tel qu'il etait en BASE — doit avoir CHANGE sur le candidat.
JAPANDI_BASE_SHA = {
    False: "d5029eeb1237e3fbe9b7983c8bc26916595fe04206deb778c68bf659938bd750",
    True:  "b7d51a949edbc9edb7d304db87c21f3185b9ca4a566225d18b9b211d61baf442",
}

V1_BASE_SHA = {
    ("warm_modern", "living_room"):     "9453a6d74967c408c9bc49df83baf12cacf8e819dedcb5ad0059059d1309c2f4",
    ("warm_modern", "dining_room"):     "43adaad803edd1796787af7d126ebf160ca1794c0699ecf2fcc1b87d96b66aa5",
    ("warm_modern", "bedroom"):         "5b22d8af9a421f8566a772403aa825f70b33a6b1691473034bc166b8bb53e016",
    ("soft_luxury", "living_room"):     "a8c1b568a74ec2cc88e16c557ce795b7dcbcdca4a9699512a8fe489c57750c69",
    ("soft_luxury", "dining_room"):     "fde8a3b93a2c8f1c1799fe2e87572c972d04b4b0201522aabe0b148e24e2e8c4",
    ("soft_luxury", "bedroom"):         "44d8f3bc7c557f96e67e1433c86fc2f02e993dcc88ca2156578fdb42cb0aff1d",
    ("japandi_calm", "living_room"):    "3523be14eb9d518eed0b2c6c8e6e0aadd8b5f38e8f27803248b5e3a9a246d186",
    ("japandi_calm", "dining_room"):    "a0effa681dc75ec3d65a0fd65d5b6d55f1863376f57d6825f1d3cdfec23e1b11",
    ("japandi_calm", "bedroom"):        "53dfd425267587a45e2bed0204127abe754ea8be916175f0fbe2a9e8bf01ea27",
    ("nordic_warmth", "living_room"):   "015cee17de8d4e5a369d3ea55a9c25ed545d084679604ecf7f4d6ba4aa74c74e",
    ("nordic_warmth", "dining_room"):   "9a4236f0b4d18998ae92132cf6e17ef8232427c716d4e7a01a22f451ca60bf14",
    ("nordic_warmth", "bedroom"):       "118016586e82a953ea0e627d50a12f0822135110d71ab21f15ae1216e7ba5079",
    ("tropical_escape", "living_room"): "350da1b3a9b255d3c98077a141f114c43ec519d51ea2d88f639e452d708f46ba",
    ("tropical_escape", "dining_room"): "898590451d9eac6d8106dd17ebc0335acda434bfdd25e476a46d74a7f61e7193",
    ("tropical_escape", "bedroom"):     "23de75bbc8d0e8782bead147715223ce3689e4a01b957073720cc2958e3f5a15",
}

ATMO = {"warm_modern": "Warm Modern", "soft_luxury": "Soft Luxury",
        "japandi_calm": "Japandi Calm", "nordic_warmth": "Nordic Warmth",
        "tropical_escape": "Tropical Escape"}

BUDGET = 4300          # _MODE_BUDGETS["FIRST_VISION"]
HERO_TAG = "HERO FURNISHING"
TV_RULE = "include a television as the living-room focal point"

# structural_identity de 150 caracteres — longueur realiste d'un releve d'openings.
SID150 = ("OPENINGS: sliding glass door on the left wall; picture window centred on "
          "the back wall; open passage back-right into the hallway; no further openings.")

PRESERVATION = [
    "Reproduce the photographed architecture exactly",
    "camera angle and perspective stay exactly as photographed",
    "Add nothing, remove nothing, fill nothing in",
    "never turn an existing opening into a wall",
    "Highest priority: preserve the structure before any styling",
    "Keep each piece's ROLE and ZONE",
    "a sofa stays a sofa in the sofa zone",
    "the TV stays where it is",
    "REPLACE each piece's design with this atmosphere's signature pieces",
]


def pure_switch(atmo_id="japandi_calm", prev="warm_modern", room="living_room",
                structural_identity=""):
    """Pure Switch = REBOOT_FRESH : iteration>=2, historique vide, atmosphere
    precedente autoritaire, lineage NON customise (cf. _pure_switch_validation.py)."""
    return C(style_label=ATMO[atmo_id], room_type=room, room_description="",
             user_instruction="Redesign this space in the " + ATMO[atmo_id] + " style.",
             iteration=2, history=[], generation_mode="preserve", edit_mode=None,
             structural_identity=structural_identity,
             prev_atmosphere_id=prev, lineage_customized=False)


def v1(atmo_id, room):
    return C(style_label=ATMO[atmo_id], room_type=room, room_description="",
             user_instruction="", iteration=1, history=[],
             generation_mode="preserve", edit_mode=None)


print("\nARBRE TESTE : " + str(TREE))
print("CONFIG      : APP_ENV=" + os.environ["APP_ENV"]
      + " BIMODAL_ENABLED=" + os.environ["BIMODAL_ENABLED"]
      + " SWITCH_BLOCK_COMPACT=" + os.environ["SWITCH_BLOCK_COMPACT"])

# =============================================================================
print("\n=== C1 — COUVERTURE SEMANTIQUE : 6 roles x 2 variantes ===")
print("     un role passe si UNE clause porte a la fois un terme de role ET un")
print("     terme de CONSTRUCTION (aucune phrase exacte n'est testee).")
for _vname, _compact in VARIANTS:
    _text = HERO("japandi_calm", compact=_compact)
    _cls = clauses(_text)
    for _role, _pats in ROLES:
        _hit = None
        for _cl in _cls:
            if has_role(_cl, _pats):
                _cw = construction_words(_cl)
                if _cw:
                    _hit = (_cl, sorted(_cw))
                    break
        _named = any(has_role(_cl, _pats) for _cl in _cls)
        _why = ("role ABSENT du HERO" if not _named
                else "role nomme mais AUCUN terme de construction dans sa clause")
        check("[%-8s] role %-17s nomme + qualifie par la forme" % (_vname, _role),
              _hit is not None, _why)
        if _hit:
            print("            -> " + _hit[0][:88] + "   forme=" + str(_hit[1]))

# =============================================================================
print("\n=== C2 — DISTINCTION vs WARM MODERN (>= 4 mots de forme propres) ===")
for _vname, _compact in VARIANTS:
    _fj = form_words(HERO("japandi_calm", compact=_compact))
    _fw = form_words(HERO("warm_modern", compact=_compact))
    _own = _fj - _fw
    check("[%-8s] %d mot(s) de forme Japandi absent(s) du Warm Modern (>=4)"
          % (_vname, len(_own)), len(_own) >= 4, str(sorted(_own)))
    print("            japandi     = " + str(sorted(_fj)))
    print("            warm_modern = " + str(sorted(_fw)))
    print("            propres     = " + str(sorted(_own)))

# =============================================================================
print("\n=== C3 — AUCUN HARDCODING DE PAIRE ===")
_params = list(inspect.signature(HERO).parameters)
check("build_switch_hero_block n'expose que ['atmosphere_id', 'compact']",
      _params == ["atmosphere_id", "compact"], str(_params))
check("aucun parametre d'atmosphere SOURCE (prev/source/from/previous/origin)",
      not any(t in p.lower() for p in _params
              for t in ("prev", "source", "from", "previous", "origin")), str(_params))
_OTHERS = ["Warm Modern", "warm_modern", "Soft Luxury", "soft_luxury",
           "Nordic Warmth", "nordic_warmth", "Nordic", "Tropical Escape",
           "tropical_escape", "Tropical"]
for _vname, _compact in VARIANTS:
    _text = HERO("japandi_calm", compact=_compact)
    _named2 = [o for o in _OTHERS if o.lower() in _text.lower()]
    check("[%-8s] le HERO Japandi ne nomme aucune autre atmosphere" % _vname,
          not _named2, str(_named2))
check("le HERO Japandi est deterministe (2 appels -> meme texte)",
      HERO("japandi_calm") == HERO("japandi_calm")
      and HERO("japandi_calm", compact=True) == HERO("japandi_calm", compact=True))
check("atmosphere inconnue -> '' (no-op sur)",
      HERO("does_not_exist") == "" and HERO("does_not_exist", compact=True) == "")
# Le HERO ne depend QUE de la cible : identique quelle que soit la source du switch.
_segs = [p.split(HERO_TAG, 1)[1][:400]
         for p in (pure_switch(prev="warm_modern"),
                   pure_switch(prev="soft_luxury"),
                   pure_switch(prev="tropical_escape"))]
check("le bloc HERO injecte est identique depuis WM / SL / Tropical",
      _segs[0] == _segs[1] == _segs[2])

# =============================================================================
print("\n=== C4 — AUCUN EFFET V1 (FIRST_VISION, iteration=1) ===")
_ROOMS_V1 = ("living_room", "dining_room", "bedroom")
_leak = [a + "/" + r for a in ATMO for r in _ROOMS_V1 if HERO_TAG in v1(a, r)]
check("aucun des %d prompts V1 ne contient '%s'" % (len(ATMO) * len(_ROOMS_V1), HERO_TAG),
      not _leak, str(_leak[:4]))
_NEW = ["FRAME-FIRST", "post-and-rail", "trestle", "spindle", "paper-cord"]
_tok_leak = [a + "/" + r + ":" + t for a in ATMO for r in _ROOMS_V1
             for t in _NEW if t.lower() in v1(a, r).lower()]
check("aucun token du nouveau HERO ne fuit dans un prompt V1",
      not _tok_leak, str(_tok_leak[:4]))
_bad = [a + "/" + r for (a, r), h in V1_BASE_SHA.items() if sha(v1(a, r)) != h]
check("les %d prompts V1 sont BYTE IDENTICAL a la reference BASE" % len(V1_BASE_SHA),
      not _bad, str(_bad[:4]))

# =============================================================================
print("\n=== C5 — AUCUN EFFET SUR LA REGLE TV ===")
for _lbl, _sid in (("structural_identity vide", ""), ("structural_identity 150c", SID150)):
    _p = pure_switch(structural_identity=_sid)
    check("[%-24s] regle TV presente dans le Pure Switch WM->Japandi" % _lbl,
          TV_RULE in _p, "len=" + str(len(_p)))

# =============================================================================
print("\n=== C6 — PRESERVATION INTACTE (9 clauses x 2 regimes) ===")
for _lbl, _sid in (("vide", ""), ("150c", SID150)):
    _p = pure_switch(structural_identity=_sid)
    for _s in PRESERVATION:
        check("[sid %-4s] %s" % (_lbl, _s[:58]), _s in _p)

# =============================================================================
print("\n=== C7 — BUDGET FIRST_VISION ===")
check("la structural_identity de reference fait bien 150 caracteres",
      len(SID150) == 150, str(len(SID150)))
_p150 = pure_switch(structural_identity=SID150)
check("Pure Switch Japandi living_room = %d < %d" % (len(_p150), BUDGET),
      len(_p150) < BUDGET, str(len(_p150)))
check("le HERO est bien present dans ce prompt budgete", HERO_TAG in _p150)

# =============================================================================
print("\n=== C8 — LES 4 AUTRES ATMOSPHERES SONT INCHANGEES ===")
for (_aid, _compact), _expected in HERO_BASE_SHA.items():
    _got = sha(HERO(_aid, compact=_compact))
    check("HERO %-16s variante %-8s BYTE IDENTICAL a BASE"
          % (_aid, "compacte" if _compact else "pleine"),
          _got == _expected, "got=" + _got[:16])
for _compact, _base_sha in JAPANDI_BASE_SHA.items():
    check("HERO japandi_calm  variante %-8s a bien CHANGE vs BASE"
          % ("compacte" if _compact else "pleine"),
          sha(HERO("japandi_calm", compact=_compact)) != _base_sha)

# =============================================================================
print("\n=== C9 — ECLAIRAGE : couvert par la DNA, PAS duplique dans le HERO ===")
# Le prompt compose doit toujours porter une consigne d'eclairage — elle vient
# de la ligne LIGHT de la DNA d'atmosphere, pas du HERO.
_p_light = pure_switch()
check("le prompt compose porte toujours une consigne d'eclairage",
      any(re.search(_p, _p_light, re.I) for _p in LIGHTING_PATTERNS))
_m = re.search(r"LIGHT:[^\n]*", _p_light)
check("cette consigne vient bien de la section LIGHT de la DNA", _m is not None)
if _m:
    print("            -> " + _m.group(0)[:88])
for _vname, _compact in VARIANTS:
    _h = HERO("japandi_calm", compact=_compact)
    check("[%-8s] le HERO ne duplique PAS l'eclairage" % _vname,
          not any(re.search(_p, _h, re.I) for _p in LIGHTING_PATTERNS),
          "le HERO renomme l'eclairage — 32 car. de marge budgetaire perdus")

# =============================================================================
_total = len(_res)
_passed = sum(1 for ok, _ in _res if ok)
print("\n" + "=" * 72)
print("  TOTAL %d   PASSED %d   FAILED %d" % (_total, _passed, _total - _passed))
print("=" * 72)
if _passed != _total:
    print("ECHECS :")
    for _ok, _name in _res:
        if not _ok:
            print("  - " + _name)
sys.exit(0 if _passed == _total else 1)
