"""
Wave 4.7.5 validation suite — Localized Authorized Changes / Refinement Authority.

Adds a concise P1.5 AUTHORIZED USER CHANGES section to V2 (Path B) and V3
(Path C) only — explicit local modification authority that overrides
atmosphere/furniture/decor/function defaults while keeping topology fixed
unless the user explicitly requested changing it. Prompt/state only.

Suites:
  A — detection + zone heuristics (Task 5, 17)
  B — clause content: bedroom/flowers/visibility/topology-fixed (Task 2,3,4,8)
  C — V1 gating: never injected on V1 (Task 1,2)
  D — V2/V3 injection + priority + survives trimming (Task 1,6,15)
  E — coherence: no contradiction w/ negative anchors; topology not weakened (Task 8,9)
  F — purity: structure sections stay leak-free (Task 7)
  G — regression: continuity/version/runtime unchanged (Task 7,11,12,13,14)
  H — backward compat + multi-request merge (Task 16,17)
  I — observability (Task 10) + main.py wiring
"""

import os
import sys
import logging

logging.disable(logging.CRITICAL)
sys.path.insert(0, os.path.dirname(__file__))

PASS = "\033[92mPASS\033[0m"
FAIL = "\033[91mFAIL\033[0m"
results = []


def check(label, condition, detail=""):
    status = PASS if condition else FAIL
    suffix = f"  [{detail}]" if detail and not condition else ""
    print(f"  {status}  {label}{suffix}")
    results.append((label, condition))


from prompt_engine.refinement_authority import (
    detect_refinement, build_authorized_changes_clause,
)
logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS, _SECTION_PRIORITY
from prompt_engine.structural_identity import extract_from_description, render_clause, render_negative_anchors
from version_state import build_source_continuity_clause, resolve_source, VersionRecord
from prompt_engine.edit_intent import classify_edit_mode, EditMode
logging.disable(logging.CRITICAL)

M = chr(0xB7)
L = f"Soft Luxury {M} Gold"
DESC = ("Open-plan living room, wide bay window on the rear wall, black glass "
        "partition on the left, diagonal depth, open kitchen on the right.")
ident = extract_from_description(DESC)
NA = render_negative_anchors(ident)

# Phrases verified to route to the intended path:
REQ_V3 = "turn the rear area into a bedroom"            # -> STRUCTURAL_TRANSFORMATION
# Style-dominant (warmer/cosier/more serene) so it routes to STYLE_REFINEMENT,
# yet contains an explicit change verb ("add") so AUTHORIZED fires on Path B.
REQ_V2 = "make it warmer, cosier and more serene, and add a tall plant"  # -> STYLE_REFINEMENT
REQ_FLOWERS = "add roses on the coffee table"           # -> LOCAL_EDIT (build_local_edit_prompt)
REQ_MULTI = "turn the rear area into a bedroom and remove the glass partition"


# ── Suite A: detection + zone heuristics ─────────────────────────────────────
print("\n=== Suite A: detection + zone heuristics ===")

d, z = detect_refinement(REQ_V3)
check("A1  bedroom request detected as change", d is True)
check("A2  rear zone detected", z == "the rear zone")
d, z = detect_refinement(REQ_FLOWERS)
check("A3  flowers request detected as change", d is True)
check("A4  coffee table zone detected", z == "the coffee table area")
d, z = detect_refinement("make it warmer")
check("A5  pure atmosphere -> NOT a change (Task 17)", d is False)
d, z = detect_refinement("")
check("A6  empty -> NOT a change", d is False and z == "")
d, z = detect_refinement("move the TV into the living room")
check("A7  move request detected (zone optional)", d is True)
d, z = detect_refinement("add a lamp behind the glass partition")
check("A8  'behind the partition' zone detected",
      d is True and "behind the partition" in z)
d, z = detect_refinement("enlarge the sofa")
check("A9  enlarge detected", d is True)


# ── Suite B: clause content ──────────────────────────────────────────────────
print("\n=== Suite B: clause content (Task 2,3,4,8) ===")

c_v3 = build_authorized_changes_clause(REQ_V3, 3)
c_v2 = build_authorized_changes_clause(REQ_V2, 2)
c_fl = build_authorized_changes_clause(REQ_FLOWERS, 3)

check("B1  clause starts with AUTHORIZED USER CHANGES",
      c_v3.startswith("AUTHORIZED USER CHANGES"))
check("B2  clause quotes the explicit request (bedroom)",
      "turn the rear area into a bedroom" in c_v3)
check("B3  clause carries the localized zone qualifier",
      "(the rear zone)" in c_v3)
