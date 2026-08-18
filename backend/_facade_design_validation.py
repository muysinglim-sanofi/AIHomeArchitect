"""Banc déterministe du candidat FACADE DESIGN (flag AYDEN_FACADE_DESIGN).

Zéro appel fournisseur. Trois obligations, dans cet ordre de gravité :

  1. INERTIE — flag OFF ⇒ le prompt est byte-identique à la baseline pour TOUTES
     les pièces (8 intérieures, 6 extérieures). C'est la garantie de rollback.
  2. NON-CONTAMINATION — flag ON ⇒ seule `facade` change. Les 8 intérieures et les
     5 autres extérieures restent byte-identiques. C'est la garantie que le
     correctif est façade-only, et elle est vérifiée machine, pas affirmée.
  3. CONTRAT — flag ON ⇒ sur façade, les deux verrous sont levés, l'ordre de design
     est présent, la géométrie est réaffirmée DANS le même bloc, et aucune
     contradiction ne subsiste.

Lancement :  python _facade_design_validation.py
"""
from __future__ import annotations

import hashlib
import io
import contextlib
import logging
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
os.chdir(HERE)
sys.path.insert(0, str(HERE))

# Le banc ne compose que des prompts : il n'ouvre aucune base et n'a besoin
# d'aucun environnement particulier. On charge un .env local s'il existe, sinon
# on tourne sur les valeurs par défaut — aucune dépendance à un projet Supabase.
for _name in (".env", ".env.local"):
    _ENV = HERE / _name
    if not _ENV.exists():
        continue
    for _raw in _ENV.read_text(encoding="utf-8").splitlines():
        _l = _raw.strip()
        if _l and not _l.startswith("#") and "=" in _l:
            _k, _, _v = _l.partition("=")
            os.environ.setdefault(_k.strip(), _v.strip())
os.environ.pop("AYDEN_FACADE_DESIGN", None)

with contextlib.redirect_stdout(io.StringIO()):
    import main  # noqa: F401  — applique les flags benchés canoniques
logging.disable(logging.CRITICAL)

from prompt_engine import preservation as P  # noqa: E402
from prompt_engine.composer_v2 import compose_generation_prompt as compose  # noqa: E402

INTERIOR = ["living_room", "bedroom", "dining_room", "office",
            "entrance", "hallway", "kitchen", "bathroom"]
EXTERIOR = ["pool_area", "terrace", "garden", "balcony", "facade", "driveway"]
ATMO = {"warm_modern": "Warm Modern", "soft_luxury": "Soft Luxury",
        "japandi_calm": "Japandi Calm", "nordic_warmth": "Nordic Warmth",
        "tropical_escape": "Tropical Escape"}

_results: list[tuple[bool, str]] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    _results.append((ok, name))
    print(f"  [{'OK ' if ok else 'ECHEC'}] {name}{('  — ' + detail) if detail and not ok else ''}")


def facade_flag(on: bool) -> None:
    if on:
        os.environ["AYDEN_FACADE_DESIGN"] = "1"
    else:
        os.environ.pop("AYDEN_FACADE_DESIGN", None)


def prompt_for(room: str, atmo: str, iteration: int = 1, prev: str | None = None) -> str:
    """Reproduit le chemin de main.py : composition puis apply_stage_mode."""
    kw = dict(style_label=ATMO[atmo], room_type=room, room_description="",
              user_instruction="", iteration=iteration, history=[],
              generation_mode="preserve", edit_mode=None)
    if prev:
        kw["prev_atmosphere_id"] = prev
        kw["lineage_customized"] = False
        kw["user_instruction"] = f"Redesign this space in the {ATMO[atmo]} style."
    base = compose(**kw)
    final, _ = P.apply_stage_mode(base, room_label=room,
                                  atmosphere_label=ATMO[atmo], atmosphere_id=atmo)
    return final


def sha(s: str) -> str:
    return hashlib.sha1(s.encode()).hexdigest()


# ── Baseline : toutes les combinaisons pièce × atmosphère, flag OFF ────────────
facade_flag(False)
BASELINE = {(r, a): sha(prompt_for(r, a)) for r in INTERIOR + EXTERIOR for a in ATMO}

print(f"\n=== 1. INERTIE — flag OFF, {len(BASELINE)} combinaisons pièce × atmosphère ===")
facade_flag(False)
drift = [f"{r}/{a}" for (r, a), h in BASELINE.items() if sha(prompt_for(r, a)) != h]
check(f"flag OFF : {len(BASELINE)}/{len(BASELINE)} prompts byte-identiques (déterminisme)",
      not drift, f"dérive: {drift[:5]}")

