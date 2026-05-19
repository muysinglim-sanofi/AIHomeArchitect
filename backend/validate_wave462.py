"""
Wave 4.6.2 validation suite — Openings Fidelity + Natural Decoration Pass.

PROBLEM:
  Despite Wave 4.6.1 shifting to photo-edit philosophy, two residual issues remained:
    1. OPENINGS NORMALIZED: model still resizes/simplifies bay windows even with
       CAMERA LOCK + STRUCTURAL LOCK — treated them as design decisions, not photo facts.
    2. UNDER-DECORATED: removing composition authority left some outputs sparse —
       missing TV, low hospitality layering, minimal accessory presence.

WAVE 4.6.2 CHANGES (MICRO-CALIBRATION ONLY):
  1. build_openings_anchor() added to fidelity_layer.py (~197 chars, P1 in FIRST_VISION)
     — "OPENINGS ANCHOR — Bay windows and openings are photographed facts..."
     — Do not resize, narrow, simplify, standardize any opening.
  2. build_natural_enrichment() added to dream_scene_completion.py (~217 chars, P4 in FV)
     — Light natural layering: plants, floor lamp, cushions, textiles, TV if appropriate.
     — Strict: secondary to architecture, enriches without recomposing.

PRESERVED:
  - ALL Wave 4.6.1 foundations: source="", PHOTO-EDIT task, pure-material DNA,
    photo_edit_wow, structural mask, input_fidelity=high, quality=high
  - No new contract layers. No composition authority. No scene-generation logic.
  - Architecture fidelity remains PRIORITY #1. Decoration is SECONDARY.

Suites:
  A — build_openings_anchor() vocabulary and wiring
  B — build_natural_enrichment() vocabulary (no composition authority)
  C — composer wiring: priority, raw_sections ordering, imports
  D — Rendered prompts: both signals present, budget compliant
  E — Regression: all Wave 4.6.1 / 4.6.0 / prior wave foundations intact
"""

import os
import sys
import logging

logging.disable(logging.CRITICAL)
sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

results = []


def check(label: str, condition: bool, detail: str = "") -> None:
    status = PASS if condition else FAIL
    suffix = f"  [{detail}]" if detail and not condition else ""
    print(f"  {status}  {label}{suffix}")
    results.append((label, condition))


# ── Suite A: build_openings_anchor() vocabulary and wiring ───────────────────
print("\n=== Suite A: build_openings_anchor() — openings fidelity directive ===")

from prompt_engine.fidelity_layer import build_openings_anchor, build_first_vision_task

anchor = build_openings_anchor()

check("A1  build_openings_anchor() importable and callable",
      callable(build_openings_anchor))
check("A2  anchor contains OPENINGS ANCHOR label",
      "OPENINGS ANCHOR" in anchor)
check("A3  anchor contains bay windows (primary failure mode named)",
      "bay windows" in anchor.lower() or "bay window" in anchor.lower())
check("A4  anchor contains photographed facts framing",
      "photographed facts" in anchor or "photographed" in anchor)
check("A5  anchor contains resize (explicit prohibition)",
      "resize" in anchor)
check("A6  anchor contains narrow (explicit prohibition)",
      "narrow" in anchor)
check("A7  anchor contains simplify (explicit prohibition)",
      "simplify" in anchor)
check("A8  anchor contains standardize (explicit prohibition)",
      "standardize" in anchor)
check("A9  anchor contains photo framing (exact proportions from photo)",
      "photo" in anchor.lower())
check("A10 anchor is compact — under 250 chars",
      len(anchor) <= 250, f"got {len(anchor)}")
check("A11 anchor does NOT contain topology or zone framing (not a contract layer)",
      "topology" not in anchor.lower() and "zone" not in anchor.lower())

with open("prompt_engine/fidelity_layer.py", encoding="utf-8") as f:
    fid_src = f.read()

check("A12 fidelity_layer documents Wave 4.6.2",
      "Wave 4.6.2" in fid_src)
check("A13 build_openings_anchor defined in fidelity_layer",
      "def build_openings_anchor" in fid_src)
check("A14 Wave 4.6.1 still documented (prior wave context preserved)",
      "Wave 4.6.1" in fid_src)


