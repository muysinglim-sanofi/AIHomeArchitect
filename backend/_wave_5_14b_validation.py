"""Wave 5.14B — Photographic Credibility validation.

Confirms the new additive layer is wired correctly :
  • _PHOTOGRAPHIC_CREDIBILITY constant exists with expected cues
  • build_photographic_credibility_block() returns ~220 chars
  • Wired in composer.py Path D (FIRST_VISION) only, gated on
    editorial_realism_enabled flag (same scope as Wave 5.14A Editorial)
  • V1 FV direct emits both Editorial + Photographic Credibility
  • REBOOT_FRESH delegation emits neither (current Wave 5.14A Fix scope)
  • _COMPACT_REALISM still byte-identical (Wave 4.7.9 contract preserved)
  • No preservation-risk wording (no movement / no architecture directives)
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
    build_photographic_credibility_block,
    _COMPACT_REALISM,
    _EDITORIAL_REALISM,
    _PHOTOGRAPHIC_CREDIBILITY,
)


# ── A. Photographic block content ─────────────────────────────────────────
print("\n=== A. photographic credibility block content ===")
PC = build_photographic_credibility_block()
check("A1  build_photographic_credibility_block returns non-empty str",
      isinstance(PC, str) and len(PC) > 0)
check("A2  block carries 'PHOTOGRAPHIC CREDIBILITY' header",
      "PHOTOGRAPHIC CREDIBILITY" in PC)
check("A3  block carries specular response cue (matte / polished)",
      "matte stays matte" in PC and "polished" in PC
      and "directional reflection" in PC)
check("A4  block carries shadow gradient cue",
      "shadow gradients" in PC.lower())
check("A5  block carries scene sharpness uniformity cue",
      "Uniform scene sharpness" in PC
      and "depth-of-field bokeh" in PC.lower())
check("A6  block size in 150-250 chars target",
      150 <= len(PC) <= 260, f"len={len(PC)}")


# ── B. NO preservation-risk wording ───────────────────────────────────────
print("\n=== B. no preservation-risk wording ===")
_RISK_TOKENS_ARCHITECTURE = [
    "wall", "window", "door", "ceiling", "floor",
    "open the", "close the", "add a", "remove the",
]
_RISK_TOKENS_MOVEMENT = [
    "rearrange", "relocate", "reposition", "move ", "shift",
]
_RISK_TOKENS_FURNISHING = [
    "sofa", "chair", "table", "lamp", "rug", "curtain",
]
_RISK_TOKENS_LIVED_IN = [
    "book", "magazine", "dust", "wrinkle", "clutter",
    "asymmetry", "messy", "lived-in",
]
for label, tokens in [
    ("B1  no architecture directives", _RISK_TOKENS_ARCHITECTURE),
    ("B2  no movement directives", _RISK_TOKENS_MOVEMENT),
    ("B3  no furniture directives", _RISK_TOKENS_FURNISHING),
    ("B4  no lived-in cues", _RISK_TOKENS_LIVED_IN),
]:
    hits = [t for t in tokens if t in PC.lower()]
    check(label, not hits, f"hits={hits}")
check("B5  no lens specs (focal length / aperture / f-stop)",
      not any(x in PC.lower() for x in (
          "mm", "f/", "aperture", "focal length", "fisheye",
      )))
check("B6  no exposure controls (clipped highlights / crushed shadows)",
      not any(x in PC.lower() for x in (
          "clipped", "crushed", "blown out", "underexposed",
      )))
check("B7  no AVOID list (Wave 5.14A learning : avoid lists bloat)",
      "AVOID" not in PC)


# ── C. composer.py wiring — Path D only, gated ───────────────────────────
print("\n=== C. composer.py — Path D sole wiring, gated ===")
with open("prompt_engine/composer.py", encoding="utf-8") as f:
    comp_src = f.read()
check("C1  composer.py imports build_photographic_credibility_block",
      "build_photographic_credibility_block" in comp_src)
check("C2  composer.py registers 'photographic_credibility' in _SECTION_PRIORITY",
      "'photographic_credibility': 3" in comp_src
      or '"photographic_credibility": 3' in comp_src)
gated_emission = comp_src.count(
    "build_photographic_credibility_block() if editorial_realism_enabled else \"\""
)
check("C3  composer.py contains exactly 1 gated emission (Path D, FV)",
      gated_emission == 1, f"found={gated_emission}")
check("C4  composer.py NO unconditional photographic emission",
      "('photographic_credibility', build_photographic_credibility_block())"
      not in comp_src
      and "(\"photographic_credibility\", build_photographic_credibility_block())"
      not in comp_src)


# ── D. End-to-end — V1 FV emits, REBOOT_FRESH does not ──────────────────
print("\n=== D. end-to-end — V1 FV emits, REBOOT_FRESH does not ===")
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

# V1 direct (editorial_realism_enabled=True)
p_v1 = compose_generation_prompt(
    f"Warm Modern {MID} Vision 1", "living room", DESC, "", 1, [],
    structural_identity=SI,
    structural_negative_anchors=NA,
    edit_mode=EditMode.FIRST_VISION,
)
check("D1  V1 FV direct contains 'PHOTOGRAPHIC CREDIBILITY'",
      "PHOTOGRAPHIC CREDIBILITY" in p_v1)
check("D2  V1 FV ALSO contains 'EDITORIAL REALISM' (5.14A still active)",
      "EDITORIAL REALISM" in p_v1)
check("D3  V1 FV contains specular cue",
      "matte stays matte" in p_v1)
check("D4  V1 FV within FIRST_VISION hard ceiling (<4000)",
      len(p_v1) < 4000, f"len={len(p_v1)}")

# REBOOT_FRESH delegation (composer_v2 passes editorial_realism_enabled=False)
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
check("D5  REBOOT_FRESH does NOT contain 'PHOTOGRAPHIC CREDIBILITY'",
      "PHOTOGRAPHIC CREDIBILITY" not in p_v2_switch)
check("D6  REBOOT_FRESH does NOT contain 'EDITORIAL REALISM' (consistent)",
      "EDITORIAL REALISM" not in p_v2_switch)
check("D7  REBOOT_FRESH still contains _COMPACT_REALISM signature",
      "not camera-staged" in p_v2_switch)


# ── E. Wave 4.7.9 / 5.14A contracts preserved ────────────────────────────
print("\n=== E. Wave 4.7.9 + 5.14A contracts preserved ===")
CR = build_compact_realism_block()
ER = build_editorial_realism_block()
check("E1  _COMPACT_REALISM length <= 133 (Wave 4.7.9 2a)",
      len(CR) <= 133, f"len={len(CR)}")
check("E2  _COMPACT_REALISM contains 'NOT a CGI render' + 'DSLR' in first 130",
      "NOT a CGI render" in CR[:130] and "DSLR" in CR[:130])
check("E3  _EDITORIAL_REALISM unchanged (Wave 5.14A intact)",
      "Material depth: visible wood grain" in ER
      and "Subtle real-world imperfections" in ER
      and "Natural light physics" in ER)


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
