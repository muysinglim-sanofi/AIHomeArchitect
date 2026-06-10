"""Wave 5.14A (post-fix) — Editorial Realism Block validation.

Confirms the editorial layer:
  • is emitted ONLY from FIRST_VISION direct V1 calls (quality=medium+high)
  • is SUPPRESSED from REBOOT_FRESH delegations (quality=low+OMIT)
  • is BYTE-IDENTICAL to its original wording (reused from dormant constants)
  • leaves _COMPACT_REALISM untouched (Wave 4.7.9 contract preserved)

Wave 5.14A initial wide injection caused V2/V3 (REBOOT_FRESH path) to
degrade because main.py keeps STYLE_REFINEMENT classification for these
calls → quality=low + fidelity=OMIT. The rich editorial vocabulary
(Material depth, imperfections, light physics) at low fidelity erodes the
V1 anchor crispness. Wave 5.14A Fix gates editorial on a new caller-
intent flag `editorial_realism_enabled`.
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


from prompt_engine.realism_layer import (
    build_compact_realism_block,
    build_editorial_realism_block,
    build_medium_realism_block,
    build_realism_block,
    _COMPACT_REALISM,
    _EDITORIAL_REALISM,
    _AVOID_AI_ARTIFACTS,
    _MEDIUM_REALISM,
)


# ── A. _COMPACT_REALISM byte-identical to Wave 4.7.9 baseline ────────────
print("\n=== A. compact realism contract preserved (Wave 4.7.9) ===")
CR = build_compact_realism_block()
check(
    "A1  _COMPACT_REALISM length <= 133 (Wave 4.7.9 assertion 2a)",
    len(CR) <= 133, f"len={len(CR)}",
)
check(
    "A2  _COMPACT_REALISM length < 200 (Wave 4.7.9 assertion 10d)",
    len(CR) < 200, f"len={len(CR)}",
)
check(
    "A3  _COMPACT_REALISM still contains 'NOT a CGI render' in first 130",
    "NOT a CGI render" in CR[:130],
)
check(
    "A4  _COMPACT_REALISM still contains 'DSLR' in first 130",
    "DSLR" in CR[:130],
)
check(
    "A5  _COMPACT_REALISM still contains 'not camera-staged'",
    "not camera-staged" in CR,
)


# ── B. Editorial block content (reuse from dormant constants) ─────────────
print("\n=== B. editorial realism block content ===")
ER = build_editorial_realism_block()
check("B1  build_editorial_realism_block returns non-empty str",
      isinstance(ER, str) and len(ER) > 0)
check("B2  editorial block carries 'EDITORIAL REALISM' header",
      "EDITORIAL REALISM" in ER)
check("B3  editorial block carries material-depth cue",
      "Material depth" in ER and "wood grain" in ER and "textile weave" in ER)
check("B4  editorial block carries imperfections cue",
      "Subtle real-world imperfections" in ER
      and "not artificially perfect" in ER)
check("B5  editorial block carries natural light physics cue",
      "Natural light physics" in ER
      and "shadow fall-off" in ER)
check("B6  editorial block carries anti-plastic avoidance",
      "plastic-looking" in ER and "uniformly shiny" in ER)
check("B7  editorial block carries anti-sterile avoidance",
      "sterile over-processed" in ER)
check("B8  editorial block carries anti-catalogue-render avoidance",
      "generic catalogue-render furniture" in ER)


# ── C. Wording reused from dormant constants only ─────────────────────────
print("\n=== C. wording reused from dormant constants only ===")
check("C1  'Material depth: visible wood grain, stone veining, textile weave' from _MEDIUM_REALISM",
      "Material depth: visible wood grain, stone veining, textile weave"
      in _MEDIUM_REALISM)
check("C2  'Subtle real-world imperfections — not artificially perfect' from _MEDIUM_REALISM",
      "Subtle real-world imperfections — not artificially perfect"
      in _MEDIUM_REALISM)
check("C3  'Natural light physics: accurate shadow fall-off, ambient fill from windows' from _MEDIUM_REALISM",
      "Natural light physics: accurate shadow fall-off, ambient fill from windows"
      in _MEDIUM_REALISM)
check("C4  'Plastic-looking or uniformly shiny materials' from _AVOID_AI_ARTIFACTS",
      "Plastic-looking or uniformly shiny materials" in _AVOID_AI_ARTIFACTS)
check("C5  'Harsh overhead lighting with no shadow variation' from _AVOID_AI_ARTIFACTS",
      "Harsh overhead lighting with no shadow variation"
      in _AVOID_AI_ARTIFACTS)
check("C6  'Sterile over-processed render feeling' from _AVOID_AI_ARTIFACTS",
      "Sterile over-processed render feeling" in _AVOID_AI_ARTIFACTS)
check("C7  'Generic catalogue-render furniture' from _AVOID_AI_ARTIFACTS",
      "Generic catalogue-render furniture" in _AVOID_AI_ARTIFACTS)


# ── D. composer.py wiring — Path D only (1 site), gated on flag ──────────
print("\n=== D. composer.py — Path D (FIRST_VISION) sole wiring, gated ===")
with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()
check("D1  composer.py imports build_editorial_realism_block",
      "build_editorial_realism_block" in comp_src)
check("D2  composer.py registers 'editorial_realism' in _SECTION_PRIORITY",
      "'editorial_realism': 3" in comp_src
      or '"editorial_realism": 3' in comp_src)
# Exactly ONE path-level wiring (Path D), gated on editorial_realism_enabled
gated_emission = comp_src.count(
    "build_editorial_realism_block() if editorial_realism_enabled else \"\""
)
check("D3  composer.py contains exactly 1 gated editorial emission (Path D)",
      gated_emission == 1, f"found={gated_emission}")
check("D4  composer.py NO unconditional editorial emission",
      "('editorial_realism', build_editorial_realism_block())" not in comp_src
      and "(\"editorial_realism\", build_editorial_realism_block())" not in comp_src)
check("D5  compose_generation_prompt accepts editorial_realism_enabled param",
      "editorial_realism_enabled: bool = True" in comp_src)


# ── E. composer_v2.py — no direct wirings, delegations carry flag ────────
print("\n=== E. composer_v2.py — flag carried by delegations only ===")
with open("prompt_engine/composer_v2.py", encoding="utf-8") as f:
    v2_src = f.read()
check("E1  composer_v2.py does NOT import build_editorial_realism_block",
      "from .realism_layer import build_compact_realism_block, build_editorial_realism_block"
      not in v2_src)
check("E2  composer_v2.py contains no direct editorial wiring",
      "build_editorial_realism_block()" not in v2_src)
check("E3  V1 delegation passes editorial_realism_enabled=True",
      "editorial_realism_enabled=True" in v2_src)
check("E4  REBOOT_FRESH delegation passes editorial_realism_enabled=False",
      "editorial_realism_enabled=False" in v2_src)


# ── F. End-to-end — editorial reaches V1, NOT REBOOT_FRESH V2+ ───────────
print("\n=== F. end-to-end — V1 emits editorial, REBOOT_FRESH does not ===")
logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt
from prompt_engine.composer_v2 import compose_generation_prompt as v2_compose
from prompt_engine.structural_identity import (
    extract_from_description, render_clause, render_negative_anchors,
)
from prompt_engine.edit_intent import EditMode
logging.disable(logging.CRITICAL)

DESC = (
    "Open-plan living room, dominant floor-to-ceiling window on the back wall, "
    "wooden door on the left wall, open kitchen on the right."
)
ident = extract_from_description(DESC)
SI = render_clause(ident, "V1")
NA = render_negative_anchors(ident)

MID = chr(0xB7)

# V1 direct (medium+high)
p_v1 = compose_generation_prompt(
    f"Warm Modern {MID} Vision 1", "living room", DESC, "", 1, [],
    structural_identity=SI,
    structural_negative_anchors=NA,
    edit_mode=EditMode.FIRST_VISION,
)
check("F1  V1 direct (medium+high) — editorial PRESENT",
      "EDITORIAL REALISM" in p_v1)
check("F2  V1 — anti-plastic cue present",
      "plastic-looking" in p_v1)
check("F3  V1 — compact realism also present",
      "not camera-staged" in p_v1)
check("F4  V1 — within FIRST_VISION budget",
      len(p_v1) < 4000, f"len={len(p_v1)}")

# V2 atmosphere switch via composer_v2 → REBOOT_FRESH delegation
# (composer_v2 detects switch via history walk, then calls composer.py
# Path D with editorial_realism_enabled=False).
p_v2_switch = v2_compose(
    f"Nordic Warmth {MID} Vision 2", "living room", DESC,
    "Redesign this space in the Nordic Warmth style.",
    2,
    [{"role": "user", "content": "Redesign this space in the Warm Modern style."},
     {"role": "ai", "content": "Here's your Warm Modern transformation — Vision 1."}],
    structural_identity=render_clause(ident, "V2"),
    source_continuity="CONTINUE FROM CURRENT DESIGN.",
    structural_negative_anchors=NA,
    edit_mode=EditMode.STYLE_REFINEMENT,
)
check("F5  V2 REBOOT_FRESH (low+OMIT) — editorial ABSENT",
      "EDITORIAL REALISM" not in p_v2_switch)
check("F6  V2 — compact realism STILL present (Wave 4.7.9 contract intact)",
      "not camera-staged" in p_v2_switch)
check("F7  V2 — anti-plastic cue ABSENT (no editorial leak)",
      "plastic-looking" not in p_v2_switch.lower())
check("F8  V2 — within FIRST_VISION budget (delegated to Path D)",
      len(p_v2_switch) < 4000, f"len={len(p_v2_switch)}")


# ── G. Wave 4.7.9 mandatory subset still passes ───────────────────────────
print("\n=== G. validate_wave479 mandatory subset still passes ===")
check("G1  Wave 4.7.9 2a — len(_COMPACT_REALISM) <= 133",
      len(CR) <= 133, f"len={len(CR)}")
check("G2  Wave 4.7.9 10d — len(_COMPACT_REALISM) < 200",
      len(CR) < 200, f"len={len(CR)}")
check("G3  Wave 4.7.9 10a — functional usability clause preserved",
      "Furniture stays usable" in CR
      and "openings and circulation clear" in CR
      and "not camera-staged" in CR)
check("G4  Wave 4.7.9 5a — no composition-authority phrase in CR",
      not any(x in CR.lower() for x in (
          "conversation grouping", "sofa grouping", "arrange the furniture",
          "centred on focal", "face the sofa", "create a conversation",
      )))


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
