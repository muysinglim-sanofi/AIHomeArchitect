"""
Wave 4.2.4 validation suite — Prompt Compression + Stable Dream Richness.

Goal: Replace blind [:3800] truncation with a priority-based budget system.
Primary compression: medium realism block (~310 chars vs ~995 for full).
Secondary compression: compact camera lock in Tier 2 (~198 vs ~464 chars).
Dream richness micro-layer added to DNA paths in FV and SR.

Suites:
  A — Medium realism block: content and size
  B — Dream micro-layer: content and size
  C — Budget system: _MODE_BUDGETS + _SECTION_PRIORITY + _assemble_with_budget present
  D — Compact camera lock: Tier 2 size and vocabulary
  E — Per-mode size budgets (hard caps enforced by _assemble_with_budget)
  F — Critical vocabulary survives after Wave 4.2.4 changes
  G — Dream richness present on correct paths
  H — No blind truncation in composer source
"""

import io
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"

results = []


def check(label: str, condition: bool, detail: str = "") -> None:
    status = PASS if condition else FAIL
    suffix = f"  [{detail}]" if detail and not condition else ""
    print(f"  {status}  {label}{suffix}")
    results.append((label, condition))


# ── Suite A: Medium realism block ─────────────────────────────────────────────
print("\n=== Suite A: Medium realism block ===")

from prompt_engine.realism_layer import (
    build_realism_block,
    build_compact_realism_block,
    build_medium_realism_block,
)

rb_medium = build_medium_realism_block()

check("A1  build_medium_realism_block callable and returns str",
      callable(build_medium_realism_block) and isinstance(rb_medium, str))
check("A2  medium realism under 350 chars (target 250-350)",
      len(rb_medium) <= 350, f"got {len(rb_medium)}")
check("A3  medium realism at least 250 chars (not too stripped)",
      len(rb_medium) >= 250, f"got {len(rb_medium)}")
check("A4  medium realism has NOT a CGI render",
      "NOT a CGI render" in rb_medium)
check("A5  medium realism has DSLR",
      "DSLR" in rb_medium)
check("A6  medium realism has real estate photography",
      "real estate" in rb_medium.lower())
check("A7  medium realism has natural light physics",
      "natural light" in rb_medium.lower())
check("A8  medium realism has material depth (grain/veining/weave)",
      "grain" in rb_medium.lower() or "veining" in rb_medium.lower() or "weave" in rb_medium.lower())
check("A9  medium realism has correct scale",
      "scale" in rb_medium.lower() or "human scale" in rb_medium.lower())
check("A10 medium realism has imperfections",
      "imperfect" in rb_medium.lower())
check("A11 medium realism smaller than full realism (primary compression)",
      len(rb_medium) < len(build_realism_block()),
      f"medium={len(rb_medium)} full={len(build_realism_block())}")
check("A12 medium realism savings at least 600 chars vs full",
      len(build_realism_block()) - len(rb_medium) >= 600,
      f"savings={len(build_realism_block()) - len(rb_medium)}")
check("A13 compact realism unchanged (must be < 200 chars)",
      len(build_compact_realism_block()) < 200, f"got {len(build_compact_realism_block())}")
check("A14 full realism unchanged (must be > 900 chars)",
      len(build_realism_block()) > 900, f"got {len(build_realism_block())}")
check("A15 NOT a CGI render in first 130 chars of medium realism",
      "NOT a CGI render" in rb_medium[:130])
check("A16 DSLR in first 130 chars of medium realism",
      "DSLR" in rb_medium[:130])


# ── Suite B: Dream micro-layer ────────────────────────────────────────────────
print("\n=== Suite B: Dream micro-layer ===")

from prompt_engine.dream_scene_completion import (
    build_dream_micro_layer,
    build_dream_addendum,
    build_scene_completion,
)

dm = build_dream_micro_layer()

check("B1  build_dream_micro_layer callable and returns str",
      callable(build_dream_micro_layer) and isinstance(dm, str))
check("B2  dream micro-layer between 50 and 120 chars",
      50 <= len(dm) <= 120, f"got {len(dm)}")
check("B3  dream micro-layer has lighting reference",
      "light" in dm.lower())
check("B4  dream micro-layer has furnishing/composition reference",
      "furnish" in dm.lower() or "composition" in dm.lower())