check("B4  clause demands visible / present application (Task 4)",
      "Visibly apply" in c_v3 and "must be clearly present" in c_v3)
check("B5  clause overrides atmosphere/furniture/decor/function defaults (Task 2,3)",
      "overrides atmosphere/furniture/decor/room-function defaults" in c_v3)
check("B6  clause keeps topology fixed unless explicitly changed (Task 3,6)",
      "Keep openings, bay window, facade and perspective fixed" in c_v3
      and "unless the user explicitly changed" in c_v3)
check("B7  flowers clause is concrete decor wording (Task 4)",
      "add roses on the coffee table" in c_fl and "must be clearly present" in c_fl)
check("B8  clause <= 380 chars (Task 8 ceiling)",
      len(c_v3) <= 380 and len(c_v2) <= 380, f"v3={len(c_v3)} v2={len(c_v2)}")
check("B9  clause concise (Task 8 ~300 target band)",
      len(c_v3) <= 340, f"got {len(c_v3)}")
check("B10 V1 (iteration<=1) -> '' (Task 1,2)",
      build_authorized_changes_clause(REQ_V3, 1) == "")
check("B11 pure atmosphere -> '' (Task 17)",
      build_authorized_changes_clause("make it warmer", 2) == "")
check("B12 empty request -> '' (Task 17)",
      build_authorized_changes_clause("", 3) == "")


# ── Suite C: V1 gating ───────────────────────────────────────────────────────
print("\n=== Suite C: V1 gating ===")

p_v1 = compose_generation_prompt(L, "living room", "", REQ_V3, 1, [],
                                 structural_identity=render_clause(ident, "V1"),
                                 structural_negative_anchors=NA,
                                 authorized_user_changes=build_authorized_changes_clause(REQ_V3, 1))
check("C1  V1 has NO AUTHORIZED USER CHANGES section",
      "AUTHORIZED USER CHANGES" not in p_v1)
check("C2  V1 still SAME APARTMENT PHOTO-EDIT + OPENINGS ANCHOR + identity (unchanged)",
      "SAME APARTMENT PHOTO-EDIT" in p_v1 and "OPENINGS ANCHOR" in p_v1
      and "STRUCTURAL IDENTITY" in p_v1)
check("C3  V1 within FIRST_VISION budget (no bloat from this wave)",
      len(p_v1) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_v1)}")


# ── Suite D: V2/V3 injection + priority ──────────────────────────────────────
print("\n=== Suite D: V2/V3 injection ===")

check("D0  routing sanity: REQ_V3 -> STRUCTURAL, REQ_V2 -> STYLE_REFINEMENT",
      classify_edit_mode(REQ_V3, 3) == EditMode.STRUCTURAL_TRANSFORMATION
      and classify_edit_mode(REQ_V2, 2) == EditMode.STYLE_REFINEMENT)

h3 = [{"role": "user", "content": "a"}, {"role": "ai", "content": "b"},
      {"role": "user", "content": REQ_V3}]
p_v3 = compose_generation_prompt(L, "living room", DESC, REQ_V3, 3, h3,
                                 structural_identity=render_clause(ident, "V3"),
                                 source_continuity=build_source_continuity_clause("latest", 3),
                                 structural_negative_anchors=NA,
                                 authorized_user_changes=build_authorized_changes_clause(REQ_V3, 3))
h2 = [{"role": "user", "content": "a"}, {"role": "ai", "content": "b"},
      {"role": "user", "content": REQ_V2}]
p_v2 = compose_generation_prompt(L, "living room", DESC, REQ_V2, 2, h2,
                                 structural_identity=render_clause(ident, "V2"),
                                 source_continuity=build_source_continuity_clause("latest", 2),
                                 structural_negative_anchors=NA,
                                 authorized_user_changes=build_authorized_changes_clause(REQ_V2, 2))
check("D1  V3 (STRUCTURAL) carries AUTHORIZED USER CHANGES (Task 1)",
      "AUTHORIZED USER CHANGES" in p_v3)
check("D2  V2 (STYLE_REFINEMENT) carries AUTHORIZED USER CHANGES (Task 1)",
      "AUTHORIZED USER CHANGES" in p_v2)
check("D3  authorized_user_changes priority = 1 (never trimmed — Task 15)",
      _SECTION_PRIORITY.get("authorized_user_changes") == 1)
check("D4  V3 explicit request text survives in the rendered prompt (Task 15)",
      "turn the rear area into a bedroom" in p_v3)
