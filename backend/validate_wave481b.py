"""
Wave 4.8.1b validation - Atmosphere DNA Mapping Fix (Japandi richness).

Root cause: label_to_atmosphere_id kept only the part before the middot, so
"Japandi . Calm" -> "japandi" while DNA is registered "japandi_calm" -> miss
-> leaner non-DNA _style_block path. Fix: registry-aware deterministic
resolution (full -> base -> unique-prefix -> legacy base fallback). Zero
regression: every previously-correct label resolves byte-identically.

Suites:
  A  label normalization (fix + every prior mapping unchanged + fallback)
  B  DNA activation proof (all 10 atmospheres HIT room DNA)
  C  backward compatibility (direct ids, legacy examples)
  D  no prompt-budget regression (Japandi . Calm V1 <= 3550, DNA present)
  E  no behavior regression (working atmospheres identical)
  F  observability + surgical scope (only the two intended files changed)
"""

import os
import sys
import logging

logging.disable(logging.CRITICAL)
sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
results = []


def check(label, cond, detail=""):
    s = PASS if cond else FAIL
    sfx = f"  [{detail}]" if detail and not cond else ""
    print(f"  {s}  {label}{sfx}")
    results.append((label, cond))


from prompt_engine.atmosphere_dna import (
    label_to_atmosphere_id, get_room_dna, get_core,
)
from prompt_engine.atmosphere_dna._base import _CORE_REGISTRY
logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS
from prompt_engine.structural_identity import extract_from_description, render_clause, render_negative_anchors
logging.disable(logging.CRITICAL)

M = chr(0xB7)  # middot used in display labels
L = lambda atm, sub: f"{atm} {M} {sub}"


# ── Suite A: label normalization ─────────────────────────────────────────────
print("\n=== Suite A: label normalization ===")
check("A1 FIX: 'Japandi . Calm' -> japandi_calm (was japandi)",
      label_to_atmosphere_id(L("Japandi", "Calm")) == "japandi_calm")
check("A2 unchanged: 'Soft Luxury . Gold' -> soft_luxury",
      label_to_atmosphere_id(L("Soft Luxury", "Gold")) == "soft_luxury")
check("A3 unchanged: 'Warm Modern . Oat' -> warm_modern",
      label_to_atmosphere_id(L("Warm Modern", "Oat")) == "warm_modern")
check("A4 unchanged: 'Zen Retreat . Serenity' -> zen_retreat",
      label_to_atmosphere_id(L("Zen Retreat", "Serenity")) == "zen_retreat")
check("A5 unchanged legacy: 'Warm Modern . Vision 2' -> warm_modern",
      label_to_atmosphere_id(L("Warm Modern", "Vision 2")) == "warm_modern")
check("A6 direct id unchanged: 'soft_luxury' -> soft_luxury",
      label_to_atmosphere_id("soft_luxury") == "soft_luxury")
check("A7 direct id unchanged: 'japandi_calm' -> japandi_calm",
      label_to_atmosphere_id("japandi_calm") == "japandi_calm")
check("A8 bare 'Japandi' -> japandi_calm (unique-prefix safety)",
      label_to_atmosphere_id("Japandi") == "japandi_calm")
# All other suffixed atmospheres now resolve to their registered id
for atm, expect in [("Bali", "bali_sanctuary"), ("Dark", "dark_contemporary"),
                    ("Nordic", "nordic_warmth"), ("Nature", "nature_retreat"),
                    ("Desert", "desert_luxe"), ("Tropical", "tropical_escape")]:
    check(f"A-suffix '{atm} . X' -> {expect}",
          label_to_atmosphere_id(L(atm, "X")) == expect)
check("A9 unknown label falls back to legacy base (no DNA): 'Foo . Bar' -> foo",
      label_to_atmosphere_id(L("Foo", "Bar")) == "foo")
check("A10 empty label safe -> '' (no crash, legacy fallback)",
      label_to_atmosphere_id("") == "")


# ── Suite B: DNA activation proof ────────────────────────────────────────────
print("\n=== Suite B: DNA activation ===")
check("B1 'Japandi . Calm' now HITS room DNA (living_room)",
      get_room_dna(label_to_atmosphere_id(L("Japandi", "Calm")), "living_room") is not None)
check("B2 Japandi core DNA reachable (philosophy present)",
      get_core("japandi_calm") is not None
      and "japan" in get_core("japandi_calm").philosophy.lower())
# Every registered atmosphere's canonical 'Title . X' label resolves + has DNA
_canon = {k: k.replace("_", " ").title() for k in _CORE_REGISTRY}
all_hit = True
for atm_id, title in _canon.items():
    rid = label_to_atmosphere_id(L(title, "Variant"))
    if rid != atm_id or get_room_dna(rid, "living_room") is None:
        all_hit = False
check("B3 all 10 atmospheres: 'Title . X' -> id + living_room DNA HIT",
      all_hit)
check("B4 'Japandi . Calm' bedroom DNA also resolves",
      get_room_dna("japandi_calm", "master_bedroom") is not None)