check("B5  dream micro-layer has warmth/atmosphere reference",
      "warm" in dm.lower() or "atmosphere" in dm.lower())
check("B6  build_dream_addendum unchanged (still returns str)",
      isinstance(build_dream_addendum("soft_luxury"), str))
check("B7  build_scene_completion unchanged (still returns str)",
      isinstance(build_scene_completion("living room", "soft_luxury"), str))


# ── Suite C: Budget system in composer ────────────────────────────────────────
print("\n=== Suite C: Budget system in composer ===")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    composer_src = f.read()

check("C1  _MODE_BUDGETS defined in composer",
      "_MODE_BUDGETS" in composer_src)
check("C2  FIRST_VISION budget 3250 in composer",
      "3250" in composer_src)
check("C3  STYLE_REFINEMENT budget 2400 in composer",
      '"STYLE_REFINEMENT": 2400' in composer_src)
check("C4  STRUCTURAL_TRANSFORMATION budget 2500 in composer",
      '"STRUCTURAL_TRANSFORMATION": 2500' in composer_src)
check("C5  LOCAL_EDIT budget 1500 in composer",
      '"LOCAL_EDIT": 1500' in composer_src)
check("C6  _SECTION_PRIORITY defined in composer",
      "_SECTION_PRIORITY" in composer_src)
check("C7  _assemble_with_budget defined in composer",
      "_assemble_with_budget" in composer_src)
check("C8  No blind char-boundary truncation in composer (no prompt[:N] clipping)",
      "prompt[:_MAX" not in composer_src and "_MAX_CHARS - 3" not in composer_src)
check("C9  No blind truncation [:_MAX_CHARS] in composer",
      "[:_MAX_CHARS" not in composer_src)
check("C10 Prompt Budget log line present in composer",
      "[Prompt Budget]" in composer_src)
check("C11 build_medium_realism_block imported in composer",
      "build_medium_realism_block" in composer_src)
check("C12 build_dream_micro_layer imported in composer",
      "build_dream_micro_layer" in composer_src)


# ── Suite D: Compact camera lock (Tier 2) ────────────────────────────────────
print("\n=== Suite D: Compact camera lock ===")

from prompt_engine.preservation import (
    build_structural_evolution_contract,
    _CAMERA_LOCK_COMPACT,
    _CAMERA_LOCK,
)

c_evol_lr = build_structural_evolution_contract("living room")

check("D1  _CAMERA_LOCK_COMPACT defined and is str",
      isinstance(_CAMERA_LOCK_COMPACT, str))
check("D2  _CAMERA_LOCK_COMPACT under 240 chars",
      len(_CAMERA_LOCK_COMPACT) <= 240, f"got {len(_CAMERA_LOCK_COMPACT)}")
check("D3  _CAMERA_LOCK_COMPACT has CAMERA LOCK",
      "CAMERA LOCK" in _CAMERA_LOCK_COMPACT)
check("D4  _CAMERA_LOCK_COMPACT has focal length",
      "focal length" in _CAMERA_LOCK_COMPACT.lower())
check("D5  _CAMERA_LOCK_COMPACT has vanishing points",
      "vanishing point" in _CAMERA_LOCK_COMPACT.lower())
check("D6  _CAMERA_LOCK_COMPACT has horizon line",
      "horizon line" in _CAMERA_LOCK_COMPACT.lower())
check("D7  _CAMERA_LOCK_COMPACT has SAME apartment",
      "same apartment" in _CAMERA_LOCK_COMPACT.lower() or "SAME" in _CAMERA_LOCK_COMPACT)
check("D8  Compact lock significantly smaller than full (at least 200 chars smaller)",
      len(_CAMERA_LOCK) - len(_CAMERA_LOCK_COMPACT) >= 200,
      f"full={len(_CAMERA_LOCK)} compact={len(_CAMERA_LOCK_COMPACT)}")
check("D9  Tier 2 uses compact lock (< 750 chars for living room)",
      len(c_evol_lr) < 750, f"got {len(c_evol_lr)}")
check("D10 Tier 2 still has camera and vanishing vocabulary",
      "camera" in c_evol_lr.lower() and "vanishing" in c_evol_lr.lower())
