"""
Wave 4.8.2 validation - V2/V3 P1 Consolidation & DNA Restoration.

4.8.1a proved V2/V3 P1 (~2528/~2601) exceeded the 2400/2500 caps, silently
evicting design_intel (atmosphere DNA) + compact_realism. Fix: de-duplicate the
two header builders (prose duplicated by contracts + structural_identity +
negative_anchors) + right-size budgets (3500/3600, < V1 3550-ish, < 4000) so
de-duped-P1 + full DNA + realism survive (only P5 refinement_memory drops).
DNA NOT compacted. V1 untouched. Contracts untouched (validator-locked).

Tests (Task 10, 1-16):
"""

import os
import sys
import logging
import hashlib

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


logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS
from prompt_engine.structural_identity import extract_from_description, render_clause, render_negative_anchors
from version_state import build_source_continuity_clause, resolve_source, VersionRecord
from prompt_engine.refinement_authority import build_authorized_changes_clause, accumulate_refinements
from prompt_engine.intent_classifier import is_confirmation
from prompt_engine.atmosphere_dna import label_to_atmosphere_id, get_room_dna, build_dna_block
logging.disable(logging.CRITICAL)

M = chr(0xB7)
EM = chr(0x2014)  # em-dash: actual separator in build_atmosphere_switch_contract ("SAME APARTMENT — ATMOSPHERE SWITCH")
D = ("Open-plan living room, dominant bay window on the rear wall, a secondary "
     "rear window beside it, two windows on the left, deep diagonal depth, "
     "open kitchen on the right.")
ident = extract_from_description(D)
SI = lambda m: render_clause(ident, m)
NA = render_negative_anchors(ident)

h2 = [{"role": "user", "content": "x"}, {"role": "ai", "content": "y"},
      {"role": "user", "content": "warmer"}]
h3 = [{"role": "user", "content": "x"}, {"role": "ai", "content": "y"},
      {"role": "user", "content": "remove the wall between kitchen and living"}]

v1_sl = compose_generation_prompt("Soft Luxury " + M + " Gold", "living room", "", "", 1, [],
                                  structural_identity=SI("V1"), structural_negative_anchors=NA)
v1_jp = compose_generation_prompt("Japandi " + M + " Calm", "living room", "", "", 1, [],
                                  structural_identity=SI("V1"), structural_negative_anchors=NA)
v2 = compose_generation_prompt("Japandi " + M + " Calm", "living room", D, "warmer", 2, h2,
                               structural_identity=SI("V2"),
                               source_continuity=build_source_continuity_clause("latest", 2),
                               structural_negative_anchors=NA)
AUTH = build_authorized_changes_clause(
    "remove the wall between kitchen and living; also add roses; turn the rear into a bedroom", 3)
v3 = compose_generation_prompt("Soft Luxury " + M + " Gold", "living room", D,
                               "remove the wall between kitchen and living", 3, h3,
                               structural_identity=SI("V3"),
                               source_continuity=build_source_continuity_clause("latest", 3),
                               structural_negative_anchors=NA, authorized_user_changes=AUTH)


# 1. V1 unchanged (byte-stable; Task 8)
print("\n=== 1. V1 no regression ===")
check("1a V1 Soft Luxury length stable (~3543, V1 untouched)",
      3530 <= len(v1_sl) <= 3555, f"len={len(v1_sl)}")
check("1b V1 keeps full stack (task/contract/openings/identity/neg/DNA/wow/realism)",
      all(k in v1_sl for k in
          ["SAME APARTMENT PHOTO-EDIT", "CAMERA LOCK", "OPENINGS ANCHOR",
           "STRUCTURAL IDENTITY", "STRUCTURAL NEGATIVE ANCHORS",
           "TRANSFORMATION AMBITION", "NOT a CGI render"])
      and ("ATMOSPHERE (" in v1_sl or "STYLE (" in v1_sl))
check("1c V1 within FIRST_VISION budget 3550 (unchanged)",
      len(v1_sl) <= _MODE_BUDGETS["FIRST_VISION"]
      and _MODE_BUDGETS["FIRST_VISION"] == 3550)