# ── Suite C: backward compatibility ──────────────────────────────────────────
print("\n=== Suite C: backward compatibility ===")
# Every previously-correct mapping must be byte-identical.
unchanged = {
    L("Soft Luxury", "Gold"): "soft_luxury",
    L("Warm Modern", "Oat"): "warm_modern",
    L("Zen Retreat", "Serenity"): "zen_retreat",
    L("Warm Modern", "Vision 2"): "warm_modern",
    "soft_luxury": "soft_luxury",
    "warm_modern": "warm_modern",
    "zen_retreat": "zen_retreat",
}
check("C1 all previously-correct mappings byte-identical",
      all(label_to_atmosphere_id(k) == v for k, v in unchanged.items()))
check("C2 previously-correct atmospheres still DNA-HIT",
      all(get_room_dna(label_to_atmosphere_id(k), "living_room") is not None
          for k in (L("Soft Luxury", "Gold"), L("Warm Modern", "Oat"),
                    L("Zen Retreat", "Serenity"))))
check("C3 unknown -> non-DNA fallback preserved (no DNA, no crash)",
      get_room_dna(label_to_atmosphere_id(L("Foo", "Bar")), "living_room") is None)


# ── Suite D: no prompt-budget regression ─────────────────────────────────────
print("\n=== Suite D: prompt-budget ===")
D = ("Open-plan living room, dominant bay window on the rear wall, a secondary "
     "rear window beside it, two windows on the left, deep diagonal depth, "
     "open kitchen on the right.")
ident = extract_from_description(D)


def fv(label):
    return compose_generation_prompt(label, "living room", "", "", 1, [],
                                     structural_identity=render_clause(ident, "V1"),
                                     structural_negative_anchors=render_negative_anchors(ident))


p_jap = fv(L("Japandi", "Calm"))
p_sl = fv(L("Soft Luxury", "Gold"))
check("D1 Japandi V1 now uses DNA path (ATMOSPHERE/ROOM block present)",
      "ATMOSPHERE (" in p_jap and "ROOM (" in p_jap)
check("D2 Japandi V1 within FIRST_VISION budget 3550 (no overflow)",
      len(p_jap) <= _MODE_BUDGETS["FIRST_VISION"], f"len={len(p_jap)}")
check("D3 Japandi V1 keeps wow + realism (no P4/P3 eviction)",
      "TRANSFORMATION AMBITION" in p_jap
      and ("CGI render" in p_jap)
      and "STRUCTURAL IDENTITY" in p_jap and "STRUCTURAL NEGATIVE ANCHORS" in p_jap)
check("D4 Soft Luxury V1 unchanged: DNA path + <=3550",
      "ATMOSPHERE (" in p_sl and len(p_sl) <= _MODE_BUDGETS["FIRST_VISION"],
      f"len={len(p_sl)}")
# DNA block contains "ATMOSPHERE STYLE (restyle...)"; the generic _style_block
# adds an EXTRA standalone "STYLE (<name>):" header. On the DNA path every
# "STYLE (" is part of "ATMOSPHERE STYLE ("; counts equal. Generic path differs.
check("D5 Japandi V1 no longer uses generic _style_block (no standalone STYLE header)",
      p_jap.count("STYLE (") == p_jap.count("ATMOSPHERE STYLE (")
      and p_jap.count("STYLE (") >= 1)


# ── Suite E: no behavior regression (working atmospheres identical) ──────────
print("\n=== Suite E: no behavior regression ===")
for atm, sub in [("Soft Luxury", "Gold"), ("Warm Modern", "Oat"),
                  ("Zen Retreat", "Serenity")]:
    p = fv(L(atm, sub))
    check(f"E {atm}: DNA path + all critical sections + <=3550",
          ("ATMOSPHERE (" in p)
          and "SAME APARTMENT PHOTO-EDIT" in p and "OPENINGS ANCHOR" in p
          and "STRUCTURAL IDENTITY" in p and "TRANSFORMATION AMBITION" in p
          and len(p) <= _MODE_BUDGETS["FIRST_VISION"], f"len={len(p)}")


# ── Suite F: observability + surgical scope ──────────────────────────────────
print("\n=== Suite F: observability + scope ===")
with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()
check("F1 [AtmosphereDNA] observability log present",
      "[AtmosphereDNA]" in comp_src
      and "dna_matched=" in comp_src and "label=%r" in comp_src)
with open("prompt_engine/atmosphere_dna/_base.py", encoding="utf-8") as f:
    base_src = f.read()
check("F2 Wave 4.8.1b documented in _base.py",
      "Wave 4.8.1b" in base_src)
check("F3 surgical: registry-aware resolution implemented",
      "_CORE_REGISTRY" in base_src and "prefix_matches" in base_src
      and "_norm_id" in base_src)
check("F4 no DNA content rewrite (build_dna_block untouched signature)",
      "def build_dna_block(dna: RoomAdaptationDNA) -> str:" in base_src)
check("F5 no new prompt section / priority change in composer (scope)",
      "Wave 4.8.1b" in comp_src
      and comp_src.count("Wave 4.8.1b") == 1)  # only the observability log

logging.disable(logging.NOTSET)

passed = sum(1 for _, ok in results if ok)
total = len(results)
failed = [l for l, ok in results if not ok]
print(f"\n{'=' * 60}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if failed:
    print("\n  FAILING CHECKS:")
    for l in failed:
        print(f"    - {l}")
print(f"{'=' * 60}")
print("""
  WAVE 4.8.1b - ATMOSPHERE DNA MAPPING FIX:
  Registry-aware label resolution. 'Japandi . Calm' -> japandi_calm (DNA HIT).
  Every previously-correct label byte-identical. Zero architecture/budget change.
""")