check("D5  V3 ordered AFTER structural identity/negative anchors (P1.5)",
      p_v3.index("STRUCTURAL NEGATIVE ANCHORS") < p_v3.index("AUTHORIZED USER CHANGES"))
check("D6  V3 ordered BEFORE atmosphere/design intel (local-over-atmosphere)",
      ("ATMOSPHERE (" not in p_v3) or
      (p_v3.index("AUTHORIZED USER CHANGES") < p_v3.index("ATMOSPHERE (")))
check("D7  single AUTHORIZED USER CHANGES section (no duplication)",
      p_v3.count("AUTHORIZED USER CHANGES") == 1 and p_v2.count("AUTHORIZED USER CHANGES") == 1)
check("D8  LOCAL_EDIT path unchanged (no AUTHORIZED section there — handled by build_local_edit_prompt)",
      classify_edit_mode(REQ_FLOWERS, 3) == EditMode.LOCAL_EDIT and
      "AUTHORIZED USER CHANGES" not in
      compose_generation_prompt(L, "living room", DESC, REQ_FLOWERS, 3,
                                [{"role": "user", "content": REQ_FLOWERS}],
                                authorized_user_changes=build_authorized_changes_clause(REQ_FLOWERS, 3)))


# ── Suite E: coherence (no contradiction / no topology weakening) ────────────
print("\n=== Suite E: coherence ===")

check("E1  V3 has BOTH negative anchors AND authorized changes (complementary)",
      "STRUCTURAL NEGATIVE ANCHORS" in p_v3 and "AUTHORIZED USER CHANGES" in p_v3)
check("E2  no contradiction: AUTH keeps topology fixed-unless-explicit; NEG forbids unrequested walls",
      "Keep openings, bay window, facade and perspective fixed" in p_v3
      and "Do not insert walls" in p_v3)
check("E3  V3 still carries STRUCTURAL IDENTITY (Task 14 — identity preserved)",
      "STRUCTURAL IDENTITY" in p_v3)
check("E4  V3 still carries CONTINUE FROM CURRENT DESIGN (4.7.3 continuity intact)",
      "CONTINUE FROM CURRENT DESIGN" in p_v3)
check("E5  topology NOT weakened: V3 still has CAMERA LOCK / openings preservation",
      "CAMERA LOCK" in p_v3 or "GEOMETRY FROZEN" in p_v3 or "STRUCTURAL CONSTRAINTS" in p_v3)
check("E6  V3 under 4000 hard ceiling (P1.5 kept; P4/P5 shed by design — Task 8)",
      len(p_v3) < 4000, f"got {len(p_v3)}")
check("E7  AUTHORIZED section does not itself invent walls/recompose (Task 9)",
      not any(v in build_authorized_changes_clause(REQ_V3, 3).lower()
              for v in ("recompose", "reinterpret the apartment",
                        "redesign the facade", "new apartment")))


# ── Suite F: structure-section purity (Task 7) ───────────────────────────────
print("\n=== Suite F: structure-section purity ===")

si_v3 = render_clause(ident, "V3")
_BANNED = ("sofa", "cozy", "luxury", "decor", "warm", "mood", "premium",
           "velvet", "furniture", "atmosphere", "styling", "aesthetic")
check("F1  structural_identity stays architecture-only (no atmosphere/decor leak)",
      not any(b in si_v3.lower() for b in _BANNED))
check("F2  negative anchors stay architecture-only (unchanged by 4.7.5)",
      not any(b in NA.lower() for b in _BANNED))
check("F3  AUTHORIZED section is its own section (legit override-target words OK, not a structure leak)",
      "AUTHORIZED USER CHANGES" in p_v3 and
      p_v3.index("STRUCTURAL IDENTITY") != p_v3.index("AUTHORIZED USER CHANGES"))


# ── Suite G: regression — continuity / version / runtime ─────────────────────
print("\n=== Suite G: regression ===")

_vr = VersionRecord("v_a", 1, "", "", "", "https://g/v1.jpg", "X", "", False, "")
r = resolve_source(source_mode="", source_version_id="", iteration=4,
                   original_image_url="https://o.jpg", before_image_url="https://b.jpg",
                   versions=[_vr])
check("G1  source resolution unchanged (V4 default -> latest)",
      r.image_url == "https://g/v1.jpg" and r.mode_resolved == "LATEST")
check("G2  V1 source still ORIGINAL (4.7.3 intact)",
      resolve_source(source_mode="", source_version_id="", iteration=1,
                     original_image_url="https://o.jpg", before_image_url="https://b.jpg",
                     versions=[]).source_type == "original")