check("D11 Full _CAMERA_LOCK unchanged (Tier 1 regression)",
      "focal length" in _CAMERA_LOCK.lower() and "horizon line" in _CAMERA_LOCK.lower())


# ── Suite E: Per-mode size budgets ────────────────────────────────────────────
print("\n=== Suite E: Per-mode size budgets ===")

import logging
logging.disable(logging.CRITICAL)

from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS

room_desc = "Open-plan living room, natural light from west-facing windows, existing oak floors, high ceilings."
history_v2 = [
    {"role": "user", "content": "I want Japandi style, calm and minimal"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer and add more texture"},
]

p_fv_j = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "", 1, [])
p_fv_z = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", room_desc, "", 1, [])
p_sr_j = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc,
    "more luxurious atmosphere, richer mood", 2, history_v2)
p_sr_z = compose_generation_prompt(
    "Zen Retreat · Serenity", "living room", room_desc,
    "calmer, more serene vibe", 2, history_v2)
p_st = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc,
    "open up the facade, add a large window", 2, history_v2)
p_le = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc,
    "add a floor lamp next to the sofa", 2, history_v2)

logging.disable(logging.NOTSET)

fv_budget = _MODE_BUDGETS["FIRST_VISION"]
sr_budget = _MODE_BUDGETS["STYLE_REFINEMENT"]
st_budget = _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"]
le_budget = _MODE_BUDGETS["LOCAL_EDIT"]

check(f"E1  FIRST_VISION (Japandi/no-DNA) within budget ({fv_budget})",
      len(p_fv_j) <= fv_budget, f"got {len(p_fv_j)}")
check(f"E2  FIRST_VISION (Zen/DNA) within budget ({fv_budget})",
      len(p_fv_z) <= fv_budget, f"got {len(p_fv_z)}")
check("E2a FIRST_VISION (Zen/DNA) under 3200 (DNA path has no scene_completion overhead)",
      len(p_fv_z) <= 3200, f"got {len(p_fv_z)}")
check(f"E3  STYLE_REFINEMENT (Japandi/no-DNA) within budget ({sr_budget})",
      len(p_sr_j) <= sr_budget, f"got {len(p_sr_j)}")
check(f"E4  STYLE_REFINEMENT (Zen/DNA) within budget ({sr_budget})",
      len(p_sr_z) <= sr_budget, f"got {len(p_sr_z)}")
check(f"E5  STRUCTURAL_TRANSFORMATION within budget ({st_budget})",
      len(p_st) <= st_budget, f"got {len(p_st)}")
check(f"E6  LOCAL_EDIT within budget ({le_budget})",
      len(p_le) <= le_budget, f"got {len(p_le)}")
check("E7  All modes under gpt-image-1 4000-char hard limit",
      all(len(p) < 4000 for p in [p_fv_j, p_fv_z, p_sr_j, p_sr_z, p_st, p_le]))
check("E8  FIRST_VISION compression vs Wave 4.2.1 full-realism baseline",
      len(p_fv_j) <= 3250, f"got {len(p_fv_j)} (target ≤3250)")
check("E9  FIRST_VISION at least 1800 chars (not accidentally empty)",
      len(p_fv_j) >= 1800, f"got {len(p_fv_j)}")
check("E10 FV significantly smaller than FIRST_VISION with full realism would have been",
      len(p_fv_j) < 3800, f"got {len(p_fv_j)}")


# ── Suite F: Critical vocabulary survives ─────────────────────────────────────
print("\n=== Suite F: Critical vocabulary survives ===")

for label, prompt in [
    ("FV_J", p_fv_j),
    ("FV_Z", p_fv_z),
    ("SR_J", p_sr_j),
    ("SR_Z", p_sr_z),
    ("ST", p_st),
    ("LE", p_le),
]:
    check(f"F-{label}: NOT a CGI render present",
          "NOT a CGI render" in prompt or "not a cgi" in prompt.lower())
    check(f"F-{label}: DSLR present",
          "DSLR" in prompt)

check("F-FV_J: vanishing points in FIRST_VISION",
      "vanishing point" in p_fv_j.lower())
check("F-FV_Z: vanishing points in FIRST_VISION (DNA)",
      "vanishing point" in p_fv_z.lower())
check("F-SR_J: vanishing points in STYLE_REFINEMENT",
      "vanishing point" in p_sr_j.lower())