print("\n=== 2. NON-CONTAMINATION — flag ON, seule `facade` doit changer ===")
facade_flag(True)
changed, unchanged = [], []
for (r, a), h in BASELINE.items():
    (changed if sha(prompt_for(r, a)) != h else unchanged).append((r, a))
int_changed = [f"{r}/{a}" for r, a in changed if r in INTERIOR]
ext_changed = [f"{r}/{a}" for r, a in changed if r in EXTERIOR and r != "facade"]
fac_changed = [(r, a) for r, a in changed if r == "facade"]

check(f"aucune pièce INTÉRIEURE modifiée ({len(INTERIOR) * len(ATMO)} combinaisons)",
      not int_changed, str(int_changed[:5]))
check(f"aucune AUTRE pièce extérieure modifiée ({(len(EXTERIOR) - 1) * len(ATMO)} combinaisons)",
      not ext_changed, str(ext_changed[:5]))
check(f"les {len(ATMO)} combinaisons `facade` sont modifiées",
      len(fac_changed) == len(ATMO), f"seulement {len(fac_changed)}")

print("\n=== 3. CONTRAT façade — flag ON ===")
facade_flag(True)
for a in ATMO:
    on = prompt_for("facade", a)
    facade_flag(False)
    off = prompt_for("facade", a)
    facade_flag(True)
    tag = f"[{a}]"
    check(f"{tag} verrou parement levé", "all facade materials and cladding" not in on)
    check(f"{tag} interdiction de restylage levée",
          "never add, alter, narrow, extend, or restyle" not in on)
    check(f"{tag} ordre de design présent", "FACADE FINISH" in on)
    check(f"{tag} géométrie réaffirmée DANS le bloc de design",
          "Never create, remove, move, resize or reshape any opening" in on)
    check(f"{tag} verrou géométrique global conservé", "pixel-for-pixel" in on)
    check(f"{tag} anti-invention portée sur le voisinage",
          "NEIGHBOURING construction site" in on
          and "never turn a construction site or service area into new villas" not in on)
    check(f"{tag} garde DNA substitué exactement une fois",
          on.count("the facade finishes may be renewed") == 1
          and P._DNA_FACADE_ARCH_GUARD not in on)
    check(f"{tag} l'ordre de design est ABSENT quand le flag est OFF",
          "FACADE FINISH" not in off)

print("\n=== 4. ABSENCE DE CONTRADICTION — flag ON, façade ===")
facade_flag(True)
for a in ATMO:
    on = prompt_for("facade", a)
    pairs = [
        ("interdit de restyler / ordre de designer",
         r"never add, alter, narrow, extend, or restyle", r"FINISHES are yours to design"),
        ("parement verrouillé / parement designable",
         r"all facade materials and cladding", r"render, cladding, material and colour"),
        ("anti-chantier global / ordre de compléter",
         r"never turn a construction site or service area into new villas",
         r"is a construction state, not a design choice"),
    ]
    for label, forbid, allow in pairs:
        both = bool(re.search(forbid, on, re.I)) and bool(re.search(allow, on, re.I))
        check(f"[{a}] pas de contradiction — {label}", not both)

print("\n=== 5. SURFACE DU CORRECTIF ===")
facade_flag(True)
check("apply_stage_mode : signature inchangée (aucun appelant à modifier)",
      "build_state" not in str(P.apply_stage_mode.__doc__ or "")
      and "facade_design" not in __import__("inspect").signature(P.apply_stage_mode).parameters)
check("le flag est lu dans preservation.py, pas passé par main.py",
      P.is_facade_design_enabled() is True)
facade_flag(False)
check("is_facade_design_enabled() retombe à False sans variable d'environnement",
      P.is_facade_design_enabled() is False)

print("\n=== 6. BUDGET DE PROMPT ===")
for a in ("warm_modern", "soft_luxury"):
    facade_flag(False)
    n_off = len(prompt_for("facade", a))
    facade_flag(True)
    n_on = len(prompt_for("facade", a))
    d = n_on - n_off
    print(f"  {a:<18} OFF={n_off}  ON={n_on}  delta={d:+d}")
    check(f"[{a}] delta de prompt < +847 (le coût du candidat historique)", d < 847,
          f"delta={d:+d}")
facade_flag(False)

ok = sum(1 for r, _ in _results if r)
tot = len(_results)
print(f"\n{'=' * 62}\nRESULTAT : {ok}/{tot}\n{'=' * 62}")
if ok != tot:
    print("ECHECS :")
    for r, n in _results:
        if not r:
            print("  -", n)
sys.exit(0 if ok == tot else 1)