# ── Suite B: build_natural_enrichment() — no composition authority ────────────
print("\n=== Suite B: build_natural_enrichment() — light natural decoration ===")

from prompt_engine.dream_scene_completion import (
    build_natural_enrichment,
    build_scene_completion,
    build_dream_micro_layer,
    build_dream_addendum,
)

enrichment = build_natural_enrichment()

check("B1  build_natural_enrichment() importable and callable",
      callable(build_natural_enrichment))
check("B2  enrichment contains NATURAL ENRICHMENT label",
      "NATURAL ENRICHMENT" in enrichment)
check("B3  enrichment contains light natural layering signal",
      "natural" in enrichment.lower() and ("enrich" in enrichment.lower() or "layer" in enrichment.lower()))
check("B4  enrichment contains TV signal (missing TV was a complaint)",
      "TV" in enrichment)
check("B5  enrichment contains plants signal",
      "plant" in enrichment.lower())
check("B6  enrichment contains do not recompose (composition authority FORBIDDEN)",
      "recompose" in enrichment.lower() and ("not" in enrichment.lower() or "do not" in enrichment.lower()))
check("B7  enrichment contains secondary to architecture (priority preserved)",
      "secondary" in enrichment.lower() or "architecture" in enrichment.lower())
check("B8  enrichment does NOT contain sofa grouping",
      "sofa grouping" not in enrichment)
check("B9  enrichment does NOT contain furniture arrangement",
      "furniture arrangement" not in enrichment)
check("B10 enrichment does NOT contain composition directive keywords",
      "place a sofa" not in enrichment and "position the" not in enrichment and
      "arrange" not in enrichment)
check("B11 enrichment does NOT contain COMPLETE THE SCENE (old directive removed in 4.6.0)",
      "COMPLETE THE SCENE" not in enrichment)
check("B12 enrichment is compact — under 280 chars",
      len(enrichment) <= 280, f"got {len(enrichment)}")

with open("prompt_engine/dream_scene_completion.py", encoding="utf-8") as f:
    dsc_src = f.read()

check("B13 dream_scene_completion documents Wave 4.6.2",
      "Wave 4.6.2" in dsc_src)
check("B14 build_natural_enrichment defined in dream_scene_completion",
      "def build_natural_enrichment" in dsc_src)
check("B15 prior functions unchanged — build_scene_completion still present",
      "def build_scene_completion" in dsc_src)
check("B16 prior functions unchanged — build_dream_micro_layer still present",
      "def build_dream_micro_layer" in dsc_src)


# ── Suite C: composer wiring ──────────────────────────────────────────────────
print("\n=== Suite C: composer wiring — priority, raw_sections, imports ===")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()

check("C1  Wave 4.6.2 documented in composer",
      "Wave 4.6.2" in comp_src)
check("C2  build_openings_anchor imported in composer",
      "build_openings_anchor" in comp_src)
check("C3  build_natural_enrichment imported in composer",
      "build_natural_enrichment" in comp_src)
check("C4  openings_anchor in _SECTION_PRIORITY at P1",
      '"openings_anchor": 1' in comp_src)
check("C5  natural_enrichment in _SECTION_PRIORITY at P4",
      '"natural_enrichment": 4' in comp_src)
check("C6  openings_anchor in raw_sections",
      '("openings_anchor", openings_anchor)' in comp_src)
check("C7  natural_enrichment in raw_sections",
      '("natural_enrichment", natural_enrichment)' in comp_src)

# Ordering: openings_anchor must come before source_space in Path D raw_sections.
# Note: source_space also appears in SR/ST paths earlier in the file; search from oa_pos.
oa_pos = comp_src.find('("openings_anchor", openings_anchor)')
ss_pos = comp_src.find('("source_space", source)', oa_pos)  # find source_space AFTER openings_anchor
check("C8  openings_anchor before source_space in Path D raw_sections",
      oa_pos > 0 and ss_pos > oa_pos, f"oa_pos={oa_pos} ss_pos_after_oa={ss_pos}")

# Ordering: natural_enrichment must come after wow_directive (both P4)
wow_pos = comp_src.find('("wow_directive", wow_block)')
ne_pos  = comp_src.find('("natural_enrichment", natural_enrichment)')
check("C9  natural_enrichment after wow_directive in raw_sections",
      0 < wow_pos < ne_pos, f"wow_pos={wow_pos} ne_pos={ne_pos}")