from generation_profiles import _PROFILES
mvp = _PROFILES["mobile_mvp_baseline"]
check("G3  mobile_mvp_baseline unchanged (quality medium, fidelity None, mask off, attempts 1)",
      mvp.quality == "medium" and mvp.input_fidelity is None
      and mvp.use_mask is False and mvp.max_attempts == 1)
with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
check("G4  runtime knobs intact (fidelity omit / mask gate / max_retries=0)",
      'edit_kwargs.pop("input_fidelity"' in main_src
      and "ENABLE_STRUCTURAL_MASK and profile.use_mask" in main_src
      and "max_retries=0" in main_src)
# Wave 4.7.8 note: bare "requests" collided with the English word in new
# comments ("refinement requests"); tightened to the actual import/network
# tokens. Module remains provider-agnostic (no SDK / no network call).
check("G5  refinement_authority.py provider-agnostic (no model/SDK/network)",
      all(s not in open("prompt_engine/refinement_authority.py", encoding="utf-8").read()
          for s in ("import openai", "from openai", "anthropic", "httpx",
                    "import requests", "requests.get", "requests.post",
                    ".create(")))
check("G6  structural_identity / negative anchors / continuity wiring intact",
      "render_negative_anchors" in main_src and "structural_identity_clause" in main_src
      and "build_source_continuity_clause(" in main_src)


# ── Suite H: backward compat + multi-request ─────────────────────────────────
print("\n=== Suite H: backward compatibility ===")

p_def = compose_generation_prompt(L, "living room", DESC, REQ_V2, 2, h2,
                                  structural_identity=render_clause(ident, "V2"),
                                  source_continuity=build_source_continuity_clause("latest", 2),
                                  structural_negative_anchors=NA)
p_empty = compose_generation_prompt(L, "living room", DESC, REQ_V2, 2, h2,
                                    structural_identity=render_clause(ident, "V2"),
                                    source_continuity=build_source_continuity_clause("latest", 2),
                                    structural_negative_anchors=NA,
                                    authorized_user_changes="")
check("H1  default == explicit '' (byte-identical; zero regression)",
      p_def == p_empty)
check("H2  no AUTHORIZED section when clause '' (filtered)",
      "AUTHORIZED USER CHANGES" not in p_def)
c_multi = build_authorized_changes_clause(REQ_MULTI, 3)
check("H3  multiple requests merge into ONE section quoting the compound ask (Task 16)",
      c_multi.count("AUTHORIZED USER CHANGES") == 1 and "bedroom" in c_multi)
check("H4  composer injects AUTHORIZED only in Path B + Path C (2 sites)",
      open("prompt_engine/composer.py", encoding="utf-8").read().count(
          '("authorized_user_changes", authorized_user_changes)') == 2)
check("H5  Wave 4.7.5 documented in composer + refinement_authority",
      "Wave 4.7.5" in open("prompt_engine/composer.py", encoding="utf-8").read()
      and "Wave 4.7.5" in open("prompt_engine/refinement_authority.py", encoding="utf-8").read())


# ── Suite I: observability + main.py wiring ──────────────────────────────────
print("\n=== Suite I: observability + wiring ===")

check("I1  detect_refinement + build_authorized_changes_clause imported in main.py",
      "from prompt_engine.refinement_authority import" in main_src
      and "build_authorized_changes_clause" in main_src)
# Wave 4.7.8 superseded the 4.7.5 raw-prompt wiring: AUTHORIZED USER CHANGES is
# now built from the ACCUMULATED refinement source (_acc_src), with fallback to
# the raw prompt (zero regression). Assert the current, superseding wiring.
check("I2  authorized_changes_clause computed from accumulated source (4.7.8; raw-prompt fallback)",
      "build_authorized_changes_clause(_acc_src, iteration)" in main_src
      and "_acc_src = _acc.text or prompt" in main_src)
check("I3  passed into composer",
      "authorized_user_changes=authorized_changes_clause" in main_src)
check("I4  [RefinementAuthority] log with all required fields (Task 10)",
      "[RefinementAuthority]" in main_src
      and "requested_change_detected=" in main_src
      and "localized_authority=" in main_src
      and "authorized_change_chars=" in main_src
      and "detected_zone=" in main_src
      and "structural_permission=" in main_src)

logging.disable(logging.NOTSET)

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
  WAVE 4.7.5 — LOCALIZED AUTHORIZED CHANGES:
  P1.5 AUTHORIZED USER CHANGES (V2/V3 only) — explicit local modification
  authority over atmosphere/furniture/decor/function defaults; topology stays
  fixed unless explicitly changed. Never trimmed. No runtime change.
""")
