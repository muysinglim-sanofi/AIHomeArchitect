"""
Wave 4.7.1 validation suite — Structural Fidelity Stabilization (R1 + R2).

SCOPE (explicitly limited by instruction to the SAFE audit recommendations):
  R1 — image-specific structural anchors wired into FIRST_VISION (Path D),
       reusing the deterministic detect_anchors() the V2 path already uses.
  R2 — unify DNA / non-DNA FIRST_VISION fidelity policy:
       (a) non-DNA completeness="" (drop INTERIOR COMPLETENESS spatial-completion
           authority absent from the DNA path)
       (b) _style_block drops the specific "Furniture — <piece>" generation
           authority; restyles existing elements via material vocabulary only.

NO runtime/OpenAI features. No masks/fidelity/retries/quality/vision.
Out of scope (deferred): R3/R4/R5/R6, Tasks 3/4/5/6/7.

Suites:
  A — R1: detect_anchors wired into FIRST_VISION, P1, descriptive-only, graceful
  B — R2: DNA/non-DNA fidelity policy unified (completeness + furniture authority)
  C — No composition-authority regression; V2/V3 + preservation untouched
  D — Prior-wave invariants still hold
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


MID = "·"  # middot used in style labels ("Soft Luxury · Gold")
DNA_LABEL = f"Soft Luxury {MID} Gold"          # resolves to soft_luxury DNA
NONDNA_ROOM = "wine cellar"                     # no DNA for any atmosphere -> _style_block
RICH_DESC = ("Open-plan living room with black glass partition, bay window centered "
             "on the rear wall, diagonal spatial depth, visible kitchen on the right.")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()

logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS, _SECTION_PRIORITY
from prompt_engine.anchor_detector import detect_anchors
logging.disable(logging.CRITICAL)

FV_BUDGET = _MODE_BUDGETS["FIRST_VISION"]


# ── Suite A: R1 — image-specific anchors in FIRST_VISION ─────────────────────
print("\n=== Suite A: R1 — detect_anchors wired into FIRST_VISION ===")

check("A1  Wave 4.7.1 documented in composer",
      "Wave 4.7.1" in comp_src)
check("A2  detect_anchors imported in composer",
      "from .anchor_detector import detect_anchors" in comp_src)
check("A3  detect_anchors(room_description) called for FIRST_VISION",
      "fv_anchor_profile = detect_anchors(room_description)" in comp_src)
check("A4  architectural_anchors at P1 in _SECTION_PRIORITY",
      _SECTION_PRIORITY.get("architectural_anchors") == 1)
check("A5  ('architectural_anchors', fv_anchor_clause) in raw_sections",
      '("architectural_anchors", fv_anchor_clause)' in comp_src)

# Ordering: openings_anchor < architectural_anchors < source_space (all P1, Path D)
oa = comp_src.find('("openings_anchor", openings_anchor)')
aa = comp_src.find('("architectural_anchors", fv_anchor_clause)')
ss = comp_src.find('("source_space", source)', oa if oa > 0 else 0)
check("A6  architectural_anchors after openings_anchor, before source_space",
      0 < oa < aa < ss, f"oa={oa} aa={aa} ss={ss}")

# Rendered: V1 with a rich description gets the concrete anchor clause.
p_v1_rich = compose_generation_prompt(DNA_LABEL, "living room", RICH_DESC, "", 1, [])
check("A7  V1 (rich desc) contains ARCHITECTURAL ANCHORS — LOCKED",
      "ARCHITECTURAL ANCHORS" in p_v1_rich and "LOCKED" in p_v1_rich)
check("A8  V1 anchor clause names concrete structure (bay window / partition / depth)",
      any(t in p_v1_rich.lower() for t in ["bay window", "partition", "diagonal"]))

# Descriptive-only / architecture-only: no atmosphere or generation verbs in the clause.
ap = detect_anchors(RICH_DESC)
clause_l = ap.clause.lower()
check("A9  anchor clause is descriptive-only (no generation/atmosphere verbs)",
      ap.clause and not any(v in clause_l for v in
          ["redesign", "reimagine", "generate", "atmosphere", "luxury", "wow",
           "decorate", "transform", "restyle"]))
check("A10 anchor clause within 185-char cap (no prompt inflation)",
      0 < len(ap.clause) <= 185, f"len={len(ap.clause)}")

# Graceful empty: no description -> no anchor section, prompt still valid.
p_v1_empty = compose_generation_prompt(DNA_LABEL, "living room", "", "", 1, [])
check("A11 V1 (empty desc) has NO ARCHITECTURAL ANCHORS section (graceful, zero cost)",
      "ARCHITECTURAL ANCHORS" not in p_v1_empty)
check("A12 V1 (empty desc) still valid (SAME APARTMENT PHOTO-EDIT present)",
      "SAME APARTMENT PHOTO-EDIT" in p_v1_empty)

# Parity: V1 is no longer LESS anchored than V2 for the same description.
hist = [{"role": "user", "content": "x"}, {"role": "ai", "content": "y"},
        {"role": "user", "content": "warmer"}]
p_v2_rich = compose_generation_prompt(DNA_LABEL, "living room", RICH_DESC, "warmer", 2, hist)
check("A13 V1 and V2 both carry ARCHITECTURAL ANCHORS for same desc (anchor parity)",
      "ARCHITECTURAL ANCHORS" in p_v1_rich and "ARCHITECTURAL ANCHORS" in p_v2_rich)


# ── Suite B: R2 — DNA / non-DNA fidelity policy unified ──────────────────────
print("\n=== Suite B: R2 — DNA / non-DNA fidelity policy unified ===")

check("B1  non-DNA FIRST_VISION completeness unified to '' (Wave 4.7.1 R2 marker)",
      'completeness = ""  # Wave 4.7.1 R2' in comp_src)
check("B2  build_interior_completeness_rule() NO LONGER called in composer",
      "completeness = build_interior_completeness_rule()" not in comp_src)
check("B3  build_interior_completeness_rule still imported (validator-harness compat)",
      "build_interior_completeness_rule" in comp_src)
check("B4  _style_block drops specific furniture authority (no 'Furniture — {furn}')",
      'f"Furniture — {furn}. "' not in comp_src and 'dna.furniture[:2]' not in comp_src)
check("B5  _style_block keeps avoid/mood/lighting caps (wave421 D10-D12 regression)",
      "dna.avoid[:3]" in comp_src and "dna.mood[:2]" in comp_src and "dna.lighting[:2]" in comp_src)
check("B6  _style_block now uses 'restyle existing elements only' (DNA-philosophy parity)",
      "restyle existing elements only" in comp_src)

# Rendered non-DNA FIRST_VISION (wine cellar -> _style_block path)
p_nondna = compose_generation_prompt(DNA_LABEL, NONDNA_ROOM, RICH_DESC, "", 1, [])
check("B7  non-DNA V1 uses _style_block (STYLE (...) present, not ATMOSPHERE/ROOM DNA block)",
      "STYLE (" in p_nondna)
check("B8  non-DNA V1 has NO 'INTERIOR COMPLETENESS' (R2: removed)",
      "INTERIOR COMPLETENESS" not in p_nondna)
check("B9  non-DNA V1 has NO 'never sparse' spatial-completion authority",
      "never sparse" not in p_nondna)
check("B10 non-DNA V1 has NO specific furniture-generation authority ('sculptural curved sofa')",
      "sculptural curved sofa" not in p_nondna and "Furniture — " not in p_nondna)
check("B11 non-DNA V1 still premium (Materials + Palette + Lighting richness retained)",
      "Materials —" in p_nondna and "Palette —" in p_nondna and "Lighting —" in p_nondna)

# DNA path parity: DNA V1 already had completeness="" — both paths now consistent.
p_dna = compose_generation_prompt(DNA_LABEL, "living room", RICH_DESC, "", 1, [])
check("B12 DNA V1 has NO 'never sparse' (was already true — parity confirmed)",
      "never sparse" not in p_dna)
check("B13 DNA + non-DNA structural policy consistent (neither has INTERIOR COMPLETENESS)",
      "INTERIOR COMPLETENESS" not in p_dna and "INTERIOR COMPLETENESS" not in p_nondna)
check("B14 non-DNA V1 has NO 'Every zone inhabited' spatial-completion echo (R2 coherence fix)",
      "Every zone inhabited" not in p_nondna and "zone inhabited" not in p_nondna)
check("B15 non-DNA V1 richness reframed material/surface (not spatial completion)",
      "materially rich" in p_nondna or "every surface considered" in p_nondna.lower())


# ── Suite C: No composition-authority regression; V2/V3 untouched ────────────
print("\n=== Suite C: regression — preservation + V2/V3 untouched ===")

check("C1  V1 still SAME APARTMENT PHOTO-EDIT (4.6.1 intact)",
      "SAME APARTMENT PHOTO-EDIT" in p_dna)
check("C2  V1 still has OPENINGS ANCHOR (4.6.2 untouched — Task 4 deferred)",
      "OPENINGS ANCHOR" in p_dna)
check("C3  V1 still has CAMERA LOCK + STRUCTURAL LOCK + ATMOSPHERE BOUNDARY",
      all(k in p_dna for k in ["CAMERA LOCK", "STRUCTURAL LOCK", "ATMOSPHERE BOUNDARY"]))
check("C4  V1 still has TRANSFORMATION AMBITION (wow intact)",
      "TRANSFORMATION AMBITION" in p_dna)
check("C5  V1 has no SOURCE SPACE (4.6.1 intact)",
      "SOURCE SPACE" not in p_dna)

p_v2 = compose_generation_prompt(DNA_LABEL, "living room", RICH_DESC, "warmer", 2, hist)
check("C6  V2 still TOPOLOGY LOCKED + ATMOSPHERE SWITCH (unaffected)",
      "TOPOLOGY LOCKED" in p_v2 and "ATMOSPHERE SWITCH" in p_v2)
check("C7  V2 still has SOURCE SPACE (V2 unaffected by R1/R2)",
      "SOURCE SPACE" in p_v2)

# V3 routing unchanged (R3/Task5 deferred) — explicit structural request still
# routes to STRUCTURAL_TRANSFORMATION via the existing classifier path.
from prompt_engine.edit_intent import classify_edit_mode, EditMode
check("C8  V3 classifier unchanged: 'remove the wall' -> STRUCTURAL_TRANSFORMATION",
      classify_edit_mode("remove the wall between kitchen and living room", 2)
      == EditMode.STRUCTURAL_TRANSFORMATION)
check("C9  V1 always FIRST_VISION at iteration 1 (mode separation intact)",
      classify_edit_mode("", 1) == EditMode.FIRST_VISION)

check("C10 V1 within FIRST_VISION budget with anchors present",
      len(p_v1_rich) <= FV_BUDGET, f"got {len(p_v1_rich)}")
check("C11 anchor injection adds <=186 chars only (no inflation)",
      0 <= (len(p_v1_rich) - len(p_v1_empty)) <= 186,
      f"delta={len(p_v1_rich) - len(p_v1_empty)}")


# ── Suite D: prior-wave invariants ───────────────────────────────────────────
print("\n=== Suite D: prior-wave invariants still hold ===")

check("D1  interior_completeness still P5 (wave450 F2 regression)",
      _SECTION_PRIORITY.get("interior_completeness") == 5)
check("D2  ('interior_completeness', completeness) tuple still in raw_sections (wave460 E4)",
      '("interior_completeness", completeness)' in comp_src)
ic = comp_src.find('("interior_completeness", completeness)')
wd = comp_src.find('("wow_directive", wow_block)')
check("D3  interior_completeness before wow_directive in raw_sections (wave431 C6)",
      0 < ic < wd, f"ic={ic} wd={wd}")
ap2 = detect_anchors("Open-plan living room with black glass partition and balcony door.")
check("D4  detect_anchors still finds anchors in benchmark (wave431 F1 regression)",
      len(ap2.anchors) > 0)
check("D5  FV does NOT contain 'TOPOLOGY LOCKED' (wave433 G13 — anchor uses 'ANCHORS — LOCKED')",
      "TOPOLOGY LOCKED" not in p_v1_rich)
check("D6  openings_anchor wording unchanged (Task 4 deferred — no scope creep)",
      "Bay windows and openings are photographed facts, not design decisions" in p_dna)

logging.disable(logging.NOTSET)


# ── Results ───────────────────────────────────────────────────────────────────

passed = sum(1 for _, ok in results if ok)
total = len(results)
failed = [lbl for lbl, ok in results if not ok]

print(f"\n{'=' * 60}")
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {total - passed}")
if failed:
    print("\n  FAILING CHECKS:")
    for lbl in failed:
        print(f"    - {lbl}")
print(f"{'=' * 60}")

print("""
  WAVE 4.7.1 — STRUCTURAL FIDELITY STABILIZATION (R1 + R2):

  R1  V1 now injects concrete detect_anchors() clause (P1, descriptive-only,
      <=185 chars, graceful-empty). V1 no longer less anchored than V2.
  R2a non-DNA FIRST_VISION completeness="" — unified with DNA path.
  R2b _style_block drops specific furniture-generation authority.

  Same image + same atmosphere -> consistent structural behaviour.
  No runtime/OpenAI features. Preservation, V2, V3 untouched.
""")