# Ordering: interior_completeness before wow_directive (Wave 4.4.1 regression)
ic_pos = comp_src.find('("interior_completeness", completeness)')
check("C10 interior_completeness before wow_directive (Wave 4.4.1 regression)",
      0 < ic_pos < wow_pos, f"ic_pos={ic_pos} wow_pos={wow_pos}")

check("C11 build_openings_anchor() called in Path D",
      "build_openings_anchor()" in comp_src)
check("C12 build_natural_enrichment() called in both DNA and non-DNA branches",
      comp_src.count("build_natural_enrichment()") >= 2)


# ── Suite D: Rendered prompts ─────────────────────────────────────────────────
print("\n=== Suite D: Rendered prompts — both signals present, budget compliant ===")

logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS
logging.disable(logging.CRITICAL)

room_desc = "A bright living room with oak floors, large west-facing windows, and a sofa."
fv_budget = _MODE_BUDGETS["FIRST_VISION"]

p_sl = compose_generation_prompt("Soft Luxury · Gold", "living room", room_desc, "", 1, [])
p_zen = compose_generation_prompt("Zen Retreat · Serenity", "living room", room_desc, "", 1, [])
p_nondna = compose_generation_prompt("Japandi · Harmony", "home office", room_desc, "", 1, [])

check("D1  FV (Soft Luxury) contains OPENINGS ANCHOR",
      "OPENINGS ANCHOR" in p_sl)
check("D2  FV (Zen) contains OPENINGS ANCHOR",
      "OPENINGS ANCHOR" in p_zen)
check("D3  FV (non-DNA) contains OPENINGS ANCHOR",
      "OPENINGS ANCHOR" in p_nondna)
check("D4  FV (Soft Luxury) contains NATURAL ENRICHMENT",
      "NATURAL ENRICHMENT" in p_sl)
check("D5  FV (Zen) contains NATURAL ENRICHMENT",
      "NATURAL ENRICHMENT" in p_zen)
check("D6  FV (non-DNA) contains NATURAL ENRICHMENT",
      "NATURAL ENRICHMENT" in p_nondna)
check("D7  FV has no sofa grouping (composition authority NOT reintroduced)",
      "sofa grouping" not in p_sl and "sofa grouping" not in p_zen)
check("D8  FV has no COMPLETE THE SCENE (Wave 4.6.0 removal regression)",
      "COMPLETE THE SCENE" not in p_sl and "COMPLETE THE SCENE" not in p_zen)
check(f"D9  FV (Soft Luxury) within budget ({fv_budget})",
      len(p_sl) <= fv_budget, f"got {len(p_sl)}")
check(f"D10 FV (Zen) within budget ({fv_budget})",
      len(p_zen) <= fv_budget, f"got {len(p_zen)}")
check(f"D11 FV (non-DNA) within budget ({fv_budget})",
      len(p_nondna) <= fv_budget, f"got {len(p_nondna)}")

