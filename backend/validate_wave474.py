"""
Wave 4.7.4 validation suite — Structural Negative Anchors / No-New-Wall Rule.

Adds a concise P1 STRUCTURAL NEGATIVE ANCHORS section (V1/V2/V3) derived ONLY
from the persistent identity: "open glass/openings are NOT walls; do not insert
walls, compartmentalize the open facade, or close glass continuity; the applied
visual treatment must not restructure the facade for wall symmetry".

Prompt-only. No runtime/OpenAI change. Architecture-only, leak-guarded, compact.

Suites:
  A — section generation, leak protection, no-anchor gating, compactness
  B — injected into V1/V2/V3; absent when no identity
  C — no contradiction / no redundancy with positive anchors
  D — main.py wiring + observability
  E — no OpenAI runtime regression; no source-resolution regression
  F — backward compatibility (default "" -> byte-identical) + prior waves intact
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


from prompt_engine.structural_identity import (
    extract_from_description, render_clause, render_negative_anchors,
    EMPTY_IDENTITY, _BANNED_SUBSTR,
)
logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS, _SECTION_PRIORITY
from version_state import build_source_continuity_clause
logging.disable(logging.CRITICAL)

M = chr(0xB7)
L = f"Soft Luxury {M} Gold"
DESC = ("Open-plan living room, wide bay window on the rear wall, black glass "
        "partition on the left, diagonal depth, open kitchen on the right.")
ident = extract_from_description(DESC)
NA = render_negative_anchors(ident)
BANNED_FURN_ATM = ("sofa", "armchair", "couch", "cushion", "rug", "lamp",
                   "plant", "velvet", "marble", "decor", "furnish", "furniture",
                   "cozy", "cosy", "luxury", "premium", "warm", "mood",
                   "atmosphere", "styling", "aesthetic", "elegant", "opulent",
                   "hospitality", "wow")


# ── Suite A: section generation / leak / gating / compactness ────────────────
print("\n=== Suite A: negative-anchor generation ===")

check("A1  render_negative_anchors returns a non-empty section for an identity",
      isinstance(NA, str) and NA.startswith("STRUCTURAL NEGATIVE ANCHORS"))
check("A2  declares openings/glass are NOT walls",
      "open space, NOT walls" in NA or "not walls" in NA.lower())
check("A3  forbids inserting walls between openings",
      "do not insert walls" in NA.lower())
check("A4  forbids compartmentalizing the open facade",
      "compartmentalize the open facade" in NA.lower())
check("A5  forbids closing glass continuity",
      "close glass continuity" in NA.lower())
check("A6  Task 4 — visual treatment must not restructure the facade",
      "must not restructure the facade" in NA.lower())
check("A7  Task 7 — NO furniture/atmosphere/decor leakage",
      not any(b in NA.lower() for b in BANNED_FURN_ATM))
check("A8  Task 7 — NO _BANNED_SUBSTR vocab at all",
      not any(b in NA.lower() for b in _BANNED_SUBSTR))
check("A9  Task 5 — section <= 450 chars (no bloat)",
      len(NA) <= 450, f"got {len(NA)}")
check("A10 Task 5 — concise single section (one 'STRUCTURAL NEGATIVE ANCHORS')",
      NA.count("STRUCTURAL NEGATIVE ANCHORS") == 1)
check("A11 Task 6 — empty identity -> '' (no section, zero cost)",
      render_negative_anchors(EMPTY_IDENTITY) == ""
      and render_negative_anchors(extract_from_description("a plain room")) == "")
check("A12 architecture-only — no per-opening enumeration (no 'bay window' echo)",
      "bay window" not in NA.lower())  # structural_identity owns enumeration


# ── Suite B: injected into V1/V2/V3; absent without identity ─────────────────
print("\n=== Suite B: V1/V2/V3 injection ===")

si = {m: render_clause(ident, m) for m in ("V1", "V2", "V3")}
h = [{"role": "user", "content": "a"}, {"role": "ai", "content": "b"},
     {"role": "user", "content": "warmer"}]
h3 = [{"role": "user", "content": "a"}, {"role": "ai", "content": "b"},
      {"role": "user", "content": "remove the wall between the kitchen and the living room"}]

p_v1 = compose_generation_prompt(L, "living room", "", "", 1, [],
                                 structural_identity=si["V1"],
                                 structural_negative_anchors=NA)
p_v2 = compose_generation_prompt(L, "living room", DESC, "warmer", 2, h,
                                 structural_identity=si["V2"],
                                 source_continuity=build_source_continuity_clause("latest", 2),
                                 structural_negative_anchors=NA)
p_v3 = compose_generation_prompt(L, "living room", DESC,
                                 "remove the wall between the kitchen and the living room",
                                 2, h3, structural_identity=si["V3"],
                                 source_continuity=build_source_continuity_clause("latest", 2),
                                 structural_negative_anchors=NA)

check("B1  V1 carries STRUCTURAL NEGATIVE ANCHORS (Task 1)",
      "STRUCTURAL NEGATIVE ANCHORS" in p_v1)
check("B2  V2 carries STRUCTURAL NEGATIVE ANCHORS (Task 1)",
      "STRUCTURAL NEGATIVE ANCHORS" in p_v2)
check("B3  V3 carries STRUCTURAL NEGATIVE ANCHORS (Task 1)",
      "STRUCTURAL NEGATIVE ANCHORS" in p_v3)
check("B4  structural_negative_anchors is P1",
      _SECTION_PRIORITY.get("structural_negative_anchors") == 1)
check("B5  V1 within FIRST_VISION budget WITH identity + negatives + DNA",
      len(p_v1) <= _MODE_BUDGETS["FIRST_VISION"], f"got {len(p_v1)}")
check("B6  V1 retains DNA block + realism + identity (no V1 regression)",
      ("ATMOSPHERE (" in p_v1 or "STYLE (" in p_v1)
      and "CGI render" in p_v1 and "STRUCTURAL IDENTITY" in p_v1)
check("B7  V3 within STRUCTURAL_TRANSFORMATION budget",
      len(p_v3) <= _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"], f"got {len(p_v3)}")
check("B8  V2 under 4000 hard ceiling (P1 kept; P4/P5 shed by design)",
      len(p_v2) < 4000, f"got {len(p_v2)}")
check("B9  V1 with NO identity -> NO negative section (Task 6)",
      "STRUCTURAL NEGATIVE ANCHORS" not in
      compose_generation_prompt(L, "living room", "", "", 1, []))
check("B10 V2 with NO identity/negatives -> NO negative section",
      "STRUCTURAL NEGATIVE ANCHORS" not in
      compose_generation_prompt(L, "living room", DESC, "warmer", 2, h))


# ── Suite C: no contradiction / no redundancy with positive anchors ─────────
print("\n=== Suite C: coherence with positive anchors ===")

check("C1  negatives reinforce, not contradict (no add/create/remove verbs)",
      not any(v in NA.lower() for v in
              ("add a wall", "create a wall", "remove the opening",
               "delete the", "generate a wall")))
check("C2  positive identity still enumerates openings; negatives stay generic",
      "bay window" in si["V1"].lower() and "bay window" not in NA.lower())
check("C3  V1 has BOTH positive identity AND negative anchors (complementary)",
      "STRUCTURAL IDENTITY" in p_v1 and "STRUCTURAL NEGATIVE ANCHORS" in p_v1)
check("C4  V1 still SAME APARTMENT PHOTO-EDIT + OPENINGS ANCHOR (positive intact)",
      "SAME APARTMENT PHOTO-EDIT" in p_v1 and "OPENINGS ANCHOR" in p_v1)
check("C5  no duplicate 'STRUCTURAL NEGATIVE ANCHORS' in any rendered prompt",
      p_v1.count("STRUCTURAL NEGATIVE ANCHORS") == 1
      and p_v2.count("STRUCTURAL NEGATIVE ANCHORS") == 1
      and p_v3.count("STRUCTURAL NEGATIVE ANCHORS") == 1)
check("C6  V3 structural request not blocked (negatives forbid INVENTING walls only)",
      "ARCHITECTURAL INTENT" in p_v3 and "do not insert walls" in p_v3.lower())
check("C7  V2 still carries CONTINUE FROM CURRENT DESIGN (4.7.3 intact)",
      "CONTINUE FROM CURRENT DESIGN" in p_v2)
check("C8  V2/V3 still carry STRUCTURAL IDENTITY (4.7.2 intact)",
      "STRUCTURAL IDENTITY" in p_v2 and "STRUCTURAL IDENTITY" in p_v3)


# ── Suite D: main.py wiring + observability ──────────────────────────────────
print("\n=== Suite D: main.py wiring ===")

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()
check("D1  render_negative_anchors imported in main.py",
      "render_negative_anchors" in main_src)
check("D2  negative_anchors_clause computed from the persistent identity",
      "negative_anchors_clause = render_negative_anchors(structural_id_obj)" in main_src)
check("D3  passed into composer",
      "structural_negative_anchors=negative_anchors_clause" in main_src)
check("D4  observability: negative_anchors_chars logged",
      "negative_anchors_chars=" in main_src)
check("D5  composer exposes structural_negative_anchors param",
      'structural_negative_anchors: str = ""' in
      open("prompt_engine/composer.py", encoding="utf-8").read())
check("D6  Wave 4.7.4 documented in composer + structural_identity",
      "Wave 4.7.4" in open("prompt_engine/composer.py", encoding="utf-8").read()
      and "Wave 4.7.4" in open("prompt_engine/structural_identity.py", encoding="utf-8").read())


# ── Suite E: no OpenAI runtime / source-resolution regression ───────────────
print("\n=== Suite E: no runtime / source regression ===")

from generation_profiles import _PROFILES
mvp = _PROFILES["mobile_mvp_baseline"]
check("E1  mobile_mvp_baseline unchanged (quality=medium, fidelity None, mask off, attempts 1)",
      mvp.quality == "medium" and mvp.input_fidelity is None
      and mvp.use_mask is False and mvp.max_attempts == 1)
check("E2  main.py runtime knobs intact (fidelity omit / mask gate / max_retries=0)",
      'edit_kwargs.pop("input_fidelity"' in main_src
      and "ENABLE_STRUCTURAL_MASK and profile.use_mask" in main_src
      and "max_retries=0" in main_src)
check("E3  structural_identity.py still provider-agnostic (no model/SDK/network)",
      all(s not in open("prompt_engine/structural_identity.py", encoding="utf-8").read()
          for s in ("import openai", "from openai", "anthropic", "httpx",
                    "requests", ".create(")))
from version_state import resolve_source, VersionRecord
_vr = VersionRecord("v_a", 1, "", "", "", "https://g/v1.jpg", "X", "", False, "")
r = resolve_source(source_mode="", source_version_id="", iteration=3,
                   original_image_url="https://o.jpg", before_image_url="https://b.jpg",
                   versions=[_vr])
check("E4  source resolution unaffected (V3 default -> latest generated)",
      r.image_url == "https://g/v1.jpg" and r.mode_resolved == "LATEST")
check("E5  V1 source still ORIGINAL (4.7.3 intact)",
      resolve_source(source_mode="", source_version_id="", iteration=1,
                     original_image_url="https://o.jpg", before_image_url="https://b.jpg",
                     versions=[]).source_type == "original")


# ── Suite F: backward compatibility + prior-wave integrity ──────────────────
print("\n=== Suite F: backward compatibility ===")

p_default = compose_generation_prompt(L, "living room", DESC, "warmer", 2, h)
p_empty = compose_generation_prompt(L, "living room", DESC, "warmer", 2, h,
                                    structural_negative_anchors="")
check("F1  default == explicit '' (zero regression, byte-identical)",
      p_default == p_empty)
check("F2  no negative section when clause '' (filtered out)",
      "STRUCTURAL NEGATIVE ANCHORS" not in p_default)
check("F3  V1 baseline (no extras) still SAME APARTMENT PHOTO-EDIT + OPENINGS ANCHOR",
      "SAME APARTMENT PHOTO-EDIT" in compose_generation_prompt(L, "living room", "", "", 1, [])
      and "OPENINGS ANCHOR" in compose_generation_prompt(L, "living room", "", "", 1, []))
check("F4  V2 baseline still TOPOLOGY LOCKED + SOURCE SPACE (4.3/legacy intact)",
      "TOPOLOGY LOCKED" in p_default and "SOURCE SPACE" in p_default)
check("F5  structural_negative_anchors injected only in V1/V2/V3 paths (3 sites)",
      open("prompt_engine/composer.py", encoding="utf-8").read().count(
          '("structural_negative_anchors", structural_negative_anchors)') == 3)
check("F6  LOCAL_EDIT path untouched (no negative section there)",
      "STRUCTURAL NEGATIVE ANCHORS" not in
      compose_generation_prompt(L, "living room", DESC, "make the rug blue", 2,
                                [{"role": "user", "content": "make the rug blue"}],
                                structural_negative_anchors=NA))

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
  WAVE 4.7.4 — STRUCTURAL NEGATIVE ANCHORS:
  Concise P1 'open glass/openings are NOT walls' topology rule in V1/V2/V3.
  Architecture-only, leak-guarded, <=450 chars, "" without identity.
  V1 retains DNA+realism+identity within budget. No runtime change.
""")
