"""
Wave 4.7.3 validation suite — Architectural State Continuity & Version Source.

Covers the 10 required validation areas + manual scenarios A/B/C, plus
backward-compat and "no OpenAI runtime regression" guards.

Suites:
  A — Source resolution rules (areas 1-6 + scenarios A/B/C)
  B — Version metadata model + persistence (Task 2)
  C — Prompt: source-continuity wording + structural identity (areas 7,10, Task 5)
  D — main.py wiring + observability (Tasks 1,3,7)
  E — No OpenAI runtime regression (area 9)
  F — Backward compatibility + regression (area 6, Task 6)
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


from version_state import (
    VersionRecord, ResolvedSource, ORIGINAL, LATEST, SPECIFIC_VERSION,
    parse_versions, serialize_versions, version_to_dict, resolve_source,
    new_version_id, build_source_continuity_clause,
)

ORIG = "https://cdn/original.jpg"
BEFORE = "https://cdn/before_latest.jpg"


def _v(vid, n, gen):
    return VersionRecord(
        version_id=vid, vision_number=n, source_mode_used="", source_version_id_used="",
        source_image_url_used="", generated_image_url=gen, atmosphere="X",
        user_request="", structural_permission=False, structural_identity_token="",
    )


V1 = _v("v_aaa", 1, "https://cdn/gen_v1.jpg")
V2 = _v("v_bbb", 2, "https://cdn/gen_v2.jpg")
V3 = _v("v_ccc", 3, "https://cdn/gen_v3_bedroom.jpg")


# ── Suite A: source resolution rules ─────────────────────────────────────────
print("\n=== Suite A: source resolution (areas 1-6 + scenarios A/B/C) ===")

# Area 1 — V1 -> original
r = resolve_source(source_mode="", source_version_id="", iteration=1,
                    original_image_url=ORIG, before_image_url=BEFORE, versions=[])
check("A1  V1 (iteration=1) -> ORIGINAL image",
      r.image_url == ORIG and r.mode_resolved == ORIGINAL and r.source_type == "original")

# V1 even if a (stale) source_mode=LATEST is sent — V1 is never latest
r = resolve_source(source_mode="LATEST", source_version_id="", iteration=1,
                    original_image_url=ORIG, before_image_url=BEFORE, versions=[V1])
check("A2  V1 forced ORIGINAL even if source_mode=LATEST (regression #1 guard)",
      r.image_url == ORIG and r.mode_resolved == ORIGINAL)

# Area 2 — V2 default -> latest generated
r = resolve_source(source_mode="", source_version_id="", iteration=2,
                    original_image_url=ORIG, before_image_url=BEFORE, versions=[V1])
check("A3  V2 default (no source_mode) -> LATEST generated (v1 gen)",
      r.image_url == V1.generated_image_url and r.mode_resolved == LATEST)

# Area 3 — V3 default -> latest generated
r = resolve_source(source_mode="", source_version_id="", iteration=3,
                    original_image_url=ORIG, before_image_url=BEFORE, versions=[V1, V2])
check("A4  V3 default -> LATEST generated (v2 gen)",
      r.image_url == V2.generated_image_url and r.mode_resolved == LATEST)

# Area 4 — SPECIFIC_VERSION
r = resolve_source(source_mode="SPECIFIC_VERSION", source_version_id="v_aaa",
                    iteration=4, original_image_url=ORIG, before_image_url=BEFORE,
                    versions=[V1, V2, V3])
check("A5  SPECIFIC_VERSION v_aaa -> that version's generated image",
      r.image_url == V1.generated_image_url and r.mode_resolved == SPECIFIC_VERSION
      and r.source_version_id == "v_aaa")

# Area 5 — ORIGINAL restart even with generated versions
r = resolve_source(source_mode="ORIGINAL", source_version_id="", iteration=4,
                    original_image_url=ORIG, before_image_url=BEFORE,
                    versions=[V1, V2, V3])
check("A6  ORIGINAL restart -> original photo even if versions exist",
      r.image_url == ORIG and r.mode_resolved == ORIGINAL and r.source_type == "original")

# Area 6 — missing/legacy + no generated -> fallback original
r = resolve_source(source_mode="", source_version_id="", iteration=2,
                    original_image_url=ORIG, before_image_url="", versions=[])
check("A7  iteration>1, no versions, no before -> fallback ORIGINAL (no crash)",
      r.image_url == ORIG and r.mode_resolved == ORIGINAL)
# legacy: before_image_url present but no versions ledger -> LATEST = before
r = resolve_source(source_mode="", source_version_id="", iteration=2,
                    original_image_url=ORIG, before_image_url=BEFORE, versions=[])
check("A8  legacy V2 (no versions ledger) -> LATEST = before_image_url",
      r.image_url == BEFORE and r.mode_resolved == LATEST)

# Unknown source_mode -> treated as missing (no crash)
r = resolve_source(source_mode="garbage_mode", source_version_id="", iteration=2,
                    original_image_url=ORIG, before_image_url=BEFORE, versions=[V1])
check("A9  unknown source_mode -> treated as missing -> LATEST",
      r.image_url == V1.generated_image_url and r.mode_resolved == LATEST)

# Unknown SPECIFIC_VERSION id -> graceful fall-through to LATEST
r = resolve_source(source_mode="SPECIFIC_VERSION", source_version_id="v_zzz",
                    iteration=3, original_image_url=ORIG, before_image_url=BEFORE,
                    versions=[V1, V2])
check("A10 SPECIFIC_VERSION unknown id -> graceful LATEST fallback (no crash)",
      r.image_url == V2.generated_image_url and r.mode_resolved == LATEST)

# Scenario A — V4 with no source continues from V3 (bedroom), not V1/original
r = resolve_source(source_mode="", source_version_id="", iteration=4,
                    original_image_url=ORIG, before_image_url=BEFORE,
                    versions=[V1, V2, V3])
check("A11 Scenario A: V4 default -> continues from V3 (bedroom), not original/V1",
      r.image_url == V3.generated_image_url and r.image_url != ORIG
      and r.image_url != V1.generated_image_url)

# Scenario B — explicit ORIGINAL restart
r = resolve_source(source_mode="ORIGINAL", source_version_id="", iteration=4,
                    original_image_url=ORIG, before_image_url=BEFORE,
                    versions=[V1, V2, V3])
check("A12 Scenario B: 'restart from original' -> original, not V3 bedroom",
      r.image_url == ORIG)

# Scenario C — explicitly continue from V1
r = resolve_source(source_mode="SPECIFIC_VERSION", source_version_id="v_aaa",
                    iteration=4, original_image_url=ORIG, before_image_url=BEFORE,
                    versions=[V1, V2, V3])
check("A13 Scenario C: 'continue from Vision 1' -> V1 image, not latest V3",
      r.image_url == V1.generated_image_url
      and r.image_url != V3.generated_image_url)


# ── Suite B: version metadata model + persistence ────────────────────────────
print("\n=== Suite B: version metadata model + persistence (Task 2) ===")

vid = new_version_id()
check("B1  new_version_id stable prefix + opaque", vid.startswith("v_") and len(vid) > 5)
check("B2  VersionRecord carries all required fields",
      set(VersionRecord.__dataclass_fields__) == {
          "version_id", "vision_number", "source_mode_used",
          "source_version_id_used", "source_image_url_used",
          "generated_image_url", "atmosphere", "user_request",
          "structural_permission", "structural_identity_token"})
ser = serialize_versions([V1, V2, V3])
rt = parse_versions(ser)
check("B3  serialize/parse round-trip preserves ledger",
      [x.version_id for x in rt] == ["v_aaa", "v_bbb", "v_ccc"]
      and rt[2].generated_image_url == V3.generated_image_url)
check("B4  parse_versions tolerant of garbage -> []",
      parse_versions("not json") == [] and parse_versions("") == []
      and parse_versions('{"not":"a list"}') == [])
check("B5  serialize_versions([]) == '' (no token when empty)",
      serialize_versions([]) == "")
check("B6  version_to_dict returns a plain dict with version_id",
      isinstance(version_to_dict(V1), dict) and version_to_dict(V1)["version_id"] == "v_aaa")
check("B7  parse drops non-dict entries without crashing",
      parse_versions('[{"version_id":"v_x","vision_number":1},"bad",123]')[0].version_id == "v_x")


# ── Suite C: prompt — continuity wording + structural identity ───────────────
print("\n=== Suite C: prompt continuity + structural identity (areas 7,10) ===")

logging.disable(logging.NOTSET)
from prompt_engine.composer import compose_generation_prompt, _MODE_BUDGETS, _SECTION_PRIORITY
from prompt_engine.structural_identity import extract_from_description, render_clause, to_token, from_token
logging.disable(logging.CRITICAL)

DESC = ("Open-plan living room, wide bay window on the rear wall, black glass "
        "partition on the left, diagonal depth, open kitchen on the right.")
ident = extract_from_description(DESC)
si_clause = render_clause(ident, "V2")
si_clause_v3 = render_clause(ident, "V3")

cont_latest = build_source_continuity_clause("latest", 2)
cont_orig = build_source_continuity_clause("original", 2)
cont_v1 = build_source_continuity_clause("original", 1)

check("C1  continuity clause for V2+ latest = CONTINUE FROM CURRENT DESIGN",
      "CONTINUE FROM CURRENT DESIGN" in cont_latest)
check("C2  continuity clause asserts original identity authoritative",
      "structural identity remains authoritative" in cont_latest
      and "windows, openings, partitions, depth" in cont_latest)
check("C3  ORIGINAL restart clause = RESTART FROM ORIGINAL + identity authority",
      "RESTART FROM ORIGINAL" in cont_orig
      and "structural identity remains authoritative" in cont_orig)
check("C4  V1 gets NO continuity clause (edits the original — zero cost)",
      cont_v1 == "")
check("C5  continuity clause is concise (<= 320 chars, no bloat)",
      len(cont_latest) <= 320 and len(cont_orig) <= 320,
      f"latest={len(cont_latest)} orig={len(cont_orig)}")

hist2 = [{"role": "user", "content": "x"}, {"role": "ai", "content": "y"},
         {"role": "user", "content": "warmer"}]
p_v2 = compose_generation_prompt(
    "Soft Luxury · Gold", "living room", DESC, "warmer", 2, hist2,
    structural_identity=si_clause, source_continuity=cont_latest)
# NOTE: use a phrase that reliably routes to STRUCTURAL_TRANSFORMATION (Path C).
# The V3 classifier gap ("replace the TV area with a bedroom" -> LOCAL_EDIT) is
# the deferred 4.7.1 audit recommendation R3 — out of scope for 4.7.3.
hist3 = [{"role": "user", "content": "x"}, {"role": "ai", "content": "y"},
         {"role": "user", "content": "remove the wall between the kitchen and the living room"}]
p_v3 = compose_generation_prompt(
    "Soft Luxury · Gold", "living room", DESC,
    "remove the wall between the kitchen and the living room", 2, hist3,
    structural_identity=si_clause_v3, source_continuity=cont_latest)
p_v1 = compose_generation_prompt(
    "Soft Luxury · Gold", "living room", "", "", 1, [],
    structural_identity=render_clause(ident, "V1"), source_continuity="")

check("C6  V2 prompt carries CONTINUE FROM CURRENT DESIGN (Task 5)",
      "CONTINUE FROM CURRENT DESIGN" in p_v2)
check("C7  V2 still carries STRUCTURAL IDENTITY (area 7 — identity preserved)",
      "STRUCTURAL IDENTITY" in p_v2 and "bay window" in p_v2.lower())
check("C8  V2 asserts original identity authoritative for architecture",
      "structural identity remains authoritative" in p_v2)
check("C9  V3 carries continuity + STRUCTURAL IDENTITY + ARCHITECTURAL INTENT",
      "CONTINUE FROM CURRENT DESIGN" in p_v3 and "STRUCTURAL IDENTITY" in p_v3
      and "ARCHITECTURAL INTENT" in p_v3)
check("C10 V3 identity allows only the explicit change (4.7.2 suffix intact)",
      "Only the explicitly requested structural change may alter them" in si_clause_v3)
check("C11 V1 prompt has NO source-continuity clause (area 10 — V1 unchanged)",
      "CONTINUE FROM CURRENT DESIGN" not in p_v1 and "RESTART FROM ORIGINAL" not in p_v1)
check("C12 V1 still SAME APARTMENT PHOTO-EDIT + OPENINGS ANCHOR (no recomposition)",
      "SAME APARTMENT PHOTO-EDIT" in p_v1 and "OPENINGS ANCHOR" in p_v1)
check("C13 source_continuity is P1 in _SECTION_PRIORITY",
      _SECTION_PRIORITY.get("source_continuity") == 1)
check("C14 V2 within budget, V3 within budget (no bloat)",
      len(p_v2) <= _MODE_BUDGETS["STYLE_REFINEMENT"]
      and len(p_v3) <= _MODE_BUDGETS["STRUCTURAL_TRANSFORMATION"])


# ── Suite D: main.py wiring + observability ──────────────────────────────────
print("\n=== Suite D: main.py wiring + observability (Tasks 1,3,7) ===")

with open("main.py", encoding="utf-8") as f:
    main_src = f.read()

check("D1  source_mode form param present (Task 1)",
      'source_mode: str = Form("")' in main_src)
check("D2  source_version_id form param present (Task 1)",
      'source_version_id: str = Form("")' in main_src)
check("D3  versions form param present (Task 1)",
      'versions: str = Form("")' in main_src)
check("D4  resolve_source used for generation_image_url (Task 3)",
      "resolve_source(" in main_src and "generation_image_url = _resolved.image_url" in main_src)
check("D5  original_image_url + generation_image_url identifiers preserved (validator compat)",
      "original_image_url" in main_src and "generation_image_url" in main_src)
check("D6  structural_permission derived from edit_mode (Task 2/4)",
      "structural_permission = (edit_mode == EditMode.STRUCTURAL_TRANSFORMATION)" in main_src)
check("D7  build_source_continuity_clause invoked (Task 5)",
      "build_source_continuity_clause(" in main_src)
check("D8  VersionRecord persisted + returned in payload (Task 2)",
      "VersionRecord(" in main_src and '"versions": serialize_versions(' in main_src
      and '"version_record": version_to_dict(' in main_src)
check("D9  [VersionState] observability log present (Task 7)",
      "[VersionState]" in main_src
      and "source_mode_requested=" in main_src
      and "source_mode_resolved=" in main_src
      and "source_image_url_type=" in main_src
      and "latest_version_id=" in main_src
      and "structural_permission=" in main_src
      and "prompt_chars=" in main_src
      and "output_size=" in main_src)
check("D10 structural_identity token still returned (4.7.2 not lost — regression)",
      '"structural_identity": structural_identity_token' in main_src)


# ── Suite E: no OpenAI runtime regression (area 9) ───────────────────────────
print("\n=== Suite E: no OpenAI runtime regression ===")

from generation_profiles import _PROFILES
mvp = _PROFILES["mobile_mvp_baseline"]
check("E1  mobile_mvp_baseline unchanged: quality=medium",
      mvp.quality == "medium")
check("E2  mobile_mvp_baseline unchanged: input_fidelity omitted (None)",
      mvp.input_fidelity is None)
check("E3  mobile_mvp_baseline unchanged: use_mask False, max_attempts 1",
      mvp.use_mask is False and mvp.max_attempts == 1)
check("E4  main.py still omits input_fidelity when None (4.7.0 intact)",
      'edit_kwargs.pop("input_fidelity"' in main_src)
check("E5  main.py mask gate intact (profile.use_mask)",
      "ENABLE_STRUCTURAL_MASK and profile.use_mask" in main_src)
check("E6  max_retries=0 intact (cost protection)",
      "max_retries=0" in main_src)
check("E7  no retries added (max_attempts still profile-driven)",
      "_MAX_ATTEMPTS = profile.max_attempts" in main_src)
check("E8  version_state has NO model/provider/network imports",
      all(s not in open("version_state.py", encoding="utf-8").read()
          for s in ("import openai", "from openai", "anthropic", "httpx",
                    "requests", ".create(")))


# ── Suite F: backward compatibility + regression ─────────────────────────────
print("\n=== Suite F: backward compatibility + regression ===")

# Absent params -> compose unchanged (byte-identical) vs explicit empties.
p_v2_none = compose_generation_prompt("Soft Luxury · Gold", "living room", DESC,
                                       "warmer", 2, hist2)
p_v2_empty = compose_generation_prompt("Soft Luxury · Gold", "living room", DESC,
                                        "warmer", 2, hist2,
                                        structural_identity="", source_continuity="")
check("F1  default params == explicit empty (zero regression, byte-identical)",
      p_v2_none == p_v2_empty)
check("F2  V2 without continuity still TOPOLOGY LOCKED + SOURCE SPACE (unchanged)",
      "TOPOLOGY LOCKED" in p_v2_none and "SOURCE SPACE" in p_v2_none)
check("F3  no source_continuity section when clause '' (filtered)",
      "CONTINUE FROM CURRENT DESIGN" not in p_v2_none)
check("F4  legacy /generate call shape still valid (new params optional)",
      'source_mode: str = Form("")' in main_src
      and 'structural_identity: str = Form("")' in main_src)
check("F5  Wave 4.7.3 documented in composer + version_state",
      "Wave 4.7.3" in open("prompt_engine/composer.py", encoding="utf-8").read()
      and "Wave 4.7.3" in open("version_state.py", encoding="utf-8").read())
check("F6  original_image_url NOT conflated with visual source (kept separate)",
      "original_image_url" in main_src
      and "ARCHITECTURAL TRUTH" in main_src)
check("F7  V1 path (Path D) has no source_continuity injection (V1 unchanged)",
      open("prompt_engine/composer.py", encoding="utf-8").read().count(
          '("source_continuity", source_continuity)') == 2)  # only Path B + Path C

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
  WAVE 4.7.3 — ARCHITECTURAL STATE CONTINUITY & VERSION SOURCE:

  V1 -> original (always). V2+ default -> latest generated (design continuity).
  source_mode ORIGINAL/SPECIFIC_VERSION honoured; legacy clients safe.
  Original photo + structural_identity remain the authoritative architecture.
  Lightweight client-round-trip version ledger. No OpenAI runtime change.
""")
