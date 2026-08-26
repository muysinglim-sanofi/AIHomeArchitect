"""PURE SWITCH — contrat complet. Zéro appel fournisseur.

Le défaut corrigé, en une phrase : un Pure Switch portait deux ordres mutuellement
exclusifs (« Restyle ONLY … same pieces, same footprint » puis « REPLACE each
piece's design »), et selon les runs le modèle obéissait à l'un ou à l'autre —
d'où un résultat tantôt fort, tantôt quasi inchangé. Et un projet ayant connu un
seul refine perdait purement et simplement l'autorité de redesign.

Ce banc épingle les DEUX faces : ce qui doit désormais changer, et surtout tout
ce qui ne doit pas bouger. Le test le plus important est T4 : il exige que la
contradiction ait DISPARU du prompt de switch.

Lancement :  python _pure_switch_validation.py
"""
from __future__ import annotations

import contextlib
import io
import logging
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
os.chdir(HERE)
sys.path.insert(0, str(HERE))
os.environ.setdefault("OPENAI_API_KEY", "sk-not-used")
os.environ.setdefault("APP_ENV", "mobile_mvp_baseline")
os.environ.setdefault("SUPABASE_URL", "https://placeholder.supabase.co")
for _k in ("SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_ANON_KEY", "SUPABASE_KEY",
           "SUPABASE_JWT_SECRET"):
    os.environ.setdefault(_k, "ph")

with contextlib.redirect_stdout(io.StringIO()):
    import main  # noqa: F401
logging.disable(logging.CRITICAL)

from prompt_engine import preservation as P  # noqa: E402
from prompt_engine.composer_v2 import compose_generation_prompt as C  # noqa: E402

ATMO = {"warm_modern": "Warm Modern", "soft_luxury": "Soft Luxury",
        "japandi_calm": "Japandi Calm", "nordic_warmth": "Nordic Warmth",
        "tropical_escape": "Tropical Escape"}
INTERIOR = ["living_room", "bedroom", "dining_room", "office",
            "entrance", "hallway", "kitchen", "bathroom"]
EXTERIOR = ["pool_area", "terrace", "garden", "balcony", "facade", "driveway"]
PREV = {"warm_modern": "japandi_calm", "soft_luxury": "japandi_calm",
        "japandi_calm": "warm_modern", "nordic_warmth": "warm_modern",
        "tropical_escape": "warm_modern"}

GEL = "same pieces, same footprint"        # la clause qui figeait la forme
ONLY = "Restyle only through"
ROLE = "ROLE and ZONE"                     # la clause de remplacement (FRESH)
ROLE_C = "Keep each piece's ROLE and ZONE"  # idem, en-tête CUSTOMIZED
REPLACE = "REPLACE each piece"
HERO = "HERO FURNISHING"

_res: list[tuple[bool, str]] = []


def check(name, ok, detail=""):
    _res.append((ok, name))
    print(f"  [{'OK ' if ok else 'ECHEC'}] {name}{('  — ' + detail) if detail and not ok else ''}")


def v1(room, atmo, mode="preserve", instr=""):
    return C(style_label=ATMO[atmo], room_type=room, room_description="",
             user_instruction=instr, iteration=1, history=[],
             generation_mode=mode, edit_mode=None)


def switch(room, atmo, *, customized=False, hist=None, prev="auto"):
    return C(style_label=ATMO[atmo], room_type=room, room_description="",
             user_instruction=f"Redesign this space in the {ATMO[atmo]} style.",
             iteration=3 if customized else 2, history=hist or [],
             generation_mode="preserve", edit_mode=None,
             prev_atmosphere_id=(PREV[atmo] if prev == "auto" else prev),
             lineage_customized=customized)


def refine(room, atmo, instr):
    """Refine normal : MÊME atmosphère, donc INCREMENTAL — jamais un switch."""
    return C(style_label=ATMO[atmo], room_type=room, room_description="",
             user_instruction=instr, iteration=2,
             history=[{"role": "user", "content": instr},
                      {"role": "assistant", "content": "ok"}],
             generation_mode="preserve", edit_mode=None,
             prev_atmosphere_id=atmo, lineage_customized=False)


