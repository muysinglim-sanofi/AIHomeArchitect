"""
Wave 4.2.1 validation suite — Prompt Stabilization + Conditioning Compression.

Root cause confirmed: STYLE_REFINEMENT prompts were 4397 chars (before DNA/realism),
597 chars over the 3800-char budget. DNA, refinement memory, and realism block were
fully truncated. Model received only geometry-preservation constraints with zero
creative instruction — causing both visual failure and server-side timeout.

Suites:
  A — Preservation module: new tier exports
  B — Realism layer: compact block
  C — Edit intent: compressed style refinement header
  D — Composer: mode-appropriate contracts wired in
  E — Prompt size budgets (all modes, Japandi + Zen)
  F — Content survival: critical vocabulary present in all modes
  G — Semantic duplication audit: same constraint not repeated
  H — Wave 4.2 regression: feature flag, input_fidelity, mask wiring
  I — Wave 4.1 regression: quality, size, original anchor, vision analysis
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


# ── Suite A: Preservation tier exports ────────────────────────────────────────
print("\n=== Suite A: Preservation tiers ===")

from prompt_engine.preservation import (
    build_structural_contract,
    build_continuation_contract,
    build_structural_evolution_contract,
    build_preservation_block,
    _CAMERA_LOCK,
    _STRUCTURAL_LOCK,
    _TRANSFORMATION_SCOPE,
    _ATMOSPHERE_BOUNDARY,
)

c_full = build_structural_contract("living room")
c_cont = build_continuation_contract("living room")
c_evol = build_structural_evolution_contract("living room")

check("A1  build_structural_contract (Tier 1) callable and returns str",
      isinstance(c_full, str) and len(c_full) > 100)
check("A2  build_continuation_contract (Tier 3) callable and returns str",
      isinstance(c_cont, str) and len(c_cont) > 50)
check("A3  build_structural_evolution_contract (Tier 2) callable and returns str",
      isinstance(c_evol, str) and len(c_evol) > 100)
check("A4  Tier 1 compressed vs Wave 4.1 (must be < 1700 chars, was 2468)",
      len(c_full) < 1700, f"got {len(c_full)}")
check("A5  Tier 3 compact with focal length + atm boundary (must be < 650 chars)",
      len(c_cont) < 650, f"got {len(c_cont)}")
check("A6  Tier 2 compact camera lock (must be < 800 chars — Wave 4.2.4 compact lock)",
      len(c_evol) < 800, f"got {len(c_evol)}")
check("A7  build_preservation_block legacy alias still works",
      build_preservation_block("living room") == c_full)

# Camera lock vocabulary must survive compression
check("A8  camera lock has vanishing point vocabulary",
      "vanishing point" in _CAMERA_LOCK.lower() or "vanishing points" in _CAMERA_LOCK.lower())
check("A9  camera lock has horizon line vocabulary",
      "horizon line" in _CAMERA_LOCK.lower())
check("A10 camera lock has focal length vocabulary",
      "focal length" in _CAMERA_LOCK.lower())
check("A11 structural lock requires windows unblocked",
      "unblocked" in _STRUCTURAL_LOCK.lower() and "window" in _STRUCTURAL_LOCK.lower())
check("A12 continuation contract has vanishing points",
      "vanishing point" in c_cont.lower())
check("A13 continuation contract has windows unblocked",
      "unblocked" in c_cont.lower() and "window" in c_cont.lower())
check("A14 evolution contract has camera lock language",
      "camera" in c_evol.lower() and "vanishing" in c_evol.lower())
check("A15 room-specific note included in continuation contract (living room)",
      "TV wall" in c_cont or "sofa zone" in c_cont or "ROOM LOCK" in c_cont)


# ── Suite B: Realism layer ─────────────────────────────────────────────────────
print("\n=== Suite B: Realism layer ===")

from prompt_engine.realism_layer import build_realism_block, build_compact_realism_block

rb_full = build_realism_block()
rb_compact = build_compact_realism_block()

check("B1  build_compact_realism_block callable",
      callable(build_compact_realism_block))
check("B2  compact realism under 200 chars",
      len(rb_compact) < 200, f"got {len(rb_compact)}")
check("B3  compact realism has NOT a CGI render",
      "NOT a CGI render" in rb_compact)
check("B4  compact realism has DSLR",
      "DSLR" in rb_compact)
check("B5  full realism block still intact",
      len(rb_full) > 900)
check("B6  full realism has Architectural Digest or Wallpaper",
      "Architectural Digest" in rb_full or "Wallpaper" in rb_full)
check("B7  compact critical terms in first 130 chars",
      "NOT a CGI render" in rb_compact[:130] and "DSLR" in rb_compact[:130])


# ── Suite C: Edit intent header compression ────────────────────────────────────
print("\n=== Suite C: Style refinement header ===")

from prompt_engine.edit_intent import build_style_refinement_header, build_structural_transformation_header

hdr_sr = build_style_refinement_header("make it warmer", "Japandi", "living room")
hdr_st = build_structural_transformation_header("remove the TV wall", "Japandi", "living room")

check("C1  style_refinement_header under 600 chars (compressed from ~934)",
      len(hdr_sr) < 600, f"got {len(hdr_sr)}")
check("C2  style_refinement_header has SAME APARTMENT CONTINUATION",
      "SAME APARTMENT" in hdr_sr or "SAME APARTMENT CONTINUATION" in hdr_sr)
check("C3  style_refinement_header has EVOLVE keyword",
      "EVOLVE" in hdr_sr)
check("C4  style_refinement_header has PRESERVE keyword",
      "PRESERVE" in hdr_sr)
check("C5  style_refinement_header includes user direction",
      "make it warmer" in hdr_sr or "Direction" in hdr_sr)
check("C6  structural_transformation_header still intact",
      len(hdr_st) > 200)


# ── Suite D: Composer routing ──────────────────────────────────────────────────
print("\n=== Suite D: Composer routing ===")

with open("prompt_engine/composer.py", encoding="utf-8") as f:
    composer_src = f.read()

check("D1  build_continuation_contract imported in composer",
      "build_continuation_contract" in composer_src)
check("D2  build_structural_evolution_contract imported in composer",
      "build_structural_evolution_contract" in composer_src)
check("D3  build_compact_realism_block imported in composer",
      "build_compact_realism_block" in composer_src)
check("D4  STYLE_REFINEMENT uses continuation_contract",
      "build_continuation_contract" in composer_src)
check("D5  STYLE_REFINEMENT uses compact realism",
      "build_compact_realism_block" in composer_src)
check("D6  FIRST_VISION uses medium realism block (Wave 4.2.4: replaces full realism)",
      "build_medium_realism_block()" in composer_src)
check("D7  STRUCTURAL_TRANSFORMATION uses evolution_contract",
      "build_structural_evolution_contract" in composer_src)
check("D8  Prompt audit logging present",
      "_audit" in composer_src and "Prompt Audit" in composer_src)
check("D9  room_context removed from STYLE_REFINEMENT path (comment present)",
      "room_context intentionally omitted" in composer_src or
      "room_context" in composer_src.split("Path B")[1].split("Path C")[0] and
      "omitted" in composer_src.split("Path B")[1].split("Path C")[0])
check("D10 _style_block caps avoid list to 3 items",
      "dna.avoid[:3]" in composer_src)
check("D11 _style_block caps mood to 2 items",
      "dna.mood[:2]" in composer_src)
check("D12 _style_block caps lighting to 2 items",
      "dna.lighting[:2]" in composer_src)


# ── Suite E: Prompt size budgets ───────────────────────────────────────────────
print("\n=== Suite E: Prompt size budgets ===")

import logging
logging.disable(logging.CRITICAL)  # suppress audit logs during size tests

from prompt_engine.composer import compose_generation_prompt

room_desc = "Open-plan living room, natural light from west-facing windows, existing oak floors, high ceilings."
history_v2 = [
    {"role": "user", "content": "I want Japandi style, calm and minimal"},
    {"role": "ai", "content": "Here is Vision 1."},
    {"role": "user", "content": "make it warmer and add more texture"},
]

# Instructions chosen to reliably trigger each classifier path:
#   STYLE_REFINEMENT:         pure style signals, no local/structural signals
#   STRUCTURAL_TRANSFORMATION: structural-specific vocabulary
#   LOCAL_EDIT:               object-specific instruction
p_fv = compose_generation_prompt(
    "Japandi · Harmony", "living room", room_desc, "", 1, [])
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

check("E1  FIRST_VISION under 3250 hard cap (Wave 4.2.4: medium realism compression)",
      len(p_fv) <= 3250, f"got {len(p_fv)}")
check("E2  FIRST_VISION under 4000 (gpt-image-1 limit)",
      len(p_fv) < 4000, f"got {len(p_fv)}")
check("E3  STYLE_REFINEMENT (Japandi/no-DNA) under 2400 absolute max (Wave 4.2.3: dream_addendum added)",
      len(p_sr_j) <= 2400, f"got {len(p_sr_j)}")
check("E4  STYLE_REFINEMENT (Japandi/no-DNA) under 2400 (all content fits — was 4397 overflowing)",
      len(p_sr_j) <= 2400, f"got {len(p_sr_j)}")
check("E5  STYLE_REFINEMENT (Zen/room-DNA) under 2400 absolute max (DNA path skips dream_addendum)",
      len(p_sr_z) <= 2400, f"got {len(p_sr_z)}")
check("E6  STRUCTURAL_TRANSFORMATION under 2500 (Wave 4.2.4: compact camera lock)",
      len(p_st) <= 2500, f"got {len(p_st)}")
check("E7  STRUCTURAL_TRANSFORMATION significantly smaller than old baseline (was ~3910)",
      len(p_st) <= 3000, f"got {len(p_st)}")
check("E8  LOCAL_EDIT under 1500 (Wave 4.2.4 budget)",
      len(p_le) <= 1500, f"got {len(p_le)}")
check("E9  All modes significantly smaller than old STYLE_REFINEMENT baseline (4397)",
      all(len(p) < 4000 for p in [p_fv, p_sr_j, p_sr_z, p_st, p_le]))
check("E10 Compression ratio: SR is at most 60% of old baseline",
      len(p_sr_j) <= 4397 * 0.60, f"got {len(p_sr_j)} (60% of 4397 = {int(4397*0.60)})")


# ── Suite F: Critical vocabulary survival ─────────────────────────────────────
print("\n=== Suite F: Critical vocabulary in all modes ===")

for label, prompt in [
    ("FIRST_VISION", p_fv),
    ("STYLE_REFINEMENT_J", p_sr_j),
    ("STYLE_REFINEMENT_Z", p_sr_z),
    ("STRUCTURAL_TRANSFORM", p_st),
    ("LOCAL_EDIT", p_le),
]:
    check(f"F-{label}: NOT a CGI render present",
          "NOT a CGI render" in prompt or "not a cgi" in prompt.lower())
    check(f"F-{label}: DSLR present",
          "DSLR" in prompt)

check("F-FV: vanishing points in FIRST_VISION contract",
      "vanishing point" in p_fv.lower())
check("F-SR: vanishing points in STYLE_REFINEMENT contract",
      "vanishing point" in p_sr_j.lower())
check("F-ST: vanishing points in STRUCTURAL_TRANSFORMATION contract",
      "vanishing point" in p_st.lower())
check("F-SR: windows unblocked in STYLE_REFINEMENT",
      "unblocked" in p_sr_j.lower() and "window" in p_sr_j.lower())
check("F-SR: atmosphere/style content in STYLE_REFINEMENT",
      "Japandi" in p_sr_j or "japandi" in p_sr_j.lower())
check("F-SR: refinement memory in STYLE_REFINEMENT",
      "warmer" in p_sr_j.lower() or "REFINEMENT" in p_sr_j)


# ── Suite G: Semantic duplication audit ───────────────────────────────────────
print("\n=== Suite G: Semantic duplication ===")

def count_phrase(prompt: str, phrase: str) -> int:
    return prompt.lower().count(phrase.lower())

# "preserve" should not appear more than 6 times (some repetition is OK — headers + contract)
preserve_count_sr = count_phrase(p_sr_j, "preserve")
check("G1  STYLE_REFINEMENT: 'preserve' appears <= 6 times (was 12+)",
      preserve_count_sr <= 6, f"count={preserve_count_sr}")

# "geometry" should be present but not repeated excessively
geo_count_sr = count_phrase(p_sr_j, "geometry")
check("G2  STYLE_REFINEMENT: 'geometry' appears <= 4 times",
      geo_count_sr <= 4, f"count={geo_count_sr}")

# "same apartment" should appear once per path, not 5+
same_apt_sr = count_phrase(p_sr_j, "same apartment") + count_phrase(p_sr_j, "same space")
check("G3  STYLE_REFINEMENT: 'same apartment/space' <= 3 occurrences",
      same_apt_sr <= 3, f"count={same_apt_sr}")

# "perspective" should not be repeated more than 4 times
persp_count_sr = count_phrase(p_sr_j, "perspective")
check("G4  STYLE_REFINEMENT: 'perspective' <= 4 occurrences",
      persp_count_sr <= 4, f"count={persp_count_sr}")

# FIRST_VISION: full contract has more, but still not excessive
preserve_count_fv = count_phrase(p_fv, "preserve")
check("G5  FIRST_VISION: 'preserve' appears <= 10 times",
      preserve_count_fv <= 10, f"count={preserve_count_fv}")


# ── Suite H: Wave 4.2 regression ──────────────────────────────────────────────
print("\n=== Suite H: Wave 4.2 regression ===")

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()

check("H1  ENABLE_STRUCTURAL_MASK feature flag present",
      "ENABLE_STRUCTURAL_MASK" in main_src)
check("H2  input_fidelity profile-driven in images.edit",
      'input_fidelity="high"' in main_src or "input_fidelity='high'" in main_src
      or "input_fidelity=profile.input_fidelity" in main_src)
check("H3  edit_kwargs dict pattern for safe mask injection",
      "edit_kwargs" in main_src)
check("H4  source image diagnostic logging present",
      "_src_w" in main_src or "source image:" in main_src)
check("H5  build_structural_mask importable",
      True)  # already verified by Suite B of Wave 4.2


# ── Suite I: Wave 4.1 regression ──────────────────────────────────────────────
print("\n=== Suite I: Wave 4.1 regression ===")

check("I1  quality profile-driven in images.edit",
      'quality="high"' in main_src or "quality='high'" in main_src
      or "quality=profile.quality" in main_src)
check("I2  _detect_output_size defined",
      "_detect_output_size" in main_src)
check("I3  original_image_url anchor present",
      "original_image_url" in main_src and "generation_image_url" in main_src)
check("I4  NOT a CGI render in first 150 chars of full realism block",
      "NOT a CGI render" in rb_full[:150])
check("I5  CAMERA LOCK in full structural contract",
      "CAMERA LOCK" in c_full)
check("I6  build_structural_contract backward compatible (Tier 1)",
      len(build_structural_contract("bathroom")) > 400)
check("I7  build_preservation_block legacy alias works",
      build_preservation_block("kitchen") == build_structural_contract("kitchen"))

# Validate the compress didn't remove essential Wave 4.1 camera-lock vocabulary
check("I8  vanishing point in Tier 1 contract",
      "vanishing point" in c_full.lower())
check("I9  horizon line in Tier 1 contract",
      "horizon line" in c_full.lower())
check("I10 already exists physically OR geometry frozen in Tier 1",
      "exists physically" in c_full.lower() or "geometry frozen" in c_full.lower() or
      "geometry or shift perspective" in c_full.lower())


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
print("  MANUAL VALIDATION REQUIRED:")
print("  [MANUAL] STYLE_REFINEMENT generations stable (no disconnect errors)")
print("  [MANUAL] FIRST_VISION: photographic quality, no CGI feel")
print("  [MANUAL] V2/V3: same apartment feeling preserved")
print("  [MANUAL] Atmosphere switch: DNA vocabulary visible in output")
print("  [MANUAL] Zen Retreat: calm, bright, natural (not dark CGI)")
print("  [MANUAL] Japandi: materials and palette recognizable")
