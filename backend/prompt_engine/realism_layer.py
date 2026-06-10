"""
Luxury realism layer — the invisible quality floor.

Wave 4.2.1: Two tiers.

  build_realism_block()        — Full block (~995 chars). For FIRST_VISION only.
  build_compact_realism_block() — Critical anti-CGI core (~155 chars).
                                  For STYLE_REFINEMENT, STRUCTURAL_TRANSFORMATION,
                                  LOCAL_EDIT. Survives even the tightest prompt budget.

Wave 4.1 rule still applies: critical vocabulary (NOT a CGI render, DSLR,
real estate photography) is in the FIRST ~150 chars of both blocks so it
survives truncation in any path.
"""

_CORE_REALISM = (
    # CRITICAL: first ~150 chars survive even in fully saturated prompts
    "RENDER QUALITY — NOT a CGI render. DSLR interior photograph. "
    "Luxury real estate / Airbnb photography quality. NOT a 3D visualization. NOT concept art. "
    # Additional detail (reaches model when budget allows — FIRST_VISION path)
    "Output must be indistinguishable from a real photograph of the transformed apartment. "
    "Natural light physics: accurate shadow fall-off, ambient fill from windows, "
    "soft reflected light. Material depth: visible wood grain, stone veining, textile weave, "
    "metal sheen at correct specular angle. Furniture at architecturally correct human scale. "
    "Subtle real-world imperfections — NOT artificially perfect or synthetically clean. "
    "Post-production quality comparable to Architectural Digest or Wallpaper* magazine — "
    "soft vignette, balanced exposure, slight colour warmth."
)

_AVOID_AI_ARTIFACTS = (
    "AVOID: Merged surfaces or impossible geometry. "
    "Plastic-looking or uniformly shiny materials. "
    "Harsh overhead lighting with no shadow variation. "
    "Furniture ignoring gravity. Oversaturated or posterised colours. "
    "Sterile over-processed render feeling. Generic catalogue-render furniture."
)

# Compact core — anti-CGI vocabulary + Wave 4.7.9 functional realism.
# Wave 4.7.9 (Functional Layout Intelligence): the redundant tail
# ("natural light physics, no plastic surfaces, no render feeling" — already
# implied by "NOT a CGI render" / "Real materials") was replaced by a tiny
# NEGATIVE-framed functional-usability clause. LENGTH-NEUTRAL (132 vs 133 chars
# → zero V1 budget impact even at Soft Luxury's 6-char headroom). Mandatory
# tokens "NOT a CGI render" and "DSLR" remain within the first 130 chars.
# Deliberately NOT composition authority (no "arrange/grouping/symmetry/face"):
# usability is asserted as a constraint, consistent with photo-edit philosophy
# ("openings ... clear" also reinforces openings preservation — no contradiction).
_COMPACT_REALISM = (
    "NOT a CGI render. DSLR real estate photo. Real materials. "
    "Furniture stays usable; openings and circulation clear; not camera-staged."
)


_MEDIUM_REALISM = (
    "RENDER QUALITY — NOT a CGI render. DSLR interior photograph. "
    "Luxury real estate photography quality. "
    "Natural light physics: accurate shadow fall-off, ambient fill from windows. "
    "Material depth: visible wood grain, stone veining, textile weave. "
    "Furniture at human scale. Subtle real-world imperfections — not artificially perfect."
)


def build_realism_block() -> str:
    """Full luxury realism constraint block. Use for FIRST_VISION only."""
    return f"{_CORE_REALISM} {_AVOID_AI_ARTIFACTS}"


def build_medium_realism_block() -> str:
    """
    Medium realism block (~310 chars). Default for FIRST_VISION in Wave 4.2.4.
    Preserves all critical terms (DSLR, NOT a CGI render, real estate photography,
    natural light physics, material texture, correct scale, imperfections).
    Removes repetitive cinematic prose from the full block.
    """
    return _MEDIUM_REALISM


def build_compact_realism_block() -> str:
    """
    Minimal anti-CGI core (~130 chars).
    Use for STYLE_REFINEMENT, STRUCTURAL_TRANSFORMATION, LOCAL_EDIT.
    Preserves all critical terms within the first 130 chars so it
    survives truncation in saturated refinement prompts.
    """
    return _COMPACT_REALISM