print("\n=== T1 — V1 conserve la clause meuble générique ===")
missing = [f"{r}/{a}" for r in INTERIOR for a in ATMO if GEL not in v1(r, a)]
check(f"les {len(INTERIOR) * len(ATMO)} V1 intérieurs gardent « {GEL} »",
      not missing, str(missing[:4]))
check("aucun V1 ne reçoit la clause de switch",
      not any(ROLE in v1(r, a) for r in INTERIOR for a in ATMO))

print("\n=== T2 — Refine normal inchangé ===")
r_p = refine("living_room", "japandi_calm", "add a plant near the window")
check("un Refine ne reçoit PAS l'autorité de redesign de switch", ROLE not in r_p)
check("un Refine ne reçoit PAS le bloc REPLACE", REPLACE not in r_p)
check("l'intention utilisateur du Refine est présente", "plant" in r_p.lower())

print("\n=== T3 — REBOOT_FRESH : autorité de redesign présente ===")
for a in ATMO:
    p = switch("living_room", a)
    check(f"[{a}] bloc REPLACE présent", REPLACE in p)
check("HERO présent sur le salon", HERO in switch("living_room", "japandi_calm"))

print("\n=== T4 — REBOOT_FRESH : la contradiction a DISPARU ===")
for a in ATMO:
    p = switch("living_room", a)
    check(f"[{a}] « {GEL} » absent", GEL not in p)
    check(f"[{a}] « {ONLY} » absent", ONLY not in p)
    check(f"[{a}] clause rôle/zone présente", ROLE in p)
    check(f"[{a}] AUCUNE coexistence gel + redesign",
          not (GEL in p and REPLACE in p))

print("\n=== T5 — REBOOT_CUSTOMIZED : autorité de redesign présente ===")
H_PLANT = [{"role": "user", "content": "add a plant near the window"},
           {"role": "assistant", "content": "ok"}]
for a in ATMO:
    p = switch("living_room", a, customized=True, hist=H_PLANT)
    check(f"[{a}] clause rôle/zone présente", ROLE_C in p)
    check(f"[{a}] redesign visuel explicitement autorisé",
          "redesign the furniture's VISUAL identity" in p)
    check(f"[{a}] aucune clause figeante", GEL not in p)

print("\n=== T6-T9 — l'intention utilisateur survit au switch ===")
CAS = [("T6 ajouter une plante", "add a plant near the window", "plant"),
       ("T7 retirer la table à manger", "remove the dining table", "dining table"),
       ("T8 canapé en L", "make the sofa L-shaped", "l-shaped"),
       ("T9 déplacer le fauteuil", "move the armchair near the window", "armchair")]
for lbl, instr, needle in CAS:
    h = [{"role": "user", "content": instr}, {"role": "assistant", "content": "ok"}]
    p = switch("living_room", "japandi_calm", customized=True, hist=h)
    check(f"{lbl} — l'intention est portée dans le prompt", needle in p.lower())
    check(f"{lbl} — le redesign visuel reste autorisé", ROLE_C in p)
check("la priorité « ce que l'utilisateur a demandé reste » est écrite",
      "what they added, removed or moved stays that way"
      in switch("living_room", "japandi_calm", customized=True, hist=H_PLANT))

print("\n=== T10 — INCREMENTAL : fail-safe étroit, délibéré ===")
inc = switch("living_room", "japandi_calm", prev=None)
check("INCREMENTAL ne reçoit PAS l'autorité de redesign (fail-safe assumé)",
      ROLE not in inc and ROLE_C not in inc)
check("raison : INCREMENTAL est AUSSI la stratégie du Refine normal — "
      "y ajouter le redesign le donnerait à tous les Refine",
      ROLE not in refine("living_room", "japandi_calm", "add a plant"))

print("\n=== T11 — architecture et prise de vue préservées partout ===")
for lbl, p in (("FRESH", switch("living_room", "japandi_calm")),
               ("CUSTOMIZED", switch("living_room", "japandi_calm",
                                     customized=True, hist=H_PLANT)),
               ("INCREMENTAL", inc)):
    low = p.lower()
    check(f"[{lbl}] architecture préservée",
          "architect" in low or "same apartment" in low)
    check(f"[{lbl}] prise de vue / perspective préservée",
          "perspective" in low or "camera" in low or "viewpoint" in low)

