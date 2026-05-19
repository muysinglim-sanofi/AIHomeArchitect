"""
Wave 4.7.2 validation suite — Persistent Structural Identity.

GOAL: V1 receives CONCRETE architectural identity even under mobile_mvp_baseline
(vision_analysis_fv=False), captured ONCE and reused across V1/V2/V3, with no
runtime-heavy / provider-locked machinery and no generation-authority leak.

Suites:
  A — Task 1: ApartmentStructuralIdentity object (architecture-only, frozen)
  B — Task 2: capture-once gating + session persistence (token round-trip)
  C — Task 3: V1 injects concrete identity even with vision_analysis_fv=False
  D — Task 4: V2 / V3 reuse the SAME identity (V3 conditional-change suffix)
  E — Task 5: no prompt bloat (concise, capped)
  F — Task 6: no generation-authority leak (atmosphere/decor/furniture banned)
  G — Task 7: observability logs present
  H — Provider portability: structural_identity.py has no model/SDK imports
  I — Regression: absent identity -> byte-identical prompts; priorities intact
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


from prompt_engine.structural_identity import (
    ApartmentStructuralIdentity, EMPTY_IDENTITY,
    extract_from_description, to_token, from_token, render_clause,
)

logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS, _SECTION_PRIORITY
logging.disable(logging.CRITICAL)

BAY = ("Open-plan living room, wide bay window dominating the rear wall, "
       "black glass partition on the left, deep diagonal perspective, "
       "open kitchen visible on the right.")


# ── Suite A: Task 1 — identity object ────────────────────────────────────────
print("\n=== Suite A: Task 1 — ApartmentStructuralIdentity object ===")

import dataclasses
flds = {f.name for f in dataclasses.fields(ApartmentStructuralIdentity)}
check("A1  frozen dataclass",
      ApartmentStructuralIdentity.__dataclass_params__.frozen)
check("A2  architecture-only fields present",
      flds == {"dominant_opening", "opening_layout", "glass_partition",
               "room_depth_type", "kitchen_visibility", "anchor_relationships"})
check("A3  no atmosphere/decor/style fields",
      not any(k in flds for k in
              ("atmosphere", "decor", "furniture", "style", "mood", "lighting")))
check("A4  EMPTY_IDENTITY.is_present is False",
      EMPTY_IDENTITY.is_present is False)
ident = extract_from_description(BAY)
check("A5  extract_from_description finds a present identity for a structural desc",
      ident.is_present)
check("A6  dominant_opening captured (bay window)",
      "bay window" in ident.dominant_opening.lower())
check("A7  glass_partition captured",
      "glass" in ident.glass_partition.lower() and ident.glass_partition != "")
check("A8  room_depth_type captured (diagonal/open-plan)",
      any(t in ident.room_depth_type.lower() for t in ("diagonal", "open-plan")))
check("A9  kitchen_visibility captured",
      "kitchen" in ident.kitchen_visibility.lower())
check("A10 fact_count > 2 for a rich description",
      ident.fact_count > 2, f"got {ident.fact_count}")
check("A11 empty/blank description -> EMPTY_IDENTITY",
      extract_from_description("").is_present is False and
      extract_from_description("   ").is_present is False)
check("A12 generic non-architectural text -> EMPTY_IDENTITY",
      extract_from_description("A nice room with a comfy feeling.").is_present is False)


# ── Suite B: Task 2 — capture-once gating + persistence ──────────────────────
print("\n=== Suite B: Task 2 — capture-once gating + token persistence ===")

tok = to_token(ident)
check("B1  to_token produces a non-empty token for a present identity",
      isinstance(tok, str) and len(tok) > 0)
check("B2  to_token(EMPTY) is '' (no token when absent)",
      to_token(EMPTY_IDENTITY) == "")
round_trip = from_token(tok)
check("B3  token round-trip preserves identity",
      round_trip.dominant_opening == ident.dominant_opening and
      round_trip.glass_partition == ident.glass_partition and
      round_trip.is_present)
check("B4  from_token tolerant of garbage -> EMPTY_IDENTITY",
      from_token("not json {{{").is_present is False and
      from_token("").is_present is False and
      from_token('{"unknown":"x"}').is_present is False)

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()

check("B5  /generate has structural_identity form param (client round-trip)",
      'structural_identity: str = Form("")' in main_src)
check("B6  client-persisted token is reused (from_token on provided token)",
      "from_token(structural_identity)" in main_src)
check("B7  capture call is gated to V1 only (elif iteration == 1)",
      "elif iteration == 1:" in main_src and "_capture_structural_text(image_bytes)" in main_src)
# The model capture must be unreachable on V2+: it lives strictly under the
# `elif iteration == 1` branch and never in the V2+ fallback `else` (which sets
# _si_source="text_fallback"). Verify: exactly one capture call, after the V1
# elif, before the V2+ fallback marker, and absent from the fallback branch.
_cap_pos = main_src.find("_capture_structural_text(image_bytes)")
_elif_pos = main_src.find("elif iteration == 1:")
_tf_pos = main_src.find('"text_fallback"')  # only in the V2+ else branch
check("B8  capture call is V1-gated, single, before the V2+ fallback branch",
      0 < _elif_pos < _cap_pos < _tf_pos
      and main_src.count("_capture_structural_text(image_bytes)") == 1,
      f"elif={_elif_pos} cap={_cap_pos} text_fallback={_tf_pos}")
check("B9  V2+ fallback is deterministic text parse only (no capture call in it)",
      "extract_from_description(room_description)" in main_src and
      "_capture_structural_text" not in main_src[_tf_pos - 220:_tf_pos + 220])
check("B10 response payload returns structural_identity token (persist forever)",
      '"structural_identity": structural_identity_token' in main_src)
check("B11 capture helper uses detail='low' + architecture-only prompt (lightweight)",
      '"detail": "low"' in main_src and "Architecture only" in main_src)
check("B12 capture helper is non-fatal (returns '' on failure)",
      "structural capture failed (non-fatal)" in main_src)


# ── Suite C: Task 3 — V1 concrete identity under vision_analysis_fv=False ─────
print("\n=== Suite C: Task 3 — V1 concrete identity (baseline-safe) ===")

# Simulate the mobile_mvp_baseline V1 reality: room_description="" (vision off),
# but a persisted/parsed identity clause is supplied -> V1 MUST carry it.
clause_v1 = render_clause(ident, "V1")
p_v1 = compose_generation_prompt(
    "Soft Luxury · Gold", "living room", "", "", 1, [],
    structural_identity=clause_v1,
)
check("C1  V1 prompt contains the STRUCTURAL IDENTITY section",
      "STRUCTURAL IDENTITY" in p_v1)
check("C2  V1 identity is declarative ('this apartment already contains')",
      "this apartment already contains" in p_v1)
check("C3  V1 identity names the concrete dominant opening (bay window)",
      "bay window" in p_v1.lower())
check("C4  V1 identity is NOT a generation instruction (no generate/redesign verbs)",
      not any(v in clause_v1.lower() for v in
              ("generate ", "redesign", "reimagine", "compose ", "add a ")))
check("C5  V1 still has OPENINGS ANCHOR + CAMERA LOCK (4.6.x/4.7.1 intact)",
      "OPENINGS ANCHOR" in p_v1 and "CAMERA LOCK" in p_v1)
check("C6  V1 still SAME APARTMENT PHOTO-EDIT (4.6.1 intact)",
      "SAME APARTMENT PHOTO-EDIT" in p_v1)
check("C7  works even though room_description='' (identity, not vision-derived)",
      "STRUCTURAL IDENTITY" in p_v1)
check("C8  structural_identity is P1 in _SECTION_PRIORITY",
      _SECTION_PRIORITY.get("structural_identity") == 1)
check("C9  V1 within FIRST_VISION budget with identity present",
      len(p_v1) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_v1)}")


# ── Suite D: Task 4 — V2 / V3 reuse same identity ────────────────────────────
print("\n=== Suite D: Task 4 — V2 / V3 reuse SAME identity ===")

hist = [{"role": "user", "content": "x"}, {"role": "ai", "content": "y"},
        {"role": "user", "content": "warmer"}]
clause_v2 = render_clause(ident, "V2")
p_v2 = compose_generation_prompt(
    "Soft Luxury · Gold", "living room", BAY, "warmer", 2, hist,
    structural_identity=clause_v2,
)
hist3 = [{"role": "user", "content": "x"}, {"role": "ai", "content": "y"},
         {"role": "user", "content": "remove the wall between kitchen and living"}]
clause_v3 = render_clause(ident, "V3")
p_v3 = compose_generation_prompt(
    "Soft Luxury · Gold", "living room", BAY,
    "remove the wall between kitchen and living", 2, hist3,
    structural_identity=clause_v3,
)
check("D1  V2 prompt carries the STRUCTURAL IDENTITY section",
      "STRUCTURAL IDENTITY" in p_v2)
check("D2  V3 prompt carries the STRUCTURAL IDENTITY section",
      "STRUCTURAL IDENTITY" in p_v3)
check("D3  V1 and V2 identity body is IDENTICAL (same persistent facts)",
      clause_v1 == clause_v2)
check("D4  V3 adds the conditional-change suffix (only explicit edit may alter)",
      "Only the explicitly requested structural change may alter them" in clause_v3)
check("D5  V1/V2 do NOT contain the V3 conditional-change suffix",
      "Only the explicitly requested structural change may alter them" not in clause_v1)
check("D6  same dominant opening fact across V1/V2/V3",
      "bay window" in clause_v1.lower() and "bay window" in clause_v2.lower()
      and "bay window" in clause_v3.lower())
check("D7  V3 still routes structural + carries ARCHITECTURAL INTENT",
      "ARCHITECTURAL INTENT" in p_v3)
check("D8  V2 within budget; V3 within budget",
      len(p_v2) <= _MODE_BUDGETS["STYLE_REFINEMENT"] and
      len(p_v3) <= _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"])


# ── Suite E: Task 5 — no prompt bloat ────────────────────────────────────────
print("\n=== Suite E: Task 5 — concise, capped ===")

full = ApartmentStructuralIdentity(
    dominant_opening="wide full-height bay window dominating the entire rear wall span",
    opening_layout="a secondary window pair on the left side wall",
    glass_partition="black-framed glass partition as a fixed structural divider",
    room_depth_type="deep diagonal perspective defining the spatial volume",
    kitchen_visibility="open kitchen visible on the right",
    anchor_relationships="the primary opening and the glass divider hold fixed relative positions",
)
rc = render_clause(full, "V3")
check("E1  render_clause <= 360 chars even with all 6 facts (no bloat)",
      len(rc) <= 360, f"got {len(rc)}")
check("E2  per-fact cap enforced (<= 90 chars each)",
      all(len(getattr(extract_from_description(BAY), f.name)) <= 90
          for f in dataclasses.fields(ApartmentStructuralIdentity)))
check("E3  empty identity renders to '' (zero prompt cost)",
      render_clause(EMPTY_IDENTITY, "V1") == "")
check("E4  dominant_opening never dropped under trim (highest priority kept)",
      "bay window" in render_clause(full, "V1").lower())


# ── Suite F: Task 6 — no generation-authority leak ───────────────────────────
print("\n=== Suite F: Task 6 — no generation-authority leak ===")

leaky = ("Cozy luxury living room with a warm velvet sofa, marble decor, "
         "premium atmosphere, a bay window on the rear wall and a glass partition.")
li = extract_from_description(leaky)
joined = " ".join([li.dominant_opening, li.opening_layout, li.glass_partition,
                    li.room_depth_type, li.kitchen_visibility,
                    li.anchor_relationships]).lower()
check("F1  banned vocab never enters identity (no sofa/velvet/luxury/atmosphere)",
      not any(b in joined for b in
              ("sofa", "velvet", "luxury", "premium", "decor", "cozy", "atmosphere", "warm")))
check("F2  legitimate architectural fact still captured (bay window)",
      "bay window" in li.dominant_opening.lower())
# NOTE: the fixed template legitimately says "do not normalize, narrow, or
# restyle them" — "restyle" there is an anti-generation PROHIBITION, not a leak.
# The leak guard applies to extracted FACT values, so assert content/atmosphere
# nouns (and creation verbs the template never uses) are absent from the clause.
check("F3  rendered clause carries no content/atmosphere leak vocab in its facts",
      not any(b in render_clause(li, "V1").lower() for b in
              ("sofa", "velvet", "luxury", "premium", "decor", "atmosphere",
               "cozy", "cosy", "redesign", "generate", "furnish")))
check("F4  from_token re-sanitises on the way in (defence in depth)",
      from_token('{"dominant_opening":"luxury velvet sofa wall"}').is_present is False)
check("F5  identity clause asserts existence, not creation",
      "already contains" in render_clause(ident, "V1") and
      "do not normalize" in render_clause(ident, "V1"))


# ── Suite G: Task 7 — observability ──────────────────────────────────────────
print("\n=== Suite G: Task 7 — observability ===")

check("G1  [StructuralIdentity] log present in main.py",
      "[StructuralIdentity]" in main_src)
check("G2  logs structural_identity_present",
      "structural_identity_present=" in main_src or "present=%s" in main_src)
check("G3  logs structural_identity_source",
      "source=%s" in main_src and "_si_source" in main_src)
check("G4  logs structural_identity_chars",
      "structural_identity_chars=" in main_src)
check("G5  logs generation_mode (V1/V2/V3)",
      "generation_mode=%s" in main_src and "_gen_mode" in main_src)


# ── Suite H: provider portability ────────────────────────────────────────────
print("\n=== Suite H: provider portability ===")

with open("prompt_engine/structural_identity.py", encoding="utf-8") as f:
    si_src = f.read()
check("H1  structural_identity.py imports NO openai",
      "import openai" not in si_src and "from openai" not in si_src)
check("H2  structural_identity.py imports NO other provider SDK",
      "anthropic" not in si_src.lower() and "google.gener" not in si_src)
check("H3  structural_identity.py makes NO network/model call",
      ".create(" not in si_src and "requests." not in si_src and "httpx" not in si_src)
check("H4  module is pure (dataclass + deterministic parse + render + json)",
      "import json" in si_src and "dataclass" in si_src and "def render_clause" in si_src)
check("H5  composer change is provider-agnostic (plain str param)",
      "structural_identity: str = \"\"" in open("prompt_engine/composer.py", encoding="utf-8").read())


# ── Suite I: regression ──────────────────────────────────────────────────────
print("\n=== Suite I: regression — absent identity = no change ===")

# Without an identity (default ""), prompts must be byte-identical to pre-4.7.2.
p_v1_none = compose_generation_prompt("Soft Luxury · Gold", "living room", "", "", 1, [])
p_v1_none_explicit = compose_generation_prompt(
    "Soft Luxury · Gold", "living room", "", "", 1, [], structural_identity="")
check("I1  default structural_identity='' -> no STRUCTURAL IDENTITY section",
      "STRUCTURAL IDENTITY" not in p_v1_none)
check("I2  explicit '' == default (byte-identical, zero regression)",
      p_v1_none == p_v1_none_explicit)
check("I3  V1 without identity still SAME APARTMENT PHOTO-EDIT + OPENINGS ANCHOR",
      "SAME APARTMENT PHOTO-EDIT" in p_v1_none and "OPENINGS ANCHOR" in p_v1_none)
check("I4  openings_anchor still P1 (4.6.2 intact)",
      _SECTION_PRIORITY.get("openings_anchor") == 1)
check("I5  architectural_anchors still P1 (4.7.1 intact)",
      _SECTION_PRIORITY.get("architectural_anchors") == 1)
check("I6  Wave 4.7.2 documented in composer",
      "Wave 4.7.2" in open("prompt_engine/composer.py", encoding="utf-8").read())
check("I7  extract_from_description deterministic (same input -> same output)",
      to_token(extract_from_description(BAY)) == to_token(extract_from_description(BAY)))
p_v2_none = compose_generation_prompt("Soft Luxury · Gold", "living room", BAY, "warmer", 2, hist)
check("I8  V2 without identity unchanged (TOPOLOGY LOCKED + SOURCE SPACE)",
      "TOPOLOGY LOCKED" in p_v2_none and "SOURCE SPACE" in p_v2_none)

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
  WAVE 4.7.2 — PERSISTENT STRUCTURAL IDENTITY:

  Capture-once (V1 only, gated) -> token persisted client-side -> reused
  deterministically in V1/V2/V3. Concrete architectural facts replace generic
  preservation wording, even under mobile_mvp_baseline (vision_analysis_fv=False).
  Provider-agnostic core (no SDK imports). Task-6 leak guard active.
  Absent identity -> byte-identical prompts (zero regression).
""")