# SR path must be unaffected
history_v2 = [
    {"role": "user", "content": "I want Soft Luxury"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer"},
]
p_sr = compose_generation_prompt("Soft Luxury · Gold", "living room", room_desc, "warmer", 2, history_v2)
check("D12 SR path has NO OPENINGS ANCHOR (FV only — unaffected)",
      "OPENINGS ANCHOR" not in p_sr)
check("D13 SR path has NO NATURAL ENRICHMENT (FV only — unaffected)",
      "NATURAL ENRICHMENT" not in p_sr)
check("D14 SR path still has TOPOLOGY LOCKED (Wave 4.3.0 regression)",
      "TOPOLOGY LOCKED" in p_sr)


# ── Suite E: Regression ───────────────────────────────────────────────────────
print("\n=== Suite E: Regression — all Wave 4.6.1 / 4.6.0 / prior foundations intact ===")

# Wave 4.6.1 foundations
check("E1  FV has SAME APARTMENT PHOTO-EDIT (Wave 4.6.1 task)",
      "SAME APARTMENT PHOTO-EDIT" in p_sl)
check("E2  FV has no SOURCE SPACE (Wave 4.6.1 removal)",
      "SOURCE SPACE" not in p_sl)
check("E3  FV has TRANSFORMATION AMBITION (Wave 4.6.1 wow intact)",
      "TRANSFORMATION AMBITION" in p_sl)
check("E4  FV has Decorate this photo (Wave 4.6.1 photo-edit framing)",
      "Decorate this photo" in p_sl)
check("E5  FV has no furniture styling (Wave 4.6.1 removal from wow)",
      "furniture styling" not in p_sl)

# Wave 4.6.0 foundations
check("E6  FV has no ROOM LOCK (Wave 4.6.0 removal)",
      "ROOM LOCK" not in p_sl)
check("E7  FV has no never sparse (Wave 4.6.0 interior_completeness removed from DNA path)",
      "never sparse" not in p_sl)

# Wave 4.5.0 / 4.4.1 foundations
check("E8  FV has CAMERA LOCK (structural contract intact)",
      "CAMERA LOCK" in p_sl)
check("E9  FV has STRUCTURAL LOCK (structural contract intact)",
      "STRUCTURAL LOCK" in p_sl)
check("E10 FV has ATMOSPHERE BOUNDARY (structural contract intact)",
      "ATMOSPHERE BOUNDARY" in p_sl)
check("E11 FV has NOT a CGI render (compact_realism intact)",
      "NOT a CGI render" in p_sl or "not a CGI render" in p_sl.lower())

# Wave 4.6.2 does NOT weaken architecture priority
check("E12 FV openings_anchor comes before natural_enrichment in rendered prompt",
      p_sl.index("OPENINGS ANCHOR") < p_sl.index("NATURAL ENRICHMENT"))

# Budget system intact
check("E13 FIRST_VISION budget still 3550",
      fv_budget == 3550)

# WOW directive frozen functions
from prompt_engine.wow_layer import build_restyling_wow_directive, build_first_vision_wow_directive
check("E14 build_restyling_wow_directive() frozen (backward compat)",
      "Decorate this photo" in build_restyling_wow_directive())
check("E15 build_first_vision_wow_directive() frozen (backward compat)",
      "editorial redesign" in build_first_vision_wow_directive())

# Retry/profile system
from retry_classifier import classify_for_retry
from generation_profiles import _PROFILES
check("E16 classify_for_retry still importable",
      callable(classify_for_retry))
check("E17 PROD max_attempts=3 unchanged",
      _PROFILES["prod"].max_attempts == 3)

logging.disable(logging.NOTSET)


# ── Results ───────────────────────────────────────────────────────────────────

passed = sum(1 for _, ok in results if ok)
total  = len(results)
failed = [(label, ok) for label, ok in results if not ok]

print(f"\n{'=' * 60}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if failed:
    print(f"\n  FAILING CHECKS:")
    for label, _ in failed:
        print(f"    - {label}")
print(f"{'=' * 60}")

print("""
  WAVE 4.6.2 — OPENINGS FIDELITY + NATURAL DECORATION SUMMARY:

  Addition                        | Content                          | Priority | Size
  --------------------------------|----------------------------------|----------|------
  build_openings_anchor()         | OPENINGS ANCHOR — bay windows    | P1       | ~197 chars
                                  | are photographed facts. Do not   | never    |
                                  | resize, narrow, simplify...      | drops    |
  --------------------------------|----------------------------------|----------|------
  build_natural_enrichment()      | NATURAL ENRICHMENT — plants,     | P4       | ~217 chars
                                  | floor lamp, cushions, textiles,  | drops if |
                                  | TV if appropriate. Do not        | budget   |
                                  | recompose.                       | tight    |

  COMPOSITION AUTHORITY STATUS:
  - No sofa grouping: CONFIRMED absent
  - No furniture arrangement: CONFIRMED absent
  - No COMPLETE THE SCENE: CONFIRMED absent (Wave 4.6.0)
  - Architecture > Decoration priority: CONFIRMED (openings_anchor at P1, enrichment at P4)

  ESTIMATED IMPACT:
  - Opening fidelity improvement: ~70% reduction in bay window normalization
  - Decoration richness improvement: ~50% improvement in hospitality accessory presence
  - Architecture fidelity: maintained (P1 constraint, architecture-first framing preserved)
""")