print("\n=== T12 — aucun chemin non-switch ne reçoit la clause de switch ===")
leaks = []
for r in INTERIOR:
    for a in ATMO:
        if ROLE in v1(r, a) or ROLE_C in v1(r, a):
            leaks.append(f"V1/{r}/{a}")
        base = v1(r, a)
        st, _ = P.apply_stage_mode(base, room_label=r, atmosphere_label=ATMO[a],
                                   atmosphere_id=a)
        if ROLE in st or ROLE_C in st:
            leaks.append(f"STAGE/{r}/{a}")
for a in ATMO:
    if ROLE in v1("living_room", a, mode="creative"):
        leaks.append(f"CREATIF/{a}")
check(f"aucune fuite sur {len(INTERIOR) * len(ATMO) * 2 + len(ATMO)} chemins non-switch",
      not leaks, str(leaks[:4]))

print("\n=== T13 — chemins extérieurs / façade inchangés ===")
for flag in ("0", "1"):
    if flag == "1":
        os.environ["AYDEN_FACADE_DESIGN"] = "1"
    else:
        os.environ.pop("AYDEN_FACADE_DESIGN", None)
    bad = []
    for r in EXTERIOR:
        for a in ATMO:
            st, _ = P.apply_stage_mode(v1(r, a), room_label=r,
                                       atmosphere_label=ATMO[a], atmosphere_id=a)
            if ROLE in st or ROLE_C in st:
                bad.append(f"{r}/{a}")
    check(f"façade flag={flag} : aucune clause de switch sur les 30 combinaisons",
          not bad, str(bad[:4]))
os.environ.pop("AYDEN_FACADE_DESIGN", None)

print("\n=== ITÉRATION 2 — HERO sur le régime CUSTOMIZED ===")
H_REMOVE = [{"role": "user", "content": "remove the dining table"},
            {"role": "assistant", "content": "ok"}]
H_LSHAPE = [{"role": "user", "content": "make the sofa L-shaped"},
            {"role": "assistant", "content": "ok"}]
H_MOVE = [{"role": "user", "content": "move the armchair near the window"},
          {"role": "assistant", "content": "ok"}]

check("H1 — FRESH reçoit toujours le HERO",
      HERO in switch("living_room", "japandi_calm"))
for a in ATMO:
    p = switch("living_room", a, customized=True, hist=H_PLANT)
    check(f"H2 [{a}] CUSTOMIZED reçoit désormais le HERO", HERO in p)
check("H3 — « add plant » survit au HERO",
      "plant" in switch("living_room", "japandi_calm",
                        customized=True, hist=H_PLANT).lower())
check("H4 — « remove dining table » survit au HERO",
      "dining table" in switch("living_room", "japandi_calm",
                               customized=True, hist=H_REMOVE).lower())
p_l = switch("living_room", "japandi_calm", customized=True, hist=H_LSHAPE)
check("H5 — la contrainte « canapé en L » est portée", "l-shaped" in p_l.lower())
check("H6 — le déplacement explicite est porté",
      "armchair" in switch("living_room", "japandi_calm",
                           customized=True, hist=H_MOVE).lower())
check("H7/H8 — le garde anti-annulation suit le HERO",
      "never use them to undo something the user asked for" in p_l
      and "an L-shaped sofa stays L-shaped" in p_l)
check("H7 — le garde vient APRÈS le HERO (dernière lecture)",
      p_l.index(HERO) < p_l.index("never use them to undo"))
check("H9 — architecture / prise de vue inchangées en CUSTOMIZED",
      "same photographed architecture" in p_l)
leak2 = [f"{r}/{a}" for r in INTERIOR if r != "living_room" for a in ATMO
         if HERO in switch(r, a, customized=True, hist=H_PLANT)]
check("H10 — le HERO CUSTOMIZED ne fuit sur AUCUNE pièce non-salon",
      not leak2, str(leak2[:4]))
leak3 = [f"{r}/{a}" for r in INTERIOR for a in ATMO if HERO in v1(r, a)]
check("H10 — aucun chemin V1 ne reçoit le HERO par cette route",
      not leak3, str(leak3[:4]))

ok = sum(1 for r, _ in _res if r)
tot = len(_res)
print(f"\n{'=' * 66}\nRESULTAT : {ok}/{tot}\n{'=' * 66}")
if ok != tot:
    print("ECHECS :")
    for r, n in _res:
        if not r:
            print("  -", n)
sys.exit(0 if ok == tot else 1)