check("F-SR_Z: vanishing points in STYLE_REFINEMENT (DNA)",
      "vanishing point" in p_sr_z.lower())
check("F-ST: vanishing points in STRUCTURAL_TRANSFORMATION",
      "vanishing point" in p_st.lower())
check("F-SR_J: windows unblocked in STYLE_REFINEMENT",
      "unblocked" in p_sr_j.lower() and "window" in p_sr_j.lower())
check("F-FV_J: CAMERA LOCK in FIRST_VISION",
      "CAMERA LOCK" in p_fv_j)
check("F-ST: CAMERA LOCK in STRUCTURAL_TRANSFORMATION",
      "CAMERA LOCK" in p_st)


# ── Suite G: Dream richness on correct paths ──────────────────────────────────
print("\n=== Suite G: Dream richness paths ===")

micro_text = build_dream_micro_layer()
addendum_text = build_dream_addendum("japandi_calm")

check("G1  FV Japandi (no-DNA): scene_completion present (not dream_micro)",
      "COMPLETE THE SCENE" in p_fv_j)
check("G2  FV Japandi (no-DNA): QUALITY atmosphere note present",
      "QUALITY" in p_fv_j)
check("G3  FV Zen (DNA): dream_micro injected",
      micro_text in p_fv_z)
check("G4  FV Zen (DNA): COMPLETE THE SCENE not present (DNA path skips it)",
      "COMPLETE THE SCENE" not in p_fv_z)
check("G5  SR Japandi (no-DNA): dream_addendum injected",
      "DREAM QUALITY" in p_sr_j)
check("G6  SR Zen (DNA): dream_micro injected",
      micro_text in p_sr_z)
check("G7  SR Zen (DNA): DREAM QUALITY not in SR (no dream_addendum on DNA paths)",
      "DREAM QUALITY" not in p_sr_z)
check("G8  dream_micro is compact (78 chars)",
      len(micro_text) <= 100)


# ── Suite H: No blind truncation ──────────────────────────────────────────────
print("\n=== Suite H: No blind truncation ===")

check("H1  No _MAX_CHARS global in composer (replaced by _MODE_BUDGETS)",
      "_MAX_CHARS = " not in composer_src)
check("H2  No [:4000] in composer",
      "[:4000]" not in composer_src)
check("H3  No [:_MAX_CHARS] in composer",
      "[:_MAX_CHARS" not in composer_src)
check("H4  _MAX_CHARS global removed from composer",
      "_MAX_CHARS = " not in composer_src)
check("H5  _assemble_with_budget used in all four paths",
      composer_src.count("_assemble_with_budget(") >= 4)
check("H6  [Prompt Budget] logged in all four paths",
      composer_src.count("[Prompt Budget]") >= 4)


# ── Summary ───────────────────────────────────────────────────────────────────
print()
print("=" * 60)
total = len(results)
passed = sum(1 for _, ok in results if ok)
failed = total - passed
print(f"  TOTAL: {total}   PASSED: {passed}   FAILED: {failed}")
if failed:
    print("\n  FAILING CHECKS:")
    for label, ok in results:
        if not ok:
            print(f"    - {label}")
print("=" * 60)
print()
print("  PROMPT SIZE REPORT (Wave 4.2.4):")
for label, prompt in [
    ("FIRST_VISION  (Japandi/no-DNA)", p_fv_j),
    ("FIRST_VISION  (Zen/DNA)       ", p_fv_z),
    ("STYLE_REFINE  (Japandi/no-DNA)", p_sr_j),
    ("STYLE_REFINE  (Zen/DNA)       ", p_sr_z),
    ("STRUCT_TRANS  (Japandi/no-DNA)", p_st),
    ("LOCAL_EDIT    (Japandi)       ", p_le),
]:
    print(f"    {label}: {len(prompt)} chars")
print()
print("  MANUAL VALIDATION REQUIRED:")
print("  [MANUAL] 5 consecutive FIRST_VISION generations — no RemoteProtocolError")
print("  [MANUAL] Soft Luxury, Japandi, Zen, Tropical — check premium feel")
print("  [MANUAL] V2+ generations — geometry preserved, no drift")
print("  [MANUAL] Outputs: layered lighting, complete furnishing, warm atmosphere")
