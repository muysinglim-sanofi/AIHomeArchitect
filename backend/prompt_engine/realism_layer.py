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