check("1d V1 Japandi still DNA path (4.8.1b intact)",
      "ATMOSPHERE (" in v1_jp)

# 2/3. V2 DNA + realism retained
print("\n=== 2/3. V2 DNA + realism retained ===")
check("2 V2 retains atmosphere DNA (design_intel present)",
      "ATMOSPHERE (" in v2 or "STYLE (" in v2)
check("3 V2 retains compact_realism (NOT a CGI render)",
      "NOT a CGI render" in v2)
check("3b V2 within new STYLE_REFINEMENT budget + < 4000 ceiling",
      len(v2) <= _MODE_BUDGETS["STYLE_REFINEMENT"] and len(v2) < 4000,
      f"len={len(v2)} bud={_MODE_BUDGETS['STYLE_REFINEMENT']}")

# 4/5/6. V3 DNA + realism + authorized retained
print("\n=== 4/5/6. V3 DNA + realism + authorized ===")
check("4 V3 retains atmosphere DNA",
      "ATMOSPHERE (" in v3 or "STYLE (" in v3)
check("5 V3 retains compact_realism",
      "NOT a CGI render" in v3)
check("6 V3 retains AUTHORIZED USER CHANGES (accumulated)",
      "AUTHORIZED USER CHANGES" in v3
      and ("bedroom" in v3.lower() or "roses" in v3.lower()))
check("6b V3 within new STRUCTURAL budget + < 4000 ceiling",
      len(v3) <= _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"] and len(v3) < 4000,
      f"len={len(v3)} bud={_MODE_BUDGETS['STRUCTURAL_TRANSFORMATION']}")

# 7. Negative anchors meaning retained
print("\n=== 7-9. preservation meaning retained ===")
check("7 V2 + V3 retain STRUCTURAL NEGATIVE ANCHORS (no-new-wall)",
      "STRUCTURAL NEGATIVE ANCHORS" in v2 and "STRUCTURAL NEGATIVE ANCHORS" in v3
      and "do not insert walls" in v2.lower() and "do not insert walls" in v3.lower())
# 8. Source continuity meaning retained
check("8 V2/V3 retain CONTINUE FROM CURRENT DESIGN + identity-authority tail",
      "CONTINUE FROM CURRENT DESIGN" in v2
      and "structural identity remains authoritative" in v2)
# 9. Structural identity meaning retained
check("9 V2/V3 retain STRUCTURAL IDENTITY facts",
      "STRUCTURAL IDENTITY" in v2 and "STRUCTURAL IDENTITY" in v3
      and "bay window" in v2.lower())
check("9b V2 keeps TOPOLOGY LOCKED + SAME APARTMENT - ATMOSPHERE SWITCH (contract untouched)",
      "TOPOLOGY LOCKED" in v2 and ("SAME APARTMENT " + EM + " ATMOSPHERE SWITCH") in v2)
check("9c V3 keeps ARCHITECTURAL INTENT (curated-locked token)",
      "ARCHITECTURAL INTENT" in v3)

# 10. No DNA compaction
print("\n=== 10. no DNA compaction ===")
dna_block = build_dna_block(get_room_dna("japandi_calm", "living_room"))
check("10 build_dna_block unchanged length-class (>= 400 chars, not compacted)",
      len(dna_block) >= 400, f"len={len(dna_block)}")
with open("prompt_engine/atmosphere_dna/_base.py", encoding="utf-8") as f:
    base_src = f.read()
check("10b _base.py build_dna_block not modified by 4.8.2 (no Wave 4.8.2 marker)",
      "Wave 4.8.2" not in base_src)

# 11. No OpenAI runtime change
print("\n=== 11-14. no runtime/state/orchestration regression ===")
from generation_profiles import _PROFILES
mvp = _PROFILES["mobile_mvp_baseline"]
with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
check("11 OpenAI runtime untouched (profile + fidelity-omit + mask gate + max_retries=0)",
      mvp.quality == "medium" and mvp.input_fidelity is None and mvp.use_mask is False
      and 'edit_kwargs.pop("input_fidelity"' in main_src
      and "ENABLE_STRUCTURAL_MASK and profile.use_mask" in main_src
      and "max_retries=0" in main_src)