# ── Wave 5.14A — Editorial Realism (additive layer) ───────────────────────────
#
# Standalone editorial-realism layer that sits ALONGSIDE _COMPACT_REALISM, not
# inside it. Wave 4.7.9's _COMPACT_REALISM is contractually length-neutral
# (≤133 / <200 chars per validate_wave479 assertions 2a / 10d) so the
# editorial-realism upgrade is delivered as a separate block, leaving
# _COMPACT_REALISM byte-identical.
#
# Wording is REUSED verbatim from:
#   • _MEDIUM_REALISM (Wave 4.2.4) — material depth + imperfections + light
#     physics phrases. Module-level constant defined above; never reached
#     production because every active composer path calls
#     `build_compact_realism_block()` only.
#   • _AVOID_AI_ARTIFACTS (Wave 4.2.1) — anti-plastic / anti-sterile /
#     anti-catalogue-render avoidance list. Bound to `build_realism_block()`
#     which is itself unused by production (only `validate_wave4*.py`
#     scripts call it).
#
# By emitting these existing strings via a new function we revive the
# dormant editorial vocabulary without inventing new wording — exactly the
# Wave 5.14A audit conclusion (Section G: "the cause is dormant vocabulary,
# not missing concepts").
#
# Composer wiring places this block at P3 priority (same tier as
# compact_realism) immediately after compact_realism in every active path.
# Under tight budget the priority system drops both together — no path can
# end up with editorial_realism but no compact_realism.
_EDITORIAL_REALISM = (
    "EDITORIAL REALISM — Material depth: visible wood grain, stone veining, "
    "textile weave. Subtle real-world imperfections — not artificially perfect. "
    "Natural light physics: accurate shadow fall-off, ambient fill from "
    "windows. AVOID: plastic-looking or uniformly shiny materials, harsh "
    "overhead lighting with no shadow variation, sterile over-processed render "
    "feeling, generic catalogue-render furniture."
)


def build_editorial_realism_block() -> str:
    """
    Wave 5.14A — additive editorial-realism layer (~440 chars).

    Sits alongside `build_compact_realism_block()` in every active composer
    path. Strengthens anti-CGI / anti-catalogue / anti-sterile vocabulary by
    reusing wording that already existed in the codebase but was bound to
    `build_medium_realism_block()` / `build_realism_block()` — both of which
    are imported but never called by any production composer path (only by
    `validate_wave4*.py` historical scripts).

    Returns a fixed ~440-char string. Production cost: pure prompt growth
    (no latency, no token billing — gpt-image-1 prompt sizing is dominated
    by image generation, not text). P3 priority in `_SECTION_PRIORITY` —
    drops alongside compact_realism under tight LOCAL_EDIT budget.
    """
    return _EDITORIAL_REALISM


# ── Wave 5.14B — Photographic Credibility (additive layer) ────────────────────
#
# Compact photographic-realism cues complementing the Wave 5.14A Editorial
# Realism block (which focuses on material depth + light physics + anti-CGI
# avoid list). Wave 5.14B targets the orthogonal photographic axes that
# Editorial does not address:
#   • Specular response (matte vs polished surfaces) — anti-CGI uniform shine
#   • Shadow gradient quality (beyond fall-off — gradient subtlety)
#   • Scene sharpness uniformity (real-estate convention, anti-bokeh)
#
# Deliberately omitted to keep preservation risk LOW :
#   • Lens specs (focal length / aperture) — could conflict with CAMERA LOCK
#   • Exposure controls (no clipped highlights) — could neutralize daylit atmos
#   • AVOID lists — Wave 5.14A learning : bloat without proportional benefit
#   • Atmosphere-specific photo signatures — deferred to Wave 5.14C
#   • Lived-in cues (books, dust, clutter) — per task constraint
#
# Wired same as Editorial : gated by `editorial_realism_enabled` flag. V1 FV
# direct emits both ; REBOOT_FRESH delegation passes False so neither fires
# on the low+OMIT path (or current Wave 5.22c medium+high test). When Wave
# 5.22c validates, the REBOOT_FRESH flag flip will enable both layers there.
_PHOTOGRAPHIC_CREDIBILITY = (
    "PHOTOGRAPHIC CREDIBILITY — Natural specular variation across materials: "
    "matte stays matte, polished shows subtle directional reflection. Subtle "
    "shadow gradients. Uniform scene sharpness — no artificial depth-of-field "
    "bokeh."
)


def build_photographic_credibility_block() -> str:
    """
    Wave 5.14B — additive photographic-credibility layer (~220 chars).

    Targets photographic axes orthogonal to Wave 5.14A Editorial Realism
    (specular response, shadow gradients, scene sharpness uniformity).
    Same gating as Editorial via `editorial_realism_enabled` flag — V1 FV
    direct emits, REBOOT_FRESH currently does not (flag=False).

    Returns a fixed ~220-char string. Latency/cost impact negligible.
    P3 priority — drops with compact_realism + editorial_realism under
    tight budget.
    """
    return _PHOTOGRAPHIC_CREDIBILITY


# Minimum interior completeness — ensures no output feels sparse or under-furnished.
# Injected alongside realism on all generation modes. ~220 chars.
_INTERIOR_COMPLETENESS = (
    "INTERIOR COMPLETENESS: The space must feel fully designed and emotionally inhabited — "
    "never sparse, empty, under-furnished, or minimally staged. "
    "Every major functional zone should feel intentionally completed with layered furniture, "
    "lighting, decor, textile richness, and hospitality-grade styling."
)


def build_interior_completeness_rule() -> str:
    """
    Minimum interior completeness rule (~220 chars). Wave 4.2.5.
    Ensures generated spaces feel fully inhabited — never sparse or empty.
    Injected as a P3 section alongside realism on all modes.
    """
    return _INTERIOR_COMPLETENESS
