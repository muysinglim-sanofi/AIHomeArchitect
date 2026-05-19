"""
Wave 4.7.5b validation suite — Secondary Topology Reinforcement.

Micro change ONLY: the structural-identity `opening_layout` wording was changed
from bare position ("a secondary window pair on the left") to shared-open-facade
CONTINUITY ("secondary opening, same open facade"). Length-neutral (~±1 char),
zero new section, zero composer/priority/main.py change, zero V1 budget impact
even at Soft Luxury's 6-char headroom.

Tests (the 12 required):
  1  secondary topology wording injected correctly
  2  no new large P1 block
  3  prompt budget remains safe (Soft Luxury V1 not saturated)
  4  no atmosphere leakage
  5  no furniture leakage
  6  no contradiction with negative anchors
  7  no contradiction with structural identity
  8  no V1 section-ordering regression
  9  no V2/V3 regression
  10 no runtime regression
  11 no source-resolution regression
  12 no trimming regression
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


from prompt_engine.structural_identity import extract_from_description, render_clause, render_negative_anchors
logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS, _SECTION_PRIORITY
from version_state import resolve_source, VersionRecord, build_source_continuity_clause
from prompt_engine.refinement_authority import build_authorized_changes_clause
logging.disable(logging.CRITICAL)

MID = chr(0xB7)
D_PAIR = ("Open-plan living room, dominant bay window on the rear wall, a "
          "secondary rear window beside it, two windows on the left, deep "
          "diagonal depth, open kitchen on the right.")
D_SIDE = "living room with a large bay window and additional windows on the right side"
ATM = ["Japandi " + MID + " Calm", "Warm Modern " + MID + " Oat", "Soft Luxury " + MID + " Gold"]

ident = extract_from_description(D_PAIR)
clause = render_clause(ident, "V1")
NA = render_negative_anchors(ident)
_BANNED_ATM = ("luxury", "premium", "warm ", "cozy", "cosy", "atmosphere", "mood",
               "elegant", "opulent", "serene", "hygge", "minimalist")
_BANNED_FURN = ("sofa", "armchair", "couch", "cushion", "rug", "lamp", "plant",
                "velvet", "marble", "decor", "furniture", "table", "bed")


# 1 — secondary topology wording injected correctly
print("\n=== 1. Secondary topology wording ===")
check("1a opening_layout is shared-open-facade continuity (not bare position)",
      ident.opening_layout == "secondary opening, same open facade")
check("1b single-side variant also continuity-worded",
      extract_from_description(D_SIDE).opening_layout == "more windows on the same open facade")
check("1c old positional wording removed",
      "window pair on the left" not in clause and "on the left" not in clause)
check("1d 'same open facade' present in identity clause (Task 2/3)",
      "same open facade" in clause)
v1 = compose_generation_prompt(ATM[0], "living room", "", "", 1, [],
                               structural_identity=clause, structural_negative_anchors=NA)
check("1e continuity wording reaches the rendered V1 prompt",
      "same open facade" in v1)


# 2 — no new large P1 block
print("\n=== 2. No new P1 block ===")
with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()
check("2a no new section key added to _SECTION_PRIORITY",
      "secondary_topology" not in comp_src and "rear_opening" not in comp_src
      and "topology_reinforcement" not in comp_src)
check("2b composer not modified by 4.7.5b (no new raw_sections entry)",
      comp_src.count("structural_identity") >= 1
      and "Wave 4.7.5b" not in comp_src)  # change is wording-only in structural_identity.py
check("2c identity clause still a single STRUCTURAL IDENTITY block",
      clause.count("STRUCTURAL IDENTITY") == 1)


# 3 — prompt budget remains safe (Task 7)
print("\n=== 3. Budget safety ===")
budgets = {}
for L in ATM:
    p = compose_generation_prompt(L, "living room", "", "", 1, [],
                                  structural_identity=clause, structural_negative_anchors=NA)
    budgets[L] = len(p)
    allp = all(k in p for k in ["STRUCTURAL IDENTITY", "STRUCTURAL NEGATIVE ANCHORS",
                                "TRANSFORMATION AMBITION", "CGI render"])
    check(f"3-{L[:11]} V1 within 3550 + all critical sections present",
          len(p) <= _MODE_BUDGETS["FIRST_VISION"] and allp,
          f"len={len(p)}")
# Wave 4.7.9 note: the compact realism rewrite is length-neutral and actually
# -1 char, so Soft Luxury V1 headroom improved 6 -> 7 (never worse). Assert the
# invariant intent: zero saturation, headroom >= 6 (4.7.5b baseline floor).
check("3-soft-luxury headroom >= 6 (zero saturation; 4.7.9 length-neutral, +1)",
      _MODE_BUDGETS["FIRST_VISION"] - budgets["Soft Luxury " + MID + " Gold"] >= 6,
      f"headroom={_MODE_BUDGETS['FIRST_VISION'] - budgets['Soft Luxury ' + MID + ' Gold']}")
check("3-identity clause length-neutral (<= 360 render cap; ~342)",
      len(clause) <= 360 and 330 <= len(clause) <= 350, f"got {len(clause)}")


# 4/5 — no atmosphere / furniture leakage
print("\n=== 4/5. Purity ===")
low = clause.lower()
check("4 no atmosphere vocab in identity clause",
      not any(b in low for b in _BANNED_ATM))
check("5 no furniture vocab in identity clause / opening_layout",
      not any(b in low for b in _BANNED_FURN)
      and not any(b in ident.opening_layout.lower() for b in _BANNED_FURN))


# 6 — no contradiction with negative anchors
print("\n=== 6. No contradiction w/ negative anchors ===")
check("6a NEG anchors unchanged (architecture-only, open-space-not-walls)",
      "open space, NOT walls" in NA and "compartmentalize the open facade" in NA)
check("6b continuity ('same open facade') reinforces NEG (no contradiction)",
      "same open facade" in clause and "facade" in NA
      and "do not insert walls" in NA.lower())


# 7 — no contradiction with structural identity
print("\n=== 7. Identity self-consistency ===")
check("7a still declarative facts, not generation instructions",
      "this apartment already contains" in clause
      and not any(v in low for v in ("generate", "redesign", "add a ", "create a")))
check("7b dominant opening still present alongside secondary",
      "bay window" in low and "same open facade" in low)


# 8 — no V1 section-ordering regression
print("\n=== 8. V1 ordering ===")
order_ok = (v1.index("STRUCTURAL IDENTITY") < v1.index("STRUCTURAL NEGATIVE ANCHORS")
            and v1.index("OPENINGS ANCHOR") < v1.index("STRUCTURAL IDENTITY"))
check("8 V1 order: OPENINGS ANCHOR < STRUCTURAL IDENTITY < NEGATIVE ANCHORS (unchanged)",
      order_ok)
check("8b V1 has NO AUTHORIZED USER CHANGES (4.7.5 gating intact)",
      "AUTHORIZED USER CHANGES" not in v1)


# 9 — no V2/V3 regression
print("\n=== 9. V2/V3 ===")
h2 = [{"role": "user", "content": "a"}, {"role": "ai", "content": "b"},
      {"role": "user", "content": "warmer"}]
p_v2 = compose_generation_prompt(ATM[2], "living room", D_PAIR, "warmer", 2, h2,
                                 structural_identity=render_clause(ident, "V2"),
                                 source_continuity=build_source_continuity_clause("latest", 2),
                                 structural_negative_anchors=NA)
h3 = [{"role": "user", "content": "a"}, {"role": "ai", "content": "b"},
      {"role": "user", "content": "turn the rear area into a bedroom"}]
p_v3 = compose_generation_prompt(ATM[2], "living room", D_PAIR,
                                 "turn the rear area into a bedroom", 3, h3,
                                 structural_identity=render_clause(ident, "V3"),
                                 source_continuity=build_source_continuity_clause("latest", 3),
                                 structural_negative_anchors=NA,
                                 authorized_user_changes=build_authorized_changes_clause(
                                     "turn the rear area into a bedroom", 3))
check("9a V2 still has identity + continuity + negative anchors",
      "STRUCTURAL IDENTITY" in p_v2 and "CONTINUE FROM CURRENT DESIGN" in p_v2
      and "STRUCTURAL NEGATIVE ANCHORS" in p_v2)
check("9b V2 carries the strengthened continuity wording",
      "same open facade" in p_v2)
check("9c V3 still has AUTHORIZED USER CHANGES + identity + negatives",
      "AUTHORIZED USER CHANGES" in p_v3 and "STRUCTURAL IDENTITY" in p_v3
      and "STRUCTURAL NEGATIVE ANCHORS" in p_v3)
check("9d V2/V3 within 4000 hard ceiling",
      len(p_v2) < 4000 and len(p_v3) < 4000)


# 10 — no runtime regression
print("\n=== 10. Runtime ===")
from generation_profiles import _PROFILES
mvp = _PROFILES["mobile_mvp_baseline"]
with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
check("10a mobile_mvp_baseline unchanged",
      mvp.quality == "medium" and mvp.input_fidelity is None
      and mvp.use_mask is False and mvp.max_attempts == 1)
check("10b runtime knobs intact (fidelity omit / mask gate / max_retries=0)",
      'edit_kwargs.pop("input_fidelity"' in main_src
      and "ENABLE_STRUCTURAL_MASK and profile.use_mask" in main_src
      and "max_retries=0" in main_src)
check("10c structural_identity.py provider-agnostic (no model/SDK)",
      all(s not in open("prompt_engine/structural_identity.py", encoding="utf-8").read()
          for s in ("import openai", "from openai", "anthropic", "httpx", ".create(")))


# 11 — no source-resolution regression
print("\n=== 11. Source resolution ===")
vr = VersionRecord("v_a", 1, "", "", "", "https://g/v1.jpg", "X", "", False, "")
r = resolve_source(source_mode="", source_version_id="", iteration=4,
                   original_image_url="https://o.jpg", before_image_url="https://b.jpg",
                   versions=[vr])
check("11a V4 default -> latest generated (4.7.3 intact)",
      r.image_url == "https://g/v1.jpg" and r.mode_resolved == "LATEST")
check("11b V1 -> ORIGINAL (4.7.3 intact)",
      resolve_source(source_mode="", source_version_id="", iteration=1,
                     original_image_url="https://o.jpg", before_image_url="https://b.jpg",
                     versions=[]).source_type == "original")


# 12 — no trimming regression
print("\n=== 12. Trimming ===")
check("12a identity clause <= render cap (360); facts not trimmed away",
      len(clause) <= 360 and "bay window" in clause and "same open facade" in clause)
check("12b extract_from_description deterministic (same in -> same out)",
      render_clause(extract_from_description(D_PAIR), "V1")
      == render_clause(extract_from_description(D_PAIR), "V1"))
check("12c no-secondary-opening desc -> no layout fact (graceful, unchanged)",
      extract_from_description("a room with one bay window").opening_layout == "")
check("12d Wave 4.7.5b documented in structural_identity.py",
      "Wave 4.7.5b" in open("prompt_engine/structural_identity.py", encoding="utf-8").read())

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
  WAVE 4.7.5b — SECONDARY TOPOLOGY REINFORCEMENT:
  opening_layout: "a secondary window pair on the left" ->
                  "secondary opening, same open facade" (length-neutral).
  Binds the secondary opening to the same continuous open facade.
  Zero new section, zero budget impact, zero V1 saturation.
""")