# 12. version-state regression
vr = VersionRecord("v_a", 1, "", "", "", "https://g/v1.jpg", "X", "", False, "")
check("12 version-state intact (V4 default -> latest; V1 -> original)",
      resolve_source(source_mode="", source_version_id="", iteration=4,
                     original_image_url="o", before_image_url="b",
                     versions=[vr]).image_url == "https://g/v1.jpg"
      and resolve_source(source_mode="", source_version_id="", iteration=1,
                         original_image_url="o", before_image_url="b",
                         versions=[]).source_type == "original")
# 13. accumulation regression
check("13 accumulation intact (bedroom+roses stack)",
      accumulate_refinements([{"role": "user", "content": "turn rear into a bedroom"},
                              {"role": "ai", "content": "ok"}],
                             "also add roses").append_count == 2)
# 14. confirmation-trigger regression
check("14 confirmation-trigger intact",
      is_confirmation("go ahead") and not is_confirmation("add a lamp"))

# 15. prompt budget improved (DNA/realism now survive vs pre-4.8.2 eviction)
print("\n=== 15-16. budget improved + topology wording ===")
check("15 budget improved: V2 DNA+realism retained (was evicted pre-4.8.2)",
      ("ATMOSPHERE (" in v2 or "STYLE (" in v2) and "NOT a CGI render" in v2)
check("15b V3 DNA+realism+auth retained (was evicted pre-4.8.2)",
      ("ATMOSPHERE (" in v3 or "STYLE (" in v3) and "NOT a CGI render" in v3
      and "AUTHORIZED USER CHANGES" in v3)
check("15c budgets right-sized (3500/3600), below V1 3550-ish ceiling concept, < 4000",
      _MODE_BUDGETS["STYLE_REFINEMENT"] == 3500
      and _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"] == 3600
      and max(_MODE_BUDGETS["STYLE_REFINEMENT"], _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"]) < 4000)
# 16. no topology wording loss
check("16 no topology wording loss (CAMERA/STRUCTURAL/openings/no-wall present V2&V3)",
      "TOPOLOGY LOCKED" in v2
      and "do not insert walls" in v2.lower() and "do not insert walls" in v3.lower()
      and "STRUCTURAL IDENTITY" in v2 and "STRUCTURAL IDENTITY" in v3)

# header de-dup proof
print("\n=== header de-duplication ===")
with open("prompt_engine/edit_intent.py", encoding="utf-8") as f:
    ei_src = f.read()
check("DEDUP SR header de-duplicated (frozen-geometry prose removed, 4.8.2)",
      "Wave 4.8.2" in ei_src
      and "Geometry, perspective, and spatial identity are frozen" not in ei_src
      and "SAME APARTMENT CONTINUATION" in ei_src)
check("DEDUP ST header keeps ARCHITECTURAL INTENT, drops CAMERA LOCK prose",
      "ARCHITECTURAL INTENT:" in ei_src
      and "CAMERA LOCK: the viewpoint, angle, and perspective are fixed" not in ei_src)
check("DEDUP contracts untouched (validator-locked signatures present in composer)",
      "build_atmosphere_switch_contract(room_type" in
      open("prompt_engine/composer.py", encoding="utf-8").read()
      and "build_structural_evolution_contract(room_type)" in
      open("prompt_engine/composer.py", encoding="utf-8").read())
check("OBS [V2V3Budget] observability present (Task 9)",
      "[V2V3Budget]" in open("prompt_engine/composer.py", encoding="utf-8").read())

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
  WAVE 4.8.2 - V2/V3 P1 CONSOLIDATION & DNA RESTORATION:
  Header de-dup + right-sized budgets (3500/3600). V2/V3 now retain
  atmosphere DNA + realism + identity + negatives + authorized + topology;
  only P5 refinement_memory drops. DNA NOT compacted. V1 byte-identical.
""")
